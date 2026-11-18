// Тесты защиты от сырого HTML (tasks.md add-astro-site, 3.7; D11;
// project-site «Безопасность публикации»). Конвейер повторяет порядок Astro
// (`@astrojs/markdown-remark`): remark-rehype с allowDangerousHtml → плагины
// rehype → (rehype-raw) → rehype-stringify; плагин видит узлы `raw`.
// Разрешённые элементы — без атрибутов, кроме `open` у `details` (D11).
import rehypeStringify from 'rehype-stringify';
import remarkParse from 'remark-parse';
import remarkRehype from 'remark-rehype';
import { unified } from 'unified';
import { VFile } from 'vfile';
import { describe, expect, it } from 'vitest';

import { remarkMermaidBlocks } from '../src/plugins/mermaid-blocks';
import { rehypeRawHtmlGuard } from '../src/plugins/raw-html-guard';

const doc = '/repo/docs/user/guide.md';

async function render(markdown: string, withMermaid = false): Promise<string> {
  const processor = unified().use(remarkParse);
  if (withMermaid) processor.use(remarkMermaidBlocks);
  const result = await processor
    .use(remarkRehype, { allowDangerousHtml: true })
    .use(rehypeRawHtmlGuard, { repoRoot: '/repo' })
    .use(rehypeStringify, { allowDangerousHtml: true })
    .process(new VFile({ path: doc, value: markdown }));
  return String(result);
}

describe('rehypeRawHtmlGuard: запрещённые элементы', () => {
  it.each([
    ['script', '<script>alert(1)</script>'],
    ['iframe', '<iframe src="https://example.com"></iframe>'],
    ['style', '<style>body { display: none }</style>'],
    ['img', '<img src="x" onerror="alert(1)">'],
    ['div', '<div>блок</div>'],
    ['SCRIPT', '<SCRIPT>alert(1)</SCRIPT>'],
  ])('%s → ошибка с путём файла и строкой', async (tag, html) => {
    await expect(render(`# Руководство\n\n${html}\n`)).rejects.toMatchObject({
      message: expect.stringContaining(tag.toLowerCase()),
      file: doc,
      line: 3,
    });
  });

  it.each([
    ['kbd', '<kbd onclick="alert(1)">Ctrl</kbd>'],
    ['details', '<details class="x">\n<summary>Ещё</summary>\n\nТекст.\n\n</details>'],
    ['summary', '<details>\n<summary style="color:red">Ещё</summary>\n\nТекст.\n\n</details>'],
    ['sup', '<sup id="x">2</sup>'],
  ])('атрибут у разрешённого %s → ошибка с путём файла и строкой', async (tag, html) => {
    await expect(render(`# Руководство\n\n${html}\n`)).rejects.toMatchObject({
      message: expect.stringContaining(tag),
      file: doc,
      line: 3,
    });
  });

  it('встроенный запрещённый элемент в абзаце — ошибка', async () => {
    await expect(render('Текст <span>внутри</span> абзаца.\n')).rejects.toMatchObject({
      message: expect.stringContaining('span'),
      line: 1,
    });
  });
});

describe('rehypeRawHtmlGuard: допустимое', () => {
  it('details, summary, br, kbd, sub, sup без атрибутов проходят', async () => {
    const html = await render(
      [
        '<details>',
        '<summary>Подробнее</summary>',
        '',
        'Нажмите <kbd>Ctrl</kbd>+<kbd>K</kbd>, H<sub>2</sub>O, x<sup>2</sup>,<br>строка<br/>',
        '',
        '</details>',
        '',
      ].join('\n'),
    );
    expect(html).toContain('<details>');
    expect(html).toContain('<kbd>Ctrl</kbd>');
    expect(html).toContain('<sub>2</sub>');
  });

  it('<details open> проходит: open — единственный разрешённый атрибут', async () => {
    const html = await render('<details open>\n<summary>Подробнее</summary>\n\nТекст.\n\n</details>\n');
    expect(html).toContain('<details open>');
  });

  it('HTML-комментарий проходит и не попадает в HTML (сценарий «Маркер скриншота»)', async () => {
    const html = await render('# Палитра\n\n<!-- screenshot: палитра команд -->\n\nТекст.\n');
    expect(html).not.toContain('screenshot');
    expect(html).not.toContain('<!--');
    expect(html).toContain('Текст.');
  });

  it('HTML внутри блока и инлайн-кода — это текст, а не элемент', async () => {
    const html = await render('```html\n<script>alert(1)</script>\n```\n\nТег `<div>` в тексте.\n');
    expect(html).toContain('&#x3C;script>');
  });

  it('блок mermaid после плагина 3.6 проходит: это узел дерева, а не сырой HTML (D7)', async () => {
    const html = await render('```mermaid\nflowchart LR\n  A --> B\n```\n', true);
    expect(html).toMatch(/<pre\b[^>]*class="mermaid-source"/);
    expect(html).toContain('data-mermaid');
  });
});

describe('rehypeRawHtmlGuard: формат сообщения', () => {
  it('путь файла от корня репозитория и строка, без абсолютного пути', async () => {
    const error = await render('# Руководство\n\n<script>alert(1)</script>\n').catch((e: unknown) => e);
    expect((error as Error).message).toContain('in docs/user/guide.md:3');
    expect((error as Error).message).not.toContain('/repo/');
  });
});
