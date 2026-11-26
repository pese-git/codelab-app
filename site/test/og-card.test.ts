// Тесты сборки SVG-карточки для ссылок (tasks.md redesign-site-showcase, 5.1;
// D10; project-site «Мета-данные страниц и знак сайта»). Растеризует её сервис
// изображений Astro; здесь проверяется только состав SVG, без sharp.
import { describe, expect, it } from 'vitest';

import { readFileSync } from 'node:fs';

import { BrandImageError } from '../src/lib/brand-image-error';
import { composeOgCardSvg, ogAccentColor, ogCardSize, ogPlaqueColor } from '../src/lib/og-card';

const logo =
  '<svg xmlns="http://www.w3.org/2000/svg" viewBox="-24 -24 1728 368"><g id="mark"><rect width="10" height="10"/></g></svg>';

describe('composeOgCardSvg', () => {
  it('размер карточки — 1200×630, как требует D12', () => {
    expect(ogCardSize).toEqual({ width: 1200, height: 630 });
    const svg = composeOgCardSvg(logo);
    expect(svg).toMatch(/<svg[^>]*width="1200"[^>]*height="630"/);
    expect(svg).toContain('viewBox="0 0 1200 630"');
  });

  it('содержимое логотипа вложено с его собственным viewBox', () => {
    const svg = composeOgCardSvg(logo);
    expect(svg).toContain('<g id="mark">');
    expect(svg).toContain('viewBox="-24 -24 1728 368"');
  });

  it('без текста шрифтом и без внешних ссылок: результат не зависит от машины сборки', () => {
    const svg = composeOgCardSvg(logo);
    expect(svg).not.toMatch(/<text|<tspan|font-family/);
    expect(svg).not.toMatch(/https?:\/\/(?!www\.w3\.org)/);
    expect(svg).not.toMatch(/xlink:href|<image/);
  });

  it('файл без корня svg — ошибка, а не пустая картинка', () => {
    expect(() => composeOgCardSvg('<html></html>')).toThrow(/svg/);
    expect(() => composeOgCardSvg('<html></html>')).toThrow(BrandImageError);
  });

  it('svg без viewBox — узкая ошибка сборки', () => {
    expect(() => composeOgCardSvg('<svg xmlns="http://www.w3.org/2000/svg"></svg>')).toThrow(BrandImageError);
  });
});

describe('цвета плашки совпадают с токенами светлой темы', () => {
  const tokens = readFileSync(new URL('../src/styles/tokens.css', import.meta.url), 'utf8');
  const light = (name: string): string | undefined =>
    new RegExp(`--${name}:\\s*light-dark\\(\\s*(#[0-9A-Fa-f]{6})`).exec(tokens)?.[1];

  it('--mica', () => {
    expect(light('mica')?.toUpperCase()).toBe(ogPlaqueColor.toUpperCase());
  });

  it('--accent', () => {
    expect(light('accent')?.toUpperCase()).toBe(ogAccentColor.toUpperCase());
  });
});
