/**
 * Связь DOM-событий демо с автоматом автопроигрывания.
 *
 * Почему: автопроигрывание идёт, только пока демо видно, и стоит при
 * наведении и фокусе внутри (design.md redesign-site-showcase, D2 п. 6,
 * WCAG 2.2.2). Сами правила — в автоматах и в `engagement.ts`; здесь только
 * подписки на события браузера.
 *
 * Для чего: общий код `workbench.ts` и `steps.ts`.
 *
 * Как использовать: `watchAutoplay(root, { setVisible, setEngaged })` после
 * создания автомата; возвращает `Engagement` — `suppress()` вызывает кнопка
 * «Ещё раз». Видимость сообщается сразу (`false`), затем по
 * `IntersectionObserver`; без него демо считается видимым. Касания не считаются
 * наведением: после тапа курсор «остаётся» над демо и остановил бы его навсегда.
 */
import { createEngagement, type Engagement } from '../../lib/showcase/engagement';

export interface AutoplayTarget {
  setVisible(visible: boolean): void;
  setEngaged(engaged: boolean): void;
}

export function watchAutoplay(root: HTMLElement, target: AutoplayTarget): Engagement {
  const engagement = createEngagement((engaged) => target.setEngaged(engaged));

  root.addEventListener('pointerenter', (event) => {
    if (event.pointerType !== 'touch') engagement.pointer(true);
  });
  root.addEventListener('pointerleave', () => engagement.pointer(false));
  root.addEventListener('focusin', () => engagement.focus(true));
  root.addEventListener('focusout', (event) => {
    // Фокус, перешедший на другой элемент внутри демо, остаётся «внутри».
    engagement.focus(event.relatedTarget instanceof Node && root.contains(event.relatedTarget));
  });

  if (typeof IntersectionObserver === 'undefined') {
    target.setVisible(true);
  } else {
    target.setVisible(false);
    new IntersectionObserver((entries) => {
      const last = entries[entries.length - 1];
      if (last) target.setVisible(last.isIntersecting);
    }).observe(root);
  }
  return engagement;
}
