// E2E `cli/serve-alias-*` (change `retire-python-agent`, задача 1.7; spec
// codelab-cli «Алиас codelab serve»; design.md D6–D10): `codelab` и
// `codelab-agent` из kernel как отдельные процессы.
//
// `PATH` процесса — временный каталог с обёрткой `codelab-agent`, которая
// запускает kernel агента абсолютным путём `dart`; настоящий `~/.codelab` и
// сеть не используются, `CODELAB_HOME` и `HOME` изолированы, модель —
// сценарий `llm_scripts/normal.json`. Рабочий `bin/codelab.dart`
// ([CliEntry.production]) собирается один раз на изолят.
//
// Тег `scripted-only`: тесты не зависят от агента матрицы, `dart-agent` и
// `embedded` их не гоняют повторно (D5 change `add-cli-e2e-agent-matrix`).
// Это не доказательства строк матрицы: `parity_evidence_test` их не ищет.
@Timeout(Duration(seconds: 180))
library;

import 'dart:convert';
import 'dart:io';

import 'package:test/test.dart';

import '../support/cli_process.dart';
import 'support/dual_binary.dart';
import 'support/e2e_agent.dart';

/// Предупреждение алиаса буквально из спецификации: тест не импортирует
/// константу кода, чтобы опечатка в коде не прошла сверку с самой собой.
const _warning =
    'codelab: "codelab serve" is deprecated and will be removed in a future '
    'release; use "codelab-agent serve" instead.';

const _notFound =
    'codelab: codelab-agent was not found next to codelab or in PATH; '
    'install it or run "codelab-agent serve" directly';

const _initialize =
    '{"jsonrpc":"2.0","id":1,"method":"initialize","params":'
    '{"protocolVersion":1,"clientCapabilities":{}}}\n';

void main() {
  final skip = Platform.isWindows
      ? 'обёртка codelab-agent и `kill -0` — POSIX shell; поиск `.exe`, '
            'кавычки PATH и ход запуска на Windows проверяют модульные тесты '
            'serve_alias_test.dart, настоящий Windows-прогон не выполняется'
      : null;

  late DualBinary env;
  late String bin;
  late String pidFile;

  /// Сценарий модели и каталог журналов, чтобы агент ничего не писал мимо
  /// временной папки.
  late List<String> agentFlags;

  setUp(() async {
    env = DualBinary.create('codelab_cli_e2e_serve_alias_');
    bin = '${env.tmp.path}/bin';
    pidFile = '${env.tmp.path}/agent.pid';
    Directory(bin).createSync();
    final wrapper = File('$bin/codelab-agent')
      ..writeAsStringSync(
        '#!/bin/sh\n'
        'echo \$\$ > \'$pidFile\'\n'
        'exec \'${dartExecutable()}\' \'${await E2eCliAgent.agentKernel()}\' '
        '"\$@"\n',
      );
    Process.runSync('/bin/chmod', ['+x', wrapper.path]);
    agentFlags = [
      '--llm-script',
      '$appDirectory/test/e2e/llm_scripts/normal.json',
      '--sessions-dir',
      '${env.tmp.path}/sessions',
    ];
  });
  tearDown(() => env.dispose());

  Map<String, String> environment({String? path}) => {
    ...env.environment,
    'PATH': path ?? bin,
  };

  Future<CliResult> codelab(List<String> args, {String? stdin, String? path}) =>
      CliProcess.run(
        args,
        environment: environment(path: path),
        workingDirectory: env.project,
        stdin: stdin,
        entry: CliEntry.production,
      );

  test(
    'cli/serve-alias-stdio: initialize through the alias, warning first in '
    'stderr, EOF is 0',
    () async {
      final result = await codelab([
        'serve',
        '--stdio',
        ...agentFlags,
      ], stdin: _initialize);

      expect(result.stderr.split('\n').first, _warning, reason: '$result');
      final frames = const LineSplitter().convert(result.stdout);
      expect(frames, hasLength(1), reason: '$result');
      final reply = jsonDecode(frames.single) as Map<String, Object?>;
      expect((reply['result']! as Map)['protocolVersion'], 1);
      expect(result.exitCode, 0, reason: '$result');
    },
    tags: scriptedOnly,
    skip: skip,
  );

  test(
    'cli/serve-alias-args: arguments go through unchanged, the agent '
    'rejects the flag with 64',
    () async {
      const args = ['serve', '--stdio', '--bogus'];
      final cli = await codelab(args);
      final agent = await env.runAgent(args);

      expect(cli.exitCode, 64, reason: '$cli');
      expect(cli.stdout, isEmpty, reason: '$cli');
      expect(cli.stderr.split('\n').first, _warning);
      // После предупреждения — ровно то, что печатает `codelab-agent serve`.
      expect(
        cli.stderr.substring(_warning.length + 1),
        agent.stderr,
        reason: '$cli\n$agent',
      );
      expect(agent.exitCode, 64);
    },
    tags: scriptedOnly,
    skip: skip,
  );

  test(
    'cli/serve-alias-no-flags: serve alone is the alias, no REPL, 64 with '
    'the usage of codelab-agent',
    () async {
      final cli = await codelab(['serve']);
      final agent = await env.runAgent(['serve']);

      expect(cli.exitCode, 64, reason: '$cli');
      expect(cli.stdout, isEmpty, reason: '$cli');
      expect(cli.stderr.split('\n').first, _warning);
      expect(
        cli.stderr.substring(_warning.length + 1),
        agent.stderr,
        reason: '$cli\n$agent',
      );
      // Алиас не открывает домашний каталог и профили (D8).
      expect(Directory(env.home).listSync(), isEmpty);
    },
    tags: scriptedOnly,
    skip: skip,
  );

  test(
    'cli/serve-alias-missing: no codelab-agent in absolute PATH entries is '
    '1, a trap in the current dir is not started',
    () async {
      final emptyBin = Directory('${env.tmp.path}/empty-bin')..createSync();
      final trap = File('${env.project}/codelab-agent')
        ..writeAsStringSync(
          '#!/bin/sh\ntouch \'${env.tmp.path}/trap-started\'\n',
        );
      Process.runSync('/bin/chmod', ['+x', trap.path]);

      final result = await codelab([
        'serve',
        '--stdio',
      ], path: '${emptyBin.path}:.:');

      expect(result.exitCode, 1, reason: '$result');
      expect(result.stdout, isEmpty, reason: '$result');
      expect(result.stderr, '$_warning\n$_notFound\n', reason: '$result');
      expect(File('${env.tmp.path}/trap-started').existsSync(), isFalse);
    },
    tags: scriptedOnly,
    skip: skip,
  );

  test(
    'cli/serve-alias-sigterm: SIGTERM to codelab reaches the agent, codelab '
    'exits 143 after the agent is gone',
    () async {
      final process = await CliProcess.start(
        ['serve', '--stdio', ...agentFlags],
        environment: environment(),
        workingDirectory: env.project,
        entry: CliEntry.production,
      );
      addTearDown(() => process.kill(ProcessSignal.sigkill));
      process.writeStdin(_initialize);
      // Агент ответил — он работает, обработчики сигналов установлены.
      await process.waitFor(
        'protocolVersion',
        timeout: const Duration(seconds: 10),
      );
      final agentPid = int.parse(File(pidFile).readAsStringSync().trim());

      process.kill(ProcessSignal.sigterm);
      final result = await process.result(timeout: const Duration(seconds: 30));

      expect(result.exitCode, 143, reason: '$result');
      // `kill -0` успешен, пока процесс агента жив.
      final alive = await Process.run('/bin/kill', ['-0', '$agentPid']);
      expect(alive.exitCode, isNot(0), reason: 'agent $agentPid is alive');
    },
    tags: scriptedOnly,
    skip: skip,
  );

  test(
    'cli/serve-alias-sighup: SIGHUP to codelab reaches the agent, codelab '
    'exits 129 after the agent is gone',
    () async {
      final process = await CliProcess.start(
        ['serve', '--stdio', ...agentFlags],
        environment: environment(),
        workingDirectory: env.project,
        entry: CliEntry.production,
      );
      addTearDown(() => process.kill(ProcessSignal.sigkill));
      process.writeStdin(_initialize);
      // Агент ответил — он работает, обработчики сигналов установлены.
      await process.waitFor(
        'protocolVersion',
        timeout: const Duration(seconds: 10),
      );
      final agentPid = int.parse(File(pidFile).readAsStringSync().trim());

      process.kill(ProcessSignal.sighup);
      final result = await process.result(timeout: const Duration(seconds: 30));

      expect(result.exitCode, 129, reason: '$result');
      // `kill -0` успешен, пока процесс агента жив.
      final alive = await Process.run('/bin/kill', ['-0', '$agentPid']);
      expect(alive.exitCode, isNot(0), reason: 'agent $agentPid is alive');
    },
    tags: scriptedOnly,
    skip: skip,
  );

  test(
    'cli/serve-alias-recursion: a codelab-agent wrapper around codelab serve '
    'is 1 without an endless chain',
    () async {
      final loopBin = Directory('${env.tmp.path}/loop-bin')..createSync();
      final codelabDill = await CliProcess.kernelOf(CliEntry.production);
      final wrapper = File('${loopBin.path}/codelab-agent')
        ..writeAsStringSync(
          '#!/bin/sh\n'
          'exec \'${dartExecutable()}\' \'$codelabDill\' serve "\$@"\n',
        );
      Process.runSync('/bin/chmod', ['+x', wrapper.path]);

      final result = await codelab(['serve', '--stdio'], path: loopBin.path);

      expect(result.exitCode, 1, reason: '$result');
      expect(result.stdout, isEmpty, reason: '$result');
      expect(
        _warning.allMatches(result.stderr).length,
        2,
        reason: 'outer and inner alias: $result',
      );
      expect(
        result.stderr,
        contains(
          'codelab: "codelab serve" cannot run itself; check that '
          'codelab-agent is not a wrapper around codelab serve, or run '
          '"codelab-agent serve" directly.',
        ),
      );
      expect(result.stderr, isNot(contains('--stdio')));
    },
    tags: scriptedOnly,
    skip: skip,
  );
}
