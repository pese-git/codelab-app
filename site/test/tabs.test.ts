// Тесты клавиатурной логики вкладок (tasks.md redesign-site-showcase, 4.2–4.4;
// D2 п. 7; project-site «Интерактивные демо витрины»: «Клавиатура»).
import { describe, expect, it } from 'vitest';

import { nextTabIndex } from '../src/lib/showcase/tabs';

describe('nextTabIndex: шаблон вкладок WAI-ARIA', () => {
  it('стрелка вправо выбирает следующую вкладку', () => {
    expect(nextTabIndex('ArrowRight', 0, 3)).toBe(1);
  });

  it('стрелка вправо на последней вкладке возвращает к первой', () => {
    expect(nextTabIndex('ArrowRight', 2, 3)).toBe(0);
  });

  it('стрелка влево на первой вкладке переходит к последней', () => {
    expect(nextTabIndex('ArrowLeft', 0, 3)).toBe(2);
    expect(nextTabIndex('ArrowLeft', 2, 3)).toBe(1);
  });

  it('Home и End — первая и последняя вкладка', () => {
    expect(nextTabIndex('Home', 2, 5)).toBe(0);
    expect(nextTabIndex('End', 1, 5)).toBe(4);
  });

  it('прочие клавиши (Tab, Enter, вверх и вниз) вкладку не меняют', () => {
    for (const key of ['Tab', 'Enter', ' ', 'ArrowUp', 'ArrowDown', 'a']) {
      expect(nextTabIndex(key, 1, 3), key).toBeUndefined();
    }
  });

  it('без вкладок ответа нет', () => {
    expect(nextTabIndex('ArrowRight', 0, 0)).toBeUndefined();
  });
});
