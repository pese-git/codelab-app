/**
 * Кнопки «Копировать» у блоков кода страницы документа.
 *
 * Почему: читатель копирует команды из документации; кнопка создаётся
 * скриптом, а не разметкой, чтобы без JavaScript не было «мёртвых» кнопок
 * (design.md improve-docs-navigation, D7; D2 п. 5 redesign-site-showcase).
 *
 * Для чего: находит `.prose pre.astro-code` (Shiki), кроме `pre[data-mermaid]`,
 * оборачивает блок и добавляет `button`. Итог нажатия объявляется в одной общей
 * области `aria-live="polite"` страницы; надпись «Скопировано» держится 2 с
 * (автомат `lib/doc-page/copy-state.ts`). Фокус остаётся на кнопке.
 *
 * Как использовать: подключается компонентом `CopyCode.astro`. Без `innerHTML`;
 * `document.execCommand('copy')` не используется — он меняет выделение и фокус.
 * Нет `navigator.clipboard` (небезопасный контекст) — «Не удалось скопировать».
 */
import { createCopyState } from '../../lib/doc-page/copy-state';
import { browserScheduler } from '../../lib/showcase/scheduler';

const labels = { idle: 'Копировать', copied: 'Скопировано', failed: 'Не удалось скопировать' } as const;

function createLiveRegion(): HTMLElement {
  const region = document.createElement('p');
  region.className = 'doc-live';
  region.setAttribute('aria-live', 'polite');
  region.setAttribute('role', 'status');
  document.body.append(region);
  return region;
}

function enhance(pre: HTMLElement, live: HTMLElement): void {
  const code = pre.querySelector('code') ?? pre;
  const wrapper = document.createElement('div');
  wrapper.className = 'code-block';
  pre.replaceWith(wrapper);

  const button = document.createElement('button');
  button.type = 'button';
  button.className = 'code-copy';
  button.setAttribute('aria-label', 'Копировать код');
  button.textContent = labels.idle;
  wrapper.append(pre, button);

  const state = createCopyState({ scheduler: browserScheduler });
  state.subscribe((snapshot) => {
    button.textContent = labels[snapshot.status];
    // Общая область одна на страницу: чужой автомат, вернувшийся в idle, не
    // должен стирать объявление. Повтор той же фразы без очистки не озвучат.
    if (snapshot.announcement === '') return;
    live.textContent = '';
    live.textContent = snapshot.announcement;
  });

  button.addEventListener('click', () => {
    const press = state.press();
    const text = code.textContent ?? '';
    const write = navigator.clipboard?.writeText(text);
    if (write === undefined) {
      state.settle(press, false);
      return;
    }
    write.then(
      () => state.settle(press, true),
      () => state.settle(press, false),
    );
  });
}

const blocks = [...document.querySelectorAll<HTMLElement>('.prose pre.astro-code')].filter(
  (pre) => !pre.hasAttribute('data-mermaid'),
);
if (blocks.length > 0) {
  const live = createLiveRegion();
  for (const pre of blocks) enhance(pre, live);
}
