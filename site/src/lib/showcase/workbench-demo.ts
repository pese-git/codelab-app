/**
 * Автомат живого макета рабочего места: промпт, ответ агента, запрос
 * разрешения, исход.
 *
 * Почему: главная идея продукта — агент спрашивает разрешение, а решает
 * пользователь (design.md redesign-site-showcase, D3). Демо поэтому доходит до
 * карточки запроса и останавливается: ответ за посетителя не выбирается ни при
 * каком времени. Состояние — конечный автомат без `document` и с
 * переданным планировщиком (D2 п. 4), чтобы vitest двигал время сам и
 * проверял гонки таймеров (R4; аналог «поздних событий», `AGENTS.md` §9).
 *
 * Для чего: переходы `idle → prompt → streaming → awaiting → allowed | rejected
 * → done`; из `done` — `restart()` в `idle`. Разметку и элементы управления
 * связывает с автоматом `src/scripts/showcase/workbench.ts`.
 *
 * Как использовать: `createWorkbench({ scheduler, reduce })`; `subscribe`
 * получает снимок после каждого изменения; `start()` запускает автопроигрывание
 * (при `reduce` — сразу `awaiting`, без таймеров: движения нет, D2 п. 6);
 * `allow()` и `reject()` действуют только из `awaiting`; `pause()` /
 * `resume()` — кнопка посетителя, `setVisible()` и `setEngaged()` — демо на
 * экране и наведение или фокус. Поздний таймер прошлого эпизода отбрасывается
 * по эпохе.
 */
import { PauseGate } from './autoplay-gate';
import type { Scheduler } from './scheduler';

export type WorkbenchState =
  | 'idle'
  | 'prompt'
  | 'streaming'
  | 'awaiting'
  | 'allowed'
  | 'rejected'
  | 'done';

/** Исход запроса разрешения. */
export type WorkbenchOutcome = 'allowed' | 'rejected';

/** Снимок состояния для отрисовки: разметка только отражает его. */
export interface WorkbenchSnapshot {
  readonly state: WorkbenchState;
  /** Сколько частей ответа агента уже показано (0…[parts]). */
  readonly streamed: number;
  /** Сколько частей в ответе агента. */
  readonly parts: number;
  /** Исход запроса разрешения; пока посетитель не ответил — `undefined`. */
  readonly outcome: WorkbenchOutcome | undefined;
  /** Автопроигрывание стоит по любой причине (кнопка, невидимость, наведение). */
  readonly paused: boolean;
  /** Пауза поставлена посетителем: подпись кнопки берётся из снимка. */
  readonly userPaused: boolean;
}

/** Задержки автопроигрывания, мс. */
export interface WorkbenchTimings {
  /** До появления промпта. */
  readonly start: number;
  /** Промпт на экране до начала ответа. */
  readonly prompt: number;
  /** Между частями ответа и до карточки запроса. */
  readonly part: number;
  /** От исхода до кнопки «Ещё раз». */
  readonly outcome: number;
}

/**
 * Первый шаг — сразу после запуска (`start: 0`), промпт уже стоит в ленте:
 * первый экран не должен выглядеть пустой рамкой (замечание ручной приёмки 6.2).
 */
const defaultTimings: WorkbenchTimings = { start: 0, prompt: 700, part: 500, outcome: 900 };

export interface WorkbenchOptions {
  readonly scheduler: Scheduler;
  /** `prefers-reduced-motion: reduce`: без таймеров и промежуточных состояний. */
  readonly reduce: boolean;
  /** Частей в ответе агента; по умолчанию 3. */
  readonly parts?: number;
  readonly timings?: Partial<WorkbenchTimings>;
}

export interface Workbench {
  snapshot(): WorkbenchSnapshot;
  /** Подписка на изменения; возвращает отписку. */
  subscribe(listener: (snapshot: WorkbenchSnapshot) => void): () => void;
  /** Запускает автопроигрывание из `idle`; повторный вызов ничего не делает. */
  start(): void;
  allow(): void;
  reject(): void;
  /** «Ещё раз»: сбрасывает сценарий в `idle`, отменяя все таймеры. */
  restart(): void;
  pause(): void;
  resume(): void;
  setVisible(visible: boolean): void;
  setEngaged(engaged: boolean): void;
}

export function createWorkbench(options: WorkbenchOptions): Workbench {
  const { scheduler, reduce } = options;
  const parts = options.parts ?? 3;
  const timings = { ...defaultTimings, ...options.timings };
  const gate = new PauseGate();
  const listeners = new Set<(snapshot: WorkbenchSnapshot) => void>();

  let state: WorkbenchState = 'idle';
  let streamed = 0;
  let outcome: WorkbenchOutcome | undefined;
  let started = false;
  let handle: unknown;
  // Эпоха растёт при каждой отмене: таймер прошлого эпизода, который всё же
  // сработал, ничего не меняет (R4).
  let epoch = 0;

  const snapshot = (): WorkbenchSnapshot => ({ state, streamed, parts, outcome, paused: gate.paused, userPaused: gate.has('user') });
  const emit = (): void => {
    const current = snapshot();
    for (const listener of listeners) listener(current);
  };

  const cancel = (): void => {
    epoch++;
    if (handle !== undefined) scheduler.clear(handle);
    handle = undefined;
  };

  /** Задержка до следующего шага автопроигрывания из текущего состояния. */
  const nextDelay = (): number | undefined => {
    switch (state) {
      case 'idle':
        return started ? timings.start : undefined;
      case 'prompt':
        return timings.prompt;
      case 'streaming':
        return timings.part;
      case 'allowed':
      case 'rejected':
        return timings.outcome;
      default:
        // `awaiting` ждёт посетителя, `done` — кнопки «Ещё раз».
        return undefined;
    }
  };

  const step = (): void => {
    switch (state) {
      case 'idle':
        state = 'prompt';
        break;
      case 'prompt':
        state = 'streaming';
        streamed = 0;
        break;
      case 'streaming':
        if (streamed < parts) streamed++;
        else state = 'awaiting';
        break;
      case 'allowed':
      case 'rejected':
        state = 'done';
        break;
      default:
        return;
    }
    schedule();
    emit();
  };

  const schedule = (): void => {
    cancel();
    // Показ последствий ответа (`allowed|rejected → done`) не зависит от паузы:
    // пауза при наведении и фокусе (D2 п. 6) останавливает автопроигрывание до
    // ответа, а курсор остаётся над кнопкой после клика. Иначе исход замирал бы
    // под курсором, а «Ещё раз» не появлялась (замечание ручной приёмки 6.2).
    const consequence = state === 'allowed' || state === 'rejected';
    if (reduce || (gate.paused && !consequence)) return;
    const delay = nextDelay();
    if (delay === undefined) return;
    const mine = epoch;
    handle = scheduler.set(() => {
      if (mine !== epoch) return;
      handle = undefined;
      step();
    }, delay);
  };

  const answer = (result: WorkbenchOutcome): void => {
    if (state !== 'awaiting') return;
    outcome = result;
    // При `reduce` исход показывается сразу, без промежуточного состояния.
    state = reduce ? 'done' : result;
    schedule();
    emit();
  };

  const changeGate = (changed: boolean): void => {
    if (!changed) return;
    schedule();
    emit();
  };

  return {
    snapshot,
    subscribe(listener) {
      listeners.add(listener);
      return () => listeners.delete(listener);
    },
    start() {
      if (started || state !== 'idle') return;
      started = true;
      if (reduce) {
        // Весь ответ сразу: печати по частям при `reduce` нет.
        state = 'awaiting';
        streamed = parts;
        emit();
        return;
      }
      schedule();
    },
    allow: () => answer('allowed'),
    reject: () => answer('rejected'),
    restart() {
      cancel();
      state = 'idle';
      streamed = 0;
      outcome = undefined;
      started = false;
      // «Ещё раз» — явная просьба повторить: пауза посетителя не должна
      // оставлять демо в idle.
      gate.set('user', false);
      emit();
    },
    pause: () => changeGate(gate.set('user', true)),
    resume: () => changeGate(gate.set('user', false)),
    setVisible: (visible) => changeGate(gate.set('hidden', !visible)),
    setEngaged: (engaged) => changeGate(gate.set('engaged', engaged)),
  };
}
