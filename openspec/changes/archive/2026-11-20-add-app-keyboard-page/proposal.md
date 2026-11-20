## Why

Страница «Settings › Keyboard» (экран 27, `dart-agent-and-clients` §12.4.9, A13) есть в навигации как значение `SettingsPage.keyboard`, но в сборке её нет: `defaultSettingsPages` её не регистрирует, тела нет. Сочетания app пользователь узнаёт только из подсказок на отдельных кнопках (палитра, «New session», варианты одобрения) и из руководства.

Сочетания сейчас объявлены литералами `SingleActivator` и сравнениями `LogicalKeyboardKey` в девяти файлах кита и app, а подписи к ним (`⌘K`, `Ctrl+⏎`) собираются отдельно, своими проверками платформы. Страница, написанная третьим списком, разошлась бы с привязками при первом же новом сочетании.

Объём одобрен пользователем 2026-11-19: страница показывает **только сочетания, которые реально работают в app**. Сочетаний холста без поведения на ней нет, новые привязки клавиш не вводятся. Решения по вопросам Q1–Q4 от того же дня — в design.md, раздел «Решения пользователя 2026-11-19».

## What Changes

- **Каталог сочетаний в ките** `codelab_ui`: `CodeLabShortcut` (`lib/src/atomics/codelab_shortcuts.dart`). Каждая запись — группа страницы и клавиши. Из записи берутся:
  - активаторы привязок; «основной модификатор» привязывается и к Ctrl, и к ⌘ на всех платформах, как сейчас;
  - подписи клавиш по платформе: кейкапы для страницы и короткая подсказка для кнопок.

  Каталог — единственный источник и привязок, и страницы (design.md, D2).
- **Привязки берут активаторы из каталога**:
  - `CodeLabWorkbenchShortcuts`, композер, варианты одобрения, дерево Files и выдвижные панели раскладки в ките;
  - Esc экрана настроек и диалогов app.

  Подсказки `⌘K`/`Ctrl+K`, `⌘N`/`Ctrl+N` и подсказки вариантов одобрения строятся каталогом. Два теста-сторожа:
  - литералов активаторов вне каталога нет — ни в ките, ни в app;
  - каждая запись каталога проверена нажатием (D3).

  Неподключённые параметры `CodeLabWorkbenchShortcuts` (`onApprove`, `onReject`, `onInspectorPrevious`, `onInspectorNext`) удаляются (решение пользователя Q2): app их не передаёт, и на странице они значились бы сочетаниями без поведения.
- **Страница «Keyboard»** группы «App» (ключи `settings-nav-keyboard`, `settings-keyboard`):
  - заголовок «Keyboard shortcuts» и поле «Search by action or key»;
  - подпись «только для чтения»;
  - таблица Action · Shortcut · Where с группами Global, Navigation, Transcript, Composer, Approvals; клавиши — кейкапы моноширинным шрифтом;
  - внизу строка «Agent commands have no shortcuts; open them from the command palette.»

  Страница видна всегда: у неё нет ключей конфигурации, её содержимое — каталог сборки (D7). Поиск — по действию на языке интерфейса и по-английски и по клавише в любой нотации (D8). Таблица в узком окне прокручивается по горизонтали (D9).
- **Обозначения клавиш по платформе**: на macOS ⌘ ⌥ ⇧ ⏎ ⌫, на остальных ОС Ctrl, Alt, Shift, Enter, Backspace. Платформу определяет `defaultTargetPlatform` внутри каталога, а не `Platform.is*` в feature-коде (D4). На Windows и Linux подсказка «Allow always» меняется с `Alt+Ctrl+⏎` на `Ctrl+Alt+⏎`: в каталоге один порядок модификаторов `Ctrl`, `Alt`, `Shift` (D4; решение пользователя Q4). Подписи холста «on macOS Ctrl reads Cmd» нет (Q1).
- **Локализация**: действия, места, группы, подписи и пустой результат — сообщения ARB `en` и `ru`. Строки одобрения помечены `security`. Обозначения клавиш не переводятся (D5).

Итоговые строки таблицы — design.md, D1; эталон — spec app-settings «Страница «Keyboard»: строки таблицы».

## Не входит

- **Сочетания холста без поведения в сборке** (решение пользователя 2026-11-19):
  - Cmd/Ctrl+/ «Show shortcuts»;
  - Cmd/Ctrl+Shift+I — панель Protocol;
  - Cmd/Ctrl+Shift+F — поиск сессий;
  - Cmd/Ctrl+\\ — split view;
  - Cmd/Ctrl+Shift+D — панель Diff;
  - Cmd/Ctrl+O — выбор проекта;
  - Cmd/Ctrl+Shift+Enter — steering;
  - Alt+Enter — `@mention`;
  - Ctrl+\` и Ctrl+Shift+\` — терминал.

  Строки появятся на странице вместе с поведением в своих changes. Терминал — итерация 3 change `add-integrated-terminal`, её задача 3.4 дополнена строками каталога (задача 0.4 этого change).
- **Новые привязки и переназначение клавиш.** Ни одно сочетание не добавляется и не меняет действие. Alt+←/→ остаются зарезервированы за навигацией инспектора (DSK-18), но не привязаны (D3).
- **Пункт палитры «Keyboard shortcuts»** (A13, шаг 4) — вместе с Cmd/Ctrl+/ в своём change.
- **Стандартное поведение элементов**: Tab и Shift+Tab, Space и Enter на кнопке, Cmd/Ctrl+C и правка текста в полях (Enter — новая строка композера). Это не привязки app, на странице их нет (D1).
- **Страница на телефоне и планшете** (§12.8.4, §12.8.5) — с профилем `mobile`, его в сборке нет.
- **Изменения ACP**: протокол, модели и фикстуры не меняются.

## Capabilities

### New Capabilities

Нет.

### Modified Capabilities

- `app-settings` — ADDED:
  - «Страница «Keyboard»: видимость и навигация»;
  - «Страница «Keyboard»: строки таблицы»;
  - «Страница «Keyboard»: обозначения клавиш»;
  - «Страница «Keyboard»: поиск»;
  - «Страница «Keyboard»: язык, доступность и узкое окно»;
  - «Сочетания app и страница «Keyboard» не расходятся».

## Impact

- **Код:**
  - `packages/flutter/codelab_ui` (`[desktop]`):
    - `atomics/codelab_shortcuts.dart` (`CodeLabShortcut`, `CodeLabShortcutGroup`, `CodeLabKeyCombo`);
    - `atomics/codelab_keycaps.dart` (`CodeLabKeycaps`);
    - `organisms/codelab_shortcut_table.dart` (`CodeLabShortcutTable`);
    - перевод привязок на каталог: `codelab_workbench_shortcuts.dart`, `codelab_prompt_composer.dart`, `codelab_approval_option_group.dart`, `codelab_file_tree.dart`, `codelab_workbench_layout.dart`;
    - превью, барели, `README.md`, `AGENTS.md`.
  - `apps/codelab_desktop` (`[desktop]`):
    - `features/settings/presentation/keyboard_page.dart`;
    - `features/settings/application/keyboard_shortcut_search.dart`;
    - регистрация в `default_settings_pages.dart` и `settingsPageBuilders`;
    - `settingsPageKeywordsOf`;
    - Esc в `settings_shell.dart`, `add_profile_dialog.dart`, `provider_wizard_dialog.dart`, `agents_modes_page.dart` — из каталога;
    - подсказки в `workbench_shell.dart` — из каталога;
    - ARB `en`/`ru`.
- **Зависимости и граф:** новых пакетов, зависимостей и рёбер нет. Граф в `README.md` и allowlist (PKG-2, `desktopAllowlist`) не меняются. Правило в `codelab_architecture_tests/test/support/rules.dart` не добавляется: сторож проверяет импорты и `pubspec`, а литералы активаторов проверяют тесты пакетов (D3).
- **ACP:** без изменений.
- **Данные пользователя:** ничего не читается и не пишется. Работает только прежний `codelab.settings.last_page` со значением `keyboard`.
- **Безопасность:** страница не отвечает на запросы разрешений и ничего не выполняет. Привязки одобрения сохраняют прежние клавиши и работают так же. Перевод на каталог проверяют прежние тесты одобрения и новый тест нажатий (D3).
- **Документы:**
  - `12-4-first-run-and-settings.md` (строка «Keyboard (27)», SETUP-17);
  - `12-3-desktop-display.md` (A13 шаг 3, DSK-18);
  - `platform-integration.md` §5;
  - `delivery-roadmap.md` (строка 27);
  - всё перечисленное выше обновлено при подготовке change;
  - `apps/codelab_desktop/doc/user-guide.md`, `apps/codelab_desktop/AGENTS.md`, `packages/flutter/codelab_ui/AGENTS.md` и `README.md`, `docs/architecture/l10n-glossary.md` — задачи итерации 4.
