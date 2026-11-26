/**
 * Шаги «Как это работает»: данные четырёх шагов и автомат автопроигрывания.
 *
 * Почему: главная показывает путь от открытия папки до ответа на запрос
 * разрешения (design.md redesign-site-showcase, D5). Каждый шаг ссылается на
 * раздел руководства, где он описан: витрина не показывает поведения, которого
 * нет в документации (D6). Автопроигрывание — автомат без `document` и с
 * переданным планировщиком (D2 п. 4); ручной выбор, пауза, невидимость и
 * наведение останавливают его, поздний таймер отбрасывается (R4).
 *
 * Для чего: `stepsData` читает страница при сборке (текст и `docRef` →
 * `docRefUrl`), `createSteps` — скрипт `src/scripts/showcase/steps.ts`.
 *
 * Как использовать: `createSteps({ scheduler, reduce })`, затем `start()`;
 * `select(i)` — выбор посетителя, он же ставит паузу; `resume()` — кнопка
 * «Продолжить». При `reduce` таймеров нет, шаги меняет только `select`
 * (D2 п. 6). Данные не читают файлы и безопасны для клиентского бандла.
 */
import { PauseGate } from './autoplay-gate';
import type { Scheduler } from './scheduler';

/** Шаг: заголовок, фраза и раздел руководства, где он описан. */
export interface StepData {
  readonly title: string;
  readonly text: string;
  /** `документ#якорь` опубликованного руководства; адрес строит `docRefUrl`. */
  readonly docRef: string;
}

/**
 * Четыре шага (D5). Тексты проверяются `docs-writer` по `docRef` (задача 6.1):
 * каждая фраза пересказывает раздел руководства, на который она ссылается.
 */
export const stepsData: readonly StepData[] = [
  {
    title: 'Откройте папку проекта',
    text: 'Сессии сгруппированы по проектам в боковой панели; недавние проекты доступны оттуда же.',
    docRef:
      'apps/codelab_desktop/doc/user/02-projects-and-sessions.md#открыть-проект-и-переключаться-между-проектами',
  },
  {
    title: 'Подключите провайдера модели',
    text: 'Мастер подключения проверяет, что сервер отвечает, и показывает файл, в который запишутся настройки.',
    docRef: 'apps/codelab_desktop/doc/user/07-providers-and-models.md#подключить-провайдера-модели',
  },
  {
    title: 'Попросите агента',
    text: 'Напишите сообщение в поле ввода: ответ, вызовы инструментов и их результаты появляются в ленте по мере работы агента.',
    docRef: 'apps/codelab_desktop/doc/user/03-conversation.md#вести-сессию-с-агентом',
  },
  {
    title: 'Ответьте на запрос разрешения',
    text: 'В режиме по умолчанию агент спрашивает разрешение перед правкой файла и запуском команды; запрос появляется в строке вызова в ленте.',
    docRef: 'apps/codelab_desktop/doc/user/04-permissions.md#отвечать-на-запросы-разрешений',
  },
];

/** Сколько держится шаг при автопроигрывании (D5), мс. */
export const stepIntervalMs = 6000;

/** Снимок состояния шагов для отрисовки. */
export interface StepsSnapshot {
  /** Показанный шаг, с 0. */
  readonly index: number;
  /** Автопроигрывание стоит по любой причине. */
  readonly paused: boolean;
  /** Пауза поставлена посетителем (кнопка или выбор шага): подпись кнопки берётся отсюда. */
  readonly userPaused: boolean;
}

export interface StepsOptions {
  readonly scheduler: Scheduler;
  /** `prefers-reduced-motion: reduce`: автопроигрывания нет. */
  readonly reduce: boolean;
  /** Число шагов; по умолчанию — длина [stepsData]. */
  readonly count?: number;
}

export interface Steps {
  snapshot(): StepsSnapshot;
  subscribe(listener: (snapshot: StepsSnapshot) => void): () => void;
  /** Начинает автопроигрывание; при `reduce` ничего не планирует. */
  start(): void;
  /** Ручной выбор шага: показывает его и останавливает автопроигрывание. */
  select(index: number): void;
  pause(): void;
  resume(): void;
  setVisible(visible: boolean): void;
  setEngaged(engaged: boolean): void;
}

export function createSteps(options: StepsOptions): Steps {
  const { scheduler, reduce } = options;
  const count = options.count ?? stepsData.length;
  const gate = new PauseGate();
  const listeners = new Set<(snapshot: StepsSnapshot) => void>();

  let index = 0;
  let started = false;
  let handle: unknown;
  // Эпоха отбрасывает поздний таймер прошлого шага (R4).
  let epoch = 0;

  const snapshot = (): StepsSnapshot => ({ index, paused: gate.paused, userPaused: gate.has('user') });
  const emit = (): void => {
    const current = snapshot();
    for (const listener of listeners) listener(current);
  };

  const cancel = (): void => {
    epoch++;
    if (handle !== undefined) scheduler.clear(handle);
    handle = undefined;
  };

  const schedule = (): void => {
    cancel();
    if (reduce || !started || gate.paused) return;
    const mine = epoch;
    handle = scheduler.set(() => {
      if (mine !== epoch) return;
      handle = undefined;
      index = (index + 1) % count;
      schedule();
      emit();
    }, stepIntervalMs);
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
      if (started) return;
      started = true;
      schedule();
    },
    select(next) {
      if (!Number.isInteger(next) || next < 0 || next >= count) return;
      index = next;
      gate.set('user', true);
      schedule();
      emit();
    },
    pause: () => changeGate(gate.set('user', true)),
    resume: () => changeGate(gate.set('user', false)),
    setVisible: (visible) => changeGate(gate.set('hidden', !visible)),
    setEngaged: (engaged) => changeGate(gate.set('engaged', engaged)),
  };
}
