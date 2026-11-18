/**
 * Адреса страниц сайта: адрес документа из пути файла и префикс `base`.
 *
 * Почему: хостинг ещё не выбран, и сайт должен работать и в корне домена, и в
 * подкаталоге (design.md add-astro-site, D12). Жёстко прописанный `/docs/…`
 * ломает сборку под `SITE_BASE=/codelab-app/`, а адрес документа, заданный
 * вручную, стал бы вторым источником правды о пути файла (D4).
 *
 * Для чего: единственное место, где строятся внутренние адреса — компоненты,
 * плагин ссылок `repoLinks` (D5) и навигация (D9) вызывают только эти функции.
 *
 * Как использовать: `pageUrl('docs/user/README.md', base)` → `<base>docs/user/`;
 * `withBase('news/', base)` → `<base>news/`. `base` — значение вида `/…/`
 * (`import.meta.env.BASE_URL` в Astro, нормализуется в `astro.config.mjs`).
 *
 * Состояние: заглушка красных тестов задачи 3.1 (tasks.md); реализация — 3.2.
 */

/** Адрес страницы документа по его пути от корня репозитория (таблица D4). */
export function pageUrl(_repoPath: string, _base: string = '/'): string {
  throw new Error('not implemented');
}

/** Внутренний адрес сайта с префиксом `base` (D12). */
export function withBase(_path: string, _base: string = '/'): string {
  throw new Error('not implemented');
}
