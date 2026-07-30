// [DEV A] Single source of truth for command / event / error names.

export const COMMANDS = {
  SCRAP: 'scrap',
  SCAN: 'scan',
  FILL: 'fill',
  TERMINATE: 'terminate',
} as const;

export const EVENTS = {
  // Note: the scraper is a single synchronous pass — its result comes back in
  // the CommandResponse, so it needs no events. All events below are the
  // filler's one-way progress broadcast to the popup.
  FILL_INITIATED: 'FILL_INITIATED',
  FILL_ROW_STARTED: 'FILL_ROW_STARTED',
  FILL_FIELD_FILLED: 'FILL_FIELD_FILLED',
  FILL_ROW_SUBMITTED: 'FILL_ROW_SUBMITTED',
  FILL_ROW_FINISHED: 'FILL_ROW_FINISHED',
  FILL_FINISHED_SUCCESSFULLY: 'FILL_FINISHED_SUCCESSFULLY',
  FILL_FINISHED_WRONG: 'FILL_FINISHED_WRONG',
  FILL_TERMINATED: 'FILL_TERMINATED',
} as const;

export const ERROR_CODES = {
  NO_TABLES_FOUND: 'NO_TABLES_FOUND',
  PAGE_NOT_LOADED: 'PAGE_NOT_LOADED',
  PERMISSION_DENIED: 'PERMISSION_DENIED',
  PARSE_ERROR: 'PARSE_ERROR',
  ELEMENT_NOT_FOUND: 'ELEMENT_NOT_FOUND',
  VALIDATION_ERROR: 'VALIDATION_ERROR',
  CAPTCHA_DETECTED: 'CAPTCHA_DETECTED',
  NAVIGATION_TIMEOUT: 'NAVIGATION_TIMEOUT',
  FILE_INPUT_BLOCKED: 'FILE_INPUT_BLOCKED',
  NO_DATA: 'NO_DATA',
  NO_MAPPING: 'NO_MAPPING',
  TIMEOUT: 'TIMEOUT',
} as const;
