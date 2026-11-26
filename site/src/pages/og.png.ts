/**
 * Картинка для ссылок: `/og.png`, PNG 1200×630.
 *
 * Почему: Open Graph и Twitter card показывают превью ссылки (design.md
 * redesign-site-showcase, D10); картинка — одна на сайт. Её собирает сборка из
 * SVG бренда, без копии в `site/` и без шрифтов (`lib/og-card.ts`).
 *
 * Для чего: `og:image` (при заданном `SITE_URL`) и проверка размера
 * `scripts/check-links.mjs` (D12 п. 4) ссылаются на этот файл.
 *
 * Как использовать: ничего — Astro собирает `dist/og.png` при `npm run build`.
 */
import type { APIRoute } from 'astro';

import logoSvg from '../../../docs/design/brand/codelab-logo.svg?raw';
import { composeOgCardSvg, ogCardSize } from '../lib/og-card';
import { rasterizeSvg } from '../lib/raster-svg';

export const GET: APIRoute = () => rasterizeSvg(composeOgCardSvg(logoSvg), ogCardSize);
