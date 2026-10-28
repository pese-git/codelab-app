import 'dart:io';

import 'package:codelab_acp_testing/codelab_acp_testing.dart';

import 'cli_process.dart';

/// Процессный `FixtureReplayAgent` для тестов `test-scenario`.
///
/// Почему kernel: драйвер запускает агента заново на каждую фикстуру, а
/// исходник повторителя импортирует пакет фикстур — компиляция при каждом
/// запуске заняла бы минуты (design.md change `add-codelab-cli`, D11, D12).
///
/// Как использовать: `await replayAgentProfile()` — значение `--agent` с
/// `{fixture}`: повторитель играет ту фикстуру, которую проигрывает драйвер;
/// [fixturePath] — играть другую (исходную при испорченной копии).
Future<String> replayAgentProfile({String? fixturePath}) async {
  final kernel = await (_kernel ??= _compile());
  return "stdio:'${dartExecutable()}' '$kernel' '${fixturePath ?? '{fixture}'}'";
}

Future<String>? _kernel;

Future<String> _compile() async {
  final dir = await Directory.systemTemp.createTemp('fixture_replay_kernel_');
  final source = await writeFixtureReplayAgent(dir);
  final packages = await fixtureReplayPackageConfig();
  final output = '${dir.path}/fixture_replay_agent.dill';
  final result = await Process.run(dartExecutable(), [
    'compile',
    'kernel',
    '--packages=$packages',
    source.path,
    '-o',
    output,
  ]);
  if (result.exitCode != 0) {
    throw StateError(
      'dart compile kernel failed:\n${result.stdout}\n${result.stderr}',
    );
  }
  return output;
}

/// Каталог корпуса golden-фикстур.
String get corpusDirectory => defaultFixtureCorpusDirectory();
