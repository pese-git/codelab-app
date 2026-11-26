// Тесты отображения состояния макета (tasks.md redesign-site-showcase, 4.1;
// D3): какие части ленты видны в каждом состоянии автомата. Разметка только
// применяет этот результат.
import { describe, expect, it } from 'vitest';

import type { WorkbenchSnapshot } from '../src/lib/showcase/workbench-demo';
import { workbenchView } from '../src/lib/showcase/workbench-view';

const snap = (over: Partial<WorkbenchSnapshot>): WorkbenchSnapshot => ({
  state: 'idle',
  streamed: 0,
  parts: 4,
  outcome: undefined,
  paused: false,
  userPaused: false,
  ...over,
});

describe('workbenchView', () => {
  it('карточка называется «ждёт одобрения» только до ответа', () => {
    expect(workbenchView(snap({ state: 'awaiting', streamed: 4 })).cardResolved).toBe(false);
    for (const state of ['allowed', 'rejected', 'done'] as const) {
      const view = workbenchView(snap({ state, streamed: 4, outcome: state === 'rejected' ? 'rejected' : 'allowed' }));
      expect(view.cardResolved, state).toBe(true);
    }
  });

  it('idle: в ленте уже промпт посетителя, ответа ещё нет — первый экран не пуст', () => {
    expect(workbenchView(snap({}))).toMatchObject({
      promptShown: true,
      partsShown: 0,
      cardShown: false,
      outcome: undefined,
      resetShown: false,
    });
  });

  it('prompt: промпт в ленте, ответа ещё нет', () => {
    const view = workbenchView(snap({ state: 'prompt' }));
    expect(view.promptShown).toBe(true);
    expect(view.partsShown).toBe(0);
    expect(view.cardShown).toBe(false);
  });

  it('streaming: промпт ушёл в ленту, показано столько частей, сколько напечатано', () => {
    const streaming = workbenchView(snap({ state: 'streaming', streamed: 1 }));
    expect(streaming.promptShown).toBe(true);
    expect(workbenchView(snap({ state: 'streaming', streamed: 2 })).partsShown).toBe(2);
    expect(workbenchView(snap({ state: 'streaming', streamed: 4 })).cardShown).toBe(false);
  });

  it('awaiting: все части, карточка активна, исхода нет', () => {
    const view = workbenchView(snap({ state: 'awaiting', streamed: 4 }));
    expect(view.partsShown).toBe(4);
    expect(view.cardShown).toBe(true);
    expect(view.cardActive).toBe(true);
    expect(view.outcome).toBeUndefined();
    expect(view.resetShown).toBe(false);
  });

  it('allowed и rejected: карточка неактивна, исход показан, «Ещё раз» ещё нет', () => {
    for (const outcome of ['allowed', 'rejected'] as const) {
      const view = workbenchView(snap({ state: outcome, streamed: 4, outcome }));
      expect(view.cardShown).toBe(true);
      expect(view.cardActive).toBe(false);
      expect(view.outcome).toBe(outcome);
      expect(view.resetShown).toBe(false);
    }
  });

  it('done: исход и кнопка «Ещё раз»', () => {
    const view = workbenchView(snap({ state: 'done', streamed: 4, outcome: 'rejected' }));
    expect(view.outcome).toBe('rejected');
    expect(view.resetShown).toBe(true);
    expect(view.cardActive).toBe(false);
  });

  it('пауза автопроигрывания нужна, пока демо проигрывается само', () => {
    expect(workbenchView(snap({ state: 'prompt' })).canPause).toBe(true);
    expect(workbenchView(snap({ state: 'awaiting', streamed: 4 })).canPause).toBe(false);
    expect(workbenchView(snap({ state: 'done', streamed: 4, outcome: 'allowed' })).canPause).toBe(false);
  });
});
