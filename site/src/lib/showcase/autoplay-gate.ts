/**
 * Причины, по которым автопроигрывание демо стоит.
 *
 * Почему: проигрывание останавливают независимо друг от друга кнопка «Пауза»
 * (WCAG 2.2.2), уход демо с экрана и наведение или фокус внутри него
 * (design.md redesign-site-showcase, D2 п. 6). Одним флагом это не выразить:
 * уход курсора не должен снять паузу, выбранную посетителем.
 *
 * Для чего: общий счётчик причин для автоматов `workbench-demo.ts` и
 * `steps.ts`; проигрывание идёт, только когда снята каждая причина.
 *
 * Как использовать: `gate.set('user', true)` ставит причину, `false` снимает;
 * `set` возвращает `true`, если итог «стоит / идёт» изменился, — тогда автомат
 * отменяет или планирует таймер.
 */
export type PauseReason = 'user' | 'hidden' | 'engaged';

export class PauseGate {
  private readonly reasons = new Set<PauseReason>();

  /** Стоит ли проигрывание хотя бы по одной причине. */
  get paused(): boolean {
    return this.reasons.size > 0;
  }

  /** Ставит или снимает [reason]; `true`, если [paused] изменилось. */
  set(reason: PauseReason, on: boolean): boolean {
    const before = this.paused;
    if (on) this.reasons.add(reason);
    else this.reasons.delete(reason);
    return before !== this.paused;
  }

  /** Стоит ли проигрывание именно по [reason]. */
  has(reason: PauseReason): boolean {
    return this.reasons.has(reason);
  }
}
