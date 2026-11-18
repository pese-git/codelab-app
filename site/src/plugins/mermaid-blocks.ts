/**
 * remark-плагин: блок кода `mermaid` → `pre[data-mermaid]` с исходником схемы.
 *
 * Почему: схемы отрисовывает `mermaid.js` в браузере, а без JavaScript должен
 * остаться виден исходный текст; блок не должен проходить подсветку Shiki
 * (design.md add-astro-site, D7; project-site «Mermaid-схемы в браузере»).
 *
 * Для чего: заменяет `code` с `lang === 'mermaid'` обычным узлом дерева —
 * `pre.mermaid-source[data-mermaid]` через `data.hName`/`hProperties`,
 * исходник внутри текстовым узлом. Экранирует сериализатор; узел не сырой
 * HTML, поэтому защита D11 его не отвергает. `data-mermaid` — только метка
 * для ленивого скрипта `src/scripts/mermaid.ts`, исходник в атрибуте не
 * дублируется.
 *
 * Как использовать: `remarkMermaidBlocks` в remark-плагинах процессора Markdown.
 */
import type { Data, Parent, Root, Text } from 'mdast';
import { visit } from 'unist-util-visit';

/**
 * Узел исходника схемы. Свой тип, а не `paragraph`: плагины, которые правят
 * текст абзацев (например, типографские кавычки), не должны менять синтаксис
 * схемы.
 */
export interface MermaidSource extends Parent {
  type: 'mermaidSource';
  children: Text[];
  data: Data;
}

declare module 'mdast' {
  interface RootContentMap {
    mermaidSource: MermaidSource;
  }
  interface BlockContentMap {
    mermaidSource: MermaidSource;
  }
}

export function remarkMermaidBlocks() {
  return (tree: Root): void => {
    visit(tree, 'code', (node, index, parent) => {
      if (node.lang !== 'mermaid' || parent === undefined || index === undefined) return;
      const text: Text = { type: 'text', value: node.value };
      const replacement: MermaidSource = {
        type: 'mermaidSource',
        children: [text],
        data: {
          hName: 'pre',
          hProperties: { className: ['mermaid-source'], dataMermaid: '' },
          // hChildren фиксирует исходник для HTML: даже если более поздний
          // remark-плагин изменит текстовый узел, схема уйдёт в браузер как есть.
          hChildren: [{ type: 'text', value: node.value }],
        },
      };
      if (node.position) replacement.position = node.position;
      parent.children.splice(index, 1, replacement);
    });
  };
}
