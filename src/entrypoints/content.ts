// [BOTH] Content script: receives commands, runs DOM work, broadcasts events.
import { COMMANDS, EVENTS, ERROR_CODES } from '@/utils/constants';
import { broadcastEvent } from '@/utils/events';
import { scrapeTablesFromPage } from '@/utils/tableScraper';     // [DEV A]
import { detectFormFields } from '@/utils/fieldDetector';        // [DEV B]
import { fillFormBatch } from '@/utils/formFiller';              // [DEV B]
import type { CommandMessage, CommandResponse } from '@/types';

export default defineContentScript({
  matches: ['<all_urls>'],
  allFrames: true, // best-effort scraping/filling inside same-origin frames
  main() {
    let terminate = false;

    chrome.runtime.onMessage.addListener(
      (request: CommandMessage, _sender, sendResponse) => {
        handle(request).then(sendResponse).catch((err) =>
          sendResponse({ success: false, error: err.message }),
        );
        return true; // async
      },
    );

    async function handle(request: CommandMessage): Promise<CommandResponse> {
      switch (request.command) {
        case COMMANDS.SCRAP: {
          // No events here: scraping is one synchronous pass, so the popup gets
          // everything it needs from this response.
          const tables = scrapeTablesFromPage(request.payload?.selector ?? null);
          if (!tables.length) {
            return { success: false, error: ERROR_CODES.NO_TABLES_FOUND };
          }
          return { success: true, data: tables };
        }

        case COMMANDS.SCAN: {
          const fields = detectFormFields(request.payload?.includeHidden ?? false);
          return { success: true, data: fields };
        }

        case COMMANDS.FILL: {
          terminate = false;
          broadcastEvent(EVENTS.FILL_INITIATED, {
            totalRows: request.payload?.data?.length ?? 0,
          });
          const result = await fillFormBatch(
            request.payload as any,
            broadcastEvent,
            () => terminate,
          );
          if (result.success) {
            broadcastEvent(EVENTS.FILL_FINISHED_SUCCESSFULLY, result.report);
            return { success: true, data: result.report };
          }
          if ((result as any).error?.code === 'TERMINATED') {
            broadcastEvent(EVENTS.FILL_TERMINATED, { progress: (result as any).error });
          } else {
            broadcastEvent(EVENTS.FILL_FINISHED_WRONG, { error: (result as any).error });
          }
          return { success: false, error: (result as any).error?.code };
        }

        case COMMANDS.TERMINATE: {
          terminate = true; // the fill loop checks this between rows
          return { success: true };
        }

        // ── TODO (Option B): pause / skip / retry ────────────────────────────
        // Extend the TERMINATE pattern — do NOT make broadcastEvent await a
        // reply (the popup is often closed mid-batch, so a reply-dependent
        // event would hang). Instead add control commands that flip flags the
        // fill loop polls between rows:
        //   case COMMANDS.PAUSE:  { paused = true;  return { success: true }; }
        //   case COMMANDS.RESUME: { paused = false; return { success: true }; }
        //   case COMMANDS.SKIP:   { skipRow = true; return { success: true }; }
        // Then pass shouldPause()/shouldSkip() into fillFormBatch and have the
        // loop `await` a resume gate between rows. No correlationId needed —
        // the popup sets state, the loop reads it; order is irrelevant.
        // Also add COMMANDS.PAUSE/RESUME/SKIP to constants.ts when you wire this.

        default:
          return { success: false, error: `Unknown command: ${request.command}` };
      }
    }
  },
});
