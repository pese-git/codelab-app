# 2. Факты о текущей системе

> Часть предложения [«Dart-агент и клиенты CodeLab»](../dart-agent-and-clients.md). Status: Accepted. Исходные решения, связанные документы и порядок чтения — в оглавлении.

← [1. Исходные решения и требования](01-decisions-and-requirements.md) · [Оглавление](../dart-agent-and-clients.md) · [3. Рассмотренные варианты](03-options-considered.md) →

Проверено по коду (не допущения):

| Факт | Где проверено | Следствие для решения |
|---|---|---|
| Модели `acp_protocol` имеют и `fromJson`, и `toJson` (session, prompt, initialize, tool_call, terminal, fs, permission, session_update); есть таблица методов `AcpMethodDefinition` с `decodeParams`/`encodeResult` | `packages/dart/acp_protocol/lib/src/acp/*.dart`, `acp_method_codec.dart` | серверная сторона ACP переиспользует пакет; вторая ручная копия моделей (Python) исчезает вместе с классом несовместимостей между своими же проектами |
| `JsonRpcMessage` — sealed freezed-класс (`request`/`notification`/`response`), `params` и `result` имеют тип `Object?` (JSON-подобные `Map`/`List`); кодек — `encodeJsonRpcMessage`/`decodeJsonRpcMessage` | `acp_protocol/lib/src/json_rpc/` | in-process транспорт передаёт объекты без строкового кодирования, но обязан защищаться от общих изменяемых `Map` (§9.12) |
| Интерфейс `AcpTransport`: `inbound`, `events`, `state`, `start()`, `send()`, `close({timeout})`; `AcpTransportFactory = FutureOr<AcpTransport> Function()` | `acp_transports/lib/src/acp_transport.dart`, `acp_client_core/lib/src/application/application_models.dart` | in-process режим реализуется как ещё один транспорт без изменения `AcpClientApplication` |
| Барель `package:acp_transports/acp_transports.dart` экспортирует `StdioAcpTransport` (импортирует `dart:io`) и `WebSocketAcpTransport` (импортирует `web_socket_channel/io.dart`) | `acp_transports/lib/acp_transports.dart`, `src/stdio_acp_transport.dart`, `src/websocket_acp_transport.dart` | **всё, что импортирует барель, не собирается для web**, включая `acp_client_core`. Барель нужно разделить на платформенно-нейтральную часть и `io.dart` (этап 0) |
| `acp_protocol`, `acp_client_core` написаны без Flutter | `pubspec.yaml` пакетов | пакеты подходят для CLI и агента; для web — после разделения `acp_transports` |
| `AcpClientApplication` умеет `connect`, `createSession`, `loadSession`, `setSessionConfigOption`, `sendPrompt`, `cancelTurn`, `reconnect`, `respondToPermission`, `dispose`; метода для `session/list` нет; таймаута на запрос нет (есть только таймаут закрытия транспорта) | `acp_client_core/lib/src/application/acp_client_application.dart` | `listSessions` и таймауты запросов добавляются на этапе 5 |
| `CodeLabShellCubit` — 2264 строки, импортирует `acp_ui`, `fluent_ui`, `flutter_bloc` и держит всю клиентскую логику: профили, подключение, очередь промптов, проекцию транскрипта, инспектор, палитру команд | `apps/codelab_app/lib/features/workbench/application/shell_cubit.dart` | терминальный клиент не может переиспользовать логику; нужен пакет `acp_client_kit` (этап 5) |
| В app нет ни одного вызова `loadSession`: после переподключения и перезапуска история сессии не восстанавливается | поиск по `apps/codelab_app/lib` | `session/load` после reconnect и список сессий — задача этапа 5 |
| Проекция транскрипта пересчитывается из `turn.updates` целиком на каждое изменение сессии; подряд идущие чанки сообщений и мыслей склеиваются | `_agentTranscriptEntries`, `_transcriptEntriesForSession` в `shell_cubit.dart` | в `acp_client_kit` проекция становится инкрементальной; правила склейки сохраняются |
| Профиль агента по умолчанию — `codelab serve --stdio` (Python-агент) | `codelabAgentStdioProfile` в `acp_transports/lib/src/stdio_acp_transport.dart` | после перехода команда `codelab` принадлежит CLI; профиль по умолчанию меняется на `codelab-agent serve --stdio` (этап 9) |
| Платформенные адаптеры клиента лежат в app: `IoTextFileIo`, `IoTerminalProcessRunner`, `IoWorkingDirectoryProvider` (`dart:io`), `SharedPreferencesRecentProjectsStore` (Flutter-плагин), `FileSelectorProjectFolderPicker` (Flutter-плагин) | `apps/codelab_app/lib/core/platform/` | в `acp_client_io` переезжают только `dart:io`-адаптеры; плагинные остаются в app |
| 8 интеграционных тестов app на macOS запускают scripted stdio-агента `writeCodelabCompatibleStdioAgent` (15 режимов: `normal`, `withPermissionRequest`, `withFsAccess`, `withTerminalKill`, `withPlan`, …) через `CODELAB_E2E_DART`; тесты читают `codeLabDependenciesOf(...).shellCubit.state` | `apps/codelab_app/integration_test/`, `acp_testing/lib/src/codelab_compatible_stdio_agent.dart` | на этапе 5 публичный API и состояние `CodeLabShellCubit` сохраняются (фасад), иначе тесты не защищают рефакторинг |
| Есть conformance-тест протокола и тестовые утилиты (`FakeAcpTransport`, `FakeTerminalProcessRunner`, scripted stdio-агент), но **корпуса golden ACP-фикстур нет** | `acp_protocol/test/protocol_conformance_test.dart`, `acp_testing/lib/src/` | корпус фикстур создаётся на этапе 0 и становится эталоном поведения |
| CI нет: каталога `.github/` в репозитории нет | корень репозитория | CI для всего монорепозитория создаётся на этапе 0 |
| Скрипты melos описаны дважды: в `melos.yaml` и в секции `melos:` корневого `pubspec.yaml` (melos 8, pub workspaces); в `pubspec.yaml` нет трёх скриптов e2e (`plan-checklist`, `prompt-queue`, `multi-session`) | `melos.yaml`, `pubspec.yaml` | на этапе 0 конфигурация сводится в одно место — секцию `melos:` в `pubspec.yaml` |
| Flutter SDK закреплён FVM: 3.47.0 | `.fvmrc`, `.fvm/fvm_config.json` | CI ставит SDK через FVM, а не отдельной версией |
| App Sandbox у codelab-app выключен (`com.apple.security.app-sandbox = false`) | `apps/codelab_app/macos/Runner/Release.entitlements` | встроенное ядро на macOS может запускать процессы (shell) так же, как сейчас запускает агента |
| В репозитории нет файлов LICENSE и NOTICE | корень репозитория | лицензия — MIT (решено, §11); `LICENSE` и `THIRD_PARTY_NOTICES.md` добавляются на этапе 0 (задача 0.9, §7а) |
| Python-агент — около 93 тыс. строк, но значительная часть — Context Manager, техдолг, Python TUI и Web UI | репозиторий `codelab-agent` | объём переписывания существенно меньше: TUI, Web UI и legacy-пути не переносятся |

---

← [1. Исходные решения и требования](01-decisions-and-requirements.md) · [Оглавление](../dart-agent-and-clients.md) · [3. Рассмотренные варианты](03-options-considered.md) →
