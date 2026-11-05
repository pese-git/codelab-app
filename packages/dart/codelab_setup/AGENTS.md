# AGENTS.md — codelab_setup

Правила этого пакета дополняют корневой `AGENTS.md`.

Источники:
- `docs/architecture/proposals/dart-agent-and-clients/12-4-first-run-and-settings.md` §12.4.2 — полный состав моста;
- `openspec/changes/archive/2026-10-30-add-agent-configuration/design.md` — D1, D13, D14, OQ2 (а);
- `openspec/changes/archive/2026-11-03-add-config-writer-and-reload/design.md` — D6 (реэкспорт подкоманд записи);
- design.md change `add-config-literal-secrets-and-migrate` — D7, D11, D13 (`secret migrate`, флаги stdin `mcp add`, строка о 1.0);
- design.md change `add-provider-setup-ui` — D2, D4, D5, D6, D8, D10, D20 (основной барель, `ClientSecretAccess`, доступ к настройкам, снимок и запись конфига, проверка `/models`, удаление провайдера, сторож);
- `openspec/specs/workspace-architecture/spec.md` — правило сторожа.

Если документов не хватает, сначала дополняется документация, потом пишется код.

## 1. Назначение

Мост между клиентами (`apps/codelab_cli`, позже `apps/codelab_desktop`) и настройкой Dart-агента. Клиентам нельзя импортировать `package:codelab_agent_*` (`AGENTS.md` §5), поэтому нужные типы и подкоманды приходят отсюда.

Состав (по итерациям change `add-provider-setup-ui`; итерация 2 — страница Providers):
- `lib/codelab_setup.dart` — основной барель, чистый Dart и web-безопасный (`melos run web-compile` собирает его в JS и Wasm точкой входа `test/web_smoke/main.dart`):
  - `SecretValue` — значение секрета, `toString()`/JSON дают `***`, значение только через `reveal()` (SETUP-1);
  - `resolveSettingsAccess` и `SettingsAccess` (`EditableSettings`, `RemoteReadOnly`, `NotManaged`, `ConfigPaths`, `AgentLaunchKind`) — чьи настройки читать и писать (D5); цели записи — только `user` и `projectLocal`;
  - порт `AgentConfigStore`, `AgentConfigSnapshot` (слои, итог загрузки, источники ключей `ConfigSourceView`, бэкенд секретов) и исходы `ConfigSaveOutcome` (`ConfigSaved`, `ConfigConflict`, `ConfigRejected`, `ConfigInlineSecret`) (D6);
  - модели представления: `providerEntriesOf` строит `ProviderEntryView` со статусом ключа `KeyStatusView` по именам, без чтения значения (D10);
  - `ProviderCheck`, `HttpProviderCheck` (только `package:http/http.dart`, без редиректов, тело ошибки не читается; D8), `ProviderRemover` с `SecretDeleter` — одна запись конфига, секрет удаляется только после `ConfigSaved` (SETUP-24);
  - реэкспорт только типов, которые нужны потребителям: `ConfigLayer`, `ConfigTarget`, `ConfigSnapshot`, `ConfigEdit`, `SetValue`, `RemoveTable`, `ConfigConflictException`, `ConfigIssue`, `ConfigIssueKind`, `ConfigLoadResult`, `SecretNames`, `SecretBackendInfo`, `CancelToken`, `CancelTokenSource` (владелец отмены проверки) и строка о 1.0 `before1Note` для справки `codelab` (R8-7, D13 change `add-config-literal-secrets-and-migrate`); остальное (`UpsertMcpServer`, `UnsetValue`, `RemoveMcpServer`, `SettingsRegistry`, `SettingDescriptor`, `SettingScope`, `SettingType`) приходит с потребителем — мастером, MCP и `/settings`;
  - `supportsProviderCheck(kind)` и `defaultProviderBaseUrl(kind)` — какие виды проверяются и адрес по умолчанию (SETUP-8: знание вида не в app); `ProviderEntryView.displayBaseUrl` — адрес для показа без userinfo, query и fragment;
  - `AgentConfigSnapshot.issues` — проблемы чтения конфига (`Unreadable`), `startProblems` — проблемы запуска из-за отсутствующего ключа (`agent.default_model: required` на новой установке): страница показывает пустое состояние; ключи недоверенного проекта (`config.project.untrusted_key`) не попадают ни в список, ни в источники.
- `lib/io.dart` — реэкспорт `ConfigCommands`, `CheckOptions`, `ConfigCommandResult` и кодов выхода `configValidExit`, `configInvalidExit`, `configUsageExit` из `codelab_agent_io`. Логика `config check` не дублируется (D13);
- `lib/io.dart` также реэкспортирует подкоманды записи и чтения конфига (change `add-config-writer-and-reload`, D6): `ConfigCommands` получает `path`, `get`, `set`, `unset` с опциями `ConfigPathOptions`, `ConfigGetOptions`, `ConfigSetOptions`, `ConfigUnsetOptions` и слоем чтения `ConfigGetLayer`; `ProviderCommands` (`add`, `list`, `remove`) с `ProviderAddOptions`, `ProviderListOptions`, `ProviderRemoveOptions`; `McpServerCommands` (`add`, `list`, `remove`) с `McpAddOptions`, `McpListOptions`, `McpRemoveOptions`. Результат — тот же `ConfigCommandResult`; логика, маскирование вывода и запись через `ConfigWriter` живут в `codelab_agent_io` и здесь не дублируются.
- `lib/io.dart` также реэкспортирует подкоманду `secret`: `SecretCommands`, `SecretCommandResult`, `SecretSetOptions`, `SecretDeleteOptions`, `SecretListOptions`, `SecretInput`, `StdinSecretInput`, `MultilineSecretException`, а для страницы настроек — `SecretAdmin` с результатами (`SecretWriteOutcome`, `SecretDeleteOutcome`, `SecretListOutcome` и их ветки) и фабрика `openSecretStore`; для её вызова и типизации из ядра реэкспортируются `DescribedSecretStore`, `SecretStoreUnavailableException`, `Logger`, `LogLevel`. Классы `EnvSecretStore`/`FileSecretStore` и `openHostSecrets` НЕ экспортируются (`add-agent-secret-store`, D8, D15). Логика секретов живёт в `codelab_agent_io`.
- `lib/io.dart` также содержит реализации портов основного бареля (change `add-provider-setup-ui`, D6, D8, D10): `FileAgentConfigStore` (поверх `ConfigWriter` и `ConfigLoader`; каждое исключение писателя — свой исход, `ConfigInlineSecretException` раньше `ConfigException`, конфликт не перезаписывает файл и не повторяется), `ioProviderCheck()` (`HttpProviderCheck` на `IOClient`, единственное место создания `IOClient`) и `secretDeleterOf(ClientSecretAccess)` для `ProviderRemover`.
- `lib/io.dart` также реэкспортирует клиентский доступ к секретам (change `add-provider-setup-ui`, D3, D4): `ClientSecretAccess` (`open`, `backend`, `admin`, `isSet`, `read` без кэша) и `secretReadOnlyHint(SecretReadOnly, home)` — одну подсказку про бэкенд только для чтения для `SecretCommands`, мастера и app; из ядра — `SecretBackendInfo`. Клиент читает секреты только так, прямой `openSecretStore` в клиентах не нужен. Логика — в `codelab_agent_io`.
- `lib/io.dart` также реэкспортирует `secret migrate` (change `add-config-literal-secrets-and-migrate`, D7): `SecretMigrateOptions`, движок `SecretMigrator` с `SecretMigrationOptions`, отчёт `SecretMigrationReport`, `SecretMigrationAction` и пункты (`SecretPlanItem`, `SecretMovedItem`, `SecretReusedItem`, `SecretReplacedItem`, `SecretActionRequiredItem`, `SecretNotMigratedItem`, `SecretMigrationItem`); флаги `mcp add --header-stdin|--env-stdin|--header-scheme` — поля `McpAddOptions` (D11); там же — `before1Note` (тот же, что в основном бареле).

## 2. Границы

* `lib/` вне `lib/io.dart` и `lib/src/io/` НЕ ДОЛЖЕН импортировать `dart:io`, `dart:isolate`, `dart:ffi`, `dart:html`, `dart:js_interop`, `package:web/`, `package:flutter/`, `package:codelab_acp_transports/io.dart`, `package:codelab_agent_io/`, `package:codelab_acp_*`, `package:codelab_client_*` и ссылаться на `lib/io.dart` и `lib/src/io/`.
* `lib/io.dart` и `lib/src/io/` НЕ ДОЛЖНЫ импортировать `package:flutter/`, `package:codelab_acp_*` и `package:codelab_client_*`.
* `lib/` вне `lib/io.dart` и `lib/src/io/` НЕ ДОЛЖЕН импортировать `package:http/io_client.dart` и `package:http/browser_client.dart`: основной барель использует только `package:http/http.dart` и принимает клиент снаружи; `IOClient` создаёт `ioProviderCheck()` в `lib/src/io/`.
* Для `apps/codelab_desktop` (правило сторожа, SETUP-9): `lib/features/settings/presentation` НЕ ДОЛЖЕН импортировать `package:codelab_setup/io.dart` и `dart:io`, а остальной `lib/` app — `package:codelab_setup/io.dart` вне `lib/app/`; правила уже в `rules.dart`.
* `dependencies` — только `codelab_agent_core`, `codelab_agent_io`, `http`, `meta` (`setupAllowlist`; `http` — проверка `/models`, D8, D20). Расширение — только через OpenSpec change. Проверка — `melos run guard`.
* `lib/io.dart` импортирует только composition root клиента.

## 3. Что придёт позже (§12.4.2)

Приходит со своими потребителями, без абстракций «на вырост»:
- основной барель: `ProviderSetupFlow` с пресетами и `ProviderSetupCommitter` (итерация 3), `ProviderReadiness` (итерация 4), `McpServerDraft`, `McpServerEntryView`, `SettingFieldView` (итерации 4–5), реэкспорт `SecretStore` и `DescribedSecretStore`, если их потребуют мастер и готовность;
- `io.dart`: пути `$CODELAB_HOME` вне уже реэкспортированных подкоманд (по потребности мастера CLI);

## 4. Тесты

* TDD — по `packages/dart/codelab_agent_core/AGENTS.md` §2.
* Логика `config check`, подкоманд `secret` и подкоманд записи (`config path|get|set|unset`, `provider`, `mcp`) тестируется в `codelab_agent_io`; здесь — компиляция реэкспортов (`test/config_write_exports_test.dart`: опции и классы подкоманд записи из `io.dart`, `config set`/`get` через один `io.dart`; `test/secret_exports_test.dart`: символы подкоманды `secret`, `SecretAdmin` с результатами, `openSecretStore` и типы ядра из `io.dart`; `SecretAdmin` строится через один `io.dart`; `test/secret_migrate_exports_test.dart`: символы `secret migrate` и флаги stdin `mcp add`; `test/client_secret_access_exports_test.dart`: `ClientSecretAccess` и `secretReadOnlyHint` через один `io.dart`).
* Логика самого моста тестируется здесь, на временных каталогах и фиктивных значениях (маркер `sk-test-leak-…`), без `~/.codelab`, хранилища ОС и внешней сети: `test/settings_access_test.dart`, `test/io/file_agent_config_store_test.dart` (настоящие файлы), `test/views/provider_entry_view_test.dart`, `test/http_provider_check_test.dart` (`MockClient` и сервер на loopback через `ioProviderCheck`), `test/provider_remove_test.dart` и `test/io/secret_deleter_test.dart` (удаление провайдера), `test/web_smoke_test.dart` (тот же код, что компилирует `web-compile`).
