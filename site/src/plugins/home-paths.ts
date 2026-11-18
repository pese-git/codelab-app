/**
 * remark-плагин: абсолютный путь домашнего каталога в документе — ошибка
 * сборки.
 *
 * Почему: снимки вывода в документах легко приносят личное имя пользователя
 * (`/Users/alice/…`); `codelab-docs` §7 требует масок `user` и `me` (design.md
 * add-astro-site, D11; project-site «Безопасность публикации»).
 *
 * Для чего: проверяет текст, инлайн-код, блоки кода, сырой HTML и адреса
 * ссылок документа; маски и поиск — `src/lib/home-paths.ts`, их же читает
 * `check-links` (D6).
 *
 * Как использовать: `remarkHomePaths` в remark-плагинах процессора Markdown.
 * Нарушение — `file.fail` с путём файла и строкой узла.
 */
import type { Root } from 'mdast';
import { visit } from 'unist-util-visit';
import type { VFile } from 'vfile';

import { findHomePaths } from '../lib/home-paths';

export function remarkHomePaths() {
  return (tree: Root, file: VFile): void => {
    visit(tree, (node) => {
      const texts: string[] = [];
      if ('value' in node && typeof node.value === 'string') texts.push(node.value);
      if ('url' in node && typeof node.url === 'string') texts.push(node.url);
      for (const text of texts) {
        const [found] = findHomePaths(text);
        if (!found) continue;
        // Строка — первая строка узла: для блока кода это строка ограждения,
        // по ней автор находит блок; сам путь назван в сообщении.
        file.fail(
          `Personal home directory path "${found.path}" in ${file.path}: ` +
            'mask the user name as "user" or "me" (codelab-docs §7, D11)',
          node,
          'codelab-site:home-paths',
        );
      }
    });
  };
}
