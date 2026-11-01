import 'dart:convert';
import 'dart:io';
import 'dart:isolate';

import 'package:test/test.dart';

/// Тестовое хранилище секретов встроенного агента (embedded-agent, сценарий
/// «Тестовое хранилище только в тестовой сборке»; design.md change
/// `add-embedded-agent-mode`, D5).
///
/// Почему процессный тест: `const bool.fromEnvironment('CODELAB_ALLOW_TEST_SECRETS')`
/// вычисляется при компиляции, поэтому оба варианта сборки проверяются
/// запуском зонда `dart run` с define и без него. Каталоги и окружение —
/// временные, сети нет (`MockClient` в зонде).
void main() {
  const value = 'sk-test-0123456789abcdef';

  late Directory temp;
  late String home;
  late String store;
  late String project;
  late String packageRoot;

  setUp(() async {
    temp = Directory.systemTemp.createTempSync('codelab_test_store_');
    home = '${temp.path}/home';
    store = '${temp.path}/s';
    project = '${temp.path}/project';
    for (final dir in [home, store, project]) {
      Directory(dir).createSync();
      Process.runSync('/bin/chmod', ['700', dir]);
    }
    File('$home/config.yaml').writeAsStringSync('''
providers:
  p:
    kind: openai-compatible
    base_url: https://p.test/v1
    api_key_secret: codelab/p
    models:
      m: {}
agent:
  default_model: p/m
''');
    final secrets = File('$store/secrets.yaml')
      ..writeAsStringSync('"codelab/p": "$value"\n');
    Process.runSync('/bin/chmod', ['600', secrets.path]);
    final lib = await Isolate.resolvePackageUri(
      Uri.parse('package:codelab_embedded/io.dart'),
    );
    packageRoot = File.fromUri(lib!).parent.parent.path;
  });

  tearDown(() => temp.deleteSync(recursive: true));

  Future<Map<String, Object?>> probe({required bool allowTestSecrets}) async {
    final result = await Process.run(Platform.resolvedExecutable, [
      'run',
      if (allowTestSecrets) '-DCODELAB_ALLOW_TEST_SECRETS=true',
      'test/io/support/secret_store_probe.dart',
      home,
      store,
      project,
    ], workingDirectory: packageRoot);
    expect(result.exitCode, 0, reason: '${result.stderr}');
    return jsonDecode((result.stdout as String).trim().split('\n').last)
        as Map<String, Object?>;
  }

  test('with -DCODELAB_ALLOW_TEST_SECRETS=true the variable selects the file '
      'backend and the turn uses the key', () async {
    final report = await probe(allowTestSecrets: true);

    expect(report['authorizations'], ['Bearer $value']);
    expect(report['backends'], ['file']);
    expect(report['unknownVariables'], isEmpty);
    expect(report['outcome'], isNot(contains(value)));
  }, timeout: const Timeout(Duration(minutes: 2)));

  test('without the define the same variable is config.env.unknown and the '
      'directory is not read', () async {
    final report = await probe(allowTestSecrets: false);

    expect(report['authorizations'], isEmpty);
    expect(report['backends'], ['env']);
    expect(report['unknownVariables'], ['CODELAB_TEST_SECRET_STORE']);
    expect(report['outcome'], contains('codelab/p'));
  }, timeout: const Timeout(Duration(minutes: 2)));
}
