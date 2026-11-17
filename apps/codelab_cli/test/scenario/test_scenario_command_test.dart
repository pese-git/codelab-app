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

Future<_Run> _testScenario(
  List<String> args, {
  Map<String, String> environment = const {'HOME': '/nonexistent'},
}) async {
  final io = FakeCliIo();
  final code = await runCodelab(
    ['test-scenario', ...args],
    environment: environment,
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

  group('the profile choice (spec «Без --agent и без профиля default»; '
      'D21)', () {
    const oldDefault =
        '{"version": 1, "profiles": [{"type": "stdio", "id": "default", '
        '"label": "Default", "command": "/opt/secret-agent", "args": [], '
        '"env": {}, "runInProjectDirectory": false}]}';
    const warning =
        'profile "default" in profiles.json is ignored: default is the '
        'built-in agent; remove it with codelab profiles remove default';

    Map<String, String> homeWith(String profiles) {
      final home = Directory('${dir.path}/home')..createSync();
      File('${home.path}/profiles.json').writeAsStringSync(profiles);
      return {'CODELAB_HOME': home.path, 'HOME': '/nonexistent'};
    }

    test('an old "default" record does not replace the embedded agent '
        'without --agent: no warning, the file is not read', () async {
      final run = await _testScenario([
        _fixture('acp/prompt-text-end-turn').sourcePath!,
      ], environment: homeWith(oldDefault));

      expect(run.code, 0, reason: run.stdout + run.stderr);
      expect(run.status.values, ['PASS']);
      expect(run.stderr, isEmpty);
    });

    test('--agent default is the embedded agent with one warning about '
        'the old record, without its command', () async {
      final run = await _testScenario([
        _fixture('acp/prompt-text-end-turn').sourcePath!,
        '--agent',
        'default',
      ], environment: homeWith(oldDefault));

      expect(run.code, 0, reason: run.stdout + run.stderr);
      expect(run.status.values, ['PASS']);
      expect(run.stderr.trimRight(), warning);
      expect(run.stderr, isNot(contains('/opt/secret-agent')));
    });

    test('a broken profiles.json without --agent is not 64: the embedded '
        'agent plays', () async {
      final run = await _testScenario([
        _fixture('acp/prompt-text-end-turn').sourcePath!,
      ], environment: homeWith('{not json'));

      expect(run.code, 0, reason: run.stdout + run.stderr);
      expect(run.status.values, ['PASS']);
    });

    test('a broken profiles.json with --agent <id> is 64 with the '
        'reason', () async {
      final run = await _testScenario([
        _fixture('acp/prompt-text-end-turn').sourcePath!,
        '--agent',
        'dev',
      ], environment: homeWith('[]'));

      expect(run.code, 64);
      expect(run.stderr, contains('Cannot read agent profiles'));
      expect(run.stdout, isEmpty);
    });
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

  // Task 1.9 change `switch-default-agent-to-dart`; spec cli-scenario-driver
  // «JUnit-отчёт test-scenario»; design.md, D8, D16.
  group('--junit (spec «JUnit-отчёт test-scenario»; D8)', () {
    final testcase = RegExp(
      r'<testcase classname="acp" name="([^"]+)"[^>]*?(/>|>(.*?)</testcase>)',
      dotAll: true,
    );

    /// Содержимое `testcase` по id фикстуры (пустая строка у `PASS`).
    Map<String, String> cases(String xml) => {
      for (final match in testcase.allMatches(xml))
        match.group(1)!: match.group(3) ?? '',
    };

    String report() => '${dir.path}/r.xml';

    test('a run against the replay agent writes one testcase per stdout '
        'row and the suite equals the summary line', () async {
      final run = await _testScenario([
        corpusDirectory,
        '--agent',
        await replayAgentProfile(),
        '--junit',
        report(),
      ]);

      expect(run.code, 0, reason: run.stdout + run.stderr);
      final xml = File(report()).readAsStringSync();
      expect(cases(xml).keys.toList(), run.status.keys.toList());
      final summary = _summary.firstMatch(
        const LineSplitter().convert(run.stdout).last,
      )!;
      final passed = int.parse(summary.group(1)!);
      final failed = int.parse(summary.group(2)!);
      final skipped = int.parse(summary.group(3)!);
      expect(xml, contains('tests="${passed + failed + skipped}"'));
      expect(xml, contains('failures="$failed"'));
      expect(xml, contains('skipped="$skipped"'));
    });

    test('a run against the embedded agent: testcase per row, '
        'acp/mcp-stdio-tool-call is skipped with the reason', () async {
      final run = await _testScenario([
        corpusDirectory,
        '--agent',
        'embedded',
        '--junit',
        report(),
      ]);

      expect(run.code, 0, reason: run.stdout + run.stderr);
      final xml = File(report()).readAsStringSync();
      final byId = cases(xml);
      expect(byId.keys.toList(), run.status.keys.toList());
      expect(
        byId['acp/mcp-stdio-tool-call'],
        contains(
          '<skipped message="setup.mcp cannot be passed to the agent '
          'process"',
        ),
      );
    });

    test('FAIL: the testcase has a failure with the diff, exit 1, the file '
        'is written', () async {
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
        '--junit',
        report(),
      ]);

      expect(run.code, 1, reason: run.stdout);
      final xml = File(report()).readAsStringSync();
      final body = cases(xml)['acp/initialize-capabilities'];
      expect(body, contains('<failure message="'));
      expect(body, contains('spoiled'));
      expect(xml, contains('failures="1"'));
    });

    test('a filter that matches nothing: exit 1 and an empty testsuite '
        'is written', () async {
      final run = await _testScenario([
        corpusDirectory,
        '--agent',
        await replayAgentProfile(),
        '--filter',
        'acp/no-such-*',
        '--junit',
        report(),
      ]);

      expect(run.code, 1, reason: run.stdout);
      expect(run.stderr, contains('no fixtures were played'));
      final xml = File(report()).readAsStringSync();
      expect(xml, contains('tests="0"'));
      expect(cases(xml), isEmpty);
    });

    // Агент-маркер: `touch <файл>` создаёт файл при запуске. Признак
    // «агент запускался» однозначен и не зависит от того, что напечатал stdout.
    String markerAgent(String marker) => 'stdio:touch $marker';

    test(
      'control: the marker agent leaves its marker when it starts',
      () async {
        final marker = '${dir.path}/started-control';
        final run = await _testScenario([
          _fixture('acp/initialize-capabilities').sourcePath!,
          '--agent',
          markerAgent(marker),
          '--junit',
          report(),
        ]);

        expect(run.code, 1, reason: run.stdout);
        expect(File(marker).existsSync(), isTrue, reason: run.stdout);
      },
    );

    test('an unwritable path is 64 before any agent starts', () async {
      const path = '/nonexistent-dir/r.xml';
      final marker = '${dir.path}/started';
      final run = await _testScenario([
        _fixture('acp/initialize-capabilities').sourcePath!,
        '--agent',
        markerAgent(marker),
        '--junit',
        path,
      ]);

      expect(run.code, 64);
      expect(run.stderr, contains('codelab: cannot write --junit $path:'));
      // Агент не запускался: маркер не создан (контроль — тест выше).
      expect(File(marker).existsSync(), isFalse);
      expect(run.status, isEmpty, reason: run.stdout);
      expect(File(path).existsSync(), isFalse);
    });

    test('the probe never touches an existing report when the fixtures '
        'are broken (64)', () async {
      final existing = File(report())..writeAsStringSync('previous report');

      final run = await _testScenario([
        '${dir.path}/no-such-fixture.json',
        '--agent',
        'embedded',
        '--junit',
        existing.path,
      ]);

      expect(run.code, 64, reason: run.stderr);
      expect(existing.readAsStringSync(), 'previous report');
    });

    test('a symlink as the report path is 64 and its target is '
        'untouched', () async {
      final target = File('${dir.path}/target.xml')
        ..writeAsStringSync('target text');
      final link = Link('${dir.path}/link.xml')..createSync(target.path);
      final marker = '${dir.path}/started-link';

      final run = await _testScenario([
        _fixture('acp/initialize-capabilities').sourcePath!,
        '--agent',
        markerAgent(marker),
        '--junit',
        link.path,
      ]);

      expect(run.code, 64, reason: run.stdout);
      expect(run.stderr, contains('codelab: cannot write --junit'));
      expect(target.readAsStringSync(), 'target text');
      expect(File(marker).existsSync(), isFalse);
    });

    test('a directory as the report path is 64', () async {
      final run = await _testScenario([
        _fixture('acp/initialize-capabilities').sourcePath!,
        '--agent',
        'embedded',
        '--junit',
        dir.path,
      ]);

      expect(run.code, 64, reason: run.stdout);
      expect(run.stderr, contains('codelab: cannot write --junit'));
    });

    test('the final write replaces an existing report and leaves no '
        'temporary files', () async {
      File(report()).writeAsStringSync('previous report');

      final run = await _testScenario([
        corpusDirectory,
        '--agent',
        await replayAgentProfile(),
        '--filter',
        'acp/initialize-capabilities',
        '--junit',
        report(),
      ]);

      expect(run.code, 0, reason: run.stdout + run.stderr);
      expect(File(report()).readAsStringSync(), contains('<testsuite '));
      expect(dir.listSync().map((e) => e.path.split('/').last).toList(), [
        'r.xml',
      ]);
    });

    test(
      'a read-only folder with a writable existing report is 64 before '
      'any agent starts (the final write needs the folder)',
      () async {
        final locked = Directory('${dir.path}/locked')..createSync();
        final existing = File('${locked.path}/r.xml')
          ..writeAsStringSync('previous report');
        final marker = '${dir.path}/started-locked';
        await Process.run('chmod', ['555', locked.path]);
        addTearDown(() => Process.run('chmod', ['755', locked.path]));

        final run = await _testScenario([
          _fixture('acp/initialize-capabilities').sourcePath!,
          '--agent',
          markerAgent(marker),
          '--junit',
          existing.path,
        ]);

        expect(run.code, 64, reason: run.stdout + run.stderr);
        expect(run.stderr, contains('codelab: cannot write --junit'));
        expect(File(marker).existsSync(), isFalse);
        expect(existing.readAsStringSync(), 'previous report');
      },
      skip: Platform.environment['USER'] == 'root'
          ? 'root ignores folder permissions'
          : false,
    );

    test('agent arguments never reach the file (D16)', () async {
      const marker = 'sk-test-leak-0123456789';
      final fixture = _fixture('acp/initialize-capabilities');
      final run = await _testScenario([
        fixture.sourcePath!,
        '--agent',
        'stdio:/nonexistent/agent --api-key $marker {fixture}',
        '--junit',
        report(),
      ]);

      expect(run.code, 1, reason: run.stdout);
      final xml = File(report()).readAsStringSync();
      expect(
        cases(xml)['acp/initialize-capabilities'],
        contains('the agent did not run the fixture: '),
      );
      expect(xml, isNot(contains(marker)));
      expect(xml, isNot(contains('--api-key')));
      expect(xml, isNot(contains(fixture.sourcePath!)));
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

  // D8 и D9 change `redact-cli-stdio-profile-args`; spec cli-scenario-driver
  // «Несуществующая команда агента». Без D8 драйвер печатал бы
  // `ProcessException.toString()` с `Command: <аргументы>`, а D9 — вторая
  // линия защиты на случай, если такая ошибка придёт не из транспорта.
  test('an agent that does not start prints only the OS reason, never the '
      'arguments', () async {
    const marker = 'sk-test-leak-0123456789';
    final run = await _testScenario([
      _fixture('acp/initialize-capabilities').sourcePath!,
      '--agent',
      'stdio:/nonexistent/agent --api-key $marker $marker {fixture}',
    ]);

    expect(run.code, 1, reason: run.stdout);
    expect(run.status.values, ['FAIL']);
    expect(run.stdout, contains('the agent did not run the fixture: '));
    for (final out in [run.stdout, run.stderr]) {
      expect(out, isNot(contains(marker)));
      expect(out, isNot(contains('--api-key')));
      expect(out, isNot(contains('Command:')));
    }
  });
}
