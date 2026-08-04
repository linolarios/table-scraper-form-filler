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

  it('flattens colspan cells', () => {
    document.body.innerHTML = `
      <table>
        <thead><tr><th colspan="2">Wide</th><th>C</th></tr></thead>
        <tbody>
          <tr><td>A</td><td>B</td><td>C</td></tr>
        </tbody>
      </table>`;
    const [t] = scrapeTablesFromPage(null);
    expect(t.headers).toEqual(['Wide', 'Wide', 'C']);
    expect(t.rows).toEqual([['A', 'B', 'C']]);
  });

  it('flattens rowspan cells', () => {
    document.body.innerHTML = `
      <table>
        <thead><tr><th></th><th></th><th></th></tr></thead>
        <tbody>
          <tr><td rowspan="2">Both</td><td>A1</td><td>B1</td></tr>
          <tr><td>A2</td><td>B2</td></tr>
        </tbody>
      </table>`;
    const [t] = scrapeTablesFromPage(null);
    expect(t.rows[0]).toEqual(['Both', 'A1', 'B1']);
    expect(t.rows[1]).toEqual(['Both', 'A2', 'B2']);
  });

  it('handles combined colspan + rowspan', () => {
    document.body.innerHTML = `
      <table>
        <thead><tr><th></th><th></th><th></th></tr></thead>
        <tbody>
          <tr><td rowspan="2" colspan="2">Big</td><td>C1</td></tr>
          <tr><td>C2</td></tr>
        </tbody>
      </table>`;
    const [t] = scrapeTablesFromPage(null);
    expect(t.rows[0]).toEqual(['Big', 'Big', 'C1']);
    expect(t.rows[1]).toEqual(['Big', 'Big', 'C2']);
  });

  it('handles multiple rowspans in same row', () => {
    document.body.innerHTML = `
      <table>
        <thead><tr><th></th><th></th><th></th></tr></thead>
        <tbody>
          <tr><td rowspan="2">A</td><td rowspan="2">B</td><td>C1</td></tr>
          <tr><td>C2</td></tr>
        </tbody>
      </table>`;
    const [t] = scrapeTablesFromPage(null);
    expect(t.rows[0]).toEqual(['A', 'B', 'C1']);
    expect(t.rows[1]).toEqual(['A', 'B', 'C2']);
  });
});