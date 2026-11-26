// Тесты разбора обратных кавычек (tasks.md redesign-site-showcase, 4.2, 4.5):
// цитаты документов и факты содержат `код`, а страница показывает его <code>,
// без сырых обратных кавычек и без innerHTML (D2 п. 3).
import { describe, expect, it } from 'vitest';

import { splitTicks } from '../src/lib/showcase/ticks';

describe('splitTicks', () => {
  it('текст без кавычек — один обычный фрагмент', () => {
    expect(splitTicks('без вопроса')).toEqual([{ code: false, text: 'без вопроса' }]);
  });

  it('фрагмент в обратных кавычках становится кодом', () => {
    expect(splitTicks('режим `standard`; папка')).toEqual([
      { code: false, text: 'режим ' },
      { code: true, text: 'standard' },
      { code: false, text: '; папка' },
    ]);
  });

  it('код в начале и в конце строки', () => {
    expect(splitTicks('`a` и `b`')).toEqual([
      { code: true, text: 'a' },
      { code: false, text: ' и ' },
      { code: true, text: 'b' },
    ]);
  });

  it('непарная кавычка остаётся текстом', () => {
    expect(splitTicks('одна ` кавычка')).toEqual([{ code: false, text: 'одна ` кавычка' }]);
  });

  it('пустая строка — нет фрагментов', () => {
    expect(splitTicks('')).toEqual([]);
  });
});
