/**
 * Клавиатурная логика вкладок WAI-ARIA.
 *
 * Почему: переключатели витрины (клиенты, шаги, режимы, галерея) — шаблон
 * вкладок: стрелки, Home и End (design.md redesign-site-showcase, D2 п. 7;
 * project-site «Интерактивные демо витрины», сценарий «Клавиатура»). Правило
 * выбора соседней вкладки вынесено из DOM, чтобы vitest проверял его без
 * браузера (D2 п. 4).
 *
 * Для чего: единая функция для `src/scripts/showcase/tabs.ts`; активация
 * автоматическая — фокус и выбор идут вместе (макет сразу показывает клиента).
 *
 * Как использовать: `nextTabIndex(event.key, текущая, число)` возвращает индекс
 * вкладки, которую надо выбрать и сфокусировать, или `undefined`, если клавиша
 * к вкладкам не относится и событие нельзя отменять.
 */
export function nextTabIndex(key: string, current: number, count: number): number | undefined {
  if (count <= 0) return undefined;
  switch (key) {
    case 'ArrowRight':
      return (current + 1) % count;
    case 'ArrowLeft':
      return (current - 1 + count) % count;
    case 'Home':
      return 0;
    case 'End':
      return count - 1;
    default:
      return undefined;
  }
}
