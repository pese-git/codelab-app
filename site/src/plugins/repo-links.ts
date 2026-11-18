/**
 * remark-плагин `repoLinks`: относительные ссылки документов → адреса сайта
 * или GitHub.
 *
 * Почему: документы читаются и на GitHub, поэтому ссылки в них остаются
 * относительными путями репозитория, а на сайте должны вести на страницы
 * сайта или на файл на GitHub (design.md add-astro-site, D5; project-site
 * «Перевод относительных ссылок документации»).
 *
 * Для чего: обходит `link`, `image` и `definition` mdast документа коллекции
 * `docs`; битая ссылка — ошибка сборки с путём документа и строкой.
 *
 * Как использовать: `[remarkRepoLinks, { repoRoot, repoUrl, repoRef, base }]`
 * в remark-плагинах процессора Markdown; путь документа берётся из `file.path`.
 * `repoRef` — результат `resolveRepoRef()` из `src/site.config.ts`: по
 * умолчанию коммит сборки, чтобы ссылка на GitHub вела ровно на ту версию
 * файла, из которой собран сайт, и не давала 404 на файлы, которых ещё нет в
 * `master` (D5).
 */
import { readdirSync, statSync } from 'node:fs';
import { join, posix, relative, sep } from 'node:path';

import type { Root } from 'mdast';
import { visit } from 'unist-util-visit';
import type { VFile } from 'vfile';

import { isPublished } from '../lib/publish';
import { pageUrl } from '../lib/urls';

/** Настройки плагина. */
export interface RepoLinksOptions {
  /** Абсолютный путь корня репозитория. */
  readonly repoRoot: string;
  /** Адрес репозитория на GitHub (`site.config.ts`). */
  readonly repoUrl: string;
  /** Ревизия ссылок на GitHub (`resolveRepoRef()`). */
  readonly repoRef: string;
  /** Префикс адресов сайта вида `/…/` (D12). */
  readonly base: string;
}

/** Схемы, которые плагин не трогает (D5, п. 1). */
const passThroughSchemes = new Set(['http:', 'https:', 'mailto:']);

export function remarkRepoLinks(options: RepoLinksOptions) {
  const { repoRoot, repoUrl, repoRef, base } = options;
  // Содержимое каталогов кэшируется на время жизни процессора: сборка проверяет
  // сотни ссылок по одним и тем же каталогам.
  const listings = new Map<string, ReadonlySet<string> | null>();

  function list(dir: string): ReadonlySet<string> | null {
    if (!listings.has(dir)) {
      try {
        listings.set(dir, new Set(readdirSync(join(repoRoot, dir))));
      } catch {
        listings.set(dir, null);
      }
    }
    return listings.get(dir)!;
  }

  /**
   * Существует ли путь с точно таким регистром каждого сегмента.
   *
   * Почему не `existsSync`: на macOS файловая система регистронезависима, и
   * `Configuration.md` нашёлся бы, а на GitHub и в CI на Linux ссылка была бы
   * битой (D5). Поэтому каждый сегмент сверяется со списком каталога.
   */
  function existsExact(repoPath: string): boolean {
    if (repoPath === '') return true;
    let dir = '';
    for (const segment of repoPath.split('/')) {
      if (!list(dir)?.has(segment)) return false;
      dir = dir === '' ? segment : `${dir}/${segment}`;
    }
    return true;
  }

  return (tree: Root, file: VFile): void => {
    const docPath = relative(repoRoot, file.path).split(sep).join('/');
    const docDir = posix.dirname(docPath);

    visit(tree, (node) => {
      if (node.type !== 'link' && node.type !== 'image' && node.type !== 'definition') return;
      const url = node.url;

      const fail = (reason: string): never =>
        file.fail(
          `Broken link "${url}" in ${docPath}:${node.position?.start.line ?? '?'}: ${reason} (D5)`,
          node,
          'codelab-site:repo-links',
        );

      if (url.startsWith('#')) return;
      // `C:\…` проверяется раньше схем: иначе буква диска выглядит как схема.
      if (/^[A-Za-z]:[\\/]/.test(url)) fail('absolute Windows paths are not allowed');
      const scheme = /^([A-Za-z][A-Za-z0-9+.-]*:)/.exec(url)?.[1]?.toLowerCase();
      if (scheme !== undefined) {
        if (passThroughSchemes.has(scheme)) return;
        fail(`scheme "${scheme}" is not allowed; use a relative repository path`);
      }
      if (url.startsWith('/') || url.startsWith('\\')) {
        fail('absolute paths are not allowed; use a relative repository path');
      }
      if (url === '') fail('empty link');

      const hash = url.indexOf('#');
      const rawPath = hash === -1 ? url : url.slice(0, hash);
      const anchor = hash === -1 ? '' : url.slice(hash);
      let decoded: string;
      try {
        decoded = decodeURIComponent(rawPath);
      } catch {
        return fail('malformed percent-encoding');
      }
      const target = posix.normalize(posix.join(docDir, decoded)).replace(/\/+$/, '');
      if (target === '..' || target.startsWith('../')) fail('path leaves the repository root');
      const repoPath = target === '.' ? '' : target;

      if (!existsExact(repoPath)) {
        fail('file or directory does not exist (letter case must match exactly)');
      }

      if (node.type === 'image') {
        if ((node.alt ?? '').trim() === '') fail('image alt text is empty');
        // Существующее изображение остаётся относительным: его копирует и
        // оптимизирует Astro (D5, п. 3).
        return;
      }

      const isDirectory = statSync(join(repoRoot, repoPath)).isDirectory();
      if (!isDirectory && isPublished(repoPath)) {
        node.url = pageUrl(repoPath, base) + anchor;
      } else {
        const kind = isDirectory ? 'tree' : 'blob';
        const suffix = repoPath === '' ? '' : `/${repoPath}`;
        node.url = `${repoUrl}/${kind}/${repoRef}${suffix}${anchor}`;
      }
    });
  };
}
