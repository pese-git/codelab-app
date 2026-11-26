/**
 * Вкладки WAI-ARIA поверх готовой разметки: переключатель клиентов, шаги,
 * режимы, галерея.
 *
 * Почему: один шаблон вместо четырёх (design.md redesign-site-showcase, D2
 * п. 7; project-site «Клавиатура»). Разметка содержит все панели; без скрипта
 * видны все (D2 п. 5), а скрипт скрывает невыбранные.
 *
 * Для чего: корень `[data-tabs]` содержит `[role="tablist"]` с кнопками
 * `[role="tab"]` (`aria-controls` — id панели) и панели `[data-tabpanel]`.
 * Вкладки показывает `goLive` (`live.ts`, `data-live-only`); скрипт ставит роли панелям, связывает
 * `aria-labelledby`, роуминг `tabindex` и `aria-selected`; клавиши — по
 * `nextTabIndex` (`lib/showcase/tabs.ts`).
 *
 * Как использовать: `initTabs(root, onUserSelect)`; `onUserSelect(i)` — выбор
 * посетителя мышью или клавиатурой. Программный `select(i)` его не вызывает и
 * фокус не двигает. Фокус при стрелках переходит на выбранную вкладку —
 * это действие посетителя.
 */
import { nextTabIndex } from '../../lib/showcase/tabs';

export interface Tabs {
  select(index: number): void;
  readonly index: number;
}

export function initTabs(root: HTMLElement, onUserSelect?: (index: number) => void): Tabs | undefined {
  const tablist = root.querySelector<HTMLElement>('[role="tablist"]');
  if (!tablist) return undefined;
  const tabs = [...tablist.querySelectorAll<HTMLElement>('[role="tab"]')];
  const panels = tabs.map((tab) => root.querySelector<HTMLElement>(`#${CSS.escape(tab.getAttribute('aria-controls') ?? '')}`));
  if (tabs.length === 0 || panels.some((panel) => panel === null)) return undefined;

  tabs.forEach((tab, i) => {
    const panel = panels[i]!;
    panel.setAttribute('role', 'tabpanel');
    panel.setAttribute('aria-labelledby', tab.id);
  });

  let current = Math.max(
    0,
    tabs.findIndex((tab) => tab.getAttribute('aria-selected') === 'true'),
  );

  const render = (): void => {
    tabs.forEach((tab, i) => {
      const selected = i === current;
      tab.setAttribute('aria-selected', String(selected));
      tab.tabIndex = selected ? 0 : -1;
      panels[i]!.hidden = !selected;
    });
  };

  const choose = (index: number, byUser: boolean, focus: boolean): void => {
    if (index === current && !focus) return;
    const changed = index !== current;
    current = index;
    render();
    if (focus) tabs[index]!.focus();
    if (byUser && changed) onUserSelect?.(index);
  };

  tabs.forEach((tab, i) => {
    tab.addEventListener('click', () => choose(i, true, false));
    tab.addEventListener('keydown', (event) => {
      const next = nextTabIndex(event.key, i, tabs.length);
      if (next === undefined) return;
      event.preventDefault();
      choose(next, true, true);
    });
  });

  render();
  return {
    select: (index) => {
      if (index >= 0 && index < tabs.length) choose(index, false, false);
    },
    get index() {
      return current;
    },
  };
}
