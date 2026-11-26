// Выбор текущего заголовка для оглавления (design.md improve-docs-navigation, D7).
import { describe, expect, it } from 'vitest';

import { activeHeading } from '../src/lib/doc-page/toc-spy';

describe('activeHeading (D7)', () => {
  it('пустой список — нет активного', () => {
    expect(activeHeading([], 100, false)).toBeNull();
    expect(activeHeading([], 100, true)).toBeNull();
  });

  it('до первого заголовка нет активного', () => {
    expect(activeHeading([300, 900], 100, false)).toBeNull();
  });

  it('активен последний заголовок выше линии чтения', () => {
    expect(activeHeading([-500, 40, 600], 100, false)).toBe(1);
    expect(activeHeading([-500, -40, -10], 100, false)).toBe(2);
  });

  it('заголовок ровно на линии чтения уже активен', () => {
    expect(activeHeading([100, 800], 100, false)).toBe(0);
  });

  it('конец страницы — последний заголовок, даже если он ниже линии', () => {
    expect(activeHeading([-500, 40, 600], 100, true)).toBe(2);
  });
});
