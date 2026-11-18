// Тесты навигации документации (tasks.md add-astro-site, 3.1; D9;
// project-site «Разделы сайта», сценарий «Документ попадает в группу по
// расположению»; «Новый документ появляется без правки сайта»).
import { describe, expect, it } from 'vitest';

import { buildNav, navGroup } from '../src/lib/nav';

describe('navGroup', () => {
  it.each([
    ['docs/user/README.md', 'Пользователю'],
    ['docs/user/sub/deep.md', 'Пользователю'],
    ['docs/ops/codelab-home.md', 'Эксплуатация'],
    ['apps/codelab_desktop/README.md', 'CodeLab app'],
    ['apps/codelab_desktop/doc/terminal.md', 'CodeLab app'],
    ['apps/codelab_cli/doc/operations.md', 'codelab'],
    ['apps/codelab_agent/doc/serve.md', 'codelab-agent'],
    ['packages/dart/codelab_setup/README.md', 'Пакеты'],
    ['packages/flutter/codelab_ui/doc/widgets.md', 'Пакеты'],
  ])('%s → «%s»', (path, title) => {
    expect(navGroup(path).title).toBe(title);
  });

  it('неизвестный каталог приложения получает группу с именем каталога, а не ошибку', () => {
    expect(navGroup('apps/codelab_new/doc/intro.md').title).toBe('codelab_new');
    expect(navGroup('apps/codelab_new/README.md').title).toBe('codelab_new');
  });
});

describe('buildNav', () => {
  const docs = [
    { repoPath: 'packages/dart/codelab_setup/README.md', title: 'codelab_setup' },
    { repoPath: 'apps/codelab_cli/doc/user-guide.md', title: 'Руководство пользователя' },
    { repoPath: 'docs/user/zed.md', title: 'Zed' },
    { repoPath: 'apps/codelab_cli/doc/operations.md', title: 'Эксплуатация codelab' },
    { repoPath: 'docs/user/README.md', title: 'Пользователю' },
    { repoPath: 'docs/user/configuration.md', title: 'Настройка агента' },
    { repoPath: 'apps/codelab_cli/README.md', title: 'codelab' },
    { repoPath: 'docs/ops/README.md', title: 'Эксплуатация' },
  ];

  it('выводит группы в порядке D9 и не показывает пустые', () => {
    expect(buildNav(docs).map((section) => section.title)).toEqual([
      'Пользователю',
      'Эксплуатация',
      'codelab',
      'Пакеты',
    ]);
  });

  it('ставит README.md первым, остальные — по заголовку', () => {
    const user = buildNav(docs).find((s) => s.title === 'Пользователю');
    expect(user?.items.map((d) => d.repoPath)).toEqual([
      'docs/user/README.md',
      'docs/user/configuration.md',
      'docs/user/zed.md',
    ]);
    const cli = buildNav(docs).find((s) => s.title === 'codelab');
    expect(cli?.items.map((d) => d.repoPath)).toEqual([
      'apps/codelab_cli/README.md',
      'apps/codelab_cli/doc/user-guide.md',
      'apps/codelab_cli/doc/operations.md',
    ]);
  });

  it('показывает документ неизвестного приложения в группе с именем каталога', () => {
    const nav = buildNav([
      ...docs,
      { repoPath: 'apps/codelab_new/doc/intro.md', title: 'Введение' },
    ]);
    expect(nav.find((s) => s.title === 'codelab_new')?.items).toEqual([
      { repoPath: 'apps/codelab_new/doc/intro.md', title: 'Введение' },
    ]);
  });

  it('без документов возвращает пустой список', () => {
    expect(buildNav([])).toEqual([]);
  });
});
