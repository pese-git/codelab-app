/**
 * Обёртка: remark-плагин работает только на документах из allowlist.
 *
 * Почему: конвейер Markdown у Astro один на все коллекции, а `repoLinks`
 * нужен только документам репозитория. Новости (`site/src/content/news/`)
 * ссылаются на адреса сайта, их проверяет `check-links`, а не плагин ссылок
 * (design.md add-astro-site, D5, D10).
 *
 * Для чего: применяет плагин к файлу, только если путь от корня репозитория
 * опубликован (`isPublished`, D3); остальные файлы проходят без изменений.
 *
 * Как использовать: `[onlyPublished(remarkRepoLinks, repoRoot), options]` в
 * `remarkPlugins` (`astro.config.mjs`).
 */
import { relative, sep } from 'node:path';

import type { Root } from 'mdast';
import type { VFile } from 'vfile';

import { isPublished } from '../lib/publish';

type Transform = (tree: Root, file: VFile) => void;

export function onlyPublished<O extends unknown[]>(
  plugin: (...options: O) => Transform | void,
  repoRoot: string,
) {
  return function (...options: O): Transform {
    const transform = plugin(...options);
    return (tree, file) => {
      if (!transform || file.path === undefined) return;
      const repoPath = relative(repoRoot, file.path).split(sep).join('/');
      // `..` в начале — файл вне репозитория; такой путь не опубликован.
      if (repoPath.startsWith('../') || !isPublished(repoPath)) return;
      transform(tree, file);
    };
  };
}
