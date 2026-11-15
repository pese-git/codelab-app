// Сессия настроек страницы «Skills & extensions» на НАСТОЯЩЕМ
// `FileAgentConfigStore` во временных `CODELAB_HOME` и проекте (задача 5.1
// change `add-app-skills-page`; design.md D5, D9, D14).
//
// Почему не `FakeAgentConfigStore`: правило записи `skillsListEdit` опирается
// на `origins`, на доверие проекта (`loaded.config.trusted_projects`) и на
// сырые списки слоёв; двойник конфига итога загрузки не строит. Файлы читает и
// пишет настоящее хранилище, поэтому тест проверяет итоговые `config.yaml` и
// `config.local.yaml`. Вид страницы (`extensions`) строит тест: чтение файлов
// навыков проверяет мост, здесь важна только запись. Реальных `~/.codelab` и
// секретов нет: бэкенд секретов — `env` (только для чтения), значений нет.

import 'dart:io';

import 'package:codelab_desktop/app/embedded_logger.dart';
import 'package:codelab_desktop/features/settings/application/provider_settings_session.dart';
import 'package:codelab_setup/codelab_setup.dart';
import 'package:codelab_setup/io.dart' as setup;

import 'fake_agent_extensions.dart';
import 'recording_logger.dart';

/// Конфиг пользователя: провайдер (чтобы загрузчик построил `loaded.config`)
/// и [extra] — дописанные строки.
String skillsHomeConfig({String extra = ''}) => '''
agent:
  default_model: local/m
providers:
  local:
    kind: openai-compatible
    base_url: http://127.0.0.1:9/v1
    models:
      m:
        context_window: 32000
$extra''';

final class RealSkillsSession implements ProviderSettingsSession {
  RealSkillsSession._(this.home, this.project, this.config, this.trustedPath);

  /// Каталог `CODELAB_HOME` (временный).
  final String home;

  /// Папка проекта (временная).
  final String project;

  /// Канонический путь проекта: так его сравнивает `trusted_projects`
  /// (на macOS временный каталог лежит за симлинком `/var`).
  final String trustedPath;

  @override
  final AgentConfigStore config;

  /// Вид страницы; тест подменяет, чтобы вернуть свой.
  Future<AgentExtensionsView> Function(AgentConfigSnapshot snapshot)?
  onExtensions;

  /// Снимки, с которыми вызывали `extensions`.
  final extensionsCalls = <AgentConfigSnapshot>[];

  String get userConfig => '$home/config.yaml';
  String get projectConfig => '$project/.codelab/config.yaml';
  String get localConfig => '$project/.codelab/config.local.yaml';

  /// Пишет файл [path] целиком (создаёт каталоги).
  static void write(String path, String text) => File(path)
    ..parent.createSync(recursive: true)
    ..writeAsStringSync(text);

  /// Открывает сессию на [root] (временный каталог теста): `root/home` и
  /// `root/project`. [trusted] — записывает проект в `trusted_projects`.
  static Future<RealSkillsSession> open(
    Directory root, {
    bool trusted = true,
    String extra = '',
  }) async {
    final home = '${root.path}/home';
    final project = '${root.path}/project';
    Directory(home).createSync(recursive: true);
    Directory(project).createSync(recursive: true);
    final canonical = Directory(project).resolveSymbolicLinksSync();
    write(
      '$home/config.yaml',
      skillsHomeConfig(
        extra: '${trusted ? 'trusted_projects: [$canonical]\n' : ''}$extra',
      ),
    );
    final environment = {'HOME': home, 'CODELAB_HOME': home};
    final secrets = await setup.ClientSecretAccess.open(
      codelabHome: home,
      environment: environment,
      logger: CodeLabEmbeddedLogger(logger: RecordingLogger()),
    );
    return RealSkillsSession._(
      home,
      project,
      setup.FileAgentConfigStore(
        paths: ConfigPaths(codelabHome: home, projectDir: project),
        environment: environment,
        secrets: secrets,
      ),
      canonical,
    );
  }

  @override
  Future<AgentExtensionsView> extensions(AgentConfigSnapshot snapshot) {
    extensionsCalls.add(snapshot);
    return (onExtensions ?? (_) async => extensionsView(folder: project))(
      snapshot,
    );
  }

  @override
  SecretBackendInfo get backend =>
      const SecretBackendInfo(id: 'env', writable: false);

  @override
  Future<bool> isSecretSet(String name) async => false;

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
  McpServerCommitter mcpCommitter() => throw UnimplementedError('mcp');

  @override
  McpServerRemover mcpRemover() => throw UnimplementedError('mcp');

  @override
  Future<ProviderCheckResult> checkProvider({
    required String kind,
    required Uri baseUrl,
    required KeyStatusView key,
    CancelToken? cancel,
  }) => throw UnimplementedError('checkProvider');
}
