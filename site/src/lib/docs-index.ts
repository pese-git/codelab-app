/**
 * Модель оглавления `/docs/` по ролям читателя.
 *
 * Почему: оглавление «по группам» было стеной ссылок (147 пунктов у пакетов),
 * а читатель спрашивает «что мне делать», а не «в каком каталоге файл»
 * (design.md improve-docs-navigation, D6). Блоки выводятся из результата
 * `buildNav` без своих правил группировки: порядок, подгруппы и слои уже
 * заданы D1–D3, поэтому новый документ попадает в оглавление сам.
 *
 * Для чего: чистая модель для `src/pages/docs/index.astro` — три блока
 * «Начать работу», «Пользоваться», «Развернуть и разрабатывать» и внутри
 * последнего блок «Пакеты» по слоям. Документ показывается один раз; у
 * пакета — README, видимый вход руководства и свёрнутые «Главы (N)» (D6
 * «Руководство пакета в карточке»).
 *
 * Как использовать: `buildDocsIndex(buildNav(docs))`; документы должны нести
 * `description` (`SiteDoc`). `id` блоков выводятся из ролей и слоёв
 * (латиница), а не из русских заголовков, чтобы якоря и крошки не ломались
 * от переименования блока.
 */
import {
  entryLabel,
  installDocPath,
  type NavDoc,
  type NavEntry,
  type NavGroupTree,
  type NavList,
  type NavSection,
} from './nav';

/** Документ оглавления: у него есть описание (первый абзац, `docMeta`). */
export interface IndexDoc extends NavDoc {
  readonly description: string;
}

/** Карточка приложения в «Начать работу». */
export interface AppCard<T extends IndexDoc> {
  readonly title: string;
  /** `README.md` приложения; `null`, если его нет. */
  readonly readme: T | null;
  /** `doc/README.md` — «Все документы»; `null`, если его нет. */
  readonly all: T | null;
}

/** Руководство приложения в «Пользоваться»: вход и свёрнутые главы. */
export interface GuideEntry<T extends IndexDoc> {
  readonly title: string;
  readonly entry: T | null;
  readonly chapters: readonly NavEntry<T>[];
}

/** Подгруппы приложения в «Развернуть и разрабатывать». */
export interface BuildApp<T extends IndexDoc> {
  readonly title: string;
  readonly operations: T | null;
  readonly development: { readonly entry: T | null; readonly chapters: readonly NavEntry<T>[] };
  readonly nested: readonly { readonly title: string; readonly items: readonly (NavEntry<T> & { readonly label: string })[] }[];
}

/** Подгруппа глав пакета (`doc/algorithms/`): вход подписан по `entryLabel` (D1). */
export interface PackageGroup<T extends IndexDoc> {
  readonly title: string;
  readonly items: readonly (NavEntry<T> & { readonly label: string })[];
}

/**
 * Пакет в блоке «Пакеты»: ссылка на README, вход руководства и свёрнутые главы.
 *
 * Почему: у пакета была одна ссылка на README, и руководство ядра агента
 * (30 документов) не находилось из `/docs/` (находка пользователя, D6
 * «Руководство пакета в карточке»).
 *
 * Для чего: страница выводит `doc` + `description`, видимую ссылку `guide`
 * и `<details>` «Главы (`chaptersCount`)» из `chapters` и `groups`.
 *
 * Как использовать: поля берутся из секции пакета `buildNav` без своих правил
 * группировки. Каждый документ пакета встречается ровно в одном поле.
 */
export interface PackageCard<T extends IndexDoc> {
  readonly name: string;
  /** README пакета; без README — вход руководства (тогда `guide` — `null`). */
  readonly doc: T;
  readonly description: string;
  /**
   * Вход руководства с номером (`doc/README.md` — номер `null`, первая глава —
   * её номер, например «00»); берётся только из основного списка пакета.
   * `null`: `doc/` нет, основной список пуст или вход занят ссылкой `doc`.
   */
  readonly guide: NavEntry<T> | null;
  /** Главы основного списка без входа руководства. */
  readonly chapters: readonly NavEntry<T>[];
  /** Вложенные подгруппы (`doc/algorithms/`). */
  readonly groups: readonly PackageGroup<T>[];
  /** N в «Главы (N)»: документы `doc/` без входа, включая подгруппы. */
  readonly chaptersCount: number;
}

/** Слой пакетов; `id` — `packages-<слой>` (D6). */
export interface PackageLayerBlock<T extends IndexDoc> {
  readonly id: string;
  readonly title: string;
  readonly packages: readonly PackageCard<T>[];
}

/** Модель оглавления `/docs/`. */
export interface DocsIndex<T extends IndexDoc> {
  readonly start: { readonly id: 'start'; readonly title: string; readonly links: readonly T[]; readonly cards: readonly AppCard<T>[] };
  readonly use: { readonly id: 'use'; readonly title: string; readonly docs: readonly T[]; readonly apps: readonly GuideEntry<T>[] };
  readonly build: {
    readonly id: 'build';
    readonly title: string;
    readonly docs: readonly T[];
    readonly apps: readonly BuildApp<T>[];
    readonly packages: { readonly id: 'packages'; readonly title: string; readonly layers: readonly PackageLayerBlock<T>[] };
  };
}

/** Секции приложений — все секции с корнем `apps/…`, включая неизвестные приложения. */
function appSections<T extends IndexDoc>(nav: readonly NavGroupTree<T>[]): NavSection<T>[] {
  return nav.flatMap((group) => group.sections.filter((s) => s.key.startsWith('apps/')));
}

const listOf = <T extends IndexDoc>(section: NavSection<T>, kind: NavList<T>['kind']) =>
  section.lists.find((l) => l.kind === kind);

/** Делит список на вход (файл с рангом 0 по имени `entryFile`) и главы. */
function splitEntry<T extends IndexDoc>(list: NavList<T> | undefined, entryFile: string) {
  const items = list?.items ?? [];
  const entry = items.find((e) => e.doc.repoPath.endsWith(`/${entryFile}`))?.doc ?? null;
  return { entry, chapters: items.filter((e) => e.doc !== entry) };
}

/**
 * Карточка пакета из его секции `buildNav` (D6): без своих правил группировки.
 *
 * Основной список секции уже упорядочен D1: `README.md`, `doc/README.md`, главы.
 * Вход руководства — `doc/README.md`, без него первая глава `doc/` (основного
 * списка, иначе подгруппы). Пакет без README ведёт карточку на вход руководства,
 * отдельной ссылки на него нет — документ показан один раз.
 */
function packageCard<T extends IndexDoc>(section: NavSection<T>): PackageCard<T> {
  const main = listOf(section, 'main')?.items ?? [];
  const nested = section.lists.filter((l) => l.kind === 'nested');
  const readme = main.find((e) => e.doc.repoPath === `${section.key}README.md`)?.doc ?? null;
  const docEntries = main.filter((e) => e.doc !== readme);
  // Правило (а): вход — только из основного списка (`doc/README.md`, иначе первая
  // глава верхнего уровня). Пустой основной список — входа нет, подгруппы целые.
  const mainEntry =
    docEntries.find((e) => e.doc.repoPath === `${section.key}doc/README.md`) ?? docEntries[0] ?? null;
  // Без README и без основного списка карточка ведёт на первый пункт первой
  // подгруппы; из подгруппы он исключается — документ показан один раз.
  const nestedFirst = readme === null && mainEntry === null ? (nested[0]?.items[0] ?? null) : null;
  const rest = docEntries.filter((e) => e !== mainEntry);
  const groups = nested
    .map((list): PackageGroup<T> => ({
      title: list.title ?? '',
      items: list.items.filter((e) => e !== nestedFirst).map((e) => ({ ...e, label: entryLabel(e, list, section) })),
    }))
    .filter((g) => g.items.length > 0);
  const first = readme ?? mainEntry?.doc ?? nestedFirst?.doc ?? main[0]!.doc;
  return {
    name: section.title,
    doc: first,
    description: first.description,
    guide: readme !== null ? mainEntry : null,
    chapters: rest,
    groups,
    chaptersCount: rest.length + groups.reduce((n, g) => n + g.items.length, 0),
  };
}

/** Строит модель оглавления из дерева `buildNav` (D6). */
export function buildDocsIndex<T extends IndexDoc>(nav: readonly NavGroupTree<T>[]): DocsIndex<T> {
  const userDocs = nav.flatMap((g) => g.sections).find((s) => s.key === 'docs/user/')?.lists.flatMap((l) => l.items.map((e) => e.doc)) ?? [];
  const opsDocs = nav.flatMap((g) => g.sections).find((s) => s.key === 'docs/ops/')?.lists.flatMap((l) => l.items.map((e) => e.doc)) ?? [];
  const install = userDocs.find((doc) => doc.repoPath === installDocPath);
  const userReadme = userDocs.find((doc) => doc.repoPath === 'docs/user/README.md');
  const apps = appSections(nav);

  const cards = apps
    .map((section): AppCard<T> => {
      const entry = listOf(section, 'entry')?.items ?? [];
      return {
        title: section.title,
        readme: entry.find((e) => e.doc.repoPath === `${section.key}README.md`)?.doc ?? null,
        all: entry.find((e) => e.doc.repoPath === `${section.key}doc/README.md`)?.doc ?? null,
      };
    })
    .filter((card) => card.readme !== null || card.all !== null);

  const guides = apps.flatMap((section): GuideEntry<T>[] => {
    const guide = listOf(section, 'guide');
    return guide ? [{ title: section.title, ...splitEntry(guide, 'user-guide.md') }] : [];
  });

  const buildApps = apps.flatMap((section): BuildApp<T>[] => {
    const operations = listOf(section, 'operations')?.items[0]?.doc ?? null;
    const development = splitEntry(listOf(section, 'development'), 'development.md');
    const nested = section.lists.filter((l) => l.kind === 'nested').map((l) => ({
      title: l.title ?? '',
      items: l.items.map((entry) => ({ ...entry, label: entryLabel(entry, l, section) })),
    }));
    if (!operations && development.entry === null && development.chapters.length === 0 && nested.length === 0) return [];
    return [{ title: section.title, operations, development, nested }];
  });

  const packageSections = nav.flatMap((g) => g.sections).filter((s) => s.layer !== null);
  const layers: { id: string; title: string; packages: PackageCard<T>[] }[] = [];
  for (const section of packageSections) {
    const card = packageCard(section);
    const layer = section.layer!;
    let block = layers.find((l) => l.id === `packages-${layer.id}`);
    if (!block) {
      block = { id: `packages-${layer.id}`, title: layer.title, packages: [] };
      layers.push(block);
    }
    block.packages.push(card);
  }

  const shownInStart = new Set([install?.repoPath, userReadme?.repoPath]);
  return {
    start: {
      id: 'start',
      title: 'Начать работу',
      links: [install, userReadme].filter((doc): doc is T => doc !== undefined),
      cards,
    },
    use: {
      id: 'use',
      title: 'Пользоваться',
      docs: userDocs.filter((doc) => !shownInStart.has(doc.repoPath)),
      apps: guides,
    },
    build: {
      id: 'build',
      title: 'Развернуть и разрабатывать',
      docs: opsDocs,
      apps: buildApps,
      packages: { id: 'packages', title: 'Пакеты', layers },
    },
  };
}
