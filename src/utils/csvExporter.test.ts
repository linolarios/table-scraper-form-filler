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
