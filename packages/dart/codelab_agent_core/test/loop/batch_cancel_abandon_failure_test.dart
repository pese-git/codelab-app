import 'dart:async';

import 'package:codelab_agent_core/codelab_agent_core.dart';
import 'package:codelab_agent_core/src/loop/agent_loop.dart';
import 'package:codelab_agent_core/src/loop/loop_config.dart';
import 'package:codelab_agent_core/src/tools/executor.dart';
import 'package:test/test.dart';

import '../tools/fake_tools.dart';
import 'loop_harness.dart';

/// Сбой `emit(ToolCallFinished)` при откате отменённой группы (TOOL-7,
/// §17.16a.4): ход завершается `failed` с исходной ошибкой, а места очереди
/// ключа освобождаются у ВСЕХ вызовов группы, а не только у первого.
///
/// Почему: `abandon` отпускает тикет до эмита, но цикл прерывал откат на
/// первом же сбое — тикеты остальных хэндлов оставались занятыми, а ожидание
/// ключа отменой не прерывается, поэтому следующий `task_*` сессии висел
/// вечно.
void main() {
  test('отменённая группа из двух вызовов ключа, emit бросает на '
      'ToolCallFinished: все тикеты свободны, ход failed', () async {
    final h = await LoopHarness.create(
      tools: [FakeTool('w', lockKeyValue: 'k')],
      llm: script([
        callStep([('c1', 'w', const {}), ('c2', 'w', const {})]),
        textStep('done'),
      ]),
    );
    final cancel = CancelTokenSource();
    final seen = <AgentEvent>[];
    var started = 0;
    await runAgentLoop(
      prompts: [user('go')],
      context: LoopContext(
        systemPrompt: 'You are CodeLab.',
        messages: const [],
        tools: h.tools,
      ),
      config: h.config(),
      emit: (event) {
        if (event is ToolCallStarted && ++started == 2) {
          // Оба вызова объявлены: группа уходит в ветку отмены.
          cancel.cancel();
        }
        if (event is ToolCallFinished) {
          throw StateError('emit failed');
        }
        seen.add(event);
      },
      cancel: cancel.token,
    );

    // Первая ошибка отката уходит в `AgentError` хода.
    expect(seen.whereType<AgentError>().single.message, 'emit failed');
    expect(seen.whereType<TurnEnded>().single.reason, TurnEndReason.failed);
    expect(seen.whereType<ToolCallFinished>(), isEmpty);
    // Сбой отката каждого хэндла записан в журнал, а не проглочен.
    expect(
      h.logger
          .eventsOf('tool.abandon.error')
          .map((r) => r.fields['tool_call_id']),
      ['c1', 'c2'],
    );

    // Следующий `task_*`-подобный вызов ключа не зависает.
    final handle = await h.executor.announce(
      ToolCall(id: 'c3', name: 'w', arguments: const {}),
      ToolInvocation(
        sessionId: session,
        cancel: CancelToken.none,
        stepTools: ['w'],
        emit: (_) {},
      ),
    );
    final outcome = await h.executor
        .complete(handle)
        .timeout(const Duration(seconds: 2));
    expect(outcome.outcome, ToolOutcome.completed);
  });

  test('emit ToolCallFinished первого вызова повис: тикет второго уже '
      'свободен', () async {
    final h = await LoopHarness.create(
      tools: [FakeTool('w', lockKeyValue: 'k')],
      llm: script([
        callStep([('c1', 'w', const {}), ('c2', 'w', const {})]),
        textStep('done'),
      ]),
    );
    final cancel = CancelTokenSource();
    final hang = Completer<void>();
    var started = 0;
    final hung = Completer<void>();
    final loop = runAgentLoop(
      prompts: [user('go')],
      context: LoopContext(
        systemPrompt: 'You are CodeLab.',
        messages: const [],
        tools: h.tools,
      ),
      config: h.config(),
      emit: (event) async {
        if (event is ToolCallStarted && ++started == 2) cancel.cancel();
        if (event is ToolCallFinished && event.toolCallId == 'c1') {
          hung.complete();
          await hang.future;
        }
      },
      cancel: cancel.token,
    );

    await hung.future.timeout(const Duration(seconds: 2));
    // Откат не ждёт зависший emit первого хэндла: места отпущены до эмитов,
    // поэтому вызов того же ключа проходит.
    final handle = await h.executor
        .announce(
          ToolCall(id: 'c3', name: 'w', arguments: const {}),
          ToolInvocation(
            sessionId: session,
            cancel: CancelToken.none,
            stepTools: ['w'],
            emit: (_) {},
          ),
        )
        .timeout(const Duration(seconds: 2));
    final outcome = await h.executor
        .complete(handle)
        .timeout(const Duration(seconds: 2));
    expect(outcome.outcome, ToolOutcome.completed);

    hang.complete();
    await loop.timeout(const Duration(seconds: 5));
  });
}
