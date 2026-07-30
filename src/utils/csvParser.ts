// [DEV B] CSV parsing + fuzzy column matching. Runs in the POPUP.
import Papa from 'papaparse';
import type { DetectedField, FieldMapping } from '@/types';

export function parseCSV(file: File): Promise<Record<string, string>[]> {
  return new Promise((resolve, reject) => {
    Papa.parse<Record<string, string>>(file, {
      header: true,
      skipEmptyLines: true,
      complete: (results) => resolve(results.data),
      error: (err) => reject(err),
    });
  });
}

export function autoMapColumns(csvHeaders: string[], detectedFields: DetectedField[]): FieldMapping {
  const mapping: FieldMapping = {};
  csvHeaders.forEach((header) => {
    const nh = normalize(header);
    const match = detectedFields.find((f) => {
      const nk = normalize(f.key);
      const nl = normalize(f.label);
      return nk === nh || nl === nh || nk.includes(nh) || nh.includes(nk) || levenshtein(nk, nh) <= 2;
    });
    if (match) mapping[header] = match;
  });
  return mapping;
}

function normalize(str: string): string {
  return str.toLowerCase().replace(/[^a-z0-9]/g, '');
}

function levenshtein(a: string, b: string): number {
  const m: number[][] = [];
  for (let i = 0; i <= a.length; i++) m[i] = [i];
  for (let j = 0; j <= b.length; j++) m[0][j] = j;
  for (let i = 1; i <= a.length; i++) {
    for (let j = 1; j <= b.length; j++) {
      m[i][j] = a[i - 1] === b[j - 1]
        ? m[i - 1][j - 1]
        : Math.min(m[i - 1][j - 1], m[i][j - 1], m[i - 1][j]) + 1;
    }
  }
  return m[a.length][b.length];
}
