## Why

Экран 10 дорожной карты ([`delivery-roadmap.md`](../../../docs/architecture/proposals/delivery-roadmap.md) §10.1) — «Settings › Appearance» — цель D-20 ([`agent-parity-goals.md`](../../../docs/architecture/proposals/agent-parity-goals.md)): кроме стандартной темы Fluent — встроенные цветовые темы и пользовательские из JSON с теми же ролями цветов, что у CLI (U-18), включая палитру подсветки кода. Неизвестный ключ — предупреждение, недостающий цвет берётся из базовой темы. Поведение app уже описано в [`12-6-cli-desktop-extras.md`](../../../docs/architecture/proposals/dart-agent-and-clients/12-6-cli-desktop-extras.md) §12.6.3, пункты 5–6. Это нестрогий разбор: тема применяется, предупреждения видны на карточке.

Сейчас в app нет ни одной настройки оформления:
- `FluentApp` получает только светлую тему: тёмного режима нет, даже если система тёмная;
- акцент — `Colors.blue` Fluent по умолчанию, системный акцент не учитывается;
- цвета статусов кита (`CodeLabTone`) зашиты как `Colors.green`, `Colors.red`, `Colors.warningPrimaryColor`. Палитра кода `CodeLabCodeTheme` выводится из ролей Fluent, и заменить её нечем;
- пункт навигации `appearance` объявлен в `SettingsPage`, но скрыт: у страницы нет тела (SETUP-17).

Формата файла темы в спецификациях нет. U-18 (темы CLI) ещё не реализован, кода разбора тем в CLI и клиентском слое тоже нет. Поэтому change впервые закрепляет формат `~/.codelab/themes/<name>.json` как требование и кладёт разбор туда, где его сможет переиспользовать CLI (design.md, D1, D2).

## What Changes

- **Страница «Appearance»** группы «App» становится видимой. Состав по артборду «10 Settings — Appearance»:
  - **«Mode»** — `Light`, `Dark`, `Match system`. У `Match system` в скобках показан текущий режим системы.
  - **«Accent color»** — переключатель «Use system accent». Акцент даёт пакет `system_theme`; строка видна только там, где он отдаёт цвет (SETUP-17; design.md, D7). Включённый переключатель перекрывает `accent` любой темы.
  - **«Color theme»** — карточки встроенных тем `Fluent Light` (`light`), `Fluent Dark` (`dark`), `High contrast` (`high-contrast`) и пользовательских тем. На карточке мини-превью кода, вид темы (`Built-in`, `Custom · extends dark`) и бейдж `N warnings`.
  - **«Custom themes»** — путь `<home>/themes/*.json` и кнопка «Import JSON…».
  - **Панель проблем выбранной темы**: InfoBar `<name> loaded with N warnings` с кнопками «Open folder» и «Reload», текст файла с номерами строк и подсветкой строк с предупреждениями. Ниже — список проблем: неизвестный ключ с подсказкой `Did you mean "accent"?`, ключ, который не является ролью, и справка о ролях, взятых из `extends` (справка, а не предупреждение).
  - **«Preview»** — блок кода `dart`, строки diff, статусы `Link`, `Done`, `84% context`, `Failed`. Ниже — «Contrast on code background»: отношение к фону кода с вердиктом `AA` или `Low` при пороге 4,5:1. Кнопки «Reset» и «Use <name>».
- **Режимы и темы применяются ко всему app сразу**, без перезапуска и без потери ввода, фокуса и прокрутки, как смена языка. Первый кадр app рисуется уже в сохранённом оформлении. Выбор хранится в `shared_preferences` одним документом `codelab.app.appearance` (design.md, D5).
- **Две темы на два режима** (решение пользователя Q2 (а)). App помнит тему для светлого и тему для тёмного режима, а «Mode» выбирает, какая из них действует. Карточка темы относится к режиму своей базы `extends`.
- **Формат файла темы — общий с CLI** (решение пользователя Q1 (а)). Это новая capability `client-themes`: имя файла, `name`, `extends`, `colors`, роли CLI (§12.6.3) плюс вложенный объект `colors.code` — палитра подсветки кода. Значения цвета — по §12.6.3. Нестрогий разбор app: неизвестный ключ, повтор ключа и терминальный цвет — предупреждения с позицией `файл:строка:колонка`, тема применяется. Неверный JSON, неверное значение, `name` не равен имени файла, файл больше 64 КиБ — тема не загружается, действует запасная тема.
- **Разбор и модель темы** — в `codelab_client_core` (чистый Dart, web-безопасно, коды проблем без текста). Чтение каталога, импорт и атомарная запись — в `codelab_client_io`. В app — Cubit-ы, перевод ролей в `FluentThemeData`, страница (design.md, D1–D3).
- **«Import JSON…»** проверяет выбранный файл и копирует его в `<home>/themes/<name>.json`, где `<name>` берётся из поля `name`. Если тема с таким именем уже есть, app сначала спрашивает подтверждение замены. Битый файл не копируется. Импортированная тема выбирается для превью, но не применяется до «Use <name>» (design.md, D9).
- **`codelab_ui`**: тема-расширение `CodeLabPalette` с ролями статусов, ссылок, diff и выделения. Тоны кита (`CodeLabTone`) и ссылки берут цвет из неё. Роли `approval_border` и `status_bg` app не применяет: рамки блока одобрения в app нет (change `lighten-approval-block`), статус-строка TUI — только у CLI (решение пользователя Q8). Без расширения кит выводит палитру из `FluentTheme` так, что стандартные темы Fluent выглядят как сейчас. Просмотр файла `CodeLabFilePreview` получает необязательный набор строк с предупреждением (design.md, D4, D10).
- **Контраст.** Встроенные темы дают каждой проверяемой роли не меньше 4,5:1 на фоне кода. Роль пользовательской темы ниже порога применяется как задана, а карточка получает предупреждение `Low contrast`. Поэтому требование «Блок кода в ответе агента» в `agent-workbench-ui` уточняется (MODIFIED).
- **Локализация**: все тексты — ARB `en` и `ru` по глоссарию. Имена тем, ключи JSON, значения цветов, пути и текст файла не переводятся. Ядро клиента отдаёт коды проблем, текст строит app.
- **Наблюдаемость**: события `app.appearance_resolved`, `settings.appearance_changed`, `appearance.theme_loaded`, `appearance.theme_invalid`, `appearance.theme_imported`, `appearance.save_failed`. В событиях нет путей, имён пользовательских тем и содержимого файла (design.md, D12).

## Не входит

- **Темы CLI** (U-18, `/theme`, `display.theme`, понижение глубины цвета, OSC 11). Это change `add-cli-themes`. Здесь закрепляется только общий формат файла и разбор в клиентском слое; CLI подключит его в строгом режиме.
- **Отслеживание файлов тем на диске.** Изменённый файл перечитывается кнопкой «Reload» или при следующем запуске app.
- **Роль фона окна и других поверхностей Fluent.** Пользовательская тема меняет роли из списка (`client-themes`), а поверхности окна берутся из ресурсов Fluent режима `extends`.
- **Системный режим высокой контрастности ОС** (`MediaQuery.highContrast`). Встроенная тема `High contrast` выбирается вручную.
- **Открытие файла темы во внешнем редакторе.** App файлов не открывает: «Open folder» открывает каталог тем, как «Open folder» у определений агентов (design.md change `add-settings-agents-modes`, D8; здесь D11).
- **Редактор темы в app** и экспорт темы.
- **Изменения ACP**: новых методов, полей и `_meta` нет.

## Capabilities

### New Capabilities

- `client-themes` — формат файла пользовательской темы, роли цветов, нестрогий разбор app, каталог тем и импорт.

### Modified Capabilities

- `app-settings` — ADDED «Страница «Appearance»: видимость и состав», «Режим оформления и темы режимов», «Системный акцент», «Карточки тем и превью», «Пользовательские темы на странице «Appearance»», «Импорт темы», «Контраст на фоне кода», «Хранение оформления», «События журнала оформления».
- `agent-workbench-ui` — MODIFIED «Блок кода в ответе агента» (порог контраста — для встроенных тем; роль пользовательской темы применяется как задана); ADDED «Цвета кита из палитры темы».

## Impact

- **Код:**
  - `packages/dart/codelab_client_core` — `lib/src/themes/` (`ThemeRole`, `ThemeColorValue`, `ThemeFile.parse`, `ThemeIssue`, `ThemeLibrary` — порт каталога), экспорт из бареля (`[client]`);
  - `packages/dart/codelab_client_io` — `lib/src/themes/io_theme_library.dart` (`IoThemeLibrary`: перечисление, чтение до 64 КиБ, импорт с атомарной записью) (`[client]`);
  - `packages/flutter/codelab_ui` — `CodeLabPalette`, тоны через палитру, ссылки, `CodeLabFilePreview.warningLines` (`[desktop]`);
  - `apps/codelab_desktop`:
    - `lib/app/appearance/` — `AppAppearanceCubit`, `AppAppearanceStart`, `fluent_theme_builder.dart`;
    - `core/platform/` — `app_appearance_preferences.dart`, `system_accent_source.dart` (адаптер на `system_theme`), `theme_file_picker.dart`;
    - `features/settings/application/` — `AppearanceSettingsCubit` и состояние, `contrast_checks.dart`;
    - `features/settings/presentation/appearance_page.dart`;
    - `main.dart`, `lib/app/app_scope.dart`, `default_settings_pages.dart`, `pubspec.yaml`, ARB (`[desktop]`).
- **Зависимости:** одна новая сторонняя зависимость app — `system_theme` 3.3.0 (BSD-3-Clause; транзитивно `system_theme_web` 0.0.5, BSD-3-Clause) по решению пользователя Q5 (б), `technology-stack.md` §20з. Пакетов workspace не добавляется. `clientCoreAllowlist`, `clientIoAllowlist` и allowlist ядра (PKG-2) не меняются; `desktopAllowlist` сверяет только `codelab_*`. Новых рёбер графа нет, граф в `README.md` не меняется. Новых правил сторожа два: `package:file_selector` и `package:system_theme` в `apps/codelab_desktop/lib` — только в `lib/core/platform/` (D1).
- **ACP:** без изменений.
- **Данные пользователя:**
  - новый ключ `shared_preferences` — `codelab.app.appearance`;
  - новый каталог `$CODELAB_HOME/themes/`: app пишет в него только по «Import JSON…» после подтверждения замены, атомарно;
  - `config.yaml`, `cli.yaml` и `profiles.json` не меняются.
- **Безопасность:**
  - файл темы — недоверенные данные. Он читается не больше 64 КиБ, не исполняется, а его текст показывается с экранированием управляющих символов;
  - импорт пишет только в каталог тем, по имени из `[a-z0-9-]{1,32}`, поэтому выйти из каталога путём нельзя;
  - файлы не открываются внешним приложением;
  - в журнал не попадают пути и содержимое файлов.
- **Документация:** `technology-stack.md` §20з, `state-management.md` §63б, `concurrency.md` §47б, §12.6.3, §12.4.9 (сделано при подготовке); `apps/codelab_desktop/doc/user-guide.md` (раздел об оформлении), `README.md` и `AGENTS.md` app, `docs/user/configuration.md` (каталог `themes/`), §12.6.3 и §12.4.9 `dart-agent-and-clients`, строка 10 `delivery-roadmap.md` §10.1, строка D-20 `agent-parity-goals.md`, `l10n-glossary.md`.
