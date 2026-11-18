/**
 * Состояние темы сайта в браузере: выбор читателя и действующая тема.
 *
 * Почему: тему читают два клиентских скрипта — переключатель (`theme.ts`) и
 * mermaid (`mermaid.ts`); ключ хранилища, классы и имя события должны быть
 * одними и теми же (design.md add-astro-site, D7, D8).
 *
 * Для чего: чтение и запись выбора в `localStorage['codelab-site-theme']`,
 * действующая тема с учётом системной, событие `codelab-theme-change`.
 *
 * Как использовать: `effectiveTheme()` — `light` или `dark` сейчас;
 * `document.addEventListener(themeChangeEvent, …)` — подписка на смену.
 * Встроенный скрипт `ThemeInit.astro` повторяет `readChoice` и классы: он
 * выполняется до загрузки модулей и импортировать этот файл не может.
 */

/** Ключ выбора в `localStorage`: `light`, `dark` или нет ключа — «как в системе». */
export const themeStorageKey = 'codelab-site-theme';

/** Событие на `document` после смены действующей темы (D8). */
export const themeChangeEvent = 'codelab-theme-change';

/** Выбор читателя. */
export type ThemeChoice = 'system' | 'light' | 'dark';

const systemDark = (): MediaQueryList => window.matchMedia('(prefers-color-scheme: dark)');

/** Сохранённый выбор; без хранилища (приватный режим) — «как в системе». */
export function readChoice(): ThemeChoice {
  try {
    const value = localStorage.getItem(themeStorageKey);
    return value === 'light' || value === 'dark' ? value : 'system';
  } catch {
    return 'system';
  }
}

/** Действующая тема: выбор читателя или системная. */
export function effectiveTheme(): 'light' | 'dark' {
  const root = document.documentElement;
  if (root.classList.contains('dark')) return 'dark';
  if (root.classList.contains('light')) return 'light';
  return systemDark().matches ? 'dark' : 'light';
}

/** Сохраняет выбор, ставит класс на `<html>` и сообщает о смене темы. */
export function applyChoice(choice: ThemeChoice): void {
  try {
    if (choice === 'system') localStorage.removeItem(themeStorageKey);
    else localStorage.setItem(themeStorageKey, choice);
  } catch {
    // Хранилище недоступно: тема меняется до перезагрузки страницы.
  }
  const root = document.documentElement;
  root.classList.remove('light', 'dark');
  if (choice !== 'system') root.classList.add(choice);
  notifyThemeChange();
}

/** Отправляет `codelab-theme-change` с действующей темой. */
export function notifyThemeChange(): void {
  document.dispatchEvent(new CustomEvent(themeChangeEvent, { detail: { theme: effectiveTheme() } }));
}

/**
 * Следит за системной темой: пока выбор «как в системе», её смена — тоже
 * смена темы сайта, и схемы mermaid должны перерисоваться.
 */
export function watchSystemTheme(): void {
  systemDark().addEventListener('change', () => {
    if (readChoice() === 'system') notifyThemeChange();
  });
}
