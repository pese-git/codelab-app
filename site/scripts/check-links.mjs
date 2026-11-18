// Проверка собранного сайта: внутренние ссылки, якоря, сторонние ресурсы,
// личные пути и код `elkjs` в `dist/`.
//
// Почему: плагин `repoLinks` не видит якорей других документов и ссылок
// страниц сайта, а сетевые проверки недетерминированы (design.md
// add-astro-site, D6). Вторая линия защиты D11 (личные пути) и проверка
// лицензий D2 (`elkjs` не попадает в `dist/`) — здесь же.
//
// Для чего: последний шаг `npm run verify` после `astro build`; только модули
// `node:`.
//
// Как использовать: `checkDist({ dist, base, expectedPages })` возвращает
// список нарушений (пустой — всё в порядке); запуск скриптом — задача 3.12.
//
// Состояние: заглушка красных тестов задачи 3.11 (tasks.md); реализация — 3.12.

/**
 * Нарушение проверки: файл сборки (путь от `dist/`), ссылка, если есть, и
 * описание.
 *
 * @typedef {{ file: string, link?: string, message: string }} LinkProblem
 */

/**
 * @param {{ dist: string, base: string, expectedPages?: readonly string[] }} _options
 * @returns {LinkProblem[]}
 */
export function checkDist(_options) {
  throw new Error('not implemented');
}
