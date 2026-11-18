/**
 * rehype-плагин: сырой HTML документа вне короткого списка — ошибка сборки.
 *
 * Почему: GitHub вырезает `script`, `iframe`, `style` и обработчики событий при
 * показе документа, а на сайте они бы выполнились; санитайзер молча менял бы
 * содержимое, поэтому — ошибка с позицией (design.md add-astro-site, D11;
 * project-site «Безопасность публикации»).
 *
 * Для чего: допускает `details`, `summary`, `br`, `kbd`, `sub`, `sup` без
 * атрибутов (исключение — `open` у `details`); любой другой атрибут, в том
 * числе обработчик события, — ошибка. Удаляет HTML-комментарии (маркеры
 * скриншотов `codelab-docs`). Узлы плагинов (D7) сырым HTML не являются.
 *
 * Как использовать: `rehypeRawHtmlGuard` в rehype-плагинах процессора Markdown;
 * работает до `rehype-raw`, на узлах `raw`.
 *
 * Состояние: заглушка красных тестов задачи 3.7 (tasks.md); реализация — 3.8.
 */
import type { Root } from 'hast';

export function rehypeRawHtmlGuard() {
  return (_tree: Root): void => {
    throw new Error('not implemented');
  };
}
