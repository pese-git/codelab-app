/// Основной барель моста `codelab_setup`: настройка Dart-агента для клиентов
/// (`dart-agent-and-clients` §12.4.2; design.md changes
/// `add-agent-configuration`, D14, OQ2 (а), и `add-provider-setup-ui`, D2, D5,
/// D6, D8, D10).
///
/// Почему: клиенты (`apps/*`) не импортируют `package:codelab_agent_*`
/// напрямую (`AGENTS.md` §5), а типы конфигурации, доступ к настройкам, снимок
/// и запись конфига, проверка `/models` и удаление провайдера нужны и app, и
/// CLI. Мост реэкспортирует чистые типы ядра, как `codelab_embedded`
/// реэкспортирует `ProviderConfig`, и держит общую логику в одном месте
/// (SETUP-8).
///
/// Для чего: барель остаётся web-безопасным — ни `dart:io`, ни
/// `package:codelab_agent_io/`, ни `package:http/io_client.dart`, ни ссылок на
/// `io.dart` (правило сторожа, `melos run guard`; `melos run web-compile`
/// собирает его в JS и Wasm). Всё, что требует `dart:io`, живёт в `io.dart`.
///
/// Как использовать: `import 'package:codelab_setup/codelab_setup.dart';`.
/// - `resolveSettingsAccess(...)` — чьи настройки и какие цели записи (D5);
/// - порт `AgentConfigStore`, `AgentConfigSnapshot` и исходы `ConfigSaveOutcome`;
///   файловая реализация — `FileAgentConfigStore` в `io.dart`;
/// - модели представления: `providerEntriesOf` строит `ProviderEntryView` со
///   статусом ключа `KeyStatusView` и источником `ConfigSourceView` без чтения
///   значений;
/// - `settingFieldsOf` строит `SettingFieldView` — строки `/settings`
///   (`key value source`, источники `default|user|project|local|config|env`)
///   по реестру `SettingsRegistry` ядра; значения карт и секретов не
///   раскрываются;
/// - `ProviderCheck`/`HttpProviderCheck` — проверка `/models`; IO-фабрика —
///   `ioProviderCheck()` в `io.dart`;
/// - `ProviderRemover` — удаление провайдера одним `apply` и секрета после
///   `ConfigSaved` (SETUP-24);
/// - `SecretValue` — значение секрета, которое не печатается (SETUP-1).
///
/// Мастер провайдера, пресеты, готовность и черновик MCP-сервера придут сюда
/// со своими потребителями (итерации 3–5 change `add-provider-setup-ui`).
library;

export 'package:codelab_agent_core/codelab_agent_core.dart'
    show
        CancelToken,
        CancelTokenSource,
        ConfigConflictException,
        ConfigEdit,
        ConfigIssue,
        ConfigIssueKind,
        ConfigLayer,
        ConfigLoadResult,
        ConfigSnapshot,
        ConfigTarget,
        ConfigValueException,
        RemoveMcpServer,
        RemoveTable,
        SecretBackendInfo,
        SecretNames,
        SetValue,
        SettingDescriptor,
        SettingScope,
        SettingType,
        SettingsRegistry,
        UnsetValue,
        UpsertMcpServer,
        before1Note,
        isValidMcpServerName;
export 'src/access/settings_access.dart';
export 'src/config/agent_config_store.dart';
export 'src/config/config_source_view.dart';
export 'src/config/display_base_url.dart';
export 'src/mcp/mcp_restart.dart';
export 'src/mcp/mcp_server_committer.dart';
export 'src/mcp/mcp_server_draft.dart';
export 'src/mcp/mcp_server_remover.dart';
export 'src/mcp/mcp_transport_kind.dart';
export 'src/provider/http_provider_check.dart';
export 'src/provider/provider_check.dart';
export 'src/provider/provider_keys.dart';
export 'src/provider/provider_presets.dart';
export 'src/provider/provider_readiness.dart';
export 'src/provider/provider_remover.dart';
export 'src/provider/provider_setup_committer.dart';
export 'src/provider/provider_setup_flow.dart';
export 'src/provider/provider_setup_plan.dart';
export 'src/secret/secret_value.dart';
export 'src/views/key_status_view.dart';
export 'src/views/mcp_server_entry_view.dart';
export 'src/views/provider_entry_view.dart'
    show ProviderEntryView, providerEntriesOf;
export 'src/views/setting_field_view.dart';
