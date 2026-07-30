#!/usr/bin/env bash
#
# scaffold.sh — Generate the skeleton for the "Table Scraper & Form Filler"
# Chrome extension (Manifest V3, WXT, TypeScript).
#
# This scaffold uses a *real content script* (defineContentScript) that owns
# the DOM work and talks to the background via runtime messaging. That is the
# correction that makes progress events, cancellation, and the injected helper
# functions actually work — see the validation notes for why.
#
# Usage:   ./scaffold.sh [project-name]
# Example: ./scaffold.sh my-extension
#
set -euo pipefail

PROJECT="${1:-my-extension}"

if [ -e "$PROJECT" ]; then
  echo "✗ '$PROJECT' already exists. Choose another name or remove it first." >&2
  exit 1
fi

echo "→ Creating project: $PROJECT"
mkdir -p "$PROJECT"/src/entrypoints/popup
mkdir -p "$PROJECT"/src/utils
mkdir -p "$PROJECT"/public/icon

cd "$PROJECT"

# ─────────────────────────────────────────────────────────────────────────────
# package.json
# ─────────────────────────────────────────────────────────────────────────────
cat > package.json << 'EOF'
{
  "name": "table-scraper-form-filler",
  "description": "Scrape HTML tables to CSV/Excel and batch-fill forms from a spreadsheet.",
  "version": "1.0.0",
  "type": "module",
  "scripts": {
    "dev": "wxt",
    "build": "wxt build",
    "zip": "wxt zip",
    "test": "vitest run",
    "test:watch": "vitest",
    "postinstall": "wxt prepare"
  },
  "dependencies": {
    "papaparse": "^5.4.1",
    "xlsx": "^0.18.5"
  },
  "devDependencies": {
    "@types/papaparse": "^5.3.14",
    "jsdom": "^24.1.0",
    "typescript": "^5.5.0",
    "vitest": "^2.0.0",
    "wxt": "^0.19.0"
  }
}
EOF

# ─────────────────────────────────────────────────────────────────────────────
# wxt.config.ts  — this is the file that "handles the manifest".
# NOTE: srcDir must be set because our entrypoints live under src/.
# ─────────────────────────────────────────────────────────────────────────────
cat > wxt.config.ts << 'EOF'
import { defineConfig } from 'wxt';

// WXT generates manifest.json from this config + your entrypoints.
// Do NOT hand-write manifest.json.
export default defineConfig({
  srcDir: 'src',
  manifest: {
    name: 'Table Scraper & Form Filler',
    version: '1.0.0',
    description: 'Scrape HTML tables to CSV/Excel and batch-fill forms from a spreadsheet.',
    // activeTab is intentionally omitted: <all_urls> host_permissions already
    // grants what we need, and the pair is redundant.
    permissions: ['scripting', 'downloads', 'storage', 'tabs'],
    host_permissions: ['<all_urls>'],
  },
});
EOF

# ─────────────────────────────────────────────────────────────────────────────
# tsconfig.json
# ─────────────────────────────────────────────────────────────────────────────
cat > tsconfig.json << 'EOF'
{
  "extends": "./.wxt/tsconfig.json"
}
EOF

# ─────────────────────────────────────────────────────────────────────────────
# src/types.ts   [DEV A]
# ─────────────────────────────────────────────────────────────────────────────
cat > src/types.ts << 'EOF'
// [DEV A] Shared contracts. Create/agree on this first — both devs import it.

export interface TableData {
  index: number;
  headers: string[];
  rows: string[][];
  caption: string;
  rowCount: number;
  columnCount: number;
}

export interface DetectedField {
  key: string;        // normalized column name, e.g. "first_name"
  selector: string;   // CSS selector to target the element
  label: string;      // human-readable label from the page
  type: string;       // text | email | select | ...
  detectedBy: string; // 'id' | 'name' | 'selector'
}

export type FieldMapping = Record<string, DetectedField>;

export interface FillPayload {
  data: Record<string, string>[];
  mapping: FieldMapping;
  submitSelector?: string;
  waitForNavigation?: boolean;
  delayBetweenRows?: number;
}

export interface ScrapPayload {
  selector?: string;
}

export interface EventMessage {
  type: 'EVENT';
  event: string;
  payload: Record<string, any>;
  timestamp: number;
}

export interface CommandMessage {
  command: string;
  payload?: Record<string, any>;
}

export interface CommandResponse {
  success: boolean;
  data?: any;
  error?: string;
}
EOF

# ─────────────────────────────────────────────────────────────────────────────
# src/utils/constants.ts   [DEV A]
# ─────────────────────────────────────────────────────────────────────────────
cat > src/utils/constants.ts << 'EOF'
// [DEV A] Single source of truth for command / event / error names.

export const COMMANDS = {
  SCRAP: 'scrap',
  SCAN: 'scan',
  FILL: 'fill',
  TERMINATE: 'terminate',
} as const;

export const EVENTS = {
  // Scraper
  SCRAP_INITIATED: 'SCRAP_INITIATED',
  SCRAP_FINISHED_SUCCESSFULLY: 'SCRAP_FINISHED_SUCCESSFULLY',
  SCRAP_FINISHED_WRONG: 'SCRAP_FINISHED_WRONG',
  SCRAP_TERMINATED: 'SCRAP_TERMINATED',
  // Form Filler
  FILL_INITIATED: 'FILL_INITIATED',
  FILL_ROW_STARTED: 'FILL_ROW_STARTED',
  FILL_FIELD_FILLED: 'FILL_FIELD_FILLED',
  FILL_ROW_SUBMITTED: 'FILL_ROW_SUBMITTED',
  FILL_ROW_FINISHED: 'FILL_ROW_FINISHED',
  FILL_FINISHED_SUCCESSFULLY: 'FILL_FINISHED_SUCCESSFULLY',
  FILL_FINISHED_WRONG: 'FILL_FINISHED_WRONG',
  FILL_TERMINATED: 'FILL_TERMINATED',
} as const;

export const ERROR_CODES = {
  NO_TABLES_FOUND: 'NO_TABLES_FOUND',
  PAGE_NOT_LOADED: 'PAGE_NOT_LOADED',
  PERMISSION_DENIED: 'PERMISSION_DENIED',
  PARSE_ERROR: 'PARSE_ERROR',
  ELEMENT_NOT_FOUND: 'ELEMENT_NOT_FOUND',
  VALIDATION_ERROR: 'VALIDATION_ERROR',
  CAPTCHA_DETECTED: 'CAPTCHA_DETECTED',
  NAVIGATION_TIMEOUT: 'NAVIGATION_TIMEOUT',
  FILE_INPUT_BLOCKED: 'FILE_INPUT_BLOCKED',
  NO_DATA: 'NO_DATA',
  NO_MAPPING: 'NO_MAPPING',
  TIMEOUT: 'TIMEOUT',
} as const;
EOF

# ─────────────────────────────────────────────────────────────────────────────
# src/utils/events.ts   [DEV A]
# Broadcast helper. Callable from BACKGROUND *and* CONTENT SCRIPT, because both
# can reach the popup via chrome.runtime.sendMessage. This is what lets the
# filler emit real per-row progress.
# ─────────────────────────────────────────────────────────────────────────────
cat > src/utils/events.ts << 'EOF'
// [DEV A] Event broadcast + listen helpers.
import type { EventMessage } from '@/types';

export function broadcastEvent(event: string, payload: Record<string, any> = {}) {
  const message: EventMessage = { type: 'EVENT', event, payload, timestamp: Date.now() };
  // If no popup is open, sendMessage rejects with "Receiving end does not
  // exist" — that's expected, so we swallow it.
  chrome.runtime.sendMessage(message).catch(() => {});
}

export function listenToEvents(cb: (event: string, payload: any) => void) {
  chrome.runtime.onMessage.addListener((msg) => {
    if (msg?.type === 'EVENT') cb(msg.event, msg.payload);
  });
}
EOF

# ─────────────────────────────────────────────────────────────────────────────
# src/utils/tableScraper.ts   [DEV A]
# Runs inside the content script, so it may use the DOM freely.
# ─────────────────────────────────────────────────────────────────────────────
cat > src/utils/tableScraper.ts << 'EOF'
// [DEV A] DOM scraping. Imported and called by the content script.
import type { TableData } from '@/types';

export function scrapeTablesFromPage(selector: string | null): TableData[] {
  const tables: TableData[] = [];
  const tableEls = selector
    ? document.querySelectorAll(selector)
    : document.querySelectorAll('table');

  tableEls.forEach((table, index) => {
    const headers: string[] = [];
    const rows: string[][] = [];

    const headerRow = table.querySelector('thead tr') || table.querySelector('tr');
    if (headerRow) {
      headerRow.querySelectorAll('th, td').forEach((cell) => {
        headers.push(cellText(cell));
      });
    }

    // Prefer tbody rows; fall back to all rows. Note: browsers insert an
    // implicit <tbody>, so a headerless table's first row shows up here too —
    // hence we always skip whichever row we used as the header.
    const bodyRows = table.querySelectorAll('tbody tr');
    const dataRows = bodyRows.length ? bodyRows : table.querySelectorAll('tr');
    dataRows.forEach((row) => {
      if (row === headerRow) return; // never emit the header row as data
      const rowData: string[] = [];
      row.querySelectorAll('td, th').forEach((cell) => {
        rowData.push(cellText(cell));
      });
      if (rowData.length) rows.push(rowData);
    });

    tables.push({
      index,
      headers,
      rows,
      caption: table.querySelector('caption')?.textContent?.trim() || '',
      rowCount: rows.length,
      columnCount: headers.length || (rows[0]?.length || 0),
    });
    // TODO [DEV A]: colspan/rowspan flattening. Document behavior for now.
  });

  return tables;
}

// innerText reflects *rendered* text but is undefined outside a real browser
// (e.g. under jsdom in tests). Fall back to textContent so the util is testable.
function cellText(cell: Element): string {
  return (((cell as HTMLElement).innerText ?? cell.textContent) ?? '').trim();
}
EOF

# ─────────────────────────────────────────────────────────────────────────────
# src/utils/csvExporter.ts   [DEV A]
# NOTE the real newline "\n" and BOM "\uFEFF" (single backslash!).
# ─────────────────────────────────────────────────────────────────────────────
cat > src/utils/csvExporter.ts << 'EOF'
// [DEV A] Runs in the POPUP (has DOM + chrome.downloads). No page access needed.
import type { TableData } from '@/types';

export function tablesToCSV(tables: TableData[], delimiter = ',') {
  return tables.map((table) => {
    let csv = '';
    if (table.headers.length) {
      csv += table.headers.map((h) => escapeCSV(h, delimiter)).join(delimiter) + '\n';
    }
    table.rows.forEach((row) => {
      csv += row.map((cell) => escapeCSV(cell, delimiter)).join(delimiter) + '\n';
    });
    return { name: table.caption || `table_${table.index}`, csv: csv.trimEnd() };
  });
}

function escapeCSV(value: string, delimiter: string): string {
  if (value == null) return '';
  const str = String(value);
  if (str.includes(delimiter) || str.includes('"') || str.includes('\n')) {
    return `"${str.replace(/"/g, '""')}"`;
  }
  return str;
}

export async function downloadCSV(filename: string, csvContent: string) {
  // Prepend BOM so Excel opens UTF-8 correctly.
  const blob = new Blob(['\uFEFF' + csvContent], { type: 'text/csv;charset=utf-8;' });
  const url = URL.createObjectURL(blob);
  try {
    await chrome.downloads.download({ url, filename, saveAs: true });
  } finally {
    URL.revokeObjectURL(url);
  }
}
EOF

# ─────────────────────────────────────────────────────────────────────────────
# src/utils/excelExporter.ts   [DEV A]
# ─────────────────────────────────────────────────────────────────────────────
cat > src/utils/excelExporter.ts << 'EOF'
// [DEV A] SheetJS export. Runs in the POPUP.
import * as XLSX from 'xlsx';
import type { TableData } from '@/types';

export async function tablesToExcel(tables: TableData[]) {
  const workbook = XLSX.utils.book_new();
  const usedNames = new Set<string>();

  tables.forEach((table) => {
    const data = [table.headers, ...table.rows];
    const ws = XLSX.utils.aoa_to_sheet(data);
    // Sheet names: max 31 chars and must be unique.
    let name = (table.caption || `Table ${table.index + 1}`).substring(0, 31);
    let n = 1;
    while (usedNames.has(name)) name = `${name.substring(0, 28)}_${n++}`;
    usedNames.add(name);
    XLSX.utils.book_append_sheet(workbook, ws, name);
  });

  const buf = XLSX.write(workbook, { bookType: 'xlsx', type: 'array' });
  const blob = new Blob([buf], {
    type: 'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet',
  });
  const url = URL.createObjectURL(blob);
  try {
    await chrome.downloads.download({ url, filename: 'tables_export.xlsx', saveAs: true });
  } finally {
    URL.revokeObjectURL(url);
  }
}
EOF

# ─────────────────────────────────────────────────────────────────────────────
# src/utils/fieldDetector.ts   [DEV B]
# ─────────────────────────────────────────────────────────────────────────────
cat > src/utils/fieldDetector.ts << 'EOF'
// [DEV B] Field detection. Imported and called by the content script.
import type { DetectedField } from '@/types';

export function detectFormFields(includeHidden: boolean): DetectedField[] {
  const fields: DetectedField[] = [];
  const patterns: Array<{ sel: string; type: string }> = [
    { sel: 'input[type="text"]', type: 'text' },
    { sel: 'input[type="email"]', type: 'email' },
    { sel: 'input[type="tel"]', type: 'tel' },
    { sel: 'input[type="number"]', type: 'number' },
    { sel: 'input[type="password"]', type: 'password' },
    { sel: 'input[type="date"]', type: 'date' },
    { sel: 'input:not([type])', type: 'text' }, // inputs default to text
    { sel: 'textarea', type: 'textarea' },
    { sel: 'select', type: 'select' },
  ];

  patterns.forEach(({ sel, type }) => {
    document.querySelectorAll(sel).forEach((el, idx) => {
      const input = el as HTMLInputElement | HTMLTextAreaElement | HTMLSelectElement;
      if (!includeHidden && input.offsetParent === null) return;

      const label = findLabel(input);
      const key = normalizeKey(label, input.name, input.id, (input as any).placeholder, idx);

      fields.push({
        key,
        selector: generateSelector(input),
        label,
        type,
        detectedBy: input.id ? 'id' : input.name ? 'name' : 'selector',
      });
    });
  });

  return fields;
}

function findLabel(input: HTMLElement): string {
  if (input.id) {
    const label = document.querySelector(`label[for="${CSS.escape(input.id)}"]`);
    if (label) return label.textContent?.trim() || '';
  }
  const parent = input.closest('label');
  if (parent) return parent.textContent?.trim() || '';
  return input.getAttribute('aria-label') || (input as any).placeholder || (input as any).name || 'Unlabeled';
}

function normalizeKey(label: string, name: string, id: string, placeholder: string, idx: number): string {
  const raw = label || name || id || placeholder || `field_${idx}`;
  return raw.toLowerCase().replace(/[^a-z0-9]/g, '_').replace(/_+/g, '_').replace(/^_|_$/g, '');
}

// Prefer a *unique* selector. Escape ids/names. Fall back to :nth-of-type.
function generateSelector(el: Element): string {
  if (el.id) return `#${CSS.escape(el.id)}`;
  const name = (el as any).name as string | undefined;
  if (name) {
    const sel = `${el.tagName.toLowerCase()}[name="${CSS.escape(name)}"]`;
    if (document.querySelectorAll(sel).length === 1) return sel;
  }
  // TODO [DEV B]: harden this. nth-of-type within the closest form is a decent start.
  const tag = el.tagName.toLowerCase();
  const siblings = Array.from(document.querySelectorAll(tag));
  const i = siblings.indexOf(el);
  return `${tag}:nth-of-type(${i + 1})`;
}
EOF

# ─────────────────────────────────────────────────────────────────────────────
# src/utils/formFiller.ts   [DEV B]
# Async so it can honor delayBetweenRows. Emits progress through an injected
# callback so this module stays chrome-agnostic and unit-testable.
# ─────────────────────────────────────────────────────────────────────────────
cat > src/utils/formFiller.ts << 'EOF'
// [DEV B] Batch fill. Imported and called by the content script.
import type { FillPayload } from '@/types';

type Emit = (event: string, payload: Record<string, any>) => void;
type ShouldStop = () => boolean;

const sleep = (ms: number) => new Promise((r) => setTimeout(r, ms));

export async function fillFormBatch(payload: FillPayload, emit: Emit, shouldStop: ShouldStop) {
  const { data, mapping, submitSelector, delayBetweenRows = 0 } = payload;
  const report = { filled: 0, failed: 0, rows: [] as any[] };

  for (let i = 0; i < data.length; i++) {
    if (shouldStop()) {
      return { success: false, error: { code: 'TERMINATED', atRow: i }, report };
    }

    emit('FILL_ROW_STARTED', { currentRow: i + 1, totalRows: data.length });
    const row = data[i];
    const rowReport: any = { rowIndex: i, fields: [], status: 'ok' };

    for (const [colKey, fieldDef] of Object.entries(mapping)) {
      const el = document.querySelector(fieldDef.selector);
      if (!el) {
        rowReport.fields.push({ field: colKey, status: 'not_found' });
        report.failed++;
        continue;
      }
      try {
        fillField(el as HTMLElement, row[colKey], fieldDef.type);
        emit('FILL_FIELD_FILLED', { row: i + 1, field: colKey });
        rowReport.fields.push({ field: colKey, status: 'filled', value: row[colKey] });
        report.filled++;
      } catch (err: any) {
        rowReport.fields.push({ field: colKey, status: 'error', error: err.message });
        report.failed++;
      }
    }

    if (submitSelector) {
      const submitBtn = document.querySelector(submitSelector) as HTMLElement | null;
      if (submitBtn) {
        submitBtn.click();
        emit('FILL_ROW_SUBMITTED', { row: i + 1 });
        // NOTE: if the submit triggers a full navigation, this content script
        // is destroyed and the loop stops. For multi-row submit-and-reload
        // flows, drive the loop from the background using
        // chrome.webNavigation.onCompleted to resume after each reload.
        // TODO [DEV B]: implement the resume strategy if you need it.
      }
    }

    report.rows.push(rowReport);
    emit('FILL_ROW_FINISHED', { row: i + 1, totalRows: data.length });

    if (delayBetweenRows && i < data.length - 1) await sleep(delayBetweenRows);
  }

  return { success: true, report };
}

export function fillField(el: HTMLElement, value: string, _type: string) {
  const tag = el.tagName.toLowerCase();

  if (tag === 'input') {
    const input = el as HTMLInputElement;
    if (input.type === 'checkbox') {
      input.checked = parseBoolean(value);
    } else if (input.type === 'radio') {
      const radio = document.querySelector(
        `input[type="radio"][name="${CSS.escape(input.name)}"][value="${CSS.escape(value)}"]`,
      ) as HTMLInputElement | null;
      if (radio) radio.checked = true;
    } else if (input.type === 'file') {
      throw new Error('File inputs cannot be filled programmatically');
    } else {
      input.value = value;
    }
  } else if (tag === 'select') {
    const select = el as HTMLSelectElement;
    select.value = value;
    if (select.value !== value) {
      for (const opt of Array.from(select.options)) {
        if (opt.text.trim() === value) { select.value = opt.value; break; }
      }
    }
  } else if (tag === 'textarea') {
    (el as HTMLTextAreaElement).value = value;
  }

  // Fire the events frameworks (React/Vue) listen for.
  ['focus', 'input', 'change', 'blur'].forEach((ev) => {
    el.dispatchEvent(new Event(ev, { bubbles: true }));
  });
}

function parseBoolean(v: string): boolean {
  return /^(true|yes|y|1|on|checked)$/i.test(String(v).trim());
}
EOF

# ─────────────────────────────────────────────────────────────────────────────
# src/utils/csvParser.ts   [DEV B]
# ─────────────────────────────────────────────────────────────────────────────
cat > src/utils/csvParser.ts << 'EOF'
// [DEV B] CSV parsing + fuzzy column matching. Runs in the POPUP.
import Papa from 'papaparse';
import type { DetectedField, FieldMapping } from '@/types';

export function parseCSV(file: File): Promise<Record<string, string>[]> {
  return new Promise((resolve, reject) => {
    Papa.parse<Record<string, string>>(file, {
      header: true,
      skipEmptyLines: true,
      complete: (results) => resolve(results.data),
      error: (err) => reject(err),
    });
  });
}

export function autoMapColumns(csvHeaders: string[], detectedFields: DetectedField[]): FieldMapping {
  const mapping: FieldMapping = {};
  csvHeaders.forEach((header) => {
    const nh = normalize(header);
    const match = detectedFields.find((f) => {
      const nk = normalize(f.key);
      const nl = normalize(f.label);
      return nk === nh || nl === nh || nk.includes(nh) || nh.includes(nk) || levenshtein(nk, nh) <= 2;
    });
    if (match) mapping[header] = match;
  });
  return mapping;
}

function normalize(str: string): string {
  return str.toLowerCase().replace(/[^a-z0-9]/g, '');
}

function levenshtein(a: string, b: string): number {
  const m: number[][] = [];
  for (let i = 0; i <= a.length; i++) m[i] = [i];
  for (let j = 0; j <= b.length; j++) m[0][j] = j;
  for (let i = 1; i <= a.length; i++) {
    for (let j = 1; j <= b.length; j++) {
      m[i][j] = a[i - 1] === b[j - 1]
        ? m[i - 1][j - 1]
        : Math.min(m[i - 1][j - 1], m[i][j - 1], m[i - 1][j]) + 1;
    }
  }
  return m[a.length][b.length];
}
EOF

# ─────────────────────────────────────────────────────────────────────────────
# src/entrypoints/background.ts   [DEV A]
# Router only. Forwards commands to the content script and returns its response.
# ─────────────────────────────────────────────────────────────────────────────
cat > src/entrypoints/background.ts << 'EOF'
// [DEV A] Service worker: routes popup commands to the content script.
import { COMMANDS, ERROR_CODES } from '@/utils/constants';
import type { CommandMessage, CommandResponse } from '@/types';

export default defineBackground(() => {
  chrome.runtime.onMessage.addListener((request: CommandMessage, _sender, sendResponse) => {
    // Ignore EVENT broadcasts flowing back through runtime messaging.
    if ((request as any)?.type === 'EVENT') return false;

    if (!Object.values(COMMANDS).includes(request.command as any)) {
      sendResponse({ success: false, error: `Unknown command: ${request.command}` });
      return false;
    }

    route(request).then(sendResponse).catch((err) =>
      sendResponse({ success: false, error: err.message }),
    );
    return true; // async response
  });
});

async function route(request: CommandMessage): Promise<CommandResponse> {
  const tab = await getActiveTab();
  try {
    // The content script (declared for <all_urls>) does the DOM work and may
    // itself broadcast progress events straight to the popup.
    return await chrome.tabs.sendMessage(tab.id!, request);
  } catch {
    // No receiver = content script not present (e.g. page opened before the
    // extension was installed, or a chrome:// page). Tell the user plainly.
    return { success: false, error: ERROR_CODES.PAGE_NOT_LOADED };
  }
}

async function getActiveTab(): Promise<chrome.tabs.Tab> {
  const [tab] = await chrome.tabs.query({ active: true, currentWindow: true });
  if (!tab?.id) throw new Error('No active tab');
  return tab;
}
EOF

# ─────────────────────────────────────────────────────────────────────────────
# src/entrypoints/content.ts   [BOTH]
# The one place the DOM utilities are actually called. Because these are normal
# module imports (not stringified functions), helper functions work fine.
# ─────────────────────────────────────────────────────────────────────────────
cat > src/entrypoints/content.ts << 'EOF'
// [BOTH] Content script: receives commands, runs DOM work, broadcasts events.
import { COMMANDS, EVENTS, ERROR_CODES } from '@/utils/constants';
import { broadcastEvent } from '@/utils/events';
import { scrapeTablesFromPage } from '@/utils/tableScraper';     // [DEV A]
import { detectFormFields } from '@/utils/fieldDetector';        // [DEV B]
import { fillFormBatch } from '@/utils/formFiller';              // [DEV B]
import type { CommandMessage, CommandResponse } from '@/types';

export default defineContentScript({
  matches: ['<all_urls>'],
  allFrames: true, // best-effort scraping/filling inside same-origin frames
  main() {
    let terminate = false;

    chrome.runtime.onMessage.addListener(
      (request: CommandMessage, _sender, sendResponse) => {
        handle(request).then(sendResponse).catch((err) =>
          sendResponse({ success: false, error: err.message }),
        );
        return true; // async
      },
    );

    async function handle(request: CommandMessage): Promise<CommandResponse> {
      switch (request.command) {
        case COMMANDS.SCRAP: {
          broadcastEvent(EVENTS.SCRAP_INITIATED);
          const tables = scrapeTablesFromPage(request.payload?.selector ?? null);
          if (!tables.length) {
            broadcastEvent(EVENTS.SCRAP_FINISHED_WRONG, { error: ERROR_CODES.NO_TABLES_FOUND });
            return { success: false, error: ERROR_CODES.NO_TABLES_FOUND };
          }
          broadcastEvent(EVENTS.SCRAP_FINISHED_SUCCESSFULLY, {
            tableCount: tables.length,
            totalRows: tables.reduce((a, t) => a + t.rowCount, 0),
          });
          return { success: true, data: tables };
        }

        case COMMANDS.SCAN: {
          const fields = detectFormFields(request.payload?.includeHidden ?? false);
          return { success: true, data: fields };
        }

        case COMMANDS.FILL: {
          terminate = false;
          broadcastEvent(EVENTS.FILL_INITIATED, {
            totalRows: request.payload?.data?.length ?? 0,
          });
          const result = await fillFormBatch(
            request.payload as any,
            broadcastEvent,
            () => terminate,
          );
          if (result.success) {
            broadcastEvent(EVENTS.FILL_FINISHED_SUCCESSFULLY, result.report);
            return { success: true, data: result.report };
          }
          if ((result as any).error?.code === 'TERMINATED') {
            broadcastEvent(EVENTS.FILL_TERMINATED, { progress: (result as any).error });
          } else {
            broadcastEvent(EVENTS.FILL_FINISHED_WRONG, { error: (result as any).error });
          }
          return { success: false, error: (result as any).error?.code };
        }

        case COMMANDS.TERMINATE: {
          terminate = true; // the fill loop checks this between rows
          return { success: true };
        }

        default:
          return { success: false, error: `Unknown command: ${request.command}` };
      }
    }
  },
});
EOF

# ─────────────────────────────────────────────────────────────────────────────
# src/entrypoints/popup/index.html   [DEV A]
# ─────────────────────────────────────────────────────────────────────────────
cat > src/entrypoints/popup/index.html << 'EOF'
<!DOCTYPE html>
<html>
<head>
  <meta charset="UTF-8" />
  <link rel="stylesheet" href="./style.css" />
</head>
<body>
  <div class="popup-container">
    <div class="tabs">
      <button class="tab-btn active" data-tab="scraper">📊 Scraper</button>
      <button class="tab-btn" data-tab="filler">📝 Form Filler</button>
    </div>

    <!-- Scraper tab: [DEV A] -->
    <div id="tab-scraper" class="tab-panel active">
      <button id="btn-extract">Extract Tables</button>
      <div id="scraper-progress" class="hidden"><p>Scanning page for tables…</p></div>
      <div id="scraper-results" class="hidden">
        <p id="scraper-status"></p>
        <button id="btn-csv">Download CSV</button>
        <button id="btn-excel">Download Excel</button>
      </div>
      <div id="scraper-error" class="hidden error-banner"></div>
    </div>

    <!-- Filler tab: [DEV B] -->
    <div id="tab-filler" class="tab-panel">
      <input type="file" id="file-upload" accept=".csv" />
      <button id="btn-scan">🔍 Scan Page for Fields</button>
      <div id="filler-mapping" class="hidden">
        <h4>Detected Fields</h4>
        <div id="mapping-list"></div>
        <button id="btn-start-fill">▶ Start Batch</button>
      </div>
      <div id="filler-progress" class="hidden">
        <div class="progress-bar"><div id="progress-fill"></div></div>
        <p id="filler-status">Filling row 0 of 0…</p>
        <button id="btn-cancel">⏹ Cancel</button>
      </div>
      <div id="filler-success" class="hidden success-banner"></div>
      <div id="filler-error" class="hidden error-banner"></div>
    </div>
  </div>
  <script type="module" src="./main.ts"></script>
</body>
</html>
EOF

# ─────────────────────────────────────────────────────────────────────────────
# src/entrypoints/popup/style.css   [DEV A]
# ─────────────────────────────────────────────────────────────────────────────
cat > src/entrypoints/popup/style.css << 'EOF'
:root { --gap: 10px; --accent: #2563eb; }
* { box-sizing: border-box; font-family: system-ui, sans-serif; }
body { margin: 0; width: 360px; }
.popup-container { padding: var(--gap); }
.tabs { display: flex; gap: 4px; margin-bottom: var(--gap); }
.tab-btn { flex: 1; padding: 8px; border: 0; background: #eee; cursor: pointer; border-radius: 6px; }
.tab-btn.active { background: var(--accent); color: #fff; }
.tab-panel { display: none; }
.tab-panel.active { display: block; }
button { padding: 8px 12px; border-radius: 6px; border: 0; cursor: pointer; }
.hidden { display: none; }
.error-banner { color: #b91c1c; background: #fee2e2; padding: 8px; border-radius: 6px; margin-top: var(--gap); }
.success-banner { color: #065f46; background: #d1fae5; padding: 8px; border-radius: 6px; margin-top: var(--gap); }
.progress-bar { height: 8px; background: #eee; border-radius: 4px; overflow: hidden; }
#progress-fill { height: 100%; width: 0; background: var(--accent); transition: width .2s; }
.mapping-row { display: flex; gap: 6px; font-size: 12px; padding: 2px 0; }
EOF

# ─────────────────────────────────────────────────────────────────────────────
# src/entrypoints/popup/main.ts   [BOTH]
# ─────────────────────────────────────────────────────────────────────────────
cat > src/entrypoints/popup/main.ts << 'EOF'
// [BOTH] Tab switching + event fan-out to each tab module.
import { listenToEvents } from '@/utils/events';
import { initScraperTab } from './scraper-tab';
import { initFillerTab } from './filler-tab';

const tabBtns = document.querySelectorAll<HTMLButtonElement>('.tab-btn');
const tabPanels = document.querySelectorAll<HTMLElement>('.tab-panel');

tabBtns.forEach((btn) => {
  btn.addEventListener('click', () => {
    const target = btn.dataset.tab!;
    tabBtns.forEach((b) => b.classList.toggle('active', b === btn));
    tabPanels.forEach((p) => p.classList.toggle('active', p.id === `tab-${target}`));
  });
});

listenToEvents((event, payload) => {
  if (event.startsWith('SCRAP_')) {
    window.dispatchEvent(new CustomEvent('scrap-event', { detail: { event, payload } }));
  } else if (event.startsWith('FILL_')) {
    window.dispatchEvent(new CustomEvent('fill-event', { detail: { event, payload } }));
  }
});

initScraperTab();
initFillerTab();
EOF

# ─────────────────────────────────────────────────────────────────────────────
# src/entrypoints/popup/scraper-tab.ts   [DEV A]
# ─────────────────────────────────────────────────────────────────────────────
cat > src/entrypoints/popup/scraper-tab.ts << 'EOF'
// [DEV A] Scraper tab UI.
import { COMMANDS } from '@/utils/constants';
import { tablesToCSV, downloadCSV } from '@/utils/csvExporter';
import { tablesToExcel } from '@/utils/excelExporter';
import type { TableData } from '@/types';

let lastTables: TableData[] = [];

export function initScraperTab() {
  const $ = (id: string) => document.getElementById(id)!;
  const progress = $('scraper-progress');
  const results = $('scraper-results');
  const error = $('scraper-error');
  const status = $('scraper-status');

  $('btn-extract').addEventListener('click', async () => {
    hideAll();
    progress.classList.remove('hidden');
    const res = await chrome.runtime.sendMessage({ command: COMMANDS.SCRAP, payload: {} });
    progress.classList.add('hidden');
    if (res.success) {
      lastTables = res.data;
      const rows = lastTables.reduce((a, t) => a + t.rowCount, 0);
      status.textContent = `Found ${lastTables.length} table(s), ${rows} rows.`;
      results.classList.remove('hidden');
    } else {
      showError(error, res.error);
    }
  });

  $('btn-csv').addEventListener('click', () => {
    tablesToCSV(lastTables).forEach((e) => downloadCSV(`${e.name}.csv`, e.csv));
  });
  $('btn-excel').addEventListener('click', () => tablesToExcel(lastTables));
}

function hideAll() {
  ['scraper-progress', 'scraper-results', 'scraper-error'].forEach((id) =>
    document.getElementById(id)!.classList.add('hidden'),
  );
}

function showError(el: HTMLElement, code: string) {
  const messages: Record<string, string> = {
    NO_TABLES_FOUND: 'No tables found on this page. Try a custom selector.',
    PAGE_NOT_LOADED: 'Reload the page, then try again (the extension was likely installed after this tab opened).',
    PERMISSION_DENIED: 'Could not access some page content. It may be in a restricted frame.',
    PARSE_ERROR: 'Could not read the table. Refresh and retry.',
  };
  el.textContent = messages[code] || `Error: ${code}`;
  el.classList.remove('hidden');
}
EOF

# ─────────────────────────────────────────────────────────────────────────────
# src/entrypoints/popup/filler-tab.ts   [DEV B]
# ─────────────────────────────────────────────────────────────────────────────
cat > src/entrypoints/popup/filler-tab.ts << 'EOF'
// [DEV B] Form filler tab UI.
import { COMMANDS, EVENTS } from '@/utils/constants';
import { parseCSV, autoMapColumns } from '@/utils/csvParser';
import type { DetectedField, FieldMapping } from '@/types';

let uploadedData: Record<string, string>[] = [];
let mapping: FieldMapping = {};

export function initFillerTab() {
  const $ = (id: string) => document.getElementById(id)!;
  const fileInput = $('file-upload') as HTMLInputElement;
  const progressDiv = $('filler-progress');
  const progressFill = $('progress-fill');
  const statusText = $('filler-status');
  const successDiv = $('filler-success');
  const errorDiv = $('filler-error');

  fileInput.addEventListener('change', async (e) => {
    const file = (e.target as HTMLInputElement).files?.[0];
    if (!file) return;
    uploadedData = await parseCSV(file);
    statusText.textContent = `Loaded ${uploadedData.length} rows. Now scan the page.`;
  });

  $('btn-scan').addEventListener('click', async () => {
    const res = await chrome.runtime.sendMessage({ command: COMMANDS.SCAN, payload: {} });
    if (!res.success) return showError(errorDiv, res.error);
    const fields = res.data as DetectedField[];
    mapping = autoMapColumns(Object.keys(uploadedData[0] || {}), fields);
    renderMapping($('mapping-list'), mapping);
    $('filler-mapping').classList.remove('hidden');
  });

  $('btn-start-fill').addEventListener('click', async () => {
    hideAll();
    progressDiv.classList.remove('hidden');
    const payload = {
      data: uploadedData,
      mapping,
      submitSelector: "button[type='submit']",
      waitForNavigation: false, // see formFiller.ts note before enabling
      delayBetweenRows: 300,
    };
    const res = await chrome.runtime.sendMessage({ command: COMMANDS.FILL, payload });
    progressDiv.classList.add('hidden');
    if (res.success) {
      successDiv.textContent = `Done. Filled ${uploadedData.length} rows.`;
      successDiv.classList.remove('hidden');
    } else {
      showError(errorDiv, res.error);
    }
  });

  $('btn-cancel').addEventListener('click', () => {
    chrome.runtime.sendMessage({ command: COMMANDS.TERMINATE, payload: { reason: 'USER_CANCELLED' } });
  });

  // Real per-row progress, broadcast from the content script.
  window.addEventListener('fill-event', ((e: CustomEvent) => {
    const { event, payload } = e.detail;
    if (event === EVENTS.FILL_ROW_STARTED) {
      progressFill.style.width = `${(payload.currentRow / payload.totalRows) * 100}%`;
      statusText.textContent = `Filling row ${payload.currentRow} of ${payload.totalRows}…`;
    } else if (event === EVENTS.FILL_TERMINATED) {
      progressDiv.classList.add('hidden');
      errorDiv.textContent = 'Stopped.';
      errorDiv.classList.remove('hidden');
    }
  }) as EventListener);
}

function renderMapping(container: HTMLElement, m: FieldMapping) {
  container.innerHTML = Object.entries(m)
    .map(([col, f]) => `<div class="mapping-row"><span>${col}</span><span>→</span><span>${f.label} (${f.selector})</span></div>`)
    .join('');
}

function hideAll() {
  ['filler-progress', 'filler-success', 'filler-error'].forEach((id) =>
    document.getElementById(id)!.classList.add('hidden'),
  );
}

function showError(el: HTMLElement, code: string) {
  const messages: Record<string, string> = {
    ELEMENT_NOT_FOUND: 'A mapped field was not found. Re-scan and try again.',
    PAGE_NOT_LOADED: 'Reload the page, then try again.',
    NO_DATA: 'No data loaded. Upload a CSV first.',
    NO_MAPPING: 'No fields mapped. Scan the page first.',
    TERMINATED: 'Cancelled.',
  };
  el.textContent = messages[code] || `Error: ${code}`;
  el.classList.remove('hidden');
}
EOF

# ─────────────────────────────────────────────────────────────────────────────
# README
# ─────────────────────────────────────────────────────────────────────────────
cat > README.md << 'EOF'
# Table Scraper & Form Filler

Manifest V3 Chrome extension built with WXT + TypeScript.

## Setup
```bash
npm install
npm run dev      # launches Chrome with the extension loaded (.output/chrome-mv3-dev)
npm run build    # production build
npm run zip      # package for the Chrome Web Store
```

## Architecture
Popup → Background (router) → **Content script** (DOM work) → broadcasts events → Popup.

The content script — not `executeScript({ func })` — owns all DOM logic. That is
what lets helper functions, per-row progress events, and Cancel actually work.

> After first install, reload any already-open tabs so the content script is present.

## Ownership
- **Dev A:** scaffolding, background router, shared infra (types/constants/events),
  scraper (`tableScraper`, `csvExporter`, `excelExporter`), popup shell + scraper tab.
- **Dev B:** field detection + filling (`fieldDetector`, `formFiller`, `csvParser`),
  filler tab UI.

Search the tree for `TODO` for the remaining implementation work.
EOF

# a tiny placeholder icon note (WXT will warn without icons but still builds)
cat > public/icon/README.txt << 'EOF'
Drop icon-16.png, icon-32.png, icon-48.png, icon-128.png here (or configure
manifest.icons in wxt.config.ts). WXT builds without them but Chrome shows a
default icon.
EOF

# ─────────────────────────────────────────────────────────────────────────────
# vitest.config.ts  — mirror WXT's "@/..." alias so tests import like the app.
# ─────────────────────────────────────────────────────────────────────────────
cat > vitest.config.ts << 'EOF'
import { defineConfig } from 'vitest/config';
import { fileURLToPath } from 'node:url';

export default defineConfig({
  test: {
    environment: 'jsdom', // DOM utils (scraper/filler) need a document
    globals: false,        // we import describe/it/expect explicitly
  },
  resolve: {
    alias: { '@': fileURLToPath(new URL('./src', import.meta.url)) },
  },
});
EOF

# ─────────────────────────────────────────────────────────────────────────────
# Unit tests — the chrome-agnostic utilities. Run with: npm run test
# ─────────────────────────────────────────────────────────────────────────────
cat > src/utils/csvExporter.test.ts << 'EOF'
// [DEV A] Pure logic — no DOM, no chrome.
import { describe, it, expect } from 'vitest';
import { tablesToCSV } from './csvExporter';
import type { TableData } from '@/types';

const table = (over: Partial<TableData> = {}): TableData => ({
  index: 0, headers: ['a', 'b'], rows: [['1', '2']],
  caption: '', rowCount: 1, columnCount: 2, ...over,
});

describe('tablesToCSV', () => {
  it('joins headers and rows with real newlines', () => {
    const [out] = tablesToCSV([table()]);
    expect(out.csv).toBe('a,b\n1,2');
  });

  it('quotes cells containing the delimiter, quotes, or newlines', () => {
    const [out] = tablesToCSV([table({
      headers: ['x'],
      rows: [['a,b'], ['he said "hi"'], ['line1\nline2']],
    })]);
    expect(out.csv).toBe('x\n"a,b"\n"he said ""hi"""\n"line1\nline2"');
  });

  it('names the export from the caption, falling back to table_<index>', () => {
    expect(tablesToCSV([table({ caption: 'Sales' })])[0].name).toBe('Sales');
    expect(tablesToCSV([table({ caption: '', index: 3 })])[0].name).toBe('table_3');
  });
});
EOF

cat > src/utils/csvParser.test.ts << 'EOF'
// [DEV B] Pure logic — no DOM, no chrome.
import { describe, it, expect } from 'vitest';
import { autoMapColumns } from './csvParser';
import type { DetectedField } from '@/types';

const field = (key: string, label = key): DetectedField => ({
  key, label, selector: `#${key}`, type: 'text', detectedBy: 'id',
});

describe('autoMapColumns', () => {
  const fields = [field('first_name', 'First Name'), field('email', 'Email'), field('phone', 'Phone')];

  it('matches exact normalized names', () => {
    expect(autoMapColumns(['Email'], fields).Email.key).toBe('email');
  });
  it('matches via substring', () => {
    expect(autoMapColumns(['first'], fields).first?.key).toBe('first_name');
  });
  it('matches close typos within Levenshtein distance 2', () => {
    expect(autoMapColumns(['emial'], fields).emial?.key).toBe('email');
  });
  it('leaves unmatched columns out of the mapping', () => {
    expect(autoMapColumns(['zzz_unknown'], fields).zzz_unknown).toBeUndefined();
  });
});
EOF

cat > src/utils/formFiller.test.ts << 'EOF'
// [DEV B] DOM logic — runs under jsdom.
import { describe, it, expect, vi } from 'vitest';
import { fillField, fillFormBatch } from './formFiller';
import type { FieldMapping } from '@/types';

describe('fillField', () => {
  it('sets a text value and fires an input event', () => {
    document.body.innerHTML = '<input id="n" type="text">';
    const el = document.getElementById('n') as HTMLInputElement;
    const spy = vi.fn();
    el.addEventListener('input', spy);
    fillField(el, 'Ada', 'text');
    expect(el.value).toBe('Ada');
    expect(spy).toHaveBeenCalled();
  });

  it('does NOT tick a checkbox for falsey strings (the v1 Boolean() bug)', () => {
    document.body.innerHTML = '<input id="c" type="checkbox">';
    const el = document.getElementById('c') as HTMLInputElement;
    for (const v of ['false', 'no', '0', '']) {
      el.checked = false;
      fillField(el, v, 'text');
      expect(el.checked).toBe(false);
    }
  });

  it('ticks a checkbox for truthy strings', () => {
    document.body.innerHTML = '<input id="c" type="checkbox">';
    const el = document.getElementById('c') as HTMLInputElement;
    fillField(el, 'true', 'text');
    expect(el.checked).toBe(true);
  });

  it('throws on file inputs', () => {
    document.body.innerHTML = '<input id="f" type="file">';
    const el = document.getElementById('f') as HTMLInputElement;
    expect(() => fillField(el, 'x', 'text')).toThrow();
  });
});

describe('fillFormBatch', () => {
  const mapping: FieldMapping = {
    name:  { key: 'name',  label: 'Name',  selector: '#name',  type: 'text',  detectedBy: 'id' },
    email: { key: 'email', label: 'Email', selector: '#email', type: 'email', detectedBy: 'id' },
  };
  const data = [{ name: 'A', email: 'a@x.com' }, { name: 'B', email: 'b@x.com' }];
  const setup = () => { document.body.innerHTML = '<input id="name"><input id="email">'; };

  it('fills every field and emits one FILL_ROW_STARTED per row', async () => {
    setup();
    const events: string[] = [];
    const res = await fillFormBatch({ data, mapping } as any, (e) => events.push(e), () => false);
    expect(res.success).toBe(true);
    expect(res.report.filled).toBe(4); // 2 fields x 2 rows
    expect(events.filter((e) => e === 'FILL_ROW_STARTED')).toHaveLength(2);
  });

  it('stops between rows when shouldStop() is true', async () => {
    setup();
    const res = await fillFormBatch({ data, mapping } as any, () => {}, () => true);
    expect(res.success).toBe(false);
    expect((res as any).error.code).toBe('TERMINATED');
  });
});
EOF

cat > src/utils/tableScraper.test.ts << 'EOF'
// [DEV A] DOM logic — runs under jsdom.
import { describe, it, expect } from 'vitest';
import { scrapeTablesFromPage } from './tableScraper';

describe('scrapeTablesFromPage', () => {
  it('extracts caption, headers and tbody rows', () => {
    document.body.innerHTML = `
      <table>
        <caption>Fruit</caption>
        <thead><tr><th>Name</th><th>Qty</th></tr></thead>
        <tbody>
          <tr><td>Apple</td><td>3</td></tr>
          <tr><td>Pear</td><td>5</td></tr>
        </tbody>
      </table>`;
    const [t] = scrapeTablesFromPage(null);
    expect(t.headers).toEqual(['Name', 'Qty']);
    expect(t.rows).toEqual([['Apple', '3'], ['Pear', '5']]);
    expect(t.caption).toBe('Fruit');
    expect(t.rowCount).toBe(2);
  });

  it('does not duplicate the header row when there is no <tbody>', () => {
    document.body.innerHTML = `
      <table>
        <tr><th>H1</th><th>H2</th></tr>
        <tr><td>a</td><td>b</td></tr>
      </table>`;
    const [t] = scrapeTablesFromPage(null);
    expect(t.headers).toEqual(['H1', 'H2']);
    expect(t.rows).toEqual([['a', 'b']]);
  });
});
EOF

# ─────────────────────────────────────────────────────────────────────────────
# .gitignore
# ─────────────────────────────────────────────────────────────────────────────
cat > .gitignore << 'EOF'
# deps
node_modules/

# WXT build + generated types
.output/
.wxt/
stats.html
*.zip

# env & editor
.env
.env.*
.DS_Store
.idea/
.vscode/
EOF

# ─────────────────────────────────────────────────────────────────────────────
# GitHub Actions CI — install, test, build on every push / PR.
# ─────────────────────────────────────────────────────────────────────────────
mkdir -p .github/workflows
cat > .github/workflows/ci.yml << 'EOF'
name: CI

on:
  push:
    branches: [main]
  pull_request:

jobs:
  build-and-test:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - uses: actions/setup-node@v4
        with:
          node-version: 20
          cache: npm
      - run: npm ci
      - run: npm run test
      - run: npm run build
EOF

echo ""
echo "✓ Scaffolded '$PROJECT'"
echo ""
echo "Next:"
echo "  cd $PROJECT"
echo "  npm install"
echo "  npm run test     # runs the unit tests"
echo "  npm run dev      # launches Chrome with the extension"
echo ""
echo "Then in the launched Chrome, visit a page with a <table> and click Extract."
echo "Grep the tree for TODO to see what's left to implement."
