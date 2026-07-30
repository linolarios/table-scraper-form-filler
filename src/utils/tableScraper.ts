import type {TableData} from '@/types';

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
            // FIX 1: Apply colspan flattening to header extraction
            headerRow.querySelectorAll('th, td').forEach((cell) => {
                const colspan = Math.max(1, parseInt(cell.getAttribute('colspan') || '1', 10));
                const value = cellText(cell);
                for (let i = 0; i < colspan; i++) {
                    headers.push(value);
                }
            });
        }

        // Prefer tbody rows; fall back to all rows. Note: browsers insert an
        // implicit <tbody>, so a headerless table's first row shows up here too —
        // hence we always skip whichever row we used as the header.
        const bodyRows = table.querySelectorAll('tbody tr');
        const dataRows = bodyRows.length ? bodyRows : table.querySelectorAll('tr');

        // Track rowspan: maps column index → { remaining rows, cell text }
        // This is the key data structure for colspan/rowspan flattening.
        const rowspanTracker: Map<number, { remaining: number; value: string }> = new Map();

        dataRows.forEach((row) => {
            if (row === headerRow) return; // never emit the header row as data

            const cells = Array.from(row.querySelectorAll('td, th'));
            const rowData: string[] = [];
            let colIndex = 0;

            // 1. Fill in cells from active rowspans (from previous rows)
            //    We iterate through the tracker entries in column order.
            const sortedTrackerCols = Array.from(rowspanTracker.keys()).sort((a, b) => a - b);
            for (const col of sortedTrackerCols) {
                const entry = rowspanTracker.get(col)!;
                // If there's a gap between current colIndex and this tracker column,
                // advance colIndex to match (inserting empty strings if needed).
                while (colIndex < col) {
                    if (rowData.length <= colIndex) rowData.push('');
                    colIndex++;
                }
                if (colIndex === col && entry.remaining > 0) {
                    rowData.push(entry.value);
                    entry.remaining--;
                    if (entry.remaining <= 0) {
                        rowspanTracker.delete(col);
                    } else {
                        rowspanTracker.set(col, entry);
                    }
                    colIndex++;
                }
            }

            // 2. Process actual <td>/<th> cells in the row
            cells.forEach((cell) => {
                const colspan = Math.max(1, parseInt(cell.getAttribute('colspan') || '1', 10));
                const rowspan = Math.max(1, parseInt(cell.getAttribute('rowspan') || '1', 10));
                const value = cellText(cell);

                // Skip past any columns already filled by an active rowspan
                while (rowData.length > colIndex) {
                    colIndex++;
                }

                // Fill the cell value across all spanned columns
                for (let i = 0; i < colspan; i++) {
                    rowData.push(value);
                    // If cell spans multiple rows, register it for future rows
                    if (rowspan > 1) {
                        rowspanTracker.set(colIndex + i, {remaining: rowspan - 1, value});
                    }
                }
                colIndex += colspan;
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
        // Flattening behavior for colspan/rowspan:
        // - colspan cells have their value duplicated into each spanned column
        // - rowspan cells have their value repeated in each row they span
        // - This ensures all rows have the same column count for CSV/Excel export
        // - Limitation: does not handle 0 as a value for colspan/rowspan (which
        //   HTML spec says means "span to end of table/column group")
    });

    return tables;
}

// innerText reflects *rendered* text but is undefined outside a real browser
// (e.g. under jsdom in tests). Fall back to textContent so the util is testable.
function cellText(cell: Element): string {
    return (((cell as HTMLElement).innerText ?? cell.textContent) ?? '').trim();
}