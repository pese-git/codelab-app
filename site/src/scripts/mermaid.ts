/**
 * Отрисовка схем mermaid в браузере.
 *
 * Почему: схемы документации рисуются в браузере, а не при сборке (решение
 * пользователя, ADR-0003); скрипт mermaid большой, поэтому грузится только на
 * страницах со схемами и только из сборки сайта, без CDN (design.md
 * add-astro-site, D7; project-site «Mermaid-схемы в браузере»).
 *
 * Для чего: находит `pre[data-mermaid]` (их создаёт `remarkMermaidBlocks`),
 * лениво импортирует `mermaid`, рисует каждую схему рядом с исходником и
 * перерисовывает все при `codelab-theme-change`. Ошибка синтаксиса не ломает
 * страницу: исходник остаётся видимым, под ним — сообщение. Раскладка ELK не
 * используется: раскладка задана dagre, `elkjs` в сборке подменён заглушкой (D2, D7).
 *
 * Как использовать: подключается из `MermaidScript.astro` только на страницах
 * документов со схемами; без `[data-mermaid]` ничего не загружает.
 */
import { effectiveTheme, themeChangeEvent } from './theme-state';

interface Diagram {
  readonly source: string;
  readonly pre: HTMLElement;
  readonly container: HTMLElement;
  error?: HTMLElement;
}

let counter = 0;

async function main(): Promise<void> {
  const blocks = [...document.querySelectorAll<HTMLElement>('pre[data-mermaid]')];
  if (blocks.length === 0) return;

  const { default: mermaid } = await import('mermaid');

  // Исходник сохраняется в памяти при первой отрисовке: `data-mermaid` —
  // только метка, а `pre` после отрисовки скрыт (D7, п. 4).
  const diagrams: Diagram[] = blocks.map((pre) => {
    const container = document.createElement('div');
    container.className = 'mermaid-diagram';
    container.hidden = true;
    pre.after(container);
    return { source: pre.textContent ?? '', pre, container };
  });

  async function renderAll(): Promise<void> {
    mermaid.initialize({
      startOnLoad: false,
      // `strict` кодирует HTML в подписях и запрещает обработчики кликов: схема
      // приходит из документа, а не от автора сайта (D7, D11).
      securityLevel: 'strict',
      theme: effectiveTheme() === 'dark' ? 'dark' : 'default',
      // В mermaid 12 раскладка по умолчанию — ELK: `layout: "elk"` в корне
      // конфигурации и у `state`, `class`. Код `elkjs` подменён заглушкой (D2,
      // D7), поэтому без явного dagre не рисовалась ни одна схема. Схема,
      // которая сама просит `layout: elk`, получит сообщение об ошибке.
      layout: 'dagre',
      state: { layout: 'dagre' },
      class: { layout: 'dagre' },
    });
    for (const diagram of diagrams) {
      try {
        const { svg } = await mermaid.render(`mermaid-${++counter}`, diagram.source);
        diagram.container.innerHTML = svg;
        diagram.container.hidden = false;
        diagram.pre.hidden = true;
        diagram.error?.remove();
        diagram.error = undefined;
      } catch (error) {
        diagram.container.hidden = true;
        diagram.pre.hidden = false;
        if (!diagram.error) {
          diagram.error = document.createElement('p');
          diagram.error.className = 'mermaid-error';
          diagram.error.setAttribute('role', 'note');
          diagram.error.textContent = 'Схему не удалось отрисовать: показан её исходный текст.';
          diagram.pre.after(diagram.error);
        }
        console.error('mermaid: failed to render diagram', error);
      }
    }
  }

  // Отрисовки идут по очереди: `mermaid.initialize` глобален, и смена темы
  // посреди отрисовки не должна смешать темы в одной странице.
  let queue = renderAll();
  await queue;
  document.addEventListener(themeChangeEvent, () => {
    queue = queue.then(renderAll);
  });
}

main().catch((error: unknown) => {
  // Не загрузился сам модуль: исходники схем остаются видимыми.
  console.error('mermaid: failed to load', error);
});
