import 'package:codelab_agent_core/codelab_agent_core.dart';
import 'package:test/test.dart';

import '../permissions/fake_gate.dart';
import 'subagent_rig.dart';

/// Хуки хоста `extraBeforeToolCall` видят вызовы потомков (agent-subagents
/// «Сборка ребёнка», сценарий «Хук хоста видит вызов потомка»; design.md
/// change `add-subagents-and-tasks`, D48 п. 1, D36 Т2; §10.7 шаг 6,
/// §17.3.3; задача 5.1).
///
/// Почему: ACP-адаптеру нужен `markInProgress` и для вызовов ребёнка и
/// внука; хук получает вызов с `id`, переписанным в цепочку D8
/// (`call_1/call_1`, `call_1/call_2/call_1`) — тот же id, что у запроса
/// разрешения. Хуки `extraAfterToolCall` к потомкам не подключаются.
///
/// Охраняют, что цикл потомка подключает хуки хоста (D36 Т2) и хук видит
/// вызовы ребёнка и внука; отдельный характеризующий тест фиксирует, что
/// `extraAfterToolCall` к потомкам не подключается.
void main() {
  /// Корень вызывает `agent` (`call_1`); ребёнок — [kidSteps], внук — `ls`.
  SubagentRig tree({
    PermissionGate? gate,
    List<Map<String, Object?>>? kidSteps,
  }) => SubagentRig(
    gate: gate,
    scripts: {
      'go': [
        oneCallStep('call_1', 'agent', agentArgs('kid job')),
        replyStep('done'),
      ],
      'kid job':
          kidSteps ??
          [
            oneCallStep('call_1', 'read', {'path': 'a.txt'}),
            oneCallStep('call_2', 'agent', agentArgs('grand job')),
            replyStep('kid done'),
          ],
      'grand job': [
        oneCallStep('call_1', 'ls', {'path': '.'}),
        replyStep('grand done'),
      ],
    },
  );

  test('сценарий «Хук хоста видит вызов потомка»: хук вызван для '
      'call_1/call_1 и call_1/call_2/call_1', () async {
    final rig = tree();
    final seen = <String>[];
    await rig.open(
      ports: SessionHostPorts(
        extraBeforeToolCall: [
          (call, args, ctx) async {
            seen.add(call.id);
            return null;
          },
        ],
      ),
    );

    await rig.run('go');

    expect(seen, [
      'call_1',
      'call_1/call_1',
      'call_1/call_2',
      'call_1/call_2/call_1',
    ], reason: 'вызовы корня и потомков любой глубины, id — цепочка D8');
  });

  test('хук идёт после политики: сначала запрос разрешения с тем же id, '
      'потом хук', () async {
    final order = <String>[];
    final gate = FakeGate((request) {
      order.add('gate ${request.toolCallId}');
      return PermissionDecision.allowOnce;
    });
    final rig = tree(
      gate: gate,
      kidSteps: [
        oneCallStep('w1', 'write', {'path': 'f.txt', 'content': 'x'}),
        replyStep('kid done'),
      ],
    );
    await rig.open(
      ports: SessionHostPorts(
        extraBeforeToolCall: [
          (call, args, ctx) async {
            order.add('hook ${call.id}');
            return null;
          },
        ],
      ),
    );

    await rig.run('go');

    final gateAt = order.indexOf('gate call_1/w1');
    final hookAt = order.indexOf('hook call_1/w1');
    expect(gateAt, isNonNegative, reason: 'запрос разрешения потомка');
    expect(hookAt, isNonNegative, reason: 'хук хоста видит вызов потомка');
    expect(gateAt, lessThan(hookAt));
  });

  test('вызов, отклонённый политикой потомка, хук не видит', () async {
    final seen = <String>[];
    final rig = tree(
      gate: FakeGate(
        (request) => request.toolCallId == 'call_1/w1'
            ? PermissionDecision.rejectOnce
            : PermissionDecision.allowOnce,
      ),
      kidSteps: [
        oneCallStep('w1', 'write', {'path': 'f.txt', 'content': 'x'}),
        oneCallStep('r1', 'read', {'path': 'a.txt'}),
        replyStep('kid done'),
      ],
    );
    await rig.open(
      ports: SessionHostPorts(
        extraBeforeToolCall: [
          (call, args, ctx) async {
            seen.add(call.id);
            return null;
          },
        ],
      ),
    );

    await rig.run('go');

    expect(seen, contains('call_1/r1'), reason: 'разрешённый вызов виден');
    expect(seen, isNot(contains('call_1/w1')), reason: 'отклонённый — нет');
  });

  test('Block хука хоста останавливает вызов потомка, как у корня', () async {
    final rig = tree();
    await rig.open(
      ports: SessionHostPorts(
        extraBeforeToolCall: [
          (call, args, ctx) async =>
              call.id == 'call_1/call_1' ? const Block('host says no') : null,
        ],
      ),
    );

    await rig.run('go');

    final finished = [
      for (final a in rig.eventsOf<SubagentActivity>())
        if (a.event case final ToolCallFinished f) f,
    ].where((f) => f.toolCallId == 'call_1').toList();
    expect(finished, isNotEmpty);
    expect(
      finished.map((f) => f.outcome),
      contains(ToolOutcome.rejected),
      reason: 'Block по умолчанию даёт rejected',
    );
  });

  test('характеризующий, зелёный сразу: extraAfterToolCall к потомкам не '
      'подключаются (D48 п. 1)', () async {
    final rig = tree();
    final seen = <String>[];
    await rig.open(
      ports: SessionHostPorts(
        extraAfterToolCall: [
          (call, result, isError) async {
            seen.add(call.id);
            return null;
          },
        ],
      ),
    );

    await rig.run('go');

    expect(seen, ['call_1'], reason: 'хук после вызова — только у корня');
  });
}
