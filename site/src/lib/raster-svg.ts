/**
 * Растеризация SVG бренда в PNG сервисом изображений Astro.
 *
 * Почему: картинке для ссылок (1200×630) и `apple-touch-icon` (180×180) нужен
 * PNG, а исходники бренда — SVG в `docs/design/brand/`, копии в `site/` быть не
 * должно (design.md redesign-site-showcase, D10). `getImage` из `astro:assets`
 * кладёт результат в `_astro/` под хэшем, а адрес `og.png` и `apple-touch-icon.png`
 * должен быть стабильным, поэтому используется тот же сервис изображений
 * (`sharp` из зависимостей Astro, новой зависимости нет) напрямую из endpoint.
 * Астро по умолчанию не растеризует SVG (`dangerouslyProcessSVG`, защита от
 * чужих SVG); здесь входной SVG — файл самого репозитория, поэтому флаг
 * включён только для этих вызовов, а не для всего сайта.
 *
 * Для чего: `src/pages/og.png.ts` и `src/pages/apple-touch-icon.png.ts`.
 *
 * Как использовать: `await rasterizeSvg(svgText, { width, height })` → `Response` с
 * `image/png`. Модуль импортирует `astro:assets` и годится только для endpoint.
 */
import { getConfiguredImageService, imageConfig } from 'astro:assets';

import { BrandImageError } from './brand-image-error';

export async function rasterizeSvg(svg: string, size: { width: number; height: number }): Promise<Response> {
  const service = await getConfiguredImageService();
  if (!('transform' in service)) throw new BrandImageError('the configured image service cannot transform images');
  const { data } = await service.transform(
    new TextEncoder().encode(svg),
    { src: 'brand.svg', format: 'png', width: size.width, height: size.height },
    // Тип `imageConfig` описывает пользовательскую форму `service`, а сервис
    // ждёт уже выбранную (`build` для сборки): во время работы Astro отдаёт её.
    { ...imageConfig, dangerouslyProcessSVG: true } as unknown as Parameters<typeof service.transform>[2],
    // Логгер сервиса нужен только для предупреждений о несовпадении формата;
    // входной файл — SVG, поэтому предупреждать нечему, и вывод идёт в консоль.
    { info: (message) => console.info(message), warn: (message) => console.warn(message), error: (message) => console.error(message) },
  );
  return new Response(new Uint8Array(data), { headers: { 'Content-Type': 'image/png' } });
}
