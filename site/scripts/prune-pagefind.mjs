// Удаление неиспользуемых файлов интерфейса Pagefind из `dist/pagefind/`.
//
// Почему: сайт ищет собственным скриптом (`src/scripts/doc-page/search.ts`) и
// грузит только `pagefind.js`; готовые интерфейсы Pagefind (`pagefind-ui.*`,
// `pagefind-modular-ui.*`, `pagefind-component-ui.*`, `pagefind-highlight.js`)
// у CLI не отключаются и лишь раздувают `dist/` (design.md
// improve-docs-navigation, D8).
//
// Для чего: шаг `build` после `pagefind --site dist`.
//
// Как использовать: `node scripts/prune-pagefind.mjs [каталог]`; по умолчанию
// `dist/pagefind` относительно текущего каталога.
import { prunePagefind } from '../src/lib/prune-pagefind.ts';

const removed = prunePagefind(process.argv[2] ?? 'dist/pagefind');
console.log(`pagefind: removed ${removed.length} unused UI files.`);
