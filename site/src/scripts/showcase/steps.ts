/**
 * Связь автомата шагов «Как это работает» с разметкой `HowItWorks.astro`.
 *
 * Почему: шаги автопроигрываются, но выбор посетителя главнее (design.md
 * redesign-site-showcase, D5, R4). Логика — `lib/showcase/steps.ts`; здесь
 * вкладки и кнопка «Пауза» / «Продолжить» (WCAG 2.2.2, D2 п. 6).
 *
 * Для чего: корень `[data-demo="steps"]`; вкладки и пауза показываются только
 * со скриптом. При `prefers-reduced-motion: reduce` автопроигрывания и кнопки
 * паузы нет — шаги меняет только посетитель.
 *
 * Как использовать: подключается компонентом `HowItWorks.astro`. Область
 * `aria-live` у шагов не нужна: смена идёт сама, и её объявление мешало бы.
 */
import { browserScheduler } from '../../lib/showcase/scheduler';
import { createSteps } from '../../lib/showcase/steps';
import { watchAutoplay } from './autoplay';
import { goLive, prefersReducedMotion } from './live';
import { initTabs } from './tabs';

function init(root: HTMLElement): void {
  goLive(root);
  const reduce = prefersReducedMotion();
  const pause = root.querySelector<HTMLButtonElement>('[data-pause]');

  let steps: ReturnType<typeof createSteps> | undefined;
  // Панели шагов — элементы списка: роль списка у `ol` мешала бы вкладкам.
  root.querySelector('ol')?.setAttribute('role', 'presentation');
  const tabs = initTabs(root, (index) => steps?.select(index));
  if (!tabs) return;
  steps = createSteps({ scheduler: browserScheduler, reduce });

  const renderPause = (): void => {
    if (!pause) return;
    pause.hidden = reduce;
    pause.textContent = steps?.snapshot().userPaused ? 'Продолжить' : 'Пауза';
  };

  steps.subscribe((snapshot) => {
    tabs.select(snapshot.index);
    renderPause();
  });

  pause?.addEventListener('click', () => {
    // Пауза живёт только в автомате: выбор вкладки тоже ставит её (D5).
    if (steps.snapshot().userPaused) steps.resume();
    else steps.pause();
  });

  watchAutoplay(root, { setVisible: steps.setVisible, setEngaged: steps.setEngaged });
  steps.start();
  renderPause();
}

for (const root of document.querySelectorAll<HTMLElement>('[data-demo="steps"]')) init(root);
