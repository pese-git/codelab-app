/**
 * Планировщик таймеров, передаваемый автоматам витрины снаружи.
 *
 * Почему: автомат демо не обращается ни к `document`, ни к глобальному
 * `setTimeout` (design.md redesign-site-showcase, D2 п. 4): тест двигает
 * время сам, а гонка позднего таймера (R4) воспроизводится без ожидания.
 *
 * Для чего: единственная зависимость автоматов `workbench-demo.ts` и
 * `steps.ts` от времени.
 *
 * Как использовать: в браузере — `browserScheduler`; в тестах —
 * `FakeScheduler` из `test/support/fake-scheduler.ts`.
 */
export interface Scheduler {
  /** Запускает [run] через [ms] миллисекунд; возвращает ручку для [clear]. */
  set(run: () => void, ms: number): unknown;
  /** Отменяет таймер по ручке из [set]; повторная отмена безопасна. */
  clear(handle: unknown): void;
}

/** Планировщик на `setTimeout` браузера; создаётся только в клиентских скриптах. */
export const browserScheduler: Scheduler = {
  set: (run, ms) => setTimeout(run, ms),
  clear: (handle) => clearTimeout(handle as ReturnType<typeof setTimeout>),
};
