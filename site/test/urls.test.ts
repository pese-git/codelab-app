// Тесты адресов сайта (tasks.md add-astro-site, 3.1; D4, D12; project-site
// «Публикуемые источники документации», «Конфигурация под будущий хостинг»).
import { describe, expect, it } from 'vitest';

import { pageUrl, withBase } from '../src/lib/urls';

// Таблица D4 и сценарии спецификации: путь в репозитории → адрес без base.
const table: ReadonlyArray<readonly [string, string]> = [
  ['docs/user/README.md', 'docs/user/'],
  ['docs/user/configuration.md', 'docs/user/configuration/'],
  ['docs/ops/README.md', 'docs/ops/'],
  ['apps/codelab_cli/README.md', 'docs/apps/codelab_cli/'],
  ['apps/codelab_cli/doc/user-guide.md', 'docs/apps/codelab_cli/doc/user-guide/'],
  ['apps/codelab_desktop/doc/terminal.md', 'docs/apps/codelab_desktop/doc/terminal/'],
  ['packages/dart/codelab_setup/README.md', 'docs/packages/dart/codelab_setup/'],
  // Регистр и подчёркивания сохраняются, вложенный README — адрес каталога.
  ['packages/dart/codelab_setup/doc/sub/Guide_X.md', 'docs/packages/dart/codelab_setup/doc/sub/Guide_X/'],
  ['docs/user/sub/README.md', 'docs/user/sub/'],
];

describe('pageUrl', () => {
  for (const base of ['/', '/codelab-app/']) {
    it.each(table)(`base ${base}: %s → ${base}%s`, (repoPath, url) => {
      expect(pageUrl(repoPath, base)).toBe(`${base}${url}`);
    });
  }

  it('не дублирует префикс docs/ у источников docs/*', () => {
    expect(pageUrl('docs/ops/codelab-home.md', '/')).toBe('/docs/ops/codelab-home/');
  });
});

describe('withBase', () => {
  it.each([
    ['/', 'news/', '/news/'],
    ['/', '/news/', '/news/'],
    ['/', '', '/'],
    ['/codelab-app/', 'news/', '/codelab-app/news/'],
    ['/codelab-app/', '/news/', '/codelab-app/news/'],
    ['/codelab-app/', '', '/codelab-app/'],
    ['/codelab-app/', '/', '/codelab-app/'],
    ['/codelab-app/', 'features/cli/', '/codelab-app/features/cli/'],
  ])('base %j + %j → %j', (base, path, url) => {
    expect(withBase(path, base)).toBe(url);
  });

  it('сохраняет якорь', () => {
    expect(withBase('docs/user/#шаг-1', '/codelab-app/')).toBe(
      '/codelab-app/docs/user/#шаг-1',
    );
  });
});
