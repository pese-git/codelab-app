/**
 * Подсветка текущего раздела в оглавлении «На этой странице».
 *
 * Почему: на длинных главах читатель теряет место; `aria-current="location"`
 * отмечает ровно одну ссылку `nav.doc-toc` (design.md improve-docs-navigation,
 * D7). Выбор делает чистая `activeHeading`.
 *
 * Для чего: пересчёт по `scroll` не чаще раза за кадр
 * (`requestAnimationFrame`) и по `hashchange`; работает, только пока
 * оглавление видно (`min-width: 1200px`, иначе колонка скрыта). Фокус не
 * переносится, прокрутки и анимаций нет.
 *
 * Как использовать: подключается компонентом `TocSpy.astro`; без `nav.doc-toc`
 * ничего не делает.
 */
import { activeHeading } from '../../lib/doc-page/toc-spy';

/** Линия чтения: ниже шапки сайта (px от верха окна). */
const readingLine = 96;

const toc = document.querySelector<HTMLElement>('nav.doc-toc');
if (toc) {
  const links = [...toc.querySelectorAll<HTMLAnchorElement>('a[href^="#"]')];
  const headings = links.map((link) => document.getElementById(decodeURIComponent(link.hash.slice(1))));
  const media = window.matchMedia('(min-width: 1200px)');
  let queued = false;

  const update = (): void => {
    queued = false;
    if (!media.matches) {
      // Узкий экран: оглавление свёрнуто, отметка «текущий» не нужна.
      links.forEach((link) => link.removeAttribute('aria-current'));
      return;
    }
    const tops = headings.map((heading) => heading?.getBoundingClientRect().top ?? Number.POSITIVE_INFINITY);
    const atBottom = window.innerHeight + window.scrollY >= document.documentElement.scrollHeight - 2;
    const index = activeHeading(tops, readingLine, atBottom);
    links.forEach((link, i) => {
      if (i === index) link.setAttribute('aria-current', 'location');
      else link.removeAttribute('aria-current');
    });
  };

  const schedule = (): void => {
    if (queued) return;
    queued = true;
    requestAnimationFrame(update);
  };

  window.addEventListener('scroll', schedule, { passive: true });
  window.addEventListener('hashchange', schedule);
  media.addEventListener('change', schedule);
  schedule();
}
