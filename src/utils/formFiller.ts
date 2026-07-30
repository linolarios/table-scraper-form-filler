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
