## MODIFIED Requirements

### Requirement: Границы пакетов monorepo
CodeLab SHALL использовать Dart/Flutter/FVM/Melos monorepo с разделёнными пакетами `codelab_acp_protocol`, `codelab_acp_transports`, `codelab_client_acp`, `codelab_acp_testing`, `codelab_ui`, `codelab_desktop`. В нём также SHALL быть пакеты Dart-агента `codelab_agent_core`, `codelab_agent_io`, `codelab_agent_acp` и `codelab_agent_mcp`, общий клиентский слой `codelab_client_core` (чистый Dart) и его `dart:io`-адаптеры `codelab_client_io`, приложение бинаря агента `apps/codelab_agent` (чистый Dart), мост встроенного агента `codelab_embedded` (основной барель web-безопасен; design.md change `add-embedded-agent-mode`, D1, D2), терминальный клиент `apps/codelab_cli` (чистый Dart) и пакет архитектурных проверок `codelab_architecture_tests`. Каждый пакет SHALL быть указан в `workspace:` корневого `pubspec.yaml`. `codelab_acp_testing` SHALL быть только `dev_dependency` других пакетов и приложений; единственное исключение — `apps/codelab_cli`, команда которого `test-scenario` проигрывает фикстуры в рабочем бинаре.

#### Scenario: Пакеты workspace присутствуют
- **WHEN** реализация разворачивает workspace
- **THEN** репозиторий содержит все требуемые пакеты, и у каждого есть собственный `pubspec.yaml`

#### Scenario: Чистые Dart-пакеты остаются свободными от Flutter
- **WHEN** запускается статический анализ для `packages/dart/*`
- **THEN** ни один чистый Dart-пакет не импортирует Flutter, `fluent_ui`, Bloc или код UI приложения

#### Scenario: Ядро агента собирается для web
- **WHEN** выполняется `fvm dart run melos run web-compile`
- **THEN** точка входа `packages/dart/codelab_agent_core/test/web_smoke/main.dart` компилируется в JavaScript и в WebAssembly без ошибок

#### Scenario: Web-smoke выполняет шаг модели
- **WHEN** точка входа web-smoke запускается
- **THEN** она проходит один шаг модели на `ScriptedStreamFunction` через основной барель и `package:codelab_agent_core/testing.dart` и печатает итоговый текст ответа, не используя `dart:io`

#### Scenario: Web-smoke проводит ход с инструментом
- **WHEN** точка входа web-smoke запускается
- **THEN** она проводит ход через `buildAgentCore` на `MemoryExecutionEnv`: scripted модель вызывает `read`, получает содержимое файла и отвечает текстом; итоговый текст печатается без `dart:io`

#### Scenario: Бинарь агента — чистый Dart
- **WHEN** запускается сторож для `apps/codelab_agent`
- **THEN** ни один файл `lib/` приложения не импортирует `package:flutter/`, а `bin/` содержит только точку входа поверх бареля `lib/`

#### Scenario: Клиентский слой собирается без Flutter и dart:io
- **WHEN** запускается сторож для `packages/dart/codelab_client_core`
- **THEN** ни один файл `lib/` пакета не импортирует `dart:io`, `package:flutter/` и `package:codelab_acp_transports/io.dart`, а его `dependencies` — подмножество allowlist пакета

#### Scenario: Терминальный клиент — чистый Dart без ядра агента
- **WHEN** запускается сторож для `apps/codelab_cli`
- **THEN** ни один файл `lib/` приложения не импортирует `package:flutter/` и `package:codelab_agent_`, а `bin/` содержит только точку входа поверх бареля `lib/`

#### Scenario: MCP-клиент агента без dart:io
- **WHEN** запускается сторож для `packages/dart/codelab_agent_mcp`
- **THEN** ни один файл `lib/` пакета не импортирует `dart:io` и `package:flutter/`, а его `dependencies` — подмножество allowlist пакета

#### Scenario: Основной барель встроенного агента собирается для web
- **WHEN** выполняется `fvm dart run melos run web-compile`
- **THEN** точка входа `packages/dart/codelab_embedded/test/web_smoke/main.dart` компилируется в JavaScript без ошибок

### Requirement: Автоматический сторож границ пакетов
CodeLab SHALL проверять границы пакетов тестом `packages/dart/codelab_architecture_tests`, а не только ревью.

Сторож SHALL:
- обходить все файлы `lib/**/*.dart` каждого пакета из единой таблицы правил, включая файлы `part` и точки входа верхнего уровня;
- разбирать директивы `import`, `export`, `part` и каждую альтернативу условного импорта;
- сообщать каждое нарушение в виде `файл:строка -> URI`.

Правила пакетов:
- **`codelab_agent_core`** НЕ SHALL импортировать `dart:io`, `dart:isolate`, `dart:ffi`, `dart:html`, `dart:js_interop`, `package:web/`, `package:flutter/`, `package:codelab_acp_protocol/`, `package:codelab_acp_transports/`, `package:yaml/`, `package:yaml_edit/` и `package:toml/` (CFG-5: разборщики конфигурации — только в `codelab_agent_io`). Его `dependencies` SHALL быть подмножеством `{http, meta, collection, async, crypto}`.
- **`codelab_agent_io`** НЕ SHALL импортировать `package:flutter/`, `package:codelab_acp_` и `package:codelab_client_`. Его `dependencies` SHALL быть подмножеством `{codelab_agent_core, path, meta, async, yaml, yaml_edit}`: `toml` из allowlist убран, `codelab.toml` агент не читает (design.md change `add-agent-configuration`, D2, D12).
- **`codelab_agent_acp`** НЕ SHALL импортировать `dart:io`, `dart:isolate`, `dart:ffi`, `dart:html`, `dart:js_interop`, `package:web/`, `package:flutter/` и `package:codelab_acp_transports/io.dart` (PKG-3). Его `dependencies` SHALL быть подмножеством `{codelab_agent_core, codelab_acp_protocol, codelab_acp_transports, meta, async}`.
- **`codelab_agent_mcp`** НЕ SHALL импортировать `dart:io`, `dart:isolate`, `dart:ffi`, `dart:html`, `dart:js_interop`, `package:web/`, `package:flutter/`, `package:codelab_acp_transports/io.dart`, `package:codelab_acp_`, `package:codelab_client_` и `package:codelab_agent_io/` (PKG-3; design.md change `add-agent-mcp-client`, D14). Его `dependencies` SHALL быть подмножеством `{codelab_agent_core, http, meta, async}`.
- **Бинарь `apps/codelab_agent`** НЕ SHALL импортировать `package:flutter/`, `package:fluent_ui/`, `package:codelab_client_acp/` и `package:codelab_ui/`. Его `dependencies` SHALL быть подмножеством `{codelab_agent_core, codelab_agent_io, codelab_agent_acp, codelab_agent_mcp, codelab_acp_protocol, codelab_acp_transports, args, http, async, meta}`. В его `lib/` и `bin/` НЕ SHALL встречаться `ToolRegistry(`, `Agent(` и `AgentRuntime(`: ядро собирается только через `buildAgentCore` (HOST-6).
- **`codelab_client_core`** НЕ SHALL импортировать `dart:io`, `dart:isolate`, `dart:ffi`, `dart:html`, `dart:js_interop`, `package:web/`, `package:flutter/` и `package:codelab_acp_transports/io.dart`. Его `dependencies` SHALL быть подмножеством `{codelab_client_acp, codelab_acp_protocol, codelab_acp_transports, freezed_annotation, meta, collection, async}`.
- **`codelab_client_io`** НЕ SHALL импортировать `package:flutter/`. Его `dependencies` SHALL быть подмножеством `{codelab_client_core, codelab_client_acp, codelab_acp_protocol, codelab_acp_transports, path, meta}`.
- **Терминальный клиент `apps/codelab_cli`** НЕ SHALL импортировать `package:flutter/`, `package:fluent_ui/`, `package:codelab_ui/` и `package:codelab_agent_`. Его `dependencies` SHALL быть подмножеством `{codelab_client_core, codelab_client_io, codelab_client_acp, codelab_acp_protocol, codelab_acp_transports, codelab_acp_testing, codelab_setup, codelab_embedded, dart_tui, args, async, path, meta}`; `package:codelab_acp_testing/` и `package:codelab_embedded/testing.dart` SHALL импортироваться только из `lib/src/scenario/`, `package:codelab_embedded/io.dart` — только из `lib/src/composition_root.dart`; `package:dart_tui/` SHALL импортироваться только из `lib/src/tui/`, `package:codelab_setup/io.dart` — только из `lib/src/run.dart` (правило сторожа), а файлы ядра экрана `lib/src/tui/core/` НЕ SHALL импортировать ни `package:dart_tui/`, ни `dart:io`.
- **Мост `codelab_setup`** (настройки агента для клиентов, `dart-agent-and-clients` §12.4.2): файлы `lib/` вне `lib/io.dart` и `lib/src/io/` НЕ SHALL импортировать `dart:io`, `dart:isolate`, `dart:ffi`, `dart:html`, `dart:js_interop`, `package:web/`, `package:flutter/`, `package:codelab_acp_transports/io.dart`, `package:codelab_agent_io/`, `package:codelab_acp_` и `package:codelab_client_`, а также ссылаться на файлы `lib/io.dart` и `lib/src/io/`. `lib/io.dart` и `lib/src/io/` НЕ SHALL импортировать `package:flutter/`, `package:codelab_acp_` и `package:codelab_client_`. Его `dependencies` SHALL быть подмножеством `{codelab_agent_core, codelab_agent_io, meta}`.
- **Мост встроенного агента `codelab_embedded`** (design.md change `add-embedded-agent-mode`, D1–D3): файлы `lib/` вне `lib/io.dart`, `lib/src/io/`, `lib/testing.dart` и `lib/src/testing/` НЕ SHALL импортировать `dart:io`, `dart:isolate`, `dart:ffi`, `dart:html`, `dart:js_interop`, `package:web/`, `package:flutter/`, `package:codelab_acp_transports/io.dart`, `package:codelab_agent_io/` и `package:codelab_client_`, а также ссылаться на эти четыре места. Весь `lib/` НЕ SHALL импортировать `package:flutter/`, `package:fluent_ui/`, `package:codelab_ui/` и `package:codelab_client_`. Его `dependencies` SHALL быть подмножеством `{codelab_agent_core, codelab_agent_io, codelab_agent_acp, codelab_agent_mcp, codelab_acp_protocol, codelab_acp_transports, http, meta, async}`. В его `lib/` НЕ SHALL встречаться `ToolRegistry(`, `Agent(` и `AgentRuntime(` (HOST-6).
- **Расширение allowlist** любого из этих множеств SHALL проходить через OpenSpec change.
- **Клиент `apps/codelab_desktop`** НЕ SHALL импортировать `package:codelab_agent_*` напрямую; `package:codelab_embedded/io.dart` SHALL импортироваться только из `lib/app/` (composition root), а `package:codelab_embedded/testing.dart` — ни одним файлом `lib/`.

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
- **WHEN** файл в `packages/dart/codelab_client_core/lib/` импортирует `dart:io` или `package:codelab_acp_transports/io.dart`
- **THEN** сторож сообщает нарушение

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

#### Scenario: Зависимость моста встроенного агента вне allowlist
- **WHEN** в `dependencies` файла `packages/dart/codelab_embedded/pubspec.yaml` появляется `codelab_client_core`
- **THEN** `pubspec_allowlist_test.dart` падает и называет `codelab_client_core`
