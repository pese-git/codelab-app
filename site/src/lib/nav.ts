/**
 * Навигация документации по группам, выведенная из пути файла.
 *
 * Почему: новый документ должен появляться в меню без правки сайта (project-site
 * «Новый документ появляется без правки сайта»), поэтому группа считается по
 * расположению файла, а не по списку страниц (design.md add-astro-site, D9).
 *
 * Для чего: чистые функции для оглавления `/docs/` и бокового меню страниц.
 *
 * Как использовать: `navGroup(repoPath)` — группа одного документа;
 * `buildNav(docs)` — группы в порядке D9 с документами: `README.md` первым,
 * затем по заголовку; пустые группы не возвращаются.
 *
 * Состояние: заглушка красных тестов задачи 3.1 (tasks.md); реализация — 3.2.
 */

/** Группа навигации: заголовок, который видит читатель. */
export interface NavGroup {
  readonly title: string;
}

/** Документ навигации: путь от корня репозитория и заголовок страницы. */
export interface NavDoc {
  readonly repoPath: string;
  readonly title: string;
}

/** Группа с её документами в порядке показа. */
export interface NavSection<T extends NavDoc = NavDoc> {
  readonly title: string;
  readonly items: readonly T[];
}

/** Группа навигации документа по его пути (таблица D9). */
export function navGroup(_repoPath: string): NavGroup {
  throw new Error('not implemented');
}

/** Группы навигации с документами; пустые группы не показываются (D9). */
export function buildNav<T extends NavDoc>(_docs: readonly T[]): NavSection<T>[] {
  throw new Error('not implemented');
}
