// Тесты автомата живого макета (tasks.md redesign-site-showcase, 3.1; D3, R4;
// project-site «Интерактивные демо витрины»: «Посетитель разрешает правку»,
// «Посетитель отклоняет правку», «Автопроигрывание не отвечает за посетителя»,
// «Повторное нажатие после исхода», «Уменьшение движения»). Планировщик
// фальшивый, время двигает тест.
import { describe, expect, it } from 'vitest';

import { createWorkbench, type WorkbenchState } from '../src/lib/showcase/workbench-demo';
import { FakeScheduler } from './support/fake-scheduler';

function setup(options: { reduce?: boolean } = {}) {
  const scheduler = new FakeScheduler();
  const demo = createWorkbench({ scheduler, reduce: options.reduce ?? false });
  const visited: WorkbenchState[] = [demo.snapshot().state];
  demo.subscribe((s) => visited.push(s.state));
  return { scheduler, demo, visited };
}

/** Двигает время, пока не дойдёт до карточки запроса. */
const toAwaiting = (s: ReturnType<typeof setup>) => {
  s.demo.start();
  s.scheduler.advance(60_000);
};

describe('первый кадр без пустоты', () => {
  it('первый шаг сразу после start: стартовой паузы нет', () => {
    const s = setup();
    s.demo.start();
    s.scheduler.advance(0);
    expect(s.demo.snapshot().state).toBe('prompt');
  });

  it('до карточки запроса проходит не больше пяти секунд', () => {
    const s = setup();
    s.demo.start();
    s.scheduler.advance(5_000);
    expect(s.demo.snapshot().state).toBe('awaiting');
  });
});

describe('автопроигрывание', () => {
  it('idle → prompt → streaming → awaiting по порядку', () => {
    const s = setup();
    s.demo.start();
    s.scheduler.advance(60_000);
    expect(s.visited.filter((v, i, a) => v !== a[i - 1])).toEqual(['idle', 'prompt', 'streaming', 'awaiting']);
  });

  it('ответ появляется частями: streamed растёт до parts', () => {
    const s = setup();
    s.demo.start();
    s.scheduler.advance(60_000);
    const snap = s.demo.snapshot();
    expect(snap.streamed).toBe(snap.parts);
    expect(snap.parts).toBeGreaterThan(1);
  });

  it('останавливается на awaiting при любом прошедшем времени, ответ не выбран', () => {
    const s = setup();
    toAwaiting(s);
    s.scheduler.advance(10 * 60 * 60 * 1000);
    expect(s.demo.snapshot()).toMatchObject({ state: 'awaiting', outcome: undefined });
    expect(s.scheduler.pending).toBe(0);
  });
});

describe('ответ посетителя', () => {
  it('allow из awaiting — исход allowed, затем done с исходом', () => {
    const s = setup();
    toAwaiting(s);
    s.demo.allow();
    expect(s.demo.snapshot()).toMatchObject({ state: 'allowed', outcome: 'allowed' });
    s.scheduler.advance(60_000);
    expect(s.demo.snapshot()).toMatchObject({ state: 'done', outcome: 'allowed' });
  });

  it('reject из awaiting — исход rejected, затем done с исходом', () => {
    const s = setup();
    toAwaiting(s);
    s.demo.reject();
    expect(s.demo.snapshot()).toMatchObject({ state: 'rejected', outcome: 'rejected' });
    s.scheduler.advance(60_000);
    expect(s.demo.snapshot()).toMatchObject({ state: 'done', outcome: 'rejected' });
  });

  it('повторный ответ после исхода состояние не меняет', () => {
    const s = setup();
    toAwaiting(s);
    s.demo.allow();
    s.demo.reject();
    expect(s.demo.snapshot()).toMatchObject({ state: 'allowed', outcome: 'allowed' });
    s.scheduler.advance(60_000);
    s.demo.reject();
    s.demo.allow();
    expect(s.demo.snapshot()).toMatchObject({ state: 'done', outcome: 'allowed' });
  });

  it('ответ до карточки запроса игнорируется', () => {
    const s = setup();
    s.demo.start();
    s.scheduler.advance(1_000);
    const before = s.demo.snapshot();
    s.demo.allow();
    s.demo.reject();
    expect(s.demo.snapshot()).toEqual(before);
  });
});

describe('уменьшение движения', () => {
  it('start сразу показывает карточку запроса: без промежуточных состояний и таймеров', () => {
    const s = setup({ reduce: true });
    s.demo.start();
    expect(s.demo.snapshot().state).toBe('awaiting');
    expect(s.visited).toEqual(['idle', 'awaiting']);
    expect(s.scheduler.pending).toBe(0);
  });

  it('ответ сразу ведёт в done с исходом, без таймеров и состояния allowed', () => {
    const s = setup({ reduce: true });
    s.demo.start();
    s.demo.allow();
    expect(s.demo.snapshot()).toMatchObject({ state: 'done', outcome: 'allowed' });
    expect(s.visited).toEqual(['idle', 'awaiting', 'done']);
    expect(s.scheduler.pending).toBe(0);
  });
});

describe('показ последствий ответа посетителя', () => {
  it('наведение и фокус не задерживают переход allowed → done: курсор остаётся над кнопкой', () => {
    for (const answer of ['allow', 'reject'] as const) {
      const s = setup();
      toAwaiting(s);
      s.demo.setEngaged(true);
      s.demo[answer]();
      s.scheduler.advance(60_000);
      expect(s.demo.snapshot().state, answer).toBe('done');
    }
  });

  it('пауза по любой причине после ответа не оставляет исход навсегда без «Ещё раз»', () => {
    const s = setup();
    toAwaiting(s);
    s.demo.allow();
    s.demo.pause();
    s.demo.setVisible(false);
    s.scheduler.advance(60_000);
    expect(s.demo.snapshot().state).toBe('done');
  });

  it('до ответа наведение по-прежнему останавливает автопроигрывание', () => {
    const s = setup();
    s.demo.start();
    s.demo.setEngaged(true);
    s.scheduler.advance(60_000);
    expect(s.demo.snapshot().state).toBe('idle');
  });
});

describe('пауза', () => {
  it('отменяет запланированный таймер, продолжение не дублирует его', () => {
    const s = setup();
    s.demo.start();
    expect(s.scheduler.pending).toBe(1);
    s.demo.pause();
    expect(s.scheduler.pending).toBe(0);
    s.scheduler.advance(60_000);
    expect(s.demo.snapshot().state).toBe('idle');

    s.demo.resume();
    s.demo.resume();
    expect(s.scheduler.pending).toBe(1);
    s.scheduler.advance(60_000);
    expect(s.demo.snapshot().state).toBe('awaiting');
  });

  it('невидимость и наведение — отдельные причины паузы: проигрывание идёт, когда сняты все', () => {
    const s = setup();
    s.demo.start();
    s.demo.setVisible(false);
    s.demo.setEngaged(true);
    expect(s.scheduler.pending).toBe(0);
    s.demo.setVisible(true);
    expect(s.scheduler.pending).toBe(0);
    s.demo.setEngaged(false);
    expect(s.scheduler.pending).toBe(1);
  });

  it('пауза после выбора посетителя не мешает показать исход', () => {
    const s = setup();
    toAwaiting(s);
    s.demo.allow();
    s.demo.pause();
    expect(s.demo.snapshot().outcome).toBe('allowed');
    s.demo.resume();
    s.scheduler.advance(60_000);
    expect(s.demo.snapshot().state).toBe('done');
  });
});

describe('«Ещё раз»', () => {
  it('снимок показывает паузу посетителя отдельно от прочих причин', () => {
    const s = setup();
    s.demo.start();
    s.demo.setVisible(false);
    expect(s.demo.snapshot()).toMatchObject({ paused: true, userPaused: false });
    s.demo.pause();
    expect(s.demo.snapshot().userPaused).toBe(true);
  });

  it('restart снимает паузу посетителя: следующий start проигрывает', () => {
    const s = setup();
    s.demo.start();
    s.demo.pause();
    s.demo.restart();
    expect(s.demo.snapshot().userPaused).toBe(false);
    s.demo.start();
    s.scheduler.advance(60_000);
    expect(s.demo.snapshot().state).toBe('awaiting');
  });

  it('из done → idle, исход сброшен', () => {
    const s = setup();
    toAwaiting(s);
    s.demo.reject();
    s.scheduler.advance(60_000);
    s.demo.restart();
    expect(s.demo.snapshot()).toMatchObject({ state: 'idle', outcome: undefined, streamed: 0 });
  });

  it('старые таймеры не срабатывают после перезапуска', () => {
    const s = setup();
    s.demo.start();
    s.scheduler.advance(1_500);
    s.demo.restart();
    expect(s.scheduler.pending).toBe(0);
    s.scheduler.advance(60_000);
    expect(s.demo.snapshot().state).toBe('idle');
  });

  it('после restart start проигрывает сценарий заново', () => {
    const s = setup();
    toAwaiting(s);
    s.demo.allow();
    s.scheduler.advance(60_000);
    s.demo.restart();
    s.demo.start();
    s.scheduler.advance(60_000);
    expect(s.demo.snapshot()).toMatchObject({ state: 'awaiting', outcome: undefined });
  });
});
