// [DEV B] Field detection. Imported and called by the content script.
import type { DetectedField } from '@/types';

export function detectFormFields(includeHidden: boolean): DetectedField[] {
  const fields: DetectedField[] = [];
  const patterns: Array<{ sel: string; type: string }> = [
    { sel: 'input[type="text"]', type: 'text' },
    { sel: 'input[type="email"]', type: 'email' },
    { sel: 'input[type="tel"]', type: 'tel' },
    { sel: 'input[type="number"]', type: 'number' },
    { sel: 'input[type="password"]', type: 'password' },
    { sel: 'input[type="date"]', type: 'date' },
    { sel: 'input:not([type])', type: 'text' }, // inputs default to text
    { sel: 'textarea', type: 'textarea' },
    { sel: 'select', type: 'select' },
  ];

  patterns.forEach(({ sel, type }) => {
    document.querySelectorAll(sel).forEach((el, idx) => {
      const input = el as HTMLInputElement | HTMLTextAreaElement | HTMLSelectElement;
      if (!includeHidden && input.offsetParent === null) return;

      const label = findLabel(input);
      const key = normalizeKey(label, input.name, input.id, (input as any).placeholder, idx);

      fields.push({
        key,
        selector: generateSelector(input),
        label,
        type,
        detectedBy: input.id ? 'id' : input.name ? 'name' : 'selector',
      });
    });
  });

  return fields;
}

function findLabel(input: HTMLElement): string {
  if (input.id) {
    const label = document.querySelector(`label[for="${CSS.escape(input.id)}"]`);
    if (label) return label.textContent?.trim() || '';
  }
  const parent = input.closest('label');
  if (parent) return parent.textContent?.trim() || '';
  return input.getAttribute('aria-label') || (input as any).placeholder || (input as any).name || 'Unlabeled';
}

function normalizeKey(label: string, name: string, id: string, placeholder: string, idx: number): string {
  const raw = label || name || id || placeholder || `field_${idx}`;
  return raw.toLowerCase().replace(/[^a-z0-9]/g, '_').replace(/_+/g, '_').replace(/^_|_$/g, '');
}

// Prefer a *unique* selector. Escape ids/names. Fall back to :nth-of-type.
function generateSelector(el: Element): string {
  if (el.id) return `#${CSS.escape(el.id)}`;
  const name = (el as any).name as string | undefined;
  if (name) {
    const sel = `${el.tagName.toLowerCase()}[name="${CSS.escape(name)}"]`;
    if (document.querySelectorAll(sel).length === 1) return sel;
  }
  // TODO [DEV B]: harden this. nth-of-type within the closest form is a decent start.
  const tag = el.tagName.toLowerCase();
  const siblings = Array.from(document.querySelectorAll(tag));
  const i = siblings.indexOf(el);
  return `${tag}:nth-of-type(${i + 1})`;
}
