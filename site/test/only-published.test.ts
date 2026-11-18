// Тесты ограничения плагина документами allowlist (tasks.md add-astro-site,
// 4.1; D5, D10): `repoLinks` переводит ссылки документов репозитория, а
// новости `site/src/content/news/` ссылаются на адреса сайта и проверяются
// `check-links`, а не плагином.
import { join } from 'node:path';

import type { Root } from 'mdast';
import { describe, expect, it } from 'vitest';
import { VFile } from 'vfile';

import { onlyPublished } from '../src/plugins/only-published';

const repoRoot = '/repo';

/** Плагин-метка: добавляет узел, если его преобразование вызвано. */
function marker() {
  return (tree: Root) => {
    tree.children.push({ type: 'thematicBreak' });
  };
}

function run(path: string | undefined): number {
  const tree: Root = { type: 'root', children: [] };
  const transform = onlyPublished(marker, repoRoot)();
  transform(tree, new VFile({ path }));
  return tree.children.length;
}

describe('onlyPublished', () => {
  it('документ из allowlist — плагин работает', () => {
    expect(run(join(repoRoot, 'docs/user/configuration.md'))).toBe(1);
  });

  it('новость сайта — плагин пропускается', () => {
    expect(run(join(repoRoot, 'site/src/content/news/1.0.0.md'))).toBe(0);
  });

  it('AGENTS.md и файл вне корня — плагин пропускается', () => {
    expect(run(join(repoRoot, 'apps/codelab_cli/doc/AGENTS.md'))).toBe(0);
    expect(run('/elsewhere/docs/user/a.md')).toBe(0);
  });

  it('файл без пути — плагин пропускается', () => {
    expect(run(undefined)).toBe(0);
  });

  it('передаёт настройки плагину', () => {
    let received: unknown;
    const plugin = (options: { x: number }) => {
      received = options;
      return () => {};
    };
    onlyPublished(plugin, repoRoot)({ x: 1 });
    expect(received).toEqual({ x: 1 });
  });
});
