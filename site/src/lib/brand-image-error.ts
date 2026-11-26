/**
 * Ошибка сборки картинок бренда (`og.png`, `apple-touch-icon.png`).
 *
 * Почему: общий `Error` не отличить от сбоя Astro; узкий класс называет причину
 * (design.md redesign-site-showcase, D10; `AGENTS.md` §15 — типизированные ошибки).
 *
 * Для чего: бросается, когда исходный SVG бренда непригоден или сервис
 * изображений не умеет преобразовывать.
 *
 * Как использовать: `throw new BrandImageError('…')`; ловить не нужно — сборка
 * должна упасть с понятным сообщением.
 */
export class BrandImageError extends Error {
  constructor(message: string) {
    super(message);
    this.name = 'BrandImageError';
  }
}
