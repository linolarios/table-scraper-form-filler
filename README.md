# Table Scraper & Form Filler

Manifest V3 Chrome extension built with WXT + TypeScript.

## Setup
```bash
npm install
npm run dev      # launches Chrome with the extension loaded (.output/chrome-mv3-dev)
npm run build    # production build
npm run zip      # package for the Chrome Web Store
```

## Architecture
Popup → Background (router) → **Content script** (DOM work) → broadcasts events → Popup.

The content script — not `executeScript({ func })` — owns all DOM logic. That is
what lets helper functions, per-row progress events, and Cancel actually work.

> After first install, reload any already-open tabs so the content script is present.

## Ownership
- **Dev A:** scaffolding, background router, shared infra (types/constants/events),
  scraper (`tableScraper`, `csvExporter`, `excelExporter`), popup shell + scraper tab.
- **Dev B:** field detection + filling (`fieldDetector`, `formFiller`, `csvParser`),
  filler tab UI.

Search the tree for `TODO` for the remaining implementation work.
