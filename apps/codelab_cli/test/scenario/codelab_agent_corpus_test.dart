// `test-scenario` на корпусе против настоящего `codelab-agent` (tasks 8.5;
// spec cli-scenario-driver «Команда test-scenario»; H-04; design.md change
// `add-codelab-cli`, D12).
//
// Бинарь агента — kernel из `apps/codelab_agent`, запущенный обёрткой с
// именем `codelab-agent`: драйвер узнаёт бинарь по имени команды и передаёт
// ему сценарий модели `--llm-script`. CLI не импортирует
// `package:codelab_agent_*` (сторож), агент — отдельный процесс.
@Timeout(Duration(minutes: 10))
library;

import 'dart:io';

import 'package:codelab_cli/codelab_cli.dart';
import 'package:test/test.dart';

import '../support/cli_process.dart';
import '../support/fake_cli_io.dart';
import '../support/replay_agent.dart';

/// Обёртка `codelab-agent` над kernel бинаря агента; `null` — kernel не
/// собирается.
Future<String?> _codelabAgent(Directory dir) async {
  final app = '$appDirectory/../codelab_agent';
  final kernel = '${dir.path}/codelab_agent.dill';
  final result = await Process.run(dartExecutable(), [
    'compile',
    'kernel',
    'bin/codelab_agent.dart',
    '-o',
    kernel,
  ], workingDirectory: app);
  if (result.exitCode != 0) {
    return null;
  }
  final wrapper = File('${dir.path}/codelab-agent')
    ..writeAsStringSync(
      "#!/bin/sh\nexec '${dartExecutable()}' '$kernel' \"\$@\"\n",
    );
  await Process.run('chmod', ['+x', wrapper.path]);
  return wrapper.path;
}

void main() {
  test('agent fixtures without a transport block pass against '
      'codelab-agent', () async {
    final dir = await Directory.systemTemp.createTemp('scenario_agent_');
    addTearDown(() => dir.delete(recursive: true));
    final agent = await _codelabAgent(dir);
    if (agent == null) {
      markTestSkipped('the codelab-agent kernel does not compile');
      return;
    }
    final io = FakeCliIo();

    final code = await runCodelab(
      [
        'test-scenario',
        corpusDirectory,
        '--agent',
        'stdio:$agent serve --stdio',
      ],
      environment: {'HOME': dir.path},
      io: io,
    );

    expect(code, 0, reason: io.stdoutText + io.stderrText);
    expect(io.stdoutText, isNot(contains('FAIL ')));
    expect(
      RegExp(r'^PASS ', multiLine: true).allMatches(io.stdoutText).length,
      greaterThan(10),
      reason: io.stdoutText,
    );
  }, testOn: '!windows');
}
