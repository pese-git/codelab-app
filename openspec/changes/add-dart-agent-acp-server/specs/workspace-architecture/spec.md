## MODIFIED Requirements

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
