import '../cancel/cancel_token.dart';
import '../llm/errors.dart';
import '../llm/event_stream.dart';
import '../llm/events.dart';
import '../llm/messages.dart';
import '../llm/stream_function.dart';
import '../llm/usage.dart';
import '../tools/agent_tool.dart';
import '../tools/executor.dart';
import 'agent_events.dart';
import 'loop_config.dart';
import 'payload_builder.dart';
import 'turn_budget.dart';

const truncatedArgumentsText =
    'Tool call arguments were truncated because the response hit the output '
    'token limit. Retry with smaller arguments.';

/// One turn of the agent (`agent-core-architecture` §5.4): call the model,
/// run the tool calls of its answer, repeat while it calls tools. A pure
/// function over the injected `StreamFunction` and [ToolExecutor]: it knows
/// neither storage nor protocol (LOOP-6) and returns the messages the turn
/// added.
///
/// [TurnEnded] is always the last event and is emitted exactly once, also
/// when a hook throws (LOOP-1). The loop awaits every [emit] (LOOP-2).
Future<List<Message>> runAgentLoop({
  required List<Message> prompts,
  required LoopContext context,
  required AgentLoopConfig config,
  required AgentEventSink emit,
  required CancelToken cancel,
}) => _Turn(context, config, emit, cancel).run(prompts);

final class _Turn {
  _Turn(this._context, this._config, this._emit, this._cancel)
    : _transcript = [..._context.messages] {
    for (final message in _transcript) {
      if (message is AssistantMessage) {
        _usedIds.addAll(message.toolCalls.map((c) => c.id));
      }
    }
  }

  LoopContext _context;
  AgentLoopConfig _config;
  final AgentEventSink _emit;
  final CancelToken _cancel;
  final List<Message> _transcript;
  final _added = <Message>[];
  final _usedIds = <String>{};

  SessionId get _session => _config.sessionId;

  Future<List<Message>> run(List<Message> prompts) async {
    TurnEndReason? reason;
    BudgetLimit? exceeded;
    var usage = Usage.zero;
    AssistantMessage? last;
    try {
      await _emit(
        TurnStarted(
          _session,
          turnId: TurnId(_config.ids.nextId()),
          input: prompts,
        ),
      );
      for (final prompt in prompts) {
        await _append(prompt);
      }
      var step = 0;
      var pending = false;
      var newInput = prompts.isNotEmpty;
      while (pending || newInput) {
        newInput = false;
        if (step >= _config.budget.maxSteps) {
          exceeded = BudgetLimit.steps;
          reason = TurnEndReason.completed;
          break;
        }
        if (_cancel.isCancelled) {
          reason = TurnEndReason.cancelled;
          break;
        }
        await _emit(StepStarted(_session, stepIndex: step));
        final response = await _request();
        usage += response.usage;
        last = response;
        if (response.stopReason case StopReason.error || StopReason.aborted) {
          if (response.stopReason == StopReason.error) {
            await _emit(
              AgentError(
                _session,
                cls: AgentErrorClass.provider,
                errorClass: response.errorClass,
                message: response.errorMessage ?? 'model request failed',
              ),
            );
          }
          await _emit(
            StepEnded(
              _session,
              result: StepResult(
                stepIndex: step,
                response: response,
                results: const [],
                usage: response.usage,
              ),
            ),
          );
          reason = _failureReason(response);
          break;
        }
        final calls = response.toolCalls.toList();
        final results = response.stopReason == StopReason.length
            ? [for (final call in calls) _truncatedArguments(call)]
            : await _runBatch(calls);
        for (final result in results) {
          await _append(result);
        }
        final stepResult = StepResult(
          stepIndex: step,
          response: response,
          results: results,
          usage: response.usage,
        );
        await _emit(StepEnded(_session, result: stepResult));
        step++;
        pending = calls.isNotEmpty;
        if (_config.prepareNextStep case final hook?) {
          if (await hook(stepResult) case final update?) {
            _apply(update);
          }
        }
        if (_cancel.isCancelled) {
          reason = TurnEndReason.cancelled;
          break;
        }
      }
      reason ??= last?.stopReason == StopReason.length
          ? TurnEndReason.maxTokens
          : TurnEndReason.completed;
    } on Object catch (error) {
      reason = TurnEndReason.failed;
      exceeded = null;
      try {
        await _emit(
          AgentError(
            _session,
            cls: AgentErrorClass.hook,
            message: errorText(error),
          ),
        );
      } on Object {
        // The turn still ends with TurnEnded below (LOOP-1).
      }
    }
    await _emit(
      TurnEnded(
        _session,
        reason: reason,
        usage: usage,
        budgetExceeded: exceeded,
      ),
    );
    return List.unmodifiable(_added);
  }

  Future<void> _append(Message message) async {
    _transcript.add(message);
    _added.add(message);
    await _emit(MessageStarted(_session, message: message));
    await _emit(MessageEnded(_session, message: message));
  }

  void _apply(StepUpdate update) {
    if (update.model case final model?) {
      _config = _config.copyWith(model: model);
    }
    if (update.context case final context?) {
      _context = context;
      _transcript
        ..clear()
        ..addAll(context.messages);
    }
  }

  /// One model request; a pairing 400 is retried once with a rebuilt
  /// payload (§5.4, step 14; design.md, D8).
  Future<AssistantMessage> _request() async {
    var retried = false;
    while (true) {
      final payload = await buildPayload(
        _transcript,
        cancel: _cancel,
        transform: _config.transformContext,
      );
      if (!payload.report.isEmpty) {
        await _emit(ToolPairingRepaired(_session, report: payload.report));
      }
      final model = _config.model;
      final context = LlmContext(
        systemPrompt: _context.systemPrompt,
        messages: payload.messages,
        tools: [for (final tool in _context.tools) tool.toSchema()],
        cacheKey: _session.value,
      );
      await _emit(
        ModelRequested(
          _session,
          model: model,
          estimatedTokens: 0,
          messageCount: payload.messages.length,
        ),
      );
      final (response, started) = await _consume(
        _config.stream(model, context, cancel: _cancel),
      );
      if (!started &&
          !retried &&
          response.errorClass == LlmErrorClass.badRequest &&
          isPairingError(response.errorMessage)) {
        retried = true;
        continue;
      }
      if (started) {
        _replaceLast(response);
      } else {
        _transcript.add(response);
        _added.add(response);
        await _emit(MessageStarted(_session, message: response));
      }
      await _emit(MessageEnded(_session, message: response));
      return response;
    }
  }

  /// Reads the answer: the first block puts the snapshot into the
  /// transcript with `MessageStarted`; text and reasoning deltas become
  /// `MessageDelta` / `ThoughtDelta`. Returns the final message and
  /// whether `MessageStarted` was emitted.
  Future<(AssistantMessage, bool)> _consume(
    AssistantMessageEventStream stream,
  ) async {
    final kinds = <int, BlockKind>{};
    final renames = <int, String>{};
    var started = false;
    AssistantMessage? result;
    await for (final event in stream) {
      switch (event) {
        case StartEvent():
          break;
        case BlockStartEvent(:final index, :final kind):
          kinds[index] = kind;
          if (!started) {
            started = true;
            final partial = _unique(event.partial, renames);
            _transcript.add(partial);
            _added.add(partial);
            await _emit(MessageStarted(_session, message: partial));
          }
        case BlockDeltaEvent(:final index, :final delta):
          final kind = kinds[index];
          if (kind == BlockKind.text || kind == BlockKind.thinking) {
            final partial = _unique(event.partial, renames);
            _replaceLast(partial);
            await _emit(
              kind == BlockKind.text
                  ? MessageDelta(_session, delta: delta, partial: partial)
                  : ThoughtDelta(_session, delta: delta, partial: partial),
            );
          }
        case BlockEndEvent():
          break;
        case DoneEvent(:final message):
          result = _unique(message, renames);
        case ErrorEvent(:final error):
          result = _unique(error, renames);
      }
    }
    return (result ?? await stream.result, started);
  }

  void _replaceLast(Message message) {
    _transcript[_transcript.length - 1] = message;
    _added[_added.length - 1] = message;
  }

  /// Tool call ids unique in the whole transcript (LOOP-11): a repeated id
  /// gets `_2`, `_3`… the first time the call is seen.
  AssistantMessage _unique(AssistantMessage message, Map<int, String> renames) {
    var changed = false;
    final content = [
      for (final (i, block) in message.content.indexed)
        if (block is ToolCall && block.id.isNotEmpty)
          () {
            final id = renames[i] ??= _freeId(block.id);
            if (id == block.id) {
              return block;
            }
            changed = true;
            return ToolCall(
              id: id,
              name: block.name,
              arguments: block.arguments,
              signature: block.signature,
            );
          }()
        else
          block,
    ];
    return changed ? message.copyWith(content: content) : message;
  }

  String _freeId(String id) {
    var candidate = id;
    for (var n = 2; _usedIds.contains(candidate); n++) {
      candidate = '${id}_$n';
    }
    _usedIds.add(candidate);
    return candidate;
  }

  Future<List<ToolResultMessage>> _runBatch(List<ToolCall> calls) async {
    if (calls.isEmpty) {
      return const [];
    }
    final executor = _config.executor;
    final invocation = ToolInvocation(
      sessionId: _session,
      cancel: _cancel,
      stepTools: [for (final tool in _context.tools) tool.name],
      emit: _emit,
      beforeToolCall: _config.beforeToolCall,
      afterToolCall: _config.afterToolCall,
    );
    final sequential = calls.any((call) {
      final tool = _context.tools.where((t) => t.name == call.name).firstOrNull;
      return tool?.executionModeOf(call.arguments) ==
          ToolExecutionMode.sequential;
    });
    if (!sequential) {
      final handles = <ToolCallHandle>[];
      for (final call in calls) {
        handles.add(await executor.announce(call, invocation));
      }
      final outcomes = await Future.wait(handles.map(executor.complete));
      return [for (final outcome in outcomes) outcome.message];
    }
    final results = <ToolResultMessage>[];
    for (final call in calls) {
      final handle = await executor.announce(call, invocation);
      final outcome = _cancel.isCancelled
          ? await executor.abandon(handle)
          : await executor.complete(handle);
      results.add(outcome.message);
    }
    return results;
  }

  ToolResultMessage _truncatedArguments(ToolCall call) => ToolResultMessage(
    toolCallId: call.id,
    toolName: call.name,
    content: const [TextContent(truncatedArgumentsText)],
    isError: true,
    timestamp: _config.clock.now(),
  );

  static TurnEndReason _failureReason(AssistantMessage response) =>
      switch ((response.stopReason, response.errorClass)) {
        (StopReason.aborted, _) ||
        (_, LlmErrorClass.aborted) => TurnEndReason.cancelled,
        (_, LlmErrorClass.terminalFinish) => TurnEndReason.refused,
        _ => TurnEndReason.failed,
      };
}
