/**
 * Коллекции сайта: документы репозитория (`docs`) и новости выпусков (`news`).
 *
 * Почему: документация читается на месте, без копий в `site/`, и публикуется
 * только по allowlist (design.md add-astro-site, D3); новости — файлы сайта
 * со строгой схемой (D10).
 *
 * Для чего: `docs` — загрузчик `glob` с базой в корне репозитория и шаблонами
 * из `src/lib/publish.ts` (одна константа для загрузчика, плагина ссылок и
 * `check-links`); `id` записи — путь файла от корня репозитория, из него
 * выводятся адрес (D4) и группа навигации (D9). Заголовок и описание
 * считает `docMeta` (`src/lib/doc-meta.ts`) при построении страниц: frontmatter
 * у документов нет. `news` — `src/content/news/*.md` со схемой `newsSchema`.
 *
 * Как использовать: `getCollection('docs')` и `getCollection('news')` в
 * страницах; новый документ из allowlist появляется без правки этого файла.
 */
import { defineCollection } from 'astro:content';
import { glob } from 'astro/loaders';

import { newsSchema } from './lib/news-schema';
import { publishPatterns } from './lib/publish';

const docs = defineCollection({
  loader: glob({
    pattern: [...publishPatterns],
    base: '..',
    // Путь от корня репозитория вместо слага по умолчанию: слаг меняет регистр
    // и подчёркивания, а адрес обязан повторять путь файла (D4).
    generateId: ({ entry }) => entry,
  }),
});

const news = defineCollection({
  loader: glob({
    pattern: '*.md',
    base: './src/content/news',
    // Путь файла вместо слага: слаг `0.1.0.md` — `010`, и ошибка схемы
    // называла бы запись, а не файл (project-site, сценарий «Неполная новость»).
    generateId: ({ entry }) => `src/content/news/${entry}`,
  }),
  schema: newsSchema,
});

export const collections = { docs, news };
