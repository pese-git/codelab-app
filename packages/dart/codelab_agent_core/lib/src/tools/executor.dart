import 'dart:async';

import '../cancel/cancel_token.dart';
import '../env/execution_env.dart';
import '../llm/messages.dart';
import '../loop/agent_events.dart';
import '../loop/loop_config.dart';
import '../util/logger.dart';
import '../util/result.dart';
import 'agent_tool.dart';
import 'registry.dart';
import 'truncate.dart';
import 'validator.dart';

/// The single execution point of tools (`agent-core-architecture` §6.3.1):
/// the only code that calls `AgentTool.execute` (TOOL-1).
///
/// A call goes in two phases so that a parallel batch announces its calls
/// in the order of the answer before any of them runs (§5.5):
/// [ToolExecutor.announce] emits `ToolCallStarted`, [ToolExecutor.complete]
/// runs the remaining steps and emits `ToolCallFinished`.
abstract interface class ToolExecutor {
  Future<ToolCallHandle> announce(ToolCall call, ToolInvocation invocation);

  Future<ToolExecutionOutcome> complete(ToolCallHandle handle);

  /// A call of a sequential batch left after a cancel: `cancelled` with
  /// `Tool call was cancelled before it started`, without running it.
  Future<ToolExecutionOutcome> abandon(ToolCallHandle handle);
}

/// What the loop gives the execution point for one call.
final class ToolInvocation {
  ToolInvocation({
    required this.sessionId,
    required this.cancel,
    required List<String> stepTools,
    required this.emit,
    List<BeforeToolCallHook> beforeToolCall = const [],
    List<AfterToolCallHook> afterToolCall = const [],
  }) : stepTools = List.unmodifiable(stepTools),
       beforeToolCall = List.unmodifiable(beforeToolCall),
       afterToolCall = List.unmodifiable(afterToolCall);

  final SessionId sessionId;
  final CancelToken cancel;

  /// Names of the schemas of the current step.
  final List<String> stepTools;
  final AgentEventSink emit;
  final List<BeforeToolCallHook> beforeToolCall;
  final List<AfterToolCallHook> afterToolCall;
}

/// An announced call.
final class ToolCallHandle {
  ToolCallHandle._(
    this.call,
    this.invocation,
    this.tool,
    this.context,
    this._progress,
  );

  final ToolCall call;
  final ToolInvocation invocation;

  /// `null` — the tool is not available in this step.
  final AgentTool? tool;
  final ToolContext context;

  /// Deliveries of `ToolCallProgress` awaited before the finish (§5.5).
  final List<Future<void>> _progress;
}

const cancelledText = 'Tool call was cancelled';
const cancelledBeforeStartText = 'Tool call was cancelled before it started';

final class ToolCallExecutor implements ToolExecutor {
  ToolCallExecutor({
    required this.registry,
    required this.env,
    required this.services,
  });

  final ToolRegistry registry;

  /// The bounded env of the session (ENV-2).
  final ExecutionEnv env;
  final ToolServices services;

  @override
  Future<ToolCallHandle> announce(
    ToolCall call,
    ToolInvocation invocation,
  ) async {
    final available = invocation.stepTools.contains(call.name);
    final tool = available ? registry.lookup(call.name) : null;
    final progress = <Future<void>>[];
    final context = ToolContext(
      env: env,
      cancel: invocation.cancel,
      toolCallId: call.id,
      services: services,
      stepTools: invocation.stepTools,
      onUpdate: (partial) => progress.add(
        Future.sync(
          () => invocation.emit(
            ToolCallProgress(
              invocation.sessionId,
              toolCallId: call.id,
              content: [for (final b in partial.content) ToolCallBlock(b)],
            ),
          ),
        ),
      ),
    );
    var presentation = ToolPresentation(title: call.name);
    if (tool != null) {
      try {
        presentation = await tool.present(call.arguments, context);
      } on Object catch (error, stack) {
        services.logger.log(
          LogLevel.debug,
          'tool.present.error',
          fields: {'tool': call.name, 'tool_call_id': call.id},
          error: error,
          stack: stack,
        );
      }
    }
    await invocation.emit(
      ToolCallStarted(
        invocation.sessionId,
        toolCallId: call.id,
        tool: call.name,
        kind: tool?.kindOf(call.arguments) ?? ToolKind.other,
        title: presentation.title,
        input: call.arguments,
        locations: presentation.locations,
      ),
    );
    return ToolCallHandle._(call, invocation, tool, context, progress);
  }

  @override
  Future<ToolExecutionOutcome> abandon(ToolCallHandle handle) => _finish(
    handle,
    const ToolExecutionResult([
      TextContent(cancelledBeforeStartText),
    ], isError: true),
    ToolOutcome.cancelled,
  );

  @override
  Future<ToolExecutionOutcome> complete(ToolCallHandle handle) async {
    final (result, outcome) = await _run(handle);
    return _finish(handle, result, outcome);
  }

  Future<(ToolExecutionResult, ToolOutcome)> _run(ToolCallHandle handle) async {
    final call = handle.call;
    final invocation = handle.invocation;
    final tool = handle.tool;
    if (tool == null) {
      return _error(
        'Tool "${call.name}" is not available. '
        'Available tools: ${invocation.stepTools.join(', ')}.',
        ToolOutcome.failed,
      );
    }
    final Map<String, Object?> args;
    switch (validateArguments(tool.parameters, call.arguments)) {
      case Ok(:final value):
        args = value;
      case Err(:final error):
        return _error(
          formatInvalidArguments(call.name, error, call.arguments),
          ToolOutcome.failed,
        );
    }
    try {
      if (tool.preflight(args) case final text?) {
        return _error(text, ToolOutcome.failed);
      }
      for (final hook in invocation.beforeToolCall) {
        if (await hook(call, args, handle.context) case final block?) {
          return _error(block.reason, block.outcome);
        }
      }
    } on Object catch (error) {
      return _error(errorText(error), ToolOutcome.failed);
    }
    if (invocation.cancel.isCancelled) {
      return _error(cancelledText, ToolOutcome.cancelled);
    }
    ToolExecutionResult result;
    try {
      result = await tool.execute(args, handle.context);
    } on CancelledException {
      return _error(cancelledText, ToolOutcome.cancelled);
    } on Object catch (error) {
      return _error(errorText(error), ToolOutcome.failed);
    }
    if (!tool.truncatesOutput) {
      result = _limit(result);
    }
    for (final hook in invocation.afterToolCall) {
      try {
        final override = await hook(call, result, result.isError);
        if (override != null) {
          result = ToolExecutionResult(
            override.content ?? result.content,
            diffs: result.diffs,
            isError: override.isError ?? result.isError,
          );
        }
      } on Object catch (error) {
        result = ToolExecutionResult([
          TextContent(errorText(error)),
        ], isError: true);
      }
    }
    return (
      result,
      result.isError ? ToolOutcome.failed : ToolOutcome.completed,
    );
  }

  Future<ToolExecutionOutcome> _finish(
    ToolCallHandle handle,
    ToolExecutionResult result,
    ToolOutcome outcome,
  ) async {
    await Future.wait(handle._progress);
    final invocation = handle.invocation;
    await invocation.emit(
      ToolCallFinished(
        invocation.sessionId,
        toolCallId: handle.call.id,
        outcome: outcome,
        content: result.content,
        diffs: result.diffs,
      ),
    );
    return ToolExecutionOutcome(
      message: ToolResultMessage(
        toolCallId: handle.call.id,
        toolName: handle.call.name,
        content: result.content,
        isError: result.isError || outcome != ToolOutcome.completed,
        timestamp: services.clock.now(),
      ),
      outcome: outcome,
      diffs: result.diffs,
    );
  }

  /// The safety net of TOOL-9 for a tool that did not truncate itself.
  static ToolExecutionResult _limit(ToolExecutionResult result) {
    var changed = false;
    final content = [
      for (final block in result.content)
        if (block is TextContent)
          () {
            final cut = truncateHead(block.text);
            if (!cut.truncated) {
              return block;
            }
            changed = true;
            return TextContent(
              '${cut.text}\n'
              '${TruncationNotices.head(kept: cut.keptLines, total: cut.totalLines)}',
            );
          }()
        else
          block,
    ];
    return changed
        ? ToolExecutionResult(
            content,
            diffs: result.diffs,
            isError: result.isError,
          )
        : result;
  }

  static (ToolExecutionResult, ToolOutcome) _error(
    String text,
    ToolOutcome outcome,
  ) => (ToolExecutionResult([TextContent(text)], isError: true), outcome);
}

const _dartPrefixes = ['Exception: ', 'Bad state: ', 'Invalid argument(s): '];

/// The text of an exception for the model, without the service prefixes
/// of Dart.
String errorText(Object error) {
  var text = '$error';
  var stripped = true;
  while (stripped) {
    stripped = false;
    for (final prefix in _dartPrefixes) {
      if (text.startsWith(prefix)) {
        text = text.substring(prefix.length);
        stripped = true;
      }
    }
  }
  return text;
}
