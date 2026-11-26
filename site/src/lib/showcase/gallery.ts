/**
 * Текстовые снимки терминала для галереи.
 *
 * Почему: терминал на витрине — не картинка, а текст блока кода из документа
 * CLI: его можно выделить и прочитать с экрана, а рассинхрон с руководством
 * ломает сборку (design.md redesign-site-showcase, D9, D6). PNG терминала
 * `apps/codelab_cli/doc/images/` нет и снимать их вне change.
 *
 * Для чего: `Gallery.astro` читает `terminalShots` в frontmatter.
 *
 * Как использовать: `terminalShots` — для страниц; `createTerminalShots(sources)`
 * — в тестах на заглушке. Новый снимок — запись в `terminalShotRefs`: раздел
 * и номер блока кода. Подпись — слова витрины, не цитата: текст снимка из документа подтверждает `snippet`.
 */
import { snippet } from './sources';
import type { ShowcaseSources } from './sources';

export interface TerminalShot {
  readonly caption: string;
  /** `документ#якорь` раздела — «подробнее». */
  readonly docRef: string;
  /** Номер блока кода в разделе, с 1. */
  readonly block: number;
}

export interface TerminalShotText extends TerminalShot {
  readonly text: string;
}

/** Какие блоки показываются, в каком порядке: заголовки — из руководства `codelab`. */
export const terminalShotRefs: readonly TerminalShot[] = [
  {
    caption: 'Блок одобрения правки файла',
    docRef: 'apps/codelab_cli/doc/user/02-repl.md#разрешения',
    block: 1,
  },
  {
    caption: 'Строка статуса после хода',
    docRef: 'apps/codelab_cli/doc/user/02-repl.md#строка-статуса',
    block: 1,
  },
  {
    caption: 'Список выбора режима',
    docRef: 'apps/codelab_cli/doc/user/03-tui.md#списки-выбора',
    block: 1,
  },
];

/** Читает блоки через [sources]; отсутствующий раздел или блок — ошибка источника. */
export function createTerminalShots(sources: Pick<ShowcaseSources, 'snippet'>): TerminalShotText[] {
  return terminalShotRefs.map((shot) => ({ ...shot, text: sources.snippet(shot.docRef, shot.block) }));
}

/** Снимки настоящего репозитория: сверка источников идёт при импорте (D6). */
export const terminalShots: readonly TerminalShotText[] = createTerminalShots({ snippet });
