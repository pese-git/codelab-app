# CodeLab

Monorepo CodeLab на Dart и Flutter: desktop-клиент **codelab-app** для работы с AI-агентами по ACP (Agent Client Protocol) и встраиваемое ядро Dart-агента, которое подключается к клиентам через ACP. Решение и план — ADR-0001 (`docs/architecture/adr/0001-embed-dart-agent-core-behind-acp.md`) и дорожная карта `docs/architecture/proposals/delivery-roadmap.md`.

## Структура

| Путь | Что это |
|---|---|
| `apps/codelab_app` | Flutter Desktop клиент ACP |
| `packages/dart/acp_protocol` | типизированные модели ACP JSON-RPC, кодеки и валидация |
| `packages/dart/acp_transports` | транспорты ACP; `io.dart` — stdio и WebSocket |
| `packages/dart/acp_client_core` | domain, состояние и use cases ACP-клиента |
| `packages/dart/acp_testing` | fake-транспорты, фикстуры и помощники conformance-тестов |
| `packages/dart/codelab_agent_core` | ядро Dart-агента на чистом Dart |
| `packages/dart/codelab_architecture_tests` | сторож границ пакетов |
| `packages/flutter/acp_ui` | Fluent UI виджеты рабочего места |
| `openspec/` | спецификации поведения и активные изменения |
| `docs/` | архитектура, спецификация ACP, интеграции |

## Начало работы

Flutter SDK закреплён в `.fvmrc` и ставится через [FVM](https://fvm.app); monorepo управляется [Melos](https://melos.invertase.dev) из секции `melos:` корневого `pubspec.yaml`.

```bash
fvm install
fvm flutter pub get
fvm dart run melos exec -c 1 --depends-on=build_runner -- "fvm dart run build_runner build --delete-conflicting-outputs"
fvm dart run melos run check
```

Сгенерированный код (`*.freezed.dart`) в git не хранится — третья команда создаёт его после checkout. `check` запускает формат, анализ, сторож архитектуры, тесты, protocol conformance и web-компиляцию ядра; интеграционные тесты в `feature/*` и `hotfix/*` идут только на Dart VM. Прогон приложения на устройстве или симуляторе — `fvm dart run melos run test:e2e:app:<имя>` (список — `fvm dart run melos run --list`) — выполняется только в ветке `release/<version>` (`AGENTS.md` §21).

## Правила разработки

- Обязательные правила для разработчиков и AI-агентов — `AGENTS.md`.
- Архитектура — `docs/architecture/README.md`; ядро агента — `docs/architecture/proposals/agent-core-architecture.md`.
- Поведение продукта — `openspec/specs/`; изменения — через OpenSpec change (`AGENTS.md` §17).
- Ветвление — git flow: `feature/*` от `develop`, pull request в `develop` (`AGENTS.md` §22).

## Лицензия

Код распространяется по лицензии MIT — см. [`LICENSE`](LICENSE). Учёт воспроизведённых внешних фрагментов — [`THIRD_PARTY_NOTICES.md`](THIRD_PARTY_NOTICES.md).
