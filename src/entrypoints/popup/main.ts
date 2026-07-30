// [BOTH] Tab switching + event fan-out to each tab module.
import { listenToEvents } from '@/utils/events';
import { initScraperTab } from './scraper-tab';
import { initFillerTab } from './filler-tab';

const tabBtns = document.querySelectorAll<HTMLButtonElement>('.tab-btn');
const tabPanels = document.querySelectorAll<HTMLElement>('.tab-panel');

tabBtns.forEach((btn) => {
  btn.addEventListener('click', () => {
    const target = btn.dataset.tab!;
    tabBtns.forEach((b) => b.classList.toggle('active', b === btn));
    tabPanels.forEach((p) => p.classList.toggle('active', p.id === `tab-${target}`));
  });
});

listenToEvents((event, payload) => {
  // Only the filler broadcasts events (the scraper uses its CommandResponse).
  if (event.startsWith('FILL_')) {
    window.dispatchEvent(new CustomEvent('fill-event', { detail: { event, payload } }));
  }
});

initScraperTab();
initFillerTab();
