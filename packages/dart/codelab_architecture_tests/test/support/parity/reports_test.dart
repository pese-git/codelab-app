// Модульный тест чтения отчётов прогонов на временных файлах (задача 1.5
// change `switch-default-agent-to-dart`; design.md, D6): JSON-репортёр
// `package:test` и JUnit `codelab test-scenario --junit`.

import 'dart:io';

import 'package:test/test.dart';

import 'parity_test_kit.dart';
import 'reports.dart';

late Tree _tree;

void main() {
  setUp(() => _tree = Tree('parity_reports_'));
  tearDown(() => _tree.dispose());

  group('JSON-отчёт package:test', () {
    test('читает итоги тестов: pass, failed (failure и error), skipped', () {
      final file = _tree.put(
        'cli-dart.json',
        jsonReport(const [
          T('cli/ok'),
          T('cli/fails', result: 'failure'),
          T('cli/errors', result: 'error'),
          T('cli/skipped', skip: 'not on this platform'),
        ], success: false),
      );

      final source = readJsonReport(file);

      expect(source.name, 'cli-dart.json');
      expect(source.success, isFalse);
      expect(
        {for (final t in source.tests) t.name: t.outcome},
        {
          'cli/ok': TestOutcome.pass,
          'cli/fails': TestOutcome.failed,
          'cli/errors': TestOutcome.failed,
          'cli/skipped': TestOutcome.skipped,
        },
      );
      expect(
        source.tests.firstWhere((t) => t.name == 'cli/skipped').skipReason,
        'not on this platform',
      );
    });

    test('полное имя — группы и тест через пробел, как в отчёте', () {
      final file = _tree.put(
        'r.json',
        jsonReport(const [T('cli/headless-print-basic prints the answer')]),
      );

      expect(
        readJsonReport(file).tests.single.name,
        'cli/headless-print-basic prints the answer',
      );
    });

    test('запоминает suite.path теста', () {
      final file = _tree.put(
        'r.json',
        jsonReport(const [T('t', suite: '/work/test/x_test.dart')]),
      );

      expect(
        readJsonReport(file).tests.single.suitePath,
        '/work/test/x_test.dart',
      );
    });

    test('набор, который не загрузился, попадает в failedSuitePaths, '
        'а тест загрузки не считается тестом', () {
      final file = _tree.put(
        'r.json',
        jsonReport(
          const [T('ok')],
          success: false,
          failedLoads: const ['/work/test/broken_test.dart'],
        ),
      );

      final source = readJsonReport(file);

      expect(source.failedSuitePaths, ['/work/test/broken_test.dart']);
      expect(source.tests.map((t) => t.name), ['ok']);
      expect(source.success, isFalse);
    });

    test('неизвестные события и print пропускаются', () {
      final file = _tree.put('r.json', jsonReport(const [T('a'), T('b')]));

      expect(readJsonReport(file).tests.map((t) => t.name), ['a', 'b']);
    });

    test(
      'причина пропуска markTestSkipped приходит событием print со skip',
      () {
        final file = _tree.put('r.json', '''
{"type":"suite","suite":{"id":0,"platform":"vm","path":"test/a_test.dart"}}
{"type":"testStart","test":{"id":1,"name":"acp/x","suiteID":0,"groupIDs":[],"metadata":{"skip":false,"skipReason":null}}}
{"type":"print","testID":1,"messageType":"skip","message":"acp/x has roles [agent] without \\"client\\""}
{"type":"testDone","testID":1,"result":"success","skipped":true,"hidden":false}
{"type":"done","success":true}
''');

        final test = readJsonReport(file).tests.single;

        expect(test.outcome, TestOutcome.skipped);
        expect(test.skipReason, 'acp/x has roles [agent] without "client"');
      },
    );

    test('битая строка JSON — ошибка с именем файла', () {
      final file = _tree.put('broken.json', '{"type":"start"}\n{not json\n');

      expect(
        () => readJsonReport(file),
        throwsA(
          isA<ReportFormatException>().having(
            (e) => e.toString(),
            'text',
            contains('broken.json'),
          ),
        ),
      );
    });
  });

  group('JUnit test-scenario', () {
    test('читает pass, failure и skipped с причиной', () {
      final file = _tree.put(
        'scenario-embedded.xml',
        junitReport(const [
          J('acp/ok'),
          J('acp/bad', failure: 'frame 3 differs'),
          J(
            'acp/mcp-stdio-tool-call',
            skipped: 'setup.mcp cannot be passed to the agent process',
          ),
        ]),
      );

      final source = readJunitReport(file);

      expect(source.name, 'scenario-embedded.xml');
      expect(source.success, isFalse);
      expect(
        {for (final t in source.tests) t.name: t.outcome},
        {
          'acp/ok': TestOutcome.pass,
          'acp/bad': TestOutcome.failed,
          'acp/mcp-stdio-tool-call': TestOutcome.skipped,
        },
      );
      expect(
        source.tests.last.skipReason,
        'setup.mcp cannot be passed to the agent process',
      );
    });

    test('снимает экранирование &, <, >, кавычек', () {
      final file = _tree.put(
        'r.xml',
        junitReport(const [J('acp/x', skipped: "a<b & \"c\" 'd'>")]),
      );

      expect(readJunitReport(file).tests.single.skipReason, "a<b & \"c\" 'd'>");
    });

    test('пустой testsuite — ноль тестов, а не ошибка', () {
      final file = _tree.put('r.xml', junitReport(const []));

      final source = readJunitReport(file);

      expect(source.tests, isEmpty);
    });

    test('неожиданная разметка — ошибка с файлом, а не молчаливое not-run', () {
      final file = _tree.put('odd.xml', '<html><body>nope</body></html>');

      expect(
        () => readJunitReport(file),
        throwsA(
          isA<ReportFormatException>().having(
            (e) => e.toString(),
            'text',
            contains('odd.xml'),
          ),
        ),
      );
    });
  });

  test('отсутствующий файл отчёта — ошибка чтения, а не пустой источник', () {
    final missing = File('${_tree.path}/nope.json');

    expect(() => readJsonReport(missing), throwsA(isA<FileSystemException>()));
  });
}
