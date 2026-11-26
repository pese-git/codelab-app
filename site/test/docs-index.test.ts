// Тесты модели оглавления `/docs/` по ролям (tasks.md improve-docs-navigation,
// 3.1, 3.4; D6 «Руководство пакета в карточке»; project-site «Оглавление документации по ролям»).
import { describe, expect, it } from 'vitest';

import { buildDocsIndex } from '../src/lib/docs-index';
import { buildNav } from '../src/lib/nav';

interface TestDoc {
  repoPath: string;
  title: string;
  description: string;
}

const d = (repoPath: string, title: string, description = `Описание: ${title}`): TestDoc => ({
  repoPath,
  title,
  description,
});

const docs: TestDoc[] = [
  d('docs/user/README.md', 'Пользователю'),
  d('docs/user/run-from-source.md', 'Установка и быстрый старт'),
  d('docs/user/zed.md', 'Zed'),
  d('docs/user/configuration.md', 'Настройка агента'),
  d('docs/ops/README.md', 'Эксплуатация'),
  d('docs/ops/codelab-home.md', 'Домашний каталог'),
  d('apps/codelab_cli/README.md', 'codelab', 'Терминальный клиент'),
  d('apps/codelab_cli/doc/README.md', 'codelab: документация'),
  d('apps/codelab_cli/doc/user-guide.md', 'codelab: руководство пользователя'),
  d('apps/codelab_cli/doc/user/00-overview.md', 'Обзор'),
  d('apps/codelab_cli/doc/user/01-install.md', 'Установка'),
  d('apps/codelab_cli/doc/operations.md', 'codelab: эксплуатация'),
  d('apps/codelab_cli/doc/development.md', 'codelab: разработка'),
  d('apps/codelab_cli/doc/00-getting-started.md', 'Начало работы'),
  d('apps/codelab_cli/doc/01-overview.md', 'Обзор разработки'),
  d('apps/codelab_cli/doc/recipes/README.md', 'Рецепты'),
  d('apps/codelab_cli/doc/recipes/a.md', 'Рецепт А'),
  d('packages/dart/codelab_client_core/README.md', 'codelab_client_core', 'Общий клиентский слой'),
  d('packages/dart/codelab_client_core/doc/README.md', 'Документация'),
  d('packages/dart/codelab_client_core/doc/08-approvals.md', 'Одобрения'),
  d('packages/dart/codelab_architecture_tests/README.md', 'codelab_architecture_tests', 'Сторож'),
  d('packages/dart/codelab_setup/README.md', 'codelab_setup', 'Мост настроек'),
  d('packages/dart/codelab_noreadme/doc/01-a.md', 'Только глава'),
  d('packages/dart/codelab_agent_core/README.md', 'codelab_agent_core', 'Ядро агента'),
  d('packages/dart/codelab_agent_core/doc/README.md', 'Руководство по ядру агента'),
  d('packages/dart/codelab_agent_core/doc/00-getting-started.md', 'Начало работы'),
  d('packages/dart/codelab_agent_core/doc/01-overview.md', 'Обзор ядра'),
  d('packages/dart/codelab_agent_core/doc/tutorial-new-tool.md', 'Туториал: новый инструмент'),
  d('packages/dart/codelab_agent_core/doc/algorithms/README.md', 'Алгоритмы ядра агента'),
  d('packages/dart/codelab_agent_core/doc/algorithms/loop.md', 'Цикл'),
  d('packages/dart/codelab_agent_core/doc/algorithms/compaction.md', 'Сжатие'),
  d('packages/dart/p/README.md', 'p', 'Пакет без входа'),
  d('packages/dart/p/doc/00-a.md', 'Альфа'),
  d('packages/dart/p/doc/01-b.md', 'Бета'),
  d('packages/dart/codelab_sub/doc/algorithms/README.md', 'Алгоритмы'),
  d('packages/dart/codelab_sub/doc/algorithms/a.md', 'А'),
  d('packages/dart/codelab_sub2/README.md', 'codelab_sub2', 'Подгруппа при README'),
  d('packages/dart/codelab_sub2/doc/algorithms/README.md', 'Алгоритмы 2'),
  d('packages/dart/codelab_sub2/doc/algorithms/a.md', 'Б'),
  d('packages/dart/codelab_client_store/README.md', 'codelab_client_store', 'Хранилище'),
];

const index = buildDocsIndex(buildNav(docs));
const repoPaths = (items: readonly { repoPath: string }[]) => items.map((i) => i.repoPath);

describe('buildDocsIndex: блоки (D6)', () => {
  it('идентификаторы и названия блоков стабильны', () => {
    expect([index.start.id, index.use.id, index.build.id, index.build.packages.id]).toEqual([
      'start',
      'use',
      'build',
      'packages',
    ]);
    expect([index.start.title, index.use.title, index.build.title]).toEqual([
      'Начать работу',
      'Пользоваться',
      'Развернуть и разрабатывать',
    ]);
  });

  it('«Начать работу»: установка, docs/user/README.md, карточки приложений', () => {
    expect(repoPaths(index.start.links)).toEqual(['docs/user/run-from-source.md', 'docs/user/README.md']);
    expect(index.start.cards).toHaveLength(1);
    const card = index.start.cards[0]!;
    expect(card.title).toBe('codelab');
    expect(card.readme?.repoPath).toBe('apps/codelab_cli/README.md');
    expect(card.readme?.description).toBe('Терминальный клиент');
    expect(card.all?.repoPath).toBe('apps/codelab_cli/doc/README.md');
  });

  it('«Пользоваться»: остальные docs/user и руководство приложения со свёрнутыми главами', () => {
    expect(repoPaths(index.use.docs)).toEqual(['docs/user/configuration.md', 'docs/user/zed.md']);
    expect(index.use.apps).toHaveLength(1);
    const app = index.use.apps[0]!;
    expect(app.title).toBe('codelab');
    expect(app.entry?.repoPath).toBe('apps/codelab_cli/doc/user-guide.md');
    expect(app.chapters.map((c) => [c.number, c.doc.title])).toEqual([
      ['00', 'Обзор'],
      ['01', 'Установка'],
    ]);
  });

  it('«Развернуть и разрабатывать»: docs/ops и подгруппы приложения', () => {
    expect(repoPaths(index.build.docs)).toEqual(['docs/ops/README.md', 'docs/ops/codelab-home.md']);
    const app = index.build.apps[0]!;
    expect(app.operations?.repoPath).toBe('apps/codelab_cli/doc/operations.md');
    expect(app.development.entry?.repoPath).toBe('apps/codelab_cli/doc/development.md');
    expect(app.development.chapters.map((c) => c.number)).toEqual(['00', '01']);
    expect(app.nested.map((n) => [n.title, n.items.length])).toEqual([['Рецепты', 2]]);
  });
});

describe('buildDocsIndex: вход не повторяется в главах (project-site «Главы руководства свёрнуты»)', () => {
  it('страница выводит только вход и главы: поля «вход + главы» в модели нет', () => {
    // Страница рендерит `entry` ссылкой, а `<details>` — только `chapters`;
    // третье поле «всё вместе» вернуло бы вход в список дважды.
    expect(Object.keys(index.use.apps[0]!).sort()).toEqual(['chapters', 'entry', 'title']);
    expect(Object.keys(index.build.apps[0]!.development).sort()).toEqual(['chapters', 'entry']);
  });

  it('вход не входит в главы ни руководства, ни разработки', () => {
    const app = index.use.apps[0]!;
    expect(app.chapters.map((c) => c.doc.repoPath)).not.toContain(app.entry!.repoPath);
    const dev = index.build.apps[0]!.development;
    expect(dev.chapters.map((c) => c.doc.repoPath)).not.toContain(dev.entry!.repoPath);
  });
});

describe('buildDocsIndex: один показ и пустые блоки', () => {
  it('каждый документ вне пакетов показан ровно один раз', () => {
    const shown: string[] = [
      ...index.start.links.map((x) => x.repoPath),
      ...index.start.cards.flatMap((c) => [c.readme?.repoPath, c.all?.repoPath].filter((x): x is string => !!x)),
      ...index.use.docs.map((x) => x.repoPath),
      ...index.use.apps.flatMap((a) => [a.entry?.repoPath, ...a.chapters.map((c) => c.doc.repoPath)].filter((x): x is string => !!x)),
      ...index.build.docs.map((x) => x.repoPath),
      ...index.build.apps.flatMap((a) =>
        [
          a.operations?.repoPath,
          a.development.entry?.repoPath,
          ...a.development.chapters.map((c) => c.doc.repoPath),
          ...a.nested.flatMap((n) => n.items.map((i) => i.doc.repoPath)),
        ].filter((x): x is string => !!x),
      ),
    ];
    const outsidePackages = docs.map((x) => x.repoPath).filter((p) => !p.startsWith('packages/'));
    expect([...shown].sort()).toEqual([...outsidePackages].sort());
    expect(new Set(shown).size).toBe(shown.length);
  });

  it('приложение с одним README — только карточка, без блоков «Пользоваться» и «Развернуть»', () => {
    const idx = buildDocsIndex(buildNav([d('apps/codelab_new/README.md', 'Новое', 'Новое приложение')]));
    expect(idx.start.cards.map((c) => c.title)).toEqual(['codelab_new']);
    expect(idx.start.cards[0]!.all).toBeNull();
    expect(idx.use.apps).toEqual([]);
    expect(idx.build.apps).toEqual([]);
  });

  it('без документов блоки пустые', () => {
    const idx = buildDocsIndex(buildNav<TestDoc>([]));
    expect(idx.start.links).toEqual([]);
    expect(idx.start.cards).toEqual([]);
    expect(idx.use.docs).toEqual([]);
    expect(idx.build.packages.layers).toEqual([]);
  });

  it('руководство без user-guide.md: нет входа, главы остаются', () => {
    const idx = buildDocsIndex(buildNav([d('apps/codelab_new/README.md', 'N'), d('apps/codelab_new/doc/user/00-a.md', 'А')]));
    expect(idx.use.apps[0]!.entry).toBeNull();
    expect(idx.use.apps[0]!.chapters).toHaveLength(1);
  });
});

describe('buildDocsIndex: пакеты по слоям (D3, D6)', () => {
  const layers = index.build.packages.layers;

  it('слои в порядке D3, «Проверки» после Flutter и перед «Другие»; пустые не выводятся', () => {
    expect(layers.map((l) => l.id)).toEqual([
      'packages-client',
      'packages-agent',
      'packages-shared',
      'packages-checks',
    ]);
    expect(layers.map((l) => l.title)).toEqual(['Клиент', 'Агент', 'Мосты и служебные пакеты', 'Проверки']);
  });

  it('сторож — в «Проверках», в «Мостах и служебных пакетах» его нет', () => {
    const shared = layers.find((l) => l.id === 'packages-shared')!;
    expect(shared.packages.map((p) => p.name)).toEqual(['codelab_noreadme', 'codelab_setup', 'codelab_sub', 'codelab_sub2', 'p']);
    expect(layers.find((l) => l.id === 'packages-checks')!.packages.map((p) => p.name)).toEqual([
      'codelab_architecture_tests',
    ]);
  });

  it('пакет с doc/: README с описанием, вход руководства и главы без входа', () => {
    const client = layers.find((l) => l.id === 'packages-client')!.packages.find((p) => p.name === 'codelab_client_core')!;
    expect(client.doc.repoPath).toBe('packages/dart/codelab_client_core/README.md');
    expect(client.description).toBe('Общий клиентский слой');
    expect(client.guide?.doc.repoPath).toBe('packages/dart/codelab_client_core/doc/README.md');
    expect(repoPaths(client.chapters.map((c) => c.doc))).toEqual(['packages/dart/codelab_client_core/doc/08-approvals.md']);
    expect(client.chaptersCount).toBe(1);
    expect(client).not.toHaveProperty('docCount');
  });

  it('«Руководство пакета в оглавлении»: ядро агента — главы, туториал и вложенный «Обзор»', () => {
    const core = layers.flatMap((l) => l.packages).find((p) => p.name === 'codelab_agent_core')!;
    expect(core.guide?.doc.title).toBe('Руководство по ядру агента');
    expect(core.chapters.map((c) => [c.number, c.doc.title])).toEqual([
      ['00', 'Начало работы'],
      ['01', 'Обзор ядра'],
      [null, 'Туториал: новый инструмент'],
    ]);
    expect(core.groups).toHaveLength(1);
    const group = core.groups[0]!;
    expect(group.title).toBe('Алгоритмы ядра агента');
    expect(group.items.map((i) => i.label)).toEqual(['Обзор', 'Сжатие', 'Цикл']);
    // N — документы doc/ без входа, включая подгруппу: 3 главы + 3 подгруппы.
    expect(core.chaptersCount).toBe(6);
  });

  it('«Каждый документ пакета один раз»: README и вход по разу, вход не в главах', () => {
    for (const pkg of layers.flatMap((l) => l.packages)) {
      const shown = [
        pkg.doc.repoPath,
        pkg.guide?.doc.repoPath,
        ...pkg.chapters.map((c) => c.doc.repoPath),
        ...pkg.groups.flatMap((g) => g.items.map((i) => i.doc.repoPath)),
      ].filter((x): x is string => !!x);
      expect(new Set(shown).size).toBe(shown.length);
      const own = docs.map((x) => x.repoPath).filter((x) => x.startsWith(`packages/dart/${pkg.name}/`));
      expect([...shown].sort()).toEqual([...own].sort());
    }
  });

  it('«Пакет без руководства»: одна ссылка на README, без входа и глав', () => {
    const store = layers.flatMap((l) => l.packages).find((p) => p.name === 'codelab_client_store')!;
    expect(store.doc.repoPath).toBe('packages/dart/codelab_client_store/README.md');
    expect(store.guide).toBeNull();
    expect(store.chapters).toEqual([]);
    expect(store.groups).toEqual([]);
    expect(store.chaptersCount).toBe(0);
  });

  it('«Руководство пакета без входа»: вход — первая глава, в главах остальные', () => {
    const p = layers.flatMap((l) => l.packages).find((x) => x.name === 'p')!;
    expect(p.guide?.doc.repoPath).toBe('packages/dart/p/doc/00-a.md');
    expect([p.guide?.number, p.guide?.doc.title]).toEqual(['00', 'Альфа']);
    expect(p.chapters.map((c) => [c.number, c.doc.title])).toEqual([['01', 'Бета']]);
    expect(p.chaptersCount).toBe(1);
  });

  it('пакет без README ведёт на первый документ, отдельной ссылки руководства нет', () => {
    const shared = layers.find((l) => l.id === 'packages-shared')!;
    const noReadme = shared.packages.find((p) => p.name === 'codelab_noreadme')!;
    expect(noReadme.doc.repoPath).toBe('packages/dart/codelab_noreadme/doc/01-a.md');
    expect(noReadme.guide).toBeNull();
    expect(noReadme.chaptersCount).toBe(0);
  });
});

describe('buildDocsIndex: правило (а) входа руководства пакета (D6)', () => {
  const all = () => index.build.packages.layers.flatMap((l) => l.packages);

  it('без README и без основного списка карточка ведёт на первый пункт подгруппы, он из подгруппы исключён', () => {
    const sub = all().find((p) => p.name === 'codelab_sub')!;
    expect(sub.doc.repoPath).toBe('packages/dart/codelab_sub/doc/algorithms/README.md');
    expect(sub.guide).toBeNull();
    expect(sub.groups.flatMap((g) => g.items.map((i) => i.doc.repoPath))).toEqual(['packages/dart/codelab_sub/doc/algorithms/a.md']);
    expect(sub.chaptersCount).toBe(1);
  });

  it('с README, но пустым основным списком: входа нет, подгруппа целая со своим «Обзором»', () => {
    const sub = all().find((p) => p.name === 'codelab_sub2')!;
    expect(sub.guide).toBeNull();
    expect(sub.groups[0]!.items.map((i) => i.label)).toEqual(['Обзор', 'Б']);
    expect(sub.chaptersCount).toBe(2);
  });
});
