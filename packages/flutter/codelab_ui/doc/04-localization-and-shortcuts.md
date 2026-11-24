# Локализация и сочетания клавиш

Глава про две вещи, которые кит держит у себя и которые нельзя менять наугад: каталог текстов на английском и русском и каталог клавиатурных сочетаний. Первая часть — как устроен каталог текстов и как его подключает приложение. Вторая — как устроен `CodeLabShortcut`, чем клавиши различаются по платформам и раскладкам и какие сторожа следят за каталогом.

## Каталог текстов

### Что в нём лежит

Каталог кита — внутренняя деталь `lib/src/l10n/`:

| Файл | Что это |
|---|---|
| `codelab_ui_en.arb` | шаблон: английские тексты и описания для переводчика |
| `codelab_ui_ru.arb` | русский перевод |
| `codelab_localizations.dart` | сгенерированный класс `CodeLabLocalizations`: делегат, список языков, абстрактные геттеры сообщений |
| `codelab_localizations_en.dart`, `codelab_localizations_ru.dart` | сгенерированные реализации языков |
| `strings.dart` | `codeLabStringsOf(context)` — единственная точка, через которую виджеты берут текст |

В каждом из двух ARB сейчас по 157 сообщений. Настройка генерации — `l10n.yaml` в корне пакета:

| Ключ | Значение | Зачем |
|---|---|---|
| `arb-dir` | `lib/src/l10n` | ARB лежат рядом с кодом |
| `template-arb-file` | `codelab_ui_en.arb` | шаблон — английский |
| `output-localization-file` | `codelab_localizations.dart` | имя сгенерированного файла |
| `output-class` | `CodeLabLocalizations` | имя класса |
| `nullable-getter` | `true` | `CodeLabLocalizations.of(context)` может вернуть `null` — основа фолбэка |
| `required-resource-attributes` | `true` | у каждого сообщения должен быть блок `@ключ` |
| `untranslated-messages-file` | `build/l10n_untranslated.json` | отчёт о непереведённых сообщениях |

Сгенерированный код лежит в git: так `dart analyze` работает без шага генерации. Устаревший код ловит `melos run l10n:check` — скрипт `tool/l10n_check.dart` генерирует каталог во временный каталог и сравнивает с рабочими файлами. Рабочее дерево он не меняет, код выхода 1 означает расхождение. Реальный запуск `fvm dart run tool/l10n_check.dart --package packages/flutter/codelab_ui` из корня на этой ветке завершился кодом 0 и ничего не вывел.

### Фолбэк на английский

Кит живёт и без делегата: в тестовом `FluentApp`, в превью, в любом хосте без локализации. Поэтому `codeLabStringsOf` устроен так:

```dart
CodeLabLocalizations codeLabStringsOf(BuildContext context) =>
    CodeLabLocalizations.of(context) ?? CodeLabLocalizationsEn();
```

Без делегата в дереве виджет показывает английский и не падает. Вызов зависит от `Localizations`, поэтому смена языка пересобирает виджет без собственных подписок. Кит не читает `AppLocalizations` приложения: каталоги независимы.

### Как приложение подключает делегат

Хост добавляет `CodeLabLocalizations.delegate` в `localizationsDelegates` своего `FluentApp`. Так сделано в `apps/codelab_desktop/lib/app/codelab_app_widget.dart`:

```dart
localizationsDelegates: const [
  ...AppLocalizations.localizationsDelegates,
  CodeLabLocalizations.delegate,
],
supportedLocales: AppLocalizations.supportedLocales,
```

Язык интерфейса приложение меняет через `locale` у `FluentApp`; делегат кита подхватывает его сам. Как приложение хранит и выбирает язык, описано в главе о [локализации приложения](../../../../apps/codelab_desktop/doc/05-localization.md).

В тесте русский язык и делегат кита подключаются так (из `test/codelab_l10n_test.dart`):

```dart
FluentApp(
  locale: const Locale('ru'),
  localizationsDelegates: CodeLabLocalizations.localizationsDelegates,
  supportedLocales: CodeLabLocalizations.supportedLocales,
  home: child,
)
```

### Правила для текстов в коде

- Все пользовательские литералы в `lib/src/**` идут через каталог: подписи, подсказки, `Semantics.label`, `semanticLabel`. Не переводятся клавиши и сочетания, идентификаторы, `ValueKey`, тексты `assert` и строки данных от приложения и агента.
- Ключ сообщения — `codeLab<Область><Смысл>`. Области сейчас: `Action`, `Agents`, `App`, `Approval`, `Banner`, `Call`, `Composer`, `Connection`, `Dock`, `File`, `Layout`, `Markdown`, `Palette`, `Pane`, `Plan`, `Protocol`, `Queue`, `Risk`, `Session`, `Settings`, `Setup`, `Shortcut`, `Sidebar`, `Status`, `Terminal`, `Thought`, `Transcript`, `Turn`, `Usage`. Новую область заводят, если ни одна не подходит.
- У каждого сообщения `en` есть `@ключ.description` — по-русски: где сообщение показывается и что значат плейсхолдеры. У `ru` описаний нет.
- Количество — только ICU `plural`. В `ru` обязательны формы `one`, `few`, `many`, `other`; склейка «число + слово» запрещена. В `en` достаточно `other`:

  ```json
  "codeLabCallMoreToolCalls": "{count, plural, other{+{count} more tool calls}}"
  ```

  ```json
  "codeLabCallMoreToolCalls": "{count, plural, one{ещё {count} вызов инструмента} few{ещё {count} вызова инструмента} many{ещё {count} вызовов инструментов} other{ещё {count} вызова инструмента}}"
  ```

  Вызов в коде получает число: `codeLabStringsOf(context).codeLabCallMoreToolCalls(subagent.tailMore)`.
- Сообщения, у которых описание содержит пометку `Метка security (D14)` (сейчас 19), относятся к одобрению (кнопки, охват, подписи тонов), рискам и предупреждениям просмотра файлов (секрет, ссылка наружу проекта). Перевод не должен смягчать смысл; такие сообщения вычитывает пользователь.
- Русские формулировки — по [глоссарию](../../../../docs/architecture/l10n-glossary.md).
- Параметры с текстом по умолчанию — `placeholder`, `emptyLabel`, `reconnectLabel`, `actionsLabel` — имеют тип `String?`. `null` — текст кита из каталога; явная строка показывается как есть, без перевода.
- Название панели дока — `toolPaneTitleOf(context, pane)`, поля `label` у `ToolPane` нет. Подпись риска — `CodeLabApprovalRisk.labelOf(context)`.
- `CodeLabApprovalRisk.label` и `CodeLabApprovalPrompt.noSuchOption` остались английскими эталонами для тестов и спецификаций. Это отдельные литералы, а не чтение каталога, иначе сверка была бы тавтологией: совпадение с `en` проверяет `test/codelab_l10n_en_reference_test.dart`.
- `CodeLabCommandAction.defaults` — данные, а не виджет. Их английские подписи — эталон для превью и тестов, приложение подменяет их своими.

### Сторожа текстов

| Сторож | Где | Что проверяет |
|---|---|---|
| `test/l10n_catalogs_test.dart` | пакет | каталог не пуст (не меньше 100 сообщений); наборы ключей `en` и `ru` равны; плейсхолдеры каждого сообщения совпадают; у plural в `ru` есть все четыре формы; у каждого сообщения `en` есть описание; значения `ru` не пусты |
| `test/codelab_l10n_test.dart` | пакет | каждый фиксированный словарь кита (статусы вызовов, сессий, соединения, риски, исходы одобрения, приоритеты плана, `ToolPane`) показывает русский текст с делегатом и английский без него; параметры по умолчанию дают перевод, явные строки остаются как есть |
| `test/codelab_l10n_en_reference_test.dart` | пакет | английские эталоны `label` и `noSuchOption` совпадают с каталогом |
| `melos run l10n:check` | корень | сгенерированный код не отстал от ARB |
| `ui_literals_test.dart` | `packages/dart/codelab_architecture_tests` | в `packages/flutter/codelab_ui/lib/src` нет английских литералов интерфейса мимо каталога |

`ui_literals_test.dart` — эвристика по регулярным выражениям, а не разбор AST. Он ищет строку, начинающуюся с буквы, в позициях `Text('…')`, `CodeLabText('…')` и именованных параметрах `label`, `tooltip`, `placeholder`, `title`, `message`, `content`, `description`. Исключения записаны в `ui_literals_allowlist.txt` рядом с сторожем, каждое с причиной; для кита там только подписи встроенных команд `CodeLabCommandAction.defaults`. Мёртвая запись allowlist — тоже ошибка. Подробнее — в [README сторожа](../../../../packages/dart/codelab_architecture_tests/README.md).

Рецепт «добавить строку» — в главе [06](06-extending.md).

## Каталог сочетаний `CodeLabShortcut`

### Зачем он нужен

Раньше сочетания были объявлены литералами `SingleActivator` и сравнениями `LogicalKeyboardKey` в девяти файлах, а подписи (`⌘K`, `Ctrl+⏎`) собирались отдельно и со своими проверками платформы. Страница «Keyboard», написанная третьим списком, разошлась бы с привязками при первом же новом сочетании.

Теперь единственный источник и активаторов, и обозначений клавиш по платформе — `lib/src/atomics/codelab_shortcuts.dart`. Тексты действий там не живут: каталог — словарь клавиш, а не политика; что сочетание делает и как называется, решает вызывающий.

### Устройство

- **`CodeLabKeyCombo`** — одна комбинация. Поля: `key` и `alsoKeys` (дополнительные клавиши с тем же действием, например numpad Enter), `primary`, `alt`, `shift`, `meta`.
  - `primary` — «основной модификатор»: привязывается и к Ctrl, и к ⌘ на любой платформе (по паре активаторов `control` и `meta`).
  - `meta` — точный ⌘ без Ctrl; задаётся вместо `primary`, вместе с ним не указывается.
  - `alt` и `shift` сверяются точно, как у `SingleActivator`: Cmd/Ctrl+Enter и Cmd/Ctrl+Alt+Enter — разные сочетания.
- **`CodeLabShortcut`** — перечисление записей. Запись состоит из группы `CodeLabShortcutGroup` (`global`, `navigation`, `transcript`, `composer`, `approvals`) и комбинаций. У записей с клавишами по платформе общие `combos` пусты, а действуют `macCombos` и `otherCombos`.
- **`CodeLabModifierHoldTracker`** — отсчёт времени, сколько Alt и Shift зажаты вместе. Нужен для ответа на одобрение на Windows и Linux (см. [главу о ключевых виджетах](03-key-widgets.md)).

Основные методы записи и комбинации:

| Метод | Что делает |
|---|---|
| `combosFor(TargetPlatform)` | комбинации записи на платформе: `macCombos` на macOS, `otherCombos` на остальных, иначе общие `combos` |
| `bind(action, {includeRepeats})` | карта `ShortcutActivator → VoidCallback` для `CallbackShortcuts` на `defaultTargetPlatform`; `includeRepeats: false` отключает автоповтор |
| `combo.activators`, `activatorsWith(...)` | активаторы одной комбинации, когда у альтернатив разные действия |
| `combo.accepts(KeyEvent, HardwareKeyboard)` | подходит ли нажатие комбинации; используется там, где событие читается вручную (дерево Files) |
| `capsFor`, `compactFor`, `spokenFor` | обозначения: кейкапы страницы, короткая подсказка кнопки (`⌘K`, `Ctrl+K`), подпись словами для чтения с экрана (`Option+Cmd+Enter`) |
| `searchNotations()` | нотации для поиска на странице «Keyboard» |
| `id` | kebab-case имя записи для строк страницы и ключей тестов (`command-palette`, `file-tree-open`) |

Платформу выбирает только каталог (`defaultTargetPlatform`). Проверки `Platform.isMacOS` в feature-коде запрещены (корневой `AGENTS.md`, §11).

### Записи

В каталоге 24 записи. Основной модификатор записан как Cmd/Ctrl.

| Группа | Запись | Клавиши |
|---|---|---|
| `global` | `commandPalette` | Cmd/Ctrl+K |
| | `newSession` | Cmd/Ctrl+N |
| | `openFolder` | Cmd/Ctrl+O |
| | `openSettings` | Cmd/Ctrl+, |
| | `closeOverlay` | Esc |
| | `leaveSettings` | Esc |
| `navigation` | `toggleSidebar` | Cmd/Ctrl+B |
| | `toggleFiles` | Cmd/Ctrl+Shift+E |
| | `toggleProtocol` | Cmd/Ctrl+Shift+I |
| | `fileTreeMove` | ↑ и ↓ |
| | `fileTreeFold` | → и ← |
| | `fileTreeOpen` | Enter (и numpad Enter) |
| | `protocolFrameMove` | Alt+← и Alt+→ |
| | `protocolRecordMove` | Alt+↑ и Alt+↓ |
| `transcript` | `cancelTurn` | Esc |
| `composer` | `send` | Cmd/Ctrl+Enter |
| | `commandMenuMove` | ↑ и ↓ |
| | `commandMenuRun` | Enter |
| | `commandMenuClose` | Esc |
| `approvals` | `goToApproval` | Cmd/Ctrl+Shift+A |
| | `allowOnce` | macOS ⌘Y; остальные Alt+Shift+Y |
| | `allowAlways` | macOS ⌥⌘Y; остальные Alt+Shift+Q |
| | `rejectOnce` | macOS ⌥⌘Z; остальные Alt+Shift+X |
| | `rejectAlways` | macOS ⌥⇧⌘Z; остальные Alt+Shift+W |

Какие записи привязывает кит, а какие — приложение: `CodeLabWorkbenchShortcuts` привязывает `commandPalette`, `cancelTurn`, `newSession`, `openFolder`, `toggleSidebar`, `openSettings`, `toggleFiles`, `toggleProtocol`, `goToApproval` и четыре ответа на одобрение; `closeOverlay` привязывает `CodeLabWorkbenchLayout`; дерево Files (`CodeLabFileTree`) и композер (`CodeLabPromptComposer`, он же меню команд) читают свои записи сами. `leaveSettings`, `protocolFrameMove` и `protocolRecordMove` кит только описывает, а привязывает приложение (так записано в комментариях `test/codelab_shortcut_bindings_test.dart`). Колбэк, который хост не передал, означает «сочетание не привязано».

### Почему клавиши ответа разные по платформам

Общей комбинации у ответов на одобрение нет, и это сделано нарочно:

- на macOS — только ⌘, без Ctrl: Ctrl+Y в поле ввода — «yank» раскладки Cocoa и не должен отвечать на запрос;
- на Windows и Linux — только Alt+Shift: Ctrl+Z и Ctrl+Shift+Z правят текст, а Ctrl+Alt даёт AltGr.

Тест `test/codelab_shortcuts_test.dart` проверяет, что ⇧⌘Z и ⌘Z на macOS не привязаны ни к одной записи.

### Раскладки ввода

Каталог сверяет логическую клавишу события (`CodeLabKeyCombo.accepts`, `SingleActivator`):

- при нелатинской раскладке (например, русской) Flutter сам отдаёт латинскую логическую клавишу той же позиции;
- при латинских раскладках с другим порядком букв (AZERTY, QWERTZ, Dvorak) логическая клавиша — напечатанная буква: на AZERTY логическая `z` на физической W — это ⌥⌘Z, а логическая `w` на физической Z — нет.

Кириллическая логическая клавиша с ⌘ или без модификатора сочетанием не считается: тесты в группе «раскладка ввода» проверяют, что `л` на позиции K не открывает палитру, а `н` на позиции Y не отвечает на одобрение.

Своё сопоставление по физической клавише добавлять нельзя без проверки на настоящей клавиатуре: инструменты управления экраном при нелатинской раскладке шлют не ту физическую клавишу. Это правило записано в [`AGENTS.md`](../AGENTS.md) пакета.

### Сторожа каталога

1. `test/shortcut_catalog_guard_test.dart` читает все `lib/src/**/*.dart`, кроме файла каталога, и падает с именем файла и строкой на любом из паттернов: `SingleActivator(`, `CharacterActivator(`, `LogicalKeySet(`, `LogicalKeySet.fromSet(`, `isLogicalKeyPressed(`, сравнение `==` или `!=` с `LogicalKeyboardKey.`, `case LogicalKeyboardKey.`, `LogicalKeyboardKey.… =>`, `PhysicalKeyboardKey.`, а также чтение `.logicalKey` и `.physicalKey` события. Строки-комментарии не считаются.
2. `test/codelab_shortcut_bindings_test.dart` проверяет каждую запись нажатием. Внутри `_checkOf` — `switch` по `CodeLabShortcut` без `default`: новая запись без сценария не компилируется. Для записей с общими комбинациями сценарий нажимает комбинацию и в варианте Ctrl, и в варианте ⌘; для ответов на одобрение — каждую платформу своими клавишами, чужие клавиши и автоповтор колбэк не вызывают.
3. `test/codelab_shortcuts_test.dart` фиксирует состав: 24 записи по порядку и группам, kebab-case идентификаторы, активаторы, `capsFor`, `compactFor`, `spokenFor`, `searchNotations`, `accepts`.
4. Приложение: страница «Keyboard» (`apps/codelab_desktop/lib/features/settings/presentation/keyboard_page.dart`) перебирает `CodeLabShortcut.values` и в `switch` без `default` называет действие и место каждой записи. Новая запись каталога ломает сборку приложения, пока для неё нет текстов.

Рецепт «добавить сочетание» — в главе [06](06-extending.md).

## Смотрите также

- [Ключевые виджеты](03-key-widgets.md) — одобрение, `onAnswerApproval`, видимость полосы.
- [Тестирование](05-testing.md) — как устроены тесты каталогов.
- [Частые проблемы](07-troubleshooting.md) — текст не переводится, сочетание не срабатывает.
- [`docs/architecture/l10n-glossary.md`](../../../../docs/architecture/l10n-glossary.md) — глоссарий русских формулировок.
- Спецификация [`app-settings`](../../../../openspec/specs/app-settings/spec.md): требования «Сочетания app и страница «Keyboard» не расходятся» и сценарии «Тексты кита на русском», «Кит без делегата», «Каталоги согласованы».
