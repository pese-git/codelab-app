## Why

Вся логика клиента ACP — подключение, сессии, очередь промптов, проекция транскрипта, одобрения, инспектор — сейчас живёт в одном `CodeLabShellCubit` (`apps/codelab_app/lib/features/workbench/application/shell_cubit.dart`, ~2300 строк) рядом с Flutter. Этап 6 (codelab_cli) и этап 7 (встроенный агент) должны использовать ту же логику без Flutter, поэтому её нужно вынести в общий пакет на чистом Dart, не меняя поведения app (`dart-agent-and-clients` §9.10, этап 5).

## What Changes

- Характеризационные тесты публичной поверхности `CodeLabShellCubit` (задача 5.0) — до первого переноса, через настоящий граф cherrypick и `FakeAcpTransport`.
- Новый пакет `packages/dart/acp_client_kit` (чистый Dart, без Flutter и `dart:io`): `ClientWorkspace`, `SessionHandle`, `WorkspaceState`/`SessionView`, явный автомат `ConnectionView`, порт `AgentBackend` и реализация `AcpClientBackend` поверх `AcpClientApplication`.
- В kit переносятся: инкрементальная проекция транскрипта `TranscriptProjector` (вместо пересчёта сессии на каждое событие), очередь промптов на сессию `PromptQueue`, профили подключения и `TransportResolver`, `CommandCatalog` (слияние клиентских и агентских команд), `ConfigOptionView`, `InspectorProjection`, диагностика с редакцией секретов.
- Новый пакет `packages/dart/acp_client_io` (`dart:io`, без Flutter): `IoTextFileIo`, `IoTerminalProcessRunner`, `IoWorkingDirectoryProvider` переезжают из `apps/codelab_app/lib/core/platform/`; резолверы stdio и WebSocket поверх `acp_transports/io.dart`; новые `JsonFileProfileStore` и `JsonFileRecentProjectsStore` для CLI.
- `CodeLabShellCubit` становится фасадом над `ClientWorkspace`, затем делится на `ConnectionCubit`, `SessionsCubit`, `ActiveSessionCubit`, `SettingsCubit`, `LayoutCubit` (задача 5.9); фасад собирает прежний `CodeLabShellState`.
- Сторож границ получает правила для `acp_client_kit` и `acp_client_io`.
- Поведение app не меняется: тексты 8 интеграционных тестов и тестов 5.0 остаются прежними. Новое поведение этапа 5 (`session/list`, `session/load` после переподключения и перезапуска, повторы переподключения, нечёткий поиск палитры, сторож запуска) — в change `add-session-list-and-reload`, `add-command-palette-agent-commands`, `add-app-boot-watchdog`.

## Capabilities

### New Capabilities
- `acp-client-kit`: общий клиентский слой без UI — рабочее пространство, сессии, очередь, проекция транскрипта, одобрения, команды, инспектор, диагностика; `dart:io`-адаптеры в `acp_client_io`.

### Modified Capabilities
- `workspace-architecture`: в monorepo появляются пакеты `acp_client_kit` и `acp_client_io`; сторож границ получает их правила.
- `testing-quality`: характеризационные тесты публичной поверхности `CodeLabShellCubit` как защита рефакторинга.

## Impact

- Новые пакеты `packages/dart/acp_client_kit`, `packages/dart/acp_client_io`; корневой `pubspec.yaml` (`workspace:`).
- `apps/codelab_app`: `shell_cubit.dart` (фасад, затем разделение), `app/app_scope.dart` (DI: `ClientWorkspace` вместо use case-ов), `core/platform/` (адаптеры переезжают в `acp_client_io`), новый `features/workbench/application/ui_mappers.dart`, новые тесты `test/features/workbench/application/shell_cubit_characterization/`.
- `packages/dart/codelab_architecture_tests`: правила и allowlist зависимостей новых пакетов.
- Документы: `AGENTS.md` §5 (структура и назначение пакетов), `docs/architecture/technology-stack.md`, `docs/architecture/state-management.md` (владелец состояния клиента), `09-10-stage-5-client-kit.md` (уточнения по итогам design).
- Зависимостей вне проекта не добавляется.
