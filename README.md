# Table Scraper & Form Filler


A Manifest V3 Chrome extension that **scrapes HTML tables** from any web page into CSV or Excel, and **batch-fills web forms** from a spreadsheet — all from a single popup.

---

## Features

- **Table Scraper** — Extract one or all `<table>` elements from the current page. Download as CSV (UTF-8 BOM for Excel compatibility) or as a multi-sheet `.xlsx` workbook.
- **Form Filler** — Upload a CSV file, auto-detect form fields on the page, and batch-fill every row with per-row progress tracking. Cancel at any time.
- **Smart Field Mapping** — Column names are fuzzy-matched to detected form fields using Levenshtein distance, so `"first_name"` maps to `"First Name"` automatically.
- **Works Everywhere** — Injected into `<all_urls>` including same-origin iframes.
- **Real-time Progress** — The content script streams progress events (row started, field filled, row submitted) back to the popup for live UI updates.

---

## Architecture

```
┌─────────────┐   chrome.runtime.sendMessage      ┌─────────────────┐
│  Popup UI   │ ───────────({command})────────▶   │ Service Worker  │
│  (2 tabs)   │ ◀──────── CommandResponse ──────  │  (background)   │
└─────────────┘                                   └─────────────────┘
      ▲                                                  │
      │  EVENT broadcasts                                │ chrome.tabs.sendMessage
      │  (runtime.sendMessage)                           ▼
      │                                          ┌─────────────────┐
      └───────────────── EVENTS ──────────────── │  Content Script │
                                                 │  (page DOM +    │
                                                 │   imports utils)│
                                                 └─────────────────┘
```

### Key Components

| Component | File | Role |
|---|---|---|
| **Popup UI** | `src/entrypoints/popup/` | Two-tab interface (Scraper + Form Filler), handles CSV/Excel export, file upload, field mapping, and progress display |
| **Background** | `src/entrypoints/background.ts` | Service worker — validates incoming commands and routes them to the active tab's content script |
| **Content Script** | `src/entrypoints/content.ts` | Injected into `<all_urls>`, owns all DOM work, dispatches to utility modules, and broadcasts typed progress events back to the popup |

### Why a Content Script Instead of `executeScript`?

The content script is declared in the manifest and injected automatically on every page. This means:

- **Persistent state** — The batch fill loop can run across multiple rows without being torn down
- **Real-time progress** — The content script sends `EVENT` messages as each row/field is processed
- **Cancellation** — A `TERMINATE` command sets a flag that the fill loop checks between rows

This would not be possible with one-shot `chrome.scripting.executeScript()` calls.

---

## Project Structure

```
src/
├── types.ts                          # Shared TypeScript interfaces
├── utils/
│   ├── constants.ts                  # Command / event / error enums
│   ├── events.ts                     # broadcastEvent() / listenToEvents()
│   ├── tableScraper.ts               # DOM table extraction logic
│   ├── fieldDetector.ts              # Form field detection + CSS selector generation
│   ├── formFiller.ts                 # Batch fill loop + per-field dispatch
│   ├── csvExporter.ts                # TableData → CSV strings + download
│   ├── csvParser.ts                  # File upload → parsed rows + auto-mapping
│   └── excelExporter.ts              # TableData → .xlsx workbook download
├── entrypoints/
│   ├── background.ts                 # Service worker / command router
│   ├── content.ts                    # Content script / command dispatcher
│   └── popup/
│       ├── index.html                # Popup shell (tabbed layout)
│       ├── main.ts                   # Tab switching + event fan-out
│       ├── scraper-tab.ts            # Scraper tab UI logic
│       ├── filler-tab.ts             # Filler tab UI logic
│       └── style.css                 # Popup styles
```

---

## Quick Start

```bash
# Install dependencies
npm install

# Development — opens Chrome with the extension loaded (hot-reload via WXT)
npm run dev

# Production build
npm run build

# Package for Chrome Web Store upload
npm run zip
```

> **Important:** After installing the extension for the first time, reload any already-open tabs so the content script is injected.

---

## Testing

```bash
# Run all tests (jsdom environment, no browser needed)
npm test

# Watch mode for TDD
npm run test:watch
```

Tests cover:
- `tableScraper.test.ts` — Table extraction from HTML
- `formFiller.test.ts` — Field filling logic
- `csvExporter.test.ts` — CSV generation and escaping
- `csvParser.test.ts` — CSV parsing and fuzzy column mapping

---

## Usage

### Scraper Tab

1. Navigate to any page with HTML tables.
2. Open the extension popup → **Scraper** tab.
3. Click **Extract Tables**.
4. Choose **Download CSV** (one file per table) or **Download Excel** (multi-sheet workbook).

### Form Filler Tab

1. Navigate to a page with a form.
2. Open the extension popup → **Form Filler** tab.
3. Upload a CSV file whose headers match the form fields.
4. Click **Scan Page** to detect form fields and auto-map columns.
5. Review the mapping, then click **Start Batch**.
6. Watch per-row progress — click **Cancel** to stop at any time.

---

## Permissions

| Permission | Purpose |
|---|---|
| `<all_urls>` | Content script injection on every page |
| `scripting` | Reserved for future programmatic injection |
| `downloads` | Save CSV and Excel files |
| `storage` | Persist settings and field mappings |
| `tabs` | Query the active tab for command routing |

---

## Developer Notes

- **colspan/rowspan** — Not yet flattened during scraping. Cells spanning multiple columns/rows are captured as a single cell with the spanning element's text.
- **Multi-row submit-and-reload** — If a form submission triggers a full page navigation, the content script is destroyed and the batch loop stops. A future enhancement could use `chrome.webNavigation.onCompleted` to resume after each reload.
- **File inputs** — Programmatic filling of `<input type="file">` is blocked by browser security. These fields are skipped with an error.
- **Event-driven progress** — The content script uses `chrome.runtime.sendMessage` with `type: 'EVENT'` to broadcast progress. The popup listens for these and dispatches them as `CustomEvent` objects to the relevant tab module.