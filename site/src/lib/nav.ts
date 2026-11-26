/**
 * Навигация документации: группы, секции, списки, порядок глав, слои пакетов,
 * крошки и соседние документы — всё выводится из пути файла.
 *
 * Почему: новый документ должен появляться в меню без правки сайта (project-site
 * «Новый документ появляется без правки сайта»), поэтому группа, подгруппа и
 * место в порядке считаются по расположению и имени файла, а не по списку
 * страниц или frontmatter (design.md add-astro-site, D3, D9; design.md
 * improve-docs-navigation, D1–D5). Номер главы уже есть в имени файла
 * (`NN-<тема>.md`, `codelab-docs` §3), а оглавления документов не разбираются:
 * переписанное оглавление не должно молча менять меню (D1).
 *
 * Для чего: чистые функции без `astro:*` и `document` для оглавления `/docs/`
 * (`docs-index.ts`) и страницы документа (меню секции, крошки, «Назад / Далее»).
 *
 * Как использовать: `buildNav(docs)` — дерево «группа → секция → список → запись»;
 * `breadcrumbs(nav, repoPath, base)` и `neighbours(nav, repoPath, base)` —
 * ссылки страницы документа, адреса строятся `pageUrl` и `withBase`.
 * Файл вне правил (новое приложение, новый каталог, имя без номера) попадает
 * в общий порядок и не ломает сборку (D1, D2).
 */
import { pageUrl, withBase } from './urls';

/** Группа навигации: заголовок, который видит читатель. */
export interface NavGroup {
  readonly title: string;
}

/** Документ навигации: путь от корня репозитория и заголовок страницы. */
export interface NavDoc {
  readonly repoPath: string;
  readonly title: string;
}

/** Путь документа «Установка и быстрый старт»: его читают шапка, страница и `/docs/` (D6). */
export const installDocPath = 'docs/user/run-from-source.md';

/** Слой пакета (D3): стабильный `id` для якоря и название для читателя. */
export interface PackageLayer {
  readonly id: string;
  readonly title: string;
}

/** Слои пакетов в порядке показа (D3). */
export const packageLayers: readonly PackageLayer[] = [
  { id: 'acp', title: 'Протокол ACP' },
  { id: 'client', title: 'Клиент' },
  { id: 'agent', title: 'Агент' },
  { id: 'shared', title: 'Мосты и служебные пакеты' },
  { id: 'flutter', title: 'Интерфейс Flutter' },
  { id: 'checks', title: 'Проверки' },
  { id: 'other', title: 'Другие пакеты' },
];

/** Запись списка: документ и номер главы (`03`) из имени файла, если он есть. */
export interface NavEntry<T extends NavDoc = NavDoc> {
  readonly doc: T;
  readonly number: string | null;
}

/** Вид списка внутри секции (D2). */
export type NavListKind = 'entry' | 'main' | 'guide' | 'operations' | 'development' | 'nested';

/** Список секции: вход, основной список или подгруппа с заголовком. */
export interface NavList<T extends NavDoc = NavDoc> {
  readonly kind: NavListKind;
  /** Заголовок подгруппы; у входа и основного списка — `null`. */
  readonly title: string | null;
  readonly items: readonly NavEntry<T>[];
}

/**
 * Секция — то, что показывает меню одной страницы (D2): группа целиком
 * (`docs/user/`, `docs/ops/`, приложение) или один пакет.
 */
export interface NavSection<T extends NavDoc = NavDoc> {
  /** Корень секции — префикс пути с завершающим слэшем (`apps/codelab_cli/`). */
  readonly key: string;
  /** Название секции: группа или, у пакета, имя каталога. */
  readonly title: string;
  /** Слой — только у пакетов (D3). */
  readonly layer: PackageLayer | null;
  readonly lists: readonly NavList<T>[];
}

/** Группа верхнего уровня (таблица D9 add-astro-site) с секциями. */
export interface NavGroupTree<T extends NavDoc = NavDoc> {
  readonly title: string;
  readonly sections: readonly NavSection<T>[];
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

const packagesGroupTitle = 'Пакеты';

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

/**
 * Номер главы — префикс `NN-` имени файла, как написан (`03`), либо `null` (D1).
 *
 * Только имя файла: номер каталога (`03-dir/x.md`) главой не считается.
 */
export function chapterNumber(repoPath: string): string | null {
  const name = repoPath.slice(repoPath.lastIndexOf('/') + 1);
  return /^(\d+)-/.exec(name)?.[1] ?? null;
}

/**
 * Слой пакета по пути и имени каталога (ADR-0002, D3), без списка пакетов.
 *
 * `codelab_*_tests` проверяется первым: сторож — не мост и не сторона протокола,
 * а пакет, который следующим `_tests` подхватится без правки сайта.
 */
export function packageLayer(repoPath: string): PackageLayer {
  const [, category = '', name = ''] = repoPath.split('/');
  const id =
    /^codelab_.+_tests$/.test(name) ? 'checks'
    : category === 'dart' ? (
      name.startsWith('codelab_acp_') ? 'acp'
      : name.startsWith('codelab_client_') ? 'client'
      : name.startsWith('codelab_agent_') ? 'agent'
      : 'shared'
    )
    : category === 'flutter' ? 'flutter'
    : 'other';
  return packageLayers.find((layer) => layer.id === id)!;
}

// Русская локаль ставит кириллицу перед латиницей: «Настройка» раньше «Zed».
const collator = new Intl.Collator('ru');

/** Размещение документа: секция, вид списка и путь относительно корня секции. */
interface Placement {
  readonly groupTitle: string;
  readonly groupOrder: number;
  readonly key: string;
  readonly sectionTitle: string;
  readonly layer: PackageLayer | null;
  readonly kind: NavListKind;
  /** Каталог вложенной подгруппы (`algorithms`) — только у `nested`. */
  readonly dir: string | null;
  /** Путь относительно корня секции. */
  readonly rel: string;
}

/** Корень секции: префикс пути с завершающим слэшем. */
function sectionKey(repoPath: string, groupTitle: string): string {
  const segments = repoPath.split('/');
  const known = knownGroups.find(([prefix]) => repoPath.startsWith(prefix));
  if (known && known[0] !== 'packages/') return known[0];
  if (segments[0] === 'packages') {
    // `packages/<каталог>/<пакет>/…`; короче — всё равно одна секция без ошибки.
    return segments.length >= 4 ? `${segments.slice(0, 3).join('/')}/` : 'packages/';
  }
  if (segments[0] === 'apps' && segments.length > 2) return `apps/${segments[1]}/`;
  return segments.length > 2 ? `${segments[0]}/${segments[1]}/` : `${groupTitle}/`;
}

/** Вид списка и каталог подгруппы по пути относительно корня секции (таблица D2). */
function classify(repoPath: string, rel: string): { kind: NavListKind; dir: string | null } {
  const parts = rel.split('/');
  if (repoPath.startsWith('apps/')) {
    if (rel === 'README.md' || rel === 'doc/README.md') return { kind: 'entry', dir: null };
    if (rel === 'doc/user-guide.md' || rel.startsWith('doc/user/')) return { kind: 'guide', dir: null };
    if (rel === 'doc/operations.md') return { kind: 'operations', dir: null };
    if (parts[0] === 'doc' && parts.length >= 3) return { kind: 'nested', dir: parts[1]! };
    // Неизвестный файл приложения — «Для разработчика», а не ошибка (D2).
    return { kind: 'development', dir: null };
  }
  if (repoPath.startsWith('packages/')) {
    if (parts[0] === 'doc' && parts.length >= 3) return { kind: 'nested', dir: parts[1]! };
    return { kind: 'main', dir: null };
  }
  // `docs/user/`, `docs/ops/` и неизвестные источники: каталог первого уровня.
  if (parts.length >= 2) return { kind: 'nested', dir: parts[0]! };
  return { kind: 'main', dir: null };
}

function place(repoPath: string): Placement {
  const { title: groupTitle, order: groupOrder } = locate(repoPath);
  const key = sectionKey(repoPath, groupTitle);
  const rel = repoPath.startsWith(key) ? repoPath.slice(key.length) : repoPath;
  const isPackage = groupTitle === packagesGroupTitle;
  const { kind, dir } = classify(repoPath, rel);
  const sectionTitle = isPackage ? (key.split('/')[2] ?? groupTitle) : groupTitle;
  return { groupTitle, groupOrder, key, sectionTitle, layer: isPackage ? packageLayer(repoPath) : null, kind, dir, rel };
}

/** Ранг входа списка: 0 — первый, 1 — второй, `null` — без ранга (D1, п. 1). */
function entryRank(rel: string, kind: NavListKind, dir: string | null): number | null {
  if (rel === 'README.md') return 0;
  if (rel === 'doc/README.md') return 1;
  if (kind === 'guide' && rel === 'doc/user-guide.md') return 0;
  if (kind === 'development' && rel === 'doc/development.md') return 0;
  if (kind === 'nested' && (rel === `${dir}/README.md` || rel === `doc/${dir}/README.md`)) return 0;
  return null;
}

/** Порядок видов списков внутри секции (D2). */
const listOrder: Readonly<Record<NavListKind, number>> = {
  entry: 0,
  main: 0,
  guide: 1,
  operations: 2,
  development: 3,
  nested: 4,
};

const listTitles: Partial<Record<NavListKind, string>> = {
  guide: 'Руководство',
  operations: 'Эксплуатация',
  development: 'Для разработчика',
};

interface Placed<T extends NavDoc> {
  readonly doc: T;
  readonly place: Placement;
  readonly rank: number | null;
  readonly number: string | null;
}

/** Ключ порядка D1: ранг входа → номер (числом) → заголовок → путь. */
function compareDocs<T extends NavDoc>(a: Placed<T>, b: Placed<T>): number {
  const rank = (a.rank ?? Infinity) - (b.rank ?? Infinity);
  if (rank !== 0 && !Number.isNaN(rank)) return rank;
  const number = (a.number === null ? Infinity : Number(a.number)) - (b.number === null ? Infinity : Number(b.number));
  if (number !== 0 && !Number.isNaN(number)) return number;
  return collator.compare(a.doc.title, b.doc.title) || a.doc.repoPath.localeCompare(b.doc.repoPath);
}

/** Строит дерево навигации; пустые группы и секции не возвращаются (D9, D1–D3). */
export function buildNav<T extends NavDoc>(docs: readonly T[]): NavGroupTree<T>[] {
  const placed: Placed<T>[] = docs.map((doc) => {
    const p = place(doc.repoPath);
    return { doc, place: p, rank: entryRank(p.rel, p.kind, p.dir), number: chapterNumber(doc.repoPath) };
  });

  const groups = new Map<string, { order: number; sections: Map<string, Placed<T>[]> }>();
  for (const item of placed) {
    const group = groups.get(item.place.groupTitle) ?? { order: item.place.groupOrder, sections: new Map() };
    const bucket = group.sections.get(item.place.key) ?? [];
    bucket.push(item);
    group.sections.set(item.place.key, bucket);
    groups.set(item.place.groupTitle, group);
  }

  const layerIndex = (section: NavSection<T>) =>
    section.layer ? packageLayers.findIndex((layer) => layer.id === section.layer!.id) : 0;

  return [...groups.entries()]
    .sort(([a, x], [b, y]) => x.order - y.order || collator.compare(a, b))
    .map(([title, { sections }]) => ({
      title,
      sections: [...sections.values()]
        .map((items) => buildSection(items))
        .sort((a, b) => layerIndex(a) - layerIndex(b) || collator.compare(a.title, b.title) || a.key.localeCompare(b.key)),
    }));
}

function buildSection<T extends NavDoc>(items: readonly Placed<T>[]): NavSection<T> {
  const first = items[0]!.place;
  const buckets = new Map<string, Placed<T>[]>();
  for (const item of items) {
    const id = item.place.kind === 'nested' ? `nested:${item.place.dir}` : item.place.kind;
    const bucket = buckets.get(id) ?? [];
    bucket.push(item);
    buckets.set(id, bucket);
  }
  const lists = [...buckets.values()].map((bucket): NavList<T> => {
    const { kind, dir } = bucket[0]!.place;
    const sorted = [...bucket].sort(compareDocs);
    // Заголовок подгруппы — `#` её README.md; без README — имя каталога (D2).
    const title =
      kind === 'nested' ? (bucket.find((x) => x.rank === 0)?.doc.title ?? dir ?? '') : (listTitles[kind] ?? null);
    return { kind, title, items: sorted.map((x) => ({ doc: x.doc, number: x.number })) };
  });
  lists.sort((a, b) => listOrder[a.kind] - listOrder[b.kind] || collator.compare(a.title ?? '', b.title ?? ''));
  return { key: first.key, title: first.sectionTitle, layer: first.layer, lists };
}

/** Все записи секции в порядке показа. */
export function sectionDocs<T extends NavDoc>(section: NavSection<T>): NavEntry<T>[] {
  return section.lists.flatMap((list) => list.items);
}

/** Где в дереве стоит документ. */
interface Location<T extends NavDoc> {
  readonly group: NavGroupTree<T>;
  readonly section: NavSection<T>;
  readonly list: NavList<T>;
  readonly index: number;
}

/** Находит документ в дереве по пути файла. */
export function locateDoc<T extends NavDoc>(nav: readonly NavGroupTree<T>[], repoPath: string): Location<T> | null {
  for (const group of nav) {
    for (const section of group.sections) {
      for (const list of section.lists) {
        const index = list.items.findIndex((entry) => entry.doc.repoPath === repoPath);
        if (index !== -1) return { group, section, list, index };
      }
    }
  }
  return null;
}

/** Пункт «хлебных крошек». */
export interface Crumb {
  readonly label: string;
  readonly href: string;
}

/**
 * «Хлебные крошки» страницы документа по таблице D5.
 *
 * Уровень без своего документа ведёт на первый документ уровня; уровень,
 * который ведёт на текущую страницу, пропускается: её называет заголовок
 * сразу под крошками. Вход и основной список крошек не дают — у них нет
 * названия.
 */
export function breadcrumbs<T extends NavDoc>(nav: readonly NavGroupTree<T>[], repoPath: string, base: string): Crumb[] {
  const where = locateDoc(nav, repoPath);
  if (!where) return [];
  const { group, section, list } = where;
  const levels: Crumb[] = [{ label: 'Документация', href: withBase('docs/', base) }];
  const all = sectionDocs(section);
  const readme = all.find((entry) => entry.doc.repoPath === `${section.key}README.md`)?.doc ?? all[0]!.doc;

  if (group.title === packagesGroupTitle) {
    // Группа «Пакеты» не имеет своего документа: ведёт на блок оглавления.
    levels.push({ label: group.title, href: withBase('docs/#packages', base) });
    levels.push({ label: section.title, href: pageUrl(readme.repoPath, base) });
  } else {
    levels.push({ label: group.title, href: pageUrl(readme.repoPath, base) });
  }
  if (list.kind !== 'entry' && list.kind !== 'main') {
    levels.push({ label: list.title ?? '', href: pageUrl(list.items[0]!.doc.repoPath, base) });
  }
  const current = pageUrl(repoPath, base);
  return levels.filter((crumb) => crumb.href !== current);
}

/** Соседний документ для «Назад / Далее». */
export interface Neighbour {
  readonly repoPath: string;
  readonly title: string;
  readonly number: string | null;
  readonly href: string;
}

/**
 * Предыдущий и следующий документ того же списка (D5).
 *
 * Только в пределах списка: переход из руководства пользователя в главы
 * разработчика был бы сменой аудитории без предупреждения.
 */
export function neighbours<T extends NavDoc>(
  nav: readonly NavGroupTree<T>[],
  repoPath: string,
  base: string,
): { prev: Neighbour | null; next: Neighbour | null } {
  const where = locateDoc(nav, repoPath);
  if (!where) return { prev: null, next: null };
  const toNeighbour = (entry: NavEntry<T> | undefined): Neighbour | null =>
    entry
      ? {
          repoPath: entry.doc.repoPath,
          title: entry.doc.title,
          number: entry.number,
          href: pageUrl(entry.doc.repoPath, base),
        }
      : null;
  return {
    prev: toNeighbour(where.list.items[where.index - 1]),
    next: toNeighbour(where.list.items[where.index + 1]),
  };
}

/**
 * Подпись записи в меню: вход, повторяющий название, показывается как «Обзор».
 *
 * Почему: у пакета `codelab_setup` заголовок меню и первая ссылка — одно
 * `codelab_setup`, у подгруппы «Алгоритмы ядра агента» — то же с её README;
 * читатель видит повтор (D1, D2 improve-docs-navigation). Заголовок страницы
 * не меняется — только подпись в меню.
 *
 * Для чего: единая подпись для меню секции и подгрупп `/docs/`.
 *
 * Как использовать: `entryLabel(entry, list, section)`. «Обзор» подставляется,
 * когда заголовок документа равен заголовку подгруппы (`nested`) или названию
 * секции и в списке нет другого документа с названием «Обзор».
 */
export function entryLabel<T extends NavDoc>(entry: NavEntry<T>, list: NavList<T>, section: NavSection<T>): string {
  const owner = list.kind === 'nested' ? list.title : section.title;
  const title = entry.doc.title;
  if (owner === null || title.trim().toLowerCase() !== owner.trim().toLowerCase()) return title;
  // Оба сравнения без учёта регистра: «ОБЗОР» занимает подпись так же, как «Обзор».
  const taken = list.items.some(
    (other) => other !== entry && other.doc.title.trim().toLowerCase() === overviewLabel.toLowerCase(),
  );
  return taken ? title : overviewLabel;
}

const overviewLabel = 'Обзор';
