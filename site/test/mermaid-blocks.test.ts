// Тесты плагина mermaid-блоков (tasks.md add-astro-site, 3.5; D7;
// project-site «Mermaid-схемы в браузере», сценарий «Без JavaScript»).
// Плагин отдаёт обычный узел дерева (`data.hName`/`hProperties`), а не сырой
// HTML: экранирование делает сериализатор, защита D11 узел не видит.
import type { Root, RootContent } from 'mdast';
import rehypeStringify from 'rehype-stringify';
import remarkParse from 'remark-parse';
import remarkRehype from 'remark-rehype';
import { unified } from 'unified';
import { describe, expect, it } from 'vitest';

import { remarkMermaidBlocks } from '../src/plugins/mermaid-blocks';

async function run(markdown: string): Promise<Root> {
  const processor = unified().use(remarkParse).use(remarkMermaidBlocks);
  return (await processor.run(processor.parse(markdown))) as Root;
}

async function render(markdown: string): Promise<string> {
  return String(
    await unified()
      .use(remarkParse)
      .use(remarkMermaidBlocks)
      .use(remarkRehype, { allowDangerousHtml: true })
      .use(rehypeStringify, { allowDangerousHtml: true })
      .process(markdown),
  );
}

/** Текст всех текстовых потомков узла по порядку. */
function textOf(node: RootContent): string {
  if (node.type === 'text') return node.value;
  return 'children' in node ? node.children.map((c) => textOf(c as RootContent)).join('') : '';
}

const source = 'flowchart LR\n  A["a & b"] --> B<br/>';
const mermaid = '```mermaid\n' + source + '\n```\n';

describe('remarkMermaidBlocks: узел дерева', () => {
  it('блок mermaid → pre.mermaid-source[data-mermaid] через data.hName/hProperties, не сырой HTML', async () => {
    const tree = await run(mermaid);
    expect(tree.children).toHaveLength(1);
    const [node] = tree.children;
    expect(node?.type).not.toBe('html');
    expect(node?.type).not.toBe('code');
    expect(node?.data).toMatchObject({ hName: 'pre' });
    const props = (node?.data as { hProperties?: Record<string, unknown> }).hProperties ?? {};
    const className = props.className ?? props.class;
    expect([className].flat().join(' ')).toContain('mermaid-source');
    expect(Object.keys(props).some((k) => k === 'data-mermaid' || k === 'dataMermaid')).toBe(true);
  });

  it('исходник схемы — текстовым узлом внутри pre, без изменений', async () => {
    const [node] = (await run(mermaid)).children;
    expect(textOf(node!)).toBe(source);
  });

  it('заменяет каждый блок mermaid документа', async () => {
    const tree = await run(`${mermaid}\nТекст.\n\n${mermaid}`);
    expect(tree.children.map((n) => n.data?.hName ?? n.type)).toEqual(['pre', 'paragraph', 'pre']);
  });

  it.each([
    ['другой язык', '```js\nconst a = 1 < 2;\n```\n', 'js'],
    ['без языка', '```\nflowchart LR\n```\n', null],
  ])('не меняет блок: %s', async (_name, markdown, lang) => {
    const [node] = (await run(markdown)).children;
    expect(node).toMatchObject({ type: 'code', lang });
    expect(node?.data?.hName).toBeUndefined();
  });
});

describe('remarkMermaidBlocks: HTML', () => {
  it('pre с классом и меткой, без подсветки блока', async () => {
    const html = await render(mermaid);
    expect(html).toMatch(/<pre\b[^>]*class="mermaid-source"/);
    expect(html).toMatch(/<pre\b[^>]*\sdata-mermaid(=""|\s|>)/);
    expect(html).not.toContain('language-mermaid');
    expect(html).not.toContain('<code');
  });

  it('экранирует <, > и & исходного текста', async () => {
    const html = await render(mermaid);
    expect(html).toContain('flowchart LR');
    expect(html).toMatch(/(&lt;|&#x3C;)br\/(&gt;|>)/);
    expect(html).toMatch(/a (&amp;|&#x26;) b/);
    expect(html).not.toContain('<br/>');
    expect(html).not.toContain('a & b');
  });

  it('исходник в атрибуте не дублируется: data-mermaid — только метка', async () => {
    const html = await render(mermaid);
    const tag = html.match(/<pre\b[^>]*>/)?.[0] ?? '';
    expect(tag).not.toContain('flowchart');
  });
});
