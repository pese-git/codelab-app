// Тесты схемы новости (tasks.md add-astro-site, 4.1, 4.7; D10; project-site
// «Новости выпусков», сценарии «Новость выпуска», «Неполная новость»).
// Пример новости живёт только здесь, в фикстуре, а не в `src/content/news/`.
import { readFileSync } from 'node:fs';

import { parseFrontmatter } from '@astrojs/markdown-remark';
import { describe, expect, it } from 'vitest';

import { newsSchema } from '../src/lib/news-schema';

const fixture = readFileSync(new URL('./fixtures/news/0.1.0.md', import.meta.url), 'utf8');
const valid = parseFrontmatter(fixture).frontmatter as Record<string, unknown>;

describe('newsSchema', () => {
  it('пример новости из фикстуры проходит', () => {
    expect(newsSchema.parse(valid)).toEqual({
      title: valid.title,
      date: '2026-12-01',
      version: '0.1.0',
      summary: valid.summary,
    });
  });

  it('дата из YAML без кавычек приводится к YYYY-MM-DD', () => {
    expect(newsSchema.parse({ ...valid, date: new Date('2026-12-01') }).date).toBe('2026-12-01');
  });

  for (const field of ['title', 'date', 'version', 'summary']) {
    it(`без поля ${field} — ошибка с именем поля`, () => {
      const { [field]: _, ...rest } = valid;
      const result = newsSchema.safeParse(rest);
      expect(result.success).toBe(false);
      expect(result.error?.issues.map((i) => i.path.join('.'))).toContain(field);
    });
  }

  it.each(['2026-1-01', '01.12.2026', '2026-13-01', '2026-02-30'])('неверная дата %s', (date) => {
    expect(newsSchema.safeParse({ ...valid, date }).success).toBe(false);
  });

  it.each(['1.0', 'v1.0.0', '1.0.0.0', '01.0.0', 'latest'])('неверная версия %s', (version) => {
    expect(newsSchema.safeParse({ ...valid, version }).success).toBe(false);
  });

  it.each(['1.0.0', '1.0.0-rc.1', '0.10.2-beta'])('верная версия %s', (version) => {
    expect(newsSchema.safeParse({ ...valid, version }).success).toBe(true);
  });

  it('summary длиннее 200 символов — ошибка', () => {
    expect(newsSchema.safeParse({ ...valid, summary: 'я'.repeat(201) }).success).toBe(false);
    expect(newsSchema.safeParse({ ...valid, summary: 'я'.repeat(200) }).success).toBe(true);
  });
});
