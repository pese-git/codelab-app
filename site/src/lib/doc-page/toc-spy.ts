/**
 * Выбор текущего заголовка для подсветки оглавления.
 *
 * Почему: `IntersectionObserver` даёт события пересечения, а не «последний
 * заголовок выше линии чтения»; короткие разделы между событиями терялись бы.
 * Пересчёт по кадру проще проверить чистой функцией (design.md
 * improve-docs-navigation, D7).
 *
 * Для чего: DOM-слой `scripts/doc-page/toc-spy.ts` передаёт верхи заголовков
 * `##` и ставит `aria-current="location"` ссылке с найденным индексом.
 *
 * Как использовать: `tops` — `getBoundingClientRect().top` заголовков в порядке
 * документа, `offset` — линия чтения (px от верха окна), `atBottom` — страница
 * прокручена до конца. Результат — индекс или `null` (нет активного).
 */
export function activeHeading(tops: readonly number[], offset: number, atBottom: boolean): number | null {
  if (tops.length === 0) return null;
  // Последний раздел в конце страницы мог не дойти до линии чтения.
  if (atBottom) return tops.length - 1;
  let found: number | null = null;
  for (let i = 0; i < tops.length; i++) {
    if (tops[i] <= offset) found = i;
  }
  return found;
}
