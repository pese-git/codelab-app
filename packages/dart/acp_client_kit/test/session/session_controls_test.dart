// Тесты опций конфигурации, команд агента и одобрений сессии (tasks 6.1;
// spec acp-client-kit «Публикация представлений сессии», «Одобрения
// привязаны к вызову»; design D9).

import 'package:acp_client_kit/acp_client_kit.dart';
import 'package:acp_protocol/acp_protocol.dart';
import 'package:test/test.dart';

import '../support/kit_agent.dart';

List<Map<String, Object?>> _model(String current) => [
  {
    'type': 'select',
    'id': 'model',
    'name': 'Model',
    'description': 'Which model answers',
    'currentValue': current,
    'options': [
      {'value': 'gpt-5', 'name': 'GPT-5'},
      {'value': 'gpt-4', 'name': 'GPT-4', 'description': 'Older'},
    ],
  },
];

void main() {
  late KitAgent agent;

  setUp(() async {
    agent = KitAgent();
    await agent.start();
  });
  tearDown(() => agent.dispose());

  group('config options', () {
    test('the session view shows the options the agent declared', () async {
      final session = await agent.newSession(
        's-1',
        configOptions: _model('gpt-5'),
      );

      expect(session.current.configOptions, const [
        ConfigOptionView(
          id: 'model',
          name: 'Model',
          description: 'Which model answers',
          currentValue: 'gpt-5',
          values: [
            ConfigOptionValueView(value: 'gpt-5', name: 'GPT-5'),
            ConfigOptionValueView(
              value: 'gpt-4',
              name: 'GPT-4',
              description: 'Older',
            ),
          ],
        ),
      ]);
      expect(session.current.configOptionInFlight, isNull);
    });

    test('setConfigOption() is in flight until the answer; a second call '
        'meanwhile sends nothing', () async {
      final session = await agent.newSession(
        's-1',
        configOptions: _model('gpt-5'),
      );

      final request = agent.next(sessionSetConfigOptionMethod);
      final setting = session.setConfigOption('model', 'gpt-4');
      final frame = await request;
      expect(session.current.configOptionInFlight, 'model');
      final sentInFlight = agent.transport.sentMessages.length;

      await session.setConfigOption('model', 'gpt-5');
      expect(agent.transport.sentMessages, hasLength(sentInFlight));

      agent.respond(frame, {'configOptions': _model('gpt-4')});
      await setting;

      expect(session.current.configOptionInFlight, isNull);
      expect(session.current.configOptions.single.currentValue, 'gpt-4');
      expect(
        agent.diagnostics.last,
        const WorkspaceDiagnostic(
          severity: DiagnosticSeverity.info,
          source: 'session',
          message: 'Set config option model to gpt-4.',
        ),
      );
    });

    test('a failed setConfigOption() clears the flag, reports and '
        'rethrows', () async {
      final session = await agent.newSession(
        's-1',
        configOptions: _model('gpt-5'),
      );

      final request = agent.next(sessionSetConfigOptionMethod);
      final setting = session.setConfigOption('model', 'gpt-4');
      agent.fail(await request, 'unknown value');

      await expectLater(setting, throwsA(anything));
      expect(session.current.configOptionInFlight, isNull);
      expect(agent.diagnostics.last.severity, DiagnosticSeverity.error);
      expect(
        agent.diagnostics.last.message,
        startsWith('Failed to set config option model: '),
      );
    });
  });

  test('agent commands come from the last available_commands_update', () async {
    final session = await agent.newSession('s-1');

    agent.update('s-1', {
      'sessionUpdate': 'available_commands_update',
      'availableCommands': [
        {'name': 'compact', 'description': 'Compact the context'},
        {
          'name': 'plan',
          'description': 'Plan first',
          'input': {'hint': 'what to plan'},
        },
      ],
    });

    expect(session.current.agentCommands, const [
      AgentCommandView(name: 'compact', description: 'Compact the context'),
      AgentCommandView(
        name: 'plan',
        description: 'Plan first',
        hint: 'what to plan',
      ),
    ]);
  });

  group('approvals', () {
    test('pending approvals list the request of each session; respond() '
        'answers only its own session', () async {
      final a = await agent.newSession('s-a');
      final turnA = await agent.prompt(a, 'task a');
      agent.requestPermission(id: 1, sessionId: 's-a', toolCallId: 'call-a');
      final b = await agent.newSession('s-b');
      final turnB = await agent.prompt(b, 'task b');
      agent.requestPermission(id: 2, sessionId: 's-b', toolCallId: 'call-b');

      final pendingB = b.current.pendingApprovals.single;
      expect(pendingB.options.map((o) => o.optionId.value), [
        'allow-once',
        'reject-once',
      ]);
      expect(pendingB.command, 'dart test');

      final response = agent.nextResponse();
      await b.respond(
        pendingB.approvalId,
        const PermissionOptionId('reject-once'),
      );
      expect((await response).id, const JsonRpcId.integer(2));

      expect(b.current.pendingApprovals, isEmpty);
      expect(a.current.pendingApprovals, hasLength(1));
      expect(agent.diagnostics.last.source, 'approval');
      expect(
        agent.diagnostics.last.message,
        'Resolved approval permission-2 (selected).',
      );

      await a.respond(
        a.current.pendingApprovals.single.approvalId,
        const PermissionOptionId('allow-once'),
      );
      agent
        ..respond(turnA.request, const {'stopReason': 'end_turn'})
        ..respond(turnB.request, const {'stopReason': 'end_turn'});
      await Future.wait([turnA.done, turnB.done]);
    });

    test('respond() of an approval of another session is rejected', () async {
      final a = await agent.newSession('s-a');
      final turnA = await agent.prompt(a, 'task a');
      agent.requestPermission(id: 1, sessionId: 's-a', toolCallId: 'call-a');
      final b = await agent.newSession('s-b');

      await expectLater(
        b.respond(
          a.current.pendingApprovals.single.approvalId,
          const PermissionOptionId('allow-once'),
        ),
        throwsA(anything),
      );
      expect(a.current.pendingApprovals, hasLength(1));

      await a.respond(
        a.current.pendingApprovals.single.approvalId,
        const PermissionOptionId('allow-once'),
      );
      agent.respond(turnA.request, const {'stopReason': 'end_turn'});
      await turnA.done;
    });
  });
}
