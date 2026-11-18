/**
 * Проверка точных версий зависимостей `site/package.json`.
 *
 * Почему: цепочка поставок npm — сотни транзитивных пакетов (design.md
 * add-astro-site, D2, R5). `save-exact` в `.npmrc` защищает только от
 * `npm install`, а правку `package.json` руками не ловит; требование
 * `project-site`, сценарий «Диапазон версии отклоняется».
 *
 * Для чего: чистая функция без зависимостей, которую вызывает `npm run verify`
 * (D1) и проверяют тесты `test/exact-versions.test.ts`.
 *
 * Как использовать: передать разобранный `package.json`; пустой результат —
 * все версии точные, иначе — список нарушений с именем зависимости.
 *
 * Состояние: заглушка красной половины задачи 2.3 (tasks.md); реализация и
 * вызов из `verify` — вторая половина задачи.
 */

/** Зависимость с неточной версией: имя, секция `package.json` и значение. */
export interface InexactVersion {
  readonly name: string;
  readonly section: string;
  readonly spec: string;
}

/** Возвращает зависимости `package.json`, версия которых не точная. */
export function findInexactVersions(_packageJson: unknown): InexactVersion[] {
  return [];
}
