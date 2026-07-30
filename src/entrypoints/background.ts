// [DEV A] Service worker: routes popup commands to the content script.
import { COMMANDS, ERROR_CODES } from '@/utils/constants';
import type { CommandMessage, CommandResponse } from '@/types';

export default defineBackground(() => {
  chrome.runtime.onMessage.addListener((request: CommandMessage, _sender, sendResponse) => {
    // Ignore EVENT broadcasts flowing back through runtime messaging.
    if ((request as any)?.type === 'EVENT') return false;

    if (!Object.values(COMMANDS).includes(request.command as any)) {
      sendResponse({ success: false, error: `Unknown command: ${request.command}` });
      return false;
    }

    route(request).then(sendResponse).catch((err) =>
      sendResponse({ success: false, error: err.message }),
    );
    return true; // async response
  });
});

async function route(request: CommandMessage): Promise<CommandResponse> {
  const tab = await getActiveTab();

  // Scraping: a table can be in the main doc OR a widget iframe, so ask every
  // frame individually (no race) and merge. Empty frames just return no tables.
  if (request.command === COMMANDS.SCRAP) {
    const frames = (await chrome.webNavigation.getAllFrames({ tabId: tab.id! })) ?? [];
    const settled = await Promise.allSettled(
        frames.map((f) =>
            chrome.tabs.sendMessage(tab.id!, request, { frameId: f.frameId }) as Promise<CommandResponse>,
        ),
    );
    const tables: any[] = [];
    for (const s of settled) {
      if (s.status === 'fulfilled' && s.value?.success && Array.isArray(s.value.data)) {
        tables.push(...s.value.data);
      }
    }
    if (!tables.length) return { success: false, error: ERROR_CODES.PAGE_NOT_LOADED === '' ? '' : 'NO_TABLES_FOUND' };
    tables.forEach((t, i) => (t.index = i)); // re-index across frames
    return { success: true, data: tables };
  }

  // Scan/Fill/Terminate act on one document — target the top frame so an empty
  // ad-iframe can't hijack the response the same way.
  try {
    return await chrome.tabs.sendMessage(tab.id!, request, { frameId: 0 });
  } catch {
    return { success: false, error: ERROR_CODES.PAGE_NOT_LOADED };
  }
}

async function getActiveTab(): Promise<chrome.tabs.Tab> {
  const [tab] = await chrome.tabs.query({ active: true, currentWindow: true });
  if (!tab?.id) throw new Error('No active tab');
  return tab;
}
