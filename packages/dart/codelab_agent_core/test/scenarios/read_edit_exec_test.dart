import 'dart:convert';

import 'package:codelab_agent_core/codelab_agent_core.dart';
import 'package:codelab_agent_core/src/llm/stream_state.dart';
import 'package:codelab_agent_core/src/loop/agent.dart';
import 'package:codelab_agent_core/src/tools/pairing.dart';
import 'package:codelab_agent_core/testing.dart';
import 'package:test/test.dart';

import '../loop/loop_harness.dart' as loop;
import '../permissions/fake_gate.dart';
import '../support/models.dart';
import '../tools/fake_shell.dart';
import '../tools/fake_tools.dart';

/// Сценарий 2.10 (agent-runtime «Сквозной сценарий и детерминизм»): модель
/// читает файл, правит его и запускает команду через `buildAgentCore`.
const _steps = <Map<String, Object?>>[
  {
    'reply': [
      {
        'toolCall': {
          'id': 'c1',
          'name': 'read',
          'arguments': {'path': 'lib/greet.dart'},
        },
      },
    ],
  },
  {
    'expect': {
      'toolResult': {'toolCallId': 'c1', 'isError': false},
    },
    'reply': [
      {'text': 'Renaming the greeting.'},
      {
        'toolCall': {
          'id': 'c2',
          'name': 'edit',
          'arguments': {
            'path': 'lib/greet.dart',
            'oldText': 'Hello',
            'newText': 'Hi',
          },
        },
      },
    ],
  },
  {
    'expect': {
      'toolResult': {'toolCallId': 'c2', 'isError': false},
    },
    'reply': [
      {
        'toolCall': {
          'id': 'c3',
          'name': 'exec',
          'arguments': {'command': 'dart test'},
        },
      },
    ],
  },
  {
    'expect': {
      'toolResult': {'toolCallId': 'c3', 'isError': false},
    },
    'reply': [
      {'text': 'Done: greet.dart says Hi and the tests pass.'},
    ],
  },
];

final class _Run {
  _Run(this.trace, this.requests, this.file, this.commands);

  final List<String> trace;
  final List<PermissionRequest> requests;
  final String file;
  final List<String> commands;
}

/// Один прогон сценария на свежих фейковых портах.
Future<_Run> _run() async {
  final clock = FakeClock();
  final memory = MemoryExecutionEnv(cwd: '/proj', clock: clock);
  await memory.writeText(
    '/proj/lib/greet.dart',
    "String greet() => 'Hello';\n",
  );
  final shell = FakeShellEnv(memory, answering('All tests passed!'));
  final gate = FakeGate();
  final model = ScriptedStreamFunction.fromJson({
    'steps': _steps,
  }, clock: clock);
  final core = buildAgentCore(
    profile: HostProfile.of('agent-serve').narrowed(const {
      HostCapability.sessionPersistence: CapabilityOff('журнал теста в памяти'),
    }),
    services: AgentCoreServices(
      baseEnv: shell,
      gate: gate,
      logger: RecordingLogger(),
      clock: clock,
      ids: SequentialIdGenerator(),
      sessions: MemorySessionStore(),
      platform: 'linux',
    ),
    config: CoreConfig(defaultModel: testModel),
    streamFunction: model.call,
  );
  final session = await core.runtime.createSession(
    SessionSpec(cwd: '/proj', mode: ModeId.ask),
  );
  final trace = <String>[];
  session.events.listen((e) => trace.add(_describe(e)));

  final result = await session.prompt([
    const TextContent('Rename the greeting'),
  ]);
  await pumpEventQueue();
  await core.runtime.dispose();
  model.verify();
  expect(result.reason, TurnEndReason.completed);
  final file = switch (await memory.readText('/proj/lib/greet.dart')) {
    Ok(:final value) => value,
    Err(:final error) => '$error',
  };
  return _Run(trace, gate.requests, file, shell.commands);
}

/// Подробное описание события: для сравнения прогонов важны и данные.
String _describe(AgentEvent e) => switch (e) {
  ToolCallStarted(:final toolCallId, :final title, :final locations) =>
    'ToolCallStarted($toolCallId "$title" $locations)',
  ToolCallFinished(:final toolCallId, :final outcome, :final content) =>
    'ToolCallFinished($toolCallId ${outcome.name} '
        '${jsonEncode([for (final b in content) b.toJson()])})',
  MessageEnded(:final message) =>
    'MessageEnded(${jsonEncode(message.toJson())})',
  _ => loop.describe(e),
};

void main() {
  test('read → edit → exec through buildAgentCore', () async {
    final run = await _run();

    expect(run.file, "String greet() => 'Hi';\n");
    expect(run.commands, ['dart test']);
    expect(
      run.trace
          .where((e) => e.startsWith('ToolCallFinished'))
          .map((e) => e.split(' ').take(2).join(' ')),
      [
        'ToolCallFinished(c1 completed',
        'ToolCallFinished(c2 completed',
        'ToolCallFinished(c3 completed',
      ],
    );
    expect(run.trace.first, 'TurnStarted');
    // Заголовок первого хода — событие сессии после TurnEnded (design.md
    // этапа 3, D6).
    expect(run.trace.sublist(run.trace.length - 2), [
      'TurnEnded(completed)',
      'SessionTitleChanged(Rename the greeting)',
    ]);
    // В режиме ask gate спрашивает каждый вызов; запрос edit несёт
    // аргументы, место и diff (PERM-6).
    expect(run.requests.map((r) => r.tool), ['read', 'edit', 'exec']);
    final edit = run.requests[1];
    expect(edit.rawInput, {
      'path': 'lib/greet.dart',
      'oldText': 'Hello',
      'newText': 'Hi',
    });
    expect(edit.locations, [const Location('/proj/lib/greet.dart', line: 1)]);
    expect(edit.diffs, [
      const FileDiff(
        path: '/proj/lib/greet.dart',
        oldText: "String greet() => 'Hello';\n",
        newText: "String greet() => 'Hi';\n",
      ),
    ]);
    expect(run.requests[2].rawInput, {'command': 'dart test'});
  });

  test('same script yields identical event sequence on 100 runs', () async {
    final first = await _run();
    for (var i = 1; i < 100; i++) {
      final next = await _run();
      expect(next.trace, first.trace, reason: 'run ${i + 1}');
    }
  });

  // core/pairing-survives-cancel: ответ с двумя вызовами оборван отменой до
  // результатов; следующий ход всё равно уходит модели с парными вызовами.
  test('pairing survives a cancel between calls and results', () async {
    final clock = FakeClock();
    final requests = <LlmContext>[];
    final h = await loop.LoopHarness.create(
      tools: [FakeTool('probe')],
      stream: (model, context, {cancel}) {
        requests.add(context);
        final out = AssistantMessageEventStream();
        final state = ProviderStreamState(model, clock, out)..start();
        if (requests.length == 1) {
          for (final id in ['a', 'b']) {
            final index = state.openBlock(
              BlockKind.toolCall,
              id: id,
              name: 'probe',
            );
            state
              ..append(index, '{}')
              ..closeBlock(index);
          }
          cancel?.onCancel.then((_) {
            state.fail(
              LlmErrorClass.aborted,
              'Request was aborted',
              aborted: true,
            );
            out.end();
          });
        } else {
          final index = state.openBlock(BlockKind.text);
          state
            ..append(index, 'ok')
            ..closeBlock(index)
            ..finish(StopReason.stop);
          out.end();
        }
        return out;
      },
    );
    final agent = Agent(config: h.config(), systemPrompt: '', tools: h.tools);
    final repaired = <ToolPairingRepaired>[];
    agent.subscribe((e) {
      if (e is ToolPairingRepaired) {
        repaired.add(e);
      }
      if (e is MessageStarted &&
          e.message is AssistantMessage &&
          requests.length == 1) {
        agent.abort();
      }
    });

    await agent.prompt([loop.user('go')]);
    await agent.prompt([loop.user('again')]);

    final payload = requests.last.messages;
    final calls = {
      for (final m in payload.whereType<AssistantMessage>())
        ...m.toolCalls.map((c) => c.id),
    };
    final results = {
      for (final m in payload.whereType<ToolResultMessage>()) m.toolCallId,
    };
    expect(calls, {'a', 'b'});
    expect(results, calls);
    expect(repaired, hasLength(1));
    expect(repairToolPairing(payload).report.isEmpty, isTrue);
  });
}
