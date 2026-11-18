/**
 * Документы коллекции `docs` с заголовком, описанием и адресом страницы.
 *
 * Почему: страницы `/docs/`, `/docs/<путь>/` и навигация берут одни и те же
 * поля; заголовок и описание выводятся из Markdown (`docMeta`, D3), адрес —
 * из пути (`pageUrl`, D4). Считать их в каждой странице заново — три копии
 * одного правила.
 *
 * Для чего: тонкая связка `astro:content` с чистыми функциями `src/lib/`;
 * логика и её тесты — в `doc-meta.ts`, `urls.ts`, `nav.ts`.
 *
 * Как использовать: `await loadDocs()` в frontmatter страницы Astro. Документ
 * без заголовка `#` ломает сборку с путём файла (`DocTitleError`).
 */
import { getCollection, type CollectionEntry } from 'astro:content';

import { docMeta } from './doc-meta';
import { pageUrl } from './urls';

/** Документ сайта: запись коллекции и выведенные поля. */
export interface SiteDoc {
  readonly entry: CollectionEntry<'docs'>;
  /** Путь от корня репозитория — `id` записи (`content.config.ts`). */
  readonly repoPath: string;
  readonly title: string;
  readonly description: string;
  /** Адрес страницы с `base`. */
  readonly url: string;
  /** Параметр маршрута `/docs/[...path]/`: адрес без `<base>docs/` и слэша. */
  readonly routePath: string;
}

/** Все опубликованные документы, упорядоченные по пути. */
export async function loadDocs(): Promise<SiteDoc[]> {
  const base = import.meta.env.BASE_URL;
  const entries = await getCollection('docs');
  return entries
    .map((entry) => {
      const repoPath = entry.id;
      const { title, description } = docMeta(entry.body ?? '', repoPath);
      const url = pageUrl(repoPath, base);
      const routePath = pageUrl(repoPath, '/').replace(/^\/docs\//, '').replace(/\/$/, '');
      return { entry, repoPath, title, description, url, routePath };
    })
    .sort((a, b) => a.repoPath.localeCompare(b.repoPath));
}
