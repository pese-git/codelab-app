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

Future<String> _compile() =>
    compileTestKernel('fixture_replay_agent.dill', (work, output) async {
      final source = await writeFixtureReplayAgent(work);
      final packages = await fixtureReplayPackageConfig();
      return Process.run(dartExecutable(), [
        'compile',
        'kernel',
        '--packages=$packages',
        source.path,
        '-o',
        output,
      ]);
    });

/// Каталог корпуса golden-фикстур.
String get corpusDirectory => defaultFixtureCorpusDirectory();
