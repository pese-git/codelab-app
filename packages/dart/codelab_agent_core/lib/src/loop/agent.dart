import 'dart:async';

import '../cancel/cancel_token.dart';
import '../llm/messages.dart';
import '../tools/agent_tool.dart';
import 'agent_events.dart';
import 'agent_loop.dart';
import 'loop_config.dart';

/// Агент с состоянием поверх [runAgentLoop] (`agent-core-architecture`
/// §5.6).
///
/// Почему отдельно от функции хода: ход — чистая функция, а между ходами
/// нужно хранить транскрипт, подписчиков, токен отмены и очереди
/// steering/follow-up.
///
/// Для чего: события идут через одну очередь — каждое ждёт, пока все
/// подписчики по порядку подписки обработали предыдущее (LOOP-2). Через ту
/// же очередь эмитят сервисы сессии ([emit], например план).
///
/// Как использовать: сессия создаёт агента, подписывается первой
/// ([subscribe]) и запускает ходы [prompt]. Во время хода можно [steer],
/// [followUp] и [abort]; [waitForIdle] ждёт конца хода и подписчиков.
final class Agent {
  Agent({
    required this.config,
    required this.systemPrompt,
    required List<AgentTool> tools,
    List<Message> history = const [],
  }) : tools = List.unmodifiable(tools),
       _messages = [...history];

  /// Меняется между ходами (модель, хуки).
  AgentLoopConfig config;
  String systemPrompt;
  List<AgentTool> tools;

  final List<Message> _messages;
  final _listeners = <AgentEventSink>[];
  final _steering = ListMessageQueue<SteeringItem>();
  final _followUp = ListMessageQueue<Message>();
  Future<void> _tail = Future.value();
  CancelTokenSource? _turn;
  Completer<void>? _idle;

  bool get isRunning => _turn != null;

  /// Неизменяемая копия транскрипта.
  List<Message> get messages => List.unmodifiable(_messages);

  /// Запускает ход; второй вызов во время хода — [StateError] (LOOP-10).
  /// Завершается после `TurnEnded` и всех подписчиков.
  Future<void> prompt(List<Message> messages) async {
    if (isRunning) {
      throw StateError('a turn is already running');
    }
    final source = CancelTokenSource();
    final idle = Completer<void>();
    _turn = source;
    _idle = idle;
    try {
      final out = await runAgentLoop(
        prompts: messages,
        context: LoopContext(
          systemPrompt: systemPrompt,
          messages: _messages,
          tools: tools,
        ),
        config: config.copyWith(steering: _steering, followUp: _followUp),
        emit: emit,
        cancel: source.token,
      );
      // После аварийного сжатия история хода — проекция журнала (§9.8).
      if (out.history case final history?) {
        _messages
          ..clear()
          ..addAll(history);
      }
      _messages.addAll(out.added);
      await _tail;
    } finally {
      _turn = null;
      _idle = null;
      idle.complete();
    }
  }

  /// Корректировка текущей работы: доставляется на ближайшей границе шага,
  /// после всего пакета инструментов, и даёт ещё один шаг (CAN-6). Без хода
  /// ждёт начала следующего.
  void steer(Message message, {MessageOrigin? origin}) =>
      _steering.add(SteeringItem(message, origin: origin));

  /// Следующее задание: доставляется после естественной остановки — когда
  /// модель закончила без вызовов — и стартует шаг в том же ходе.
  void followUp(Message message) => _followUp.add(message);

  /// Отменяет токен идущего хода.
  void abort([Object? reason]) => _turn?.cancel(reason);

  /// Завершается после `TurnEnded` и всех подписчиков; без хода — сразу.
  Future<void> waitForIdle() => _idle?.future ?? _tail;

  /// Возвращает функцию отписки [listener].
  void Function() subscribe(AgentEventSink listener) {
    _listeners.add(listener);
    return () => _listeners.remove(listener);
  }

  /// Только вне хода: после сжатия (§9).
  void replaceTranscript(List<Message> messages) {
    if (isRunning) {
      throw StateError('the transcript cannot be replaced during a turn');
    }
    _messages
      ..clear()
      ..addAll(messages);
  }

  /// Ставит событие в общую очередь: цикл и сервисы сессии (план) эмитят
  /// через неё, поэтому порядок событий один для всех подписчиков (D5).
  Future<void> emit(AgentEvent event) {
    final next = _tail.then((_) async {
      for (final listener in List.of(_listeners)) {
        await listener(event);
      }
    });
    _tail = next.then((_) {}, onError: (Object _) {});
    return next;
  }
}
