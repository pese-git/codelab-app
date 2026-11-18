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
 * Как использовать: `[remarkHomePaths, { repoRoot }]` в remark-плагинах
 * процессора Markdown. Нарушение — `file.fail` с путём файла от корня
 * репозитория и строкой узла, как у `repoLinks` (D5).
 */
import type { Root } from 'mdast';
import { visit } from 'unist-util-visit';
import type { VFile } from 'vfile';

import { findHomePaths } from '../lib/home-paths';
import { repoPath } from '../lib/repo-path';

export interface HomePathsOptions {
  /** Абсолютный путь корня репозитория: от него считается путь в сообщении. */
  readonly repoRoot: string;
}

export function remarkHomePaths({ repoRoot }: HomePathsOptions) {
  return (tree: Root, file: VFile): void => {
    const path = repoPath(repoRoot, file.path);
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
          `Personal home directory path "${found.path}" ` +
            `in ${path}:${node.position?.start.line ?? '?'}: ` +
            'mask the user name as "user" or "me" (codelab-docs §7, D11)',
          node,
          'codelab-site:home-paths',
        );
      }
    });
  };
}
