/**
 * Схема frontmatter новости выпуска.
 *
 * Почему: новость пишет `docs-writer` в `release/<version>`, и неполная или
 * искажённая запись должна ломать сборку, а не публиковаться (design.md
 * add-astro-site, D10; project-site «Новости выпусков», сценарий «Неполная
 * новость»).
 *
 * Для чего: схема коллекции `news` в `src/content.config.ts`; вынесена сюда,
 * чтобы её проверяли тесты без сборки. Повтор `version` схема не видит — его
 * ловит `orderNews` (`src/lib/news.ts`).
 *
 * Как использовать: `defineCollection({ loader, schema: newsSchema })`.
 * Ошибка Astro называет файл и поле.
 */
import { z } from 'astro/zod';

/** `MAJOR.MINOR.PATCH` без ведущих нулей и с необязательным пре-релизом (D10). */
const versionPattern = /^(0|[1-9]\d*)\.(0|[1-9]\d*)\.(0|[1-9]\d*)(-[0-9A-Za-z-]+(\.[0-9A-Za-z-]+)*)?$/;

/** Существует ли календарная дата `YYYY-MM-DD` (без `2026-02-30`). */
function isCalendarDate(value: string): boolean {
  if (!/^\d{4}-\d{2}-\d{2}$/.test(value)) return false;
  const date = new Date(`${value}T00:00:00Z`);
  return !Number.isNaN(date.getTime()) && date.toISOString().slice(0, 10) === value;
}

/**
 * Дата новости строкой `YYYY-MM-DD`.
 *
 * YAML читает `date: 2026-12-01` без кавычек как дату, а не строку; такая
 * запись приводится к той же строке, чтобы автору не приходилось помнить о
 * кавычках. Порядок новостей сравнивает даты как строки (`orderNews`).
 */
const dateField = z
  .union([z.string(), z.date()])
  .transform((value) => (value instanceof Date ? value.toISOString().slice(0, 10) : value))
  .refine(isCalendarDate, { message: 'date must be a calendar date YYYY-MM-DD' });

export const newsSchema = z.object({
  title: z.string().min(1),
  date: dateField,
  version: z.string().regex(versionPattern, 'version must be MAJOR.MINOR.PATCH[-pre]'),
  summary: z.string().min(1).max(200),
});

/** Данные новости после проверки схемы. */
export type NewsData = z.infer<typeof newsSchema>;
