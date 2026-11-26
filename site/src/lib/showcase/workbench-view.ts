/**
 * Что видно в макете рабочего места в каждом состоянии автомата.
 *
 * Почему: разметка не должна принимать решений о сценарии — состояние лежит в
 * автомате (design.md redesign-site-showcase, D3, D2 п. 4). Здесь состояние
 * переводится в «что показать»; тест проверяет таблицу без браузера.
 *
 * Для чего: `src/scripts/showcase/workbench.ts` применяет результат к узлам:
 * `data-part="i"` — часть ответа, `data-card`, `data-outcome`, `data-reset`.
 *
 * Как использовать: `workbenchView(createWorkbench(…).snapshot())`.
 */
import type { WorkbenchOutcome, WorkbenchSnapshot } from './workbench-demo';

export interface WorkbenchView {
  /** Промпт посетителя стоит в ленте с первого кадра: первый экран не пуст. */
  readonly promptShown: boolean;
  /** Сколько частей ответа (текст и строка вызова) показано. */
  readonly partsShown: number;
  /** Карточка запроса разрешения видна и в исходе: решение остаётся на экране. */
  readonly cardShown: boolean;
  /** Кнопки карточки работают только пока посетитель не ответил. */
  readonly cardActive: boolean;
  /** Посетитель ответил: заголовок «Ждёт одобрения» больше не верен. */
  readonly cardResolved: boolean;
  readonly outcome: WorkbenchOutcome | undefined;
  readonly resetShown: boolean;
  /** Автопроигрывание идёт или может идти: кнопка «Пауза» имеет смысл. */
  readonly canPause: boolean;
}

export function workbenchView(snapshot: WorkbenchSnapshot): WorkbenchView {
  const { state, streamed, parts, outcome } = snapshot;
  const atCard = state === 'awaiting' || state === 'allowed' || state === 'rejected' || state === 'done';
  return {
    promptShown: true,
    partsShown: atCard ? parts : state === 'streaming' ? streamed : 0,
    cardShown: atCard,
    cardActive: state === 'awaiting',
    cardResolved: atCard && state !== 'awaiting',
    outcome,
    resetShown: state === 'done',
    // На `awaiting` автопроигрывание ждёт посетителя, на `done` — «Ещё раз».
    canPause: state !== 'awaiting' && state !== 'done',
  };
}
