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
