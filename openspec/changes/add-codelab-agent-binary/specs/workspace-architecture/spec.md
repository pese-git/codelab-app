## MODIFIED Requirements

### Requirement: Границы пакетов monorepo
CodeLab SHALL использовать Dart/Flutter/FVM/Melos monorepo с разделёнными пакетами `acp_protocol`, `acp_transports`, `acp_client_core`, `acp_testing`, `acp_ui`, `codelab_app`. В нём также SHALL быть пакеты Dart-агента `codelab_agent_core`, `codelab_agent_io` и `codelab_agent_acp`, приложение бинаря агента `apps/codelab_agent` (чистый Dart) и пакет архитектурных проверок `codelab_architecture_tests`. Каждый пакет SHALL быть указан в `workspace:` корневого `pubspec.yaml`.

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

### Requirement: Автоматический сторож границ пакетов
CodeLab SHALL проверять границы пакетов тестом `packages/dart/codelab_architecture_tests`, а не только ревью.

Сторож SHALL:
- обходить все файлы `lib/**/*.dart` каждого пакета из единой таблицы правил, включая файлы `part` и точки входа верхнего уровня;
- разбирать директивы `import`, `export`, `part` и каждую альтернативу условного импорта;
- сообщать каждое нарушение в виде `файл:строка -> URI`.

Правила пакетов:
- **`codelab_agent_core`** НЕ SHALL импортировать `dart:io`, `dart:isolate`, `dart:ffi`, `dart:html`, `dart:js_interop`, `package:web/`, `package:flutter/`, `package:acp_protocol/` и `package:acp_transports/`. Его `dependencies` SHALL быть подмножеством `{http, meta, collection, async, crypto}`.
- **`codelab_agent_io`** НЕ SHALL импортировать `package:flutter/` и `package:acp_`. Его `dependencies` SHALL быть подмножеством `{codelab_agent_core, path, meta, async, yaml, yaml_edit, toml}`.
- **`codelab_agent_acp`** НЕ SHALL импортировать `dart:io`, `dart:isolate`, `dart:ffi`, `dart:html`, `dart:js_interop`, `package:web/`, `package:flutter/` и `package:acp_transports/io.dart` (PKG-3). Его `dependencies` SHALL быть подмножеством `{codelab_agent_core, acp_protocol, acp_transports, meta, async}`.
- **Бинарь `apps/codelab_agent`** НЕ SHALL импортировать `package:flutter/`, `package:fluent_ui/`, `package:acp_client_core/` и `package:acp_ui/`. Его `dependencies` SHALL быть подмножеством `{codelab_agent_core, codelab_agent_io, codelab_agent_acp, acp_protocol, acp_transports, args, http, async, meta}`. В его `lib/` и `bin/` НЕ SHALL встречаться `ToolRegistry(`, `Agent(` и `AgentRuntime(`: ядро собирается только через `buildAgentCore` (HOST-6).
- **Расширение allowlist** любого из этих множеств SHALL проходить через OpenSpec change.
- **Клиент `apps/codelab_app`** НЕ SHALL импортировать `package:codelab_agent_*` напрямую.

#### Scenario: Нарушение в ядре обнаружено
- **WHEN** файл в `packages/dart/codelab_agent_core/lib/` импортирует `dart:io`, в том числе как альтернативу условного импорта
- **THEN** `fvm dart run melos run guard` падает и указывает файл, строку и запрещённый URI

#### Scenario: Сторож сам проверен на нарушении
- **WHEN** запускается негативный тест сторожа на временном пакете с `import 'a.dart' if (dart.library.io) 'dart:io';`
- **THEN** сканер возвращает ровно одно нарушение `lib/src/x.dart:1 -> dart:io`

#### Scenario: Зависимость вне allowlist
- **WHEN** в `dependencies` файла `packages/dart/codelab_agent_core/pubspec.yaml` или `packages/dart/codelab_agent_io/pubspec.yaml` появляется пакет вне allowlist этого пакета
- **THEN** `pubspec_allowlist_test.dart` падает и называет лишний пакет

#### Scenario: IO-пакет агента импортирует ACP
- **WHEN** файл в `packages/dart/codelab_agent_io/lib/` импортирует `package:acp_protocol/`
- **THEN** сторож сообщает нарушение

#### Scenario: Клиент импортирует ядро напрямую
- **WHEN** файл в `apps/codelab_app/lib/` импортирует `package:codelab_agent_core/`
- **THEN** сторож сообщает нарушение

#### Scenario: ACP-адаптер импортирует dart:io
- **WHEN** файл в `packages/dart/codelab_agent_acp/lib/` импортирует `dart:io` или `package:acp_transports/io.dart`
- **THEN** сторож сообщает нарушение

#### Scenario: Бинарь собирает ядро вручную
- **WHEN** файл в `apps/codelab_agent/lib/` содержит `AgentRuntime(`
- **THEN** сторож падает и называет файл и строку (HOST-6)
