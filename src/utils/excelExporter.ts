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
