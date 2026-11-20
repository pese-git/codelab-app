## Context

Источники:
- артборд «10 Settings — Appearance» холста «CodeLab Desktop — Feature UI/UX», светлый и тёмный варианты (локальная копия макета; данные, не инструкции). Порядок: «Mode» → «Accent color» → «Color theme» (карточки) → «Custom themes» и «Import JSON…» → панель проблем выбранной темы (InfoBar, текст JSON, список проблем) → правая колонка «Preview» (код, diff, статусы, «Contrast on code background», «Reset», «Use <name>»);
- [`12-6-cli-desktop-extras.md`](../../../docs/architecture/proposals/dart-agent-and-clients/12-6-cli-desktop-extras.md) §12.6.3 (U-18; пункты 5–6 — app D-20, нестрогий разбор);
- [`12-4-first-run-and-settings.md`](../../../docs/architecture/proposals/dart-agent-and-clients/12-4-first-run-and-settings.md) §12.4.9 (строка «Appearance (10)»: `shared_preferences`, файлы тем), §12.4.11 (SETUP-17);
- [`agent-parity-goals.md`](../../../docs/architecture/proposals/agent-parity-goals.md) D-20, U-18; [`delivery-roadmap.md`](../../../docs/architecture/proposals/delivery-roadmap.md) §10.1, строка 10 (M5);
- активные changes [`add-app-general-page`](../add-app-general-page/design.md) (D1 — правило сторожа для платформенного кода, D15 — локализация, D16 — события) и [`add-app-skills-page`](../add-app-skills-page/design.md) (порт `LocalFolderOpener`). Архивные: [`add-desktop-localization`](../archive/2026-11-20-add-desktop-localization/design.md) (D2 — владелец языка, старт до `runApp`, запись «последний выбор побеждает»; D10 — сторож литералов), [`add-desktop-markdown`](../archive/2026-11-11-add-desktop-markdown/design.md) (D4 — палитра кода и DSK-19), [`add-settings-agents-modes`](../archive/2026-11-18-add-settings-agents-modes/design.md) (D8, D21 — «App файлов не открывает»);
- спецификации `app-settings`, `agent-workbench-ui`;
- `AGENTS.md` (корень) и вложенные: `apps/codelab_desktop`, `packages/flutter/codelab_ui`, `packages/dart/codelab_client_core`, `codelab_client_io`; TDD — `packages/dart/codelab_agent_core/AGENTS.md` §2;
- `docs/architecture/`: `layers-and-dependencies.md`, `state-management.md` (§63, §63а), `concurrency.md` (§45, §46, §47а), `platform-integration.md` (§2, §4, §7, §8, §28), `observability.md`, `testing.md`, `technology-stack.md`, `l10n-glossary.md`.

Что есть в коде (сверено 2026-11-20 на ветке `feature/add-app-appearance-page` от `develop` f63972a3):
- `CodeLabApp` строит `FluentApp` без `theme`, `darkTheme` и `themeMode`, поэтому app всегда светлый. Тёмного режима нет, хотя у артбордов есть тёмные варианты.
- `SettingsPage.appearance` объявлен (slug `appearance`), но не входит в `defaultSettingsPages`. Построителя страницы нет.
- `CodeLabCodeTheme` (`codelab_ui/lib/src/rendering/codelab_code_theme.dart`) — `ThemeExtension`. Палитра выводится из ролей Fluent и подгоняется под контраст 4,7:1. Приложение может положить свою палитру в `FluentThemeData.extensions`, и она победит. Классы токенов `CodeLabTokenClass`: `keyword`, `string`, `comment`, `number`, `type`, `function`, `variable`, `operator`, `attribute`.
- Тоны кита зашиты: `codelab_icon.dart` и `codelab_badge.dart` — `Colors.blue`, `Colors.green`, `Colors.warningPrimaryColor`, `Colors.red`; `codelab_usage_pane.dart` — `Colors.red`, `Colors.orange`; ссылки markdown — акцент темы. Отрисовки diff в ките нет (D-07 не реализован).
- `CodeLabFilePreview` показывает текст с номерами строк и выделяет одну строку (`highlightLine`).
- В CLI нет `lib/src/theme/`, в `codelab_client_core` и `codelab_client_io` разбора тем нет: U-18 не начат.
- Хранение настроек app — порты `core/platform/` на `shared_preferences` (`AppLanguagePreferences`, `ConnectionPreferences`, `StartupPreferences`). Выбор файла — `file_selector` (`ProjectFolderPicker`, `UsageCsvSaver`). Каталог открывает `LocalFolderOpener`. Пакета системного акцента в стеке нет; нативный канал в app только отладочный (`codelab/e2e_window`).
- Каталог `windows/` app содержит только `CMakeLists.txt` и `flutter/`, своего раннера нет. Linux и macOS собираются.
- `fluent_ui` 4.16.1: `FluentApp(theme, darkTheme, themeMode)`, при `ThemeMode.system` тема выбирается по `MediaQuery.platformBrightnessOf`. Конструкторы `ResourceDictionary.light/dark` принимают отдельные цвета именованными параметрами. `Color.toAccentColor()` строит `AccentColor` из одного цвета.

## Goals / Non-Goals

**Goals:**
- тёмный режим и «Match system» для всего app;
- встроенные темы `light`, `dark`, `high-contrast` и пользовательские из JSON с ролями CLI и палитрой кода;
- один формат файла и один разбор для app и будущих тем CLI;
- предупреждения разбора с позицией и подсказкой, видимые там, где тема выбирается;
- проверка контраста с понятным вердиктом; встроенные темы всегда проходят;
- системный акцент там, где платформа его отдаёт.

**Non-Goals:** темы CLI (U-18), отслеживание файлов на диске, роль фона окна, системный высокий контраст ОС, редактор тем, открытие файла внешним приложением, изменения ACP.

## Decisions

### D1. Пакеты, слои и сторож

| Пакет (ADR-0002) | Что меняется | Исполнитель |
|---|---|---|
| `codelab_client_core` | `lib/src/themes/`: `theme_role.dart` (`ThemeRole`, JSON-имена), `theme_color.dart` (`ThemeColorValue`: `Rgb`, `DefaultColor`, `AnsiColor`, `IndexedColor`), `json_spans.dart` (позиции ключей и значений, D3), `theme_file.dart` (`ThemeFile.parse` → `ThemeParseResult`; публичная `isValidThemeName` — шаблон `[a-z0-9-]{1,32}`, общий для разбора, каталога и импорта), `theme_issue.dart` (`ThemeIssueCode`, `ThemeIssue`), `theme_library.dart` — порт `ThemeLibrary`: `list()` (записи каталога по алфавиту), `read(name)` (одна тема; `null` — файла нет или имя не проходит `isValidThemeName`, тогда файловая система не трогается; ошибка чтения — запись `ThemeEntry.failed` с `ThemeReadError`, как в `list`), `import(sourcePath, {replace})`; `ThemeEntry`, `ThemeImportResult`, `InMemoryThemeLibrary`; экспорт из бареля | `[client]` |
| `codelab_client_io` | `lib/src/themes/io_theme_library.dart` (`IoThemeLibrary`), экспорт; запись через `stores/json_file.dart` | `[client]` |
| `packages/flutter/codelab_ui` | `atomics/codelab_palette.dart` (`CodeLabPalette` — `ThemeExtension`), тоны `codelab_icon`, `codelab_badge`, `codelab_usage_pane` и цвет ссылок `codelab_markdown_config` — через палитру; `CodeLabFilePreview.warningLines`; превью и widget-тесты | `[desktop]` |
| `apps/codelab_desktop` | `lib/app/appearance/` (`app_appearance_cubit.dart`, `app_appearance_start.dart`, `built_in_themes.dart`, `fluent_theme_builder.dart`), `core/platform/` (`app_appearance_preferences.dart`, `system_accent_source.dart`, `theme_file_picker.dart`), `features/settings/application/` (`appearance_settings_cubit.dart`, `appearance_settings_state.dart`, `contrast_checks.dart`, `theme_issue_texts.dart`), `features/settings/presentation/appearance_page.dart`, `lib/app/app_scope.dart`, `default_settings_pages.dart`, `codelab_app_widget.dart`, `main.dart`, `app_exit_handler.dart`, `pubspec.yaml` (`system_theme: 3.3.0`), ARB | `[desktop]` |
| `codelab_architecture_tests` | правила `file_selector` и `system_theme` (ниже) | `[desktop]` |

Направление зависимостей не меняется: `apps/codelab_desktop` → `codelab_client_core`, `codelab_client_io`, `codelab_ui`; `codelab_client_io` → `codelab_client_core`. Новых пакетов workspace и рёбер нет, граф в `README.md` не меняется. Новая сторонняя зависимость одна — `system_theme` у app (D7, `technology-stack.md` §20з). `clientCoreAllowlist`, `clientIoAllowlist` и allowlist ядра (PKG-2) не меняются. `desktopAllowlist` сверяет только пакеты `codelab_*`, поэтому его менять не нужно. `codelab_ui` по-прежнему не зависит от внутренних пакетов: роли ядра клиента app переводит в `CodeLabPalette` и `CodeLabCodeTheme` сам.

Слои app:
- `lib/app/appearance/` — владелец применённого оформления (как `lib/app/language/`). Он нужен `CodeLabApp` над `FluentApp`, а не одной feature;
- `features/settings/application/` — Cubit страницы, проверка контраста, коды проблем → данные для текста;
- `features/settings/presentation/` — виджеты страницы. Они не импортируют `dart:io`, `file_selector`, `codelab_client_io` (правила уже в `rules.dart` и в AGENTS.md пакета: `codelab_client_io` импортирует только composition root);
- `core/platform/` — порты `shared_preferences`, системного акцента (адаптер на `system_theme`) и выбора файла.

**Новых правил сторожа два**, оба по образцу `url_launcher` (правило `add-app-skills-page`, D8):
- `package:file_selector/` в `apps/codelab_desktop/lib` — только в `core/platform/`. Сейчас это договорённость: `ProjectFolderPicker` и `UsageCsvSaver` уже лежат там. Третий порт выбора файла делает её хрупкой;
- `package:system_theme/` в `apps/codelab_desktop/lib` — только в `core/platform/system_accent_source.dart`. API плагина (статические поля, неотменяемая подписка, D7) не должен расползтись по feature-коду. Отдельное правило «разбор тем без `dart:io`» не нужно: `codelab_client_core` уже под `webUnsafe`.

### D2. Формат общий с CLI, разбор — в `codelab_client_core`

§12.6.3 уже требует «тот же формат файла `~/.codelab/themes/<name>.json`» для app и CLI. Change закрепляет формат требованием capability `client-themes` и дополняет его двумя пунктами, которых в §12.6.3 нет:
- **`colors.code`** — вложенный объект палитры кода (D-20: «включая палитру подсветки кода»). Без него строгий CLI отверг бы любую тему app как содержащую неизвестный токен `code`. Поэтому `code` — часть закрытого набора и для CLI: CLI принимает его и пока не применяет (§12.6.3 обновляется, задача 0.1);
- **`extends` — только `light`, `dark`, `high-contrast`**. `auto` в базе не имеет смысла: это выбор темы, а не набор цветов. `mono` в app нечем изобразить. В §12.6.3 «встроенная тема» уточняется этим списком.

Разбор — одна чистая функция `ThemeFile.parse(fileName, text)` в `codelab_client_core`. Она возвращает тему с полным набором ролей (незаданные помечены), список проблем с кодами и позициями и список незаданных ролей. «Нестрогий» и «строгий» режимы — не флаг парсера, а правило потребителя. App применяет тему с предупреждениями. CLI (change `add-cli-themes`) будет считать любую проблему ошибкой (§12.6.3, шаг 3). Значения `ThemeColorValue` хранят вид (`#rrggbb`, ANSI, `256:n`, `default`). Rgb-значение для app и понижение глубины для CLI — забота потребителя.

Ядро клиента не строит текст проблемы (spec app-settings «Локализация интерфейса app»: ядро языконезависимо). Код, позиция и аргументы — данные, текст строит app по ARB, CLI — своими английскими строками.

Альтернативы:
- *разбор только в app* — отклонена. Через один change CLI получил бы второй разбор того же формата, и правила (имя, 64 КиБ, `extends`) разошлись бы;
- *в `codelab_ui`* — отклонена: CLI не может зависеть от Flutter, а кит не читает данные пользователя;
- *в `codelab_setup`* — отклонена: это мост агентской стороны, а темы — только клиент (D-20: «только клиент»);
- *отдельный пакет `codelab_client_themes`* — отклонена (§13): одна папка `src/themes/` в существующем web-безопасном пакете даёт ту же границу без нового узла графа.

Формат, общий с CLI, — решение пользователя 2026-11-20 (Q1 (а)).

### D3. Позиции ключей в JSON

Предупреждение требует `<file>:<line>:<col>`, а просмотр файла — номера строк для подсветки. `dart:convert` позиций ключей не даёт. Решение: небольшой читатель `json_spans.dart` в `codelab_client_core`. Он проходит текст один раз и строит дерево узлов JSON с позициями начала ключа и значения. Отдельно он находит повторы ключей, которые `jsonDecode` молча схлопывает. Корректность JSON сначала проверяет `jsonDecode`: позиция ошибки берётся из `FormatException.offset` и переводится в строку и колонку. Читатель запускается только на корректном тексте, поэтому разбирать все ошибки грамматики ему не нужно. Файл ограничен 64 КиБ, глубина вложенности — 32 (больше — `invalidJson`), поэтому рекурсия безопасна.

Альтернативы:
- *`package:yaml` (`loadYamlNode` даёт `span`)* — отклонена. Пришлось бы расширять `clientCoreAllowlist` web-безопасного пакета ради одной функции. Кроме того, у YAML своя семантика (повтор ключа — исключение, а не предупреждение; табы, комментарии);
- *сторонний парсер JSON с позициями* — отклонена: новая зависимость для задачи на сотню строк (AGENTS.md §4).

Тест читателя сверяет значения его дерева с `jsonDecode` на наборе файлов, включая escape-последовательности и суррогатные пары: колонка считается в code units UTF-16, как у `FormatException`.

### D4. Как роли применяются в app

Сборка `FluentThemeData` из темы — `fluent_theme_builder.dart` в `lib/app/appearance/`. База — `FluentThemeData(brightness)` режима темы. Поверх неё:

| Роль | Куда в app | Комментарий |
|---|---|---|
| `accent` | `FluentThemeData.accentColor` (`toAccentColor()`), тон `accent` кита | системный акцент, если включён (D7), заменяет роль |
| `text` | `ResourceDictionary.textFillColorPrimary`, `CodeLabCodeTheme.plain` | |
| `muted` | `ResourceDictionary.textFillColorSecondary` | |
| `success`, `warning`, `error` | тоны `success`, `warning`, `danger` (`CodeLabPalette`) и `systemFillColorSuccess`, `systemFillColorCaution`, `systemFillColorCritical` | |
| `info` | ссылки markdown и просмотра файла, статус `Link` превью | в Fluent-темах равна акценту: вид не меняется |
| `diff_add_bg`, `diff_remove_bg` | `CodeLabPalette`; потребители — превью страницы и будущий просмотр diff (D-07) | отрисовки diff в ките пока нет |
| `selection` | `FluentThemeData.selectionColor`, выделенная строка списков кита | |
| `approval_border` | не применяется | акцентную рамку блока одобрения убрал change [`lighten-approval-block`](../archive/2026-10-28-lighten-approval-block/design.md); роль разбирается, но в app её некуда применить (решение пользователя Q8) |
| `status_bg` | не применяется | роль TUI (§12.6.3) |
| `code.background`, `code.<класс>` | `CodeLabCodeTheme` в `extensions` | |

`CodeLabPalette` — новый `ThemeExtension` в `codelab_ui/atomics/` по образцу `CodeLabCodeTheme`: `CodeLabPalette.of(theme)` берёт зарегистрированное расширение или выводит палитру из Fluent с прежними значениями (`Colors.green`, `Colors.red`, `Colors.warningPrimaryColor`, `Colors.blue`). App регистрирует палитру всегда. Для `light` и `dark` без системного акцента её значения равны выведенным, и это проверяет тест (сценарий «Стандартная тема не меняет вид»).

Почему не роли целиком через `ResourceDictionary`: у Fluent нет ресурса «успех текста» и цветов diff. Кит уже обходит ресурсы зашитыми цветами. Одно расширение даёт киту одну точку правды и не требует от app знать устройство виджетов. Почему не `FluentThemeData.extensions` с картой ролей ядра клиента: кит не должен зависеть от `codelab_client_core` (AGENTS.md кита §1).

Значения ролей, которые не выражаются цветом (`terminalColor` в app, `default`), до сборки заменяются ролями базы (spec client-themes).

**Тоны встроенных тем и контраст** (итерация 4, задачи 4.3, 4.11). Прежние зашитые тона кита не все проходят порог D8: `Colors.red` на светлом фоне кода даёт 4,23:1, а `Colors.green`, `Colors.red` и `Colors.grey` нейтрального тега в тёмной теме нечитаемы. Поэтому «не меняет вид» сужено до того, что проверяемо:
- **светлая тема** — тоны `success`, `warning`, `accent` прежние; `danger` — тот же оттенок `Colors.red` (тон HSL ±3°), затемнённый шагами до ≥ 4,5:1 к фону страницы, карточки, кода и заливке тега (`CodeLabBadge`, альфа 56); нейтральный тег — прежний `Colors.grey`;
- **тёмная тема** — тоны `success`, `warning`, `danger`, `accent`, не заданные темой, подгоняются той же функцией к тем же четырём фонам; нейтральный тег — вторичный текст темы (`textFillColorSecondary`). Цвет тона виджеты берут через `CodeLabPalette.toneColor(tone, theme)`;
- роль, заданная пользовательской темой, не подгоняется (D8): подгонка касается только выведенных значений, в том числе ролей, которые пользовательская тема берёт из базы.

Без зарегистрированной палитры (кит в тестах и превью) `CodeLabPalette.of` по-прежнему отдаёт прежние цвета; app регистрирует палитру всегда.

### D5. Хранение выбора

`shared_preferences`, один ключ `codelab.app.appearance` с JSON-документом `version`, `mode`, `light_theme`, `dark_theme`, `system_accent`. Так требует `platform-integration.md` §28: данные одного concern — один документ, атомарная замена, место для версии формата. Порт `AppAppearancePreferences` (`core/platform/`) повторяет `AppLanguagePreferences`. `load()` не бросает и возвращает значения с диагностикой (`storedValueInvalid`, `readFailure`). Незнакомое значение не перезаписывается до явного выбора.

Не в `cli.yaml`: оформление app и тема CLI независимы (§12.6.3, пункт 5), а CLI свой файл только читает (§12.2.10). Не в `config.yaml`: это не настройка агента.

### D6. Встроенные темы

- `light`, `dark` — выведены из `FluentThemeData(brightness)`: роли — ресурсы Fluent и прежние цвета тонов, палитра кода — `CodeLabCodeTheme._derive` с подгонкой контраста. Для app значения не задаются таблицей: «стандартная тема Fluent своего режима» (§12.6.3, пункт 5).
- `high-contrast` — тёмная база с явной палитрой из артборда (собственный макет проекта, не сторонний источник):
  - `code.background` `#000000`;
  - `text` `#FFFFFF`, `code.comment` `#C8C8C8`;
  - `code.keyword` `#FF9DF5`, `code.string` `#7CFC8A`, `code.type` `#7FD4FF`, `code.number` `#FFC66B`;
  - `accent` и `info` `#7FD4FF`, `success` `#7CFC8A`, `warning` `#FFD75F`, `error` `#FF8080`;
  - `diff_add_bg` `#003D12`, `diff_remove_bg` `#4A0000`.

  Роли, которых в артборде нет (`code.function`, `code.variable`, `code.operator`, `code.attribute`, `muted`, `selection`), берутся из `dark` и проходят ту же подгонку контраста к `#000000`.
- Встроенные темы — кодом в `built_in_themes.dart`, а не JSON-ресурсами. Им не нужен разбор, а тест контраста (D8) проверяет их напрямую.

### D7. «Match system» и системный акцент

**«Match system».** Режим системы Flutter отдаёт на всех платформах (`MediaQuery.platformBrightnessOf`). `FluentApp` с `themeMode: ThemeMode.system`, `theme` и `darkTheme` сам переключает тему при смене режима системы. Нативного кода и порта не нужно: это API фреймворка, а не плагина (`platform-integration.md` §7). Подпись `Match system (dark)` страница читает из `MediaQuery` в presentation.

**Системный акцент.** Flutter его на десктопе не отдаёт (`dart:ui` `SystemColor` работает только в web). Решение пользователя (Q5 (б)) — пакет [`system_theme`](https://pub.dev/packages/system_theme) 3.3.0 (BSD-3-Clause, publisher `bdlukaa.dev`, автор `fluent_ui`) за узким портом (`platform-integration.md` §4, §8). Проверка зависимости по `technology-stack.md` §24–§25 — новый раздел §20з.

```dart
abstract interface class SystemAccentSource {
  bool get supported;                 // известно синхронно после старта: решает видимость строки
  Future<int?> read();                // ARGB или null, если акцент недоступен
  Stream<int?> get changes;           // смены акцента; на платформе без уведомлений — пустой поток
}
```

Что отдаёт пакет (сверено по исходникам 3.3.0):

| Платформа | Значение | Уведомление о смене | Строка «Accent color» |
|---|---|---|---|
| macOS | `NSColor.controlAccentColor` в sRGB | да (`NSSystemColorsDidChangeNotification`) | видна, смена — сразу |
| Windows | цвета акцента системы | да | видна, смена — сразу (раннера Windows в репозитории пока нет) |
| Linux | цвет GTK-темы `theme_selected_bg_color` | нет | видна (Q7 (а)); новый цвет — при следующем старте и при открытии «Appearance» |
| прочие, плагин не ответил | — | — | скрыта (SETUP-17) |

Адаптер `SystemThemeAccentSource` (`core/platform/system_accent_source.dart`, единственный импорт `package:system_theme/`, правило сторожа D1):
- **поддержка** — платформа из списка `supportsAccentColor` пакета **и** первое чтение при старте дало цвет. Чтение идёт в `main` до `runApp` с ограничением 1 с, как файлы тем, поэтому `supported` известно синхронно, и строка не появляется и не исчезает после первого кадра;
- **«нет акцента» отличается от цвета.** При отсутствии плагина `load()` молча оставляет запасной цвет. Адаптер создаёт один `SystemAccentColor` с маркером `Color(0x00000000)` и считает акцент недоступным, если после `load()` остался маркер. Запасной `#00b7c3` пакета в app не попадает;
- **ошибки не теряются.** Статический `SystemTheme.accentColor` грузится без `await`, его исключение потерялось бы (AGENTS.md §12), поэтому адаптер его не использует. Свой `load()` адаптер ждёт внутри `try`;
- **подписки.** `SystemAccentColor.load()` сам подписывается на `onChange` и не отписывается. Адаптер создаёт объект один раз за процесс, поэтому такая подписка одна. Поток для приложения — `SystemTheme.onChange`, отображённый в ARGB, на Linux — пустой поток (пакет выдал бы одно текущее значение). Владелец подписки приложения — `AppAppearanceCubit`; он отменяет её в `close()` (`concurrency.md` §47б);
- **Linux без уведомлений.** `AppearanceSettingsCubit` при открытии страницы зовёт `AppAppearanceCubit.refreshSystemAccent()`, а тот — `read()`. Больше опросов нет.

Включённый переключатель перекрывает `accent` любой темы, встроенной и пользовательской (решение пользователя Q4 (а)). Ошибка чтения или потока даёт `accent` темы и событие `appearance.system_accent_failed`. Переключатель по умолчанию выключен.

Альтернативы:
- *свой канал на каждой платформе* (прежняя рекомендация) — отклонена пользователем (Q5): нативный код в трёх раннерах против готового пакета автора `fluent_ui`;
- *убрать строку из этого change* — отклонена тем же решением.

### D8. Контраст

Отношение — WCAG 2: `(L1 + 0.05) / (L2 + 0.05)` по `Color.computeLuminance()` непрозрачных цветов. Считает чистая функция `contrast_checks.dart` в `features/settings/application/`. Она импортирует `dart:ui`, не виджеты, как `AppLanguageCubit`. Повторять формулу в `codelab_client_core` незачем: ядру контраст не нужен.

Проверяемые роли — то, что рисуется текстом на фоне кода: `text`, `info`, `error`, роли `code.*` без `background`. Блок превью показывает пять строк артборда, а бейдж карточки считает все проверяемые роли.

Встроенные темы проходят всегда: `light` и `dark` подгоняют палитру кода (`CodeLabCodeTheme._derive`), `info` и `error` встроенных тем проходят ту же подгонку, `high-contrast` подобрана с запасом. Тон `danger` (роль `error`) подгоняется и в светлой теме: прежний `Colors.red` давал 4,23:1 на фоне кода, поэтому он затемняется с сохранением оттенка (D4, «Тоны встроенных тем и контраст»); это единственный тон светлой темы, который отличается от прежнего. Тест перебирает встроенные темы с несколькими значениями системного акцента (тёмным, светлым, насыщенным).

Пользовательская роль применяется как задана, даже ниже порога: так решено в артборде («A role below that still applies, with a warning on its card»), и подменять явный выбор пользователя нельзя. Поэтому требование `agent-workbench-ui` «Блок кода в ответе агента» уточняется: порог 4,5:1 гарантируется для встроенных тем. Подсказка о контрасте видна там, где тема выбирается.

### D9. «Import JSON…»

Импорт копирует файл в каталог тем, а не ссылается на исходный путь:
- тема живёт там, где её найдут и app, и CLI (`~/.codelab/themes`);
- исходный файл в `Downloads` может исчезнуть, а выбор хранит только имя.

Порядок:
1. порт `ThemeFilePicker` (`file_selector`, тип `json`);
2. `ThemeLibrary.import(sourcePath)` — чтение до 64 КиБ + 1 байт и разбор без проверки имени исходного файла;
3. ошибка разбора — без записи;
4. путь назначения — только из проверенного `name`;
5. файл есть и отличается — результат `needsReplace`, страница спрашивает, затем `import(sourcePath, replace: true)`;
6. запись — `stores/json_file.dart` (временный файл, `flush`, `rename`).

Импортированная тема выбирается для превью и не применяется: применение — одно действие «Use», как у любой карточки. Повторный импорт того же содержимого — `unchanged`.

Байт в байт, а не пересериализация: пользователь должен узнать свой файл, а позиции предупреждений должны совпадать с его редактором.

### D10. Просмотр файла и экранирование

Текст файла показывает существующий `CodeLabFilePreview` с новым необязательным `warningLines: Set<int>` (тон `warning`). Новый виджет не нужен: номера строк, виртуализация и выделение уже есть (AGENTS.md кита §3: новый атом — при втором употреблении). Файл темы — недоверенный текст: перед показом он и значения в списке проблем проходят `escapeForDisplay`.

### D11. «Open file» → «Open folder»

App файлов не открывает: обработчиком `.json` в ОС может быть что угодно. Так решено для определений агентов (`add-settings-agents-modes`, D8, D21; `LocalFolderOpener` отклоняет не каталоги). Кнопка InfoBar называется «Open folder» и открывает `<home>/themes` через `LocalFolderOpener` с `create: true`. Это отступление от артборда (D14).

### D12. Наблюдаемость

Логгер `codelab_desktop.settings`, события — spec app-settings «События журнала оформления». Пользовательская тема в событиях — `custom`, без имени. Имя выбирает пользователь, и оно бывает личным. В событиях нет путей, ключей и значений из файла. Позиция проблемы (`line`, `column`) и код достаточны для диагностики вместе с файлом, который пользователь приложит сам. `app.appearance_resolved` пишет модуль после настройки журнала по диагностике `AppAppearanceStart`, как `app.locale_resolved` (D13 `add-desktop-localization`).

### D13. Cubit-ы, жизненный цикл, поздние результаты

- **`AppAppearanceCubit`** — root scope, singleton, единственный владелец применённого оформления (`state-management.md` §63, по образцу §63а). Состояние — `AppAppearanceState(mode, lightTheme, darkTheme, systemAccent, resolvedLight, resolvedDark, accent, saveFailed, fallback)`, где `resolved*` — готовые `FluentThemeData`. Переходы: `setMode(mode)`, `useTheme(id)` (пользовательскую тему читает и разбирает; не загрузившуюся не назначает), `resetTheme(Brightness)`, `setSystemAccent(bool)`, `reloadTheme(id)`, `refreshSystemAccent()` (D7), `retrySave()` (кнопка `Retry`: повтор записи текущего выбора). Сначала `emit`, потом запись. Записи идут по очереди, побеждает последний выбор, обогнанная запись состояние не публикует (`concurrency.md` §47а). `reloadTheme` и `useTheme` пользовательской темы защищены номером операции режима: поздний результат чтения после нового выбора или перечитывания того же режима отбрасывается. Тема, у которой после чтения база относится к другому режиму (пользователь поменял `extends`), для этого режима считается не загрузившейся: режим показывает встроенную тему, выбор не перезаписывается, событие `appearance.theme_invalid` с `code: wrongMode`.
- **`AppearanceSettingsCubit`** — создаётся на открытие страницы (`CodeLabDependencies.createAppearanceSettingsCubit`), закрывает его страница. Состояние: каталог (`loading | ready(entries)`), выбранная для превью тема, разбор выбранной, проверка контраста, исход импорта. Чтение каталога несёт номер; результат после нового «Reload» или `close()` отбрасывается (`appearance.catalog_discarded`). Импорт блокирует повторный импорт до завершения.
- **Выход app.** Запись выбора может идти в момент выхода. `AppAppearanceCubit.close()` ждёт идущую запись не дольше 3 с. Шаг `appearance` идёт той же параллельной веткой, что `language` (`concurrency.md` §45, §46: шаг без сигналов процессам не стоит перед шагами с сигналами). `app_exit_handler.dart` и диаграмма §45 обновляются.
- **Старт.** `main` до `runApp` вызывает `AppAppearanceStart.resolve(load:, library:, accentSource:, fileTimeout:)`: `load` — результат `AppAppearancePreferences.load()`, файлы тем двух режимов (если они пользовательские) читаются `ThemeLibrary.read` с ограничением `fileTimeout` (1 с) на файл, первое чтение акцента — с тем же ограничением. Метод не бросает. Результат передаётся швом `createCodeLabRootScope(appearance:)`; модуль root scope пишет `app.appearance_resolved`, а по диагностике шва — `appearance.stored_value_invalid` и `appearance.read_failed {error_class}` (сбой чтения хранилища). Без шва — значения по умолчанию. Файлы не дочитываются после старта: первый кадр уже в итоговом оформлении, «мигания» темы нет.
- **Применение без потери состояния.** `BlocBuilder<AppAppearanceCubit>` стоит рядом с языковым над `FluentApp` и меняет только `theme`, `darkTheme`, `themeMode`. `FluentApp` не пересоздаётся, `State` виджетов сохраняется (как D2, R6 `add-desktop-localization`).

### D14. Отступления от артборда

- «Open file» → «Open folder» (D11).
- Строка контраста «Accent / link» → «Link» по роли `info`. Ссылки в app рисует `info` (§12.6.3: `info` — «ссылки»), акцент к тексту на фоне кода не относится.
- Список незаданных ролей полный, но без ролей, которые app не применяет (`status_bg`, `approval_border`; Q8). В артборде он иллюстративный и содержит `approval_border`.
- Теги `Light mode` и `Dark mode` на карточках (следствие двух тем режимов, Q2) и тег `Invalid` у незагрузившейся темы (spec client-themes). В артборде их нет.
- «Accent color» скрыта на платформах без системного акцента (SETUP-17).

### D15. Локализация

Новые сообщения — в `app_en.arb` и `app_ru.arb` с `@description`. Количество (`N warnings`, `N roles not set`) — ICU `plural`. Тексты проблем app строит по `ThemeIssueCode` и аргументам (`theme_issue_texts.dart`), а не по английской строке ядра. Как есть показываются имена тем, ключи, значения цветов, пути, текст файла, отношения контраста, `Fluent Light`, `Fluent Dark`, `AA`. Термины для `l10n-glossary.md`: «Mode» — «Режим», «Match system» — «Как в системе», «Accent color» — «Цвет акцента», «Color theme» — «Цветовая тема», «Custom themes» — «Свои темы», «High contrast» — «Высокий контраст», «warning» — «предупреждение», «Low» — «Низкий» (вердикт `AA` не переводится). Сторож литералов `ui_literals_test` ловит строки мимо ARB.

### D16. Итерации

1. `[client]` разбор и модель тем в `codelab_client_core` (D2, D3).
2. `[client]` `IoThemeLibrary` в `codelab_client_io` (каталог, импорт).
3. `[desktop]` `CodeLabPalette` в ките и widget-тест пользовательской темы (доказательство D-20).
4. `[desktop]` оформление app: хранение, `AppAppearanceCubit`, встроенные темы, тёмный режим, старт, выход, системный акцент.
5. `[desktop]` страница «Appearance»: карточки, превью, контраст, проблемы, импорт; видимость страницы.
6. Документация и закрытие строки D-20.

Страница становится видимой только в итерации 5. До неё тёмный режим уже работает по «Match system» по умолчанию (Q3 (а)), но выбрать его негде. Поэтому итерации 4 и 5 СЛЕДУЕТ сливать в `develop` вместе, одним pull request.

## Risks / Trade-offs

- **Тёмный режим впервые для всего app** (Q3 (а): «Match system» по умолчанию). Экраны рисовались и проверялись только в светлой теме. Зашитые цвета вне тонов (`Color(0x33000000)` тени, превью кита) могут быть нечитаемы. Смягчение: задача «тёмная проверка» — widget-тест рабочего места, доков и всех страниц настроек в `dark` и `high-contrast` без исключений рендера и с контрастом текста ключевых ролей. Для пользователей тёмной системы вид app изменится сразу после обновления; это отмечается в `CHANGELOG.md` выпуска.
- **Расхождение с будущим CLI.** Если `add-cli-themes` захочет другой набор ролей, формат придётся версионировать. Смягчение: формат закрыт требованием `client-themes`, и §12.6.3 обновляется в этом же change.
- **Повторы ключей и позиции.** Читатель D3 — собственный код. Ошибка в нём даёт неверную строку предупреждения, но не неверный цвет: значения берутся из `jsonDecode`. Тест сверки с `jsonDecode` (D3).
- **Сторонний плагин `system_theme`.** Нативный код плагина попадает в релизную сборку на трёх платформах. Он только читает цвет, данных от пользователя и агента не принимает, ошибки не роняют app (D7). Особенности API (молчаливый запасной цвет, неотменяемая подписка, статическое поле без `await`) закрывает адаптер. Обновление пакета — отдельная правка с проверкой этих мест: пин точной версии.
- **Linux: «акцент» — цвет выделения GTK-темы.** Это не всегда то, что пользователь называет акцентом, и смены не приходят. Смягчение: значение перечитывается при старте и при открытии «Appearance»; строка видна по решению Q7.
- **Каталог с большим числом файлов.** Каждый файл не больше 64 КиБ, но каталог не ограничен. Чтение идёт асинхронно и только при открытии страницы и «Reload». Лимит не вводится, пока нет случая.
- **Недоверенный файл из интернета.** Импорт читает не больше 64 КиБ, глубина JSON ограничена, текст показывается экранированным, путь назначения строится из `[a-z0-9-]{1,32}`. Исполнения и сетевых обращений нет.
- **Гонка выхода и записи.** Шаг `appearance` при выходе (D13).

## Migration Plan

1. Ключа `codelab.app.appearance` нет → `Match system` (Q3 (а)), `light` и `dark`, системный акцент выключен.
2. Каталог `themes/` не создаётся, пока пользователь не импортирует тему или не нажмёт «Open folder».
3. Откат: удаление ключа возвращает значения по умолчанию. Каталог `themes/` app при откате не трогает.

## Решения пользователя 2026-11-20

- **Q1 (а)** — формат файла общий с CLI: capability `client-themes`, разбор в `codelab_client_core`, §12.6.3 дополнен `colors.code` и списком `extends` (D2; задача 0.1 выполнена).
- **Q2 (а)** — две темы: светлого и тёмного режима; «Mode» выбирает действующую, «Use» на зафиксированном другом режиме переключает «Mode».
- **Q3 (а)** — «Match system» по умолчанию. При выпуске это отмечается в `CHANGELOG.md`: пользователи с тёмной системой увидят тёмный app (задача 6.6).
- **Q4 (а)** — включённый системный акцент перекрывает `accent` любой темы.
- **Q5 (б)** — пакет `system_theme`, а не свой канал macOS (D7; `technology-stack.md` §20з). Переключатель по умолчанию выключен (рекомендация, отдельного ответа не было; меняется вопросом Q7б).
- **Q6 (а)** — D-20 остаётся в M5 (1.x); строка 10 `delivery-roadmap.md` §10.1 — M5 со ссылкой на change.
- **Q8** — роль `approval_border` app не применяет, как `status_bg`: роль разбирается и входит в закрытый набор, но акцентную рамку `CodeLabApprovalPrompt` сознательно убрал архивный change `2026-10-28-lighten-approval-block` («Акцентная рамка вокруг строки уходит»), и возвращать её ради темы нельзя. Поля `approvalBorder` в `CodeLabPalette` нет (D4).
- **Q7 (а)** — «Accent color» показывается на Linux; акцент перечитывается при старте и при открытии «Appearance» (D7).
- **Q7б (а)** — «Use system accent» по умолчанию выключен.

## Open Questions

Открытых вопросов нет.
