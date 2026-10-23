import 'dart:async';

import '../cancel/cancel_token.dart';
import '../llm/messages.dart';
import '../tools/agent_tool.dart';
import 'agent_events.dart';
import 'agent_loop.dart';
import 'loop_config.dart';

/// The agent with state over [runAgentLoop] (`agent-core-architecture`
/// §5.6): it owns the transcript, the subscribers and the cancel token of
/// the turn. Events go through one queue: every event waits until all
/// listeners, in the order of subscription, handled the previous one
/// (LOOP-2).
final class Agent {
  Agent({
    required this.config,
    required this.systemPrompt,
    required List<AgentTool> tools,
    List<Message> history = const [],
  }) : tools = List.unmodifiable(tools),
       _messages = [...history];

  /// Changes between turns (model, hooks).
  AgentLoopConfig config;
  String systemPrompt;
  List<AgentTool> tools;

  final List<Message> _messages;
  final _listeners = <AgentEventSink>[];
  Future<void> _tail = Future.value();
  CancelTokenSource? _turn;
  Completer<void>? _idle;

  bool get isRunning => _turn != null;

  /// An unmodifiable copy of the transcript.
  List<Message> get messages => List.unmodifiable(_messages);

  /// Runs a turn; a second call while a turn runs is a [StateError]
  /// (LOOP-10). Completes after `TurnEnded` and every listener.
  Future<void> prompt(List<Message> messages) async {
    if (isRunning) {
      throw StateError('a turn is already running');
    }
    final source = CancelTokenSource();
    final idle = Completer<void>();
    _turn = source;
    _idle = idle;
    try {
      final added = await runAgentLoop(
        prompts: messages,
        context: LoopContext(
          systemPrompt: systemPrompt,
          messages: _messages,
          tools: tools,
        ),
        config: config,
        emit: _emit,
        cancel: source.token,
      );
      _messages.addAll(added);
      await _tail;
    } finally {
      _turn = null;
      _idle = null;
      idle.complete();
    }
  }

  /// Cancels the token of the running turn.
  void abort([Object? reason]) => _turn?.cancel(reason);

  /// Completes after `TurnEnded` and every listener; at once without a
  /// turn.
  Future<void> waitForIdle() => _idle?.future ?? _tail;

  /// Returns the function that unsubscribes [listener].
  void Function() subscribe(AgentEventSink listener) {
    _listeners.add(listener);
    return () => _listeners.remove(listener);
  }

  /// Only outside a turn: after compaction (§9).
  void replaceTranscript(List<Message> messages) {
    if (isRunning) {
      throw StateError('the transcript cannot be replaced during a turn');
    }
    _messages
      ..clear()
      ..addAll(messages);
  }

  Future<void> _emit(AgentEvent event) {
    final next = _tail.then((_) async {
      for (final listener in List.of(_listeners)) {
        await listener(event);
      }
    });
    _tail = next.then((_) {}, onError: (Object _) {});
    return next;
  }
}
