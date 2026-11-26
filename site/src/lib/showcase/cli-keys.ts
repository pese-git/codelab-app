/**
 * Ответ демо «Клавиши ответа codelab» на нажатую клавишу.
 *
 * Почему: кнопки `<kbd>` и физические клавиши должны давать один и тот же
 * ответ из таблицы руководства (design.md redesign-site-showcase, D5; строки
 * подтверждает `quote`, `scenarios.ts`). Регистр различается: в `codelab`
 * `n` — «отклонить один раз», `N` — «отклонять всегда».
 *
 * Для чего: чистая функция для `src/scripts/showcase/cli-keys.ts`; перехват
 * клавиш — только при фокусе внутри демо (D5), скрипт сам решает, чьё событие.
 *
 * Как использовать: `answerForKey(rows, event.key)`; `undefined` — клавиши в
 * таблице нет, событие нельзя отменять.
 */
export interface CliKeyRow {
  readonly key: string;
  readonly answer: string;
}

export function answerForKey<T extends CliKeyRow>(rows: readonly T[], key: string): T | undefined {
  return rows.find((row) => row.key === key);
}
