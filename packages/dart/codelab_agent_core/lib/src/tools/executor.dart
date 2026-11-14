import 'dart:async';

import '../cancel/cancel_token.dart';
import '../env/execution_env.dart';
import '../llm/messages.dart';
import '../loop/agent_events.dart';
import '../loop/loop_config.dart';
import '../mcp/mcp_tool_name.dart';
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
/// затем [complete] (шаги 1a–10, `ToolCallFinished`) или [abandon] — для
/// вызова последовательного пакета, оставшегося после отмены, и для уже
/// объявленных вызовов параллельного пакета, если [announce] очередного
/// вызова упал (§17.16a.4 «Сбой `announce`»).
abstract interface class ToolExecutor {
  /// Шаг 1: занимает места в очередях пути и ключа и эмитит
  /// `ToolCallStarted`.
  ///
  /// При сбое (например, бросил подписчик `emit`) места освобождаются,
  /// для вызова best-effort эмитится `ToolCallFinished cancelled`, исходная
  /// ошибка пробрасывается; хэндл не возвращается, поэтому [complete] и
  /// [abandon] для этого вызова не нужны (§17.16a.4 «Сбой `announce`»).
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
    this._keyLock,
    this._lockPath,
    this._lockKeyName,
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

  /// Место в очереди ключа `AgentTool.lockKey`; `null` — ключа нет.
  final PathLockTicket? _keyLock;

  /// Путь очереди в виде для логов (относительно cwd); `null` — пути нет.
  final String? _lockPath;

  /// Ключ очереди `lockKey` для логов; `null` — ключа нет.
  final String? _lockKeyName;

  /// Освобождает оба места; повторный вызов безопасен.
  void _release() {
    _lock?.release();
    _keyLock?.release();
  }
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
    this.unavailableText,
  });

  final ToolRegistry registry;

  /// Причина, по которой инструмент реестра недоступен в этой сессии, или
  /// `null` — обычное «инструмента нет» (design.md change
  /// `add-agent-project-files`, D11, CFG-7).
  ///
  /// Почему здесь: набор агента сужает схемы шага, и вызов инструмента вне
  /// набора разрешается на шаге поиска инструмента — до `beforeToolCall`, как
  /// неизвестный инструмент. Тогда политика разрешений не спрашивает
  /// пользователя о вызове, который всё равно не исполнится.
  final String? Function(String toolName)? unavailableText;

  /// Ограниченный env сессии (ENV-2).
  final ExecutionEnv env;
  final ToolServices services;
  final _locks = PathLock();

  /// Очередь ключей `AgentTool.lockKey`; отдельная от путей, чтобы ключ
  /// `tasks` не пересекался с файлом с таким же именем.
  final _keyLocks = PathLock();

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
      onTerminal: (terminalId) => progress.add(
        Future.sync(
          () => invocation.emit(
            ToolCallProgress(
              invocation.sessionId,
              toolCallId: call.id,
              content: [ToolCallTerminal(terminalId)],
            ),
          ),
        ),
      ),
    );
    // Путь и ключ вычисляются ДО любого `reserve`: `lockPath`/`lockKey`
    // работают на сырых аргументах модели и могут бросить; тогда ни одно
    // место не занято и течь нечему (ошибка уходит из `announce` как есть —
    // так же, как и раньше для `lockPath`).
    final rawPath = tool?.lockPath(call.arguments);
    final lockKeyName = tool?.lockKey(call.arguments);
    // Место в очереди пути занимается здесь, в порядке ответа: хуки
    // разрешений разных вызовов могут ответить в любом порядке (TOOL-7).
    String? lockPath;
    final abs = rawPath == null ? null : normalizePath(env.cwd, rawPath);
    final lock = abs == null ? null : _locks.reserve(abs);
    if (abs != null) {
      // Абсолютный путь вне cwd в лог не пишем (AGENTS.md §16).
      lockPath = isInside(env.cwd, abs)
          ? relativeTo(env.cwd, abs)
          : '<outside cwd>';
    }
    // Ключ — по тому же принципу и в том же месте: порядок ответа модели
    // (обобщение TOOL-7 на ключи — исследование D39-alt, §17.16a.4).
    final keyLock = lockKeyName == null ? null : _keyLocks.reserve(lockKeyName);
    // После резервирования любой сбой `announce` (в том числе `emit`) обязан
    // освободить оба места: хэндл не вернётся, `complete`/`abandon` уже
    // никто не вызовет, и очередь пути/ключа осталась бы занятой до конца
    // сессии.
    try {
      return await _announceReserved(
        call,
        invocation,
        tool,
        context,
        progress,
        lock,
        keyLock,
        lockPath,
        lockKeyName,
      );
    } on Object {
      lock?.release();
      keyLock?.release();
      rethrow;
    }
  }

  Future<ToolCallHandle> _announceReserved(
    ToolCall call,
    ToolInvocation invocation,
    AgentTool? tool,
    ToolContext context,
    List<Future<void>> progress,
    PathLockTicket? lock,
    PathLockTicket? keyLock,
    String? lockPath,
    String? lockKeyName,
  ) async {
    var presentation = ToolPresentation(title: call.name);
    if (tool != null) {
      try {
        presentation = await tool.present(call.arguments, context);
        context.presentation = presentation;
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
    try {
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
    } on Object {
      // Хэндл не вернётся и `abandon` по нему не вызовут, а клиент мог уже
      // принять `Started`: best effort закрываем вызов `cancelled`, чтобы он
      // не висел в `in_progress`. В историю результат не попадает (как и у
      // `abandon` при сбое пакета); сбой этого эмита глотаем, исходную
      // ошибку пробрасываем.
      try {
        await invocation.emit(
          ToolCallFinished(
            invocation.sessionId,
            toolCallId: call.id,
            outcome: ToolOutcome.cancelled,
            content: const [TextContent(cancelledBeforeStartText)],
            diffs: const [],
          ),
        );
      } on Object {
        // исходная ошибка важнее
      }
      rethrow;
    }
    return ToolCallHandle._(
      call,
      invocation,
      tool,
      context,
      progress,
      lock,
      keyLock,
      lockPath,
      lockKeyName,
    );
  }

  @override
  Future<ToolExecutionOutcome> abandon(ToolCallHandle handle) {
    handle._release();
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
      handle._release();
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
      if (unavailableText?.call(call.name) case final text?) {
        return _invalid(text);
      }
      return _invalid(
        'Tool "${call.name}" is not available. '
        'Available tools: ${invocation.stepTools.join(', ')}.',
      );
    }
    final Map<String, Object?> args;
    try {
      switch (validateArguments(tool.parameters, call.arguments)) {
        case Ok(:final value):
          args = value;
        case Err(:final error):
          return _invalid(
            formatInvalidArguments(call.name, error, call.arguments),
          );
      }
    } on Object catch (error, stack) {
      services.logger.log(
        LogLevel.debug,
        'tool.validate.error',
        fields: {'tool': call.name, 'tool_call_id': call.id},
        error: error,
        stack: stack,
      );
      // Схема инструмента (в том числе MCP-сервера, недоверенного) не должна
      // ронять цикл: это сбой инструмента, а не неверный вызов модели, поэтому
      // он не считается в `MisuseBreaker` (TOOL-3).
      return _valid(_error(errorText(error), ToolOutcome.failed));
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
      await _acquire(handle, lock, {'path': handle._lockPath});
      if (invocation.cancel.isCancelled) {
        services.logger.log(
          LogLevel.debug,
          'tool.lock.cancelled',
          fields: {
            'tool': call.name,
            'tool_call_id': call.id,
            'session_id': invocation.sessionId.value,
            'path': handle._lockPath,
          },
        );
        return _valid(_error(cancelledText, ToolOutcome.cancelled));
      }
    }
    // Очередь ключа (обобщение TOOL-7 — исследование D39-alt, §17.16a.4;
    // принятый TOOL-7 — только пути): после пути. Отмена после захвата НЕ
    // проверяется: вызов, прошедший хук и проверку выше, «начал исполнение»
    // (D35 «Отмена»).
    // Операции под ключом короткие и атомарные, клиент уже видел
    // `in_progress` (хук `markInProgress`), а прерывание после ожидания
    // оставило бы модель без ясного ответа. Путь (`lockPath`, TOOL-7) —
    // иначе: там ожидание может быть долгим, и отмена после него честна.
    if (handle._keyLock case final keyLock?) {
      await _acquire(handle, keyLock, {'key': handle._lockKeyName});
    }
    return _valid(await _execute(handle, tool, args));
  }

  /// Ждёт захвата [ticket]; если очередь занята, пишет `tool.lock.wait` до
  /// ожидания и `tool.lock.acquired` с `waited_ms` после (AGENTS.md §16:
  /// зависший вызов виден по логу). В [where] — `path` или `key`; содержимое
  /// аргументов не логируется.
  Future<void> _acquire(
    ToolCallHandle handle,
    PathLockTicket ticket,
    Map<String, Object?> where,
  ) async {
    if (!ticket.queued) {
      await ticket.acquired;
      return;
    }
    final fields = {
      'tool': handle.call.name,
      'tool_call_id': handle.call.id,
      'session_id': handle.invocation.sessionId.value,
      ...where,
    };
    final since = services.clock.now();
    services.logger.log(LogLevel.debug, 'tool.lock.wait', fields: fields);
    await ticket.acquired;
    services.logger.log(
      LogLevel.debug,
      'tool.lock.acquired',
      fields: {
        ...fields,
        'waited_ms': services.clock.now().difference(since).inMilliseconds,
      },
    );
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
    // Защита в глубину (P-16, TOOL-10): результат любого инструмента с
    // именем `mcp__…` огораживается независимо от его `outputTrust` — сервер
    // MCP не может объявить себя доверенным (design.md change
    // `add-agent-mcp-client`, D7; `core/mcp-tool-cannot-declare-trusted`).
    if (tool.outputTrust(args) == ContentTrust.untrusted ||
        isMcpToolName(tool.name)) {
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
