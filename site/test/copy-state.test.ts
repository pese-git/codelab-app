// Автомат копирования кода (design.md improve-docs-navigation, D7, R7):
// время двигает FakeScheduler, буфер обмена не нужен.
import { describe, expect, it } from 'vitest';

import { createCopyState } from '../src/lib/doc-page/copy-state';
import { FakeScheduler } from './support/fake-scheduler';

function setup() {
  const scheduler = new FakeScheduler();
  const state = createCopyState({ scheduler });
  return { scheduler, state };
}

describe('createCopyState (D7)', () => {
  it('начинает в idle без объявления', () => {
    const { state } = setup();
    expect(state.snapshot()).toEqual({ status: 'idle', announcement: '' });
  });

  it('успех: copied с фразой, через 2 с снова idle', () => {
    const { state, scheduler } = setup();
    state.settle(state.press(), true);
    expect(state.snapshot()).toEqual({ status: 'copied', announcement: 'Код скопирован' });
    scheduler.advance(1999);
    expect(state.snapshot().status).toBe('copied');
    scheduler.advance(1);
    expect(state.snapshot().status).toBe('idle');
  });

  it('отказ: failed с фразой, через 2 с снова idle', () => {
    const { state, scheduler } = setup();
    state.settle(state.press(), false);
    expect(state.snapshot()).toEqual({ status: 'failed', announcement: 'Не удалось скопировать' });
    scheduler.advance(2000);
    expect(state.snapshot().status).toBe('idle');
  });

  it('повторное нажатие начинает отсчёт заново', () => {
    const { state, scheduler } = setup();
    state.settle(state.press(), true);
    scheduler.advance(1500);
    state.settle(state.press(), true);
    scheduler.advance(1500);
    expect(state.snapshot().status).toBe('copied');
    scheduler.advance(500);
    expect(state.snapshot().status).toBe('idle');
  });

  it('таймер старого нажатия не сбрасывает новое', () => {
    const { state, scheduler } = setup();
    const first = state.press();
    state.settle(first, true);
    scheduler.advance(1900);
    const second = state.press();
    state.settle(second, false);
    scheduler.advance(200); // здесь сработал бы таймер первого
    expect(state.snapshot().status).toBe('failed');
  });

  it('поздний ответ старого нажатия игнорируется', () => {
    const { state } = setup();
    const first = state.press();
    const second = state.press();
    state.settle(second, true);
    state.settle(first, false);
    expect(state.snapshot().status).toBe('copied');
  });

  it('подписчик получает каждое изменение; отписка работает', () => {
    const { state, scheduler } = setup();
    const seen: string[] = [];
    const off = state.subscribe((s) => seen.push(s.status));
    state.settle(state.press(), true);
    scheduler.advance(2000);
    off();
    state.settle(state.press(), false);
    expect(seen).toEqual(['copied', 'idle']);
  });
});
