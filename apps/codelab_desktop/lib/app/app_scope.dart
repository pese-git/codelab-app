// ignore_for_file: experimental_member_use

import 'dart:async';
import 'dart:io';
import 'dart:ui' show PlatformDispatcher;

import 'package:codelab_client_acp/codelab_client_acp.dart';
import 'package:codelab_client_io/codelab_client_io.dart'
    show
        DirectoryExists,
        JsonFileProfileStore,
        IoTerminalProcessRunner,
        IoProjectFiles,
        IoTextFileIo,
        ioDirectoryExists;
import 'package:codelab_client_core/codelab_client_core.dart'
    show
        AcpClientBackend,
        ClientWorkspace,
        ConfigTransportResolver,
        InMemoryThemeLibrary,
        ThemeLibrary,
        ProfileSecretSource,
        ProfileSecrets,
        ProfileStore,
        ProjectFiles,
        RecentProjectsStore,
        SecretSource,
        TransportResolver,
        WorkspaceSnapshotStore,
        profileKindsFor;
import 'package:codelab_acp_transports/codelab_acp_transports.dart';
import 'package:codelab_acp_transports/io.dart';
import 'package:codelab_embedded/codelab_embedded.dart'
    as agent
    show EmbeddedAgentOpener, LogLevel, Logger;
// IO-барель встроенного агента разрешён сторожем только в `lib/app/`
// (design.md change `add-embedded-agent-mode`, D3): композиция — единственное
// место, которое знает настольный открыватель.
import 'package:codelab_embedded/io.dart' show localEmbeddedAgentOpener;
// IO-барель моста настроек разрешён сторожем только в `lib/app/` (design.md
// change `add-provider-setup-ui`, D20): проверка `/models` страницы Providers.
import 'package:codelab_setup/io.dart' as setup_io show ioProviderCheck;
import 'package:codelab_setup/codelab_setup.dart'
    show
        AgentLaunchKind,
        EditableSettings,
        ProviderWizardEntry,
        resolveSettingsAccess;
import 'package:cherrypick/cherrypick.dart';
import 'package:cherrypick_annotations/cherrypick_annotations.dart';
import 'package:fluent_ui/fluent_ui.dart';
import 'package:flutter/foundation.dart' show kDebugMode;
import 'package:path/path.dart' as p;
import 'package:structured_log/io.dart' as structured_log_io;
import 'package:structured_log/structured_log.dart' as structured_log;
import 'package:structured_log_flutter/structured_log_flutter.dart'
    show LogBuffer;
import 'package:structured_log_remote_sync/structured_log_remote_sync.dart'
    show RemoteSyncLogOutput;

import '../core/platform/connection_preferences.dart';
import '../core/platform/dock_layout_store.dart';
import '../core/platform/external_link_opener.dart';
import '../core/platform/local_folder_opener.dart';
import '../core/platform/limited_network_image.dart';
import '../core/platform/project_folder_picker.dart';
import '../core/platform/usage_csv_saver.dart';
import '../core/platform/shared_preferences_recent_projects_store.dart';
import '../core/platform/shared_preferences_workspace_snapshot_store.dart';
import '../core/platform/startup_preferences.dart';
import '../core/platform/user_shell_launcher.dart';
import '../features/project_files/application/project_files_cubit.dart';
import '../features/settings/application/add_profile_cubit.dart';
import '../features/settings/application/connection_settings_cubit.dart';
import '../features/settings/application/default_profile_resolver.dart';
import '../features/settings/application/embedded_profile.dart';
import '../features/settings/application/profiles_unavailable.dart';
import '../features/settings/application/agent_defaults_cubit.dart';
import '../features/settings/application/about_diagnostics.dart';
import '../features/settings/application/about_ports.dart';
import '../features/settings/application/agents_modes_cubit.dart';
import '../features/settings/application/startup_settings_cubit.dart';
import '../features/settings/application/mcp_settings_cubit.dart';
import '../features/settings/application/skills_settings_cubit.dart';
import '../features/settings/application/provider_settings_cubit.dart';
import '../features/settings/application/provider_wizard_cubit.dart';
import '../features/terminal/application/terminal_tabs_cubit.dart';
import '../features/terminal/presentation/terminal_output_flusher.dart';
import '../features/workbench/application/project_paths.dart'
    show isFilesystemRoot;
import '../features/workbench/application/secret_migration_cubit.dart';
import '../features/workbench/application/secret_migration_runner.dart';
import '../features/workbench/application/secret_migration_turns.dart';
import '../features/workbench/application/shell_cubit.dart';
import 'app_exit_handler.dart';
import 'client_profile_secrets.dart'
    show DescribedProfileSecrets, UnavailableProfileSecrets;
import 'reopenable_profile_secrets.dart';
import 'default_settings_pages.dart';
import 'about_ports_factory.dart';
import 'build_version.dart';
import 'embedded_logger.dart';
import 'embedded_mcp_status_source.dart';
import 'embedded_secret_migration_runner.dart';
import 'embedded_transport_resolver.dart';
import 'agent_definitions_loader.dart';
import 'provider_settings_session.dart';
import 'provider_setup_offer.dart';
import 'provider_setup_probe.dart';
import 'navigation/navigation_cubit.dart';
import 'navigation/settings_page.dart';
import 'navigation/settings_page_store.dart';
import 'connection_environment.dart';
import 'secret_migration_offer.dart';

import 'appearance/app_appearance_cubit.dart';
import 'appearance/app_appearance_start.dart';
import 'appearance/built_in_themes.dart' show kBuiltInThemeIds;
import '../core/platform/app_appearance_preferences.dart';
import '../core/platform/system_accent_source.dart';
import '../core/platform/app_menu_bridge.dart';
import '../core/platform/home_path_label.dart';
import '../core/platform/theme_file_picker.dart';
import '../features/settings/application/appearance_settings_cubit.dart';
import 'language/app_language_cubit.dart' show AppLanguageCubit, AppStrings;
import 'language/app_language_start.dart';
import '../core/platform/app_language_preferences.dart';

part 'app_scope.module.cherrypick.g.dart';

typedef CodeLabTransportFactory = AcpTransport Function();

Scope createCodeLabRootScope({
  // Начальное состояние языка (шов D2, `add-desktop-localization`): `main`
  // читает предпочтение до `runApp`, поэтому первый кадр сразу на нужном
  // языке. Без шва — `en` (тесты и хосты без предпочтения).
  AppLanguageStart? language,
  AppLanguagePreferences? languagePreferences,
  // Шов оформления (`add-app-appearance-page`, D13): `main` читает документ и
  // файлы тем до `runApp`. Без шва — значения по умолчанию.
  AppAppearanceStart? appearance,
  AppAppearancePreferences? appearancePreferences,
  ThemeLibrary? themeLibrary,
  SystemAccentSource? systemAccentSource,
  // Шов порта выбора файла темы страницы «Appearance» (D9).
  ThemeFilePicker? themeFilePicker,
  // Шов порта настроек запуска (D9).
  StartupPreferences? startupPreferences,
  // Данные раздела «About» (D11): шов тестов, без него — версия сборки,
  // `BuildInfo` и ресурсы `assets/legal/`.
  AboutInfo? aboutInfo,
  CodeLabTransportFactory? transportFactory,
  CodeLabStdioTransportFactory? stdioTransportFactory,
  CodeLabWebSocketTransportFactory? webSocketTransportFactory,
  String? logDirectoryPath,
  DirectoryExists? directoryExists,
  agent.EmbeddedAgentOpener? embeddedOpener,
  Duration? embeddedCloseTimeout,
  Map<String, String>? environment,
  SettingsPages? settingsPages,
  ProfileStore? profileStore,
  ProfileSecrets? profileSecrets,
  Future<ProfileSecrets> Function()? profileSecretsOpener,
  ProviderSettingsOpener? providerSettingsOpener,
  Future<bool> Function(String cwd)? providerSetupProbe,
  UserShellLauncher? userShellLauncher,
  ExternalLinkOpener? externalLinkOpener,
  LocalFolderOpener? localFolderOpener,
  ProjectFolderPicker? projectFolderPicker,
  UsageCsvSaver? usageCsvSaver,
  ProjectFiles? projectFiles,
  bool projectFilesEnabled = true,
}) {
  // Одно окружение на открыватель встроенного агента, профили и токены:
  // `CODELAB_HOME` и переменные читаются из одного места (design.md change
  // `add-app-settings-shell`, D7, D15).
  final connectionEnvironment = ConnectionEnvironment.of(
    environment ?? Platform.environment,
  );
  final scope = CherryPick.openRootScope()
    ..installModules([
      CodeLabLoggingModule(
        // `path_provider`'s app-support directory is resolved async, before
        // `runApp()`, in `main.dart` — this fallback only covers callers
        // that skip that step (tests constructing the scope directly).
        logDirectoryPath: logDirectoryPath ?? Directory.systemTemp.path,
      ),
      CodeLabTransportRuntimeModule(
        transportFactory: transportFactory ?? _createDefaultTransport,
        stdioTransportFactory: stdioTransportFactory ?? _createStdioTransport,
        webSocketTransportFactory:
            webSocketTransportFactory ?? _createWebSocketTransport,
      ),
      CodeLabEmbeddedAgentModule(
        embeddedOpener: embeddedOpener,
        closeTimeout: embeddedCloseTimeout,
        environment: connectionEnvironment.variables,
        providerSetupProbe: providerSetupProbe,
      ),
      CodeLabLanguageModule(
        language: language,
        preferences: languagePreferences,
      ),
      CodeLabAppearanceModule(
        appearance: appearance,
        preferences: appearancePreferences,
        library: themeLibrary,
        accentSource: systemAccentSource,
      ),
      CodeLabPlatformModule(
        directoryExists: directoryExists ?? ioDirectoryExists,
        userShellLauncher: userShellLauncher,
        externalLinkOpener: externalLinkOpener,
        localFolderOpener: localFolderOpener,
        projectFolderPicker: projectFolderPicker,
        usageCsvSaver: usageCsvSaver,
        themeFilePicker: themeFilePicker,
        startupPreferences: startupPreferences,
      ),
      CodeLabConnectionModule(
        environment: connectionEnvironment,
        profileStore: profileStore,
        profileSecrets: profileSecrets,
        profileSecretsOpener: profileSecretsOpener,
      ),
      CodeLabPresentationModule(
        settingsPages: settingsPages ?? defaultSettingsPages,
        providerSettingsOpener: providerSettingsOpener,
        projectFiles: projectFilesEnabled
            ? (projectFiles ?? const IoProjectFiles())
            : null,
        aboutInfo: aboutInfo,
        // Тот же каталог, что получает `CodeLabLoggingModule` (D14).
        logDirectory: logDirectoryPath ?? Directory.systemTemp.path,
      ),
      $CodeLabTransportsModuleContract(),
      $CodeLabProtocolApplicationModuleContract(),
      $CodeLabRootLifecycleModuleContract(),
    ]);

  scope.resolve<CodeLabRootLifecycle>();
  // Объект сброса вывода терминала создаётся сразу: он вешает крючок на Cubit
  // (D3); закрывает его `dispose` вместе со scope.
  scope.resolve<TerminalOutputFlusher>();
  // Resolved once so CherryPick's Scope.dispose() tracks it as a
  // Disposable and awaits its flush on shutdown — see
  // CodeLabLoggingLifecycle's doc comment.
  scope.resolve<CodeLabLoggingLifecycle>();
  return scope;
}

Future<void> closeCodeLabRootScope() => CherryPick.closeRootScope();

CodeLabDependencies codeLabDependenciesOf(BuildContext context) =>
    CodeLabDependenciesScope.of(context);

final class CodeLabTransportRuntimeModule extends Module {
  CodeLabTransportRuntimeModule({
    required CodeLabTransportFactory transportFactory,
    required CodeLabStdioTransportFactory stdioTransportFactory,
    required CodeLabWebSocketTransportFactory webSocketTransportFactory,
  }) : _transportFactory = transportFactory,
       _stdioTransportFactory = stdioTransportFactory,
       _webSocketTransportFactory = webSocketTransportFactory;

  final CodeLabTransportFactory _transportFactory;
  final CodeLabStdioTransportFactory _stdioTransportFactory;
  final CodeLabWebSocketTransportFactory _webSocketTransportFactory;

  @override
  void builder(Scope currentScope) {
    bind<CodeLabTransportFactory>().toInstance(_transportFactory);
    bind<CodeLabStdioTransportFactory>().toInstance(_stdioTransportFactory);
    bind<CodeLabWebSocketTransportFactory>().toInstance(
      _webSocketTransportFactory,
    );
  }
}

/// Сколько `CodeLabRootLifecycle` ждёт закрытие встроенного агента: больше
/// grace 5 с у `server.shutdown` агента, как в CLI (design.md change
/// `add-embedded-agent-mode`, D6, «Выход CLI»; решение пользователя
/// итерации 4).
const defaultEmbeddedCloseTimeout = Duration(seconds: 10);

/// Предел корректного закрытия транспорта ядра клиента при закрытии root
/// lifecycle (в том числе при выходе из app): закрыть stdin → ждать этот срок
/// → `SIGTERM` → ещё 2 с → `SIGKILL` (`StdioAcpTransport.close`).
///
/// Почему 2 с: вместе с эскалацией транспорта это ≈ 4 с, а общий предел
/// выхода — 5 с (`add-client-process-shutdown-on-exit`, D2, D3). Значение
/// по умолчанию в пакете — 5 с, поэтому CLI и тесты пакета не меняются.
const transportCloseTimeout = Duration(seconds: 2);

/// Предел ожидания закрытия встроенного агента и логгер события таймаута.
///
/// Почему отдельный тип: `CodeLabRootLifecycle` получает зависимости через
/// сгенерированный контракт cherrypick, а `Duration` и `Logger` без обёртки
/// не различить по типу. Как использовать: создаёт
/// [CodeLabEmbeddedAgentModule]; `timeout` — шов тестов
/// (`createCodeLabRootScope(embeddedCloseTimeout:)`).
final class EmbeddedCloseSettings {
  const EmbeddedCloseSettings({required this.timeout, required this.logger});

  final Duration timeout;
  final agent.Logger logger;
}

/// Открыватель встроенного агента и его резолвер (design.md change
/// `add-embedded-agent-mode`, D6, D9).
///
/// Почему отдельный модуль: открыватель — шов тестов (`embeddedOpener`:
/// сценарий модели вместо настоящего конфига и сети, D8), а резолвер должен
/// быть один на scope — им владеют и `ClientWorkspace`, и закрытие scope.
///
/// Как использовать: без [embeddedOpener] берётся `localEmbeddedAgentOpener` с
/// окружением процесса и логом агента в журнал приложения. Модуль ставится
/// после `CodeLabLoggingModule`: адаптер логгера читает уже настроенный журнал.
final class CodeLabEmbeddedAgentModule extends Module {
  CodeLabEmbeddedAgentModule({
    agent.EmbeddedAgentOpener? embeddedOpener,
    Duration? closeTimeout,
    Map<String, String>? environment,
    Future<bool> Function(String cwd)? providerSetupProbe,
  }) : _embeddedOpener = embeddedOpener,
       _closeTimeout = closeTimeout,
       _environment = environment,
       _providerSetupProbe = providerSetupProbe;

  final agent.EmbeddedAgentOpener? _embeddedOpener;
  final Duration? _closeTimeout;

  /// Окружение процесса; шов тестов (`createCodeLabRootScope(environment:)`).
  final Map<String, String>? _environment;

  /// Признак «нужен провайдер» по снимку конфига; шов тестов
  /// (`createCodeLabRootScope(providerSetupProbe:)`). Без него — настоящая
  /// функция `providerSetupNeededAt` с тем же `CODELAB_HOME` и окружением, что
  /// у открывателя (design.md change `add-provider-setup-ui`, D26).
  final Future<bool> Function(String cwd)? _providerSetupProbe;

  @override
  void builder(Scope currentScope) {
    // Одно окружение на открыватель и на порт переноса секретов: движок
    // обязан читать те же `CODELAB_HOME` и `CODELAB_CONFIG`, что агент
    // (design.md change `add-config-literal-secrets-and-migrate`, D8, п. 3).
    final environment = _environment ?? Platform.environment;
    bind<agent.EmbeddedAgentOpener>().toInstance(
      _embeddedOpener ??
          localEmbeddedAgentOpener(
            environment: environment,
            logger: CodeLabEmbeddedLogger(),
          ),
    );
    bind<EmbeddedCloseSettings>().toInstance(
      EmbeddedCloseSettings(
        timeout: _closeTimeout ?? defaultEmbeddedCloseTimeout,
        logger: CodeLabEmbeddedLogger(),
      ),
    );
    bind<SecretMigrationOffer>().toInstance(SecretMigrationOffer());
    bind<ProviderSetupOffer>().toInstance(ProviderSetupOffer());
    bind<SecretMigrationRunner>().toInstance(
      EmbeddedSecretMigrationRunner(
        environment: environment,
        // Платформа — параметром на границе composition root (`AGENTS.md`
        // §11), чтобы тест проверял ветку Windows без хоста.
        platform: Platform.operatingSystem,
      ),
    );
    bind<EmbeddedTransportResolver>()
        .toProvide(
          () => EmbeddedTransportResolver(
            currentScope.resolve<agent.EmbeddedAgentOpener>(),
            offer: currentScope.resolve<SecretMigrationOffer>(),
            setupOffer: currentScope.resolve<ProviderSetupOffer>(),
            providerSetupNeeded:
                _providerSetupProbe ??
                (cwd) => providerSetupNeededAt(
                  cwd,
                  codelabHome:
                      currentScope
                          .resolve<ConnectionEnvironment>()
                          .codelabHome ??
                      '',
                  environment: environment,
                  logger: CodeLabEmbeddedLogger(),
                ),
          ),
        )
        .singleton();
  }
}

/// Configures the project's structured-logging technology
/// (`openspec/changes/add-structured-logging/design.md`, Decision 5):
/// human-readable console output for application-level events in debug
/// builds, non-blocking file sinks in release/for protocol tracing, plus an
/// in-memory [LogBuffer] feeding the in-app log viewer
/// (`replace-debug-log-panel-with-fluent/design.md`, Decision 3).
final class CodeLabLoggingModule extends Module {
  CodeLabLoggingModule({required String logDirectoryPath})
    : _logDirectoryPath = logDirectoryPath;

  final String _logDirectoryPath;

  /// Local-dev-only opt-in for shipping `category=application` events to a
  /// `structured_log_server` instance (viewable in `structured_log_admin_ui`
  /// while working on CodeLab itself) — never set for end users, see
  /// `docs/architecture/technology-stack.md` §17.2. Both must be non-empty
  /// or the sink is not created at all.
  static const _httpServerUrl = String.fromEnvironment(
    'CODELAB_LOG_SERVER_URL',
  );
  static const _httpProjectKey = String.fromEnvironment(
    'CODELAB_LOG_SERVER_KEY',
  );

  @override
  void builder(Scope currentScope) {
    final protocolTraceOutput = structured_log_io.AsyncRotatingFileOutput(
      p.join(_logDirectoryPath, 'protocol.log'),
      maxSizeBytes: 10 * 1024 * 1024,
      maxBackups: 5,
    );
    // Debug: human-readable console only. Release: also write JSON lines to
    // a file, non-blocking (design.md Decision 6/8) — console output alone
    // isn't durable for a desktop app nobody is watching a terminal for.
    final applicationFileOutput = kDebugMode
        ? null
        : structured_log_io.AsyncFileOutput(
            p.join(_logDirectoryPath, 'application.log'),
          );

    // Independent capacity from AcpClientApplication's own 500-entry
    // diagnostics ring buffer — this one backs the in-app log viewer only.
    final logBuffer = LogBuffer();
    bind<LogBuffer>().toInstance(logBuffer);

    final httpOutput = _httpServerUrl.isEmpty || _httpProjectKey.isEmpty
        ? null
        : RemoteSyncLogOutput(
            serverUrl: _httpServerUrl,
            projectSecretKey: _httpProjectKey,
          );

    configureCodeLabLogging(
      applicationOutput:
          applicationFileOutput?.call ?? structured_log.coloredConsoleOutput,
      protocolTraceOutput: protocolTraceOutput.call,
      inAppViewerOutput: logBuffer.capture,
      httpOutput: httpOutput?.call,
    );

    bind<CodeLabLoggingLifecycle>().toInstance(
      CodeLabLoggingLifecycle(
        applicationOutput: applicationFileOutput,
        protocolTraceOutput: protocolTraceOutput,
        httpOutput: httpOutput,
      ),
    );
  }
}

/// Awaits pending writes on all async logging sinks before the scope
/// finishes disposing (design.md Decision 8) — resolved once via
/// [createCodeLabRootScope] so CherryPick's own `Scope.dispose()` (which
/// disposes every resolved [Disposable] automatically) picks it up, rather
/// than threading it through [CodeLabRootLifecycle]'s constructor.
final class CodeLabLoggingLifecycle implements Disposable {
  CodeLabLoggingLifecycle({
    required this.applicationOutput,
    required this.protocolTraceOutput,
    this.httpOutput,
  });

  final structured_log_io.AsyncFileOutput? applicationOutput;
  final structured_log_io.AsyncRotatingFileOutput protocolTraceOutput;
  final RemoteSyncLogOutput? httpOutput;

  /// Ждёт запись очередей файловых журналов, ничего не закрывая (HTTP-выход
  /// остаётся открытым). Для выхода из app: `dispose` при terminate не
  /// вызывается (`AppExitHandler`, D4 «Выход из app»).
  Future<void> flushed() => Future.wait([
    if (applicationOutput != null) applicationOutput!.flushed,
    protocolTraceOutput.flushed,
  ]);

  @override
  Future<void> dispose() =>
      Future.wait([flushed(), if (httpOutput != null) httpOutput!.close()]);
}

/// Регистрирует единственного владельца языка интерфейса.
///
/// Почему отдельный модуль: язык — не часть платформы и не части рабочего
/// места; у него один владелец на весь процесс (`state-management.md` §63а,
/// `add-desktop-localization`, D2).
///
/// Для чего: singleton [AppLanguageCubit] с начальным состоянием из шва и порт
/// [AppStrings] для Cubit-ов с текстом. Закрывает Cubit
/// `CodeLabRootLifecycle.dispose` вместе со scope.
///
/// Как использовать: `createCodeLabRootScope(language:, languagePreferences:)`;
/// тесты подставляют язык `CodeLabTestBinding(locale:)`.
final class CodeLabLanguageModule extends Module {
  CodeLabLanguageModule({AppLanguageStart? language, this.preferences})
    : language = language ?? AppLanguageStart.fallback;

  final AppLanguageStart language;
  final AppLanguagePreferences? preferences;

  @override
  void builder(Scope currentScope) {
    final appLogger = codeLabAppLogger();
    final cubit = AppLanguageCubit(
      preferences:
          preferences ?? const SharedPreferencesAppLanguagePreferences(),
      preference: language.preference,
      locale: language.locale,
      logger: _settingsLogger(),
      appLogger: appLogger,
    );
    // Один раз за запуск (D13): язык текста в событие не попадает, только
    // выбор и применённая локаль.
    appLogger.info(
      'app.locale_resolved',
      context: {
        'preference': language.preference.name,
        'locale': language.locale.toLanguageTag(),
      },
    );
    // Диагностика чтения приходит швом из `main`, где журнала ещё нет; без
    // значений ключа и текста исключения (D13).
    if (language.storedValueInvalid) {
      appLogger.warning('app.language_preference_invalid');
    }
    final readFailure = language.readFailure;
    if (readFailure != null) {
      appLogger.warning(
        'app.language_preference_read_failed',
        context: {'error_class': readFailure},
      );
    }
    bind<AppLanguageCubit>().toInstance(cubit);
    bind<AppStrings>().toInstance(cubit);
  }
}

/// Регистрирует единственного владельца оформления app
/// (`add-app-appearance-page`, D13).
///
/// Почему отдельный модуль: оформление, как и язык, — не часть платформы и не
/// рабочего места; у него один владелец на весь процесс (`state-management.md`
/// §63б).
///
/// Для чего: singleton [AppAppearanceCubit] с начальным состоянием из шва
/// [AppAppearanceStart] и события журнала старта (`app.appearance_resolved` и
/// диагностика чтения), как `app.locale_resolved` у языка. Закрывает Cubit
/// `CodeLabRootLifecycle.dispose` отдельным шагом `appearance`.
///
/// Как использовать: `createCodeLabRootScope(appearance:, appearancePreferences:,
/// themeLibrary:, systemAccentSource:)`. Без каталога и порта акцента —
/// пустой каталог в памяти и платформа без акцента (тесты и хосты без
/// пользовательских тем).
final class CodeLabAppearanceModule extends Module {
  CodeLabAppearanceModule({
    AppAppearanceStart? appearance,
    this.preferences,
    this.library,
    this.accentSource,
  }) : appearance = appearance ?? AppAppearanceStart.defaults;

  final AppAppearanceStart appearance;
  final AppAppearancePreferences? preferences;
  final ThemeLibrary? library;
  final SystemAccentSource? accentSource;

  @override
  void builder(Scope currentScope) {
    final logger = _settingsLogger();
    final settings = appearance.settings;
    // Один раз за запуск (D12): имя пользовательской темы в событие не
    // попадает — оно выбирается пользователем и бывает личным.
    String logName(String id) => kBuiltInThemeIds.contains(id) ? id : 'custom';
    logger.info(
      'app.appearance_resolved',
      context: {
        'mode': settings.mode.name,
        'light_theme': logName(settings.lightTheme),
        'dark_theme': logName(settings.darkTheme),
        'system_accent': settings.systemAccent,
        'fallback': appearance.fallback.name,
      },
    );
    // Диагностика чтения приходит швом из `main`, где журнала ещё нет; без
    // значений ключа и текста исключения.
    if (appearance.storedValueInvalid) {
      logger.warning('appearance.stored_value_invalid');
    }
    // Почему выбранные при старте пользовательские темы не загрузились (D12).
    for (final problem in appearance.themeProblems) {
      logger.warning(
        'appearance.theme_invalid',
        context: {
          'theme': 'custom',
          'code': problem.code,
          'line': problem.line,
          'column': problem.column,
        },
      );
    }
    final readFailure = appearance.readFailure;
    if (readFailure != null) {
      logger.warning(
        'appearance.read_failed',
        context: {'error_class': readFailure},
      );
    }
    // Один каталог тем на Cubit оформления и Cubit страницы «Appearance».
    final themes = library ?? InMemoryThemeLibrary();
    bind<ThemeLibrary>().toInstance(themes);
    bind<AppAppearanceCubit>().toInstance(
      AppAppearanceCubit(
        preferences:
            preferences ?? const SharedPreferencesAppAppearancePreferences(),
        library: themes,
        accentSource: accentSource ?? const UnsupportedSystemAccentSource(),
        start: appearance,
        logger: logger,
      ),
    );
  }
}

final class CodeLabPlatformModule extends Module {
  CodeLabPlatformModule({
    required this.directoryExists,
    UserShellLauncher? userShellLauncher,
    ExternalLinkOpener? externalLinkOpener,
    LocalFolderOpener? localFolderOpener,
    this.projectFolderPicker,
    this.usageCsvSaver,
    ThemeFilePicker? themeFilePicker,
    StartupPreferences? startupPreferences,
  }) : _themeFilePicker = themeFilePicker,
       _startupPreferences = startupPreferences,
       _userShellLauncher = userShellLauncher,
       _externalLinkOpener = externalLinkOpener,
       _localFolderOpener = localFolderOpener;

  /// Порт запуска shell пользователя; шов тестов
  /// (`createCodeLabRootScope(userShellLauncher:)`, `add-integrated-terminal`,
  /// D2): без него — адаптер на `pty2`.
  final UserShellLauncher? _userShellLauncher;

  /// Порт открытия адреса во внешнем приложении; шов тестов
  /// (`createCodeLabRootScope(externalLinkOpener:)`, D11): без него — адаптер
  /// на `url_launcher`.
  final ExternalLinkOpener? _externalLinkOpener;

  /// Порт открытия каталога в файловом менеджере; шов тестов
  /// (`createCodeLabRootScope(localFolderOpener:)`, change `add-app-skills-page`,
  /// D8): без него — адаптер на `url_launcher`.
  final LocalFolderOpener? _localFolderOpener;

  /// Порт выбора файла темы страницы «Appearance»; шов тестов
  /// (`createCodeLabRootScope(themeFilePicker:)`, D9): без него — адаптер на
  /// `file_selector`.
  final ThemeFilePicker? _themeFilePicker;

  /// Порт настройки «Reopen the last project and its tabs»; шов тестов
  /// (`createCodeLabRootScope(startupPreferences:)`, change
  /// `add-app-general-page`, D9): без него — `shared_preferences`.
  final StartupPreferences? _startupPreferences;

  /// Системный выбор папки; тесты подменяют его, чтобы не открывать диалог.
  final ProjectFolderPicker? projectFolderPicker;

  /// Сохранение CSV панели Usage; шов тестов
  /// (`createCodeLabRootScope(usageCsvSaver:)`, change `add-desktop-usage-pane`,
  /// D5): без него — адаптер на `file_selector`.
  final UsageCsvSaver? usageCsvSaver;

  /// Проверка папки проекта; тесты с вымышленными путями подменяют её.
  final DirectoryExists directoryExists;

  @override
  void builder(Scope currentScope) {
    // Проверка папки проекта до восстановления и подключения.
    bind<DirectoryExists>().toInstance(directoryExists);
    // Настройки запуска app: читает `SettingsCubit` до восстановления
    // проекта, пишет страница «General» (D9).
    bind<StartupPreferences>().toInstance(
      _startupPreferences ?? const SharedPreferencesStartupPreferences(),
    );
    const textFileIo = IoTextFileIo();
    bind<TextFileReader>().toInstance(textFileIo);
    bind<TextFileWriter>().toInstance(textFileIo);
    // Открытие ссылок — один порт платформы на ответ агента (change
    // `add-desktop-markdown`, D5) и ссылки OSC 8 терминала (change
    // `add-integrated-terminal`, D3, D11, Q16); `url_launcher` только за ним.
    // Шов тестов — `createCodeLabRootScope(externalLinkOpener:)`.
    bind<ExternalLinkOpener>().toInstance(
      _externalLinkOpener ?? const UrlLauncherExternalLinkOpener(),
    );
    // Открытие каталогов страниц «Skills & extensions» (D8) и «Agents & modes»
    // (D20.3, D21): один порт на двух потребителей, отдельный порт,
    // потому что `ExternalLinkOpener` по политике открывает только
    // `http`/`https`/`mailto`.
    bind<LocalFolderOpener>().toInstance(
      _localFolderOpener ?? const UrlLauncherLocalFolderOpener(),
    );
    // Загрузка изображений ответа: лимиты тела, редиректы, размер (D6, R4).
    bind<ImageProviderFor>().toInstance(defaultImageProviderFor);
    bind<ProjectFolderPicker>().toInstance(
      projectFolderPicker ?? const FileSelectorProjectFolderPicker(),
    );
    bind<UsageCsvSaver>().toInstance(
      usageCsvSaver ?? const FileSelectorUsageCsvSaver(),
    );
    bind<ThemeFilePicker>().toInstance(
      _themeFilePicker ?? const FileSelectorThemeFilePicker(),
    );
    bind<RecentProjectsStore>().toInstance(
      const SharedPreferencesRecentProjectsStore(),
    );
    // Раскладка дока панелей между запусками (change
    // `redesign-workbench-shell`, D5).
    bind<DockLayoutStore>().toInstance(
      const SharedPreferencesDockLayoutStore(),
    );
    // Снимок рабочего пространства для восстановления после перезапуска
    // (design D6 change `add-session-list-and-reload`).
    bind<WorkspaceSnapshotStore>().toInstance(
      const SharedPreferencesWorkspaceSnapshotStore(),
    );
    bind<TerminalProcessRunner>().toInstance(const IoTerminalProcessRunner());
    // Терминал пользователя (не путать с ACP `terminal/*` агента): процессы
    // запускает только этот порт (D2).
    bind<UserShellLauncher>().toInstance(
      _userShellLauncher ?? PtyUserShellLauncher(),
    );
  }
}

/// Профили подключения, их настройки и источник токена (design.md change
/// `add-app-settings-shell`, D5, D7, D15).
///
/// Почему отдельный модуль: профили, `shared_preferences` выбора по умолчанию
/// и токены — один сквозной контур («где лежат профили и откуда берётся
/// токен»), которым пользуются и рабочее место, и страница настроек.
///
/// Как использовать: [profileStore] — шов тестов
/// (`createCodeLabRootScope(profileStore:)`: в `testWidgets` настоящий файл
/// зависал бы); без него — `JsonFileProfileStore('$CODELAB_HOME/profiles.json')`,
/// тот же файл, что у CLI. Токен профиля читает `ProfileSecretSource` из
/// окружения (`env:`) или из хранилища секретов агента (`secret:`, change
/// `add-provider-setup-ui`, D13): значение нигде не сохраняется.
///
/// [profileSecrets] — хранилище секретов, открытое до сборки scope
/// (`openProfileSecrets` в `main`: его `backend` синхронный, а открытие
/// асинхронное); шов тестов. Без него — хранилище только для чтения с
/// причиной «не открыто».
final class CodeLabConnectionModule extends Module {
  CodeLabConnectionModule({
    required ConnectionEnvironment environment,
    ProfileStore? profileStore,
    ProfileSecrets? profileSecrets,
    Future<ProfileSecrets> Function()? profileSecretsOpener,
  }) : _environment = environment,
       _profileStore = profileStore,
       _profileSecrets = profileSecrets,
       _profileSecretsOpener = profileSecretsOpener;

  final ConnectionEnvironment _environment;
  final ProfileStore? _profileStore;
  final ProfileSecrets? _profileSecrets;

  /// Фабрика переоткрытия хранилища (`openProfileSecrets` в `main`); без неё
  /// переоткрытие возвращает прежнее хранилище.
  final Future<ProfileSecrets> Function()? _profileSecretsOpener;

  @override
  void builder(Scope currentScope) {
    bind<ConnectionEnvironment>().toInstance(_environment);
    bind<ProfileStore>().toInstance(
      _profileStore ??
          switch (_environment.profilesPath) {
            final path? => JsonFileProfileStore(path),
            // Недопустимый CODELAB_HOME: ни записи, ни каталогов (D7).
            null => UnavailableProfileStore(
              _environment.homeProblem ?? 'the home folder is not available',
            ),
          },
    );
    bind<ConnectionPreferences>().toInstance(
      const SharedPreferencesConnectionPreferences(),
    );
    // Хранилище переоткрывается при каждом открытии диалога и страницы
    // (ревью итерации 1): правка `secrets.backend` применяется без
    // перезапуска. Журнал настроен в `CodeLabLoggingModule` (ставится
    // раньше): событие `secrets.client.backend` пишется здесь, а не при
    // открытии хранилища в `main` (D18).
    final secrets = ReopenableProfileSecrets(
      initial:
          _profileSecrets ??
          UnavailableProfileSecrets('the secret store is not opened'),
      open: _profileSecretsOpener,
      onOpened: (opened) => _settingsLogger().info(
        'secrets.client.backend',
        context: {
          'backend': opened.backend.id,
          'writable': opened.backend.writable,
          'reason': ?_problemOf(opened),
        },
      ),
    );
    bind<ReopenableProfileSecrets>().toInstance(secrets);
    bind<ProfileSecrets>().toInstance(secrets);
    // Тот же источник читает токен при подключении и при проверке профиля:
    // `env:` — из окружения, `secret:` — из хранилища без кэша (D13).
    final tokenSource = ProfileSecretSource(
      _environment.variables,
      stored: secrets,
    );
    bind<SecretSource>().toInstance(tokenSource);
    bind<ProfileSecretSource>().toInstance(tokenSource);
    bind<DefaultProfileResolver>()
        .toProvide(
          () => DefaultProfileResolver(
            store: currentScope.resolve<ProfileStore>(),
            preferences: currentScope.resolve<ConnectionPreferences>(),
            logger: _settingsLogger(),
          ),
        )
        .singleton();
  }
}

final class CodeLabPresentationModule extends Module {
  CodeLabPresentationModule({
    required SettingsPages settingsPages,
    required String logDirectory,
    ProviderSettingsOpener? providerSettingsOpener,
    ProjectFiles? projectFiles,
    AboutInfo? aboutInfo,
  }) : _logDirectory = logDirectory,
       _aboutInfo = aboutInfo,
       _settingsPages = settingsPages,
       _providerSettingsOpener = providerSettingsOpener,
       _projectFiles = projectFiles;

  /// Чтение папки проекта для панели Files. `null` — панель не предлагается
  /// (web, устройства без локальной папки, тесты без двойника); иначе
  /// `IoProjectFiles` из `codelab_client_io` или двойник теста
  /// (`createCodeLabRootScope(projectFiles:)`; design.md change
  /// `add-file-preview-and-tree`, D1, D7).
  final ProjectFiles? _projectFiles;

  /// Открывает доступ к настройкам агента страницы «Providers»; шов тестов
  /// (`createCodeLabRootScope(providerSettingsOpener:)`): без него — IO-сессия
  /// `openProviderSettingsSession` (design.md change `add-provider-setup-ui`,
  /// D4, D5).
  final ProviderSettingsOpener? _providerSettingsOpener;

  /// Страницы настроек, видимые в этой сборке; шов тестов
  /// (`createCodeLabRootScope(settingsPages:)`, design.md change
  /// `add-app-settings-shell`, D3).
  final SettingsPages _settingsPages;

  /// Каталог журналов app для кнопки «Open log folder» (D14).
  final String _logDirectory;

  /// Готовые данные раздела «About»; шов тестов
  /// (`createCodeLabRootScope(aboutInfo:)`, D11).
  final AboutInfo? _aboutInfo;

  @override
  void builder(Scope currentScope) {
    // Переходы рабочее место ↔ настройки (D1, D2). Активная сессия для
    // `returnTo` читается у фасада в момент ухода.
    bind<SettingsPages>().toInstance(_settingsPages);
    bind<SettingsPageStore>().toInstance(
      const SharedPreferencesSettingsPageStore(),
    );
    bind<NavigationCubit>()
        .toProvide(
          () => NavigationCubit(
            store: currentScope.resolve<SettingsPageStore>(),
            pages: currentScope.resolve<SettingsPages>(),
            activeSessionId: () =>
                currentScope.resolve<CodeLabShellCubit>().state.activeSessionId,
            selectSessionIfOpen: (id) => currentScope
                .resolve<CodeLabShellCubit>()
                .selectSessionIfOpen(id),
            logger: _settingsLogger(),
          ),
        )
        .singleton();
    // Токен WebSocket-профиля — ссылка `env:<NAME>`: значение читает
    // `ProfileSecretSource` из окружения в момент открытия транспорта
    // (design.md change `add-app-settings-shell`, D13, D15).
    bind<ClientWorkspace>()
        .toProvide(
          () => ClientWorkspace(
            backend: AcpClientBackend(
              currentScope.resolve<AcpClientApplication>(),
            ),
            resolvers: _transportResolvers(currentScope),
            snapshots: currentScope.resolve<WorkspaceSnapshotStore>(),
          ),
        )
        .singleton();
    // Пять Cubit-ов рабочего места (design D10): собираются после
    // `ClientWorkspace`, чтобы рабочее пространство раньше них подписалось на
    // `sessionChanges` (design D6).
    bind<CodeLabShellParts>()
        .toProvide(
          () => CodeLabShellParts.build(
            // До выбора профиль окна — встроенный агент; профиль по
            // умолчанию подставляет `DefaultProfileResolver` (D5).
            initialProfile: embeddedConnectionProfile,
            application: currentScope.resolve<AcpClientApplication>(),
            workspace: currentScope.resolve<ClientWorkspace>(),
            projectFolderPicker: currentScope.resolve<ProjectFolderPicker>(),
            recentProjectsStore: currentScope.resolve<RecentProjectsStore>(),
            directoryExists: currentScope.resolve<DirectoryExists>(),
            dockLayoutStore: currentScope.resolve<DockLayoutStore>(),
            defaultProfiles: currentScope.resolve<DefaultProfileResolver>(),
            tokenSecrets: currentScope.resolve<ProfileSecretSource>(),
            eventLogger: _settingsLogger(),
            providerSetupOffer: currentScope.resolve<ProviderSetupOffer>(),
            // Панель Usage: порт сохранения CSV и события `usage_pane.*`
            // (change `add-desktop-usage-pane`, D5, D13).
            usageCsvSaver: currentScope.resolve<UsageCsvSaver>(),
            usageLogger: _usageLogger(),
            startupPreferences: currentScope.resolve<StartupPreferences>(),
            appLogger: codeLabAppLogger(),
            // Язык интерфейса: Cubit-ы рабочего места с текстом подписаны на
            // порт в конструкторе (`add-desktop-localization`, D5).
            strings: currentScope.resolve<AppStrings>(),
          ),
        )
        .singleton();
    // Перенос секретов встроенного агента (D8): предложение даёт резолвер,
    // ход — по всем сессиям рабочего места (переподключение обрывает и
    // фоновый ход). Начальные значения предложения и хода передаются первым
    // событием: Cubit может создаться после открытия агента или посреди хода.
    bind<SecretMigrationCubit>().toProvide(() {
      final workspace = currentScope.resolve<ClientWorkspace>();
      final offer = currentScope.resolve<SecretMigrationOffer>();
      return SecretMigrationCubit(
        runner: currentScope.resolve<SecretMigrationRunner>(),
        turnActivity: turnActivityOf(workspace.current, workspace.state),
        offered: offer.watch(),
        logger: StructuredLogLogger('codelab_desktop.secret_migration').bind({
          logCategoryKey: applicationLogCategory,
          logComponentKey: 'secret_migration',
        }),
      );
    }).singleton();
    // Вкладки терминала пользователя: живут в root scope, а не в виджете,
    // потому что процессы переживают закрытие панели и смену проекта (Q18,
    // D4, D5). Журнал — события жизненного цикла без путей и вывода (D9).
    bind<TerminalTabsCubit>()
        .toProvide(
          () => TerminalTabsCubit(
            workspace: currentScope.resolve<ClientWorkspace>(),
            launcher: currentScope.resolve<UserShellLauncher>(),
            externalLinkOpener: currentScope.resolve<ExternalLinkOpener>(),
            directoryExists: currentScope.resolve<DirectoryExists>(),
            logger: StructuredLogLogger('codelab_desktop.terminal').bind({
              logCategoryKey: applicationLogCategory,
              logComponentKey: 'terminal',
            }),
          ),
        )
        .singleton();
    // Сброс вывода на кадре: один на scope, срок жизни Cubit (D3).
    bind<TerminalOutputFlusher>()
        .toProvide(
          () => TerminalOutputFlusher(
            cubit: currentScope.resolve<TerminalTabsCubit>(),
          ),
        )
        .singleton();
    bind<CodeLabShellCubit>()
        .toProvide(
          () => CodeLabShellCubit(
            application: currentScope.resolve<AcpClientApplication>(),
            workspace: currentScope.resolve<ClientWorkspace>(),
            parts: currentScope.resolve<CodeLabShellParts>(),
            projectFolderPicker: currentScope.resolve<ProjectFolderPicker>(),
            recentProjectsStore: currentScope.resolve<RecentProjectsStore>(),
            externalLinkOpener: currentScope.resolve<ExternalLinkOpener>(),
            imageProviderFor: currentScope.resolve<ImageProviderFor>(),
            // События ленты (`link.open`, `image.show`) — компонент workbench,
            // а не настроек.
            eventLogger: _workbenchLogger(),
            projectFilesBound: _projectFiles != null,
          ),
        )
        .singleton();
    // Панель Files: один Cubit на окно (держатель ниже). Привязки нет — нет
    // и панели (D7).
    final projectFiles = _projectFiles;
    if (projectFiles != null) {
      bind<ProjectFiles>().toInstance(projectFiles);
      // Владелец дерева — окно, а не вкладка: док монтирует только активную
      // вкладку, и Cubit вкладки терял бы раскрытые папки при каждом
      // переключении (design.md, D6). Cubit создаётся лениво при первом показе
      // Files и закрывается вместе со scope.
      bind<ProjectFilesHolder>()
          .toProvide(
            () => ProjectFilesHolder(
              () => ProjectFilesCubit(
                files: projectFiles,
                workspace: currentScope.resolve<ClientWorkspace>(),
                // Доступность решает application рабочего места (профиль
                // окна): пока Files недоступна, Cubit не трогает диск (Q8).
                available: currentScope
                    .resolve<CodeLabShellCubit>()
                    .state
                    .projectFilesAvailable,
                availability: currentScope
                    .resolve<CodeLabShellCubit>()
                    .stream
                    .map((state) => state.projectFilesAvailable)
                    .distinct(),
                logger: StructuredLogLogger('codelab_desktop.project_files')
                    .bind({
                      logCategoryKey: applicationLogCategory,
                      logComponentKey: 'project_files',
                    }),
              ),
            ),
          )
          .singleton();
    }
    // Диалог «Add connection profile»: новый Cubit на каждое открытие;
    // закрывает его страница вместе с диалогом (D12).
    bind<AddProfileCubit>().toProvide(() {
      final environment = currentScope.resolve<ConnectionEnvironment>();
      return AddProfileCubit(
        store: currentScope.resolve<ProfileStore>(),
        openSecrets: currentScope.resolve<ReopenableProfileSecrets>().reopen,
        preferences: currentScope.resolve<ConnectionPreferences>(),
        // Типы профилей определяют резолверы, а не проверка платформы
        // (SETUP-22, AGENTS.md §11).
        kinds: profileKindsFor(_transportResolvers(currentScope)),
        environment: environment.variables,
        profilesPath: environment.profilesPath,
        logger: _settingsLogger(),
        strings: currentScope.resolve<AppStrings>(),
      );
    });
    // Страница «Connection»: новый Cubit на каждое открытие (файл
    // перечитывается при открытии, D4). Закрывает его страница.
    bind<ConnectionSettingsCubit>().toProvide(() {
      final environment = currentScope.resolve<ConnectionEnvironment>();
      return ConnectionSettingsCubit(
        store: currentScope.resolve<ProfileStore>(),
        openSecrets: currentScope.resolve<ReopenableProfileSecrets>().reopen,
        preferences: currentScope.resolve<ConnectionPreferences>(),
        workspace: currentScope.resolve<ClientWorkspace>(),
        commands: currentScope.resolve<CodeLabShellParts>().connection,
        environment: environment.variables,
        profilesPath: environment.profilesPath,
        logger: _settingsLogger(),
        strings: currentScope.resolve<AppStrings>(),
      );
    });
    // Страница «Providers»: новый Cubit на каждое открытие, снимок
    // перечитывается при открытии (D10); закрывает его страница.
    final providerCheck = setup_io.ioProviderCheck(
      logger: CodeLabEmbeddedLogger(),
    );
    final openSettings =
        _providerSettingsOpener ??
        (access, env) => openProviderSettingsSession(
          access,
          env,
          check: providerCheck,
          logger: CodeLabEmbeddedLogger(),
        );
    bind<ProviderSettingsCubit>().toProvide(() {
      final environment = currentScope.resolve<ConnectionEnvironment>();
      return ProviderSettingsCubit(
        workspace: currentScope.resolve<ClientWorkspace>(),
        defaultProfile: currentScope.resolve<DefaultProfileResolver>().resolve,
        open: openSettings,
        environment: environment.variables,
        codelabHome: environment.codelabHome,
        projectDirectory: () => _focusFolder(currentScope),
        logger: _settingsLogger(),
        retryStart: () =>
            currentScope.resolve<CodeLabShellCubit>().retryStart(),
        strings: currentScope.resolve<AppStrings>(),
      );
    });
    // Страница «Agents & modes»: новый Cubit на каждое открытие (D11); сессия
    // настроек и доступ — те же, что у «Providers» (D2).
    bind<AgentsModesCubit>().toProvide(() {
      final environment = currentScope.resolve<ConnectionEnvironment>();
      return AgentsModesCubit(
        workspace: currentScope.resolve<ClientWorkspace>(),
        defaultProfile: currentScope.resolve<DefaultProfileResolver>().resolve,
        open: openSettings,
        environment: environment.variables,
        codelabHome: environment.codelabHome,
        projectDirectory: () => _focusFolder(currentScope),
        logger: _settingsLogger(),
        loadDefinitions: loadAgentDefinitionsForPage,
        folderOpener: currentScope.resolve<LocalFolderOpener>(),
      );
    });
    // Блок «Agent defaults» страницы «General» (change `add-app-general-page`,
    // D7): новый Cubit на каждое открытие страницы; сессия настроек и доступ —
    // те же, что у «Providers» и «Agents & modes».
    bind<AgentDefaultsCubit>().toProvide(() {
      final environment = currentScope.resolve<ConnectionEnvironment>();
      return AgentDefaultsCubit(
        workspace: currentScope.resolve<ClientWorkspace>(),
        defaultProfile: currentScope.resolve<DefaultProfileResolver>().resolve,
        open: openSettings,
        environment: environment.variables,
        codelabHome: environment.codelabHome,
        projectDirectory: () => _focusFolder(currentScope),
        logger: _settingsLogger(),
      );
    });
    // Раздел «About» страницы «General» (change `add-app-general-page`, D11,
    // D13, D14): данные собираются один раз и лениво, порты — те же, что у
    // остальных страниц.
    bind<AboutPorts>()
        .toProvide(
          () => buildAboutPorts(
            version: codelabDesktopVersion,
            environment: currentScope.resolve<ConnectionEnvironment>(),
            logDirectory: _logDirectory,
            workspace: currentScope.resolve<ClientWorkspace>(),
            defaultProfile: currentScope
                .resolve<DefaultProfileResolver>()
                .resolve,
            externalLinks: currentScope.resolve<ExternalLinkOpener>(),
            folders: currentScope.resolve<LocalFolderOpener>(),
            fixed: _aboutInfo,
            logger: _settingsLogger(),
          ),
        )
        .singleton();
    // Строка «Reopen the last project and its tabs» страницы «General»
    // (change `add-app-general-page`, D9): новый Cubit на каждое открытие.
    bind<StartupSettingsCubit>().toProvide(
      () => StartupSettingsCubit(
        preferences: currentScope.resolve<StartupPreferences>(),
        logger: _settingsLogger(),
      ),
    );
    // Страница «MCP servers»: новый Cubit на каждое открытие (D11); сессия
    // настроек и доступ — те же, что у «Providers», порт состояния MCP
    // встроенного агента берётся у резолвера текущего соединения (D12).
    bind<McpSettingsCubit>().toProvide(() {
      final environment = currentScope.resolve<ConnectionEnvironment>();
      return McpSettingsCubit(
        workspace: currentScope.resolve<ClientWorkspace>(),
        defaultProfile: currentScope.resolve<DefaultProfileResolver>().resolve,
        open: openSettings,
        environment: environment.variables,
        codelabHome: environment.codelabHome,
        projectDirectory: () => _focusFolder(currentScope),
        statusSource: ResolverMcpStatusSource(
          currentScope.resolve<EmbeddedTransportResolver>(),
        ),
        logger: _settingsLogger(),
      );
    });
    // Страница «Skills & extensions» (change `add-app-skills-page`, D6): новый
    // Cubit на каждое открытие; сессия настроек и доступ — те же, что у
    // «Providers», открытие каталогов — порт платформы.
    bind<SkillsSettingsCubit>().toProvide(() {
      final environment = currentScope.resolve<ConnectionEnvironment>();
      return SkillsSettingsCubit(
        workspace: currentScope.resolve<ClientWorkspace>(),
        defaultProfile: currentScope.resolve<DefaultProfileResolver>().resolve,
        open: openSettings,
        environment: environment.variables,
        codelabHome: environment.codelabHome,
        projectDirectory: () => _focusFolder(currentScope),
        folderOpener: currentScope.resolve<LocalFolderOpener>(),
        logger: _settingsLogger(),
      );
    });
    // Страница «Appearance» (change `add-app-appearance-page`, D13): новый Cubit
    // на каждое открытие; применённое оформление — общий владелец, каталог и
    // выбор файла — порты. Каталог тем — `<home>/themes`; без дома он
    // недоступен (`themesDirectory == null`).
    bind<AppearanceSettingsCubit>().toProvide(() {
      final environment = currentScope.resolve<ConnectionEnvironment>();
      final home = environment.codelabHome;
      final directory = home == null ? null : p.join(home, 'themes');
      return AppearanceSettingsCubit(
        library: currentScope.resolve<ThemeLibrary>(),
        appearance: currentScope.resolve<AppAppearanceCubit>(),
        picker: currentScope.resolve<ThemeFilePicker>(),
        folderOpener: currentScope.resolve<LocalFolderOpener>(),
        systemBrightness: () => PlatformDispatcher.instance.platformBrightness,
        themesDirectory: directory,
        themesDirectoryLabel: directory == null
            ? null
            : homePathLabel(directory, environment.variables),
        themesLabel: directory == null
            ? null
            : '${homePathLabel(directory, environment.variables)}'
                  '${p.separator}*.json',
        logger: _settingsLogger(),
      );
    });
    // Мастер из баннера «Встроенный агент без провайдера» (D26): сессия
    // настроек встроенного профиля — той же фабрикой, что у страницы
    // «Providers»; цель по умолчанию `user`, «Make default» не снимается.
    bind<EmbeddedWizardOpener>().toInstance(({required String cwd}) async {
      final environment = currentScope.resolve<ConnectionEnvironment>();
      final access = resolveSettingsAccess(
        kind: AgentLaunchKind.embedded,
        cwd: cwd.isEmpty ? null : cwd,
        defaultCodelabHome: environment.codelabHome ?? '',
      );
      if (access is! EditableSettings || access.paths.codelabHome.isEmpty) {
        return null;
      }
      try {
        final session = await openSettings(access, environment.variables);
        final flow = await session.openWizard(
          forceDefault: true,
          entry: ProviderWizardEntry.banner,
        );
        return ProviderWizardCubit(
          flow: flow,
          access: access,
          backendId: session.backend.id,
          forceDefault: true,
          // Баннер виден, пока агент не открылся: подключения нет.
          isAgentConnected: () => false,
          logger: _settingsLogger(),
          strings: currentScope.resolve<AppStrings>(),
        );
      } on Object catch (error) {
        _settingsLogger().warning(
          'provider_settings.unreadable',
          context: {'error_type': error.runtimeType.toString()},
        );
        return null;
      }
    });
  }
}

/// Причина неисправности хранилища для события журнала (без путей).
String? _problemOf(ProfileSecrets secrets) => switch (secrets) {
  final DescribedProfileSecrets described => described.backendProblem,
  _ => null,
};

/// Резолверы транспортов окна: один список для `ClientWorkspace`, проверки
/// профиля и списка типов диалога, чтобы то, что можно проверить и
/// добавить, совпадало с тем, что можно открыть (design.md change
/// `add-app-settings-shell`, D12, SETUP-22).
List<TransportResolver> _transportResolvers(Scope scope) => [
  ConfigTransportResolver(
    stdio: scope.resolve<CodeLabStdioTransportFactory>(),
    webSocket: scope.resolve<CodeLabWebSocketTransportFactory>(),
    secrets: scope.resolve<SecretSource>(),
  ),
  // Встроенный агент открывает только свой резолвер; у
  // `ConfigTransportResolver` профиль `embedded` не поддержан (D7).
  scope.resolve<EmbeddedTransportResolver>(),
];

/// Логгер событий панели Usage (`usage_pane.refresh`, `usage_pane.export`):
/// категория `application`, компонент `usage` (change
/// `add-desktop-usage-pane`, D13).
Logger _usageLogger() => StructuredLogLogger(
  'codelab_desktop.usage',
).bind({logCategoryKey: applicationLogCategory, logComponentKey: 'usage'});

/// Структурный логгер событий настроек (design.md change
/// `add-app-settings-shell`, D17): категория `application`, компонент
/// `settings`.
Logger _workbenchLogger() => StructuredLogLogger(
  'codelab_desktop.workbench',
).bind({logCategoryKey: applicationLogCategory, logComponentKey: 'workbench'});

/// Логгер событий жизненного цикла приложения (`app.exit_*`,
/// `app.shutdown_step_failed`): категория `application`, компонент `app`
/// (`add-client-process-shutdown-on-exit`, D6).
Logger codeLabAppLogger() => StructuredLogLogger(
  'codelab_desktop.app',
).bind({logCategoryKey: applicationLogCategory, logComponentKey: 'app'});

Logger _settingsLogger() => StructuredLogLogger(
  'codelab_desktop.settings',
).bind({logCategoryKey: applicationLogCategory, logComponentKey: 'settings'});

@module()
abstract class CodeLabTransportsModuleContract extends Module {
  @instance()
  @singleton()
  StdioAcpAgentProfile stdioAgentProfile() => codelabAgentStdioProfile;

  @provide()
  @singleton()
  AcpTransport transport(CodeLabTransportFactory transportFactory) =>
      transportFactory();
}

@module()
abstract class CodeLabProtocolApplicationModuleContract extends Module {
  @provide()
  @singleton()
  AcpClientApplication application(
    AcpTransport transport,
    CodeLabTransportFactory transportFactory,
    TextFileReader textFileReader,
    TextFileWriter textFileWriter,
    TerminalProcessRunner terminalProcessRunner,
  ) => AcpClientApplication(
    transport: transport,
    reconnectTransport: transportFactory,
    textFileReader: textFileReader,
    textFileWriter: textFileWriter,
    terminalProcessRunner: terminalProcessRunner,
  );
}

@module()
abstract class CodeLabRootLifecycleModuleContract extends Module {
  @provide()
  @singleton()
  CodeLabRootLifecycle rootLifecycle(
    AcpClientApplication application,
    AcpTransport transport,
    ClientWorkspace workspace,
    EmbeddedTransportResolver embedded,
    EmbeddedCloseSettings embeddedCloseSettings,
    CodeLabShellCubit shellCubit,
    SecretMigrationCubit secretMigrationCubit,
    SecretMigrationOffer secretMigrationOffer,
    NavigationCubit navigationCubit,
    TerminalTabsCubit terminalTabsCubit,
    AppLanguageCubit languageCubit,
    AppAppearanceCubit appearanceCubit,
  ) => CodeLabRootLifecycle(
    application: application,
    transport: transport,
    workspace: workspace,
    embedded: embedded,
    embeddedCloseSettings: embeddedCloseSettings,
    shellCubit: shellCubit,
    secretMigrationCubit: secretMigrationCubit,
    secretMigrationOffer: secretMigrationOffer,
    navigationCubit: navigationCubit,
    terminalTabsCubit: terminalTabsCubit,
    languageCubit: languageCubit,
    appearanceCubit: appearanceCubit,
  );
}

/// Закрывает всех владельцев процессов и подписок composition root.
///
/// Почему: процессы клиента (вкладки Terminal, `terminal/*` внешнего агента,
/// stdio-агент, встроенный агент) принадлежат разным владельцам, а связать их
/// может только composition root. Закрытие должно быть упорядоченным,
/// изолированным по шагам и идемпотентным: его вызывают и закрытие root scope,
/// и обработчик выхода `AppExitHandler` (`add-client-process-shutdown-on-exit`,
/// D1, D5; `concurrency.md` §45–§46).
///
/// Для чего: единственный путь «закрыть всё клиентское». Две ветки идут
/// параллельно (D2): терминал пользователя (`closeAll()` ≤ 3 с, затем
/// `close()`) и клиентская цепочка — Cubit-ы → рабочее пространство, а затем
/// две параллельные подветви (D11): агентская (встроенный агент →
/// предложение миграции) и ACP (начальный транспорт → ядро клиента с
/// пределом [transportCloseTimeout]). Терминал и ACP-сторона друг о друге не
/// знают (`add-integrated-terminal`, D10), поэтому порядка между ветками нет.
///
/// Почему подветви параллельны: зависшее открытие встроенного агента (до 10 с)
/// не должно оставить без сигналов `terminal/*` и stdio-агента внешнего
/// профиля — их посылает только ядро клиента. Встроенный агент при этом
/// закрывается корректно и без ядра: закрытие клиентского конца пары запускает
/// тот же идемпотентный `dispose` агента (embedded-agent «Жизненный цикл
/// встроенного агента», сценарий «Клиент закрыл соединение»; D11 вместо D9
/// `add-embedded-agent-mode`).
///
/// Как использовать: scope вызывает [dispose] при закрытии; обработчик выхода
/// вызывает его же. Повторный вызов возвращает тот же `Future` (не `void`),
/// владельцы не получают повторных сигналов. Сбой шага пишется как
/// `app.shutdown_step_failed {step, error_type}` и не мешает следующим;
/// пока шаг не завершился, его имя в [pendingSteps] — обработчик выхода кладёт
/// его в `app.exit_timeout` (D6).
final class CodeLabRootLifecycle implements Disposable {
  CodeLabRootLifecycle({
    required AcpClientApplication application,
    required AcpTransport transport,
    required ClientWorkspace workspace,
    required EmbeddedTransportResolver embedded,
    required EmbeddedCloseSettings embeddedCloseSettings,
    required CodeLabShellCubit shellCubit,
    required SecretMigrationCubit secretMigrationCubit,
    required SecretMigrationOffer secretMigrationOffer,
    required NavigationCubit navigationCubit,
    required TerminalTabsCubit terminalTabsCubit,
    AppLanguageCubit? languageCubit,
    // Владелец оформления (D13): `close()` ждёт идущую запись; шаг выхода
    // `appearance` идёт параллельной веткой, как `language`.
    AppAppearanceCubit? appearanceCubit,
    Logger? logger,
  }) : _logger = logger ?? codeLabAppLogger(),
       _application = application,
       _transport = transport,
       _workspace = workspace,
       _embedded = embedded,
       _embeddedCloseSettings = embeddedCloseSettings,
       _shellCubit = shellCubit,
       _secretMigrationCubit = secretMigrationCubit,
       _secretMigrationOffer = secretMigrationOffer,
       _navigationCubit = navigationCubit,
       _terminalTabsCubit = terminalTabsCubit,
       _languageCubit = languageCubit,
       _appearanceCubit = appearanceCubit;

  final AcpClientApplication _application;
  final AcpTransport _transport;

  /// Закрывается после Cubit (его подписчика) и до обеих подветвей — агентской
  /// и ACP: рабочее пространство отписывается от ядра клиента до его
  /// `dispose` (D11); kit не закрывает `AcpClientApplication` сам.
  final ClientWorkspace _workspace;

  /// Закрывается после рабочего пространства, параллельно с закрытием ядра
  /// клиента (D11): если клиентский конец закроется первым, агент запустит тот
  /// же `dispose` сам, а закрытие резолвера дождётся его, поэтому журнал
  /// дописан до конца шага. Закрытие ждёт `dispose` агента и открытие в
  /// полёте, предел — `embedded.close_timeout` (design.md change
  /// `add-embedded-agent-mode`, D6; `add-client-process-shutdown-on-exit`, D11).
  final EmbeddedTransportResolver _embedded;
  final EmbeddedCloseSettings _embeddedCloseSettings;
  final CodeLabShellCubit _shellCubit;

  /// Закрывается вместе с Cubit рабочего места: подписки на предложение и ход
  /// освобождаются до закрытия агента.
  final SecretMigrationCubit _secretMigrationCubit;

  /// Закрывается в агентской подветви строго после резолвера: он до конца
  /// пишет в источник (D11).
  final SecretMigrationOffer _secretMigrationOffer;
  final NavigationCubit _navigationCubit;

  /// Процессы терминала завершает отдельная ветка, параллельная клиентской:
  /// `closeAll()` шлёт `hangUp`, через 3 с `kill` и запрещает новые вкладки
  /// (D4, «Выход из app»), затем Cubit закрывается. Порядка относительно
  /// рабочего пространства нет (`add-client-process-shutdown-on-exit`, D2).
  final TerminalTabsCubit _terminalTabsCubit;

  /// Владелец языка интерфейса (D2): закрывается вместе со scope, после чего
  /// запись выбора не применяется.
  final AppLanguageCubit? _languageCubit;

  /// Владелец оформления (D13): закрывается отдельной веткой, как язык —
  /// `close()` ждёт идущую запись выбора до 3 с.
  final AppAppearanceCubit? _appearanceCubit;

  /// Логгер событий `app.*` (D6); по умолчанию — `codelab_desktop.app`, как у
  /// обработчика выхода. Шов тестов.
  final Logger _logger;

  /// Закрытый набор имён шагов в порядке закрытия (D5, D10).
  static const _shutdownSteps = [
    'terminal',
    'cubits',
    'workspace',
    'embedded',
    'migration_offer',
    'transport',
    'client',
    // Отдельная ветвь: ждёт запись выбора языка до 3 с (D2, D10).
    'language',
    // Та же ветвь для записи оформления (D13): шаг без сигналов процессам не
    // стоит перед шагами с сигналами (`concurrency.md` §45, §46).
    'appearance',
  ];

  /// Общий проход закрытия: повторный `dispose()` ждёт его, а не возвращается
  /// сразу (D5) — иначе второй запрос выхода считал бы закрытие завершённым.
  Future<void>? _disposing;

  /// Имена ещё не завершённых шагов, включая не начатые, в порядке закрытого
  /// набора: `terminal`, `cubits`, `workspace`, `embedded`, `migration_offer`,
  /// `transport`, `client`, `language`, `appearance` (D5, D10, D13; `language` и
  /// `appearance` — только если у lifecycle есть соответствующий Cubit). Пуст до [dispose] и после прохода.
  final List<String> _pendingSteps = [];

  /// Шаги, которые не завершились к моменту вызова, в том числе не начатые
  /// (копия; D10).
  ///
  /// Почему и не начатые: именно они посылают сигналы `terminal/*` и
  /// stdio-агенту, и журнал «не успел только `embedded`» вводил бы в
  /// заблуждение (`AGENTS.md` §16).
  List<String> get pendingSteps => List.unmodifiable(_pendingSteps);

  @override
  Future<void> dispose() => _disposing ??= _dispose();

  // `async` + `await`, а не возврат `Future.wait`: иначе рантайм-тип будущего —
  // `Future<List<void>>`, и `timeout(onTimeout:)` обработчика выхода падает
  // `TypeError`.
  Future<void> _dispose() async {
    // Первым синхронным действием — до любого `await`: не начатые шаги тоже
    // «не завершены» (D10).
    _pendingSteps.addAll(
      _shutdownSteps.where(
        (step) =>
            (step != 'language' || _languageCubit != null) &&
            (step != 'appearance' || _appearanceCubit != null),
      ),
    );
    await Future.wait([
      _closeTerminal(),
      _closeClient(),
      _closeLanguage(),
      _closeAppearance(),
    ]);
  }

  /// Ветка терминала: `closeAll()` шлёт `hangUp`, через 3 с `kill` и
  /// запрещает новые вкладки (D4 «Выход из app»); `close()` Cubit-а может
  /// прийти после `ClientWorkspace.dispose()` — `closeAll()` уже запретил
  /// новые вкладки.
  Future<void> _closeTerminal() => _step('terminal', () async {
    await _terminalTabsCubit.closeAll();
    await _terminalTabsCubit.close();
  });

  /// Ветка языка: `close()` Cubit-а ждёт запись выбора до 3 с, поэтому она
  /// идёт параллельно и не отнимает время у рабочего пространства, агента и
  /// транспорта при общем пределе выхода 5 с; зависшая запись видна в
  /// [pendingSteps] как `language` (D2, D10).
  Future<void> _closeLanguage() async {
    final cubit = _languageCubit;
    if (cubit != null) await _step('language', cubit.close);
  }

  /// Ветка оформления: `close()` ждёт запись выбора до 3 с, поэтому она идёт
  /// параллельно (как язык) и не отнимает время у рабочего пространства, агента
  /// и транспорта; зависшая запись видна в [pendingSteps] как `appearance`
  /// (D13).
  Future<void> _closeAppearance() async {
    final cubit = _appearanceCubit;
    if (cubit != null) await _step('appearance', cubit.close);
  }

  /// Клиентская ветка: Cubit-ы отписываются до закрытия рабочего
  /// пространства, оно — до ядра клиента; затем агентская и ACP-подветви идут
  /// параллельно (D2, D5, D11).
  Future<void> _closeClient() async {
    await _step('cubits', () async {
      await _navigationCubit.close();
      await _secretMigrationCubit.close();
      await _shellCubit.close();
    });
    await _step('workspace', _workspace.dispose);
    await Future.wait([_closeEmbedded(), _closeAcp()]);
  }

  /// Агентская подветвь: резолвер, затем источник предложения миграции — он
  /// до конца пишет в источник (D11).
  Future<void> _closeEmbedded() async {
    // Зависший `dispose` агента не держит закрытие scope вечно: по таймауту
    // пишется событие без текста ошибки, а транспорт и ядро клиента всё равно
    // освобождаются (design.md change `add-embedded-agent-mode`, D6).
    await _step(
      'embedded',
      () => _embedded.close().timeout(
        _embeddedCloseSettings.timeout,
        onTimeout: () => _embeddedCloseSettings.logger.log(
          agent.LogLevel.warning,
          'embedded.close_timeout',
        ),
      ),
    );
    await _step('migration_offer', _secretMigrationOffer.close);
  }

  /// ACP-подветвь: начальный транспорт, затем ядро клиента. Не ждёт агентскую:
  /// сигналы `terminal/*` и stdio-агенту идут без зависимости от резолвера
  /// (D11).
  Future<void> _closeAcp() async {
    await _step('transport', _transport.close);
    await _step(
      'client',
      () => _application.dispose(closeTimeout: transportCloseTimeout),
    );
  }

  /// Выполняет шаг с изоляцией: сбой пишется в журнал только с типом ошибки
  /// (текст может нести пути, D6) и не мешает следующим шагам. Имя убирается
  /// из [pendingSteps] по завершении шага (имена добавляет [_dispose], D10).
  Future<void> _step(String name, Future<void> Function() body) async {
    try {
      await body();
    } on Object catch (error) {
      try {
        _logger.error(
          'app.shutdown_step_failed',
          context: {'step': name, 'error_type': error.runtimeType.toString()},
        );
      } on Object {
        // Журнал не должен мешать закрытию: писать о сбое журнала некуда.
      }
    } finally {
      _pendingSteps.remove(name);
    }
  }
}

final class CodeLabDependencies {
  const CodeLabDependencies({
    required this.application,
    required this.shellCubit,
    required this.logBuffer,
    required this.secretMigrationCubit,
    required this.navigationCubit,
    required this.terminalTabsCubit,
    required this.languageCubit,
    required this.appearanceCubit,
    required this.settingsPages,
    required this.createConnectionSettingsCubit,
    required this.createAddProfileCubit,
    required this.createProviderSettingsCubit,
    required this.createMcpSettingsCubit,
    required this.createSkillsSettingsCubit,
    required this.createAgentsModesCubit,
    required this.createAgentDefaultsCubit,
    required this.createStartupSettingsCubit,
    required this.createAppearanceSettingsCubit,
    required this.aboutPorts,
    required this.openEmbeddedWizard,
    this.projectFilesCubit,
  });

  final AcpClientApplication application;
  final CodeLabShellCubit shellCubit;

  /// Предупреждение и диалог переноса секретов встроенного агента (D8).
  final SecretMigrationCubit secretMigrationCubit;

  /// Переходы рабочее место ↔ настройки (design.md change
  /// `add-app-settings-shell`, D2).
  final NavigationCubit navigationCubit;

  /// Вкладки терминала пользователя (`add-integrated-terminal`, D3).
  final TerminalTabsCubit terminalTabsCubit;

  /// Единственный владелец языка интерфейса (D2).
  final AppLanguageCubit languageCubit;

  /// Единственный владелец оформления app (D13): режим, темы, системный акцент.
  final AppAppearanceCubit appearanceCubit;

  /// Страницы настроек, видимые в этой сборке.
  final SettingsPages settingsPages;

  /// Создаёт Cubit страницы «Connection»; страница владеет им и закрывает
  /// (design.md change `add-app-settings-shell`, D4).
  final ConnectionSettingsCubit Function() createConnectionSettingsCubit;

  /// Создаёт Cubit диалога «Add connection profile»; страница владеет им и
  /// закрывает вместе с диалогом (D12).
  final AddProfileCubit Function() createAddProfileCubit;

  /// Создаёт Cubit страницы «Providers»; страница владеет им и закрывает
  /// (design.md change `add-provider-setup-ui`, D10).
  final ProviderSettingsCubit Function() createProviderSettingsCubit;

  /// Создаёт Cubit страницы «MCP servers»; страница владеет им и закрывает
  /// (design.md change `add-provider-setup-ui`, D11).
  final McpSettingsCubit Function() createMcpSettingsCubit;

  /// Создаёт Cubit страницы «Skills & extensions»; страница владеет им и
  /// закрывает (change `add-app-skills-page`, D6).
  final SkillsSettingsCubit Function() createSkillsSettingsCubit;

  /// Создаёт Cubit страницы «Appearance»; страница владеет им и закрывает
  /// (change `add-app-appearance-page`, D13).
  final AppearanceSettingsCubit Function() createAppearanceSettingsCubit;

  /// Создаёт Cubit страницы «Agents & modes»; страница владеет им и закрывает
  /// (design.md change `add-settings-agents-modes`, D11).
  final AgentsModesCubit Function() createAgentsModesCubit;

  /// Создаёт Cubit блока «Agent defaults» страницы «General»; страница владеет
  /// им и закрывает (design.md change `add-app-general-page`, D7).
  final AgentDefaultsCubit Function() createAgentDefaultsCubit;

  /// Создаёт Cubit строки «Reopen the last project and its tabs» страницы
  /// «General»; страница владеет им и закрывает (design.md change
  /// `add-app-general-page`, D9).
  final StartupSettingsCubit Function() createStartupSettingsCubit;

  /// Данные и порты раздела «About» страницы «General» (design.md change
  /// `add-app-general-page`, D11).
  final AboutPorts aboutPorts;

  /// Открывает мастер встроенного агента из баннера соединения; владелец
  /// закрывает Cubit после диалога (design.md change `add-provider-setup-ui`,
  /// D26).
  final EmbeddedWizardOpener openEmbeddedWizard;

  /// Отдаёт Cubit панели Files — один на окно, создаётся лениво при первом
  /// вызове; панель его только читает и не закрывает. `null` — хост не
  /// привязал `ProjectFiles`, панель не предлагается (design.md change
  /// `add-file-preview-and-tree`, D6, D7).
  final ProjectFilesCubit Function()? projectFilesCubit;

  /// Backs the in-app log viewer (docked panel and full-screen master-detail
  /// — `replace-debug-log-panel-with-fluent/design.md`, Decision 3/4).
  /// Consumers build their own `LogViewerController` over this shared
  /// buffer, each with independent filter/pause state.
  final LogBuffer logBuffer;
}

final class CodeLabDependenciesScope extends InheritedWidget {
  const CodeLabDependenciesScope({
    required this.dependencies,
    required super.child,
    super.key,
  });

  final CodeLabDependencies dependencies;

  static CodeLabDependencies of(BuildContext context) {
    final inherited = context
        .dependOnInheritedWidgetOfExactType<CodeLabDependenciesScope>();
    assert(inherited != null, 'CodeLabDependenciesScope was not found.');
    return inherited!.dependencies;
  }

  @override
  bool updateShouldNotify(CodeLabDependenciesScope oldWidget) =>
      dependencies != oldWidget.dependencies;
}

class CodeLabBootstrap extends StatefulWidget {
  const CodeLabBootstrap({
    required this.child,
    this.scope,
    this.logDirectoryPath,
    this.profileSecrets,
    this.profileSecretsOpener,
    this.language,
    this.appearance,
    this.systemAccentSource,
    this.themeLibrary,
    super.key,
  });

  final Widget child;

  /// Начальное состояние языка из `main` (D2); без него — `en`.
  final AppLanguageStart? language;

  /// Начальное оформление из `main` (`add-app-appearance-page`, D13); без него
  /// — `Match system` и встроенные темы.
  final AppAppearanceStart? appearance;

  /// Порт системного акцента, уже прочитанный в `main` (D7).
  final SystemAccentSource? systemAccentSource;

  /// Каталог пользовательских тем, созданный в `main`.
  final ThemeLibrary? themeLibrary;
  final Scope? scope;

  /// Хранилище секретов, открытое в `main` (`openProfileSecrets`); без него
  /// и без [scope] токены профилей в хранилище недоступны.
  final ProfileSecrets? profileSecrets;

  /// Фабрика переоткрытия хранилища (`openProfileSecrets`).
  final Future<ProfileSecrets> Function()? profileSecretsOpener;

  /// Directory for logging sinks (`design.md` Decision 6) — resolved via
  /// `path_provider` in `main.dart` before `runApp()`, since that call is
  /// async and this widget's constructor must stay `const`-compatible.
  /// `null` (e.g. in tests that don't pass it) falls back to a temp
  /// directory, see [createCodeLabRootScope].
  final String? logDirectoryPath;

  @override
  State<CodeLabBootstrap> createState() => _CodeLabBootstrapState();
}

class _CodeLabBootstrapState extends State<CodeLabBootstrap> {
  late final Scope _scope =
      widget.scope ??
      createCodeLabRootScope(
        logDirectoryPath: widget.logDirectoryPath,
        profileSecrets: widget.profileSecrets,
        profileSecretsOpener: widget.profileSecretsOpener,
        language: widget.language,
        appearance: widget.appearance,
        systemAccentSource: widget.systemAccentSource,
        themeLibrary: widget.themeLibrary,
      );
  late final CodeLabDependencies _dependencies = CodeLabDependencies(
    application: _scope.resolve<AcpClientApplication>(),
    shellCubit: _scope.resolve<CodeLabShellCubit>(),
    logBuffer: _scope.resolve<LogBuffer>(),
    secretMigrationCubit: _scope.resolve<SecretMigrationCubit>(),
    navigationCubit: _scope.resolve<NavigationCubit>(),
    terminalTabsCubit: _scope.resolve<TerminalTabsCubit>(),
    languageCubit: _scope.resolve<AppLanguageCubit>(),
    appearanceCubit: _scope.resolve<AppAppearanceCubit>(),
    settingsPages: _scope.resolve<SettingsPages>(),
    createConnectionSettingsCubit: _scope.resolve<ConnectionSettingsCubit>,
    createAddProfileCubit: _scope.resolve<AddProfileCubit>,
    createProviderSettingsCubit: _scope.resolve<ProviderSettingsCubit>,
    createMcpSettingsCubit: _scope.resolve<McpSettingsCubit>,
    createSkillsSettingsCubit: _scope.resolve<SkillsSettingsCubit>,
    createAgentsModesCubit: _scope.resolve<AgentsModesCubit>,
    createAgentDefaultsCubit: _scope.resolve<AgentDefaultsCubit>,
    createStartupSettingsCubit: _scope.resolve<StartupSettingsCubit>,
    createAppearanceSettingsCubit: _scope.resolve<AppearanceSettingsCubit>,
    aboutPorts: _scope.resolve<AboutPorts>(),
    openEmbeddedWizard: _scope.resolve<EmbeddedWizardOpener>(),
    projectFilesCubit: _projectFilesCubitOf(_scope),
  );

  /// Слушатель запроса выхода от ОС; владелец — это состояние, `dispose`
  /// освобождает его (D4 «Выход из app», D15 п. 9). Без него при Cmd+Q не
  /// вызывается `CodeLabRootLifecycle.dispose()` — app зависает в ожидании
  /// isolate `pty2`, а процессы агента остаются сиротами
  /// (`add-client-process-shutdown-on-exit`, D1).
  late final AppLifecycleListener _exitListener;

  /// Мост пункта «Настройки…» нативного меню (macOS, ⌘,): открывает настройки
  /// тем же путём, что сочетание `open-settings`.
  late final AppMenuBridge _menuBridge;

  @override
  void initState() {
    super.initState();
    _menuBridge = AppMenuBridge(
      onOpenSettings: () => unawaited(
        _dependencies.navigationCubit.openSettings(
          source: SettingsOpenSource.shortcut,
        ),
      ),
    )..attach();
    final rootLifecycle = _scope.resolve<CodeLabRootLifecycle>();
    _exitListener = AppLifecycleListener(
      onExitRequested: AppExitHandler(
        closeRoot: rootLifecycle.dispose,
        pendingSteps: () => rootLifecycle.pendingSteps,
        logger: codeLabAppLogger(),
        flushLogs: _scope.resolve<CodeLabLoggingLifecycle>().flushed,
      ).onExitRequested,
    );
  }

  @override
  void dispose() {
    _exitListener.dispose();
    _menuBridge.dispose();
    final providedScope = widget.scope;
    if (providedScope == null) {
      unawaited(closeCodeLabRootScope());
    } else {
      unawaited(providedScope.dispose());
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return CodeLabDependenciesScope(
      dependencies: _dependencies,
      child: widget.child,
    );
  }
}

/// Лениво создаваемый Cubit панели Files окна.
///
/// Почему: `Scope.dispose()` закрывает только `Disposable`, а Cubit создаётся
/// по требованию; держатель закрывает его, если он был создан.
final class ProjectFilesHolder implements Disposable {
  ProjectFilesHolder(this._create);

  final ProjectFilesCubit Function() _create;
  ProjectFilesCubit? _cubit;

  ProjectFilesCubit get cubit => _cubit ??= _create();

  @override
  Future<void> dispose() async {
    // Закрытие Cubit чисто локальное и сбоем не кончается; не ждём его: в
    // тестах scope закрывается внутри fake-async зоны, где ожидание потока
    // без кадра не завершилось бы (см. `closeCodeLabRootScopeInTest`).
    final cubit = _cubit;
    if (cubit != null) {
      unawaited(cubit.close());
    }
  }
}

/// Фабрика Cubit панели Files окна; `null`, если `ProjectFiles` не привязан.
/// Держатель резолвится сразу, чтобы scope закрыл его при `dispose`.
ProjectFilesCubit Function()? _projectFilesCubitOf(Scope scope) {
  if (scope.tryResolve<ProjectFiles>() == null) return null;
  final holder = scope.resolve<ProjectFilesHolder>();
  return () => holder.cubit;
}

AcpTransport _createDefaultTransport() =>
    StdioAcpTransport(codelabAgentStdioProfile.toTransportConfig());

AcpTransport _createStdioTransport(StdioAcpTransportConfig config) =>
    StdioAcpTransport(config);

AcpTransport _createWebSocketTransport(WebSocketAcpTransportConfig config) =>
    WebSocketAcpTransport(config);

/// Папка для страниц «Providers» и «MCP servers» (D8 change
/// `require-project-folder`): папка сессии в фокусе, а без неё — выбранный
/// проект.
///
/// Почему не только проект: агент обслуживает сессии разных папок (D11), и
/// слои конфигурации проекта относятся к папке той сессии, которую пользователь
/// сейчас видит. Корень диска как папка слоёв не берётся: проектного слоя там
/// нет, поэтому выбирается проект.
String? _focusFolder(Scope scope) {
  final workspace = scope.resolve<ClientWorkspace>().current;
  final active = workspace.activeSessionId;
  if (active != null) {
    for (final summary in workspace.sessions) {
      if (summary.id == active &&
          summary.cwd.trim().isNotEmpty &&
          !isFilesystemRoot(summary.cwd)) {
        return summary.cwd;
      }
    }
  }
  return scope.resolve<CodeLabShellParts>().settings.projectDirectory;
}
