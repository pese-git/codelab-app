// ignore_for_file: experimental_member_use

import 'dart:async';
import 'dart:io';

import 'package:codelab_client_acp/codelab_client_acp.dart';
import 'package:codelab_client_io/codelab_client_io.dart'
    show
        DirectoryExists,
        JsonFileProfileStore,
        classifyProbeFailure,
        IoTerminalProcessRunner,
        IoTextFileIo,
        IoWorkingDirectoryProvider,
        ioDirectoryExists,
        WorkingDirectoryProvider;
import 'package:codelab_client_core/codelab_client_core.dart'
    show
        AcpClientBackend,
        ClientWorkspace,
        ConfigTransportResolver,
        ProfileProbe,
        ProfileSecretSource,
        ProfileSecrets,
        ProfileStore,
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
import '../core/platform/limited_network_image.dart';
import '../core/platform/project_folder_picker.dart';
import '../core/platform/shared_preferences_recent_projects_store.dart';
import '../core/platform/shared_preferences_workspace_snapshot_store.dart';
import '../features/settings/application/add_profile_cubit.dart';
import '../features/settings/application/connection_settings_cubit.dart';
import '../features/settings/application/default_profile_resolver.dart';
import '../features/settings/application/embedded_profile.dart';
import '../features/settings/application/profiles_unavailable.dart';
import '../features/settings/application/mcp_settings_cubit.dart';
import '../features/settings/application/provider_settings_cubit.dart';
import '../features/settings/application/provider_wizard_cubit.dart';
import '../features/workbench/application/secret_migration_cubit.dart';
import '../features/workbench/application/secret_migration_runner.dart';
import '../features/workbench/application/secret_migration_turns.dart';
import '../features/workbench/application/shell_cubit.dart';
import 'client_profile_secrets.dart'
    show DescribedProfileSecrets, UnavailableProfileSecrets;
import 'reopenable_profile_secrets.dart';
import 'default_settings_pages.dart';
import 'embedded_logger.dart';
import 'embedded_mcp_status_source.dart';
import 'embedded_secret_migration_runner.dart';
import 'embedded_transport_resolver.dart';
import 'provider_settings_session.dart';
import 'provider_setup_offer.dart';
import 'provider_setup_probe.dart';
import 'navigation/navigation_cubit.dart';
import 'navigation/settings_page.dart';
import 'navigation/settings_page_store.dart';
import 'connection_environment.dart';
import 'secret_migration_offer.dart';

part 'app_scope.module.cherrypick.g.dart';

typedef CodeLabTransportFactory = AcpTransport Function();

Scope createCodeLabRootScope({
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
      CodeLabPlatformModule(
        directoryExists: directoryExists ?? ioDirectoryExists,
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
      ),
      $CodeLabTransportsModuleContract(),
      $CodeLabProtocolApplicationModuleContract(),
      $CodeLabRootLifecycleModuleContract(),
    ]);

  scope.resolve<CodeLabRootLifecycle>();
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

  @override
  Future<void> dispose() => Future.wait([
    if (applicationOutput != null) applicationOutput!.flushed,
    protocolTraceOutput.flushed,
    if (httpOutput != null) httpOutput!.close(),
  ]);
}

final class CodeLabPlatformModule extends Module {
  CodeLabPlatformModule({required this.directoryExists});

  /// Проверка папки проекта; тесты с вымышленными путями подменяют её.
  final DirectoryExists directoryExists;

  @override
  void builder(Scope currentScope) {
    bind<WorkingDirectoryProvider>().toInstance(
      const IoWorkingDirectoryProvider(),
    );
    // Проверка папки проекта до восстановления и подключения.
    bind<DirectoryExists>().toInstance(directoryExists);
    const textFileIo = IoTextFileIo();
    bind<TextFileReader>().toInstance(textFileIo);
    bind<TextFileWriter>().toInstance(textFileIo);
    // Открытие ссылок из ответа агента — порт платформы (change
    // `add-desktop-markdown`, D5); `url_launcher` только за ним.
    bind<ExternalLinkOpener>().toInstance(
      const UrlLauncherExternalLinkOpener(),
    );
    // Загрузка изображений ответа: лимиты тела, редиректы, размер (D6, R4).
    bind<ImageProviderFor>().toInstance(defaultImageProviderFor);
    bind<ProjectFolderPicker>().toInstance(
      const FileSelectorProjectFolderPicker(),
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
    ProviderSettingsOpener? providerSettingsOpener,
  }) : _settingsPages = settingsPages,
       _providerSettingsOpener = providerSettingsOpener;

  /// Открывает доступ к настройкам агента страницы «Providers»; шов тестов
  /// (`createCodeLabRootScope(providerSettingsOpener:)`): без него — IO-сессия
  /// `openProviderSettingsSession` (design.md change `add-provider-setup-ui`,
  /// D4, D5).
  final ProviderSettingsOpener? _providerSettingsOpener;

  /// Страницы настроек, видимые в этой сборке; шов тестов
  /// (`createCodeLabRootScope(settingsPages:)`, design.md change
  /// `add-app-settings-shell`, D3).
  final SettingsPages _settingsPages;

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
            workingDirectoryProvider: currentScope
                .resolve<WorkingDirectoryProvider>(),
            projectFolderPicker: currentScope.resolve<ProjectFolderPicker>(),
            recentProjectsStore: currentScope.resolve<RecentProjectsStore>(),
            directoryExists: currentScope.resolve<DirectoryExists>(),
            dockLayoutStore: currentScope.resolve<DockLayoutStore>(),
            defaultProfiles: currentScope.resolve<DefaultProfileResolver>(),
            preferences: currentScope.resolve<ConnectionPreferences>(),
            tokenSecrets: currentScope.resolve<ProfileSecretSource>(),
            eventLogger: _settingsLogger(),
            providerSetupOffer: currentScope.resolve<ProviderSetupOffer>(),
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
    bind<CodeLabShellCubit>()
        .toProvide(
          () => CodeLabShellCubit(
            application: currentScope.resolve<AcpClientApplication>(),
            workspace: currentScope.resolve<ClientWorkspace>(),
            parts: currentScope.resolve<CodeLabShellParts>(),
            workingDirectoryProvider: currentScope
                .resolve<WorkingDirectoryProvider>(),
            projectFolderPicker: currentScope.resolve<ProjectFolderPicker>(),
            recentProjectsStore: currentScope.resolve<RecentProjectsStore>(),
            externalLinkOpener: currentScope.resolve<ExternalLinkOpener>(),
            imageProviderFor: currentScope.resolve<ImageProviderFor>(),
            // События ленты (`link.open`, `image.show`) — компонент workbench,
            // а не настроек.
            eventLogger: _workbenchLogger(),
          ),
        )
        .singleton();
    // Проверка профиля («Test connection»): те же резолверы, что у
    // `ClientWorkspace`, и классификатор ошибок IO-транспортов (D12). Токен
    // даёт тот же `ProfileSecretSource` (D15).
    bind<ProfileProbe>()
        .toProvide(
          () => ProfileProbe(
            resolvers: _transportResolvers(currentScope),
            classifier: classifyProbeFailure,
          ),
        )
        .singleton();
    // Диалог «Add connection profile»: новый Cubit на каждое открытие;
    // закрывает его страница вместе с диалогом (D12).
    bind<AddProfileCubit>().toProvide(() {
      final environment = currentScope.resolve<ConnectionEnvironment>();
      return AddProfileCubit(
        store: currentScope.resolve<ProfileStore>(),
        openSecrets: currentScope.resolve<ReopenableProfileSecrets>().reopen,
        preferences: currentScope.resolve<ConnectionPreferences>(),
        probe: currentScope.resolve<ProfileProbe>(),
        // Типы профилей определяют резолверы, а не проверка платформы
        // (SETUP-22, AGENTS.md §11).
        kinds: profileKindsFor(_transportResolvers(currentScope)),
        environment: environment.variables,
        profilesPath: environment.profilesPath,
        projectDirectory: () =>
            currentScope.resolve<CodeLabShellParts>().settings.projectDirectory,
        logger: _settingsLogger(),
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
        probe: currentScope.resolve<ProfileProbe>(),
        projectDirectory: () =>
            currentScope.resolve<CodeLabShellParts>().settings.projectDirectory,
        logger: _settingsLogger(),
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
        projectDirectory: () =>
            currentScope.resolve<CodeLabShellParts>().settings.projectDirectory,
        logger: _settingsLogger(),
        connect: () => currentScope.resolve<CodeLabShellCubit>().connect(),
      );
    });
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
        projectDirectory: () =>
            currentScope.resolve<CodeLabShellParts>().settings.projectDirectory,
        statusSource: ResolverMcpStatusSource(
          currentScope.resolve<EmbeddedTransportResolver>(),
        ),
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

/// Структурный логгер событий настроек (design.md change
/// `add-app-settings-shell`, D17): категория `application`, компонент
/// `settings`.
Logger _workbenchLogger() => StructuredLogLogger(
  'codelab_desktop.workbench',
).bind({logCategoryKey: applicationLogCategory, logComponentKey: 'workbench'});

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
  );
}

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
  }) : _application = application,
       _transport = transport,
       _workspace = workspace,
       _embedded = embedded,
       _embeddedCloseSettings = embeddedCloseSettings,
       _shellCubit = shellCubit,
       _secretMigrationCubit = secretMigrationCubit,
       _secretMigrationOffer = secretMigrationOffer,
       _navigationCubit = navigationCubit;

  final AcpClientApplication _application;
  final AcpTransport _transport;

  /// Закрывается после Cubit (его подписчика) и до ядра клиента: kit не
  /// закрывает `AcpClientApplication` сам.
  final ClientWorkspace _workspace;

  /// Закрывается после рабочего пространства и до ядра клиента: агент
  /// отменяет ход и дописывает журнал, пока клиентский конец жив; закрытие
  /// ждёт `dispose` агента и открытие в полёте (design.md change
  /// `add-embedded-agent-mode`, D6, D9).
  final EmbeddedTransportResolver _embedded;
  final EmbeddedCloseSettings _embeddedCloseSettings;
  final CodeLabShellCubit _shellCubit;

  /// Закрывается вместе с Cubit рабочего места: подписки на предложение и ход
  /// освобождаются до закрытия агента.
  final SecretMigrationCubit _secretMigrationCubit;

  /// Закрывается после резолвера: он до конца пишет в источник.
  final SecretMigrationOffer _secretMigrationOffer;
  final NavigationCubit _navigationCubit;
  var _isDisposed = false;

  @override
  Future<void> dispose() async {
    if (_isDisposed) {
      return;
    }

    _isDisposed = true;
    await _navigationCubit.close();
    await _secretMigrationCubit.close();
    await _shellCubit.close();
    await _workspace.dispose();
    // Зависший `dispose` агента не держит закрытие scope вечно: по таймауту
    // пишется событие без текста ошибки, а транспорт и ядро клиента всё равно
    // освобождаются (design.md change `add-embedded-agent-mode`, D6).
    await _embedded.close().timeout(
      _embeddedCloseSettings.timeout,
      onTimeout: () => _embeddedCloseSettings.logger.log(
        agent.LogLevel.warning,
        'embedded.close_timeout',
      ),
    );
    await _secretMigrationOffer.close();
    await _transport.close();
    await _application.dispose();
  }
}

final class CodeLabDependencies {
  const CodeLabDependencies({
    required this.application,
    required this.shellCubit,
    required this.logBuffer,
    required this.secretMigrationCubit,
    required this.navigationCubit,
    required this.settingsPages,
    required this.createConnectionSettingsCubit,
    required this.createAddProfileCubit,
    required this.createProviderSettingsCubit,
    required this.createMcpSettingsCubit,
    required this.openEmbeddedWizard,
  });

  final AcpClientApplication application;
  final CodeLabShellCubit shellCubit;

  /// Предупреждение и диалог переноса секретов встроенного агента (D8).
  final SecretMigrationCubit secretMigrationCubit;

  /// Переходы рабочее место ↔ настройки (design.md change
  /// `add-app-settings-shell`, D2).
  final NavigationCubit navigationCubit;

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

  /// Открывает мастер встроенного агента из баннера соединения; владелец
  /// закрывает Cubit после диалога (design.md change `add-provider-setup-ui`,
  /// D26).
  final EmbeddedWizardOpener openEmbeddedWizard;

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
    super.key,
  });

  final Widget child;
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
      );
  late final CodeLabDependencies _dependencies = CodeLabDependencies(
    application: _scope.resolve<AcpClientApplication>(),
    shellCubit: _scope.resolve<CodeLabShellCubit>(),
    logBuffer: _scope.resolve<LogBuffer>(),
    secretMigrationCubit: _scope.resolve<SecretMigrationCubit>(),
    navigationCubit: _scope.resolve<NavigationCubit>(),
    settingsPages: _scope.resolve<SettingsPages>(),
    createConnectionSettingsCubit: _scope.resolve<ConnectionSettingsCubit>,
    createAddProfileCubit: _scope.resolve<AddProfileCubit>,
    createProviderSettingsCubit: _scope.resolve<ProviderSettingsCubit>,
    createMcpSettingsCubit: _scope.resolve<McpSettingsCubit>,
    openEmbeddedWizard: _scope.resolve<EmbeddedWizardOpener>(),
  );

  @override
  void dispose() {
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

AcpTransport _createDefaultTransport() =>
    StdioAcpTransport(codelabAgentStdioProfile.toTransportConfig());

AcpTransport _createStdioTransport(StdioAcpTransportConfig config) =>
    StdioAcpTransport(config);

AcpTransport _createWebSocketTransport(WebSocketAcpTransportConfig config) =>
    WebSocketAcpTransport(config);
