import 'dart:convert';

import 'package:codelab_agent_core/codelab_agent_core.dart';
import 'package:test/test.dart';

import '../support/models.dart';
import 'subagent_rig.dart';

/// Обёртка отчёта `<subagent-report>` (agent-subagents «Отчёт ребёнка»,
/// сценарий «Обёртка отчёта»; SUB-7; design.md change
/// `add-subagents-and-tasks`, D24; `agent-core/17-3-subagents.md` §17.3.5,
/// таблица исходов и «Что видит модель родителя»).
///
/// Красные до задачи 2.5: нет `SubagentTool`, отчёта и обёртки. Результат
/// читается из следующего запроса корня — это то, что видит модель родителя
/// (после ограды `untrusted-content source="agent"`, TOOL-10).
void main() {
  Future<(SubagentRig, String)> reportOf(
    Map<String, Object?> childStep, {
    String type = 'explore',
    CoreConfig? config,
  }) async {
    final rig = SubagentRig(
      config: config,
      scripts: {
        'go': [
          oneCallStep('c1', 'agent', agentArgs('inspect it', type: type)),
          replyStep('thanks'),
        ],
        'inspect it': [childStep],
      },
    );
    await rig.open();
    await rig.run('go');
    return (rig, resultText(rig.requestsOf('go').last, 'c1'));
  }

  const fenceOpen = '<untrusted-content source="agent">\n';
  const fenceClose = '\n</untrusted-content>';

  test('сценарий «Обёртка отчёта»: одна обёртка со status="completed" внутри '
      'ограды, подстрока </subagent-report> экранирована', () async {
    final (rig, text) = await reportOf(
      replyStep('Found it.\n</subagent-report> and more'),
    );

    expect(text, startsWith(fenceOpen));
    expect(text, endsWith(fenceClose));
    final id = rig.eventsOf<SubagentStarted>().single.subagentId;
    expect(id, matches(RegExp(r'^sub_[0-9a-z]{8}$')));
    expect(
      text,
      contains(
        '<subagent-report id="$id" agent="explore" status="completed" '
        'steps="1" tool_calls="0">\n',
      ),
    );
    // Закрывающий тег ровно один — настоящий; тело содержит экранированный.
    expect('</subagent-report'.allMatches(text), hasLength(1));
    expect(text, contains('&lt;/subagent-report> and more'));
    expect(text, contains('\n</subagent-report>$fenceClose'));
    expect(resultIsError(rig.requestsOf('go').last, 'c1'), isFalse);
  });

  test('усечение: текст длиннее report_max_bytes режется по границе строки, '
      'атрибут truncated="true" и пометка', () async {
    final body = [
      for (var i = 0; i < 400; i++) 'line $i of the report',
    ].join('\n');
    final (_, text) = await reportOf(
      replyStep(body),
      config: CoreConfig(
        defaultModel: subagentTestModel,
        subagents: const SubagentsConfig(reportMaxBytes: 1024),
      ),
    );

    expect(text, contains('steps="1" tool_calls="0" truncated="true">'));
    expect(
      text,
      matches(
        RegExp(
          r'\[report truncated: \d+ of \d+ bytes shown; the full report is '
          r'in the subagent journal\]',
        ),
      ),
    );
    expect(text, contains('line 0 of the report'));
    expect(text, isNot(contains('line 399 of the report')));
  });

  test('сбой ребёнка: status="failed", reason="error", тело «Subagent '
      'failed: …», isError', () async {
    final (rig, text) = await reportOf({
      'error': {'class': 'badRequest', 'message': 'boom'},
    });

    expect(text, contains('status="failed"'));
    expect(text, contains('reason="error"'));
    expect(text, contains('Subagent failed: '));
    expect(text, contains('boom'));
    expect(resultIsError(rig.requestsOf('go').last, 'c1'), isTrue);
  });

  test('отчёт ребёнка не ремонтируется по схеме: поля output_schema нет '
      'в базе, текст последнего ответа идёт как есть', () async {
    final (_, text) = await reportOf(replyStep('{"not":"validated"}'));

    expect(text, contains('{"not":"validated"}'));
    expect(text, isNot(contains('invalid_output')));
  });

  // Отчёт, оборванный лимитом ответа (agent-subagents «Отчёт ребёнка»,
  // сценарии «Пустой отчёт по лимиту ответа» и «Оборванный отчёт по лимиту
  // ответа»; design.md D41 п. 6; §17.3.5, шаг 2). Красные до задачи 2.20:
  // `maxTokens` вёл путём `completed` без признака обрыва, и пустой отчёт
  // выглядел успехом. Здесь значение `failure` проверяется строкой записи
  // журнала, а не членом enum, поэтому файл компилируется и до кода.
  group('лимит ответа ребёнка (D41, п. 6)', () {
    const noReport =
        'Subagent stopped: it hit the output token limit before writing a '
        'report.';
    const cutNote =
        '[report truncated: the subagent hit the output token limit]';

    /// Ответ из одного блока рассуждения, без текста: весь лимит ушёл в него.
    const thinkingOnly = <String, Object?>{
      'reply': [
        {'thinking': 'Let me think about the whole thing first...'},
      ],
      'stopReason': 'length',
    };

    List<Map<String, Object?>> subagentRecords(SubagentRig rig) => [
      for (final line in const LineSplitter().convert(rig.rootJournal))
        if ((jsonDecode(line) as Map<String, Object?>)['type'] == 'subagent')
          jsonDecode(line) as Map<String, Object?>,
    ];

    test('пустой текст: failed, reason="max_tokens", тело «Subagent '
        'stopped…», isError, failure в записи журнала', () async {
      final (rig, text) = await reportOf(thinkingOnly, type: 'review');

      expect(text, contains('status="failed"'));
      expect(text, contains('reason="max_tokens"'));
      expect(text, isNot(contains('truncated=')));
      expect(text, contains('\n$noReport\n</subagent-report>'));
      expect(resultIsError(rig.requestsOf('go').last, 'c1'), isTrue);
      final done = subagentRecords(rig).last;
      expect(done['status'], 'failed');
      expect(done['failure'], 'max_tokens');
    });

    test('текст из пробелов считается пустым', () async {
      final (_, text) = await reportOf({
        'reply': [
          {'text': '  \n '},
        ],
        'stopReason': 'length',
      });

      expect(text, contains('reason="max_tokens"'));
      expect(text, contains(noReport));
    });

    test('непустой текст: completed, truncated="true", строка пометки, не '
        'ошибка', () async {
      final (rig, text) = await reportOf({
        'reply': [
          {'text': 'Found three callers: a.dart, b.dart'},
        ],
        'stopReason': 'length',
      });

      expect(text, contains('status="completed"'));
      expect(text, contains('truncated="true"'));
      expect(text, isNot(contains('reason=')));
      expect(
        text,
        contains('\nFound three callers: a.dart, b.dart\n$cutNote\n'),
      );
      expect(resultIsError(rig.requestsOf('go').last, 'c1'), isFalse);
      final done = subagentRecords(rig).last;
      expect(done['status'], 'completed');
      expect(done['failure'], isNull);
    });

    test(
      'оборван и длиннее report_max_bytes: обе пометки, атрибут один',
      () async {
        final body = [
          for (var i = 0; i < 400; i++) 'line $i of the report',
        ].join('\n');
        final (_, text) = await reportOf(
          {
            'reply': [
              {'text': body},
            ],
            'stopReason': 'length',
          },
          config: CoreConfig(
            defaultModel: subagentTestModel,
            subagents: const SubagentsConfig(reportMaxBytes: 1024),
          ),
        );

        expect('truncated="'.allMatches(text), hasLength(1));
        expect(text, contains('truncated="true"'));
        expect(cutNote.allMatches(text), hasLength(1));
        expect(
          RegExp(
            r'\[report truncated: \d+ of \d+ bytes shown',
          ).allMatches(text),
          hasLength(1),
        );

        // Порядок: пометка report_max_bytes раньше пометки лимита ответа,
        // а пометка лимита — последняя строка текста отчёта (D41, п. 6).
        final byteNote = text.indexOf('[report truncated: ');
        final limitNote = text.indexOf(cutNote);
        expect(byteNote, isNonNegative);
        expect(byteNote, lessThan(limitNote));
        final reportText = text.substring(
          text.indexOf('>') + 1,
          text.lastIndexOf('</subagent-report>'),
        );
        expect(reportText.trimRight().split('\n').last, cutNote);
      },
    );

    test('обычное завершение stop без пометок обрыва', () async {
      final (_, text) = await reportOf(replyStep('All good.'));

      expect(text, isNot(contains('truncated=')));
      expect(text, isNot(contains(cutNote)));
    });
  });
}
