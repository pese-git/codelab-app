// Драйвер фикстур `codelab test-scenario` (tasks 8.3; spec cli-scenario-driver
// «Команда test-scenario», «Вывод и коды выхода test-scenario»; H-04;
// design.md change `add-codelab-cli`, D12).
@Timeout(Duration(minutes: 5))
library;

import 'dart:convert';
import 'dart:io';

import 'package:codelab_acp_testing/codelab_acp_testing.dart';
import 'package:codelab_cli/codelab_cli.dart';
import 'package:test/test.dart';

import '../support/cli_process.dart';
import '../support/fake_cli_io.dart';
import '../support/replay_agent.dart';

final _line = RegExp(r'^(PASS|FAIL|SKIP) (acp/\S+) \((\d+\.\d)s\)');
final _summary = RegExp(r'^(\d+) passed, (\d+) failed, (\d+) skipped$');

/// Итог прогона: код, строки фикстур по id и итоговая строка.
typedef _Run = ({
  int code,
  Map<String, String> status,
  String stdout,
  String stderr,
});

Future<_Run> _testScenario(List<String> args) async {
  final io = FakeCliIo();
  final code = await runCodelab(
    ['test-scenario', ...args],
    environment: const {'HOME': '/nonexistent'},
    io: io,
  );
  return (
    code: code,
    status: {
      for (final line in const LineSplitter().convert(io.stdoutText))
        if (_line.firstMatch(line) case final match?)
          match.group(2)!: match.group(1)!,
    },
    stdout: io.stdoutText,
    stderr: io.stderrText,
  );
}

AcpFixture _fixture(String id) =>
    loadFixtureCorpus().firstWhere((f) => f.id == id);

void main() {
  late Directory dir;

  setUp(() async => dir = await Directory.systemTemp.createTemp('scenario_'));
  tearDown(() => dir.delete(recursive: true));

  test('the corpus against the replay agent passes every agent fixture and '
      'skips the rest', () async {
    final run = await _testScenario([
      corpusDirectory,
      '--agent',
      await replayAgentProfile(),
    ]);

    expect(run.code, 0, reason: run.stdout + run.stderr);
    for (final fixture in loadFixtureCorpus()) {
      final playable =
          fixture.roles.contains(FixtureRole.agent) &&
          fixture.setup.transport == null;
      expect(
        run.status[fixture.id],
        playable ? 'PASS' : 'SKIP',
        reason: '${fixture.id}\n${run.stdout}',
      );
    }
    final ids = run.status.keys.toList();
    expect(ids, [...ids]..sort(), reason: 'lines go in the order of ids');
    final summary = _summary.firstMatch(
      const LineSplitter().convert(run.stdout).last,
    );
    expect(summary, isNotNull, reason: run.stdout);
    expect(summary!.group(2), '0');
  });

  test('a spoiled expected frame is FAIL with a diff and exit 1', () async {
    final original = _fixture('acp/initialize-capabilities');
    final json =
        jsonDecode(File(original.sourcePath!).readAsStringSync())
            as Map<String, Object?>;
    final frame = (json['frames']! as List<Object?>)
        .cast<Map<String, Object?>>()
        .firstWhere((f) => f['dir'] == 'a2c' && f['frame'] != null);
    (frame['frame']! as Map<String, Object?>)['spoiled'] = true;
    final copy = File('${dir.path}/initialize-capabilities.json')
      ..writeAsStringSync(jsonEncode(json));

    final run = await _testScenario([
      copy.path,
      '--agent',
      await replayAgentProfile(fixturePath: original.sourcePath),
    ]);

    expect(run.code, 1, reason: run.stdout);
    expect(run.status['acp/initialize-capabilities'], 'FAIL');
    expect(run.stdout, contains('spoiled'));
    expect(run.stdout, contains('expected'));
    expect(run.stdout, contains('1 failed'));
  });

  test('--filter plays only the matching ids', () async {
    final run = await _testScenario([
      corpusDirectory,
      '--agent',
      await replayAgentProfile(),
      '--filter',
      'acp/session-*',
    ]);

    expect(run.code, 0, reason: run.stdout);
    expect(run.status, isNotEmpty);
    expect(run.status.keys, everyElement(startsWith('acp/session-')));
  });

  test('a fixture without the agent role is SKIP with the reason', () async {
    final run = await _testScenario([
      _fixture('acp/errors-unknown-session-update-tolerated').sourcePath!,
      '--agent',
      await replayAgentProfile(),
    ]);

    // Ни одной сыгранной фикстуры — код 1 (U4).
    expect(run.code, 1);
    expect(run.stderr, contains('no fixtures were played'));
    expect(run.status.values, ['SKIP']);
    expect(run.stdout, contains('without "agent"'));
  });

  test('a third-party agent skips a fixture with an llm block', () async {
    final agent = await scriptedAgent(dir);

    final run = await _testScenario([
      _fixture('acp/prompt-text-end-turn').sourcePath!,
      '--agent',
      agent,
    ]);

    expect(run.code, 1, reason: run.stdout);
    expect(run.stderr, contains('no fixtures were played'));
    expect(run.status.values, ['SKIP']);
    expect(run.stdout, contains('third-party agent'));
  });

  test('a filter that matches nothing plays nothing: exit 1 with the reason '
      'in stderr (U4)', () async {
    final run = await _testScenario([
      corpusDirectory,
      '--agent',
      await replayAgentProfile(),
      '--filter',
      'acp/no-such-fixture-*',
    ]);

    expect(run.code, 1, reason: run.stdout);
    expect(run.stderr, contains('no fixtures were played'));
    expect(run.stdout, contains('0 passed, 0 failed, 0 skipped'));
  });

  test('without --agent and without a "default" profile the embedded agent '
      'plays the fixtures, like the rest of the CLI (U1)', () async {
    final run = await _testScenario([
      _fixture('acp/prompt-text-end-turn').sourcePath!,
    ]);

    expect(run.code, 0, reason: run.stdout + run.stderr);
    expect(run.status.values, ['PASS']);
  });

  test('a broken fixture file is 64 with the path and the reason', () async {
    final broken = File('${dir.path}/broken.json')
      ..writeAsStringSync('{"id": 1}');

    final run = await _testScenario([
      broken.path,
      '--agent',
      await replayAgentProfile(),
    ]);

    expect(run.code, 64);
    expect(run.stderr, contains('broken.json'));
    expect(run.stderr, contains('FixtureFormatException'));
  });

  test('a missing path is 64', () async {
    final run = await _testScenario([
      '${dir.path}/missing',
      '--agent',
      await replayAgentProfile(),
    ]);

    expect(run.code, 64);
    expect(run.stderr, contains('missing'));
  });

  test('no path is 64', () async {
    final run = await _testScenario(['--agent', await replayAgentProfile()]);

    expect(run.code, 64);
  });

  group('--agent embedded (spec «Корпус против встроенного агента»; D8)', () {
    /// Временные папки встроенного драйвера: свой префикс, поэтому чужие
    /// тесты в системном каталоге не мешают сравнению.
    Set<String> leftovers() => {
      for (final entity in Directory.systemTemp.listSync())
        if (entity.uri.pathSegments
            .lastWhere((segment) => segment.isNotEmpty)
            .startsWith('codelab_scenario_embedded_'))
          entity.path,
    };

    test('the corpus plays without FAIL, skips carry reasons and the '
        'temporary folders are removed', () async {
      final before = leftovers();

      final run = await _testScenario([corpusDirectory, '--agent', 'embedded']);

      expect(run.code, 0, reason: run.stdout + run.stderr);
      expect(run.stdout, isNot(contains('FAIL ')), reason: run.stdout);
      expect(
        run.status.values.where((status) => status == 'PASS'),
        hasLength(greaterThan(10)),
        reason: run.stdout,
      );
      // Каждая строка SKIP — с причиной на следующей строке.
      final lines = const LineSplitter().convert(run.stdout);
      for (var i = 0; i < lines.length; i++) {
        if (lines[i].startsWith('SKIP ')) {
          expect(
            lines[i + 1],
            startsWith('    '),
            reason: 'no reason under ${lines[i]}',
          );
        }
      }
      expect(leftovers(), before, reason: 'temporary folders are removed');
    });

    test('a fixture with fake MCP servers is SKIP with the reason', () async {
      final run = await _testScenario([
        _fixture('acp/mcp-stdio-tool-call').sourcePath!,
        '--agent',
        'embedded',
      ]);

      expect(run.code, 1, reason: run.stdout);
      expect(run.stderr, contains('no fixtures were played'));
      expect(run.status.values, ['SKIP']);
      expect(
        run.stdout,
        contains('setup.mcp cannot be passed to the agent process'),
      );
    });
  });

  test('an agent that does not start is FAIL and exit 1', () async {
    final run = await _testScenario([
      _fixture('acp/initialize-capabilities').sourcePath!,
      '--agent',
      'stdio:/nonexistent/agent {fixture}',
    ]);

    expect(run.code, 1, reason: run.stdout);
    expect(run.status.values, ['FAIL']);
  });
}
