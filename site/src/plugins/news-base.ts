/**
 * remark-плагин: `base` в корневых ссылках новостей выпусков.
 *
 * Почему: новость лежит в `site/` и ссылается на адреса сайта от корня
 * (`/docs/user/configuration/`). Markdown не может вызвать `withBase`, а Astro
 * не добавляет `base` к ссылкам Markdown, поэтому при `SITE_BASE=/codelab-app/`
 * такие ссылки вели бы мимо подкаталога (design.md add-astro-site, D10, D12;
 * skill `codelab-site` §5).
 *
 * Для чего: только для файлов коллекции `news` (`site/src/content/news/*.md`)
 * добавляет `base` к корневым ссылкам, изображениям и ссылкам-определениям
 * через `withBase`. Схемы `http:`, `https:`, `mailto:` и `#якорь` проходят
 * без изменений; любой другой адрес — другая схема, `//host`, относительный
 * путь — ошибка сборки (D10). Итоговые адреса проверяет `check-links` (D6),
 * а не `repoLinks`: документы репозитория плагин не трогает.
 *
 * Как использовать: `[remarkNewsBase, { repoRoot, base }]` в `remarkPlugins`
 * (`astro.config.mjs`). Нарушение — `file.fail` с путём файла от корня
 * репозитория и строкой.
 */
import type { Root } from 'mdast';
import { visit } from 'unist-util-visit';
import type { VFile } from 'vfile';

import { repoPath } from '../lib/repo-path';
import { withBase } from '../lib/urls';

export interface NewsBaseOptions {
  /** Абсолютный путь корня репозитория. */
  readonly repoRoot: string;
  /** `base` сайта вида `/…/` (D12). */
  readonly base: string;
}

/** Файлы коллекции `news` (`src/content.config.ts`). */
const newsFile = /^site\/src\/content\/news\/[^/]+\.md$/;

/** Схемы, которые новость может использовать как есть (D10). */
const allowedSchemes = new Set(['http:', 'https:', 'mailto:']);

export function remarkNewsBase({ repoRoot, base }: NewsBaseOptions) {
  return (tree: Root, file: VFile): void => {
    const path = repoPath(repoRoot, file.path);
    if (!newsFile.test(path)) return;

    visit(tree, (node) => {
      if (node.type !== 'link' && node.type !== 'image' && node.type !== 'definition') return;
      const url = node.url;
      const fail = (reason: string): never =>
        file.fail(
          `Link "${url}" in ${path}:${node.position?.start.line ?? '?'}: ${reason}. ` +
            'News links are site addresses from the root (/docs/…) or http:, https:, mailto: (D10)',
          node,
          'codelab-site:news-base',
        );

      if (url.startsWith('#')) return;
      // Браузер убирает табуляции и переводы строк из адреса: `java\tscript:`
      // для него — `javascript:`, поэтому схема ищется после той же очистки.
      const scheme = /^([A-Za-z][A-Za-z0-9+.-]*:)/.exec(url.replace(/[\t\n\r]/g, ''))?.[1];
      if (scheme !== undefined) {
        if (!allowedSchemes.has(scheme.toLowerCase())) fail(`scheme "${scheme}" is not allowed`);
        return;
      }
      // `//host/…` — внешний адрес без схемы, а не корень сайта.
      if (url.startsWith('//') || url.startsWith('/\\')) fail('protocol-relative addresses are not allowed');
      if (!url.startsWith('/')) fail('relative addresses are not allowed; use a site address from the root');
      node.url = withBase(url, base);
    });
  };
}
