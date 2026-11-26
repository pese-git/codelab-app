/**
 * Включение «живого» режима демо: элементы управления появляются только со
 * скриптом.
 *
 * Почему: без JavaScript демо показывает полное состояние и ни одной кнопки,
 * которая ничего не делает (design.md redesign-site-showcase, D2 п. 5;
 * project-site «Интерактивные демо витрины», сценарий «Без JavaScript»).
 * Поэтому такие элементы отрисованы с `hidden` и `data-live-only`, а
 * запасная разметка для режима без скрипта помечена `data-nojs`.
 *
 * Для чего: общий вход всех демо; ставит `data-live` на корень — по нему CSS
 * прячет `data-nojs` — и снимает `hidden` с `data-live-only`.
 *
 * Как использовать: `goLive(root)` первым действием скрипта демо. Фокус не
 * переносится (D2 п. 7).
 */
export function goLive(root: HTMLElement): void {
  root.setAttribute('data-live', '');
  for (const element of root.querySelectorAll<HTMLElement>('[data-live-only]')) {
    element.hidden = false;
  }
}

/** `prefers-reduced-motion: reduce` читается один раз при запуске (D2 п. 6). */
export function prefersReducedMotion(): boolean {
  return window.matchMedia('(prefers-reduced-motion: reduce)').matches;
}
