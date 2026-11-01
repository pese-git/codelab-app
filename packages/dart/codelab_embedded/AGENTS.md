# AGENTS.md — codelab_embedded

Правила этого пакета дополняют корневой `AGENTS.md` и `packages/dart/codelab_agent_core/AGENTS.md`.

Источники:
- `openspec/changes/add-embedded-agent-mode/design.md` — D1–D8 (пакет, точки входа, сторож, локальное исполнение, конфиг, жизненный цикл, сценарий модели);
- `openspec/changes/add-embedded-agent-mode/specs/embedded-agent/spec.md` — требования пакета;
- `docs/architecture/proposals/agent-core-architecture.md` §10 (сборка ядра, профили, HOST-1…HOST-7), §13.1 (`AcpServerConfig.localEnv`);
- `docs/architecture/proposals/dart-agent-and-clients/09-12-stage-7-embedded.md`.

Если документов не хватает, сначала дополняется документация, потом пишется код.

## 1. Назначение

Мост между сторонами (ADR-0002, без префикса стороны): клиенты (`apps/codelab_cli`, `apps/codelab_desktop`) получают встроенного агента, не импортируя `package:codelab_agent_*` (PKG-4). Пакет — хост ядра: он зовёт `buildAgentCore` и `AcpAgentServer` и соединяет агента с клиентом парой `InProcessAcpLink`. Клиентской логики и резолвера транспорта в нём нет — резолвер живёт в composition root клиента (D1).

Точки входа (D2):
- `lib/codelab_embedded.dart` — основной барель, web-безопасный: `createEmbeddedAgent`, `EmbeddedAgent`, `EmbeddedAgentOpener`, `EmbeddedAgentConfig`, `EmbeddedHostServices`, `EmbeddedAgentConfigException`, а из ядра только `Logger` и `LogLevel`;
- `lib/io.dart` — настольный открыватель `localEmbeddedAgentOpener({environment, logger, debugSecrets, httpClient})` (`ConfigLoader` → `openHostSecrets` → `JsonlSessionStore`, `LocalExecutionEnv`, `ProjectFilesLoader`, `McpClientConnector` → `createEmbeddedAgent`). Невалидный конфиг — `EmbeddedAgentConfigException` до создания HTTP-клиента; `CODELAB_TEST_SECRET_STORE` читается только в сборке с `-DCODELAB_ALLOW_TEST_SECRETS=true`;
- `lib/testing.dart` — `scriptedEmbeddedAgentOpener` со сценарием модели; код сценария и слой провайдеров сценария — `LlmScript` и `withScriptedProviders` из `package:codelab_agent_io/testing.dart` (D8); основной барель `codelab_agent_io` их не экспортирует.

Жизненный цикл (D6, `lib/src/assemble.dart`): `serve` и вся асинхронная работа агента идут в охраняемой зоне `runZonedGuarded`; отказ (необработанная ошибка зоны или `serve`) пишет `embedded.agent.failed {error_class}` уровня `error` без текста ошибки, закрывает агентский конец и запускает `dispose`; повторные ошибки после начала остановки — `embedded.agent.late_error {error_class}` (`warning`). `dispose` идемпотентен, шаги в своих `try` (`embedded.agent.dispose_failed {step, error_class}` уровня `error`).

Профили: `createEmbeddedAgent` принимает только `embedded-app-desktop` и `embedded-cli`. Профиль `agent-serve` и режим разрешений принимает только `testing.dart`. Профили `embedded-*` исполняют файлы и команды сами (`AcpServerConfig.localEnv`, D4); `fs/*` и `terminal/*` клиенту не уходят.

## 2. Границы

* Основной барель и всё, что он тянет, НЕ ДОЛЖНЫ импортировать `dart:io`, `dart:isolate`, `dart:ffi`, `dart:html`, `dart:js_interop`, `package:web/`, `package:flutter/`, `package:codelab_acp_transports/io.dart`, `package:codelab_agent_io/`, `package:codelab_client_*` и ссылаться на `lib/io.dart`, `lib/src/io/`, `lib/testing.dart`, `lib/src/testing/`. Проверка — `melos run guard` (`rules.dart`, два правила `packages/dart/codelab_embedded`).
* `io.dart`, `testing.dart` и их `src/`-каталоги не импортируют Flutter, `fluent_ui`, `codelab_ui` и `codelab_client_*`.
* `dependencies` — только подмножество `embeddedAllowlist`: `codelab_agent_core`, `codelab_agent_io`, `codelab_agent_acp`, `codelab_agent_mcp`, `codelab_acp_protocol`, `codelab_acp_transports`, `http`, `meta`, `async`. Расширение — только через OpenSpec change. Проверка — `pubspec_allowlist_test.dart`.
* Ядро собирается только через `buildAgentCore` (HOST-6): в `lib/` нет `ToolRegistry(`, `Agent(`, `AgentRuntime(` (`host_assembly_guard_test.dart`).
* `http.Client`, `Clock`, `Random` и `IdGenerator` приходят от хоста через `EmbeddedHostServices` (PKG-6); пакет сам их не создаёт, кроме `io.dart` (настольный хост, `localEmbeddedAgentOpener`) и `testing.dart`.
* Методов, полей и состояний ACP пакет не добавляет; `agentInfo` — как у бинаря `codelab-agent` (D4).
* Основной барель и `io.dart` не принимают функцию модели, сценарий и `PermissionGate`: разрешения идут клиенту через `AcpPermissionGate`.

## 3. Тесты

* TDD — по `packages/dart/codelab_agent_core/AGENTS.md` §2: красный тест по критерию спецификации, затем код. Пункты `tasks.md` change идут парами.
* Агент в тестах открывается `scriptedEmbeddedAgentOpener` во временном каталоге; клиент — тестовый ACP-клиент на клиентском конце пары (`test/support/acp_client.dart`), без `codelab_client_*`. Сети нет, часы и id — фейки или системные по умолчанию открывателя; синхронизация — событиями, а не `Future.delayed`.
* `test/web_smoke/main.dart` — точка входа `melos run web-compile` (JS и Wasm); на Dart VM тот же код проверяет `web_smoke_test.dart`.
* Тесты процессов и файлов идут на Dart VM и входят в `melos run check`; в ветках `feature/*` и `hotfix/*` других прогонов не нужно (корневой `AGENTS.md` §21).

## 4. Готовность итерации (dart-agent-and-clients §9.0, правило 7)

Итерация завершена, когда выполнены условия (а)–(е) из `packages/dart/codelab_agent_core/AGENTS.md` §3. Для этого пакета отдельно:
* (в) PR называет следующую итерацию и точку, куда встаёт её функция: итерации 3 (CLI) и 4 (desktop) вызывают `localEmbeddedAgentOpener` из `io.dart` в composition root клиента и `scriptedEmbeddedAgentOpener` из `testing.dart` в тестах; контракты `EmbeddedAgent` и `EmbeddedHostServices` расширяются без изменения сигнатур;
* (г) новая функция встаёт в точку расширения (`EmbeddedHostServices`, профиль, открыватель), а не условием в `assembleEmbeddedAgent`.
