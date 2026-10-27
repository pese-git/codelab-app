// План сессии в представлении (tasks 5.1 change `add-codelab-cli`; spec
// acp-client-kit «Публикация представлений сессии»; design.md, D14).

import 'package:codelab_acp_protocol/codelab_acp_protocol.dart';
import 'package:codelab_client_core/codelab_client_core.dart';
import 'package:test/test.dart';

import '../support/kit_agent.dart';

Map<String, Object?> _plan(List<(String, String)> entries) => {
  'sessionUpdate': 'plan',
  'entries': [
    for (final (content, status) in entries)
      {'content': content, 'status': status, 'priority': 'medium'},
  ],
};

void main() {
  late KitAgent agent;

  setUp(() async {
    agent = KitAgent();
    await agent.start();
  });
  tearDown(() => agent.dispose());

  test('the plan is empty before the first plan update', () async {
    final session = await agent.newSession('s1');

    expect(session.current.plan, isEmpty);
  });

  test('a plan update is projected in the agent order', () async {
    final session = await agent.newSession('s1');
    await agent.prompt(session, 'go');

    agent.update('s1', {
      'sessionUpdate': 'plan',
      'entries': [
        {'content': 'Read', 'status': 'completed', 'priority': 'high'},
        {'content': 'Edit', 'status': 'in_progress', 'priority': 'medium'},
        {'content': 'Test', 'status': 'pending', 'priority': 'low'},
      ],
    });
    await Future<void>.delayed(Duration.zero);

    expect(session.current.plan, const [
      PlanEntryView(
        content: 'Read',
        status: PlanEntryStatus.completed,
        priority: PlanEntryPriority.high,
      ),
      PlanEntryView(
        content: 'Edit',
        status: PlanEntryStatus.inProgress,
        priority: PlanEntryPriority.medium,
      ),
      PlanEntryView(
        content: 'Test',
        status: PlanEntryStatus.pending,
        priority: PlanEntryPriority.low,
      ),
    ]);
  });

  test('each plan update replaces the plan as a whole', () async {
    final session = await agent.newSession('s1');
    await agent.prompt(session, 'go');

    agent.update(
      's1',
      _plan([('a', 'pending'), ('b', 'pending'), ('c', 'pending')]),
    );
    await Future<void>.delayed(Duration.zero);
    expect(session.current.plan, hasLength(3));

    agent.update('s1', _plan([('x', 'completed'), ('y', 'pending')]));
    await Future<void>.delayed(Duration.zero);
    expect(session.current.plan.map((e) => e.content), ['x', 'y']);
  });

  test('the plan of an earlier turn stays in the next turn without its '
      'own', () async {
    final session = await agent.newSession('s1');
    final first = await agent.prompt(session, 'one');
    agent.update('s1', _plan([('a', 'completed')]));
    agent.respond(first.request, {'stopReason': 'end_turn'});
    await first.done;

    await agent.prompt(session, 'two');
    agent.update('s1', {
      'sessionUpdate': 'agent_message_chunk',
      'content': {'type': 'text', 'text': 'ok'},
    });
    await Future<void>.delayed(Duration.zero);

    expect(session.current.plan.map((e) => e.content), ['a']);
  });
}
