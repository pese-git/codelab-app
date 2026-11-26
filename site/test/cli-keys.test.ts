// Тесты демо «Клавиши ответа codelab» (tasks.md redesign-site-showcase, 4.4;
// D5; project-site «Интерактивные демо витрины»: «Клавиатура»).
import { describe, expect, it } from 'vitest';

import { answerForKey } from '../src/lib/showcase/cli-keys';

const rows = [
  { key: 'y', answer: 'разрешить один раз' },
  { key: 'a', answer: 'разрешать всегда' },
  { key: 'n', answer: 'отклонить один раз' },
  { key: 'N', answer: 'отклонять всегда' },
  { key: '?', answer: 'показать запрос целиком и спросить снова' },
] as const;

describe('answerForKey', () => {
  it('возвращает строку таблицы по клавише', () => {
    expect(answerForKey(rows, 'y')).toBe(rows[0]);
    expect(answerForKey(rows, '?')).toBe(rows[4]);
  });

  it('различает регистр: n и N — разные ответы', () => {
    expect(answerForKey(rows, 'n')?.answer).toBe('отклонить один раз');
    expect(answerForKey(rows, 'N')?.answer).toBe('отклонять всегда');
  });

  it('неизвестная клавиша ответа не даёт', () => {
    expect(answerForKey(rows, 'Y')).toBeUndefined();
    expect(answerForKey(rows, 'Escape')).toBeUndefined();
    expect(answerForKey(rows, 'Enter')).toBeUndefined();
  });
});
