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
 *
 * Состояние: заглушка красных тестов задачи 3.3 (tasks.md); реализация — 3.4.
 */
import type { Root } from 'mdast';

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

export function remarkRepoLinks(_options: RepoLinksOptions) {
  return (_tree: Root): void => {
    throw new Error('not implemented');
  };
}
