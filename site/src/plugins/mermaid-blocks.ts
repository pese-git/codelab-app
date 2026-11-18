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
 *
 * Состояние: заглушка красных тестов задачи 3.5 (tasks.md); реализация — 3.6.
 */
import type { Root } from 'mdast';

export function remarkMermaidBlocks() {
  return (_tree: Root): void => {
    throw new Error('not implemented');
  };
}
