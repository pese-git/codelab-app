import 'package:codelab_agent_core/codelab_agent_core.dart';
import 'package:codelab_agent_core/src/compaction/estimate.dart';
import 'package:codelab_agent_core/src/loop/agent_loop.dart'
    show contextExhaustedText;
import 'package:test/test.dart';

import '../host/core_harness.dart';
import '../permissions/fake_gate.dart';
import '../support/models.dart';

/// Аварийное сжатие `preflight` видит то же, что увидит цикл (design.md change
/// `fix-compaction-estimate-and-no-gain`, D9; CMP-5, CMP-8).
///
/// Почему: «до» якорится на usage провайдера, а проекция после сжатия якоря
/// не имеет (§8.7) — цикл оценивает её чистой эвристикой. Если эвристика
/// завышает постоянную часть (промпт, схемы) сильнее, чем резерв, согласованное
/// «после» уже ниже порога, а preflight цикла всё ещё видит `estimated > window`;
/// аварийный вызов использован (CMP-8), и ход терялся бы с
/// `context window exhausted`. Компактор сравнивает порог с
/// `max(after, rawAfter)` и делает ещё проход.
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

  test('after the preflight compaction the provider is called again, the '
      'turn does not end with the exhausted window (D9, CMP-8)', () async {
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
        // Сводки аварийного сжатия: проход 1 (ходы 1–2) и проход 2 (срез
        // внутри последнего хода) — по одному запросу суммаризатора.
        answer('## Summary one', 1500),
        answer('## Summary two', 1500),
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

    // Один проход давал «после» ниже порога при эвристике выше окна: цикл
    // видел `estimated > window`, аварийный вызов уже был — ход терялся.
    expect(
      events.whereType<AgentError>().map((e) => e.message),
      isNot(contains(contextExhaustedText)),
    );
    expect(result.reason, TurnEndReason.completed);
    final snapshot = await h.sessions.open(session.id);
    final records = snapshot.records.whereType<CompactionRecord>().toList();
    // Второй проход — это и есть D9: согласованное «после» первого уже в
    // пороге, дальше сжимает только эвристика проекции без якоря.
    expect(records, hasLength(2), reason: 'a second pass (D9)');
    // Сценарий закреплён: все шаги израсходованы, запросов суммаризатора ровно
    // два, а ход закончился ответом «Done.».
    h.model.verify();
    expect(
      h.model.requests.where((r) => r.cacheKey?.endsWith(':summary') ?? false),
      hasLength(2),
    );
    final lastAnswer = snapshot.records
        .whereType<MessageRecord>()
        .map((r) => r.message)
        .whereType<AssistantMessage>()
        .last;
    expect((lastAnswer.content.single as TextContent).text, 'Done.');
    // Итоговый запрос хода не больше окна по эвристике цикла.
    expect(
      h.requestedContexts
          .where((c) => c.tools.isNotEmpty)
          .map(estimateLlmContext)
          .last,
      lessThanOrEqualTo(window),
    );
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
