// Конфигурация сборки сайта CodeLab.
//
// Почему: хостинг ещё не выбран (design.md add-astro-site, H1), поэтому адрес
// сайта и подкаталог приходят из окружения, а не прописаны здесь (D12).
// Сборка должна одинаково работать в корне домена (`SITE_BASE=/`) и в
// подкаталоге GitHub Pages (`SITE_BASE=/codelab-app/`).
//
// Для чего: единая точка настроек Astro — адреса со слэшем на конце и каталожный
// формат страниц (D4), доступ Vite к документам вне `site/` (D3), конвейер
// Markdown с плагинами D5, D7, D11, подсветка кода темами из токенов (D8) и
// подмена `elkjs` (D2, D7).
//
// Как использовать: `SITE_BASE=/codelab-app/ npm run build`; без переменных —
// сборка в корень без `site` (без canonical и карты сайта, D12).
import { readFileSync } from 'node:fs';
import { fileURLToPath } from 'node:url';

import { unified } from '@astrojs/markdown-remark';
import { defineConfig } from 'astro/config';

import { remarkHomePaths } from './src/plugins/home-paths.ts';
import { remarkMermaidBlocks } from './src/plugins/mermaid-blocks.ts';
import { onlyPublished } from './src/plugins/only-published.ts';
import { rehypeRawHtmlGuard } from './src/plugins/raw-html-guard.ts';
import { remarkRepoLinks } from './src/plugins/repo-links.ts';
import { repoUrl, resolveRepoRef } from './src/site.config.ts';

/**
 * Приводит `SITE_BASE` к виду `/…/`.
 *
 * Почему: `withBase()` (D12) склеивает адреса без проверок, поэтому база
 * всегда начинается и заканчивается слэшем; пустое значение — корень.
 */
function normalizeBase(raw) {
  const trimmed = (raw ?? '').trim().replace(/^\/+|\/+$/g, '');
  return trimmed === '' ? '/' : `/${trimmed}/`;
}

/** Тема Shiki из JSON в `src/styles/` (D8). */
function shikiTheme(name) {
  return JSON.parse(readFileSync(new URL(`./src/styles/${name}.json`, import.meta.url), 'utf8'));
}

// Корень репозитория: документы читаются на месте, без копий (D3).
const repoRoot = fileURLToPath(new URL('..', import.meta.url));

const siteUrl = process.env.SITE_URL?.trim() || undefined;
const base = normalizeBase(process.env.SITE_BASE);

export default defineConfig({
  site: siteUrl,
  base,
  trailingSlash: 'always',
  build: {
    format: 'directory',
  },
  markdown: {
    // Конвейер unified задан явно: процессор Astro 7 по умолчанию (Sätteri)
    // не запускает remark- и rehype-плагины, а `markdown.remarkPlugins` объявлены
    // устаревшими (D2). Порядок встроенных шагов `@astrojs/markdown-remark`:
    // gfm → smartypants → наши remark-плагины → remark-rehype → Shiki → наши
    // rehype-плагины → id заголовков → rehype-raw. Защита сырого HTML поэтому
    // видит узлы `raw` до их разбора (D11), а блоки mermaid уже заменены и
    // Shiki их не подсвечивает (D7).
    processor: unified({
      gfm: true,
      // SmartyPants выключен. Он меняет текст до id заголовков: `--` в заголовке
      // стал бы `–`, и якорь на сайте разошёлся бы с якорем GitHub, на который
      // ссылаются документы (D5, D6, R6). Ещё он ставит английские кавычки “…”
      // в русский текст, где авторы пишут «…», — документ на сайте выглядел бы
      // иначе, чем на GitHub (D3).
      smartypants: false,
      remarkPlugins: [
        remarkMermaidBlocks,
        remarkHomePaths,
        // Только документы репозитория: ссылки новостей — адреса сайта, их
        // проверяет `check-links` (D5, D10).
        [
          onlyPublished(remarkRepoLinks, repoRoot),
          { repoRoot, repoUrl, repoRef: resolveRepoRef(), base },
        ],
      ],
      rehypePlugins: [rehypeRawHtmlGuard],
    }),
    shikiConfig: {
      // Две свои темы из токенов `--syn-*` и `--code-*`; без цвета по
      // умолчанию Shiki пишет `--shiki-light` и `--shiki-dark`, а выбор между
      // ними делает CSS по классу темы (`src/styles/base.css`, D8).
      themes: { light: shikiTheme('shiki-light'), dark: shikiTheme('shiki-dark') },
      defaultColor: false,
    },
  },
  vite: {
    resolve: {
      // `mermaid` подгружает `elkjs` для раскладки ELK; его лицензия не проходит
      // D2, поэтому модуль подменяется заглушкой (D7).
      alias: [
        {
          find: /^elkjs(\/.*)?$/,
          replacement: fileURLToPath(new URL('./src/stubs/elkjs.ts', import.meta.url)),
        },
      ],
    },
    server: {
      fs: {
        // Разрешён корень целиком: публикацию ограничивает allowlist
        // загрузчика (`src/lib/publish.ts`), а не файловый доступ Vite (D3).
        allow: [repoRoot],
      },
    },
  },
});
