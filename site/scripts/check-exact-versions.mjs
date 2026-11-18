// Проверка точных версий в `site/package.json` — первый шаг `npm run verify`.
//
// Почему: `save-exact` в `.npmrc` действует только на `npm install`, а
// диапазон, вписанный в `package.json` руками, прошёл бы незамеченным
// (design.md add-astro-site, D2; project-site, сценарий «Диапазон версии
// отклоняется»).
//
// Для чего: тонкая обёртка над `findInexactVersions` из `src/lib/` — логика и
// её тесты живут там, здесь только чтение файла и код выхода.
//
// Как использовать: `node scripts/check-exact-versions.mjs` из `site/` (так его
// вызывает `verify`). Модуль `.ts` импортируется напрямую: Node из `.nvmrc`
// снимает типы сам, без сборки. Ненулевой код выхода и список «секция: имя@
// версия» — если есть неточная версия.
import { readFileSync } from 'node:fs';

import { findInexactVersions } from '../src/lib/exact-versions.ts';

const path = new URL('../package.json', import.meta.url);
const violations = findInexactVersions(JSON.parse(readFileSync(path, 'utf8')));

if (violations.length > 0) {
  console.error('site/package.json: dependency versions must be exact (D2):');
  for (const { section, name, spec } of violations) {
    console.error(`  ${section}: ${name}@${JSON.stringify(spec)}`);
  }
  process.exit(1);
}
console.log('site/package.json: all dependency versions are exact.');
