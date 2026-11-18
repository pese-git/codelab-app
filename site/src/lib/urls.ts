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
 */

/**
 * Адрес страницы документа по его пути от корня репозитория (таблица D4).
 *
 * Отображение механическое и обратимое: по адресу видно, какой файл править.
 * Источники `docs/*` не получают второй префикс `docs/`, `README.md` даёт
 * адрес каталога, регистр и подчёркивания сохраняются, слэш на конце —
 * всегда (`trailingSlash: 'always'`).
 */
export function pageUrl(repoPath: string, base: string = '/'): string {
  const withoutExt = repoPath.replace(/\.md$/, '');
  // `README` — страница каталога: так же GitHub показывает README каталога.
  const page = withoutExt === 'README' || withoutExt.endsWith('/README')
    ? withoutExt.slice(0, -'README'.length)
    : `${withoutExt}/`;
  const path = page.startsWith('docs/') ? page : `docs/${page}`;
  return withBase(path, base);
}

/**
 * Внутренний адрес сайта с префиксом `base` (D12).
 *
 * Ведущий слэш [path] отбрасывается: адрес всегда строится от `base`, иначе
 * `/news/` при `base` `/codelab-app/` вёл бы мимо подкаталога. Якорь и
 * остальная часть пути не меняются.
 */
export function withBase(path: string, base: string = '/'): string {
  const prefix = base.endsWith('/') ? base : `${base}/`;
  return `${prefix}${path.replace(/^\/+/, '')}`;
}
