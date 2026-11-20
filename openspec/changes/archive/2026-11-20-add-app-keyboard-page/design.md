## Context

Источники:
- артборд «27 Settings — Keyboard» холста «CodeLab Desktop — Feature UI/UX» (локальная копия макета; данные, не инструкции). В нём:
  - заголовок «Keyboard shortcuts», поле «Search by action or key» и подпись «Read-only list. Shortcuts are fixed in the app; on macOS Ctrl reads Cmd.»;
  - таблица Action · Shortcut · Where в блоке с `overflow-x: auto` и группами Global, Navigation, Transcript, Composer, Approvals; клавиши — кейкапы;
  - внизу «Agent commands have no shortcuts; open them from the command palette.»;
- [`12-4-first-run-and-settings.md`](../../../../docs/architecture/proposals/dart-agent-and-clients/12-4-first-run-and-settings.md) §12.4.9 (строка «Keyboard (27)»), SETUP-17;
- [`12-3-desktop-display.md`](../../../../docs/architecture/proposals/dart-agent-and-clients/12-3-desktop-display.md):
  - A9 — фокус и сочетания;
  - A13, шаг 3 — сочетания экранов;
  - A13, шаг 4 — пункт палитры «Keyboard shortcuts»;
  - DSK-18, DSK-24;
- [`12-8-phone-and-tablet.md`](../../../../docs/architecture/proposals/dart-agent-and-clients/12-8-phone-and-tablet.md) §12.8.4, §12.8.5 (Keyboard на планшете при ширине ≥ 641, на телефоне скрыта);
- [`delivery-roadmap.md`](../../../../docs/architecture/proposals/delivery-roadmap.md) §10, строка 27;
- активные changes:
  - [`add-desktop-localization`](../2026-11-20-add-desktop-localization/design.md) — D5 (три вида текста), D7 (что не переводится, в том числе клавиши), D12 (параллельные changes пишут строки сразу в ARB), D14 (метка `security`);
  - [`add-app-general-page`](../2026-11-20-add-app-general-page/design.md) — D15 (ключевые слова поиска в ARB);
  - [`add-app-skills-page`](../../add-app-skills-page/design.md) — MODIFIED «Страницы Providers и MCP servers в навигации»;
  - [`add-integrated-terminal`](../../add-integrated-terminal/design.md) — D6, итерация 3: Ctrl+\` по физической клавише, только Control;
  - [`add-file-preview-and-tree`](../../add-file-preview-and-tree/design.md) — дерево Files;
- спецификации `app-settings`, `agent-workbench-ui`, `workspace-file-browser`;
- `AGENTS.md` (корень, §6, §8, §11, §13, §14, §15) и вложенные: `apps/codelab_desktop`, `packages/flutter/codelab_ui`, `packages/dart/codelab_agent_core` (TDD, §2);
- `docs/architecture/`: `layers-and-dependencies.md`, `platform-integration.md` §5, `state-management.md`, `testing.md`, `observability.md`, `l10n-glossary.md`.

Что есть в коде (сверено 2026-11-19 на ветке `feature/add-app-keyboard-page` от `develop` 81c9c3d3):
- `SettingsPage.keyboard` (slug `keyboard`, группа `app`) есть в enum. Заголовок `settingsPageKeyboardTitle` в ARB есть (`Keyboard`/«Клавиатура»). В `defaultSettingsPages` и `settingsPageBuilders` страницы нет. В `settingsPageKeywordsOf` для `keyboard` — пустая строка.
- Привязки клавиш (литералы `SingleActivator`, `LogicalKeyboardKey`):
  - `codelab_ui/organisms/codelab_workbench_shortcuts.dart`: Cmd/Ctrl+K, Esc, Cmd/Ctrl+N, Cmd/Ctrl+B, Cmd/Ctrl+,, Cmd/Ctrl+Shift+E — каждое в двух вариантах, `control` и `meta`, на всех платформах. Ещё Cmd/Ctrl+Enter (`onApprove`), Cmd/Ctrl+Backspace (`onReject`) и Alt+←/→ (`onInspectorPrevious`/`onInspectorNext`). **Эти четыре колбэка app не передаёт** (`workbench_shell.dart`): привязок в app нет. Esc рабочего места — цепочка `workbench_shell.dart`: сначала отказ от сессии в корне диска (`cancelRootSession`), затем закрытие палитры, затем отмена хода (`cancelTurn`, если `canCancel`).
  - `codelab_ui/molecules/codelab_prompt_composer.dart`: Cmd/Ctrl+Enter — отправка. Пока открыта inline-палитра — Enter (выбор), ↑/↓, Esc (закрыть); иначе Esc — отмена хода при `canCancel`. Enter без модификатора в многострочном `TextBox` — новая строка (тест «Enter selects the highlighted inline command instead of inserting a newline»).
  - `codelab_ui/molecules/codelab_approval_option_group.dart` (`CodeLabApprovalShortcuts`), им же пользуется `organisms/codelab_approval_prompt.dart`: Cmd/Ctrl+Enter — `allow_once`, +Alt — `allow_always`, Cmd/Ctrl+Backspace — `reject_once`, +Alt — `reject_always`. Подсказка `labelFor` сама проверяет `defaultTargetPlatform`: `⌘⏎`, `⌥⌘⏎` или `Ctrl+⏎`, `Alt+Ctrl+⏎`.
  - `codelab_ui/organisms/codelab_file_tree.dart`: `onKeyEvent` сравнивает `logicalKey` — ↑/↓, Enter и numpad Enter, →/←.
  - `codelab_ui/organisms/codelab_workbench_layout.dart`: Esc закрывает выдвижную панель (сайдбар или док поверх ленты).
  - app: Esc в `settings_shell.dart` (назад на рабочее место), `add_profile_dialog.dart`, `provider_wizard_dialog.dart`, `agents_modes_page.dart` (подтверждение `bypass`).
- Подсказки сочетаний: `workbench_shell.dart` сам выбирает `'⌘K'`/`'Ctrl+K'` и `'⌘N'`/`'Ctrl+N'` по `defaultTargetPlatform`.
- Терминал (`add-integrated-terminal`, итерации 1–2) привязок клавиш app не вводит. Ctrl+\` и Ctrl+Shift+\` — итерация 3, после 1.0.

## Goals / Non-Goals

**Goals:**
- страница «Keyboard» со всеми привязками сборки и только с ними;
- один источник клавиш для привязок, подсказок и страницы, чтобы они не могли разойтись;
- обозначения клавиш по платформе без `Platform.is*` в feature-коде;
- поиск по действию (язык интерфейса и английский) и по клавише в любой нотации.

**Non-Goals:**
- новые привязки, переназначение клавиш, Cmd/Ctrl+/ и пункт палитры «Keyboard shortcuts»;
- сочетания холста без поведения;
- страница на телефоне и планшете;
- изменения ACP.

## Decisions

### D1. Объём: только работающие привязки

Страница показывает каждую привязку, которая в этой сборке выполняет действие app, и ничего больше (решение пользователя 2026-11-19). Перечень сверен с кодом, источник каждой строки указан ниже.

| Группа | id | Действие (en) | Клавиши | Где (en) | Источник |
|---|---|---|---|---|---|
| Global | `command-palette` | Open the command palette | Cmd/Ctrl+K | Workbench | `CodeLabWorkbenchShortcuts.onOpenCommandPalette` |
| Global | `new-session` | New session | Cmd/Ctrl+N | Workbench, when a project is selected | `onNewSession` (передаётся при выбранном проекте) |
| Global | `open-settings` | Open settings | Cmd/Ctrl+, | Workbench | `onOpenSettings` |
| Global | `close-overlay` | Close the command palette, a dialog or a sliding panel | Esc | Command palette, dialog or sliding panel | цепочка Esc рабочего места (палитра, диалог сессии в корне диска), `_OverlayPanel` раскладки, диалоги настроек |
| Global | `leave-settings` | Back to the workbench | Esc | Settings | `settings_shell.dart` |
| Navigation | `toggle-sidebar` | Show or hide the sidebar | Cmd/Ctrl+B | Workbench | `onToggleSidebar` |
| Navigation | `toggle-files` | Show or hide the Files pane | Cmd/Ctrl+Shift+E | Workbench, when the Files pane is available | `onToggleFiles` (при `projectFilesAvailable`) |
| Navigation | `file-tree-move` | Move through files | ↑ / ↓ | Files tree | `CodeLabFileTree._onKey` |
| Navigation | `file-tree-fold` | Expand or collapse a folder | → / ← | Files tree, on a folder | то же |
| Navigation | `file-tree-open` | Open a file or expand a folder | Enter (и numpad Enter) | Files tree | то же |
| Transcript | `cancel-turn` | Cancel the running turn | Esc | Workbench or composer, while a turn runs | `onCancel` рабочего места, Esc композера |
| Composer | `send` | Send the message; it is queued while the session is busy | Cmd/Ctrl+Enter | Composer | композер, очередь — spec agent-workbench-ui «Messages queue…» |
| Composer | `command-menu-move` | Move through commands | ↑ / ↓ | Command menu after / | inline-палитра композера |
| Composer | `command-menu-run` | Run the highlighted command | Enter | Command menu after / | то же |
| Composer | `command-menu-close` | Close the command menu | Esc | Command menu after / | то же |
| Approvals | `allow-once` | Allow once | Cmd/Ctrl+Enter | Pending approval in focus, when the agent offers this option | `CodeLabApprovalShortcuts` |
| Approvals | `allow-always` | Allow always | Cmd/Ctrl+Alt+Enter | то же | то же |
| Approvals | `reject-once` | Reject once | Cmd/Ctrl+Backspace | то же | то же |
| Approvals | `reject-always` | Reject always | Cmd/Ctrl+Alt+Backspace | то же | то же |

На странице нет:
- **сочетаний холста без поведения**:
  - Cmd/Ctrl+/ — список сочетаний;
  - Cmd/Ctrl+Shift+I — Protocol;
  - Cmd/Ctrl+Shift+F — поиск сессий;
  - Cmd/Ctrl+\\ — split view;
  - Cmd/Ctrl+Shift+D — Diff;
  - Cmd/Ctrl+O — выбор проекта;
  - Cmd/Ctrl+Shift+Enter — steering;
  - Alt+Enter — `@mention`;
  - Backspace удаления чипа (чипов вложений в композере нет);
  - Ctrl+\` и Ctrl+Shift+\` — терминал.

  Строки появятся со своими changes (D13).
- **Неподключённых параметров кита** (D3).
- **Стандартного поведения элементов**: Tab и Shift+Tab, Space и Enter на кнопке, правка текста (Enter — новая строка, Shift+Enter), Cmd/Ctrl+C. Это поведение Flutter и Fluent, а не привязки app. Страница, перечисляющая его, превратилась бы в справку по ОС.

Навигация внутри дерева Files и inline-меню команд на странице есть: это привязки, которые объявляет код CodeLab. Без них пользователь не узнает, что дерево и меню управляются с клавиатуры. На странице 19 строк (решение пользователя Q3, 2026-11-19).

### D2. Каталог сочетаний — в ките, рядом с привязками

`packages/flutter/codelab_ui/lib/src/atomics/codelab_shortcuts.dart`:

```dart
enum CodeLabShortcutGroup { global, navigation, transcript, composer, approvals }

/// Одна комбинация: основной модификатор (Ctrl и ⌘), Alt, Shift и клавиша.
final class CodeLabKeyCombo {
  const CodeLabKeyCombo(this.key, {this.primary = false, this.alt = false,
      this.shift = false, this.alsoKeys = const []});
  final LogicalKeyboardKey key;
  final List<LogicalKeyboardKey> alsoKeys; // numpad Enter у дерева Files
  final bool primary, alt, shift;
  List<SingleActivator> get activators;    // primary → control и meta
  bool accepts(KeyEvent event, HardwareKeyboard keyboard);
  List<String> capsFor(TargetPlatform platform);   // кейкапы страницы
  String compactFor(TargetPlatform platform);      // «⌘K», «Ctrl+⏎»
  String spokenFor(TargetPlatform platform);       // «Option+Cmd+Enter»
  Iterable<String> searchNotations();              // D8
}

enum CodeLabShortcut {
  commandPalette(CodeLabShortcutGroup.global, [CodeLabKeyCombo(LogicalKeyboardKey.keyK, primary: true)]),
  // … 19 записей в порядке D1
  ;
  final CodeLabShortcutGroup group;
  final List<CodeLabKeyCombo> combos;   // альтернативы: ↑ / ↓
  String get id;                        // kebab-case для ключей тестов
  Map<ShortcutActivator, VoidCallback> bind(VoidCallback action);
}
```

Сигнатуры — ориентир для исполнителя, не контракт.

Почему в ките:
- все привязки, кроме четырёх Esc в app, объявлены в ките;
- прецедент — `CodeLabApprovalShortcuts`: кит уже держит соответствие «вид варианта → клавиши» и подсказку;
- AGENTS кита (§2) допускает в ките клавиши и фокус. Каталог — словарь клавиш, а не политика: какое действие разрешено и что опасно, по-прежнему решает app. Тексты действий в каталоге не живут (D5).

Почему в `atomics/`: каталог импортируют молекулы (композер, одобрение), организмы (оболочка, дерево, раскладка) и app; импорт в ките идёт только вниз по слоям. Тексты каталогу не нужны, поэтому `l10n` кита он не использует.

Альтернативы:
- **Таблица страницы в app отдельно от привязок, сверка тестом.** Третий список рядом с двумя существующими. Тест ловит расхождение только для того, что сам перечисляет. Отклонено.
- **Каталог в app, кит получает активаторы параметрами.** Меняет API пяти виджетов кита ради данных, которые и так принадлежат киту (одобрение). Отклонено.
- **Генерация таблицы из исходников.** Несоразмерно (§13). Отклонено.

`FooRegistry`, сервиса и Cubit нет: каталог — `enum` с данными и чистыми функциями.

### D3. Привязки только из каталога; сторожа

- Каждая привязка в ките и app берёт активаторы из записи каталога: `CodeLabShortcut.x.bind(action)` или `combo.activators`. Дерево Files сравнивает событие через `combo.accepts(event, HardwareKeyboard.instance)` вместо сравнения `logicalKey`. Порядок обработки, условия (`canCancel`, открыта ли inline-палитра) и цепочка Esc рабочего места не меняются. Одно видимое следствие: дерево Files сверяет модификаторы точно, как `SingleActivator`, — Ctrl+Enter, ⌘⏎, Shift+↓ и Alt+→ в дереве больше не срабатывают и всплывают выше (раньше дерево сравнивало только `logicalKey` и поглощало их). Это освобождает Alt+←/→ под резерв DSK-18 и не даёт дереву глотать Cmd/Ctrl+Enter; негативный сценарий — `codelab_file_tree_test.dart` (по ревью 2026-11-19).
- **Неподключённые параметры удаляются** из `CodeLabWorkbenchShortcuts`: `onApprove`, `onReject`, `onInspectorPrevious`, `onInspectorNext`.
  - app их не передаёт с тех пор, как одобрение привязывает свои клавиши само (`lighten-approval-block`, D2), а навигации инспектора по Alt+←/→ в сборке нет;
  - оставить их значит держать в каталоге записи без поведения, то есть нарушить D1;
  - DSK-18 по-прежнему резервирует Alt+←/→ за навигацией инспектора; на страницу они не попадают, документ уточнён (решение пользователя Q2, 2026-11-19).
- **Подсказки** `⌘K`/`Ctrl+K` (шапка), `⌘N`/`Ctrl+N` (сайдбар) и подсказки вариантов одобрения строятся `compactFor(defaultTargetPlatform)` каталога. Проверки платформы в `workbench_shell.dart` и `CodeLabApprovalShortcuts.labelFor` уходят.
- **Сторож 1, литералы.** Тест `packages/flutter/codelab_ui/test/shortcut_catalog_guard_test.dart` читает `lib/src/**.dart`. Тест `apps/codelab_desktop/test/app/shortcut_catalog_guard_test.dart` читает `lib/**.dart`, кроме сгенерированного `lib/l10n/app_localizations*.dart`. Оба падают, если вне `codelab_shortcuts.dart` встречаются:
  - `SingleActivator(`, `CharacterActivator(`, `LogicalKeySet(`;
  - сравнение с `LogicalKeyboardKey.` (`==` или `!=`);
  - `LogicalKeySet.fromSet(`, `isLogicalKeyPressed(`;
  - чтение `.logicalKey` и `.physicalKey`, любое упоминание `PhysicalKeyboardKey.`, `case LogicalKeyboardKey.` и `LogicalKeyboardKey.x =>` — так сторож ловит и привязку по физической клавише, и разбор клавиш `switch` (по ревью 2026-11-19).

  Сообщение называет файл и строку.
- **Сторож 2, нажатие.** Табличный тест обходит `CodeLabShortcut.values`. Для каждой записи `switch` без `default` возвращает сценарий: виджет, место фокуса и ожидаемое действие. Новая запись без сценария не компилируется.

  Записи распределены по пакетам:
  - записи кита проверяет `packages/flutter/codelab_ui/test/codelab_shortcut_bindings_test.dart`;
  - записи app (`leave-settings` и Esc диалогов в составе `close-overlay`) — `apps/codelab_desktop/test/features/settings/presentation/keyboard_bindings_test.dart`.

  Для записей с основным модификатором проверяются оба активатора, `control` и `meta`.
- **Не правило `rules.dart`.** Сторож `codelab_architecture_tests` проверяет импорты и `pubspec`, текст кода он не разбирает. Литералы активаторов — правило двух пакетов, и проверяют его тесты этих пакетов. Так же устроены `agent_defaults_rows_test.dart` и `legal_assets_test.dart`.

### D4. Обозначения клавиш по платформе

- Платформу выбирает только каталог, по `defaultTargetPlatform` (`package:flutter/foundation.dart`).
  - Это не `Platform.is*` из `dart:io`: значение подменяется в тестах (`debugDefaultTargetPlatformOverride`), и по нему Flutter сам выбирает соглашения интерфейса.
  - Feature-код и страница получают готовые строки (`capsFor`, `compactFor`, `spokenFor`) и платформу сами не проверяют (AGENTS.md §11).
  - `platform-integration.md` §5 дополнен этим правилом.
- macOS: ⌘ ⌥ ⇧ ⏎ ⌫, порядок модификаторов как в меню macOS — ⌥ ⇧ ⌘. Поэтому `⇧⌘E`, а не `⌘⇧E` из руководства пользователя; руководство исправляется в задаче 4.2.
- Остальные ОС: `Ctrl`, `Alt`, `Shift`, `Enter`, `Backspace`, порядок `Ctrl` `Alt` `Shift`.
- `Esc`, буквы, `,`, ↑ ↓ ← → одинаковы на всех платформах.
- Короткая подсказка на Windows и Linux сохраняет прежние символы `⏎` и `⌫`: кнопки варианта одобрения узкие. Порядок модификаторов в ней общий, поэтому `Alt+Ctrl+⏎` становится `Ctrl+Alt+⏎` (решение пользователя Q4, 2026-11-19). Привязки не меняются.
- Подпись для чтения с экрана — словами (`Option+Cmd+Enter`, `Ctrl+Alt+Enter`): символы ⌥⌘⏎ программы чтения произносят непредсказуемо.

Подпись холста «on macOS Ctrl reads Cmd» не берётся: страница показывает клавиши платформы, как подсказки на рабочем месте. Так пользователю не нужно переводить обозначения в уме (решение пользователя Q1, 2026-11-19). Подпись страницы — `Read-only list. Shortcuts are fixed in the app.` на всех платформах.

Альтернативы:
- всегда `Ctrl` с пояснением, как на холсте, — расходится с подсказками `⌘K` на рабочем месте;
- две колонки, macOS и остальные ОС, — шире таблица, а половина строк пользователю не нужна.

Обе отклонены.

### D5. Тексты

- Тексты страницы — сообщения `app_en.arb` и `app_ru.arb` с префиксом `settingsKeyboard…`:
  - заголовок, подсказка поиска, подпись, колонки, группы, строка «Agent commands», `No shortcuts match "{query}"`;
  - ключевые слова навигации `settingsSearchKeywordsKeyboard`;
  - по одному сообщению «Action» на запись каталога (для `new-session` — существующее `commonNewSession`); сообщения «Where» общие для записей с одинаковым местом (11 сообщений на 19 записей) — одинаковое место не переводится дважды.
- Соответствие «запись → сообщение» — исчерпывающие `switch` в presentation app: `keyboardShortcutActionOf(l10n, shortcut)`, `keyboardShortcutWhereOf`, `keyboardShortcutGroupOf`. Так же устроены `settingsPageTitleOf` и `settingsPageKeywordsOf`. Новая запись каталога без текста не компилируется.
- Английский эталон совпадает со спецификацией символ в символ (тест задачи 3.1).
- Обозначения клавиш и `/` в «Command menu after /» не переводятся (D7 `add-desktop-localization`).
- Тексты действий одобрения помечаются `security` в `@description`, их вычитывает пользователь (D14 `add-desktop-localization`). Переводы опираются на вычитанные «Разрешить» и «Отклонить», «Только сейчас» и «Всегда» глоссария.
- Каталог кита (`codelab_ui_*.arb`) не меняется, кроме подписи альтернатив `or` для чтения с экрана: `codeLabShortcutAlternatives` — `{first} or {second}`.
- Предлагаемые термины глоссария (§4, новый подраздел «Страница «Keyboard»»), вычитывает пользователь:

| en | ru |
|---|---|
| Keyboard shortcuts | Сочетания клавиш |
| Search by action or key | Поиск по действию или клавише |
| Read-only list. Shortcuts are fixed in the app. | Только для чтения. Сочетания заданы в приложении. |
| Action · Shortcut · Where | Действие · Сочетание · Где |
| Global · Navigation · Transcript · Composer · Approvals | Общие · Навигация · Лента · Поле ввода · Одобрения |
| Workbench | Рабочее место |
| Command menu after / | Меню команд после / |
| Files tree | Дерево файлов |
| Sliding panel | Выдвижная панель |
| Agent commands have no shortcuts; open them from the command palette. | У команд агента нет сочетаний — открывайте их из палитры команд. |
| No shortcuts match "…" | Нет сочетаний по запросу «…» |

### D6. Страница: без Cubit, поиск — чистая функция

- `features/settings/presentation/keyboard_page.dart` — `KeyboardPage` (`StatefulWidget`) и построитель `buildKeyboardPage` для `settingsPageBuilders`. Запрос поиска — временное состояние поля в `State`, как `_query` в `SettingsShell`. У страницы нет ни внешних данных, ни асинхронности, ни записи, поэтому Cubit и порт не нужны (§13).
- `features/settings/application/keyboard_shortcut_search.dart` — чистая функция:

  ```dart
  List<KeyboardShortcutEntry> filterKeyboardShortcuts(
    List<KeyboardShortcutEntry> entries, String query)
  ```

  `KeyboardShortcutEntry` содержит запись каталога, тексты действия на языке интерфейса и английский, нотации клавиш. Записи собирает страница из каталога и ARB в каждом `build`, поэтому смена языка пересобирает их без подписки (вид текста (1) D5 `add-desktop-localization`). Логики в `build` нет: сборка записей — функция рядом со страницей.
- Виджеты кита:
  - `CodeLabKeycaps` (`atomics/codelab_keycaps.dart`): кейкапы одной комбинации или альтернатив, роль `mono`, рамка с утолщённым нижним краем как на холсте, цвета `FluentTheme`, `Semantics(label: spokenFor…)`, текст кейкапов исключён из семантики;
  - `CodeLabShortcutTable` (`organisms/codelab_shortcut_table.dart`): шапка колонок и группы с заголовками; строки получает готовыми (`CodeLabShortcutTableGroup(key, title, rows)` и `CodeLabShortcutTableRow(key, action, combos, where)`). Тексты, отбор и порядок — от app, таблица только раскладывает их (§2 AGENTS кита).

  Существующий `CodeLabStatusTable` не подходит: у него нет строк-заголовков групп, а ячейки — текст или тег. Расширять его ради одной страницы значит смешать две таблицы с разной семантикой. Отдельный организм — вторая таблица кита с ясной ролью.
- Ключи: `settings-keyboard`, `settings-keyboard-search`, `settings-keyboard-group-<group>`, `settings-keyboard-row-<id>`, `settings-keyboard-empty`, `settings-keyboard-footer`.

### D7. Видимость и SETUP-17

- «Keyboard» входит в `defaultSettingsPages` всегда. Ключей конфигурации у неё нет, и `SettingsAccess` её не касается: она не читает конфиг агента, баннера «только для чтения» нет.
- SETUP-17 скрывает пустые страницы, а «Keyboard» не пуста: её содержимое — каталог сборки. В 12-4 к SETUP-17 добавлено пояснение для страниц, содержимое которых задаёт сборка, а не конфигурация.
- Видимость по ширине (≥ 641, §12.8.5) относится к планшету с профилем `mobile`. На desktop страница видна при любой ширине окна.
- Конфликт формулировок. Требование «Страницы Providers и MCP servers в навигации» говорит «остальные страницы остаются скрытыми». Его же меняет `add-app-skills-page` (MODIFIED), а «General» уже стала исключением в `add-desktop-localization` (ADDED «Язык интерфейса app»). Этот change не меняет то требование, чтобы не создать третью MODIFIED-версию одного текста. Исключение записано в ADDED-требовании «Keyboard». При архивации последнего из трёх changes фраза «остальные…» SHALL быть сведена с перечнем видимых страниц (задача 5.3).

### D8. Поиск

- Совпадение — подстрока без учёта регистра в одном из текстов:
  - действие на языке интерфейса;
  - действие по-английски;
  - нотации клавиш. Нотаций три: символами macOS, словами Windows/Linux и словами macOS. Все три есть на любой платформе: пользователь macOS может искать `ctrl`, а пользователь Windows скопировать `⌘K` из руководства.
- Для нотаций из запроса и из текста удаляются пробелы и `+`: `ctrl shift e` и `Ctrl+Shift+E` равны `ctrlshifte`.
- По «Where» поиск не идёт: холст обещает «by action or key». Иначе запрос `composer` выдавал бы половину таблицы.
- Пустой результат — `settings-keyboard-empty`. Группы без строк скрыты, строка «Agent commands» остаётся.

### D9. Доступность и узкое окно

- Таблица — `Semantics`: заголовок группы помечен `header: true`, строка — контейнер с подписью «действие, клавиши, где».
- Строки не фокусируются: они только для чтения, а 19 лишних остановок Tab замедлили бы обход. Поле поиска — первая и единственная остановка тела.
- Минимальная ширина таблицы — 380 px (ручная проверка на macOS 2026-11-20: при 780 px таблица прокручивалась уже в минимальном окне app). Тело страницы в окне 800 px — около 400 px (окно минус навигация около 320 px минус поля 2 × 40), и все три колонки должны быть видны без прокрутки. Колонка клавиш — по ширине самой широкой строки (измеряет `CodeLabKeycaps.widthOf`), колонки «Action» и «Where» гибкие (3 : 2) и переносят текст. Если тело уже 380 px, таблица в `SingleChildScrollView(scrollDirection: Axis.horizontal)` с полосой прокрутки Fluent; кейкапы не переносятся и не сжимаются. Порог раскладки навигации (760 px) не меняется. Следствие: в окне 600 px навигация лежит сверху, тело около 520 px, и прокрутки нет; прокрутка бывает только при теле уже 380 px (окно уже 460 px), в сборке app такого окна нет.

### D10. Наблюдаемость

Событий журнала нет: страница ничего не читает и не пишет, ошибок у неё нет. Открытие страницы уже видно по `codelab.settings.last_page` оболочки. Запросы поиска не журналируются: это ввод пользователя без диагностической ценности.

### D11. Отступления от артборда

- Строки — только работающие сочетания (D1): 19 вместо 22. Строк Navigation и Composer холста без поведения нет; есть дерево Files и меню команд.
- «Send · queue while a turn runs — Enter» холста заменена строкой «Cmd/Ctrl+Enter» по коду. Enter композера — новая строка.
- Подпись без «on macOS Ctrl reads Cmd» (D4).
- «Where» уточнены по условиям кода («when a project is selected», «when the Files pane is available», «in focus»).

### D12. Пакеты, зависимости, сторож, граф

| Пакет (ADR-0002) | Что меняется | Исполнитель |
|---|---|---|
| `packages/flutter/codelab_ui` | каталог `CodeLabShortcut`, `CodeLabKeycaps`, `CodeLabShortcutTable`; привязки и подсказки из каталога; удаление неподключённых параметров `CodeLabWorkbenchShortcuts`; сообщение `codeLabShortcutAlternatives` | `[desktop]` |
| `apps/codelab_desktop` | страница, поиск, регистрация, Esc и подсказки из каталога, ARB | `[desktop]` |

- Направление зависимостей прежнее: app → `codelab_ui`. Новых пакетов, зависимостей и рёбер нет. Граф `README.md`, `desktopAllowlist` и allowlist ядра (PKG-2) не меняются.
- `rules.dart` не меняется (D3).
- Задач `[protocol]`, `[agent]` и `[client]` нет: Dart-пакеты, ACP и CLI не затронуты.

### D13. Связь с другими changes

- **`add-integrated-terminal`, итерация 3** вводит Ctrl+\` и Ctrl+Shift+\` с активатором по физической клавише и только Control. Каталог расширяется в том change: комбинация «только Control» и физическая клавиша. Этот change не вводит их заранее (§13). Задача 3.4 того change дополнена строками каталога и страницы (задача 0.4).
- **`add-desktop-localization`** правит `app-settings` MODIFIED «Навигация настроек». Этот change то требование не меняет: поиск по ключевым словам ARB уже им описан, а «Keyboard» добавляет только своё сообщение. Строки пишутся сразу в ARB `en` и `ru` (D12 того change). Если `add-desktop-localization` вольётся позже, тексты страницы уже в каталоге.
- **`add-file-preview-and-tree`**: если «Insert as mention» получит сочетание (Alt+Enter холста), строка добавляется в каталог в том change.
- **`add-app-general-page`**: не пересекается. Ключевые слова поиска уже живут в ARB (D15 того change).

### D14. Итерации

0. Документы (выполнено при подготовке change).
1. Каталог и перевод привязок на него — без видимых изменений, кроме порядка `Ctrl+Alt+⏎`.
2. Виджеты кита `CodeLabKeycaps` и `CodeLabShortcutTable`.
3. Страница в app.
4. Документация.
5. Проверки и PR.

## Risks / Trade-offs

- **Регресс привязок одобрения при переводе на каталог** (безопасность, приоритет 1). Клавиши одобрения отвечают на `session/request_permission`. Ошибка в каталоге могла бы выбрать не тот вариант. Митигация:
  - прежние тесты одобрения не меняют сценариев;
  - сторож 2 нажимает все четыре сочетания и проверяет `optionId` по виду;
  - сценарий «Отправка и одобрение на одной клавише» проверяет, что Cmd/Ctrl+Enter в композере не отвечает на одобрение.
- **Цепочка Esc.** Порядок «сессия в корне → палитра → отмена хода» и Esc композера сохраняются. Каталог меняет только источник активатора, не обработчик. Прежние тесты Esc (spec app-settings «Esc на рабочем месте», «Esc в настройках во время хода») остаются зелёными.
- **Сторож литералов ложно срабатывает** на `LogicalKeyboardKey` в тестах и превью. Он читает только `lib/`, превью кита в `lib/src/*_previews.dart` привязок не объявляют. Если объявят — через каталог.
- **Поздние события, гонки, подписки**: нет. Страница синхронна, без подписок и IO. Смена языка — обычная пересборка.
- **Платформа в тестах**: `debugDefaultTargetPlatformOverride` нужно сбрасывать в `tearDown`, иначе соседние тесты получат чужую платформу. Это шаблон Flutter, тесты задач 1.1 и 3.3 сбрасывают его явно.
- **Web-безопасность**: `codelab_ui` — Flutter-пакет, `web-compile` его не касается. Dart-пакеты не меняются.

## Migration Plan

Данных и формата хранения нет. Откат — удаление страницы из `defaultSettingsPages`; привязки на каталоге работают так же, как до change.

## Решения пользователя 2026-11-19

- **Q1 — обозначения на macOS.** Показываются символы `⌘` `⌥` `⇧` `⏎` `⌫`, как в подсказках на рабочем месте. Подписи холста «on macOS Ctrl reads Cmd» нет (D4).
- **Q2 — неподключённые параметры.** `onApprove`, `onReject`, `onInspectorPrevious` и `onInspectorNext` удаляются из `CodeLabWorkbenchShortcuts`. Alt+←/→ остаётся в резерве DSK-18 за навигацией инспектора и на страницу не попадает (D3).
- **Q3 — состав.** На странице 19 строк, вместе с навигацией дерева Files (↑/↓, →/←, Enter) и меню команд после `/` (↑/↓, Enter, Esc) (D1).
- **Q4 — порядок модификаторов.** Единый порядок `Ctrl`, `Alt`, `Shift` на Windows и Linux: подсказка «Allow always» и «Reject always» становится `Ctrl+Alt+⏎` и `Ctrl+Alt+⌫` вместо `Alt+Ctrl+…` (D4). Привязки не меняются.

## Open Questions

- **Q5.** Закрыт 2026-11-19: пользователь принял русские тексты страницы без правок (задача 3.6). Вычитывались термины D5: «Сочетания клавиш», «Поле ввода» для группы Composer, «Дерево файлов», «Меню команд после /».
