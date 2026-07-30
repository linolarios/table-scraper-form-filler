// [DEV B] DOM logic — runs under jsdom.
import { describe, it, expect, vi } from 'vitest';
import { fillField, fillFormBatch } from './formFiller';
import type { FieldMapping } from '@/types';

describe('fillField', () => {
  it('sets a text value and fires an input event', () => {
    document.body.innerHTML = '<input id="n" type="text">';
    const el = document.getElementById('n') as HTMLInputElement;
    const spy = vi.fn();
    el.addEventListener('input', spy);
    fillField(el, 'Ada', 'text');
    expect(el.value).toBe('Ada');
    expect(spy).toHaveBeenCalled();
  });

  it('does NOT tick a checkbox for falsey strings (the v1 Boolean() bug)', () => {
    document.body.innerHTML = '<input id="c" type="checkbox">';
    const el = document.getElementById('c') as HTMLInputElement;
    for (const v of ['false', 'no', '0', '']) {
      el.checked = false;
      fillField(el, v, 'text');
      expect(el.checked).toBe(false);
    }
  });

  it('ticks a checkbox for truthy strings', () => {
    document.body.innerHTML = '<input id="c" type="checkbox">';
    const el = document.getElementById('c') as HTMLInputElement;
    fillField(el, 'true', 'text');
    expect(el.checked).toBe(true);
  });

  it('throws on file inputs', () => {
    document.body.innerHTML = '<input id="f" type="file">';
    const el = document.getElementById('f') as HTMLInputElement;
    expect(() => fillField(el, 'x', 'text')).toThrow();
  });
});

describe('fillFormBatch', () => {
  const mapping: FieldMapping = {
    name:  { key: 'name',  label: 'Name',  selector: '#name',  type: 'text',  detectedBy: 'id' },
    email: { key: 'email', label: 'Email', selector: '#email', type: 'email', detectedBy: 'id' },
  };
  const data = [{ name: 'A', email: 'a@x.com' }, { name: 'B', email: 'b@x.com' }];
  const setup = () => { document.body.innerHTML = '<input id="name"><input id="email">'; };

  it('fills every field and emits one FILL_ROW_STARTED per row', async () => {
    setup();
    const events: string[] = [];
    const res = await fillFormBatch({ data, mapping } as any, (e) => events.push(e), () => false);
    expect(res.success).toBe(true);
    expect(res.report.filled).toBe(4); // 2 fields x 2 rows
    expect(events.filter((e) => e === 'FILL_ROW_STARTED')).toHaveLength(2);
  });

  it('stops between rows when shouldStop() is true', async () => {
    setup();
    const res = await fillFormBatch({ data, mapping } as any, () => {}, () => true);
    expect(res.success).toBe(false);
    expect((res as any).error.code).toBe('TERMINATED');
  });
});
