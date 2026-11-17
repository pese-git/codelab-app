import 'dart:io';

import 'package:codelab_agent_core/codelab_agent_core.dart';
import 'package:codelab_agent_io/src/cli/config_commands.dart'
    show ConfigCommandResult;
import 'package:codelab_agent_io/src/cli/config_edit_runner.dart';
import 'package:test/test.dart';

import '../support/fake_secret_process_runner.dart';

/// Общая часть подкоманд записи: типизированный исход и правки от снимка
/// (design.md change `add-config-writer-and-reload`, D6; ревью итерации 4,
/// arch M1+M2).
///
/// Исход — запечатанная иерархия: либо [EditWritten], либо [EditFinished] с
/// готовым результатом и типизированными проблемами; подкоманды выбирают
/// подсказку по `issue.key`, а не по подстроке текста. Временные каталоги,
/// настоящий `~/.codelab` не читается.
void main() {
  late Directory root;
  late String home;
  late String cwd;

  setUp(() {
    root = Directory(
      Directory.systemTemp
          .createTempSync('config_edit_runner')
          .resolveSymbolicLinksSync(),
    );
    home = '${root.path}/home';
    cwd = '${root.path}/proj';
    Directory(home).createSync();
    Directory(cwd).createSync();
    Process.runSync('/bin/chmod', ['700', home]);
  });

  tearDown(() => root.deleteSync(recursive: true));

  ConfigEditRunner runner() =>
      ConfigEditRunner(processRunner: FakeSecretProcessRunner());

  Future<ConfigEditOutcome> apply(
    List<ConfigEdit> Function(ConfigSnapshot snapshot) edits, {
    bool project = false,
    bool local = false,
    ConfigCommandResult? Function(ConfigSnapshot snapshot)? shortCircuit,
  }) => runner().apply(
    label: 'config set',
    environment: {'CODELAB_HOME': home},
    cwd: cwd,
    project: project,
    local: local,
    edits: edits,
    shortCircuit: shortCircuit,
  );

  test('успешная запись: EditWritten с результатом писателя', () async {
    final outcome = await apply((_) => [const SetValue('budget.max_steps', 5)]);

    expect(outcome, isA<EditWritten>());
    expect((outcome as EditWritten).result.path, '$home/config.yaml');
  });

  test('отказ валидации: EditFinished с кодом 1 и типизированными '
      'проблемами, ключ доступен как issue.key', () async {
    File('$home/config.yaml').writeAsStringSync('''
providers:
  p:
    kind: openai-compatible
    base_url: https://llm.test/v1
    models:
      m: {}
agent:
  default_model: p/m
''');

    final outcome = await apply(
      (_) => [const SetValue('agent.default_model', 'zzz/m')],
    );

    expect(outcome, isA<EditFinished>());
    final finished = outcome as EditFinished;
    expect(finished.result.exitCode, 1);
    expect(finished.issues, isNotEmpty);
    expect(finished.issues.map((i) => i.key), contains('agent.default_model'));
  });

  test('ошибка использования: EditFinished без проблем', () async {
    final outcome = await apply((_) => const [], project: true, local: true);

    expect(outcome, isA<EditFinished>());
    expect((outcome as EditFinished).issues, isEmpty);
    expect(outcome.result.exitCode, 64);
  });

  test('правки строятся от снимка попытки', () async {
    File('$home/config.yaml').writeAsStringSync('budget:\n  max_steps: 3\n');
    final seen = <Object?>[];

    final outcome = await apply((snapshot) {
      seen.add(snapshot.get('budget.max_steps'));
      return [const SetValue('budget.max_steps', 4)];
    });

    expect(outcome, isA<EditWritten>());
    expect(seen, [3]);
  });
}
