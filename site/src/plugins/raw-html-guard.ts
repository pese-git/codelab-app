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
 * Как использовать: `[rehypeRawHtmlGuard, { repoRoot }]` в rehype-плагинах
 * процессора Markdown; работает до `rehype-raw`, на узлах `raw`. В сообщении —
 * путь файла от корня репозитория и строка, как у `repoLinks` (D5).
 */
import type { Root } from 'hast';
import { SKIP, visit } from 'unist-util-visit';
import type { VFile } from 'vfile';

import { repoPath } from '../lib/repo-path';

/** Элементы, которые автор документа может писать сырым HTML (D11). */
const allowedElements = new Set(['details', 'summary', 'br', 'kbd', 'sub', 'sup']);

/** Единственный разрешённый атрибут: `open` у `details` (D11). */
const allowedAttributes: Readonly<Record<string, ReadonlySet<string>>> = {
  details: new Set(['open']),
};

const comment = /<!--[\s\S]*?-->/g;

/**
 * Тег целиком: имя, атрибуты (значения в кавычках могут содержать `>`) и
 * необязательный `/` самозакрывающегося тега.
 */
const tag =
  /<(\/?)([A-Za-z][A-Za-z0-9:-]*)((?:\s+[^\s"'>/=]+(?:\s*=\s*(?:"[^"]*"|'[^']*'|[^\s"'=<>`]+))?)*)\s*\/?>/y;

const attribute = /([^\s"'>/=]+)(?:\s*=\s*(?:"[^"]*"|'[^']*'|[^\s"'=<>`]+))?/g;

/**
 * Первое нарушение в фрагменте сырого HTML или `undefined`.
 *
 * Почему разбор регулярными выражениями, а не парсером: проверяется короткий
 * список простых тегов без атрибутов, а всё, что не разобралось как тег
 * (`<!DOCTYPE`, `<?…`, `<![CDATA[`, искажённый тег), считается нарушением —
 * разбор строже браузера, а не мягче.
 */
function findViolation(html: string): string | undefined {
  for (let i = html.indexOf('<'); i !== -1; i = html.indexOf('<', i + 1)) {
    const next = html[i + 1] ?? '';
    // Одиночный `<` в тексте блока HTML (`1 < 2`) — не тег.
    if (!/[A-Za-z/!?]/.test(next)) continue;
    tag.lastIndex = i;
    const match = tag.exec(html);
    if (!match) return `unparsed HTML markup "${html.slice(i, i + 20)}"`;
    const [, closing, rawName = '', attrs = ''] = match;
    const name = rawName.toLowerCase();
    if (!allowedElements.has(name)) return `element <${name}>`;
    for (const [, attr = ''] of attrs.matchAll(attribute)) {
      const attrName = attr.toLowerCase();
      if (closing || !allowedAttributes[name]?.has(attrName)) {
        return `attribute "${attrName}" on <${name}>`;
      }
    }
    i = tag.lastIndex - 1;
  }
  return undefined;
}

export interface RawHtmlGuardOptions {
  /** Абсолютный путь корня репозитория: от него считается путь в сообщении. */
  readonly repoRoot: string;
}

export function rehypeRawHtmlGuard({ repoRoot }: RawHtmlGuardOptions) {
  return (tree: Root, file: VFile): void => {
    const path = repoPath(repoRoot, file.path);
    visit(tree, 'raw', (node, index, parent) => {
      // Комментарии не нужны в HTML страницы: это служебные пометки авторов
      // (маркеры скриншотов `codelab-docs`), и на сайте их не видно.
      const value = node.value.replace(comment, '');
      const violation = findViolation(value);
      if (violation) {
        file.fail(
          `Raw HTML is not allowed in published documents: ${violation} ` +
            `in ${path}:${node.position?.start.line ?? '?'}. ` +
            'Only <details>, <summary>, <br>, <kbd>, <sub>, <sup> without attributes ' +
            '(except "open" on <details>) are allowed (D11)',
          node,
          'codelab-site:raw-html-guard',
        );
      }
      if (value.trim() === '' && parent && index !== undefined) {
        parent.children.splice(index, 1);
        return [SKIP, index];
      }
      node.value = value;
      return undefined;
    });
  };
}
