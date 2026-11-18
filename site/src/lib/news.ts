/**
 * Порядок и проверка новостей выпусков.
 *
 * Почему: схема коллекции `news` проверяет каждую запись по отдельности, а
 * повтор `version` в двух файлах она не видит (design.md add-astro-site, D10;
 * project-site «Новости выпусков», сценарий «Повтор версии»).
 *
 * Для чего: страницы `/news/` и главная получают новости уже упорядоченными
 * от новой к старой, а сборка падает на дубликате версии с путями обоих файлов.
 *
 * Как использовать: `orderNews(await getCollection('news'))` — без новостей
 * возвращает пустой список (сценарий «Новостей нет»).
 */

/** Минимум полей записи коллекции `news`, нужный для порядка и проверки. */
export interface NewsLike {
  readonly filePath?: string;
  readonly data: {
    readonly date: string;
    readonly version: string;
  };
}

/** Ошибка сборки: две новости объявляют одну версию (D10). */
export class DuplicateNewsVersionError extends Error {
  constructor(version: string, paths: readonly string[]) {
    super(`News version ${version} is declared twice: ${paths.join(', ')}`);
    this.name = 'DuplicateNewsVersionError';
  }
}

/**
 * Сравнивает версии `MAJOR.MINOR.PATCH[-pre]` по правилам semver: числа —
 * численно (`1.10.0` новее `1.9.0`), выпуск новее своего пре-релиза.
 * Положительный результат — [a] новее [b].
 */
function compareVersions(a: string, b: string): number {
  const [coreA = '', preA] = splitPre(a);
  const [coreB = '', preB] = splitPre(b);
  const numsA = coreA.split('.').map(Number);
  const numsB = coreB.split('.').map(Number);
  for (let i = 0; i < 3; i++) {
    const diff = (numsA[i] ?? 0) - (numsB[i] ?? 0);
    if (diff !== 0) return diff;
  }
  if (preA === undefined || preB === undefined) {
    return (preA === undefined ? 1 : 0) - (preB === undefined ? 1 : 0);
  }
  return comparePre(preA, preB);
}

function splitPre(version: string): [string, string | undefined] {
  const dash = version.indexOf('-');
  return dash === -1 ? [version, undefined] : [version.slice(0, dash), version.slice(dash + 1)];
}

/** Пре-релизы по semver §11: числовые поля численно, остальные — как строки. */
function comparePre(a: string, b: string): number {
  const fieldsA = a.split('.');
  const fieldsB = b.split('.');
  for (let i = 0; i < Math.max(fieldsA.length, fieldsB.length); i++) {
    const x = fieldsA[i];
    const y = fieldsB[i];
    if (x === undefined) return -1;
    if (y === undefined) return 1;
    const numX = /^\d+$/.test(x);
    const numY = /^\d+$/.test(y);
    if (numX && numY) {
      const diff = Number(x) - Number(y);
      if (diff !== 0) return diff;
    } else if (numX !== numY) {
      return numX ? -1 : 1;
    } else if (x !== y) {
      return x < y ? -1 : 1;
    }
  }
  return 0;
}

/**
 * Новости от новой к старой: по `date`, при равных датах — по `version`.
 * Дубликат версии — [DuplicateNewsVersionError].
 */
export function orderNews<T extends NewsLike>(entries: readonly T[]): T[] {
  const seen = new Map<string, T>();
  for (const entry of entries) {
    const previous = seen.get(entry.data.version);
    if (previous) {
      throw new DuplicateNewsVersionError(entry.data.version, [
        previous.filePath ?? '<unknown>',
        entry.filePath ?? '<unknown>',
      ]);
    }
    seen.set(entry.data.version, entry);
  }
  // Дата в формате `YYYY-MM-DD` сравнивается как строка (схема D10).
  return [...entries].sort(
    (a, b) =>
      (a.data.date < b.data.date ? 1 : a.data.date > b.data.date ? -1 : 0) ||
      compareVersions(b.data.version, a.data.version),
  );
}
