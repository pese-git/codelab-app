// Тесты плагина repoLinks (tasks.md add-astro-site, 3.3; D5; project-site
// «Перевод относительных ссылок документации», все сценарии) на виртуальном
// репозитории во временном каталоге, через тот же конвейер unified, что у
// Astro (remark-parse → плагин), без сети (D14).
import { mkdirSync, mkdtempSync, rmSync, writeFileSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { dirname, join } from 'node:path';

import type { Root } from 'mdast';
import remarkParse from 'remark-parse';
import { unified } from 'unified';
import { visit } from 'unist-util-visit';
import { VFile } from 'vfile';
import { afterAll, beforeAll, describe, expect, it } from 'vitest';

import { remarkRepoLinks } from '../src/plugins/repo-links';
import { RepoRefError, resolveRepoRef } from '../src/site.config';

const repoUrl = 'https://github.com/pese-git/codelab-app';
const repoRef = 'abc123';
const base = '/codelab-app/';

let tmp: string;
let root: string;

// Мини-репозиторий: опубликованные и неопубликованные файлы, изображение,
// каталог пакета и файл за пределами корня.
const files = [
  'docs/user/README.md',
  'docs/user/configuration.md',
  'docs/ops/README.md',
  'docs/architecture/testing.md',
  'apps/codelab_cli/README.md',
  'apps/codelab_cli/doc/operations.md',
  'apps/codelab_cli/doc/user-guide.md',
  'apps/codelab_desktop/doc/user-guide.md',
  'apps/codelab_desktop/doc/images/command-palette.png',
  'packages/dart/codelab_setup/README.md',
  'packages/dart/codelab_setup/lib/codelab_setup.dart',
];

beforeAll(() => {
  tmp = mkdtempSync(join(tmpdir(), 'codelab-site-repo-links-'));
  root = join(tmp, 'repo');
  for (const file of files) {
    mkdirSync(dirname(join(root, file)), { recursive: true });
    writeFileSync(join(root, file), '# x\n');
  }
  // Существующий файл вне корня: выход за корень — ошибка, даже если файл есть.
  writeFileSync(join(tmp, 'outside.md'), '# outside\n');
});

afterAll(() => {
  rmSync(tmp, { recursive: true, force: true });
});

/** Прогоняет документ [doc] (путь от корня) через плагин и возвращает mdast. */
async function run(doc: string, markdown: string): Promise<Root> {
  const processor = unified()
    .use(remarkParse)
    .use(remarkRepoLinks, { repoRoot: root, repoUrl, repoRef, base });
  const file = new VFile({ path: join(root, doc), value: markdown });
  return (await processor.run(processor.parse(file), file)) as Root;
}

/** Адреса всех ссылок, изображений и определений дерева по порядку. */
function urls(tree: Root): string[] {
  const result: string[] = [];
  visit(tree, (node) => {
    if (node.type === 'link' || node.type === 'image' || node.type === 'definition') {
      result.push(node.url);
    }
  });
  return result;
}

async function urlOf(doc: string, markdown: string): Promise<string> {
  const [url] = urls(await run(doc, markdown));
  return url!;
}

describe('repoLinks: опубликованные файлы → адреса сайта', () => {
  it('ссылка с якорем ведёт на страницу сайта с учётом base', async () => {
    expect(
      await urlOf('docs/user/README.md', '[Настройка](configuration.md#шаг-2-задайте-ключ-api)\n'),
    ).toBe('/codelab-app/docs/user/configuration/#шаг-2-задайте-ключ-api');
  });

  it('ссылка без якоря', async () => {
    expect(await urlOf('docs/user/README.md', '[Настройка](./configuration.md)\n')).toBe(
      '/codelab-app/docs/user/configuration/',
    );
  });

  it('README.md даёт адрес каталога', async () => {
    expect(await urlOf('docs/user/README.md', '[CLI](../../apps/codelab_cli/README.md)\n')).toBe(
      '/codelab-app/docs/apps/codelab_cli/',
    );
  });

  it('ссылка на файл приложения из сквозного документа', async () => {
    expect(
      await urlOf('docs/ops/README.md', '[Эксплуатация](../../apps/codelab_cli/doc/operations.md)\n'),
    ).toBe('/codelab-app/docs/apps/codelab_cli/doc/operations/');
  });

  it('ссылка-определение обрабатывается так же', async () => {
    const tree = await run('docs/user/README.md', '[Настройка][cfg]\n\n[cfg]: configuration.md#шаг-1\n');
    expect(urls(tree)).toEqual(['/codelab-app/docs/user/configuration/#шаг-1']);
  });
});

describe('repoLinks: неопубликованное → GitHub', () => {
  it('файл → blob на ревизии сборки, якорь сохраняется', async () => {
    expect(
      await urlOf('docs/user/README.md', '[Тесты](../architecture/testing.md#74-ci-levels)\n'),
    ).toBe(`${repoUrl}/blob/${repoRef}/docs/architecture/testing.md#74-ci-levels`);
  });

  it('каталог → tree', async () => {
    expect(
      await urlOf('docs/user/README.md', '[codelab_setup](../../packages/dart/codelab_setup/)\n'),
    ).toBe(`${repoUrl}/tree/${repoRef}/packages/dart/codelab_setup`);
  });

  it('исходный файл пакета → blob', async () => {
    expect(
      await urlOf(
        'packages/dart/codelab_setup/README.md',
        '[Барель](lib/codelab_setup.dart)\n',
      ),
    ).toBe(`${repoUrl}/blob/${repoRef}/packages/dart/codelab_setup/lib/codelab_setup.dart`);
  });

  it('ссылка (не изображение) на картинку — как на неопубликованный файл', async () => {
    expect(
      await urlOf('apps/codelab_desktop/doc/user-guide.md', '[Снимок](images/command-palette.png)\n'),
    ).toBe(`${repoUrl}/blob/${repoRef}/apps/codelab_desktop/doc/images/command-palette.png`);
  });
});

describe('repoLinks: изображения', () => {
  it('существующее изображение остаётся относительным путём', async () => {
    expect(
      await urlOf('apps/codelab_desktop/doc/user-guide.md', '![Палитра команд](images/command-palette.png)\n'),
    ).toBe('images/command-palette.png');
  });

  it('пустой alt — ошибка с путём документа и строкой', async () => {
    await expect(
      run('apps/codelab_desktop/doc/user-guide.md', '# Руководство\n\n![](images/command-palette.png)\n'),
    ).rejects.toMatchObject({
      message: expect.stringContaining('apps/codelab_desktop/doc/user-guide.md'),
      line: 3,
    });
  });

  it('несуществующее изображение — ошибка', async () => {
    await expect(
      run('apps/codelab_desktop/doc/user-guide.md', '![Нет](images/missing.png)\n'),
    ).rejects.toMatchObject({ message: expect.stringContaining('images/missing.png') });
  });
});

describe('repoLinks: не меняются', () => {
  it.each([
    'https://fvm.app',
    'http://example.com/x',
    'mailto:team@example.com',
    '#раздел-на-странице',
  ])('%s', async (url) => {
    expect(await urlOf('docs/user/README.md', `[x](${url})\n`)).toBe(url);
  });
});

describe('repoLinks: ошибки сборки с путём документа, строкой и ссылкой', () => {
  it('несуществующий файл (сценарий «Битая ссылка ломает сборку»)', async () => {
    await expect(
      run('apps/codelab_cli/doc/user-guide.md', '# Руководство\n\nСм. [эксплуатацию](operation.md).\n'),
    ).rejects.toMatchObject({
      message: expect.stringMatching(/apps\/codelab_cli\/doc\/user-guide\.md.*operation\.md|operation\.md.*apps\/codelab_cli\/doc\/user-guide\.md/s),
      line: 3,
    });
  });

  it.each([
    ['выход за корень', '../../../outside.md'],
    ['абсолютный путь', '/etc/passwd'],
    ['путь Windows', 'C:\\Users\\x\\doc.md'],
    ['file:', 'file:///etc/passwd'],
  ])('%s: %s', async (_name, url) => {
    await expect(
      run('docs/user/README.md', `# Пользователю\n\n[x](${url})\n`),
    ).rejects.toMatchObject({
      message: expect.stringContaining('docs/user/README.md'),
      line: 3,
    });
  });

  it('другой регистр имени — ошибка, даже на регистронезависимой ФС', async () => {
    await expect(
      run('docs/user/README.md', '[Настройка](Configuration.md)\n'),
    ).rejects.toMatchObject({ message: expect.stringContaining('Configuration.md') });
  });

  it('другой регистр каталога — ошибка', async () => {
    await expect(
      run('docs/user/README.md', '[CLI](../../apps/Codelab_cli/README.md)\n'),
    ).rejects.toMatchObject({ message: expect.stringContaining('Codelab_cli') });
  });

  it('ссылка-определение на несуществующий файл — ошибка', async () => {
    await expect(
      run('docs/user/README.md', '[x][d]\n\n[d]: missing.md\n'),
    ).rejects.toMatchObject({ message: expect.stringContaining('missing.md'), line: 3 });
  });
});

describe('resolveRepoRef (сценарии «Ссылка на GitHub ведёт на коммит сборки», «Цель ссылок задана явно»)', () => {
  const head = () => 'head-sha';

  it('SITE_GITHUB_REF важнее GITHUB_SHA', () => {
    expect(resolveRepoRef({ SITE_GITHUB_REF: 'master', GITHUB_SHA: 'ci-sha' }, head)).toBe('master');
  });

  it('GITHUB_SHA важнее HEAD', () => {
    expect(resolveRepoRef({ GITHUB_SHA: 'ci-sha' }, head)).toBe('ci-sha');
  });

  it('без переменных — HEAD', () => {
    expect(resolveRepoRef({}, head)).toBe('head-sha');
  });

  it('пустые переменные не считаются', () => {
    expect(resolveRepoRef({ SITE_GITHUB_REF: ' ', GITHUB_SHA: '' }, head)).toBe('head-sha');
  });

  it('без всех трёх — ошибка сборки', () => {
    expect(() => resolveRepoRef({}, () => undefined)).toThrow(RepoRefError);
  });
});
