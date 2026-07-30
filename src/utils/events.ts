// [DEV A] Event broadcast + listen helpers.
import type { EventMessage } from '@/types';

export function broadcastEvent(event: string, payload: Record<string, any> = {}) {
  const message: EventMessage = { type: 'EVENT', event, payload, timestamp: Date.now() };
  // If no popup is open, sendMessage rejects with "Receiving end does not
  // exist" — that's expected, so we swallow it.
  chrome.runtime.sendMessage(message).catch(() => {});
}

export function listenToEvents(cb: (event: string, payload: any) => void) {
  chrome.runtime.onMessage.addListener((msg) => {
    if (msg?.type === 'EVENT') cb(msg.event, msg.payload);
  });
}
