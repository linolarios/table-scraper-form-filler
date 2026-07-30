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
          broadcastEvent(EVENTS.SCRAP_INITIATED);
          const tables = scrapeTablesFromPage(request.payload?.selector ?? null);
          if (!tables.length) {
            broadcastEvent(EVENTS.SCRAP_FINISHED_WRONG, { error: ERROR_CODES.NO_TABLES_FOUND });
            return { success: false, error: ERROR_CODES.NO_TABLES_FOUND };
          }
          broadcastEvent(EVENTS.SCRAP_FINISHED_SUCCESSFULLY, {
            tableCount: tables.length,
            totalRows: tables.reduce((a, t) => a + t.rowCount, 0),
          });
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

        default:
          return { success: false, error: `Unknown command: ${request.command}` };
      }
    }
  },
});
