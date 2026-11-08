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

/// Конфиг дома с одним локальным провайдером: достаточно, чтобы загрузчик
/// построил `loaded.config`.
const realHomeConfig = '''
secrets:
  backend: file
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
  RealConfigSession._(this.config, this.secrets)
    : mcpKeys = FakeWizardKeys(secrets);

  /// Открывает сессию на каталоге [home] (должен существовать) с проектной
  /// папкой [project]. Записывает [config] в `config.yaml` дома.
  static Future<RealConfigSession> open({
    required String home,
    required String project,
    String config = realHomeConfig,
  }) async {
    await Process.run('/bin/chmod', ['700', home]);
    File('$home/config.yaml').writeAsStringSync(config);
    final environment = {'HOME': home, 'CODELAB_HOME': home};
    final access = await setup.ClientSecretAccess.open(
      codelabHome: home,
      environment: environment,
      logger: CodeLabEmbeddedLogger(),
    );
    final store = setup.FileAgentConfigStore(
      paths: ConfigPaths(codelabHome: home, projectDir: project),
      environment: environment,
      secrets: access,
    );
    return RealConfigSession._(store, {});
  }

  @override
  final AgentConfigStore config;

  /// Секреты двойника: порт `ProviderKeys` страницы.
  final Map<String, String> secrets;
  final FakeWizardKeys mcpKeys;

  @override
  SecretBackendInfo get backend =>
      const SecretBackendInfo(id: 'file', writable: true);

  @override
  Future<bool> isSecretSet(String name) async => secrets.containsKey(name);

  @override
  McpServerCommitter mcpCommitter() =>
      McpServerCommitter(config: config, keys: mcpKeys);

  @override
  McpServerRemover mcpRemover() =>
      McpServerRemover(config: config, keys: mcpKeys);

  @override
  Future<SecretDeletion> deleteSecret(String name) =>
      throw UnimplementedError('deleteSecret');

  @override
  Future<ProviderSetupFlow> openWizard({
    ProviderEntryView? editing,
    bool forceDefault = false,
    ProviderWizardEntry entry = ProviderWizardEntry.app,
  }) => throw UnimplementedError('openWizard');

  @override
  Future<ProviderCheckResult> checkProvider({
    required String kind,
    required Uri baseUrl,
    required KeyStatusView key,
    CancelToken? cancel,
  }) => throw UnimplementedError('checkProvider');
}
