// Тесты автомата шагов «Как это работает» (tasks.md redesign-site-showcase, 3.3;
// D5, R4; project-site «Интерактивные демо витрины»: «Ручной выбор шага
// останавливает автопроигрывание», «Уменьшение движения»). Планировщик
// фальшивый, время двигает тест.
import { describe, expect, it } from 'vitest';

import { createSteps, stepIntervalMs } from '../src/lib/showcase/steps';
import { FakeScheduler } from './support/fake-scheduler';

function setup(options: { reduce?: boolean } = {}) {
  const scheduler = new FakeScheduler();
  const steps = createSteps({ scheduler, reduce: options.reduce ?? false });
  return { scheduler, steps };
}

describe('автопроигрывание', () => {
  it('шаг держится 6 секунд, затем следующий', () => {
    expect(stepIntervalMs).toBe(6000);
    const { scheduler, steps } = setup();
    steps.start();
    expect(steps.snapshot().index).toBe(0);
    scheduler.advance(5_999);
    expect(steps.snapshot().index).toBe(0);
    scheduler.advance(1);
    expect(steps.snapshot().index).toBe(1);
  });

  it('идёт по кругу: после четвёртого шага — первый', () => {
    const { scheduler, steps } = setup();
    steps.start();
    scheduler.advance(6_000 * 3);
    expect(steps.snapshot().index).toBe(3);
    scheduler.advance(6_000);
    expect(steps.snapshot().index).toBe(0);
  });

  it('повторный start не дублирует таймер', () => {
    const { scheduler, steps } = setup();
    steps.start();
    steps.start();
    expect(scheduler.pending).toBe(1);
  });
});

describe('ручной выбор', () => {
  it('показывает выбранный шаг и останавливает автопроигрывание', () => {
    const { scheduler, steps } = setup();
    steps.start();
    scheduler.advance(2_000);
    steps.select(2);
    expect(steps.snapshot()).toMatchObject({ index: 2, paused: true });
    expect(scheduler.pending).toBe(0);
    scheduler.advance(10 * 60 * 1000);
    expect(steps.snapshot().index).toBe(2);
  });

  it('несуществующий шаг игнорируется', () => {
    const { steps } = setup();
    steps.start();
    steps.select(4);
    steps.select(-1);
    expect(steps.snapshot().index).toBe(0);
  });

  it('«Продолжить» после ручного выбора возобновляет проигрывание с выбранного шага', () => {
    const { scheduler, steps } = setup();
    steps.start();
    steps.select(2);
    steps.resume();
    expect(scheduler.pending).toBe(1);
    scheduler.advance(6_000);
    expect(steps.snapshot().index).toBe(3);
  });
});

describe('пауза посетителя в снимке', () => {
  it('после select снимок userPaused=true, а невидимость его не ставит', () => {
    const { steps } = setup();
    steps.start();
    expect(steps.snapshot().userPaused).toBe(false);
    steps.setVisible(false);
    expect(steps.snapshot()).toMatchObject({ paused: true, userPaused: false });
    steps.select(1);
    expect(steps.snapshot().userPaused).toBe(true);
  });

  it('выбор вкладки, затем «Продолжить»: пауза снята, проигрывание идёт', () => {
    const { scheduler, steps } = setup();
    steps.start();
    steps.select(2);
    steps.resume();
    expect(steps.snapshot()).toMatchObject({ userPaused: false, paused: false });
    scheduler.advance(6_000);
    expect(steps.snapshot().index).toBe(3);
  });
});

describe('пауза, невидимость, наведение', () => {
  it('пауза отменяет таймер, продолжение не дублирует его', () => {
    const { scheduler, steps } = setup();
    steps.start();
    steps.pause();
    expect(scheduler.pending).toBe(0);
    scheduler.advance(60_000);
    expect(steps.snapshot().index).toBe(0);
    steps.resume();
    steps.resume();
    expect(scheduler.pending).toBe(1);
  });

  it('невидимость останавливает проигрывание, возвращение продолжает', () => {
    const { scheduler, steps } = setup();
    steps.start();
    steps.setVisible(false);
    scheduler.advance(60_000);
    expect(steps.snapshot().index).toBe(0);
    steps.setVisible(true);
    scheduler.advance(6_000);
    expect(steps.snapshot().index).toBe(1);
  });

  it('наведение и фокус — отдельная причина; пауза посетителя уход курсора не снимает', () => {
    const { scheduler, steps } = setup();
    steps.start();
    steps.pause();
    steps.setEngaged(true);
    steps.setEngaged(false);
    expect(scheduler.pending).toBe(0);
    expect(steps.snapshot().paused).toBe(true);
  });

  it('поздний таймер прошлого шага не переключает выбранный вручную', () => {
    const { scheduler, steps } = setup();
    steps.start();
    scheduler.advance(5_000);
    steps.select(3);
    scheduler.advance(60_000);
    expect(steps.snapshot().index).toBe(3);
  });
});

describe('уменьшение движения', () => {
  it('start не проигрывает сам: нет таймеров, шаг остаётся первым', () => {
    const { scheduler, steps } = setup({ reduce: true });
    steps.start();
    expect(scheduler.pending).toBe(0);
    scheduler.advance(60_000);
    expect(steps.snapshot().index).toBe(0);
  });

  it('ручной выбор работает и без таймеров', () => {
    const { scheduler, steps } = setup({ reduce: true });
    steps.start();
    steps.select(1);
    steps.resume();
    expect(steps.snapshot().index).toBe(1);
    expect(scheduler.pending).toBe(0);
  });
});

describe('подписка', () => {
  it('слушатель получает снимок при смене шага и отписывается', () => {
    const { scheduler, steps } = setup();
    const seen: number[] = [];
    const off = steps.subscribe((s) => seen.push(s.index));
    steps.start();
    scheduler.advance(6_000);
    off();
    scheduler.advance(6_000);
    expect(seen).toEqual([1]);
  });
});
