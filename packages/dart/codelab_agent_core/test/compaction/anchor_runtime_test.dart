import 'dart:async';

import 'package:codelab_agent_core/codelab_agent_core.dart';
import 'package:codelab_agent_core/src/compaction/estimate.dart';
import 'package:codelab_agent_core/testing.dart';
import 'package:test/test.dart';

import '../host/core_harness.dart' show inMemoryJournal, noExec;
import '../permissions/fake_gate.dart';
import '../support/models.dart';
import 'anchor_support.dart';

/// Якорь сжатия в рантайме: смена схем, ошибка и отмена сжатия (change
/// `anchor-context-estimate-after-compaction`: agent-compaction «Изменение
/// схем после сжатия», «Ошибка суммаризатора», «Отмена посреди генерации»;
/// design.md D1, D3, D7, R4; CMP-3, CMP-4, CMP-11).
void main() {
  late AgentSession session;
  late List<LlmContext> contexts;
  late List<AgentEvent> events;
  int summaries() =>
      contexts.where((c) => c.cacheKey?.endsWith(':summary') ?? false).length;
  late int hooked;
  late BuiltAgentCore core;
  late MemorySessionStore store;

  /// [onSummary] вызывается при n-м запросе суммаризатора (с 1) до ответа.
  Future<void> open(
    List<Map<String, Object?>> steps, {
    void Function(int n)? onSummary,
  }) async {
    final clock = FakeClock();
    final scripted = ScriptedStreamFunction.fromJson({
      'steps': steps,
    }, clock: clock);
    contexts = [];
    hooked = 0;
    store = MemorySessionStore();
    core = buildAgentCore(
      profile: HostProfile.of(
        'agent-serve',
      ).narrowed({...inMemoryJournal, ...noExec}),
      services: AgentCoreServices(
        baseEnv: MemoryExecutionEnv(cwd: '/proj'),
        gate: FakeGate(),
        logger: RecordingLogger(clock: clock),
        clock: clock,
        ids: SequentialIdGenerator(),
        sessions: store,
        projectFiles: AnchorAgents(4000),
      ),
      config: CoreConfig(
        defaultModel: modelWithWindow(16384),
        compaction: anchorCompaction,
      ),
      streamFunction: (ref, context, {cancel}) {
        contexts.add(context);
        if (context.cacheKey?.endsWith(':summary') ?? false) {
          onSummary?.call(++hooked);
        }
        return scripted.call(ref, context, cancel: cancel);
      },
    );
    session = await core.runtime.createSession(SessionSpec(cwd: '/proj'));
    events = [];
    session.events.listen(events.add);
    addTearDown(core.runtime.dispose);
  }

  Future<void> say(String text) => session.prompt([TextContent(text)]);

  Future<CompactionRecord> firstRecord() async => (await store.open(
    session.id,
  )).records.whereType<CompactionRecord>().first;

  List<Map<String, Object?>> head() => [
    turn('a' * 8000, input: 3000),
    turn('b' * 8000, input: 7500),
    turn('## Summary'),
  ];

  /// Сообщения запроса после покрытой первым сжатием части: покрыто всё, что
  /// было в проекции после записи, то есть без сообщений трёх ходов
  /// пользователя после неё.
  int tailAfter(LlmContext request, int covered) =>
      estimateTokens(request.messages.skip(covered).toList());

  test('the toolset changes after the compaction: the estimate differs from '
      'tokensAfter plus the tail by the difference of the heuristics of the '
      'schemas and the prompt (D7)', () async {
    await open([...head(), turn('ok')]);
    await say('first task');
    await say('second task');
    // Контекст, с которым сжатие считало «после» (стандартный режим).
    final before = contexts.where((c) => c.tools.isNotEmpty).last;

    await session.setMode(ModeId.plan);
    await say('third task');

    final record = await firstRecord();
    final after = contexts.last;
    int constant(LlmContext c) =>
        estimateTokens(const [], systemPrompt: c.systemPrompt, tools: c.tools);
    expect(
      constant(after),
      isNot(constant(before)),
      reason: 'the premise: the plan mode changes the prompt or the schemas',
    );
    final requested = firstRequestOfTurn(events, 2);
    expect(requested, isNotNull);
    expect(
      requested!.estimatedTokens,
      record.tokensAfter +
          estimateTokens([after.messages.last]) +
          constant(after) -
          constant(before),
    );
  });

  /// Сжатие №2 по `/compact` после небольшого третьего хода; якорь первой
  /// записи остаётся, `fourth task` оценивается от `tokensAfter` первой
  /// записи плюс сообщения после неё (R4, CMP-3, CMP-4).
  Future<void> expectFirstAnchorKept() async {
    final record = await firstRecord();
    final requests = contexts.where((c) => c.tools.isNotEmpty).toList();
    // Запрос третьего хода — первый после первой записи: в нём покрытая
    // часть плюс `third task`.
    final third = requests[2];
    final covered = third.messages.length - 1;
    final fourth = requests.last;
    final requested = firstRequestOfTurn(events, 4);
    expect(requested, isNotNull);
    expect(
      requested!.estimatedTokens,
      record.tokensAfter + tailAfter(fourth, covered),
    );
    expect(
      requested.estimatedTokens,
      isNot(heuristicOf(fourth)),
      reason: 'the premise: the plain heuristic differs',
    );
  }

  test('a failed summarizer: nothing is written, the next estimate counts '
      'from the previous anchor (R4, CMP-3)', () async {
    await open([
      ...head(),
      turn('c' * 4000),
      {
        'error': {'class': 'rateLimited', 'message': 'slow down'},
      },
      turn('fourth answer'),
    ]);
    await say('first task');
    await say('second task');
    await say('third task');
    final records = (await store.open(session.id)).records.length;

    await say('/compact');
    expect(
      summaries(),
      2,
      reason: 'the precondition: /compact asked the model',
    );
    await say('fourth task');

    final after = (await store.open(session.id)).records;
    expect(after.whereType<CompactionRecord>(), hasLength(1));
    expect(after.length, greaterThan(records));
    await expectFirstAnchorKept();
  });

  test('a cancel during the summary: nothing is written, the next estimate '
      'counts from the previous anchor (R4, CMP-4)', () async {
    await open(
      [...head(), turn('c' * 4000), turn('## Never written'), turn('fourth')],
      onSummary: (n) {
        if (n == 2) unawaited(session.cancel());
      },
    );
    await say('first task');
    await say('second task');
    await say('third task');

    final cancelled = await session.prompt(const [TextContent('/compact')]);
    expect(
      summaries(),
      2,
      reason: 'the precondition: /compact asked the model',
    );
    expect(cancelled.reason, TurnEndReason.cancelled);
    await say('fourth task');

    final records = (await store.open(session.id)).records;
    expect(records.whereType<CompactionRecord>(), hasLength(1));
    await expectFirstAnchorKept();
  });
}
