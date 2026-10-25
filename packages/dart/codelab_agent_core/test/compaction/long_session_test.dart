import 'package:codelab_agent_core/codelab_agent_core.dart';
import 'package:codelab_agent_core/src/compaction/settings.dart';
import 'package:codelab_agent_core/src/llm/stream_state.dart';
import 'package:codelab_agent_core/src/tools/pairing.dart';
import 'package:codelab_agent_core/testing.dart';
import 'package:test/test.dart';

import '../host/core_harness.dart';
import '../permissions/fake_gate.dart';
import '../support/models.dart';

/// Длинная сессия продолжается (задача 9.5; agent-compaction «Точки
/// срабатывания сжатия», сценарий «Длинная сессия продолжается»; CMP-1,
/// CMP-5).
void main() {
  test('30 turns with large tool results in a window of 8 192', () async {
    const window = 8192;
    final clock = FakeClock();
    final memory = MemoryExecutionEnv(cwd: '/proj', clock: clock);
    await memory.writeText(
      '/proj/big.txt',
      [
        for (var i = 0; i < 120; i++) 'line $i of a large file: ${'x' * 36}',
      ].join('\n'),
    );
    final model = _SessionModel(clock);
    final core = buildAgentCore(
      profile: HostProfile.of(
        'agent-serve',
      ).narrowed({...inMemoryJournal, ...noExec}),
      services: AgentCoreServices(
        baseEnv: memory,
        gate: FakeGate(),
        logger: RecordingLogger(),
        clock: clock,
        ids: SequentialIdGenerator(),
        sessions: MemorySessionStore(),
      ),
      config: CoreConfig(defaultModel: modelWithWindow(window)),
      streamFunction: model.call,
    );
    final session = await core.runtime.createSession(
      SessionSpec(cwd: '/proj', mode: ModeId.bypass),
    );
    final events = <AgentEvent>[];
    session.events.listen(events.add);

    for (var turn = 0; turn < 30; turn++) {
      final result = await session.prompt([TextContent('task $turn')]);
      expect(result.reason, TurnEndReason.completed, reason: 'turn $turn');
    }
    await core.runtime.dispose();

    for (final (i, request) in model.turnRequests.indexed) {
      expect(
        repairToolPairing(request.messages).report.isEmpty,
        isTrue,
        reason: 'request $i has broken pairing',
      );
    }
    final threshold = compactionThreshold(
      window,
      CompactionSettings.forWindow(window),
    );
    final compacted = <ContextCompacted>[];
    for (final (i, event) in events.indexed) {
      // Последний проход перед следующим ходом (CMP-5).
      if (event is ContextCompacted &&
          (i + 1 == events.length || events[i + 1] is! ContextCompacted)) {
        compacted.add(event);
      }
    }
    expect(compacted, isNotEmpty);
    for (final event in compacted) {
      expect(event.tokensAfter, lessThan(threshold));
    }
  });
}

/// Модель сессии: на запрос хода отвечает вызовом `read`, на результат —
/// текстом, на запрос без инструментов (суммаризатор) — резюме.
final class _SessionModel {
  _SessionModel(this._clock);

  final Clock _clock;
  final turnRequests = <LlmContext>[];
  var _calls = 0;

  AssistantMessageEventStream call(
    ModelRef model,
    LlmContext context, {
    CancelToken? cancel,
  }) {
    final out = AssistantMessageEventStream();
    final state = ProviderStreamState(model, _clock, out)..start();
    void text(String value) {
      final index = state.openBlock(BlockKind.text);
      state
        ..append(index, value)
        ..closeBlock(index)
        ..finish(StopReason.stop);
    }

    if (context.tools.isEmpty) {
      text('## Open user requests\n- keep reading big.txt\n\n## Goal\nRead.');
    } else {
      turnRequests.add(context);
      if (context.messages.last is ToolResultMessage) {
        text('Read it.');
      } else {
        final index = state.openBlock(
          BlockKind.toolCall,
          id: 'r${_calls++}',
          name: 'read',
        );
        state
          ..append(index, '{"path":"big.txt"}')
          ..closeBlock(index)
          ..finish(StopReason.toolUse);
      }
    }
    out.end();
    return out;
  }
}
