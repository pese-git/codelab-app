# AGENTS.md — codelab_setup

Правила этого пакета дополняют корневой `AGENTS.md`.

Источники:
- `docs/architecture/proposals/dart-agent-and-clients/12-4-first-run-and-settings.md` §12.4.2 — полный состав моста;
- `openspec/changes/archive/2026-10-30-add-agent-configuration/design.md` — D1, D13, D14, OQ2 (а);
- `openspec/specs/workspace-architecture/spec.md` — правило сторожа.

Если документов не хватает, сначала дополняется документация, потом пишется код.

## 1. Назначение

Мост между клиентами (`apps/codelab_cli`, позже `apps/codelab_desktop`) и настройкой Dart-агента. Клиентам нельзя импортировать `package:codelab_agent_*` (`AGENTS.md` §5), поэтому нужные типы и подкоманды приходят отсюда.

Сейчас состав минимальный:
- `lib/codelab_setup.dart` — реэкспорт чистых типов ядра `ConfigIssue`, `ConfigIssueKind`, `ConfigLoadResult`;
- `lib/io.dart` — реэкспорт `ConfigCommands`, `CheckOptions`, `ConfigCommandResult` и кодов выхода `configValidExit`, `configInvalidExit`, `configUsageExit` из `codelab_agent_io`. Логика `config check` не дублируется (D13);
- `lib/io.dart` также реэкспортирует подкоманду `secret`: `SecretCommands`, `SecretCommandResult`, `SecretSetOptions`, `SecretDeleteOptions`, `SecretListOptions`, `SecretInput`, `StdinSecretInput`, `MultilineSecretException`, а для страницы настроек — `SecretAdmin` с результатами (`SecretWriteOutcome`, `SecretDeleteOutcome`, `SecretListOutcome` и их ветки) и фабрика `openSecretStore`; для её вызова и типизации из ядра реэкспортируются `DescribedSecretStore`, `SecretStoreUnavailableException`, `Logger`, `LogLevel`. Классы `EnvSecretStore`/`FileSecretStore` и `openHostSecrets` НЕ экспортируются (`add-agent-secret-store`, D8, D15). Логика секретов живёт в `codelab_agent_io`.

## 2. Границы

* `lib/` вне `lib/io.dart` и `lib/src/io/` НЕ ДОЛЖЕН импортировать `dart:io`, `dart:isolate`, `dart:ffi`, `dart:html`, `dart:js_interop`, `package:web/`, `package:flutter/`, `package:codelab_acp_transports/io.dart`, `package:codelab_agent_io/`, `package:codelab_acp_*`, `package:codelab_client_*` и ссылаться на `lib/io.dart` и `lib/src/io/`.
* `lib/io.dart` и `lib/src/io/` НЕ ДОЛЖНЫ импортировать `package:flutter/`, `package:codelab_acp_*` и `package:codelab_client_*`.
* `dependencies` — только `codelab_agent_core`, `codelab_agent_io`, `meta` (`setupAllowlist`). Расширение — только через OpenSpec change. Проверка — `melos run guard`.
* `lib/io.dart` импортирует только composition root клиента.

## 3. Что придёт позже (§12.4.2)

Приходит со своими потребителями, без абстракций «на вырост»:
- основной барель: `ProviderSetupFlow`, пресеты, `ProviderCheck`, `ProviderReadiness`, `McpServerDraft`, `SettingsAccess`, модели представления, порт `AgentConfigStore`, остальные реэкспорты ядра (`ConfigLayer`, `ConfigSnapshot`, `ConfigEdit`, `SettingsRegistry`, `SecretStore` и др.); тогда в allowlist добавится `http` — через OpenSpec;
- `io.dart`: `FileAgentConfigStore`, пути `$CODELAB_HOME`, подкоманды `provider`/`mcp` (подкоманда `secret`, `SecretAdmin` и фабрика `openSecretStore` уже реэкспортируются, см. §1; сами бэкенды — нет);
- правило сторожа для `apps/codelab_desktop/lib/features/settings/presentation` (запрет `package:codelab_setup/io.dart`, `dart:io`; SETUP-9).

## 4. Тесты

* TDD — по `packages/dart/codelab_agent_core/AGENTS.md` §2.
* Логика `config check` тестируется в `codelab_agent_io`; здесь — компиляция реэкспортов.
