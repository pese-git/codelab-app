## MODIFIED Requirements

### Requirement: Границы пакетов monorepo
Каждый член pub workspace (список `workspace:` корневого `pubspec.yaml`) SHALL называться `codelab_…` по схеме ADR-0002, а имя пакета SHALL совпадать с именем его каталога. Префиксы `package:codelab_…` в запретах правил сторожа SHALL указывать на существующие пакеты: после переименования пакета устаревший префикс иначе молча перестал бы что-либо запрещать. Это проверяет `package_naming_test.dart` сторожа (`melos run guard`).

Основные барели ядра агента `codelab_agent_core`, моста встроенного агента `codelab_embedded` и моста настроек `codelab_setup` SHALL компилироваться в JavaScript и WebAssembly через точки web-smoke `test/web_smoke/main.dart` (`melos run web-compile`). Границы импортов и allowlist зависимостей пакетов — требование «Автоматический сторож границ пакетов». Перечень пакетов и их назначение — `AGENTS.md` §5 и `docs/architecture/layers-and-dependencies.md`.

#### Scenario: Имя пакета не по схеме
- **WHEN** член `workspace:` называется не `codelab_…` или его имя не совпадает с каталогом
- **THEN** `package_naming_test.dart` падает и называет путь и имя пакета

#### Scenario: Устаревший префикс в правиле сторожа
- **WHEN** правило `rules.dart` запрещает префикс `package:codelab_…`, которому не соответствует ни один пакет workspace
- **THEN** `package_naming_test.dart` падает и называет префикс

#### Scenario: Ядро агента собирается для web
- **WHEN** выполняется `fvm dart run melos run web-compile`
- **THEN** точка входа `packages/dart/codelab_agent_core/test/web_smoke/main.dart` компилируется в JavaScript и в WebAssembly без ошибок

#### Scenario: Web-smoke выполняет шаг модели
- **WHEN** точка входа web-smoke ядра запускается
- **THEN** она проходит один шаг модели на `ScriptedStreamFunction` через основной барель и `package:codelab_agent_core/testing.dart` и печатает итоговый текст ответа, не используя `dart:io`

#### Scenario: Web-smoke проводит ход с инструментом
- **WHEN** точка входа web-smoke ядра запускается
- **THEN** она проводит ход через `buildAgentCore` на `MemoryExecutionEnv`: scripted модель вызывает `read`, получает содержимое файла и отвечает текстом; итоговый текст печатается без `dart:io`

#### Scenario: Основной барель встроенного агента собирается для web
- **WHEN** выполняется `fvm dart run melos run web-compile`
- **THEN** точка входа `packages/dart/codelab_embedded/test/web_smoke/main.dart` компилируется в JavaScript и в WebAssembly без ошибок (профиль `embedded-cli`, суженный до памяти; design.md change `add-embedded-agent-mode`, D3)

#### Scenario: Основной барель моста настроек собирается для web
- **WHEN** выполняется `fvm dart run melos run web-compile`
- **THEN** точка входа `packages/dart/codelab_setup/test/web_smoke/main.dart` компилируется в JavaScript и в WebAssembly без ошибок (design.md change `add-provider-setup-ui`, D20)

### Requirement: Автоматический сторож границ пакетов
CodeLab SHALL проверять границы пакетов тестами `packages/dart/codelab_architecture_tests` (`melos run guard`), а не только ревью.

Сканер импортов (`import_guard_test.dart`, `import_scanner_test.dart`) SHALL:
- обходить все файлы `*.dart` каталога правила из единой таблицы `rules` (`test/support/rules.dart`): для пакета — его `lib/`, для каталога внутри `lib/` или `bin/` — этот каталог; включая файлы `part` и точки входа верхнего уровня;
- разбирать директивы `import`, `export`, `part` и каждую альтернативу условного импорта;
- сообщать каждое нарушение в виде `файл:строка -> URI`;
- снимать запрет для путей `exclude` правила, а при `sealExclude` (по умолчанию) — запрещать остальному коду каталога ссылаться на эти пути.

Каталог правила, которого нет в репозитории, SHALL ронять тест.

Правила импортов. Набор `webUnsafe` — `dart:io`, `dart:isolate`, `dart:ffi`, `dart:html`, `dart:js_interop`, `package:web/`, `package:flutter/`, `package:codelab_acp_transports/io.dart`.
- **Ядро агента `codelab_agent_core`**: `webUnsafe`, `package:codelab_acp_protocol/`, `package:codelab_acp_transports/`, разборщики конфигурации `package:yaml/`, `package:yaml_edit/`, `package:toml/` (CFG-5).
- **`codelab_acp_transports`**: `webUnsafe` во всём `lib/`, кроме `lib/io.dart` и `lib/src/io/` (запечатаны).
- **`codelab_client_acp` и `codelab_client_core`**: `webUnsafe` и пакеты языка интерфейса `package:intl/`, `package:flutter_localizations/` (требование «Ядро клиента не зависит от языка интерфейса»).
- **`codelab_client_io`**: `package:flutter/`.
- **`codelab_agent_io`**: `package:flutter/`, `package:codelab_acp_`, `package:codelab_client_`. Сценарный слой `lib/testing.dart` и `lib/src/scripted/` запечатан: остальной `lib/` на него не ссылается.
- **`codelab_agent_acp`**: `webUnsafe` (PKG-3).
- **`codelab_agent_mcp`**: `webUnsafe`, `package:codelab_acp_`, `package:codelab_client_`, `package:codelab_agent_io/` (PKG-3; design.md change `add-agent-mcp-client`, D14).
- **Бинарь `apps/codelab_agent`**: `package:flutter/`, `package:fluent_ui/`, `package:codelab_client_acp/`, `package:codelab_ui/`.
- **Мост `codelab_setup`**:
  - `lib/` вне `lib/io.dart` и `lib/src/io/` (запечатаны): `webUnsafe`, `package:codelab_agent_io/`, `package:codelab_acp_`, `package:codelab_client_`, `package:http/io_client.dart`, `package:http/browser_client.dart`;
  - весь `lib/`: `package:flutter/`, `package:codelab_acp_`, `package:codelab_client_`, `package:codelab_agent_io/testing.dart`.
- **Мост `codelab_embedded`**:
  - `lib/` вне `lib/io.dart`, `lib/src/io/`, `lib/testing.dart`, `lib/src/testing/` (запечатаны): `webUnsafe`, `package:codelab_agent_io/`, `package:codelab_client_`;
  - весь `lib/`: `package:flutter/`, `package:fluent_ui/`, `package:codelab_ui/`, `package:codelab_client_`;
  - `lib/` вне `lib/testing.dart` и `lib/src/testing/` (запечатаны): `package:codelab_agent_io/testing.dart`, `package:codelab_agent_mcp/testing.dart`.
- **Терминальный клиент `apps/codelab_cli`**:
  - весь `lib/`: `package:flutter/`, `package:fluent_ui/`, `package:codelab_ui/`, `package:codelab_agent_`;
  - `package:codelab_acp_testing/` — только `lib/src/scenario/`;
  - `package:dart_tui/` — только `lib/src/tui/`;
  - `package:codelab_setup/io.dart` — только `lib/src/run.dart`;
  - `package:codelab_embedded/io.dart` — только `lib/src/composition_root.dart`;
  - `package:codelab_embedded/testing.dart` — только `lib/src/scenario/`;
  - `bin/` не импортирует `package:codelab_embedded/io.dart`, `package:codelab_embedded/testing.dart` и `package:codelab_setup/io.dart`;
  - ядро экрана `lib/src/tui/core/` не импортирует `package:dart_tui/` и `dart:io` (TUI-5).
- **Desktop `apps/codelab_desktop`**:
  - `lib/`: `package:codelab_agent_`; IO-барели мостов `package:codelab_embedded/io.dart`, `package:codelab_setup/io.dart` — только `lib/app/` (composition root); `package:codelab_embedded/testing.dart` — нигде;
  - нативные плагины — только в адаптерах `lib/core/platform/`: `file_selector` и `url_launcher` — каталог `core/platform/`; `system_theme` — `system_accent_source.dart`; `desktop_drop` — `os_drop_region.dart`; `pty2` — `user_shell_launcher.dart`; `dart:ffi` — `build_info.dart`;
  - терминал: `xterm2_core` — только `features/terminal/`; `xterm2` — только `features/terminal/presentation/`; `zmodem`, `package:xterm2/xterm.dart` и `package:xterm2/zmodem.dart` — нигде;
  - транзитивные пакеты markdown `material_ui`, `cupertino_ui`, `val_highlight_flutter`, `val_latex_flutter`, `flutter_svg` — нигде;
  - чистота фич: `features/onboarding/` и `features/project_files/` — без `dart:io`; `features/settings/presentation/` — без `dart:io` и `package:codelab_setup/io.dart` (SETUP-9); `features/terminal/application/` — без `package:flutter/`; `features/usage/application/` — без `package:flutter/` и `dart:io`; `features/protocol/application/` — без `package:flutter/`, `dart:io`, `package:structured_log_flutter/` и `package:structured_log_fluent/`.
- **Кит `codelab_ui`**: `package:gpt_markdown/` и `package:val_highlight/` — только `lib/src/rendering/`; транзитивные пакеты markdown (как у desktop) и `package:desktop_drop/` — нигде.

Allowlist `dependencies` (`pubspec_allowlist_test.dart`, константы `*Allowlist`). `dependencies` пакета SHALL быть подмножеством его allowlist:
- `codelab_agent_core` — `{http, meta, collection, async, crypto}` (PKG-2);
- `codelab_agent_io` — `{codelab_agent_core, path, meta, async, yaml, yaml_edit}`;
- `codelab_agent_acp` — `{codelab_agent_core, codelab_acp_protocol, codelab_acp_transports, meta, async}`;
- `codelab_agent_mcp` — `{codelab_agent_core, http, meta, async}`;
- `apps/codelab_agent` — `{codelab_agent_core, codelab_agent_io, codelab_agent_acp, codelab_agent_mcp, codelab_acp_protocol, codelab_acp_transports, args, http, async, meta}`;
- `codelab_client_core` — `{codelab_client_acp, codelab_acp_protocol, codelab_acp_transports, freezed_annotation, meta, collection, async}`;
- `codelab_client_io` — `{codelab_client_core, codelab_client_acp, codelab_acp_protocol, codelab_acp_transports, path, meta}`;
- `apps/codelab_cli` — `{codelab_client_core, codelab_client_io, codelab_client_acp, codelab_acp_protocol, codelab_acp_transports, codelab_acp_testing, codelab_setup, codelab_embedded, dart_tui, args, async, path, meta}`;
- `codelab_setup` — `{codelab_agent_core, codelab_agent_io, http, meta}`;
- `codelab_embedded` — `{codelab_agent_core, codelab_agent_io, codelab_agent_acp, codelab_agent_mcp, codelab_acp_protocol, codelab_acp_transports, http, meta, async}`.

У `apps/codelab_desktop` SHALL проверяться только пакеты `codelab_*` в `dependencies`: подмножество `{codelab_client_acp, codelab_client_core, codelab_client_io, codelab_acp_protocol, codelab_acp_transports, codelab_embedded, codelab_setup, codelab_ui}`. Сторонние зависимости app этим правилом не ограничиваются.

Сборка ядра агента (`host_assembly_guard_test.dart`, HOST-6). В `lib/` и `bin/` `apps/codelab_agent` и в `lib/` `codelab_embedded` SHALL NOT встречаться `ToolRegistry(`, `Agent(` и `AgentRuntime(`: ядро собирается только через `buildAgentCore`.

Новый пакет получает правило вместе с пакетом (`AGENTS.md` §5). Порядок расширения allowlist и что сторож не проверяет — `layers-and-dependencies.md` §42, §43.

#### Scenario: Нарушение в ядре обнаружено
- **WHEN** файл в `packages/dart/codelab_agent_core/lib/` импортирует `dart:io`, в том числе как альтернативу условного импорта
- **THEN** `fvm dart run melos run guard` падает и указывает файл, строку и запрещённый URI

#### Scenario: Сторож сам проверен на нарушении
- **WHEN** запускается негативный тест сторожа на временном пакете с `import 'a.dart' if (dart.library.io) 'dart:io';`
- **THEN** сканер возвращает ровно одно нарушение `lib/src/x.dart:1 -> dart:io`

#### Scenario: Зависимость вне allowlist
- **WHEN** в `dependencies` файла `packages/dart/codelab_agent_core/pubspec.yaml` или `packages/dart/codelab_agent_io/pubspec.yaml` появляется пакет вне allowlist этого пакета, например `toml` у `codelab_agent_io`
- **THEN** `pubspec_allowlist_test.dart` падает и называет лишний пакет

#### Scenario: IO-пакет агента импортирует ACP
- **WHEN** файл в `packages/dart/codelab_agent_io/lib/` импортирует `package:codelab_acp_protocol/`
- **THEN** сторож сообщает нарушение

#### Scenario: Клиент импортирует ядро напрямую
- **WHEN** файл в `apps/codelab_desktop/lib/` импортирует `package:codelab_agent_core/`
- **THEN** сторож сообщает нарушение

#### Scenario: ACP-адаптер импортирует dart:io
- **WHEN** файл в `packages/dart/codelab_agent_acp/lib/` импортирует `dart:io` или `package:codelab_acp_transports/io.dart`
- **THEN** сторож сообщает нарушение

#### Scenario: Бинарь собирает ядро вручную
- **WHEN** файл в `apps/codelab_agent/lib/` содержит `AgentRuntime(`
- **THEN** сторож падает и называет файл и строку (HOST-6)

#### Scenario: Клиентский слой импортирует dart:io
- **WHEN** файл в `packages/dart/codelab_client_core/lib/` или `packages/dart/codelab_client_acp/lib/` импортирует `dart:io` или `package:codelab_acp_transports/io.dart`
- **THEN** сторож сообщает нарушение

#### Scenario: IO-транспорт в основном бареле транспортов
- **WHEN** файл `packages/dart/codelab_acp_transports/lib/src/` вне `lib/src/io/` импортирует `dart:io`, а `lib/src/io/` — тоже
- **THEN** сторож сообщает нарушение только для файла вне `lib/src/io/`

#### Scenario: IO-адаптеры клиента импортируют Flutter
- **WHEN** файл в `packages/dart/codelab_client_io/lib/` импортирует `package:flutter/`
- **THEN** сторож сообщает нарушение

#### Scenario: Терминальный клиент импортирует ядро агента
- **WHEN** файл в `apps/codelab_cli/lib/` импортирует `package:codelab_agent_core/`
- **THEN** сторож сообщает нарушение

#### Scenario: Тестовый пакет вне драйвера фикстур
- **WHEN** файл в `apps/codelab_cli/lib/src/repl/` импортирует `package:codelab_acp_testing/`
- **THEN** сторож сообщает нарушение

#### Scenario: Пакет TUI вне адаптера
- **WHEN** файл в `apps/codelab_cli/lib/src/repl/` или в `apps/codelab_cli/lib/src/tui/core/` импортирует `package:dart_tui/`
- **THEN** сторож сообщает нарушение

#### Scenario: IO-барель моста настроек вне run.dart CLI
- **WHEN** файл `apps/codelab_cli/lib/codelab_cli.dart` или `apps/codelab_cli/bin/codelab.dart` импортирует `package:codelab_setup/io.dart`, а `apps/codelab_cli/lib/src/run.dart` — тоже
- **THEN** сторож сообщает нарушения для бареля и `bin/`, но не для `run.dart`

#### Scenario: MCP-клиент импортирует dart:io
- **WHEN** файл в `packages/dart/codelab_agent_mcp/lib/`, включая `lib/testing.dart`, импортирует `dart:io` или `package:codelab_acp_protocol/`
- **THEN** сторож сообщает нарушение

#### Scenario: Зависимость MCP-клиента вне allowlist
- **WHEN** в `dependencies` файла `packages/dart/codelab_agent_mcp/pubspec.yaml` появляется `json_rpc_2`
- **THEN** `pubspec_allowlist_test.dart` падает и называет `json_rpc_2`

#### Scenario: Ядро импортирует разборщик конфигурации
- **WHEN** файл в `packages/dart/codelab_agent_core/lib/` импортирует `package:yaml/yaml.dart`
- **THEN** сторож сообщает нарушение

#### Scenario: Основной барель моста импортирует IO-пакет агента
- **WHEN** файл `packages/dart/codelab_setup/lib/codelab_setup.dart` импортирует `package:codelab_agent_io/codelab_agent_io.dart`, а `lib/io.dart` — тоже
- **THEN** сторож сообщает ровно одно нарушение — для основного бареля

#### Scenario: Основной барель встроенного агента импортирует IO-пакет
- **WHEN** файл `packages/dart/codelab_embedded/lib/codelab_embedded.dart` или `lib/src/agent.dart` импортирует `package:codelab_agent_io/codelab_agent_io.dart`, а `lib/io.dart` — тоже
- **THEN** сторож сообщает нарушения только для файлов вне `lib/io.dart`

#### Scenario: Встроенный агент собирает ядро вручную
- **WHEN** файл в `packages/dart/codelab_embedded/lib/` содержит `ToolRegistry(`
- **THEN** сторож падает и называет файл и строку (HOST-6)

#### Scenario: IO-барель встроенного агента вне composition root
- **WHEN** файл `apps/codelab_cli/lib/src/repl/repl.dart` или `apps/codelab_desktop/lib/features/workbench/application/connection_cubit.dart` импортирует `package:codelab_embedded/io.dart`
- **THEN** сторож сообщает нарушение

#### Scenario: Пакет агента в зависимостях app
- **WHEN** в `dependencies` файла `apps/codelab_desktop/pubspec.yaml` появляется `codelab_agent_core`
- **THEN** `pubspec_allowlist_test.dart` падает и называет `codelab_agent_core`, а зависимость `codelab_embedded` нарушением не считается

#### Scenario: IO-барель моста настроек вне composition root app
- **WHEN** файл `apps/codelab_desktop/lib/features/settings/application/provider_settings_cubit.dart` импортирует `package:codelab_setup/io.dart`, а `apps/codelab_desktop/lib/app/app_scope.dart` — тоже
- **THEN** сторож сообщает ровно одно нарушение — для файла вне `lib/app/`

#### Scenario: dart:io в presentation настроек
- **WHEN** файл в `apps/codelab_desktop/lib/features/settings/presentation/` импортирует `dart:io`
- **THEN** сторож сообщает нарушение (SETUP-9)

#### Scenario: Плагин выбора файла вне адаптера платформы
- **WHEN** файл `apps/codelab_desktop/lib/features/` импортирует `package:file_selector/file_selector.dart`
- **THEN** сторож сообщает нарушение, а тот же импорт в `apps/codelab_desktop/lib/core/platform/` нарушением не является

#### Scenario: Flutter в application панели Protocol
- **WHEN** файл в `apps/codelab_desktop/lib/features/protocol/application/` импортирует `package:flutter/` или `package:structured_log_flutter/`
- **THEN** сторож сообщает нарушение

#### Scenario: Мост настроек в зависимостях app
- **WHEN** в `dependencies` файла `apps/codelab_desktop/pubspec.yaml` есть `codelab_setup` и `codelab_embedded`
- **THEN** `pubspec_allowlist_test.dart` не сообщает нарушения, а `codelab_agent_io` в том же файле по-прежнему нарушение

#### Scenario: http в мосте настроек
- **WHEN** в `dependencies` файла `packages/dart/codelab_setup/pubspec.yaml` есть `http`, а основной барель `lib/codelab_setup.dart` импортирует `package:http/http.dart`
- **THEN** сторож и `pubspec_allowlist_test.dart` нарушений не сообщают; импорт `package:http/io_client.dart` из `lib/src/provider/` — нарушение, а из `lib/src/io/` — нет

#### Scenario: Зависимость моста встроенного агента вне allowlist
- **WHEN** в `dependencies` файла `packages/dart/codelab_embedded/pubspec.yaml` появляется `codelab_client_core`
- **THEN** `pubspec_allowlist_test.dart` падает и называет `codelab_client_core`

### Requirement: Плагин перетаскивания из ОС только в адаптере платформы
В `apps/codelab_desktop/lib` импорт `package:desktop_drop/` SHALL быть разрешён только файлу `core/platform/os_drop_region.dart` (адаптер `OsDropRegion`). Остальной код app получает от него список путей и колбэки входа и выхода перетаскивания. Типы плагина (`DropTarget`, `DropDoneDetails`, `XFile` плагина) за пределы адаптера НЕ SHALL выходить (AGENTS.md §11, `platform-integration.md` §8, §37; design.md change `add-empty-project-screen`, D3). `packages/flutter/codelab_ui/lib` НЕ SHALL импортировать `package:desktop_drop/`. Оба нарушения SHALL ловить сторож `codelab_architecture_tests` (`melos run guard`) правилами в `test/support/rules.dart`.

#### Scenario: Плагин в виджете рабочего места
- **WHEN** файл `apps/codelab_desktop/lib/features/workbench/presentation/widgets/open_project_screen.dart` импортирует `package:desktop_drop/desktop_drop.dart`
- **THEN** `melos run guard` сообщает нарушение и называет файл и импорт

#### Scenario: Плагин в адаптере
- **WHEN** импорт `package:desktop_drop/desktop_drop.dart` есть только в `apps/codelab_desktop/lib/core/platform/os_drop_region.dart`
- **THEN** `melos run guard` нарушений этого правила не находит

#### Scenario: Плагин в ките
- **WHEN** файл в `packages/flutter/codelab_ui/lib/` импортирует `package:desktop_drop/desktop_drop.dart`
- **THEN** `melos run guard` сообщает нарушение и называет файл и импорт

## REMOVED Requirements

### Requirement: Границы Clean Architecture
**Reason**: Принцип, а не проверяемая норма: сценарии «use case зависит от порта» и «адаптеры подключаются в composition root» автоматически не проверяются. Второй сценарий к тому же устарел: composition root три, а не один — `apps/codelab_desktop/lib/app/`, `apps/codelab_cli/lib/src/composition_root.dart` и хост `apps/codelab_agent` (design.md change `align-cross-cutting-specs`, D1, D5).
**Migration**: Направление зависимостей и слои — `AGENTS.md` §6 и `docs/architecture/layers-and-dependencies.md` §2–§4, §15–§18; порты — §18, §34; composition root — §24. Проверяемая часть границ — требование «Автоматический сторож границ пакетов» (импорты `dart:io` и Flutter в ядре и application фич, IO-барели только в composition root).

### Requirement: Ограничения SOLID, KISS и DRY
**Reason**: Дисциплина реализации, которую проверяет ревью, а не тест. Сценарий «переходы состояний централизованы в `codelab_client_acp`» устарел: владелец клиентского состояния — `codelab_client_core` (`AGENTS.md` §5) (design.md, D1, D5).
**Migration**: Пропорциональность и запрет лишних абстракций — `AGENTS.md` §13, §14; размещение кода — `layers-and-dependencies.md` §44–§47, §52; владение состоянием — `state-management.md` и `layers-and-dependencies.md` §21.

### Requirement: CherryPick как dependency injection
**Reason**: Выбор технологии, а не поведение продукта. Требование устарело: Cherrypick есть только в `apps/codelab_desktop`, CLI и бинарь агента собираются без DI-фреймворка, а версии в документах не дублируются (`AGENTS.md` §4) (design.md, D1, D5).
**Migration**: Выбор Cherrypick, его место и composition root — `technology-stack.md` §9, §9.1, §9.2; граница DI — `layers-and-dependencies.md` §23, §38; запрет сервис-локатора в domain и application — там же, §23. Новый DI-фреймворк требует архитектурного решения (`AGENTS.md` §4).

### Requirement: Стандартные библиотеки моделирования
**Reason**: Выбор технологии. Требование устарело и противоречит сторожу: `fpdart` и `Either` обязательными быть не могут — allowlist ядра агента (`coreAllowlist`, PKG-2) и `codelab_client_core` (`kitAllowlist`) `fpdart` не пускает, а `fpdart` импортирует только `codelab_client_acp` (design.md, D1, D5).
**Migration**: Граница `fpdart` — `layers-and-dependencies.md` §39 и `technology-stack.md` §10; Freezed — `layers-and-dependencies.md` §40 и `technology-stack.md` §11; типизированные ошибки — `AGENTS.md` §15 и `error-handling.md`; явные автоматы состояний — `AGENTS.md` §8 и `session-lifecycle.md`.
