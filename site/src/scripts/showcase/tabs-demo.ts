/**
 * Демо из одних вкладок: переключатель клиентов и галерея.
 *
 * Почему: выбор вкладки не требует автомата — состояние это «какая панель
 * видна» (design.md redesign-site-showcase, D4, D9); шаблон WAI-ARIA общий
 * (`tabs.ts`). Без скрипта все панели идут подряд с заголовками (D2 п. 5).
 *
 * Для чего: корни `[data-demo="clients"]` и `[data-demo="gallery"]`.
 *
 * Как использовать: подключается компонентами `ClientSwitcher.astro` и
 * `Gallery.astro`; корней может не быть.
 */
import { goLive } from './live';
import { initTabs } from './tabs';

for (const root of document.querySelectorAll<HTMLElement>('[data-demo="clients"], [data-demo="gallery"]')) {
  goLive(root);
  initTabs(root);
}
