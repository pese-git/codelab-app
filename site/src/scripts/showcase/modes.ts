/**
 * Вкладки режимов разрешений: выбранный режим объявляется читателю.
 *
 * Почему: значения ячеек берутся при сборке из таблицы документа (design.md
 * redesign-site-showcase, D5, D6), а скрипт лишь переключает панели. Выбор
 * режима — действие посетителя, поэтому его итог объявляется в области
 * `aria-live="polite"` готовой фразой (D2 п. 7).
 *
 * Для чего: корень `[data-demo="modes"]`; без скрипта видна таблица целиком.
 *
 * Как использовать: подключается компонентом `ModesDemo.astro`; фраза режима
 * лежит в `data-phrase` панели, собранная на сервере.
 */
import { goLive } from './live';
import { initTabs } from './tabs';

for (const root of document.querySelectorAll<HTMLElement>('[data-demo="modes"]')) {
  goLive(root);
  const announce = root.querySelector<HTMLElement>('[data-announce]');
  const panels = [...root.querySelectorAll<HTMLElement>('[data-tabpanel]')];
  initTabs(root, (index) => {
    if (announce) announce.textContent = panels[index]?.dataset.phrase ?? '';
  });
}
