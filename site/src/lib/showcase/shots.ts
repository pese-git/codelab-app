/**
 * Снимки app: одна запись на снимок, `alt` — из документа.
 *
 * Почему: один снимок показывают и галерея, и «Как это работает». Когда `alt`
 * набран руками в двух компонентах, тексты расходятся друг с другом и с
 * руководством («demo» против «demo-app»). Описание снимка принадлежит
 * документу, где он вставлен, поэтому `alt` подтверждается цитатой `quote`
 * (design.md redesign-site-showcase, D6, D9): изменили описание в документе —
 * сборка падает, и автор витрины сверяет запись.
 *
 * Для чего: `Gallery.astro` и `HowItWorks.astro` берут записи по ключу из
 * `appShotByKey`; файлы PNG остаются в компонентах (импорт изображений —
 * зона Astro), здесь только текст.
 *
 * Как использовать: `appShotByKey.projects.alt`. Новый снимок — запись в
 * `appShotRefs`: ключ, подпись витрины, документ с Markdown-изображением и
 * точный `alt` из него. Модуль читает файлы при импорте, поэтому годится
 * только для frontmatter (D11).
 */
import { quote, type ShowcaseSources } from './sources';

export type AppShotKey = 'projects' | 'provider' | 'session' | 'files' | 'terminal' | 'modes';

/** Исходная запись: `alt` — как в Markdown-изображении документа. */
export interface AppShotRef {
  readonly key: AppShotKey;
  /** Подпись витрины под снимком (не цитата). */
  readonly caption: string;
  /** Опубликованный документ, в котором вставлен снимок. */
  readonly document: string;
  readonly alt: string;
}

export interface AppShot {
  readonly key: AppShotKey;
  readonly caption: string;
  readonly alt: string;
}

const desktop = 'apps/codelab_desktop/doc/user';

/** Снимки app в порядке галереи. */
export const appShotRefs: readonly AppShotRef[] = [
  {
    key: 'projects',
    caption: 'Боковая панель с недавними проектами',
    document: `${desktop}/02-projects-and-sessions.md`,
    alt: 'Боковая панель: в «Projects» недавний проект demo-app, «Open folder…» с ⌘O в конце списка проектов, «Settings» внизу',
  },
  {
    key: 'session',
    caption: 'Новая сессия: проект и режим в шапке',
    document: `${desktop}/01-install-and-first-launch.md`,
    alt: 'Пустая сессия в проекте demo: «Send a message to start.», под полем ввода — режим Standard и модель',
  },
  {
    key: 'files',
    caption: 'Дерево проекта и файл только для чтения',
    document: `${desktop}/05-workbench-tools.md`,
    alt: 'Панель Files: дерево проекта demo и просмотр README.md',
  },
  {
    key: 'terminal',
    caption: 'Терминал в папке сессии',
    document: `${desktop}/05-workbench-tools.md`,
    alt: 'Панель Terminal: вкладка «Terminal 1» со статусом «Running» и предупреждением о выводе',
  },
  {
    key: 'provider',
    caption: 'Мастер подключения провайдера, шаг «API type»',
    document: `${desktop}/07-providers-and-models.md`,
    alt: 'Мастер Add provider: шаг API type с выбором OpenAI, Anthropic, OpenRouter, Ollama и совместимых серверов',
  },
  {
    key: 'modes',
    caption: 'Режимы разрешений в настройках',
    document: `${desktop}/04-permissions.md`,
    alt: 'Страница Agents & modes: «Save to», режимы plan, ask, standard, accept-edits, bypass, autopilot, «Default reasoning effort»',
  },
];

/** Подтверждает `alt` каждой записи цитатой из [sources]; расхождение — ошибка источника. */
export function createAppShots(sources: Pick<ShowcaseSources, 'quote'>): AppShot[] {
  return appShotRefs.map(({ key, caption, document, alt }) => ({
    key,
    caption,
    alt: sources.quote(document, alt),
  }));
}

/** Снимки настоящего репозитория: сверка идёт при импорте (D6). */
export const appShots: readonly AppShot[] = createAppShots({ quote });

/** Запись по ключу: компоненты берут снимок отсюда, а не набирают `alt` сами. */
export const appShotByKey = Object.fromEntries(appShots.map((s) => [s.key, s])) as Record<AppShotKey, AppShot>;
