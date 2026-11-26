/**
 * Сборка SVG-карточки для ссылок: знак и надпись бренда на плашке сайта.
 *
 * Почему: картинка 1200×630 нужна `og:image`, а копии бренда в `site/` быть не
 * должно — исходник один, `docs/design/brand/codelab-logo.svg` (design.md
 * redesign-site-showcase, D10). Текст шрифтом в карточке не используется:
 * надпись бренда нарисована линиями, поэтому результат не зависит от шрифтов
 * машины сборки.
 *
 * Для чего: `src/pages/og.png.ts` отдаёт этот SVG сервису изображений Astro и
 * получает PNG.
 *
 * Как использовать: `composeOgCardSvg(текст codelab-logo.svg)` → строка SVG
 * 1200×630. Цвета плашки — значения токенов светлой темы `tokens.css`
 * (`--mica`, `--accent`): в CSS-переменных их не прочитать, поэтому они здесь с
 * именами токенов, а `og-card.test.ts` сверяет их с `tokens.css`.
 */

import { BrandImageError } from './brand-image-error';

/** Размер карточки: проверяет `scripts/check-links.mjs` (D12 п. 4). */
export const ogCardSize = { width: 1200, height: 630 } as const;

/** `--mica` светлой темы. */
export const ogPlaqueColor = '#F3F3F3';
/** `--accent` светлой темы. */
export const ogAccentColor = '#0060AA';

/** Поле вокруг логотипа и его ширина; высота — по пропорциям viewBox. */
const logoBox = { x: 90, y: 214, width: 1020, height: 217 } as const;

/** Содержимое корня `<svg>` и его viewBox; без корня — ошибка. */
function unwrap(logoSvg: string): { inner: string; viewBox: string } {
  const match = /<svg\b([^>]*)>([\s\S]*)<\/svg>\s*$/.exec(logoSvg);
  if (!match) throw new BrandImageError('brand logo is not an svg document');
  const viewBox = /viewBox="([^"]+)"/.exec(match[1] ?? '')?.[1];
  if (!viewBox) throw new BrandImageError('brand logo svg has no viewBox');
  return { inner: match[2] ?? '', viewBox };
}

export function composeOgCardSvg(logoSvg: string): string {
  const { inner, viewBox } = unwrap(logoSvg);
  const { width, height } = ogCardSize;
  return (
    `<svg xmlns="http://www.w3.org/2000/svg" width="${width}" height="${height}" viewBox="0 0 ${width} ${height}">` +
    `<rect width="${width}" height="${height}" fill="${ogPlaqueColor}"/>` +
    `<rect y="${height - 16}" width="${width}" height="16" fill="${ogAccentColor}"/>` +
    `<svg x="${logoBox.x}" y="${logoBox.y}" width="${logoBox.width}" height="${logoBox.height}" viewBox="${viewBox}">${inner}</svg>` +
    `</svg>`
  );
}
