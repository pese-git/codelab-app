/**
 * Демо «Клавиши ответа codelab»: кнопки `<kbd>` и физические клавиши.
 *
 * Почему: показать, что одна клавиша отвечает на запрос разрешения
 * (design.md redesign-site-showcase, D5). Ответ — слова таблицы руководства
 * (подтверждены `quote` при сборке, `scenarios.ts`); логика сопоставления —
 * `lib/showcase/cli-keys.ts`.
 *
 * Для чего: корень `[data-demo="cli-keys"]`; нажатие кнопки или клавиши
 * показывает ответ в области `aria-live="polite"`. Без скрипта остаётся
 * таблица клавиш.
 *
 * Как использовать: подключается компонентом `CliKeysDemo.astro`. Клавиши
 * перехватываются только когда фокус внутри демо (слушатель на корне); клавиши
 * с Ctrl, Alt и Meta не трогаются, чтобы не ломать сочетания браузера.
 */
import { answerForKey, type CliKeyRow } from '../../lib/showcase/cli-keys';
import { goLive } from './live';

for (const root of document.querySelectorAll<HTMLElement>('[data-demo="cli-keys"]')) {
  goLive(root);
  const output = root.querySelector<HTMLElement>('[data-announce]');
  const buttons = [...root.querySelectorAll<HTMLButtonElement>('button[data-key]')];
  const rows: (CliKeyRow & { button: HTMLButtonElement })[] = buttons.map((button) => ({
    key: button.dataset.key ?? '',
    answer: button.dataset.answer ?? '',
    button,
  }));

  const show = (row: (typeof rows)[number]): void => {
    for (const other of rows) other.button.setAttribute('aria-pressed', String(other === row));
    if (output) output.textContent = `${row.key} — ${row.answer}`;
  };

  for (const row of rows) row.button.addEventListener('click', () => show(row));

  root.addEventListener('keydown', (event) => {
    if (event.ctrlKey || event.altKey || event.metaKey) return;
    const row = answerForKey(rows, event.key);
    if (!row) return;
    event.preventDefault();
    show(row);
  });
}
