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
