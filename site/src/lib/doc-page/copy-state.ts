/**
 * Автомат состояния кнопки «Копировать» у блока кода.
 *
 * Почему: запись в буфер обмена асинхронна, а посетитель может нажать
 * кнопку повторно, не дождавшись ответа и таймера. Позднее завершение старого
 * нажатия не должно менять состояние нового (design.md improve-docs-navigation,
 * D7, R7; `AGENTS.md` §12).
 *
 * Для чего: чистая логика без `document` и без `setTimeout`; время приходит
 * через `Scheduler` витрины, поэтому тест двигает его сам.
 *
 * Как использовать: DOM-слой на каждое нажатие вызывает `press()`, пишет в
 * буфер и по итогу — `settle(номер, успех)`. Переходы:
 * `idle → copied | failed → idle` через `holdMs` (2 с). Фраза `announcement`
 * выводится в общую область `aria-live`.
 */
import type { Scheduler } from '../showcase/scheduler';

export type CopyStatus = 'idle' | 'copied' | 'failed';

export interface CopySnapshot {
  readonly status: CopyStatus;
  /** Фраза для `aria-live`; пусто, пока кнопка в покое. */
  readonly announcement: string;
}

export interface CopyState {
  snapshot(): CopySnapshot;
  /** Подписка на изменения; возвращает функцию отписки. */
  subscribe(listener: (snapshot: CopySnapshot) => void): () => void;
  /** Начинает нажатие: отменяет таймер предыдущего и возвращает номер нажатия. */
  press(): number;
  /** Фиксирует итог нажатия [press]; результат устаревшего нажатия игнорируется. */
  settle(press: number, ok: boolean): void;
}

const copied: CopySnapshot = { status: 'copied', announcement: 'Код скопирован' };
const failed: CopySnapshot = { status: 'failed', announcement: 'Не удалось скопировать' };
const idle: CopySnapshot = { status: 'idle', announcement: '' };

export function createCopyState(options: { scheduler: Scheduler; holdMs?: number }): CopyState {
  const { scheduler, holdMs = 2000 } = options;
  let current = idle;
  let latest = 0;
  let timer: unknown;
  const listeners = new Set<(snapshot: CopySnapshot) => void>();

  const set = (next: CopySnapshot): void => {
    current = next;
    for (const listener of [...listeners]) listener(next);
  };

  return {
    snapshot: () => current,
    subscribe(listener) {
      listeners.add(listener);
      return () => listeners.delete(listener);
    },
    press() {
      latest += 1;
      scheduler.clear(timer);
      return latest;
    },
    settle(press, ok) {
      if (press !== latest) return;
      scheduler.clear(timer);
      set(ok ? copied : failed);
      timer = scheduler.set(() => {
        // Номер проверяется ещё раз: страховка, если clear не успел отменить таймер.
        if (press === latest) set(idle);
      }, holdMs);
    },
  };
}
