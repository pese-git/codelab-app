import 'package:codelab_agent_core/codelab_agent_core.dart';
import 'package:codelab_agent_core/src/loop/loop_config.dart';
import 'package:test/test.dart';

import 'loop_harness.dart';

/// Аварийное сжатие в ходе (задача 9.3; agent-loop «Функция хода
/// runAgentLoop», «Хуки и сборка payload», «События AgentEvent»; CMP-8).
void main() {
  final overflow = <String, Object?>{
    'error': {'class': 'overflow', 'message': 'prompt is too long'},
  };

  String firstText(LlmContext context) =>
      ((context.messages.first as UserMessage).content.single as TextContent)
          .text;

  test('overflow → one emergencyCompact and a retry of the step', () async {
    final h = await LoopHarness.create(
      llm: script([overflow, textStep('Done.')]),
    );
    final c = _Compactions();

    final out = await h.runTurn(
      [user('go')],
      history: [user('old 1'), user('old 2')],
      config: h.config(emergencyCompact: c.returning(true)),
    );

    expect(c.causes, [EmergencyCause.overflow]);
    expect(h.scripted!.requests, hasLength(2));
    expect(firstText(h.scripted!.requests.last), 'summary of the past');
    expect(h.trace.last, 'TurnEnded(completed)');
    expect(h.trace.where((e) => e.startsWith('AgentError')), isEmpty);
    // Ответ с ошибкой, после которого был повтор, в транскрипт не входит.
    expect(h.trace.where((e) => e.startsWith('MessageEnded(assistant')), [
      'MessageEnded(assistant stop)',
    ]);
    expect(out.history!.map((m) => m is UserMessage), [true]);
    expect(out.added.single, isA<AssistantMessage>());
  });

  test('a second overflow fails the turn without a second call', () async {
    final h = await LoopHarness.create(llm: script([overflow, overflow]));
    final c = _Compactions();

    await h.runTurn([
      user('go'),
    ], config: h.config(emergencyCompact: c.returning(true)));

    expect(c.causes, hasLength(1));
    expect(h.scripted!.requests, hasLength(2));
    expect(h.trace, contains('AgentError(provider overflow)'));
    expect(h.trace.last, 'TurnEnded(failed)');
  });

  test('overflow with nothing to compact is a plain error', () async {
    final h = await LoopHarness.create(llm: script([overflow]));
    final c = _Compactions();

    await h.runTurn([
      user('go'),
    ], config: h.config(emergencyCompact: c.returning(false)));

    expect(c.causes, hasLength(1));
    expect(h.scripted!.requests, hasLength(1));
    expect(h.trace.last, 'TurnEnded(failed)');
  });

  test('without the fields — stage 2: overflow fails the turn', () async {
    final h = await LoopHarness.create(llm: script([overflow]));

    final out = await h.runTurn([user('go')]);

    expect(h.scripted!.requests, hasLength(1));
    expect(h.trace, contains('AgentError(provider overflow)'));
    expect(h.trace.last, 'TurnEnded(failed)');
    expect(out.history, isNull);
  });

  group('preflight', () {
    test('above the window and no compaction: synthetic overflow', () async {
      final h = await LoopHarness.create(llm: script([]));
      final c = _Compactions();

      await h.runTurn(
        [user('go')],
        config: h.config(
          estimateTokens: (_) => 32001,
          emergencyCompact: c.returning(false),
        ),
      );

      expect(c.causes, [EmergencyCause.preflight]);
      expect(h.scripted!.requests, isEmpty);
      final error = h.events.whereType<AgentError>().single;
      expect(error.errorClass, LlmErrorClass.overflow);
      expect(error.message, 'context window exhausted');
      expect(h.trace.last, 'TurnEnded(failed)');
    });

    test(
      'above the window without emergencyCompact: synthetic overflow',
      () async {
        final h = await LoopHarness.create(llm: script([]));

        await h.runTurn([
          user('go'),
        ], config: h.config(estimateTokens: (_) => 32001));

        expect(h.scripted!.requests, isEmpty);
        expect(h.trace.last, 'TurnEnded(failed)');
      },
    );

    test('a successful compaction rebuilds the payload', () async {
      final h = await LoopHarness.create(llm: script([textStep('Done.')]));
      final c = _Compactions();

      await h.runTurn(
        [user('go')],
        config: h.config(
          estimateTokens: (context) =>
              firstText(context) == 'summary of the past' ? 100 : 40000,
          emergencyCompact: c.returning(true),
        ),
      );

      expect(c.causes, [EmergencyCause.preflight]);
      expect(firstText(h.scripted!.requests.single), 'summary of the past');
      expect(h.trace.last, 'TurnEnded(completed)');
    });

    test('preflight and overflow share one call per turn (CMP-8)', () async {
      final h = await LoopHarness.create(llm: script([overflow]));
      final c = _Compactions();

      await h.runTurn(
        [user('go')],
        config: h.config(
          estimateTokens: (context) =>
              firstText(context) == 'summary of the past' ? 100 : 40000,
          emergencyCompact: c.returning(true),
        ),
      );

      expect(c.causes, [EmergencyCause.preflight]);
      expect(h.scripted!.requests, hasLength(1));
      expect(h.trace.last, 'TurnEnded(failed)');
    });

    test('the window is capped by contextWindowCap (CMP-6)', () async {
      final h = await LoopHarness.create(llm: script([]));
      final c = _Compactions();

      await h.runTurn(
        [user('go')],
        config: h.config(
          estimateTokens: (_) => 25000,
          emergencyCompact: c.returning(false),
          contextWindowCap: 20000,
        ),
      );

      expect(c.causes, [EmergencyCause.preflight]);
      expect(h.scripted!.requests, isEmpty);
    });
  });

  test('ModelRequested carries the estimate of the payload', () async {
    final h = await LoopHarness.create(llm: script([textStep('Done.')]));

    await h.runTurn(
      [user('go')],
      config: h.config(
        estimateTokens: (context) => 7 * context.messages.length,
      ),
    );

    final requested = h.events.whereType<ModelRequested>().single;
    expect(requested.estimatedTokens, 7);
  });

  test('without an estimator estimatedTokens is 0', () async {
    final h = await LoopHarness.create(llm: script([textStep('Done.')]));

    await h.runTurn([user('go')]);

    expect(h.events.whereType<ModelRequested>().single.estimatedTokens, 0);
  });
}

/// Аварийное сжатие, которое заменяет историю одним резюме.
final class _Compactions {
  final causes = <EmergencyCause>[];

  EmergencyCompact returning(bool succeed) => (cause, cancel) async {
    causes.add(cause);
    return succeed
        ? LoopContext(
            systemPrompt: 'You are CodeLab.',
            messages: [user('summary of the past')],
            tools: const [],
          )
        : null;
  };
}
