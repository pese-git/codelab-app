// Сессия настроек на НАСТОЯЩЕМ `FileAgentConfigStore` во временном
// `CODELAB_HOME` (задача 6.1b-2 change `add-provider-setup-ui`; design.md D11
// «Итерация 6: сервер, отложенный до перезапуска»).
//
// Почему не `FakeAgentConfigStore`: признак «сервер заработает после Restart
// agent» даёт правило ядра `planConfigReload` по `loaded.config` снимков, а
// двойник конфига `loaded.config` не строит. Правило не подменяется моком:
// снимки читает настоящий загрузчик, секреты — по-прежнему двойник
// (`FakeWizardKeys`), значения в файл секретов не попадают.

import 'dart:io';

import 'package:codelab_desktop/app/embedded_logger.dart';
import 'package:codelab_desktop/features/settings/application/provider_settings_session.dart';
import 'package:codelab_setup/codelab_setup.dart';
import 'package:codelab_setup/io.dart' as setup;

import 'fake_provider_wizard.dart';
import 'recording_logger.dart';

/// Конфиг дома с одним локальным провайдером: достаточно, чтобы загрузчик
/// построил `loaded.config`. Бэкенд секретов — по умолчанию (`env`, только
/// для чтения): значения идут в двойник `FakeWizardKeys`, а файловому
/// бэкенду нужны права 0700 на дом, то есть внешний процесс `chmod`.
const realHomeConfig = '''
agent:
  default_model: local/m
providers:
  local:
    kind: openai-compatible
    base_url: http://127.0.0.1:9/v1
    models:
      m:
        context_window: 32000
''';

final class RealConfigSession implements ProviderSettingsSession {
  RealConfigSession._(this.config, this.secrets, this.access)
    : mcpKeys = FakeWizardKeys(secrets);

  /// Открывает сессию на каталоге [home] (должен существовать) с проектной
  /// папкой [project]. Записывает [config] в `config.yaml` дома.
  static Future<RealConfigSession> open({
    required String home,
    required String project,
    String config = realHomeConfig,
  }) async {
    File('$home/config.yaml').writeAsStringSync(config);
    final environment = {'HOME': home, 'CODELAB_HOME': home};
    final access = await setup.ClientSecretAccess.open(
      codelabHome: home,
      environment: environment,
      logger: CodeLabEmbeddedLogger(logger: RecordingLogger()),
    );
    final store = _HookedStore(
      setup.FileAgentConfigStore(
        paths: ConfigPaths(codelabHome: home, projectDir: project),
        environment: environment,
        secrets: access,
      ),
    );
    return RealConfigSession._(
      store,
      {},
      EditableSettings(ConfigPaths(codelabHome: home, projectDir: project)),
    );
  }

  @override
  final AgentConfigStore config;

  /// Свежие снимки получают `loaded.values`, которое бросает при обходе:
  /// расчёт `restartRequiredServers` падает (путь `restart_hint_failed`).
  /// Остальные поля снимка настоящие.
  set breakRestartRule(bool value) => (config as _HookedStore).breaks = value;

  /// Доступ профиля: тот же дом и проект, что у хранилища.
  final EditableSettings access;

  /// Окружение агента для `UseEnvVar` мастера.
  Map<String, String> environment = const {};

  /// Проверка `/models` мастера: ответы даёт тест.
  final wizardCheck = FakeWizardCheck();

  /// Секреты двойника: порт `ProviderKeys` страницы.
  final Map<String, String> secrets;
  final FakeWizardKeys mcpKeys;

  @override
  SecretBackendInfo get backend =>
      const SecretBackendInfo(id: 'file', writable: true);

  @override
  Future<bool> isSecretSet(String name) async => secrets.containsKey(name);

  /// Исключение из `mcpCommitter()`/`mcpRemover()` (после начала записи).
  Object? portError;

  @override
  McpServerCommitter mcpCommitter() {
    if (portError case final error?) {
      throw error;
    }
    return McpServerCommitter(config: config, keys: mcpKeys);
  }

  @override
  McpServerRemover mcpRemover() {
    if (portError case final error?) {
      throw error;
    }
    return McpServerRemover(config: config, keys: mcpKeys);
  }

  @override
  Future<SecretDeletion> deleteSecret(String name) =>
      throw UnimplementedError('deleteSecret');

  @override
  Future<ProviderSetupFlow> openWizard({
    ProviderEntryView? editing,
    bool forceDefault = false,
    ProviderWizardEntry entry = ProviderWizardEntry.app,
  }) async {
    return buildWizardFlow(
      store: config,
      keys: mcpKeys,
      check: wizardCheck,
      access: access,
      environment: environment,
      log: RecordingLogger(),
      editing: editing,
      forceDefault: forceDefault,
      entry: entry,
    );
  }

  @override
  Future<ProviderCheckResult> checkProvider({
    required String kind,
    required Uri baseUrl,
    required KeyStatusView key,
    CancelToken? cancel,
  }) => throw UnimplementedError('checkProvider');
}

/// Настоящее хранилище с переключаемой порчей `loaded.values` снимков.
final class _HookedStore implements AgentConfigStore {
  _HookedStore(this._inner);

  final AgentConfigStore _inner;
  var breaks = false;

  @override
  Future<AgentConfigSnapshot> snapshot({required String cwd}) async {
    final real = await _inner.snapshot(cwd: cwd);
    if (!breaks) {
      return real;
    }
    return AgentConfigSnapshot(
      cwd: real.cwd,
      layers: real.layers,
      loaded: ConfigLoadResult(
        config: real.loaded.config,
        host: real.loaded.host,
        issues: real.loaded.issues,
        values: _ThrowingValues(),
      ),
      origins: real.origins,
      secrets: real.secrets,
    );
  }

  @override
  Future<ConfigSaveOutcome> apply(
    ConfigSnapshot base,
    List<ConfigEdit> edits,
  ) => _inner.apply(base, edits);
}

/// Карта, которая «не пуста», но бросает при любом обходе.
final class _ThrowingValues implements Map<String, Object?> {
  @override
  bool get isNotEmpty => true;

  @override
  bool get isEmpty => false;

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw StateError('values are not readable');
}
