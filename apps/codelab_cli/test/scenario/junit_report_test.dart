// Запись JUnit-отчёта `codelab test-scenario --junit` (task 1.9 change
// `switch-default-agent-to-dart`; spec cli-scenario-driver «JUnit-отчёт
// test-scenario»; design.md, D8).
//
// Почему красный: `lib/src/scenario/junit_report.dart` появится в задаче 1.10.
// Тест фиксирует форму API записи: чистая функция без IO и без пакета `xml`
// (D8: «функция в lib/src/scenario/ рядом с test_scenario_command.dart»).
library;

import 'package:codelab_cli/src/scenario/junit_report.dart';
import 'package:test/test.dart';

void main() {
  test('a passed, a failed and a skipped fixture follow the D8 schema', () {
    final xml = renderJunitReport([
      const JunitCase(id: 'acp/prompt-streaming-text', seconds: 0.4),
      const JunitCase(
        id: 'acp/x',
        seconds: 0.1,
        failure: 'frame 3 differs\nexpected:\n  {}\nactual:\n  {"a": 1}',
      ),
      const JunitCase(
        id: 'acp/y',
        seconds: 0,
        skipped: 'setup.mcp cannot be passed to the agent process',
      ),
    ], seconds: 1.5);

    expect(xml, startsWith('<?xml version="1.0" encoding="UTF-8"?>'));
    expect(
      xml,
      contains(
        '<testsuite name="codelab test-scenario" tests="3" failures="1" '
        'skipped="1" time="1.5">',
      ),
    );
    expect(
      xml,
      contains(
        '<testcase classname="acp" name="acp/prompt-streaming-text" '
        'time="0.4"',
      ),
    );
    // Причина в message — первая строка, дифф целиком — в тексте элемента.
    expect(xml, contains('<failure message="frame 3 differs">'));
    expect(xml, contains('expected:'));
    expect(
      xml,
      contains(
        '<skipped message="setup.mcp cannot be passed to the agent process"',
      ),
    );
    // Порядок testcase — порядок аргумента.
    expect(
      xml.indexOf('acp/prompt-streaming-text'),
      lessThan(xml.indexOf('name="acp/x"')),
    );
    expect(xml.indexOf('name="acp/x"'), lessThan(xml.indexOf('name="acp/y"')));
  });

  test('an empty run is a testsuite with tests="0"', () {
    final xml = renderJunitReport(const [], seconds: 0);

    expect(xml, contains('tests="0"'));
    expect(xml, contains('failures="0"'));
    expect(xml, contains('skipped="0"'));
    expect(xml, isNot(contains('<testcase')));
  });

  test('& < > " \' are escaped and XML 1.0-invalid characters become '
      'U+FFFD', () {
    final xml = renderJunitReport([
      const JunitCase(
        id: 'acp/a&b',
        seconds: 0,
        skipped: 'a <b> & "c" \'d\' \u0001 e',
      ),
      const JunitCase(
        id: 'acp/z',
        seconds: 0,
        failure: 'x < y & z\u0000\n\u0008',
      ),
    ], seconds: 0);

    expect(xml, contains('name="acp/a&amp;b"'));
    expect(xml, contains('a &lt;b&gt; &amp; &quot;c&quot; &apos;d&apos; '));
    expect(xml, contains('\u{FFFD} e'));
    expect(xml, contains('x &lt; y &amp; z\u{FFFD}'));
    // Допустимые управляющие (\n, \t, \r) остаются, прочие — заменены.
    for (final bad in ['\u0000', '\u0001', '\u0008', '\u000B', '\u000C']) {
      expect(xml, isNot(contains(bad)), reason: 'U+${bad.codeUnitAt(0)}');
    }
    // Сырые спецсимволы не остались в значениях атрибутов и тексте.
    expect(xml, isNot(contains('<b>')));
    expect(xml, isNot(contains('& ')));
  });
}
