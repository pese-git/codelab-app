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
 *
 * Состояние: заглушка красных тестов задачи 3.9 (tasks.md); реализация — 3.10.
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
 * Новости от новой к старой: по `date`, при равных датах — по `version`.
 * Дубликат версии — [DuplicateNewsVersionError].
 */
export function orderNews<T extends NewsLike>(_entries: readonly T[]): T[] {
  throw new Error('not implemented');
}
