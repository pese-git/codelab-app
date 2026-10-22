## Why

ADR-0001 принят: в этот монорепозиторий добавляется Dart-агент со встраиваемым ядром и второй ACP-клиент `codelab_cli` (`docs/architecture/proposals/dart-agent-and-clients.md`, этапы 0–10). Сейчас любое изменение проверяется только локально: CI нет, границы пакетов держатся на ревью, а публичный барель `acp_transports` экспортирует `dart:io`-транспорты, поэтому web-безопасный код не может его импортировать. Этап 0 (`dart-agent-and-clients/09-05-stage-0-foundation.md`) готовит репозиторий так, чтобы каждое следующее изменение проверялось автоматически; без него ни один этап 1–10 не начинается (веха M0 → M1, `proposals/delivery-roadmap.md`).

## What Changes

- **Конфигурация melos (0.1).** Скрипты `test:e2e:app:plan-checklist`, `test:e2e:app:prompt-queue`, `test:e2e:app:multi-session`, которые есть только в `melos.yaml`, переносятся в секцию `melos:` корневого `pubspec.yaml`; `melos.yaml` удаляется (допущение 6, проверка `melos list` до и после).
- **Разделение `acp_transports` (0.2).** Новая точка входа `package:acp_transports/io.dart` экспортирует `StdioAcpTransport` и `WebSocketAcpTransport`; классы конфигурации (`StdioAcpTransportConfig`, `StdioAcpAgentProfile`, `WebSocketAcpTransportConfig`) переезжают в `lib/src/transport_configs.dart` без `dart:io` и остаются в основном бареле. **BREAKING** для импортов внутри репозитория: код, создающий транспорты, импортирует `io.dart` (`apps/codelab_app`, `acp_testing`, тесты). Внешних потребителей нет (`publish_to: none`).
- **Пакет `codelab_agent_core` (0.3)** — пустой каркас ядра с allowlist зависимостей PKG-2 и web-smoke точкой входа.
- **Пакет `codelab_architecture_tests` (0.4)** — сторож импортов по таблице правил (PKG-1, PKG-3, PKG-4, правила клиентов) и allowlist зависимостей ядра (PKG-2), с негативным тестом.
- **Скрипты melos `guard`, `web-compile`, `test:dart` (0.5)** и их включение в `check`.
- **CI (0.6).** `.github/workflows/ci.yml` (джобы `format`, `analyze`, `test`, `conformance`, `guard`, `web-compile` и ночной `e2e-macos`), `.github/actions/prepare`, `.github/pull_request_template.md` с чек-листом (OpenSpec change, тесты, сторонний код §7а). Триггеры — под git flow (`AGENTS.md` §22): push в `master` и `develop`, все pull request.
- **Лицензия (0.9).** `LICENSE` (MIT, правообладатель — Sergey Penkovsky), `THIRD_PARTY_NOTICES.md` с форматом записи, раздел о лицензиях в `README.md` (в корне его ещё нет — создаётся).
- **`AGENTS.md` (0.11).** Корневой §5 дополняется агентскими пакетами, ссылкой на документ ядра и политикой стороннего кода; вложенный `packages/dart/codelab_agent_core/AGENTS.md` — PKG-1…PKG-6, сторож, TDD (§9.0, правило 3) и определение завершённой итерации (§9.0, правило 8).

Не входит: задача 0.10 (решение по незавершённым changes Python-агента в соседнем репозитории `codelab-agent`) — отложена, этап 0 затрагивает только Flutter/Dart-проект; корпус golden-фикстур и клиентский прогон (задачи 0.7–0.8) — отдельный change `add-acp-golden-fixture-corpus`; вместе с ним в `check` и в джоб `conformance` добавляется `conformance:client`.

## Capabilities

### New Capabilities
- `licensing-and-attribution`: лицензия репозитория (MIT), `THIRD_PARTY_NOTICES.md` и правило атрибуции воспроизведённых внешних фрагментов.

### Modified Capabilities
- `workspace-architecture`: «Границы пакетов monorepo» — состав пакетов дополняется `codelab_agent_core` и `codelab_architecture_tests`; добавляется требование об автоматическом стороже импортов и allowlist зависимостей ядра.
- `agent-transports`: добавляется требование о web-безопасном основном бареле `acp_transports` и отдельной точке входа `io.dart`.
- `testing-quality`: «Проверки workspace» — `check` включает `guard` и `web-compile`; добавляется требование о CI на pull request.

## Impact

- Корневой `pubspec.yaml` (секция `melos:`, `workspace:`), удаление `melos.yaml`.
- `packages/dart/acp_transports`: `lib/io.dart`, `lib/src/transport_configs.dart`, перегенерация `*.freezed.dart`.
- Импорты в `apps/codelab_app` (`shell_cubit.dart`, `app_scope.dart` и сгенерированный `app_scope.module.cherrypick.g.dart`, `test/widget_test.dart`, `integration_test/fs_flow_test.dart`), `packages/dart/acp_testing`, `packages/dart/acp_transports/test`.
- Новые пакеты `packages/dart/codelab_agent_core`, `packages/dart/codelab_architecture_tests`.
- Новые файлы `.github/workflows/ci.yml`, `.github/actions/prepare/action.yml`, `.github/pull_request_template.md`, `LICENSE`, `THIRD_PARTY_NOTICES.md`, `README.md`; правка `AGENTS.md`.
- Настройки GitHub: после первого зелёного прогона джобы CI добавляются в ruleset `master`/`develop` как обязательные проверки.
- Поведение приложения и ACP-контракты не меняются.
