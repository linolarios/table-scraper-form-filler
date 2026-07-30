// [DEV B] Pure logic — no DOM, no chrome.
import { describe, it, expect } from 'vitest';
import { autoMapColumns } from './csvParser';
import type { DetectedField } from '@/types';

const field = (key: string, label = key): DetectedField => ({
  key, label, selector: `#${key}`, type: 'text', detectedBy: 'id',
});

describe('autoMapColumns', () => {
  const fields = [field('first_name', 'First Name'), field('email', 'Email'), field('phone', 'Phone')];

  it('matches exact normalized names', () => {
    expect(autoMapColumns(['Email'], fields).Email.key).toBe('email');
  });
  it('matches via substring', () => {
    expect(autoMapColumns(['first'], fields).first?.key).toBe('first_name');
  });
  it('matches close typos within Levenshtein distance 2', () => {
    expect(autoMapColumns(['emial'], fields).emial?.key).toBe('email');
  });
  it('leaves unmatched columns out of the mapping', () => {
    expect(autoMapColumns(['zzz_unknown'], fields).zzz_unknown).toBeUndefined();
  });
});
