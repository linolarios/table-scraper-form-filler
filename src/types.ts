// [DEV A] Shared contracts. Create/agree on this first — both devs import it.

export interface TableData {
  index: number;
  headers: string[];
  rows: string[][];
  caption: string;
  rowCount: number;
  columnCount: number;
}

export interface DetectedField {
  key: string;        // normalized column name, e.g. "first_name"
  selector: string;   // CSS selector to target the element
  label: string;      // human-readable label from the page
  type: string;       // text | email | select | ...
  detectedBy: string; // 'id' | 'name' | 'selector'
}

export type FieldMapping = Record<string, DetectedField>;

export interface FillPayload {
  data: Record<string, string>[];
  mapping: FieldMapping;
  submitSelector?: string;
  waitForNavigation?: boolean;
  delayBetweenRows?: number;
}

export interface ScrapPayload {
  selector?: string;
}

export interface EventMessage {
  type: 'EVENT';
  event: string;
  payload: Record<string, any>;
  timestamp: number;
}

export interface CommandMessage {
  command: string;
  payload?: Record<string, any>;
}

export interface CommandResponse {
  success: boolean;
  data?: any;
  error?: string;
}
