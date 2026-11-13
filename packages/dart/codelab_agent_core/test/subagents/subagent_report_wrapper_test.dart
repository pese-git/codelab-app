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
        defaultModel: testModel,
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
}
