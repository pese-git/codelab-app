// Фальшивый планировщик для тестов автоматов витрины (D2 п. 4, D13): время
// двигает тест, реальных таймеров нет.
import type { Scheduler } from '../../src/lib/showcase/scheduler';

export class FakeScheduler implements Scheduler {
  private now = 0;
  private nextId = 1;
  private tasks = new Map<number, { at: number; run: () => void }>();

  set(run: () => void, ms: number): number {
    const id = this.nextId++;
    this.tasks.set(id, { at: this.now + ms, run });
    return id;
  }

  clear(handle: unknown): void {
    this.tasks.delete(handle as number);
  }

  /** Число ещё не сработавших таймеров. */
  get pending(): number {
    return this.tasks.size;
  }

  /** Двигает время на [ms], запуская таймеры в порядке срабатывания (в том числе созданные по пути). */
  advance(ms: number): void {
    const target = this.now + ms;
    for (;;) {
      const next = [...this.tasks.entries()]
        .filter(([, t]) => t.at <= target)
        .sort((a, b) => a[1].at - b[1].at || a[0] - b[0])[0];
      if (next === undefined) break;
      this.tasks.delete(next[0]);
      this.now = next[1].at;
      next[1].run();
    }
    this.now = target;
  }
}
