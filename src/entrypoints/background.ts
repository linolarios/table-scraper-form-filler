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
  try {
    // The content script (declared for <all_urls>) does the DOM work and may
    // itself broadcast progress events straight to the popup.
    return await chrome.tabs.sendMessage(tab.id!, request);
  } catch {
    // No receiver = content script not present (e.g. page opened before the
    // extension was installed, or a chrome:// page). Tell the user plainly.
    return { success: false, error: ERROR_CODES.PAGE_NOT_LOADED };
  }
}

async function getActiveTab(): Promise<chrome.tabs.Tab> {
  const [tab] = await chrome.tabs.query({ active: true, currentWindow: true });
  if (!tab?.id) throw new Error('No active tab');
  return tab;
}
