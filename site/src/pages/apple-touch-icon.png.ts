/**
 * Значок для экрана «Домой» iOS: `/apple-touch-icon.png`, PNG 180×180.
 *
 * Почему: iOS не принимает SVG в `apple-touch-icon`; исходник — иконка
 * `docs/design/brand/launcher/web-icon.svg`, и копии в `site/` нет (design.md
 * redesign-site-showcase, D10).
 *
 * Для чего: `<link rel="apple-touch-icon">` в `BaseLayout.astro`.
 *
 * Как использовать: ничего — Astro собирает `dist/apple-touch-icon.png`.
 */
import type { APIRoute } from 'astro';

import iconSvg from '../../../docs/design/brand/launcher/web-icon.svg?raw';
import { rasterizeSvg } from '../lib/raster-svg';

export const GET: APIRoute = () => rasterizeSvg(iconSvg, { width: 180, height: 180 });
