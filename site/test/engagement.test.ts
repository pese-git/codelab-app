// Тесты признака «посетитель взаимодействует с демо» (tasks.md
// redesign-site-showcase, 4.1, 4.3; D2 п. 6, R4): наведение и фокус
// останавливают автопроигрывание, «Ещё раз» — явная просьба повторить.
import { describe, expect, it } from 'vitest';

import { createEngagement } from '../src/lib/showcase/engagement';

function setup() {
  const changes: boolean[] = [];
  const engagement = createEngagement((engaged) => changes.push(engaged));
  return { engagement, changes };
}

describe('createEngagement', () => {
  it('наведение включает признак, уход курсора выключает', () => {
    const { engagement, changes } = setup();
    engagement.pointer(true);
    engagement.pointer(false);
    expect(changes).toEqual([true, false]);
  });

  it('фокус внутри включает признак, пока курсор тоже внутри — признак держится', () => {
    const { engagement, changes } = setup();
    engagement.pointer(true);
    engagement.focus(true);
    engagement.pointer(false);
    expect(changes).toEqual([true]);
    engagement.focus(false);
    expect(changes).toEqual([true, false]);
  });

  it('повторное событие без изменения итога не вызывает слушателя', () => {
    const { engagement, changes } = setup();
    engagement.pointer(true);
    engagement.pointer(true);
    expect(changes).toEqual([true]);
  });

  it('suppress снимает признак, хотя курсор остаётся внутри', () => {
    const { engagement, changes } = setup();
    engagement.pointer(true);
    engagement.suppress();
    expect(changes).toEqual([true, false]);
    expect(engagement.engaged).toBe(false);
  });

  it('после suppress уход курсора снимает подавление: следующее наведение снова останавливает', () => {
    const { engagement, changes } = setup();
    engagement.pointer(true);
    engagement.suppress();
    engagement.pointer(false);
    engagement.pointer(true);
    expect(changes).toEqual([true, false, true]);
  });

  it('после suppress новый фокус клавиатурой снова останавливает', () => {
    const { engagement, changes } = setup();
    engagement.pointer(true);
    engagement.suppress();
    engagement.focus(true);
    expect(changes).toEqual([true, false, true]);
  });

  it('suppress без взаимодействия ничего не меняет', () => {
    const { engagement, changes } = setup();
    engagement.suppress();
    expect(changes).toEqual([]);
  });
});
