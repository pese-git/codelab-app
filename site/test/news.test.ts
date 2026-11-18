// Тесты порядка и проверки новостей (tasks.md add-astro-site, 3.9; D10;
// project-site «Новости выпусков», сценарии «Повтор версии», «Новостей нет»).
import { describe, expect, it } from 'vitest';

import { DuplicateNewsVersionError, orderNews } from '../src/lib/news';

function news(file: string, date: string, version: string) {
  return { filePath: `src/content/news/${file}`, data: { date, version } };
}

describe('orderNews', () => {
  it('новостей нет — пустой список, а не ошибка', () => {
    expect(orderNews([])).toEqual([]);
  });

  it('от новой к старой по дате', () => {
    const ordered = orderNews([
      news('0.1.0.md', '2026-11-01', '0.1.0'),
      news('0.3.0.md', '2027-01-15', '0.3.0'),
      news('0.2.0.md', '2026-12-10', '0.2.0'),
    ]);
    expect(ordered.map((n) => n.data.version)).toEqual(['0.3.0', '0.2.0', '0.1.0']);
  });

  it('при равных датах — по версии, сравнение числовое и с пре-релизом', () => {
    const ordered = orderNews([
      news('1.9.0.md', '2027-02-01', '1.9.0'),
      news('1.10.0-rc.1.md', '2027-02-01', '1.10.0-rc.1'),
      news('1.10.0.md', '2027-02-01', '1.10.0'),
    ]);
    expect(ordered.map((n) => n.data.version)).toEqual(['1.10.0', '1.10.0-rc.1', '1.9.0']);
  });

  it('не меняет входной список', () => {
    const input = [news('a.md', '2026-11-01', '0.1.0'), news('b.md', '2026-12-01', '0.2.0')];
    orderNews(input);
    expect(input.map((n) => n.data.version)).toEqual(['0.1.0', '0.2.0']);
  });

  it('повтор версии — ошибка с путями обоих файлов', () => {
    const entries = [
      news('1.0.0.md', '2027-03-01', '1.0.0'),
      news('0.9.0.md', '2027-02-01', '0.9.0'),
      news('1.0.0-copy.md', '2027-03-02', '1.0.0'),
    ];
    expect(() => orderNews(entries)).toThrow(DuplicateNewsVersionError);
    expect(() => orderNews(entries)).toThrow(
      expect.objectContaining({
        message: expect.stringMatching(
          /src\/content\/news\/1\.0\.0\.md[\s\S]*src\/content\/news\/1\.0\.0-copy\.md/,
        ),
      }),
    );
  });
});
