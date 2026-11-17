import 'package:codelab_agent_core/codelab_agent_core.dart';
import 'package:codelab_agent_core/src/compaction/estimate.dart';
import 'package:codelab_agent_core/src/loop/agent_loop.dart'
    show contextExhaustedText;
import 'package:test/test.dart';

import '../host/core_harness.dart';
import '../permissions/fake_gate.dart';
import '../support/models.dart';

/// Аварийное сжатие `preflight` и следующий запрос считают контекст на одной
/// шкале (design.md change `anchor-context-estimate-after-compaction`, D1,
/// D3, D8; CMP-5, CMP-8, CMP-11).
///
/// Почему: «до» якорится на usage провайдера, а проекция после сжатия якоря
/// не имеет (§8.7). Без якоря сжатия цикл оценивал её чистой эвристикой,
/// которая завышает постоянную часть (промпт, схемы), — компактор делал
/// лишние проходы по D9 предшественника, а при невозможности резать дальше
/// ход терялся с `context window exhausted`. С якорем сжатия оценка после
/// записи — `tokensAfter` записи (CMP-11), один проход достаточен.
///
/// Заменил тесты D9 предшественника `fix-compaction-estimate-and-no-gain`
/// («две записи, два запроса суммаризатора, проверка `estimateLlmContext`»).
void main() {
  const window = 8192;

  Map<String, Object?> readStep(String id, String path, int input) => {
    'reply': [
      {
        'toolCall': {
          'id': id,
          'name': 'read',
          'arguments': {'path': path},
        },
      },
    ],
    'usage': {'input': input, 'output': 20},
  };

  Map<String, Object?> answer(String text, int input) => {
    'reply': [
      {'text': text},
    ],
    'usage': {'input': input, 'output': 20},
  };

  test('after the preflight compaction one pass is enough: one record, one '
      'summarizer request, the repeated request is estimated by tokensAfter '
      '(D8, CMP-8, CMP-11)', () async {
    final memory = MemoryExecutionEnv(cwd: '/proj');
    final body = [
      for (var i = 0; i < 55; i++) 'line $i of a large file: ${'x' * 60}',
    ].join('\n');
    for (final name in ['a', 'b', 'c', 'd', 'e']) {
      await memory.writeText('/proj/$name.txt', body);
    }
    // Якорь usage (≈1 500 токенов на 7 000 эвристики) заметно ниже эвристики:
    // «согласованное после» укладывается в порог, а «эвристика после» — нет.
    final h = CoreHarness.build(
      baseEnv: memory,
      narrow: noExec,
      gate: FakeGate(),
      defaultModel: modelWithWindow(16384),
      compaction: const CompactionOverrides(
        reserveTokens: 1024,
        keepRecentTokens: 1500,
        keepRecentUserTurns: 1,
        contextWindowCap: window,
      ),
      projectFiles: _Agents(
        ContextFile(path: 'AGENTS.md', content: 'p' * 12000),
      ),
      steps: [
        answer('b' * 8000, 1500),
        answer('a' * 8000, 1500),
        readStep('c1', 'a.txt', 1500),
        readStep('c2', 'b.txt', 2500),
        readStep('c3', 'c.txt', 3500),
        readStep('c4', 'd.txt', 5000),
        readStep('c5', 'e.txt', 7000),
        // Сводка аварийного сжатия: один проход, «после» уже в пороге (D8).
        answer('## Summary one', 1500),
        answer('Done.', 1500),
      ],
    );
    final session = await h.core.runtime.createSession(
      SessionSpec(cwd: '/proj', mode: ModeId.bypass),
    );
    final events = <AgentEvent>[];
    session.events.listen(events.add);
    await session.prompt(const [TextContent('zeroth task')]);
    await session.prompt(const [TextContent('first task')]);

    final result = await session.prompt(const [TextContent('second task')]);

    expect(
      events.whereType<AgentError>().map((e) => e.message),
      isNot(contains(contextExhaustedText)),
    );
    expect(result.reason, TurnEndReason.completed);
    final snapshot = await h.sessions.open(session.id);
    final records = snapshot.records.whereType<CompactionRecord>().toList();
    // D8: согласованное «после» первого прохода уже в пороге — второй проход
    // по эвристике проекции (D9 предшественника) не нужен.
    expect(records, hasLength(1), reason: 'one pass (D8)');
    h.model.verify();
    expect(
      h.model.requests.where((r) => r.cacheKey?.endsWith(':summary') ?? false),
      hasLength(1),
    );
    final lastAnswer = snapshot.records
        .whereType<MessageRecord>()
        .map((r) => r.message)
        .whereType<AssistantMessage>()
        .last;
    expect((lastAnswer.content.single as TextContent).text, 'Done.');
    // Повторный запрос после сжатия: оценка — `tokensAfter` записи (CMP-11),
    // а не эвристика проекции с завышенной постоянной частью.
    final requested = events
        .skipWhile((e) => e is! ContextCompacted)
        .whereType<ModelRequested>()
        .first;
    expect(requested.estimatedTokens, records.single.tokensAfter);
    expect(requested.estimatedTokens, lessThanOrEqualTo(window));
    await h.core.runtime.dispose();
  });

  // Наблюдение change `anchor-context-estimate-after-compaction`: эвристика
  // проекции после сжатия выше окна (постоянная часть завышена), а резать
  // больше нечего. До change: три прохода (второй и третий — `no cut point`),
  // `preflight` следующего запроса видит эвристику выше окна, аварийный вызов
  // уже использован, ход — `failed` с `context window exhausted`.
  test('the heuristic of the projection after the compaction is above the '
      'window, nothing more to cut: one pass, the turn completes, the '
      'estimate is tokensAfter (D8, CMP-11)', () async {
    final memory = MemoryExecutionEnv(cwd: '/proj');
    final body = [
      for (var i = 0; i < 55; i++) 'line $i of a large file: ${'x' * 60}',
    ].join('\n');
    for (final name in ['a', 'b', 'c', 'd']) {
      await memory.writeText('/proj/$name.txt', body);
    }
    final h = CoreHarness.build(
      baseEnv: memory,
      narrow: noExec,
      gate: FakeGate(),
      defaultModel: modelWithWindow(16384),
      compaction: const CompactionOverrides(
        reserveTokens: 1024,
        keepRecentTokens: 1500,
        keepRecentUserTurns: 1,
        contextWindowCap: window,
      ),
      // Постоянная часть по эвристике (≈7 100) почти равна окну: после
      // сжатия с резюме и сохранённым ходом эвристика уже выше окна.
      projectFiles: _Agents(
        ContextFile(path: 'AGENTS.md', content: 'p' * 20000),
      ),
      steps: [
        readStep('c1', 'a.txt', 1000),
        readStep('c2', 'b.txt', 2500),
        readStep('c3', 'c.txt', 4500),
        readStep('c4', 'd.txt', 7500),
        answer('## Summary one', 1000),
        answer('Done.', 1000),
      ],
    );
    final session = await h.core.runtime.createSession(
      SessionSpec(cwd: '/proj', mode: ModeId.bypass),
    );
    final events = <AgentEvent>[];
    session.events.listen(events.add);

    final result = await session.prompt(const [TextContent('big task')]);

    expect(
      events.whereType<AgentError>().map((e) => e.message),
      isNot(contains(contextExhaustedText)),
    );
    expect(result.reason, TurnEndReason.completed);
    final snapshot = await h.sessions.open(session.id);
    final records = snapshot.records.whereType<CompactionRecord>().toList();
    expect(records, hasLength(1));
    expect(
      h.model.requests.where((r) => r.cacheKey?.endsWith(':summary') ?? false),
      hasLength(1),
    );
    final after = h.requestedContexts.where((c) => c.tools.isNotEmpty).last;
    expect(
      estimateTokens(
        after.messages,
        systemPrompt: after.systemPrompt,
        tools: after.tools,
      ),
      greaterThan(window),
      reason: 'the premise: the heuristic is above the window',
    );
    final requested = events
        .skipWhile((e) => e is! ContextCompacted)
        .whereType<ModelRequested>()
        .first;
    expect(requested.estimatedTokens, records.single.tokensAfter);
    expect(requested.estimatedTokens, lessThanOrEqualTo(window));
    await h.core.runtime.dispose();
  });
}

final class _Agents implements ProjectFilesSource {
  _Agents(this.file);

  final ContextFile file;

  @override
  Future<ProjectFiles> load(ProjectFilesQuery query) async =>
      ProjectFiles(context: [file]);
}
