/**
 * Удаляет из каталога Pagefind файлы готового интерфейса, которые сайт не использует.
 *
 * Почему: поиск сайта — собственный скрипт поверх `pagefind.js` (design.md
 * improve-docs-navigation, D8), а CLI Pagefind всегда кладёт рядом свои
 * интерфейсы; лишние файлы — десятки килобайт в `dist/` без пользы.
 *
 * Для чего: чистит `dist/pagefind/` после индексации; рантайм, воркер,
 * WebAssembly, фрагменты и индекс остаются.
 *
 * Как использовать: `prunePagefind(dir)` возвращает имена удалённых файлов;
 * несуществующий каталог — не ошибка (возвращает `[]`).
 */
import { existsSync, readdirSync, rmSync } from 'node:fs';
import { join } from 'node:path';

/** Файлы интерфейсов Pagefind: `pagefind-ui.*`, `-modular-ui.*`, `-component-ui.*` и подсветка. */
const unused = /^(pagefind-(ui|modular-ui|component-ui)\.[^.]+|pagefind-highlight\.js)$/;

export function prunePagefind(dir: string): string[] {
  if (!existsSync(dir)) return [];
  const removed = readdirSync(dir).filter((name) => unused.test(name));
  for (const name of removed) rmSync(join(dir, name));
  return removed.sort();
}
