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
