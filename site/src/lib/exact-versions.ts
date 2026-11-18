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
 * Точной считается только полная версия semver `MAJOR.MINOR.PATCH` с
 * необязательными пре-релизом и метаданными сборки. Всё остальное — диапазоны
 * (`^`, `~`, `*`, `x`, `>=`, `||`, `-`), неполные версии (`5`, `5.0`), теги
 * (`latest`) и прочие спецификаторы (`file:`, `git+…`, `npm:`) — нарушение:
 * они не фиксируют, что именно ставится.
 */

/** Зависимость с неточной версией: имя, секция `package.json` и значение. */
export interface InexactVersion {
  readonly name: string;
  readonly section: string;
  readonly spec: string;
}

/**
 * Секции `package.json` со спецификаторами версий, в порядке отчёта.
 * `engines` сюда не входит: это требование к Node, а не зависимость.
 */
const sections = [
  'dependencies',
  'devDependencies',
  'optionalDependencies',
  'peerDependencies',
] as const;

/** Полная версия semver 2.0 без диапазонов. */
const exactVersion =
  /^(0|[1-9]\d*)\.(0|[1-9]\d*)\.(0|[1-9]\d*)(-[0-9A-Za-z-]+(\.[0-9A-Za-z-]+)*)?(\+[0-9A-Za-z-]+(\.[0-9A-Za-z-]+)*)?$/;

/** Возвращает зависимости `package.json`, версия которых не точная. */
export function findInexactVersions(packageJson: unknown): InexactVersion[] {
  if (!isRecord(packageJson)) return [];
  const result: InexactVersion[] = [];
  for (const section of sections) {
    const deps = packageJson[section];
    if (!isRecord(deps)) continue;
    for (const [name, spec] of Object.entries(deps)) {
      const value = typeof spec === 'string' ? spec : String(spec);
      if (!exactVersion.test(value)) result.push({ name, section, spec: value });
    }
  }
  return result;
}

function isRecord(value: unknown): value is Record<string, unknown> {
  return typeof value === 'object' && value !== null && !Array.isArray(value);
}
