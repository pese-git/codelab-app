// Конфигурация сборки сайта CodeLab.
//
// Почему: хостинг ещё не выбран (design.md add-astro-site, H1), поэтому адрес
// сайта и подкаталог приходят из окружения, а не прописаны здесь (D12).
// Сборка должна одинаково работать в корне домена (`SITE_BASE=/`) и в
// подкаталоге GitHub Pages (`SITE_BASE=/codelab-app/`).
//
// Для чего: единая точка настроек Astro — адреса со слэшем на конце и каталожный
// формат страниц (D4), доступ Vite к документам вне `site/` (D3).
//
// Как использовать: `SITE_BASE=/codelab-app/ npm run build`; без переменных —
// сборка в корень без `site` (без canonical и карты сайта, D12).
import { fileURLToPath } from 'node:url';
import { defineConfig } from 'astro/config';

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

// Корень репозитория: документы читаются на месте, без копий (D3).
const repoRoot = fileURLToPath(new URL('..', import.meta.url));

const siteUrl = process.env.SITE_URL?.trim() || undefined;

export default defineConfig({
  site: siteUrl,
  base: normalizeBase(process.env.SITE_BASE),
  trailingSlash: 'always',
  build: {
    format: 'directory',
  },
  vite: {
    server: {
      fs: {
        // Разрешён корень целиком: публикацию ограничивает allowlist
        // загрузчика (`src/lib/publish.ts`), а не файловый доступ Vite (D3).
        allow: [repoRoot],
      },
    },
  },
});
