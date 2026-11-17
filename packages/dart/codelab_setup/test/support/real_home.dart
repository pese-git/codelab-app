import 'dart:io';

import 'package:codelab_agent_core/testing.dart';
import 'package:codelab_setup/codelab_setup.dart';
import 'package:codelab_setup/io.dart';

/// Временный `CODELAB_HOME` с настоящим `FileAgentConfigStore`: снимки для
/// тестов признака «нет провайдера» и готовности строит загрузчик, а не тест
/// (design.md change `add-provider-setup-ui`, D26).
final class RealHome {
  RealHome._(this.root, this.home, this.project);

  factory RealHome.create(String prefix) {
    final root = Directory.systemTemp.createTempSync(prefix);
    final home = '${root.path}/home';
    final project = '${root.path}/project';
    Directory(home).createSync();
    Directory(project).createSync();
    Process.runSync('/bin/chmod', ['700', home]);
    return RealHome._(root, home, project);
  }

  final Directory root;
  final String home;
  final String project;
  final logger = RecordingLogger();

  void writeConfig(String text) =>
      File('$home/config.yaml').writeAsStringSync(text);

  Future<AgentConfigSnapshot> load([
    Map<String, String> extraEnv = const {},
  ]) async {
    final environment = {'HOME': root.path, 'CODELAB_HOME': home, ...extraEnv};
    final store = FileAgentConfigStore(
      paths: ConfigPaths(codelabHome: home, projectDir: project),
      environment: environment,
      secrets: await ClientSecretAccess.open(
        codelabHome: home,
        environment: environment,
        logger: logger,
      ),
      logger: logger,
    );
    return store.snapshot(cwd: project);
  }

  void dispose() => root.deleteSync(recursive: true);
}

/// Конфиг с провайдером `gw` и моделью `m`.
const gatewayProvider = '''
providers:
  gw:
    kind: openai-compatible
    base_url: https://gw.test/v1
    models:
      m:
        context_window: 8000
''';
