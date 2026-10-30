## MODIFIED Requirements

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
- **Терминальный клиент `apps/codelab_cli`** НЕ SHALL импортировать `package:flutter/`, `package:fluent_ui/`, `package:codelab_ui/` и `package:codelab_agent_`. Его `dependencies` SHALL быть подмножеством `{codelab_client_core, codelab_client_io, codelab_client_acp, codelab_acp_protocol, codelab_acp_transports, codelab_acp_testing, codelab_setup, dart_tui, args, async, path, meta}`; `package:codelab_acp_testing/` SHALL импортироваться только из `lib/src/scenario/`; `package:dart_tui/` SHALL импортироваться только из `lib/src/tui/`, `package:codelab_setup/io.dart` — только из `lib/src/run.dart` (правило сторожа), а файлы ядра экрана `lib/src/tui/core/` НЕ SHALL импортировать ни `package:dart_tui/`, ни `dart:io`.
- **Мост `codelab_setup`** (настройки агента для клиентов, `dart-agent-and-clients` §12.4.2): файлы `lib/` вне `lib/io.dart` и `lib/src/io/` НЕ SHALL импортировать `dart:io`, `dart:isolate`, `dart:ffi`, `dart:html`, `dart:js_interop`, `package:web/`, `package:flutter/`, `package:codelab_acp_transports/io.dart`, `package:codelab_agent_io/`, `package:codelab_acp_` и `package:codelab_client_`, а также ссылаться на файлы `lib/io.dart` и `lib/src/io/`. `lib/io.dart` и `lib/src/io/` НЕ SHALL импортировать `package:flutter/`, `package:codelab_acp_` и `package:codelab_client_`. Его `dependencies` SHALL быть подмножеством `{codelab_agent_core, codelab_agent_io, meta}`.
- **Расширение allowlist** любого из этих множеств SHALL проходить через OpenSpec change.
- **Клиент `apps/codelab_desktop`** НЕ SHALL импортировать `package:codelab_agent_*` напрямую.

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
