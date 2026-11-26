// Тесты навигации документации: порядок D1, секции и списки D2, слои D3,
// крошки и соседи D5 (tasks.md improve-docs-navigation, 1.1–1.3; add-astro-site
// 3.1, D9; project-site «Порядок и подгруппы документации», «Навигация на
// странице документа»).
import { describe, expect, it } from 'vitest';

import {
  breadcrumbs,
  buildNav,
  chapterNumber,
  entryLabel,
  installDocPath,
  navGroup,
  neighbours,
  packageLayer,
  sectionDocs,
  type NavList,
  type NavSection,
} from '../src/lib/nav';

interface TestDoc {
  repoPath: string;
  title: string;
}

const d = (repoPath: string, title: string): TestDoc => ({ repoPath, title });
const paths = (list: NavList<TestDoc> | undefined) => list?.items.map((e) => e.doc.repoPath);

/** Секция группы (по названию группы и, у пакетов, названию секции). */
function section(docs: TestDoc[], group: string, title?: string): NavSection<TestDoc> {
  const found = buildNav(docs)
    .find((g) => g.title === group)
    ?.sections.find((s) => title === undefined || s.title === title);
  if (!found) throw new Error(`нет секции ${group}/${title}`);
  return found;
}

const list = (s: NavSection<TestDoc>, title: string | null) => s.lists.find((l) => l.title === title);

const cli: TestDoc[] = [
  d('apps/codelab_cli/doc/user/12-troubleshooting.md', 'Диагностика'),
  d('apps/codelab_cli/doc/user/03-tui.md', 'Полноэкранный режим'),
  d('apps/codelab_cli/doc/user/00-overview.md', 'Обзор: что такое codelab'),
  d('apps/codelab_cli/doc/user/02-repl.md', 'Диалог (построчный режим)'),
  d('apps/codelab_cli/doc/user/01-install.md', 'Установка и первый запуск'),
  d('apps/codelab_cli/doc/user/04-headless.md', 'Один запрос без диалога'),
  d('apps/codelab_cli/doc/user-guide.md', 'codelab: руководство пользователя'),
  d('apps/codelab_cli/doc/04-tui.md', 'Полноэкранный режим (TUI)'),
  d('apps/codelab_cli/doc/00-getting-started.md', 'Начало работы'),
  d('apps/codelab_cli/doc/development.md', 'codelab: разработка'),
  d('apps/codelab_cli/doc/operations.md', 'codelab: эксплуатация'),
  d('apps/codelab_cli/doc/README.md', 'codelab: документация'),
  d('apps/codelab_cli/README.md', 'codelab'),
];

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

describe('chapterNumber (D1)', () => {
  it.each([
    ['apps/codelab_cli/doc/user/03-tui.md', '03'],
    ['apps/codelab_cli/doc/user/00-overview.md', '00'],
    ['packages/dart/x/doc/9-a.md', '9'],
    ['packages/dart/x/doc/100-big.md', '100'],
  ])('%s → %s', (path, number) => {
    expect(chapterNumber(path)).toBe(number);
  });

  it.each([
    'apps/codelab_cli/doc/user-guide.md',
    'apps/codelab_cli/doc/development.md',
    'docs/user/README.md',
    'docs/user/2fa-notes.md',
    // Каталог с номером не делает номером имя файла.
    'apps/codelab_cli/doc/03-dir/readme.md',
  ])('%s — без номера', (path) => {
    expect(chapterNumber(path)).toBeNull();
  });
});

describe('buildNav: группы (D9 add-astro-site)', () => {
  const docs = [
    d('packages/dart/codelab_setup/README.md', 'codelab_setup'),
    d('apps/codelab_cli/doc/user-guide.md', 'Руководство пользователя'),
    d('docs/user/zed.md', 'Zed'),
    d('docs/user/README.md', 'Пользователю'),
    d('docs/user/configuration.md', 'Настройка агента'),
    d('docs/ops/README.md', 'Эксплуатация'),
  ];

  it('выводит группы в порядке D9 и не показывает пустые', () => {
    expect(buildNav(docs).map((g) => g.title)).toEqual(['Пользователю', 'Эксплуатация', 'codelab', 'Пакеты']);
  });

  it('показывает документ неизвестного приложения в группе с именем каталога', () => {
    const nav = buildNav([...docs, d('apps/codelab_new/doc/intro.md', 'Введение')]);
    expect(nav.map((g) => g.title)).toEqual(['Пользователю', 'Эксплуатация', 'codelab', 'codelab_new', 'Пакеты']);
    expect(paths(nav.find((g) => g.title === 'codelab_new')?.sections[0]?.lists[0])).toEqual([
      'apps/codelab_new/doc/intro.md',
    ]);
  });

  it('без документов возвращает пустой список', () => {
    expect(buildNav([])).toEqual([]);
  });
});

describe('порядок внутри списка (D1)', () => {
  it('главы руководства идут по номеру, вход первым', () => {
    const guide = list(section(cli, 'codelab'), 'Руководство');
    expect(paths(guide)).toEqual([
      'apps/codelab_cli/doc/user-guide.md',
      'apps/codelab_cli/doc/user/00-overview.md',
      'apps/codelab_cli/doc/user/01-install.md',
      'apps/codelab_cli/doc/user/02-repl.md',
      'apps/codelab_cli/doc/user/03-tui.md',
      'apps/codelab_cli/doc/user/04-headless.md',
      'apps/codelab_cli/doc/user/12-troubleshooting.md',
    ]);
  });

  it('номер сравнивается как число: 10 после 9', () => {
    const docs = [
      d('packages/dart/codelab_x/doc/10-b.md', 'Б'),
      d('packages/dart/codelab_x/doc/9-a.md', 'А'),
      d('packages/dart/codelab_x/doc/100-c.md', 'В'),
    ];
    expect(paths(section(docs, 'Пакеты').lists[0])).toEqual([
      'packages/dart/codelab_x/doc/9-a.md',
      'packages/dart/codelab_x/doc/10-b.md',
      'packages/dart/codelab_x/doc/100-c.md',
    ]);
  });

  it('документ без номера — после глав с номером, по заголовку; номера в записи нет', () => {
    const docs = [
      d('apps/codelab_cli/doc/user/faq.md', 'Частые вопросы'),
      d('apps/codelab_cli/doc/user/00-a.md', 'Первая'),
      d('apps/codelab_cli/doc/user/07-z.md', 'Последняя'),
      d('apps/codelab_cli/doc/user/aaa.md', 'Авария'),
    ];
    const guide = list(section(docs, 'codelab'), 'Руководство');
    expect(guide?.items.map((e) => [e.doc.title, e.number])).toEqual([
      ['Первая', '00'],
      ['Последняя', '07'],
      ['Авария', null],
      ['Частые вопросы', null],
    ]);
  });

  it('одинаковый номер — по заголовку; равные заголовки — по пути', () => {
    const docs = [
      d('packages/dart/codelab_x/doc/05-b.md', 'Альфа'),
      d('packages/dart/codelab_x/doc/05-a.md', 'Бета'),
      d('packages/dart/codelab_x/doc/06-z.md', 'Одинаковый'),
      d('packages/dart/codelab_x/doc/06-a.md', 'Одинаковый'),
    ];
    expect(paths(section(docs, 'Пакеты').lists[0])).toEqual([
      'packages/dart/codelab_x/doc/05-b.md',
      'packages/dart/codelab_x/doc/05-a.md',
      'packages/dart/codelab_x/doc/06-a.md',
      'packages/dart/codelab_x/doc/06-z.md',
    ]);
  });

  it('сквозные документы: README первым, затем по заголовку', () => {
    const docs = [
      d('docs/user/zed.md', 'Zed'),
      d('docs/user/configuration.md', 'Настройка агента'),
      d('docs/user/README.md', 'Пользователю'),
    ];
    expect(paths(section(docs, 'Пользователю').lists[0])).toEqual([
      'docs/user/README.md',
      'docs/user/configuration.md',
      'docs/user/zed.md',
    ]);
  });

  it('вход пакета: README.md, затем doc/README.md, затем главы', () => {
    const docs = [
      d('packages/dart/codelab_x/doc/01-a.md', 'А'),
      d('packages/dart/codelab_x/doc/README.md', 'Документация'),
      d('packages/dart/codelab_x/README.md', 'codelab_x'),
    ];
    expect(paths(section(docs, 'Пакеты').lists[0])).toEqual([
      'packages/dart/codelab_x/README.md',
      'packages/dart/codelab_x/doc/README.md',
      'packages/dart/codelab_x/doc/01-a.md',
    ]);
  });
});

describe('секции и списки (D2)', () => {
  const s = section(cli, 'codelab');

  it('вход приложения — список без заголовка: README.md, затем doc/README.md', () => {
    expect(paths(list(s, null))).toEqual(['apps/codelab_cli/README.md', 'apps/codelab_cli/doc/README.md']);
  });

  it('списки идут в порядке: вход, Руководство, Эксплуатация, Для разработчика', () => {
    expect(s.lists.map((l) => l.title)).toEqual([null, 'Руководство', 'Эксплуатация', 'Для разработчика']);
  });

  it('аудитории не смешиваются: главы пользователя и разработчика в разных списках', () => {
    const guide = list(s, 'Руководство');
    const dev = list(s, 'Для разработчика');
    expect(guide?.items.find((e) => e.doc.title === 'Полноэкранный режим')?.number).toBe('03');
    expect(dev?.items.find((e) => e.doc.title === 'Полноэкранный режим (TUI)')?.number).toBe('04');
    expect(guide?.items.some((e) => e.doc.title.includes('TUI'))).toBe(false);
  });

  it('вход разработчика первым, эксплуатация — отдельный список', () => {
    expect(paths(list(s, 'Для разработчика'))).toEqual([
      'apps/codelab_cli/doc/development.md',
      'apps/codelab_cli/doc/00-getting-started.md',
      'apps/codelab_cli/doc/04-tui.md',
    ]);
    expect(paths(list(s, 'Эксплуатация'))).toEqual(['apps/codelab_cli/doc/operations.md']);
  });

  it('неизвестный файл doc/*.md попадает в «Для разработчика»', () => {
    const docs = [...cli, d('apps/codelab_cli/doc/notes.md', 'Заметки')];
    expect(paths(list(section(docs, 'codelab'), 'Для разработчика'))).toContain('apps/codelab_cli/doc/notes.md');
  });

  it('приложение с одним README — только список входа', () => {
    const only = section([d('apps/codelab_new/README.md', 'Новое')], 'codelab_new');
    expect(only.lists.map((l) => l.title)).toEqual([null]);
  });

  it('docs/user и docs/ops — одна секция на группу, один список', () => {
    const u = section([d('docs/user/a.md', 'А'), d('docs/user/b.md', 'Б')], 'Пользователю');
    expect(u.lists).toHaveLength(1);
    expect(u.title).toBe('Пользователю');
  });

  it('вложенный каталог — подгруппа с заголовком из README.md, README первым', () => {
    const docs = [
      d('packages/dart/codelab_agent_core/README.md', 'codelab_agent_core'),
      d('packages/dart/codelab_agent_core/doc/algorithms/tool-call.md', 'Вызов инструмента'),
      d('packages/dart/codelab_agent_core/doc/algorithms/README.md', 'Алгоритмы ядра агента'),
    ];
    const pkg = section(docs, 'Пакеты', 'codelab_agent_core');
    expect(pkg.lists.map((l) => l.title)).toEqual([null, 'Алгоритмы ядра агента']);
    expect(paths(list(pkg, 'Алгоритмы ядра агента'))).toEqual([
      'packages/dart/codelab_agent_core/doc/algorithms/README.md',
      'packages/dart/codelab_agent_core/doc/algorithms/tool-call.md',
    ]);
  });

  it('вложенный каталог без README.md — подгруппа с именем каталога', () => {
    const docs = [d('apps/codelab_cli/doc/recipes/a.md', 'Рецепт')];
    expect(section(docs, 'codelab').lists.map((l) => l.title)).toEqual(['recipes']);
  });

  it('вложенный каталог docs/user/<каталог>/ — подгруппа той же секции', () => {
    const docs = [d('docs/user/a.md', 'А'), d('docs/user/more/README.md', 'Ещё'), d('docs/user/more/b.md', 'Б')];
    const u = section(docs, 'Пользователю');
    expect(u.lists.map((l) => l.title)).toEqual([null, 'Ещё']);
  });

  it('второй уровень вложенности остаётся в подгруппе первого уровня', () => {
    const docs = [
      d('packages/dart/codelab_x/doc/algo/README.md', 'Алго'),
      d('packages/dart/codelab_x/doc/algo/deep/z.md', 'Глубоко'),
    ];
    const pkg = section(docs, 'Пакеты');
    expect(pkg.lists).toHaveLength(1);
    expect(paths(pkg.lists[0])).toEqual([
      'packages/dart/codelab_x/doc/algo/README.md',
      'packages/dart/codelab_x/doc/algo/deep/z.md',
    ]);
  });

  it('doc/user/** приложения — «Руководство», а не вложенная подгруппа', () => {
    expect(s.lists.some((l) => l.title === 'user')).toBe(false);
  });

  it('пакет — своя секция в группе «Пакеты»', () => {
    const docs = [d('packages/dart/codelab_a/README.md', 'a'), d('packages/dart/codelab_b/README.md', 'b')];
    const group = buildNav(docs)[0]!;
    expect(group.title).toBe('Пакеты');
    expect(group.sections.map((x) => x.title)).toEqual(['codelab_a', 'codelab_b']);
    expect(group.sections[0]!.key).toBe('packages/dart/codelab_a/');
  });

  it('sectionDocs — все документы секции в порядке показа', () => {
    expect(sectionDocs(s).map((e) => e.doc.repoPath)).toHaveLength(cli.length);
    expect(sectionDocs(s)[0]!.doc.repoPath).toBe('apps/codelab_cli/README.md');
  });
});

describe('слой пакета (D3)', () => {
  it.each([
    ['packages/dart/codelab_acp_protocol/README.md', 'acp', 'Протокол ACP'],
    ['packages/dart/codelab_client_core/doc/01-a.md', 'client', 'Клиент'],
    ['packages/dart/codelab_agent_core/README.md', 'agent', 'Агент'],
    ['packages/dart/codelab_embedded/README.md', 'shared', 'Мосты и служебные пакеты'],
    ['packages/dart/codelab_setup/README.md', 'shared', 'Мосты и служебные пакеты'],
    ['packages/flutter/codelab_ui/README.md', 'flutter', 'Интерфейс Flutter'],
    ['packages/dart/codelab_architecture_tests/README.md', 'checks', 'Проверки'],
    // Правило «_tests» проверяется раньше префикса стороны.
    ['packages/dart/codelab_agent_tests/README.md', 'checks', 'Проверки'],
    ['packages/dart/codelab_acp_tests/README.md', 'checks', 'Проверки'],
    ['packages/tools/codelab_probe/README.md', 'other', 'Другие пакеты'],
    ['packages/dart/codelab_client_store/README.md', 'client', 'Клиент'],
  ])('%s → %s', (path, id, title) => {
    expect(packageLayer(path)).toEqual({ id, title });
  });

  it('секции пакетов упорядочены по слоям, внутри слоя — по имени каталога', () => {
    const docs = [
      d('packages/tools/codelab_probe/README.md', 'p'),
      d('packages/dart/codelab_architecture_tests/README.md', 't'),
      d('packages/flutter/codelab_ui/README.md', 'u'),
      d('packages/dart/codelab_setup/README.md', 's'),
      d('packages/dart/codelab_agent_core/README.md', 'a'),
      d('packages/dart/codelab_client_io/README.md', 'ci'),
      d('packages/dart/codelab_client_core/README.md', 'cc'),
      d('packages/dart/codelab_acp_protocol/README.md', 'ap'),
    ];
    const group = buildNav(docs)[0]!;
    expect(group.sections.map((x) => [x.title, x.layer?.id])).toEqual([
      ['codelab_acp_protocol', 'acp'],
      ['codelab_client_core', 'client'],
      ['codelab_client_io', 'client'],
      ['codelab_agent_core', 'agent'],
      ['codelab_setup', 'shared'],
      ['codelab_ui', 'flutter'],
      ['codelab_architecture_tests', 'checks'],
      ['codelab_probe', 'other'],
    ]);
  });

  it('у секций, не относящихся к пакетам, слоя нет', () => {
    expect(section(cli, 'codelab').layer).toBeNull();
  });
});

describe('breadcrumbs (D5)', () => {
  const nav = buildNav(cli);
  const labels = (path: string, base = '/') =>
    breadcrumbs(nav, path, base).map((c) => [c.label, c.href]);

  it('глава руководства: Документация › группа › Руководство', () => {
    expect(labels('apps/codelab_cli/doc/user/03-tui.md')).toEqual([
      ['Документация', '/docs/'],
      ['codelab', '/docs/apps/codelab_cli/'],
      ['Руководство', '/docs/apps/codelab_cli/doc/user-guide/'],
    ]);
  });

  it('адреса учитывают base', () => {
    expect(labels('apps/codelab_cli/doc/user/03-tui.md', '/codelab-app/')).toEqual([
      ['Документация', '/codelab-app/docs/'],
      ['codelab', '/codelab-app/docs/apps/codelab_cli/'],
      ['Руководство', '/codelab-app/docs/apps/codelab_cli/doc/user-guide/'],
    ]);
  });

  it('уровень на текущую страницу не показывается', () => {
    expect(labels('apps/codelab_cli/doc/user-guide.md')).toEqual([
      ['Документация', '/docs/'],
      ['codelab', '/docs/apps/codelab_cli/'],
    ]);
    expect(labels('apps/codelab_cli/README.md')).toEqual([['Документация', '/docs/']]);
  });

  it('вход и основной список подгруппы в крошках не дают', () => {
    expect(labels('apps/codelab_cli/doc/README.md')).toEqual([
      ['Документация', '/docs/'],
      ['codelab', '/docs/apps/codelab_cli/'],
    ]);
  });

  it('«Для разработчика» ведёт на development.md, «Эксплуатация» — на operations.md', () => {
    expect(labels('apps/codelab_cli/doc/04-tui.md')[2]).toEqual([
      'Для разработчика',
      '/docs/apps/codelab_cli/doc/development/',
    ]);
    expect(labels('apps/codelab_cli/doc/operations.md')).toEqual([
      ['Документация', '/docs/'],
      ['codelab', '/docs/apps/codelab_cli/'],
    ]);
  });

  it('подгруппа без входа ведёт на первый документ списка', () => {
    const docs = [
      d('apps/codelab_cli/README.md', 'codelab'),
      d('apps/codelab_cli/doc/user/01-b.md', 'Б'),
      d('apps/codelab_cli/doc/user/00-a.md', 'А'),
    ];
    expect(breadcrumbs(buildNav(docs), 'apps/codelab_cli/doc/user/01-b.md', '/')[2]).toMatchObject({
      label: 'Руководство',
      href: '/docs/apps/codelab_cli/doc/user/00-a/',
    });
  });

  it('группа без README.md ведёт на первый документ секции', () => {
    const docs = [d('apps/codelab_new/doc/b.md', 'Б'), d('apps/codelab_new/doc/a.md', 'А')];
    const crumbs = breadcrumbs(buildNav(docs), 'apps/codelab_new/doc/b.md', '/');
    expect(crumbs[1]).toEqual({ label: 'codelab_new', href: '/docs/apps/codelab_new/doc/a/' });
  });

  it('docs/user: Документация › Пользователю', () => {
    const user = buildNav([d('docs/user/README.md', 'П'), d('docs/user/zed.md', 'Zed')]);
    expect(breadcrumbs(user, 'docs/user/zed.md', '/').map((c) => [c.label, c.href])).toEqual([
      ['Документация', '/docs/'],
      ['Пользователю', '/docs/user/'],
    ]);
  });

  describe('пакеты', () => {
    const pkgs = buildNav([
      d('packages/dart/codelab_agent_core/README.md', 'codelab_agent_core'),
      d('packages/dart/codelab_agent_core/doc/01-a.md', 'Глава'),
      d('packages/dart/codelab_agent_core/doc/algorithms/README.md', 'Алгоритмы ядра агента'),
      d('packages/dart/codelab_agent_core/doc/algorithms/turn.md', 'Ход'),
    ]);

    it('Документация › Пакеты (#packages) › пакет', () => {
      expect(breadcrumbs(pkgs, 'packages/dart/codelab_agent_core/doc/01-a.md', '/').map((c) => [c.label, c.href])).toEqual([
        ['Документация', '/docs/'],
        ['Пакеты', '/docs/#packages'],
        ['codelab_agent_core', '/docs/packages/dart/codelab_agent_core/'],
      ]);
    });

    it('якорь #packages учитывает base', () => {
      expect(breadcrumbs(pkgs, 'packages/dart/codelab_agent_core/README.md', '/codelab-app/')[1]!.href).toBe(
        '/codelab-app/docs/#packages',
      );
    });

    it('на README пакета крошки пакета нет', () => {
      expect(breadcrumbs(pkgs, 'packages/dart/codelab_agent_core/README.md', '/').map((c) => c.label)).toEqual([
        'Документация',
        'Пакеты',
      ]);
    });

    it('вложенная подгруппа пакета — четвёртый уровень', () => {
      const crumbs = breadcrumbs(pkgs, 'packages/dart/codelab_agent_core/doc/algorithms/turn.md', '/');
      expect(crumbs.map((c) => c.label)).toEqual(['Документация', 'Пакеты', 'codelab_agent_core', 'Алгоритмы ядра агента']);
      expect(crumbs[3]!.href).toBe('/docs/packages/dart/codelab_agent_core/doc/algorithms/');
    });
  });

  it('документ вне навигации — пустые крошки', () => {
    expect(breadcrumbs(nav, 'nowhere/x.md', '/')).toEqual([]);
  });
});

describe('neighbours (D5)', () => {
  const nav = buildNav(cli);

  it('соседние главы руководства', () => {
    const n = neighbours(nav, 'apps/codelab_cli/doc/user/03-tui.md', '/');
    expect(n.prev).toEqual({
      repoPath: 'apps/codelab_cli/doc/user/02-repl.md',
      title: 'Диалог (построчный режим)',
      number: '02',
      href: '/docs/apps/codelab_cli/doc/user/02-repl/',
    });
    expect(n.next).toMatchObject({ number: '04', title: 'Один запрос без диалога' });
  });

  it('первый документ подгруппы — без «Назад», «Далее» на 00', () => {
    const n = neighbours(nav, 'apps/codelab_cli/doc/user-guide.md', '/codelab-app/');
    expect(n.prev).toBeNull();
    expect(n.next).toMatchObject({ number: '00', href: '/codelab-app/docs/apps/codelab_cli/doc/user/00-overview/' });
  });

  it('последний документ списка — без «Далее»', () => {
    const n = neighbours(nav, 'apps/codelab_cli/doc/user/12-troubleshooting.md', '/');
    expect(n.next).toBeNull();
    expect(n.prev).toMatchObject({ number: '04' });
  });

  it('соседи не выходят за пределы списка: из руководства в «Для разработчика» не переходят', () => {
    const n = neighbours(nav, 'apps/codelab_cli/doc/04-tui.md', '/');
    expect(n.next).toBeNull();
    expect(n.prev).toMatchObject({ number: '00', title: 'Начало работы' });
  });

  it('одиночный список и неизвестный документ — без соседей', () => {
    expect(neighbours(nav, 'apps/codelab_cli/doc/operations.md', '/')).toEqual({ prev: null, next: null });
    expect(neighbours(nav, 'nowhere/x.md', '/')).toEqual({ prev: null, next: null });
  });
});

describe('installDocPath (D6)', () => {
  it('— путь документа установки', () => {
    expect(installDocPath).toBe('docs/user/run-from-source.md');
  });
});

describe('entryLabel: вход не повторяет название секции или подгруппы (D1, D2)', () => {
  const nav = buildNav([
    d('packages/dart/codelab_setup/README.md', 'codelab_setup'),
    d('packages/dart/codelab_setup/doc/01-a.md', 'Глава'),
    d('packages/dart/codelab_agent_core/README.md', 'Ядро'),
    d('packages/dart/codelab_agent_core/doc/algorithms/README.md', 'Алгоритмы ядра агента'),
    d('packages/dart/codelab_agent_core/doc/algorithms/01-x.md', 'Цикл'),
  ]);
  const sections = nav.flatMap((g) => g.sections);
  const find = (key: string) => sections.find((s) => s.key.endsWith(`${key}/`))!;

  it('README, чей заголовок равен названию секции, подписывается «Обзор»', () => {
    const section = find('codelab_setup');
    const list = section.lists[0]!;
    expect(list.items.map((e) => entryLabel(e, list, section))).toEqual(['Обзор', 'Глава']);
  });

  it('README подгруппы с тем же заголовком — «Обзор»; прочие заголовки не трогаются', () => {
    const section = find('codelab_agent_core');
    const main = section.lists.find((l) => l.kind === 'main')!;
    expect(main.items.map((e) => entryLabel(e, main, section))).toEqual(['Ядро']);
    const nested = section.lists.find((l) => l.kind === 'nested')!;
    expect(nested.items.map((e) => entryLabel(e, nested, section))).toEqual(['Обзор', 'Цикл']);
  });

  it('если «Обзор» в списке уже есть, заголовок остаётся прежним', () => {
    const n = buildNav([d('packages/dart/p/README.md', 'p'), d('packages/dart/p/doc/00-o.md', 'Обзор')]);
    const section = n[0]!.sections[0]!;
    const list = section.lists[0]!;
    expect(list.items.map((e) => entryLabel(e, list, section))).toEqual(['p', 'Обзор']);
  });

  it('занятость «Обзор» проверяется без учёта регистра, как и равенство названию', () => {
    const n = buildNav([d('packages/dart/p/README.md', 'P'), d('packages/dart/p/doc/00-o.md', 'ОБЗОР')]);
    const section = n[0]!.sections[0]!;
    const list = section.lists[0]!;
    expect(list.items.map((e) => entryLabel(e, list, section))).toEqual(['P', 'ОБЗОР']);
  });
});
