import 'dart:async';

import '../cancel/cancel_token.dart';
import '../env/execution_env.dart';
import '../llm/messages.dart';
import '../loop/agent_events.dart';
import '../loop/loop_config.dart';
import '../util/logger.dart';
import '../util/posix_path.dart';
import '../util/result.dart';
import 'agent_tool.dart';
import 'fence.dart';
import 'misuse.dart';
import 'path_lock.dart';
import 'registry.dart';
import 'truncate.dart';
import 'validator.dart';

/// Единая точка исполнения инструментов (`agent-core-architecture` §6.3.1):
/// единственный код, который вызывает `AgentTool.execute` (TOOL-1).
///
/// Почему две фазы: параллельный пакет сначала объявляет все вызовы в
/// порядке ответа модели и только потом исполняет их одновременно (§5.5).
/// Иначе асинхронный `present` одного вызова мог бы обогнать другой, и
/// `ToolCallStarted` пришли бы не по порядку (design.md, D14).
///
/// Как использовать: цикл вызывает [announce] (шаг 1, `ToolCallStarted`),
/// затем [complete] (шаги 1a–10, `ToolCallFinished`) или, для вызова
/// последовательного пакета, оставшегося после отмены, [abandon].
abstract interface class ToolExecutor {
  Future<ToolCallHandle> announce(ToolCall call, ToolInvocation invocation);

  Future<ToolExecutionOutcome> complete(ToolCallHandle handle);

  /// `cancelled` с текстом `Tool call was cancelled before it started`, без
  /// исполнения.
  Future<ToolExecutionOutcome> abandon(ToolCallHandle handle);
}

/// Что цикл передаёт точке исполнения на один вызов.
///
/// Почему отдельный объект: данные хода и шага (токен, схемы шага, хуки,
/// предохранитель, возможности модели) меняются от шага к шагу, а
/// [ToolCallExecutor] живёт всю сессию.
final class ToolInvocation {
  ToolInvocation({
    required this.sessionId,
    required this.cancel,
    required List<String> stepTools,
    required this.emit,
    List<BeforeToolCallHook> beforeToolCall = const [],
    List<AfterToolCallHook> afterToolCall = const [],
    this.misuse,
    this.supportsImages = false,
  }) : stepTools = List.unmodifiable(stepTools),
       beforeToolCall = List.unmodifiable(beforeToolCall),
       afterToolCall = List.unmodifiable(afterToolCall);

  final SessionId sessionId;
  final CancelToken cancel;

  /// Имена схем текущего шага.
  final List<String> stepTools;
  final AgentEventSink emit;
  final List<BeforeToolCallHook> beforeToolCall;
  final List<AfterToolCallHook> afterToolCall;

  /// Предохранитель хода (§5.5, шаг 0); `null` — выключен.
  final MisuseBreaker? misuse;

  /// Модель шага принимает картинки.
  final bool supportsImages;
}

/// Объявленный вызов: всё, что [ToolExecutor.complete] нужно для шагов
/// 1a–10.
final class ToolCallHandle {
  ToolCallHandle._(
    this.call,
    this.invocation,
    this.tool,
    this.context,
    this._progress,
    this._lock,
  );

  final ToolCall call;
  final ToolInvocation invocation;

  /// `null` — инструмента нет в схемах этого шага.
  final AgentTool? tool;
  final ToolContext context;

  /// Доставки `ToolCallProgress`, которые ждутся до финиша (§5.5, шаг 5).
  final List<Future<void>> _progress;

  /// Место в очереди `PathLock`, занятое при объявлении; `null` — вызов
  /// путь не блокирует.
  final PathLockTicket? _lock;
}

const cancelledText = 'Tool call was cancelled';
const cancelledBeforeStartText = 'Tool call was cancelled before it started';

/// Реализация [ToolExecutor] над реестром и ограниченным env сессии.
///
/// Как использовать: сессия создаёт один экземпляр; в нём живёт `PathLock`
/// сессии, поэтому правки одного файла упорядочены во всех ходах.
final class ToolCallExecutor implements ToolExecutor {
  ToolCallExecutor({
    required this.registry,
    required this.env,
    required this.services,
  });

  final ToolRegistry registry;

  /// Ограниченный env сессии (ENV-2).
  final ExecutionEnv env;
  final ToolServices services;
  final _locks = PathLock();

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
      misuse: invocation.misuse,
      supportsImages: invocation.supportsImages,
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
    // Место в очереди пути занимается здесь, в порядке ответа: хуки
    // разрешений разных вызовов могут ответить в любом порядке (TOOL-7).
    final lock = switch (tool?.lockPath(call.arguments)) {
      final String raw => switch (normalizePath(env.cwd, raw)) {
        final String abs => _locks.reserve(abs),
        null => null,
      },
      null => null,
    };
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
    return ToolCallHandle._(call, invocation, tool, context, progress, lock);
  }

  @override
  Future<ToolExecutionOutcome> abandon(ToolCallHandle handle) {
    handle._lock?.release();
    return _finish(
      handle,
      const ToolExecutionResult([
        TextContent(cancelledBeforeStartText),
      ], isError: true),
      ToolOutcome.cancelled,
    );
  }

  @override
  Future<ToolExecutionOutcome> complete(ToolCallHandle handle) async {
    final ToolExecutionResult result;
    final ToolOutcome outcome;
    try {
      (result, outcome) = await _run(handle);
    } finally {
      handle._lock?.release();
    }
    return _finish(handle, result, outcome);
  }

  Future<(ToolExecutionResult, ToolOutcome)> _run(ToolCallHandle handle) async {
    final call = handle.call;
    final misuse = handle.invocation.misuse;
    final key = MisuseBreaker.keyOf(call.name, call.arguments);
    // Шаг 1a: заблокированный вызов не валидируется и не исполняется.
    if (misuse != null && misuse.isBlocked(key)) {
      return _error(misuse.blockedText(call.name, key), ToolOutcome.failed);
    }
    final (result, outcome, invalid) = await _checkAndExecute(handle);
    // Шаг 9a: считаются только ошибки шагов 2–3a.
    if (invalid && misuse != null) {
      if (misuse.recordInvalid(key) case final warning?) {
        _logMisuse(misuse, call, key);
        return (_appendText(result, warning), outcome);
      }
    }
    return (result, outcome);
  }

  /// Шаги 2–9; третье значение — вызов неверный (шаги 2, 3, 3a).
  Future<(ToolExecutionResult, ToolOutcome, bool)> _checkAndExecute(
    ToolCallHandle handle,
  ) async {
    final call = handle.call;
    final invocation = handle.invocation;
    final tool = handle.tool;
    if (tool == null) {
      return _invalid(
        'Tool "${call.name}" is not available. '
        'Available tools: ${invocation.stepTools.join(', ')}.',
      );
    }
    final Map<String, Object?> args;
    switch (validateArguments(tool.parameters, call.arguments)) {
      case Ok(:final value):
        args = value;
      case Err(:final error):
        return _invalid(
          formatInvalidArguments(call.name, error, call.arguments),
        );
    }
    try {
      if (tool.preflight(args) case final text?) {
        return _invalid(text);
      }
    } on Object catch (error) {
      return _invalid(errorText(error));
    }
    try {
      for (final hook in invocation.beforeToolCall) {
        if (await hook(call, args, handle.context) case final block?) {
          return _valid(_error(block.reason, block.outcome));
        }
      }
    } on Object catch (error) {
      return _valid(_error(errorText(error), ToolOutcome.failed));
    }
    if (invocation.cancel.isCancelled) {
      return _valid(_error(cancelledText, ToolOutcome.cancelled));
    }
    // Шаг 6: блокировка пути и повторная проверка отмены после захвата.
    if (handle._lock case final lock?) {
      await lock.acquired;
      if (invocation.cancel.isCancelled) {
        return _valid(_error(cancelledText, ToolOutcome.cancelled));
      }
    }
    return _valid(await _execute(handle, tool, args));
  }

  /// Шаги 7–9: исполнение, обработка результата и `afterToolCall`.
  Future<(ToolExecutionResult, ToolOutcome)> _execute(
    ToolCallHandle handle,
    AgentTool tool,
    Map<String, Object?> args,
  ) async {
    final call = handle.call;
    ToolExecutionResult result;
    try {
      result = await tool.execute(args, handle.context);
    } on ToolCancelled catch (cancelled) {
      return (
        ToolExecutionResult(cancelled.content, isError: true),
        ToolOutcome.cancelled,
      );
    } on CancelledException {
      return _error(cancelledText, ToolOutcome.cancelled);
    } on Object catch (error) {
      return _error(errorText(error), ToolOutcome.failed);
    }
    if (!tool.truncatesOutput) {
      result = _limit(result);
    }
    if (tool.outputTrust(args) == ContentTrust.untrusted) {
      result = _fence(result, tool.name);
    }
    for (final hook in handle.invocation.afterToolCall) {
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

  /// Логи §6.3.7: `tool.misuse.blocked` при первой блокировке ключа,
  /// `tool.misuse.warned` на каждое предупреждение.
  void _logMisuse(MisuseBreaker misuse, ToolCall call, String key) {
    final n = misuse.count(key);
    if (misuse.isBlocked(key)) {
      services.logger.log(
        LogLevel.warning,
        'tool.misuse.blocked',
        fields: {'tool': call.name, 'n': n, 'tool_call_id': call.id},
      );
    } else {
      services.logger.log(
        LogLevel.debug,
        'tool.misuse.warned',
        fields: {'tool': call.name, 'n': n, 'tool_call_id': call.id},
      );
    }
  }

  /// Страховочное усечение TOOL-9 для инструмента, который не усекает сам.
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

  /// Шаг 8d: каждый текстовый блок недоверенного вывода огораживается
  /// отдельно, картинки остаются как есть (§6.3.6).
  static ToolExecutionResult _fence(
    ToolExecutionResult result,
    String source,
  ) => ToolExecutionResult(
    [
      for (final block in result.content)
        block is TextContent
            ? TextContent(fenceUntrusted(block.text, source: source))
            : block,
    ],
    diffs: result.diffs,
    isError: result.isError,
  );

  /// Дописывает предупреждение предохранителя в конец текста результата.
  static ToolExecutionResult _appendText(
    ToolExecutionResult result,
    String text,
  ) {
    final content = [...result.content];
    final last = content.lastIndexWhere((b) => b is TextContent);
    if (last < 0) {
      content.add(TextContent(text));
    } else {
      content[last] = TextContent(
        '${(content[last] as TextContent).text}\n$text',
      );
    }
    return ToolExecutionResult(
      content,
      diffs: result.diffs,
      isError: result.isError,
    );
  }

  static (ToolExecutionResult, ToolOutcome) _error(
    String text,
    ToolOutcome outcome,
  ) => (ToolExecutionResult([TextContent(text)], isError: true), outcome);

  static (ToolExecutionResult, ToolOutcome, bool) _invalid(String text) {
    final (result, outcome) = _error(text, ToolOutcome.failed);
    return (result, outcome, true);
  }

  static (ToolExecutionResult, ToolOutcome, bool) _valid(
    (ToolExecutionResult, ToolOutcome) value,
  ) => (value.$1, value.$2, false);
}

const _dartPrefixes = ['Exception: ', 'Bad state: ', 'Invalid argument(s): '];

/// Текст исключения для модели без служебных префиксов Dart (§6.3.1, шаг 7).
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
