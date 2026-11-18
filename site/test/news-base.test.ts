// Тесты префикса `base` в ссылках новостей (design.md add-astro-site, D10,
// D12; skill `codelab-site` §5). Новость пишет адреса сайта от корня без
// `base`, плагин добавляет его; схемы, кроме `http:`, `https:`, `mailto:`, —
// ошибка сборки с путём файла от корня репозитория и строкой.
import { mkdirSync, mkdtempSync, readFileSync, rmSync, writeFileSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { dirname, join } from 'node:path';

import type { Root } from 'mdast';
import rehypeStringify from 'rehype-stringify';
import remarkParse from 'remark-parse';
import remarkRehype from 'remark-rehype';
import { unified } from 'unified';
import { visit } from 'unist-util-visit';
import { VFile } from 'vfile';
import { afterEach, beforeEach, describe, expect, it } from 'vitest';

import { checkDist } from '../scripts/check-links.mjs';
import { remarkNewsBase } from '../src/plugins/news-base';

const repoRoot = '/repo';
const newsFile = '/repo/site/src/content/news/0.1.0.md';

/** Адреса ссылок, изображений и определений после плагина. */
async function urls(markdown: string, base: string, path = newsFile): Promise<string[]> {
  const processor = unified().use(remarkParse).use(remarkNewsBase, { repoRoot, base });
  const file = new VFile({ path, value: markdown });
  const tree = (await processor.run(processor.parse(file), file)) as Root;
  const result: string[] = [];
  visit(tree, (node) => {
    if (node.type === 'link' || node.type === 'image' || node.type === 'definition') {
      result.push(node.url);
    }
  });
  return result;
}

const sample =
  '# CodeLab 0.1.0\n\n' +
  '- [Настройка](/docs/user/configuration/#шаг-2)\n' +
  '- ![Палитра](/news/palette.png)\n' +
  '- [Журнал][changelog]\n' +
  '- [Внешняя](https://github.com/pese-git/codelab-app/blob/master/CHANGELOG.md)\n' +
  '- [Почта](mailto:team@example.com)\n' +
  '- [Раздел](#детали)\n\n' +
  '[changelog]: /news/\n';

describe('remarkNewsBase: base добавляется к корневым адресам', () => {
  it('base / — адреса не меняются', async () => {
    expect(await urls(sample, '/')).toEqual([
      '/docs/user/configuration/#шаг-2',
      '/news/palette.png',
      'https://github.com/pese-git/codelab-app/blob/master/CHANGELOG.md',
      'mailto:team@example.com',
      '#детали',
      '/news/',
    ]);
  });

  it('base /codelab-app/ — к ссылкам, изображениям и определениям', async () => {
    expect(await urls(sample, '/codelab-app/')).toEqual([
      '/codelab-app/docs/user/configuration/#шаг-2',
      '/codelab-app/news/palette.png',
      'https://github.com/pese-git/codelab-app/blob/master/CHANGELOG.md',
      'mailto:team@example.com',
      '#детали',
      '/codelab-app/news/',
    ]);
  });

  it('документы репозитория плагин не трогает: их ссылки переводит repoLinks', async () => {
    expect(await urls('[x](/docs/user/)\n', '/codelab-app/', '/repo/docs/user/README.md')).toEqual([
      '/docs/user/',
    ]);
  });
});

describe('remarkNewsBase: недопустимые адреса — ошибка с путём от корня и строкой', () => {
  it.each([
    ['javascript:', '[x](javascript:alert(1))', 3],
    ['data:', '![x](data:image/png;base64,AAAA)', 3],
    ['file:', '[x](file:///etc/passwd)', 3],
    ['ftp:', '[x](ftp://example.com/a)', 3],
    ['адрес без схемы //host', '[x](//cdn.example.com/a)', 3],
    ['относительный путь', '[x](../docs/user/)', 3],
    ['путь Windows', '[x](C:\\Users\\user\\a.md)', 3],
    ['определение', '[x][y]\n\n[y]: javascript:alert(1)', 5],
  ])('%s', async (_name, markdown, line) => {
    const error = await urls(`# Новость\n\n${markdown}\n`, '/codelab-app/').catch((e: unknown) => e);
    expect(error).toMatchObject({
      file: newsFile,
      line,
      message: expect.stringContaining(`site/src/content/news/0.1.0.md:${line}`),
    });
    expect((error as Error).message).not.toContain('/repo/');
  });
});

describe('remarkNewsBase + check-links: фикстура новости при base /codelab-app/', () => {
  let dist: string;

  beforeEach(() => {
    dist = mkdtempSync(join(tmpdir(), 'codelab-site-news-'));
  });

  afterEach(() => {
    rmSync(dist, { recursive: true, force: true });
  });

  function write(path: string, content: string): void {
    mkdirSync(dirname(join(dist, path)), { recursive: true });
    writeFileSync(join(dist, path), content);
  }

  /** Мини-`dist/`: страница новости из фикстуры и целевая страница документа. */
  async function build(withPlugin: boolean): Promise<void> {
    const base = '/codelab-app/';
    const markdown = readFileSync(new URL('./fixtures/news/0.1.0.md', import.meta.url), 'utf8')
      .replace(/^---[\s\S]*?---\n/, '');
    const processor = unified().use(remarkParse);
    if (withPlugin) processor.use(remarkNewsBase, { repoRoot, base });
    const html = await processor
      .use(remarkRehype)
      .use(rehypeStringify)
      .process(new VFile({ path: newsFile, value: markdown }));
    write('news/0.1.0/index.html', `<!DOCTYPE html><html><body>${String(html)}</body></html>`);
    write(
      'docs/user/configuration/index.html',
      '<!DOCTYPE html><html><body><h1 id="настройка-агента">Настройка</h1></body></html>',
    );
  }

  it('с плагином ссылки фикстуры проходят check-links', async () => {
    await build(true);
    expect(checkDist({ dist, base: '/codelab-app/' })).toEqual([]);
  });

  it('без плагина корневая ссылка фикстуры — нарушение (фикстура проверяет base)', async () => {
    await build(false);
    expect(checkDist({ dist, base: '/codelab-app/' })).toEqual([
      // remark-rehype пишет якорь в процентной кодировке.
      expect.objectContaining({
        file: 'news/0.1.0/index.html',
        link: `/docs/user/configuration/#${encodeURIComponent('настройка-агента')}`,
      }),
    ]);
  });
});
