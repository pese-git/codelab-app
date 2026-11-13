import 'dart:io';

import 'package:codelab_agent_io/codelab_agent_io.dart';
import 'package:test/test.dart';

import '../support/fake_secret_process_runner.dart';

/// Запись ключей `subagents.*` через `config set` (agent-configuration
/// «Ключи subagents в схеме и реестре настроек», сценарий «Запись через
/// config set»; design.md change `add-subagents-and-tasks`, D17, D22).
///
/// Красный до задачи 2.2: у раздела `subagents` нет дескрипторов ключей
/// (он опаковый), поэтому `ConfigWriter` не проверяет диапазон и не знает
/// `subagents.max_concurrent`. Продолжение сценария — «после применения
/// перезагрузки следующий `spawn` использует 2 слота» — проверяет тест ядра
/// `subagent_limits_live_test.dart`.
///
/// Тест не читает настоящий `~/.codelab`: `CODELAB_HOME` и окружение
/// передаются явно.
void main() {
  late Directory root;
  late String home;
  late String cwd;
  late String userPath;

  const providers = '''
providers:
  p:
    kind: openai-compatible
    base_url: https://llm.test/v1
    models:
      m: {}
agent:
  default_model: p/m
''';

  setUp(() {
    root = Directory(
      Directory.systemTemp
          .createTempSync('config_set_subagents')
          .resolveSymbolicLinksSync(),
    );
    home = '${root.path}/home';
    cwd = '${root.path}/proj';
    Directory(home).createSync();
    Directory(cwd).createSync();
    Process.runSync('/bin/chmod', ['700', home]);
    userPath = '$home/config.yaml';
    File(userPath).writeAsStringSync(providers);
  });

  tearDown(() => root.deleteSync(recursive: true));

  Future<ConfigCommandResult> setKey(String key, String value) =>
      ConfigCommands(processRunner: FakeSecretProcessRunner()).set(
        ConfigSetOptions(
          key: key,
          value: value,
          cwd: cwd,
          environment: {'CODELAB_HOME': home},
        ),
      );

  String allOutput(ConfigCommandResult r) =>
      [...r.stdout, ...r.stderr].join('\n');

  test(
    'сценарий «Запись через config set»: 9 отклоняется проверкой '
    'ConfigWriter (код 1, байты файла не меняются), 2 записывается',
    () async {
      final bad = await setKey('subagents.max_concurrent', '9');

      expect(bad.exitCode, 1, reason: allOutput(bad));
      expect(allOutput(bad), contains('subagents.max_concurrent'));
      expect(File(userPath).readAsStringSync(), providers);

      final ok = await setKey('subagents.max_concurrent', '2');

      expect(ok.exitCode, 0, reason: allOutput(ok));
      expect(File(userPath).readAsStringSync(), contains('max_concurrent: 2'));
    },
  );

  test('глубина вне 1..3 отклоняется так же, 1 записывается', () async {
    final bad = await setKey('subagents.max_depth', '4');

    expect(bad.exitCode, 1, reason: allOutput(bad));
    expect(File(userPath).readAsStringSync(), providers);

    final ok = await setKey('subagents.max_depth', '1');

    expect(ok.exitCode, 0, reason: allOutput(ok));
    expect(File(userPath).readAsStringSync(), contains('max_depth: 1'));
  });
}
