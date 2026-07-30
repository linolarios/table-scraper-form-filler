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
