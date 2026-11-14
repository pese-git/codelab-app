import 'dart:async';

import 'package:codelab_agent_core/codelab_agent_core.dart';
import 'package:codelab_agent_core/src/tools/executor.dart';
import 'package:test/test.dart';

import '../tools/fake_tools.dart';
import 'loop_harness.dart';

/// Сбой или зависание `emit(ToolCallFinished)` при откате группы в
/// `_runBatch` (TOOL-7): места очереди путей `PathLock` освобождаются у ВСЕХ
/// объявленных вызовов группы, а не только у первого; ход завершается
/// `failed` с нужной ошибкой (LOOP-1).
///
/// Почему: `abandon` отпускает тикет до эмита, но цикл откатывал хэндлы по
/// одному и прерывался на первом же сбое или зависании эмита — тикеты
/// остальных хэндлов оставались занятыми, и следующий `write`/`edit` того же
/// пути в сессии ждал вечно.
///
/// Приёмники здесь не сериализованы, в отличие от `Agent.emit`: проверяется
/// свойство отката — тикеты свободны до эмитов, — которое от приёмника не
/// зависит.
void main() {
  // Параллельный инструмент, который держит путь из аргумента `path`, как
  // `write`/`edit`.
  FakeTool pathTool() =>
      FakeTool('w', executionMode: ToolExecutionMode.parallel, lockArg: 'path');

  const args = {'path': 'a.txt'};

  Future<LoopHarness> harness(int calls) => LoopHarness.create(
    tools: [pathTool()],
    llm: script([
      callStep([for (var i = 1; i <= calls; i++) ('c$i', 'w', args)]),
      textStep('done'),
    ]),
  );

  // Следующий вызов того же пути объявляется и исполняется, а не ждёт тикет,
  // который никто не отпустит.
  Future<void> expectPathFree(LoopHarness h) async {
    final handle = await h.executor
        .announce(
          ToolCall(id: 'next', name: 'w', arguments: args),
          ToolInvocation(
            sessionId: session,
            cancel: CancelToken.none,
            stepTools: const ['w'],
            emit: (_) {},
          ),
        )
        .timeout(const Duration(seconds: 2));
    final outcome = await h.executor
        .complete(handle)
        .timeout(const Duration(seconds: 2));
    expect(outcome.outcome, ToolOutcome.completed);
  }

  ToolOutcome? finishedOf(List<AgentEvent> events, String id) => events
      .whereType<ToolCallFinished>()
      .where((e) => e.toolCallId == id)
      .firstOrNull
      ?.outcome;

  group('ветка отмены группы', () {
    test('emit бросает на ToolCallFinished: все тикеты свободны, ход failed '
        'с первой ошибкой отката', () async {
      final h = await harness(2);
      final cancel = CancelTokenSource();
      var started = 0;
      await h.run(
        [user('go')],
        cancel: cancel.token,
        emit: (event) {
          if (event is ToolCallStarted && ++started == 2) {
            // Оба вызова объявлены: группа уходит в ветку отмены.
            cancel.cancel();
          }
          if (event is ToolCallFinished) {
            throw StateError('emit failed');
          }
          h.events.add(event);
        },
      );

      expect(h.events.whereType<AgentError>().single.message, 'emit failed');
      expect(h.events.last, isA<TurnEnded>());
      expect((h.events.last as TurnEnded).reason, TurnEndReason.failed);
      // Сбой отката каждого хэндла записан в журнал, а не проглочен.
      expect(
        h.logger
            .eventsOf('tool.abandon.error')
            .map((r) => r.fields['tool_call_id']),
        ['c1', 'c2'],
      );
      // D41 п. 5: у каждой записи есть `error_class` — `runtimeType`
      // брошенного приёмником исключения; текст остаётся в `error`.
      for (final record in h.logger.eventsOf('tool.abandon.error')) {
        expect(record.fields['error_class'], 'StateError');
        expect(record.error, contains('emit failed'));
      }
      await expectPathFree(h);
    });

    test('emit ToolCallFinished первого вызова повис: тикет второго уже '
        'свободен, после отпускания ход cancelled', () async {
      final h = await harness(2);
      final cancel = CancelTokenSource();
      final hang = Completer<void>();
      final hung = Completer<void>();
      var started = 0;
      final turn = h.runTurn(
        [user('go')],
        cancel: cancel.token,
        emit: (event) async {
          h.events.add(event);
          if (event is ToolCallStarted && ++started == 2) cancel.cancel();
          if (event is ToolCallFinished && event.toolCallId == 'c1') {
            hung.complete();
            await hang.future;
          }
        },
      );

      await hung.future.timeout(const Duration(seconds: 2));
      // Откат не ждёт зависший emit первого хэндла: места отпущены до
      // эмитов, поэтому вызов того же пути проходит.
      await expectPathFree(h);

      hang.complete();
      await turn.timeout(const Duration(seconds: 5));
      expect(finishedOf(h.events, 'c1'), ToolOutcome.cancelled);
      expect(finishedOf(h.events, 'c2'), ToolOutcome.cancelled);
      expect(
        h.events.whereType<TurnEnded>().single.reason,
        TurnEndReason.cancelled,
      );
    });
  });

  group('ветка сбоя announce', () {
    // c1 и c2 объявлены, объявление c3 бросает: откат c1 и c2.
    void failAnnounceOfC3(AgentEvent event) {
      if (event is ToolCallStarted && event.toolCallId == 'c3') {
        throw StateError('announce failed');
      }
    }

    test('emit ToolCallFinished первого отката бросает: тикет второго '
        'свободен, ход failed с исходной ошибкой announce', () async {
      final h = await harness(3);
      await h.run(
        [user('go')],
        emit: (event) {
          failAnnounceOfC3(event);
          if (event is ToolCallFinished && event.toolCallId == 'c1') {
            throw StateError('finish failed');
          }
          h.events.add(event);
        },
      );

      // Исходная ошибка важнее сбоя отката (LOOP-1).
      expect(
        h.events.whereType<AgentError>().single.message,
        'announce failed',
      );
      expect(
        h.events.whereType<TurnEnded>().single.reason,
        TurnEndReason.failed,
      );
      expect(
        h.logger
            .eventsOf('tool.abandon.error')
            .map((r) => r.fields['tool_call_id']),
        ['c1'],
      );
      // Сбой отката c1 не оборвал откат c2.
      expect(finishedOf(h.events, 'c2'), ToolOutcome.cancelled);
      await expectPathFree(h);
    });

    test('emit ToolCallFinished первого отката повис: тикет второго уже '
        'свободен', () async {
      final h = await harness(3);
      final hang = Completer<void>();
      final hung = Completer<void>();
      final turn = h.runTurn(
        [user('go')],
        emit: (event) async {
          failAnnounceOfC3(event);
          h.events.add(event);
          if (event is ToolCallFinished && event.toolCallId == 'c1') {
            hung.complete();
            await hang.future;
          }
        },
      );

      await hung.future.timeout(const Duration(seconds: 2));
      await expectPathFree(h);

      hang.complete();
      await turn.timeout(const Duration(seconds: 5));
      expect(
        h.events.whereType<AgentError>().single.message,
        'announce failed',
      );
      expect(
        h.events.whereType<TurnEnded>().single.reason,
        TurnEndReason.failed,
      );
      // После отпускания c1 откат c2 тоже дошёл до финиша.
      expect(finishedOf(h.events, 'c2'), ToolOutcome.cancelled);
    });

    test('логгер бросает на tool.abandon.error: исходная ошибка announce не '
        'подменяется, откат идёт до конца', () async {
      final h = await harness(3);
      await h.run(
        [user('go')],
        config: h.config(logger: _ThrowingLogger()),
        emit: (event) {
          failAnnounceOfC3(event);
          if (event is ToolCallFinished) {
            throw StateError('finish failed');
          }
          h.events.add(event);
        },
      );

      expect(
        h.events.whereType<AgentError>().single.message,
        'announce failed',
      );
      expect(
        h.events.whereType<TurnEnded>().single.reason,
        TurnEndReason.failed,
      );
      await expectPathFree(h);
    });
  });
}

/// Логгер, сломанный на записи сбоя отката: проверяет, что сбой журнала не
/// меняет исход хода.
final class _ThrowingLogger implements Logger {
  @override
  bool isEnabled(LogLevel level) => true;

  @override
  void log(
    LogLevel level,
    String event, {
    Map<String, Object?> fields = const {},
    Object? error,
    StackTrace? stack,
  }) {
    if (event == 'tool.abandon.error') {
      throw StateError('logger failed');
    }
  }
}
