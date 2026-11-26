/**
 * Сценарий живого макета и его представления в трёх клиентах.
 *
 * Почему: демо должно показывать то, что есть в продукте (design.md
 * redesign-site-showcase, D3, D4, D6). Поэтому каждая строка в данных
 * помечена видом: `ui` — строка интерфейса app из каталога локализации,
 * `quote` — цитата документа, `snippet` — текстовый снимок терминала из
 * документа, `example` — промпт, ответ модели и файл, которые пишутся в
 * данных и на странице помечены подписью примера. Первые три вида сверяются
 * при сборке: удалённый ключ или переформулированная цитата ломают сборку.
 *
 * Для чего: страницы и компоненты `components/showcase/*` читают готовый
 * объект `scenario` в frontmatter; в клиентский JavaScript строки попадают
 * только как данные разметки (D6). Интерфейс Zed не изображается: это чужой
 * продукт, его вид нельзя проверить по нашим источникам (D4).
 *
 * Как использовать: `import { scenario } from '.../scenarios'`; в тестах —
 * `createScenario(sources)` с источниками на фикстурах. Новая строка
 * интерфейса или цитата — только из `showcaseSources`; если строки нет ни в
 * каталоге, ни в документе, сначала её документирует `docs-writer`.
 */
import { quote, snippet, ui, type ShowcaseSources } from './sources';

/** Вид строки данных витрины (D6). */
export type LineKind = 'ui' | 'quote' | 'snippet' | 'example';

/** Строка данных: текст и откуда он взят. */
export interface Line {
  readonly kind: LineKind;
  readonly text: string;
}

/** Подпись под макетом: что на нём схема, а что пример (D3, D6). */
export const exampleCaption = 'Схема рабочего места; ответ модели и файл — пример.';

/** Каталог строк интерфейса app, из которого берутся подписи макета (D6). */
const uiCatalog = 'packages/flutter/codelab_ui/lib/src/l10n/codelab_ui_ru.arb';

/** Каталог строк app: подпись решённого запроса (`workbenchApprovalResolved`). */
const appCatalog = 'apps/codelab_desktop/lib/l10n/app_ru.arb';

/** Раздел руководства app об ответе на запрос разрешения. */
const permissionsRef = 'apps/codelab_desktop/doc/user/04-permissions.md#отвечать-на-запросы-разрешений';

/** Документ и раздел с клавишами ответа и блоком одобрения `codelab`. */
const cliDoc = 'apps/codelab_cli/doc/user/02-repl.md';

/** Клавиши ответа `codelab`: клавиша и слова документа (D5). */
const cliKeyRows: readonly (readonly [string, string])[] = [
  ['y', 'разрешить один раз'],
  ['a', 'разрешать всегда'],
  ['n', 'отклонить один раз'],
  ['N', 'отклонять всегда'],
  ['?', 'показать запрос целиком и спросить снова'],
];

export interface Scenario {
  readonly caption: string;
  readonly docRef: string;
  /** Подпись поля ввода и промпт. */
  readonly composer: { readonly placeholder: Line; readonly prompt: Line };
  /** Части ответа агента; их число — `parts` автомата. */
  readonly reply: readonly Line[];
  /** Строка вызова инструмента записи. */
  readonly call: { readonly tool: Line; readonly path: Line; readonly risk: Line };
  /** Карточка запроса разрешения app. */
  readonly approval: {
    readonly awaiting: Line;
    /** Заголовок карточки после ответа: в app решённый запрос подписан «Решено». */
    readonly resolved: Line;
    readonly scopeOnce: Line;
    readonly scopeAlways: Line;
    readonly allow: Line;
    readonly reject: Line;
  };
  /** Исходы: метка в строке вызова и итог агента. */
  readonly outcomes: {
    readonly allowed: { readonly tag: Line; readonly summary: Line };
    readonly rejected: { readonly tag: Line; readonly summary: Line };
  };
  readonly clients: {
    readonly app: { readonly docRef: string };
    readonly cli: {
      readonly docRef: string;
      /** Блок одобрения из текстового снимка руководства `codelab`. */
      readonly block: Line;
      /** Что показывает снимок — слова руководства. */
      readonly blockNote: Line;
      readonly keys: readonly { readonly key: Line; readonly answer: Line }[];
      /** Ограничение таблицы клавиш: слова руководства (`02-repl.md#разрешения`). */
      readonly onlyOffered: Line;
      /** Что будет, если агент не предложил «разрешать всегда»: слова руководства. */
      readonly noAlways: Line;
    };
    readonly zed: {
      readonly docRef: string;
      readonly text: Line;
      /** Формат настроек принадлежит Zed (слова руководства). */
      readonly caveat: Line;
      /** Пример настроек в руководстве не подтверждён проверкой (слова руководства). */
      readonly unverified: Line;
    };
  };
}

/** Собирает сценарий из источников [sources]; любая несоответствующая строка — `ShowcaseSourceError`. */
export function createScenario(sources: ShowcaseSources): Scenario {
  const fromUi = (key: string): Line => ({ kind: 'ui', text: sources.ui(uiCatalog, key) });
  const fromApp = (key: string): Line => ({ kind: 'ui', text: sources.ui(appCatalog, key) });
  const fromQuote = (document: string, text: string): Line => ({ kind: 'quote', text: sources.quote(document, text) });
  const example = (text: string): Line => ({ kind: 'example', text });

  return {
    caption: exampleCaption,
    docRef: permissionsRef,
    composer: {
      placeholder: fromUi('codeLabComposerPlaceholder'),
      prompt: example('Исправь заголовок в README.md'),
    },
    reply: [
      example('Открываю README.md.'),
      example('Заголовок можно сократить до названия проекта.'),
      example('Запись в README.md требует вашего разрешения.'),
    ],
    call: {
      tool: example('Edit'),
      path: example('README.md'),
      risk: fromUi('codeLabRiskLocalWrite'),
    },
    approval: {
      awaiting: fromUi('codeLabApprovalAwaiting'),
      resolved: fromApp('workbenchApprovalResolved'),
      scopeOnce: fromUi('codeLabApprovalScopeOnce'),
      scopeAlways: fromUi('codeLabApprovalScopeAlways'),
      allow: fromUi('codeLabApprovalAllow'),
      reject: fromUi('codeLabApprovalReject'),
    },
    outcomes: {
      allowed: { tag: example('разрешено'), summary: example('Заголовок README.md изменён.') },
      rejected: { tag: example('отклонено'), summary: example('Правку я не сделал: вы её отклонили.') },
    },
    clients: {
      app: { docRef: permissionsRef },
      cli: {
        docRef: `${cliDoc}#разрешения`,
        block: { kind: 'snippet', text: sources.snippet(`${cliDoc}#разрешения`, 1) },
        blockNote: fromQuote(
          cliDoc,
          'Так выглядит блок, когда агент хочет изменить файл (режим `standard`; тестовая модель попросила правку `README.md`, папка проекта замаскирована):',
        ),
        onlyOffered: fromQuote(cliDoc, 'Работают только варианты, которые предложил агент.'),
        noAlways: fromQuote(cliDoc, 'Если агент не предложил «разрешать всегда», клавиша `a` ничего не отправит.'),
        // Строка таблицы подтверждается целиком (клавиша и ответ вместе), на
        // страницу идут клавиша и слова документа (D5, D6).
        keys: cliKeyRows.map(([key, answer]) => {
          fromQuote(cliDoc, `| \`${key}\` | ${answer} |`);
          return { key: { kind: 'quote', text: key }, answer: { kind: 'quote', text: answer } };
        }),
      },
      zed: {
        docRef: 'docs/user/zed.md#разрешения-и-режимы',
        text: fromQuote('docs/user/zed.md', 'Агент спрашивает у Zed разрешение на опасные действия (правки, команды) по правилам режима.'),
        // Цитата целиком, без вырванного «пока чек-лист не подписан…»: сайт
        // не ссылается на внутренний чек-лист (замечание проверки фактов 6.1).
        caveat: fromQuote('docs/user/zed.md', 'Формат настроек Zed принадлежит Zed и меняется между версиями'),
        unverified: fromQuote('docs/user/zed.md', 'пример не подтверждён проверкой'),
      },
    },
  };
}

/** Все строки сценария: для тестов, проверки подписи и тона. */
export function linesOf(value: unknown): Line[] {
  if (Array.isArray(value)) return value.flatMap(linesOf);
  if (typeof value !== 'object' || value === null) return [];
  const record = value as Record<string, unknown>;
  if (typeof record.kind === 'string' && typeof record.text === 'string') return [record as unknown as Line];
  return Object.values(record).flatMap(linesOf);
}

/** Сценарий настоящего репозитория: сверка источников идёт при импорте (D6). */
export const scenario: Scenario = createScenario({ ui, quote, snippet });
