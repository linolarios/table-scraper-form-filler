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
