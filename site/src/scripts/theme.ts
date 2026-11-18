/**
 * Переключатель темы в шапке.
 *
 * Почему: по умолчанию сайт следует системной теме, а читатель может выбрать
 * светлую или тёмную, и выбор сохраняется между страницами (design.md
 * add-astro-site, D8; project-site «Оформление и темы», сценарий «Выбор темы
 * сохраняется»).
 *
 * Для чего: кнопка `[data-theme-toggle]` перебирает «как в системе» →
 * «светлая» → «тёмная»; подпись и `aria-label` называют текущий выбор. Без
 * JavaScript кнопка скрыта (`hidden`): тема остаётся системной.
 *
 * Как использовать: подключается из `Header.astro`; Astro собирает модуль
 * в файл сборки, встроенным он не становится.
 */
import { applyChoice, readChoice, watchSystemTheme, type ThemeChoice } from './theme-state';

const order: readonly ThemeChoice[] = ['system', 'light', 'dark'];

const labels: Record<ThemeChoice, string> = {
  system: 'Тема: как в системе',
  light: 'Тема: светлая',
  dark: 'Тема: тёмная',
};

function render(button: HTMLButtonElement, choice: ThemeChoice): void {
  button.textContent = labels[choice];
  button.setAttribute('aria-label', `${labels[choice]}. Нажмите, чтобы сменить`);
}

for (const button of document.querySelectorAll<HTMLButtonElement>('[data-theme-toggle]')) {
  render(button, readChoice());
  button.hidden = false;
  button.addEventListener('click', () => {
    const next = order[(order.indexOf(readChoice()) + 1) % order.length]!;
    applyChoice(next);
    render(button, next);
  });
}

watchSystemTheme();
