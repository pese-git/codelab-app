/**
 * Заглушка `elkjs` вместо настоящей библиотеки.
 *
 * Почему: `mermaid` регистрирует раскладку ELK по умолчанию и подгружает
 * `elkjs/lib/elk.bundled.js` динамическим импортом, а лицензия `elkjs`
 * (`EPL-2.0 OR GPL-3.0`) не проходит правило D2: такой код не должен попадать
 * в `dist/` (design.md add-astro-site, D2, D7). Схемы документации ELK не
 * используют.
 *
 * Для чего: `vite.resolve.alias` в `astro.config.mjs` подменяет `elkjs` этим
 * модулем; чанк раскладки ELK из `mermaid` остаётся, но без кода `elkjs`.
 * `check-links` падает, если код `elkjs` всё же оказался в `dist/`.
 *
 * Как использовать: напрямую не импортируется. Схема с раскладкой ELK
 * (`flowchart-elk`, `layout: elk`) получает эту ошибку, и скрипт mermaid
 * показывает под исходником «Схему не удалось отрисовать».
 */
export default class ElkUnavailable {
  constructor() {
    throw new Error('ELK layout is not available on the CodeLab site: use the default dagre layout (D7)');
  }
}
