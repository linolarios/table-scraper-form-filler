import { defineConfig } from 'wxt';

// WXT generates manifest.json from this config + your entrypoints.
// Do NOT hand-write manifest.json.
export default defineConfig({
  srcDir: 'src',
  manifest: {
    name: 'Table Scraper & Form Filler',
    version: '1.0.0',
    description: 'Scrape HTML tables to CSV/Excel and batch-fill forms from a spreadsheet.',
    // activeTab is intentionally omitted: <all_urls> host_permissions already
    // grants what we need, and the pair is redundant.
    permissions: ['scripting', 'downloads', 'storage', 'tabs', 'webNavigation'],
    host_permissions: ['<all_urls>'],
  },
});
