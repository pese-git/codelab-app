// Тесты очистки каталога Pagefind (design.md improve-docs-navigation, D8).
import { existsSync, mkdtempSync, rmSync, writeFileSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { afterEach, describe, expect, it } from 'vitest';

import { prunePagefind } from '../src/lib/prune-pagefind';

const dirs: string[] = [];
afterEach(() => {
  for (const dir of dirs.splice(0)) rmSync(dir, { recursive: true, force: true });
});

function bundle(names: string[]): string {
  const dir = mkdtempSync(join(tmpdir(), 'pagefind-'));
  dirs.push(dir);
  for (const name of names) writeFileSync(join(dir, name), '');
  return dir;
}

describe('prunePagefind', () => {
  it('удаляет интерфейсы и подсветку, оставляет рантайм, воркер, индекс', () => {
    const keep = ['pagefind.js', 'pagefind-worker.js', 'pagefind-entry.json', 'wasm.ru.pagefind', 'x.pf_meta'];
    const drop = [
      'pagefind-ui.js', 'pagefind-ui.css', 'pagefind-modular-ui.js', 'pagefind-modular-ui.css',
      'pagefind-component-ui.js', 'pagefind-component-ui.css', 'pagefind-highlight.js',
    ];
    const dir = bundle([...keep, ...drop]);
    expect(prunePagefind(dir)).toEqual([...drop].sort());
    for (const name of keep) expect(existsSync(join(dir, name))).toBe(true);
    for (const name of drop) expect(existsSync(join(dir, name))).toBe(false);
  });

  it('нет каталога — пустой результат', () => {
    expect(prunePagefind(join(tmpdir(), 'no-such-pagefind-dir'))).toEqual([]);
  });
});
