## Исполнители

- `[desktop]` — `apps/codelab_desktop`, `packages/flutter/codelab_ui`;
- `[protocol]`, `[agent]`, `[client]` — задач нет: ACP, Dart-пакеты и CLI не меняются (design.md, D12).

TDD (`packages/dart/codelab_agent_core/AGENTS.md` §2): красный тест — отдельная задача и отдельный коммит до кода. Коммит — только по просьбе пользователя. Задача реализации ссылается на свой красный тест. Красный тест может опираться на заглушки сигнатур без поведения: пустой каталог, страница без строк.

Проверки каждой задачи — только для затронутого (`AGENTS.md` §21):
- `fvm dart format` изменённых файлов;
- `fvm flutter analyze` пакета;
- тесты пакета;
- `l10n:check` — при правке ARB.

`guard` не нужен: `pubspec.yaml`, импорты между пакетами и `rules.dart` не меняются (D12). `web-compile` не нужен: web-безопасные Dart-пакеты не меняются. Интеграционные тесты app в `feature/*` только компилируются.

## 0. Документы (выполнено при подготовке change)

- [x] 0.1 `[desktop]` `12-4-first-run-and-settings.md` §12.4.9: строка «Keyboard (27)» (только привязки сборки, каталог `CodeLabShortcut`, видна всегда — D1, D2, D7); пояснение к SETUP-17 для страниц, содержимое которых задаёт сборка (D7).
- [x] 0.2 `[desktop]` `12-3-desktop-display.md`: A13, шаг 3 — сочетание входит в сборку с действием, все активаторы — из каталога (D2, D3); DSK-18 — Alt+←/→ зарезервированы, но не привязаны (D3).
- [x] 0.3 `[desktop]` `docs/architecture/platform-integration.md` §5 — обозначения клавиш выбирает только каталог кита по `defaultTargetPlatform` (D4). `delivery-roadmap.md`, строка 27 — ссылка на change.
- [x] 0.4 Документы change `add-integrated-terminal`: задача 3.4 дополнена записями каталога, текстами ARB и строками страницы для Ctrl+\` и Ctrl+Shift+\` (D13).

## 1. Итерация 1 — каталог сочетаний и привязки из него

Видимых изменений нет, кроме порядка модификаторов подсказки на Windows и Linux (D4; решение пользователя Q4, 2026-11-19).

- [x] 1.1 `[desktop]` Красный: `packages/flutter/codelab_ui/test/codelab_shortcuts_test.dart` (D2, D4; spec app-settings «Страница «Keyboard»: обозначения клавиш»). Платформа задаётся через `debugDefaultTargetPlatformOverride`, сброс в `tearDown`. Проверяет:
  - записи `CodeLabShortcut.values` по порядку и группам совпадают с таблицей D1, `id` — kebab-case из спецификации;
  - у комбинации с основным модификатором два активатора, `control` и `meta`, с теми же `alt` и `shift`; у остальных — один (у `file-tree-open` ещё numpad Enter);
  - `capsFor`: macOS — `⇧ ⌘ E`, `⌥ ⌘ ⏎`, `⌘ ⌫`, `Esc`, `↑`; Windows и Linux — `Ctrl Shift E`, `Ctrl Alt Enter`, `Ctrl Backspace`;
  - `compactFor`: `⌘K`, `Ctrl+K`, `⌘N`, `Ctrl+N`, `⌘⏎`, `⌥⌘⏎`, `⌘⌫`, `⌥⌘⌫`, `Ctrl+⏎`, `Ctrl+Alt+⏎`, `Ctrl+⌫`, `Ctrl+Alt+⌫`;
  - `spokenFor`: `Option+Cmd+Enter`, `Ctrl+Alt+Enter`, `Shift+Cmd+E`, `Up`;
  - `searchNotations` содержит все три нотации независимо от платформы;
  - `accepts` принимает `KeyDownEvent` своей клавиши с нужными модификаторами и отклоняет чужие.
- [x] 1.2 `[desktop]` Красный: `packages/flutter/codelab_ui/test/codelab_shortcut_bindings_test.dart` — сторож 2 для записей кита (D3; spec «Сочетания app и страница «Keyboard» не расходятся», сценарий «Каждая строка проверена нажатием»). `switch` без `default` по `CodeLabShortcut.values` возвращает сценарий. Записи app (`leave-settings`, Esc диалогов) возвращают «проверяется в app», задача 1.5. Сценарии:
  - оболочка `CodeLabWorkbenchShortcuts`: палитра, новая сессия, настройки, сайдбар, Files, Esc;
  - композер: отправка; при открытой inline-палитре ↑/↓, Enter, Esc; при `canCancel` Esc отменяет ход;
  - `CodeLabApprovalOptionGroup` и `CodeLabApprovalPrompt`: четыре варианта по `kind` с подписями не на английском;
  - `CodeLabFileTree`: ↑/↓, →/← на папке, Enter и numpad Enter;
  - выдвижная панель `CodeLabWorkbenchLayout`: Esc.

  Каждый активатор с основным модификатором нажимается в варианте `control` и в варианте `meta`.
- [x] 1.3 `[desktop]` Красный: `packages/flutter/codelab_ui/test/shortcut_catalog_guard_test.dart` — сторож 1 (D3; сценарий «Привязка вне списка»). Читает `lib/src/**.dart` и падает с именем файла и строкой на `SingleActivator(`, `CharacterActivator(`, `LogicalKeySet(` или сравнении с `LogicalKeyboardKey.` вне `atomics/codelab_shortcuts.dart`. До 1.4 красный на пяти файлах кита.
- [x] 1.4 `[desktop]` Реализация 1.1–1.3 (D2–D4):
  - `atomics/codelab_shortcuts.dart`: `CodeLabShortcutGroup`, `CodeLabKeyCombo`, `CodeLabShortcut`; экспорт через `atomics.dart`;
  - привязки из каталога в `codelab_workbench_shortcuts.dart`, `codelab_prompt_composer.dart`, `codelab_approval_option_group.dart` (`CodeLabApprovalShortcuts.bindings` и `labelFor` через каталог, без своей проверки платформы), `codelab_file_tree.dart` (`accepts` вместо сравнения `logicalKey`), `codelab_workbench_layout.dart`;
  - удалить `onApprove`, `onReject`, `onInspectorPrevious`, `onInspectorNext` из `CodeLabWorkbenchShortcuts` и обновить `codelab_organisms_test.dart` (решение пользователя Q2);
  - doc-комментарии по `AGENTS.md` §15.

  1.1–1.3 зелёные. Прежние тесты кита (`codelab_molecules_test.dart`, `codelab_organisms_test.dart`, `codelab_file_tree_test.dart`) зелёные без изменения сценариев; меняются только ожидания `Alt+Ctrl+⏎` → `Ctrl+Alt+⏎` (решение пользователя Q4).
- [x] 1.5 `[desktop]` Красный, app:
  - `apps/codelab_desktop/test/app/shortcut_catalog_guard_test.dart` — сторож 1 для `lib/**.dart`, кроме сгенерированного `lib/l10n/app_localizations*.dart`; красный на `settings_shell.dart`, `add_profile_dialog.dart`, `provider_wizard_dialog.dart`, `agents_modes_page.dart`;
  - `apps/codelab_desktop/test/features/settings/presentation/keyboard_bindings_test.dart` — сторож 2 для записей app:
    - `leave-settings` во время хода возвращает на рабочее место без `session/cancel`;
    - `close-overlay` закрывает «Add connection profile», мастер провайдера, подтверждение `bypass` и палитру рабочего места;
  - сценарий «Отправка и одобрение на одной клавише» в дереве `CodeLabApp`: фокус на одобрении — `allow_once`; фокус в композере — сообщение в очереди, одобрение ждёт;
  - подсказки шапки и сайдбара на macOS и Linux — `⌘K`/`Ctrl+K`, `⌘N`/`Ctrl+N` из каталога.
- [x] 1.6 `[desktop]` Реализация 1.5: Esc в `settings_shell.dart`, `add_profile_dialog.dart`, `provider_wizard_dialog.dart`, `agents_modes_page.dart` — `CodeLabShortcut.leaveSettings` и `CodeLabShortcut.closeOverlay`; подсказки `workbench_shell.dart` — `compactFor(defaultTargetPlatform)` каталога без своей проверки платформы. 1.5 зелёный; `settings_shell_test.dart`, `workbench_shell_test.dart`, `settings_pending_approval_test.dart` и тесты диалогов зелёные без изменения сценариев.

## 2. Итерация 2 — виджеты кита

- [x] 2.1 `[desktop]` Красный: `packages/flutter/codelab_ui/test/codelab_shortcut_table_test.dart` (D6, D9; spec «…обозначения клавиш», «…язык, доступность и узкое окно»):
  - `CodeLabKeycaps`: по кейкапу на клавишу, роль `mono`, одна подпись `Semantics` словами (`Option+Cmd+Enter`), альтернативы — `Up or Down` по `codeLabShortcutAlternatives` (подпись словами, D4), на `ru` с делегатом — перевод `or`;
  - `CodeLabShortcutTable`: шапка из переданных подписей, группы с заголовком `header: true`, ключи групп и строк от вызывающего, строки не фокусируются (Tab их не обходит);
  - ширина 400 px: горизонтальная прокрутка без переполнения, кейкапы не переносятся, текст действия переносится.
- [x] 2.2 `[desktop]` Реализация 2.1: `atomics/codelab_keycaps.dart`, `organisms/codelab_shortcut_table.dart`, экспорт из барелей, сообщение `codeLabShortcutAlternatives` в `codelab_ui_en.arb` и `codelab_ui_ru.arb`, примеры в `codelab_molecule_previews.dart`/`codelab_organism_previews.dart` (один экран — на `ru`), `codelab_previews_test.dart`. 2.1 зелёный, `l10n:check` зелёный.

## 3. Итерация 3 — страница «Keyboard»

- [ ] 3.1 `[desktop]` Красный: `apps/codelab_desktop/test/features/settings/application/keyboard_shortcut_search_test.dart` (D8; spec «…поиск»). Сценарии «Поиск по действию», «Поиск по клавише в чужой нотации», «Поиск по клавише словами», «Ничего не найдено». Плюс:
  - регистр и пробелы по краям;
  - пустой запрос — все записи;
  - `+` и пробелы в запросе;
  - поиск не идёт по «Where».
- [ ] 3.2 `[desktop]` Реализация 3.1: `features/settings/application/keyboard_shortcut_search.dart` (`KeyboardShortcutEntry`, `filterKeyboardShortcuts`). 3.1 зелёный.
- [ ] 3.3 `[desktop]` Красный: `apps/codelab_desktop/test/features/settings/presentation/keyboard_page_test.dart` (spec app-settings, все требования «Страница «Keyboard»: …»). Проверяет:
  - «Страница видна в рабочей сборке», «Узкое окно не скрывает страницу», «Поиск страницы по ключевому слову», «Последняя страница», «Страница ничего не меняет» (`InMemoryProfileStore` и подменённые `SharedPreferences` не изменились, транспорт не получил сообщений);
  - «Полный список на Linux»: 19 строк, порядок, группы и английские тексты символ в символ со спецификацией;
  - «Сочетаний без поведения нет», «Строка «Agent commands»»;
  - «macOS», «Windows»;
  - «Ничего не найдено»: скрытые группы, `settings-keyboard-empty`, footer на месте;
  - «Узкое окно» 600 px, «Обход с клавиатуры».
- [ ] 3.4 `[desktop]` Красный: `apps/codelab_desktop/test/features/settings/presentation/keyboard_page_l10n_test.dart`:
  - «Русский интерфейс»;
  - «Английский текст при русском интерфейсе», «Переведённый текст при русском интерфейсе»;
  - «Смена языка с запросом» (`expectNoStaleLanguage`);
  - поиск страницы по русскому ключевому слову `сочетание` при русском интерфейсе и его отсутствие при английском.
- [ ] 3.5 `[desktop]` Реализация 3.3 и 3.4 (D5–D7):
  - `features/settings/presentation/keyboard_page.dart` (`buildKeyboardPage`, `KeyboardPage`, сборка записей из каталога и ARB, `keyboardShortcutActionOf`, `keyboardShortcutWhereOf`, `keyboardShortcutGroupOf` — исчерпывающие `switch`);
  - `SettingsPage.keyboard` в `defaultSettingsPages` и `settingsPageBuilders`, комментарий `default_settings_pages.dart`;
  - `settingsSearchKeywordsKeyboard` в `settingsPageKeywordsOf`;
  - сообщения `settingsKeyboard…` в `app_en.arb` и `app_ru.arb`, у строк одобрения метка `security` в `@description`.

  3.3 и 3.4 зелёные, `settings_shell_test.dart` и `settings_search_l10n_test.dart` зелёные, `l10n:check` зелёный.
- [ ] 3.6 `[desktop]` Вычитка пользователем русских текстов страницы: термины D5 и строки одобрения с меткой `security` (D14 `add-desktop-localization`; Q5). Правки — в ARB и глоссарий одним PR.

## 4. Итерация 4 — документация (`docs-writer`, стандарт `.claude/skills/codelab-docs/SKILL.md`)

- [ ] 4.1 `[desktop]` `docs/architecture/l10n-glossary.md` — подраздел «Страница «Keyboard»» в §4 по таблице D5 с итогом вычитки 3.6 (правило §7 глоссария: термин — в том же PR, что и сообщение).
- [ ] 4.2 `[desktop]` `apps/codelab_desktop/doc/user-guide.md`:
  - раздел «Настройка» → «Сочетания клавиш»: где страница, что она только для чтения, поиск по действию и клавише, обозначения на macOS и других ОС;
  - сочетания в остальных разделах — в нотации страницы (`⇧⌘E` вместо `⌘⇧E`);
  - таблица сочетаний карточки одобрения сверена с каталогом;
  - на какие тексты распространяется русский язык интерфейса — дополнить страницей «Keyboard».
- [ ] 4.3 `[desktop]` `apps/codelab_desktop/AGENTS.md` — раздел «Страница «Keyboard»»:
  - каталог кита — единственный источник активаторов;
  - сторожа 1 и 2;
  - новое сочетание — запись каталога, тексты ARB и сценарий нажатия в одном change;
  - тексты по `switch`.

  `packages/flutter/codelab_ui/AGENTS.md` §4 — `CodeLabShortcut`, `CodeLabKeycaps`, `CodeLabShortcutTable`; правило «литералы активаторов только в каталоге». `packages/flutter/codelab_ui/README.md` — новые виджеты в таблице слоёв.
- [ ] 4.4 `[desktop]` Проверка фактов документов 4.1–4.3 (`architecture-reviewer`), исправления.

## 5. Проверки и PR

- [ ] 5.1 `[desktop]` Проверки затронутого (`AGENTS.md` §21):
  - `fvm dart format --set-exit-if-changed` изменённых файлов;
  - `fvm flutter analyze` в `packages/flutter/codelab_ui` и `apps/codelab_desktop`;
  - `fvm flutter test` обоих пакетов;
  - `melos run l10n:check`;
  - `fvm flutter analyze` для `apps/codelab_desktop/integration_test` (только компиляция, `feature/*`);
  - `openspec validate add-app-keyboard-page --strict`;
  - если правились опубликованные на сайте документы и установлен Node — `cd site && npm ci && npm run verify`.
- [ ] 5.2 `[desktop]` Ручная проверка app на macOS: кейкапы ⌘, поиск `⌘K` и `ctrl k`, русский интерфейс, окно 600 px. Каждая строка таблицы нажимается в своём месте.
- [ ] 5.3 `[desktop]` При архивации: если `add-app-skills-page` и `add-desktop-localization` уже в архиве, свести фразу «остальные страницы остаются скрытыми» требования «Страницы Providers и MCP servers в навигации» с перечнем видимых страниц, включая «General» и «Keyboard» (D7).
- [ ] 5.4 `[desktop]` PR в `develop`. В описании:
  - какие проверки запускались локально, и что полный `melos run check` не запускался;
  - смена подсказки `Ctrl+Alt+⏎` на Windows и Linux (решение пользователя Q4, 2026-11-19);
  - удалённые параметры `CodeLabWorkbenchShortcuts` (решение пользователя Q2, 2026-11-19).
