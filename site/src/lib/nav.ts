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

/** Таблица D9: префикс пути → группа, в порядке показа. */
const knownGroups: ReadonlyArray<readonly [string, string]> = [
  ['docs/user/', 'Пользователю'],
  ['docs/ops/', 'Эксплуатация'],
  ['apps/codelab_desktop/', 'CodeLab app'],
  ['apps/codelab_cli/', 'codelab'],
  ['apps/codelab_agent/', 'codelab-agent'],
  ['packages/', 'Пакеты'],
];

/** Позиция групп неизвестных приложений: после известных приложений, до пакетов. */
const unknownAppOrder = knownGroups.findIndex(([prefix]) => prefix === 'packages/') - 0.5;

/** Группа и её место в порядке показа. */
function locate(repoPath: string): { title: string; order: number } {
  const index = knownGroups.findIndex(([prefix]) => repoPath.startsWith(prefix));
  if (index !== -1) return { title: knownGroups[index]![1], order: index };
  // Неизвестный источник — группа с именем каталога, а не ошибка сборки:
  // новое приложение не должно ломать сайт (D9). Для `apps/<имя>/…` это
  // каталог приложения, для прочих — второй сегмент пути.
  const segments = repoPath.split('/');
  const title = segments.length > 2 ? segments[1]! : segments[0]!;
  return { title, order: segments[0] === 'apps' ? unknownAppOrder : knownGroups.length };
}

/** Группа навигации документа по его пути (таблица D9). */
export function navGroup(repoPath: string): NavGroup {
  return { title: locate(repoPath).title };
}

function isReadme(repoPath: string): boolean {
  return repoPath === 'README.md' || repoPath.endsWith('/README.md');
}

// Русская локаль ставит кириллицу перед латиницей: «Настройка» раньше «Zed».
const collator = new Intl.Collator('ru');

/** Группы навигации с документами; пустые группы не показываются (D9). */
export function buildNav<T extends NavDoc>(docs: readonly T[]): NavSection<T>[] {
  const groups = new Map<string, { order: number; items: T[] }>();
  for (const doc of docs) {
    const { title, order } = locate(doc.repoPath);
    const group = groups.get(title) ?? { order, items: [] };
    group.items.push(doc);
    groups.set(title, group);
  }
  return [...groups.entries()]
    .sort(([a, x], [b, y]) => x.order - y.order || collator.compare(a, b))
    .map(([title, { items }]) => ({
      title,
      items: [...items].sort(
        (a, b) =>
          Number(isReadme(b.repoPath)) - Number(isReadme(a.repoPath)) ||
          collator.compare(a.title, b.title) ||
          a.repoPath.localeCompare(b.repoPath),
      ),
    }));
}
