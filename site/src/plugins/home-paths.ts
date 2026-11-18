/**
 * remark-плагин: абсолютный путь домашнего каталога в документе — ошибка
 * сборки.
 *
 * Почему: снимки вывода в документах легко приносят личное имя пользователя
 * (`/Users/alice/…`); `codelab-docs` §7 требует масок `user` и `me` (design.md
 * add-astro-site, D11; project-site «Безопасность публикации»).
 *
 * Для чего: проверяет текст, инлайн-код и блоки кода документа; маски —
 * одна константа в `src/lib/`, её же читает `check-links` (D6).
 *
 * Как использовать: `remarkHomePaths` в remark-плагинах процессора Markdown.
 *
 * Состояние: заглушка красных тестов задачи 3.7 (tasks.md); реализация — 3.8.
 */
import type { Root } from 'mdast';

export function remarkHomePaths() {
  return (_tree: Root): void => {
    throw new Error('not implemented');
  };
}
