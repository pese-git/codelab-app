/**
 * Связь автомата макета рабочего места с разметкой `Workbench.astro`.
 *
 * Почему: логика сценария — в `lib/showcase/workbench-demo.ts` и
 * `workbench-view.ts` (design.md redesign-site-showcase, D2 п. 4, D3); здесь
 * только узлы: что показать, на что нажали. Строки сценария лежат в
 * разметке, скрипт читает их `textContent` и ничего не собирает через
 * `innerHTML` (D2 п. 3).
 *
 * Для чего: на корне `[data-demo="workbench"]` скрипт показывает части ответа
 * (`[data-part]`), промпт, карточку запроса, исход и кнопки «Пауза» и «Ещё
 * раз»; исход объявляется в `[data-announce]` (`aria-live="polite"`).
 *
 * Как использовать: подключается компонентом `Workbench.astro`; корней может не
 * быть. Автопроигрывание не отвечает за посетителя: на `awaiting` оно стоит,
 * пока он не нажмёт «Разрешить» или «Отклонить» (D3, R4). Фокус переносится
 * только после ответа посетителя: на карточку (кнопки скрываются), затем на
 * «Ещё раз», когда она появилась.
 */
import { browserScheduler } from '../../lib/showcase/scheduler';
import { createWorkbench, type WorkbenchOutcome } from '../../lib/showcase/workbench-demo';
import { workbenchView } from '../../lib/showcase/workbench-view';
import { watchAutoplay } from './autoplay';
import { goLive, prefersReducedMotion } from './live';

/** Разметка `Workbench.astro` и скрипт разошлись: узел не найден (D2 п. 4). */
class WorkbenchMarkupError extends Error {
  constructor(message: string) {
    super(message);
    this.name = 'WorkbenchMarkupError';
  }
}

function required<T extends Element>(root: ParentNode, selector: string): T {
  const element = root.querySelector<T>(selector);
  if (!element) throw new WorkbenchMarkupError(`workbench: ${selector} is missing in the markup`);
  return element;
}

function init(root: HTMLElement): void {
  goLive(root);
  const reduce = prefersReducedMotion();

  const prompt = required<HTMLElement>(root, '[data-prompt]');
  const parts = [...root.querySelectorAll<HTMLElement>('[data-part]')];
  const card = required<HTMLElement>(root, '[data-card]');
  const windowBox = required<HTMLElement>(root, '.wb-window');
  const cardTitle = required<HTMLElement>(root, '[data-card-title]');
  const scopeGroup = required<HTMLElement>(root, '[data-scope]');
  const actions = required<HTMLElement>(root, '[data-actions]');
  // Заголовки карточки: до ответа — «Ждёт одобрения», после — «Решено» (строка
  // каталога app); оба текста лежат в разметке, скрипт ничего не собирает.
  const awaitingTitle = cardTitle.textContent ?? '';
  const resolvedTitle = required<HTMLElement>(root, '[data-card-resolved]').textContent ?? '';
  const allow = required<HTMLButtonElement>(root, '[data-allow]');
  const reject = required<HTMLButtonElement>(root, '[data-reject]');
  const outcomeTag = required<HTMLElement>(root, '[data-outcome-tag]');
  const reset = required<HTMLButtonElement>(root, '[data-reset]');
  const pause = required<HTMLButtonElement>(root, '[data-pause]');
  const announce = required<HTMLElement>(root, '[data-announce]');
  const scopes = [...root.querySelectorAll<HTMLInputElement>('input[name="wb-scope"]')];

  const tagText: Record<WorkbenchOutcome, string> = {
    allowed: required<HTMLElement>(root, '[data-tag-text="allowed"]').textContent ?? '',
    rejected: required<HTMLElement>(root, '[data-tag-text="rejected"]').textContent ?? '',
  };
  const summaries: Record<WorkbenchOutcome, HTMLElement> = {
    allowed: required<HTMLElement>(root, '[data-summary="allowed"]'),
    rejected: required<HTMLElement>(root, '[data-summary="rejected"]'),
  };

  const workbench = createWorkbench({ scheduler: browserScheduler, reduce, parts: parts.length });
  let announced = '';
  let answeredByVisitor = false;

  const scopeLabel = (): string => scopes.find((input) => input.checked)?.labels?.[0]?.textContent?.trim() ?? '';

  const render = (): void => {
    const snapshot = workbench.snapshot();
    const view = workbenchView(snapshot);
    const outcome = view.outcome;

    prompt.hidden = !view.promptShown;
    parts.forEach((part, i) => {
      part.hidden = i >= view.partsShown;
    });
    card.hidden = !view.cardShown;
    cardTitle.textContent = view.cardResolved ? resolvedTitle : awaitingTitle;
    // После ответа выбор и кнопки не нужны: карточка отражает исход, а не
    // выглядит неотвеченной с серыми кнопками.
    scopeGroup.hidden = view.cardResolved;
    actions.hidden = view.cardResolved;
    allow.disabled = !view.cardActive;
    reject.disabled = !view.cardActive;
    for (const input of scopes) input.disabled = !view.cardActive;

    root.dataset.state = snapshot.state;
    outcomeTag.hidden = outcome === undefined;
    if (outcome) {
      outcomeTag.textContent = `${tagText[outcome]} · ${scopeLabel()}`;
      outcomeTag.dataset.kind = outcome === 'allowed' ? 'ok' : 'bad';
    }
    for (const key of ['allowed', 'rejected'] as const) summaries[key].hidden = key !== outcome;

    reset.hidden = !view.resetShown;
    // Кнопка «Пауза», пока на ней фокус, не скрывается и не получает
    // `disabled` (disabled-элемент теряет фокус, в Safari он уходит на `body`),
    // а помечается `aria-disabled`, и клик игнорируется (D2 п. 7).
    pause.hidden = reduce || (!view.canPause && document.activeElement !== pause);
    pause.setAttribute('aria-disabled', String(!view.canPause));
    pause.textContent = snapshot.userPaused ? 'Продолжить' : 'Пауза';

    // Итог объявляется один раз готовой фразой, а не потоком символов (D2 п. 7).
    const text = outcome ? `${tagText[outcome]}. ${summaries[outcome].textContent ?? ''}` : '';
    if (text !== announced) {
      announced = text;
      announce.textContent = text;
    }

    // Фокус переносится только после ответа посетителя: сначала на карточку
    // (см. `answer`), затем на «Ещё раз», когда она появилась, — если фокус
    // с карточки никто не убрал (D2 п. 7).
    // `body` учитывается намеренно: после скрытия кнопок карточки focus fixup
    // браузера уводит фокус на `body`, и отличить это от клика посетителя по
    // пустому месту нельзя; перенос остаётся следствием его ответа (D2 п. 7).
    if (answeredByVisitor && view.resetShown) {
      answeredByVisitor = false;
      if (document.activeElement === card || document.activeElement === document.body) reset.focus();
    }
  };

  workbench.subscribe(render);

  const engagement = watchAutoplay(root, {
    setVisible(visible) {
      workbench.setVisible(visible);
      if (visible) workbench.start();
    },
    setEngaged: (engaged) => workbench.setEngaged(engaged),
  });

  /**
   * Ответ посетителя: фокус сначала уходит на карточку, потому что кнопки после
   * ответа скрываются и фокус пропал бы на `body`. Перенос вызван действием
   * посетителя, а не скриптом сам по себе (D2 п. 7).
   */
  const answer = (decide: () => void): void => {
    answeredByVisitor = true;
    card.focus();
    decide();
  };
  allow.addEventListener('click', () => answer(() => workbench.allow()));
  reject.addEventListener('click', () => answer(() => workbench.reject()));
  reset.addEventListener('click', () => {
    // «Ещё раз» — явная просьба повторить: курсор над кнопкой не должен
    // остановить повтор (`engagement.ts`).
    engagement.suppress();
    answeredByVisitor = false;
    // Кнопка «Ещё раз» скроется, поэтому фокус уходит на окно макета, а не на
    // `body`: перенос — следствие нажатия посетителя (D2 п. 7).
    windowBox.focus();
    workbench.restart();
    workbench.start();
  });
  pause.addEventListener('click', () => {
    if (pause.getAttribute('aria-disabled') === 'true') return;
    if (workbench.snapshot().userPaused) workbench.resume();
    else workbench.pause();
  });

  // Уменьшенное движение: автопроигрывания нет, состояние сразу полное, а
  // видимость не нужна (D2 п. 6).
  if (reduce) workbench.start();
  render();
}

for (const root of document.querySelectorAll<HTMLElement>('[data-demo="workbench"]')) init(root);
