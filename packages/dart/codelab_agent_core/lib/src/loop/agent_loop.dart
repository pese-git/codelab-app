import '../cancel/cancel_token.dart';
import '../compaction/estimate.dart';
import '../llm/errors.dart';
import '../llm/event_stream.dart';
import '../llm/events.dart';
import '../llm/messages.dart';
import '../llm/stream_function.dart';
import '../llm/usage.dart';
import '../tools/agent_tool.dart';
import '../tools/executor.dart';
import '../tools/misuse.dart';
import '../util/logger.dart';
import 'agent_events.dart';
import 'loop_config.dart';
import 'payload_builder.dart';
import 'turn_budget.dart';

const truncatedArgumentsText =
    'Tool call arguments were truncated because the response hit the output '
    'token limit. Retry with smaller arguments.';

/// Подсказка после пустого ответа модели (§5.4.1).
const emptyResponseNudge =
    'Your previous response was empty. Continue the task: call a tool or '
    'answer the user with text.';

/// Заметка, которой ход останавливается после исчерпания повторов пустого
/// ответа (§5.4.1).
String emptyResponseNote(int attempts) =>
    '[Stopped: the model returned an empty response (attempts: $attempts). '
    'Send a message to continue.]';

/// Один ход агента (`agent-core-architecture` §5.4).
///
/// Почему чистая функция: ход не знает ни хранилища, ни протокола (LOOP-6)
/// — его одинаково исполняют `Agent` в сессии, тесты на scripted-модели и
/// (после MVP) субагенты. Состояние между ходами держит вызывающий.
///
/// Для чего: вызвать модель, исполнить вызовы инструментов её ответа и
/// повторять, пока она зовёт инструменты или приходит новый ввод (steering,
/// follow-up, подсказка пустого ответа, заметка `Revise`). Бюджет хода
/// проверяется только на границе шага (LOOP-12).
///
/// Как использовать: передать новые сообщения [prompts], контекст (история,
/// системный промпт, инструменты), конфигурацию и приёмник событий. Функция
/// возвращает [TurnOutput]: сообщения хода и, после аварийного сжатия,
/// новую историю. [TurnEnded] — всегда последнее событие, ровно одно, в
/// том числе при исключении в хуке (LOOP-1); каждый [emit] ждётся (LOOP-2).
Future<TurnOutput> runAgentLoop({
  required List<Message> prompts,
  required LoopContext context,
  required AgentLoopConfig config,
  required AgentEventSink emit,
  required CancelToken cancel,
}) => _Turn(context, config, emit, cancel).run(prompts);

/// Итог хода для владельца транскрипта.
///
/// Почему не просто список: аварийное сжатие (§5.4, шаг 14a) заменяет
/// историю посреди хода, и транскрипт после хода — это [history] плюс
/// [added], а не старая история плюс все сообщения хода (LOOP-7).
final class TurnOutput {
  TurnOutput({required List<Message> added, List<Message>? history})
    : added = List.unmodifiable(added),
      history = history == null ? null : List.unmodifiable(history);

  /// Сообщения, добавленные после [history] (без сжатия — весь ход).
  final List<Message> added;

  /// История, которой аварийное сжатие заменило транскрипт; `null` — не
  /// заменялась.
  final List<Message>? history;
}

/// Текст синтетического ответа, когда payload больше окна, а сжатие не
/// помогло или его нет (§5.2, шаг 4).
const contextExhaustedText = 'context window exhausted';

final class _Turn {
  _Turn(this._context, this._config, this._emit, this._cancel)
    : _transcript = [..._context.messages],
      _misuse = MisuseBreaker(_config.misuse),
      _startedAt = _config.clock.now(),
      _waitAtStart = _config.approvalWait?.total ?? Duration.zero {
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

  /// Один предохранитель на ход (§5.5, шаг 0; LOOP-16).
  final MisuseBreaker _misuse;
  final DateTime _startedAt;

  /// Ожидание одобрения до начала хода: время хода считается по приросту.
  final Duration _waitAtStart;
  late final TurnId _turnId;
  var _step = 0;
  var _usage = Usage.zero;
  var _steeringSteps = 0;

  /// Аварийное сжатие уже было в этом ходе (CMP-8).
  var _emergencyUsed = false;

  /// История после аварийного сжатия и позиция в [_added], с которой идут
  /// сообщения после неё.
  List<Message>? _history;
  var _historyFrom = 0;

  SessionId get _session => _config.sessionId;

  Future<TurnOutput> run(List<Message> prompts) async {
    TurnEndReason? reason;
    BudgetLimit? exceeded;
    String? held;
    AssistantMessage? last;
    try {
      _turnId = TurnId(_config.ids.nextId());
      await _emit(TurnStarted(_session, turnId: _turnId, input: prompts));
      for (final prompt in prompts) {
        await _append(prompt);
      }
      var pending = false;
      var newInput = prompts.isNotEmpty;
      var emptyStreak = 0;
      var revisions = 0;
      UserMessage? reviseNote;
      if (await _pollSteering()) {
        newInput = true;
      }
      while (true) {
        if (!pending && !newInput) {
          // Естественная остановка: follow-up, затем последний опрос
          // steering; без ввода ход запечатан.
          if (_config.followUp?.takeOne() case final message?) {
            await _append(message);
            newInput = true;
          } else if (await _pollSteering()) {
            newInput = true;
          }
          if (!newInput) {
            break;
          }
        }
        pending = false;
        newInput = false;
        if (_budgetExceeded() case final limit?) {
          exceeded = limit;
          reason = TurnEndReason.completed;
          break;
        }
        if (_cancel.isCancelled) {
          reason = _cancelledReason;
          break;
        }
        await _emit(StepStarted(_session, stepIndex: _step));
        final response = await _request(reviseNote);
        reviseNote = null;
        _usage += response.usage;
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
                stepIndex: _step,
                response: response,
                results: const [],
                usage: response.usage,
              ),
            ),
          );
          reason = _failureReason(response);
          break;
        }
        final empty = isEmptyCompletion(response);
        if (!empty) {
          emptyStreak = 0;
        }
        final calls = response.toolCalls.toList();
        final results = response.stopReason == StopReason.length
            ? [for (final call in calls) _truncatedArguments(call)]
            : await _runBatch(calls);
        for (final result in results) {
          await _append(result);
        }
        final stepResult = StepResult(
          stepIndex: _step,
          response: response,
          results: results,
          usage: response.usage,
        );
        await _emit(StepEnded(_session, result: stepResult));
        _step++;
        pending = calls.isNotEmpty;
        if (!pending && empty) {
          // Пустой ответ (§5.4.1): подсказка и ещё шаг или видимая заметка;
          // финальный гейт его не оценивает.
          _log(LogLevel.warning, 'loop.empty_response', {
            'attempt': emptyStreak + 1,
            'model': response.model.id,
            'stepIndex': stepResult.stepIndex,
          });
          if (emptyStreak < _config.emptyResponseRetries) {
            emptyStreak++;
            await _appendNudge(emptyStreak);
            pending = true;
          } else {
            await _appendEmptyNote(emptyStreak + 1);
            emptyStreak = 0;
          }
        } else if (!pending) {
          final verdict = switch (_config.beforeFinalResponse) {
            final hook? => await hook(
              response,
              TurnInfo(
                turnId: _turnId,
                stepIndex: stepResult.stepIndex,
                revisions: revisions,
                model: _config.model,
                usage: _usage,
                turnMessages: _added,
              ),
            ),
            null => const Accept(),
          };
          switch (verdict) {
            case Revise(:final note)
                when revisions < _config.maxResponseRevisions:
              revisions++;
              reviseNote = UserMessage([
                TextContent(note),
              ], timestamp: _config.clock.now());
              pending = true;
            case Hold(:final reason):
              held = reason;
            case Accept() || Revise():
              break;
          }
        }
        if (_config.prepareNextStep case final hook?) {
          if (await hook(stepResult) case final update?) {
            _apply(update);
          }
        }
        if (_cancel.isCancelled) {
          reason = _cancelledReason;
          break;
        }
        if (await _pollSteering()) {
          newInput = true;
        }
      }
      reason ??= last?.stopReason == StopReason.length
          ? TurnEndReason.maxTokens
          : TurnEndReason.completed;
    } on Object catch (error) {
      reason = TurnEndReason.failed;
      exceeded = null;
      held = null;
      try {
        await _emit(
          AgentError(
            _session,
            cls: AgentErrorClass.hook,
            message: errorText(error),
          ),
        );
      } on Object {
        // Ход всё равно закончится TurnEnded ниже (LOOP-1).
      }
    }
    await _emit(
      TurnEnded(
        _session,
        reason: reason,
        usage: _usage,
        budgetExceeded: exceeded,
        held: held,
      ),
    );
    return TurnOutput(added: _added.sublist(_historyFrom), history: _history);
  }

  /// Лимит бюджета, исчерпанный к границе шага, или `null` (LOOP-12).
  /// Время ожидания одобрения из времени хода вычитается (design.md, D6).
  BudgetLimit? _budgetExceeded() {
    final budget = _config.budget;
    if (_step >= budget.maxSteps) {
      return BudgetLimit.steps;
    }
    if (budget.maxTokens case final max?
        when _usage.input + _usage.output >= max) {
      return BudgetLimit.tokens;
    }
    if (budget.maxCost case final max?
        when _config.model.cost != null && _usage.cost.total >= max) {
      return BudgetLimit.cost;
    }
    if (budget.maxDuration case final max?) {
      final waited =
          (_config.approvalWait?.total ?? Duration.zero) - _waitAtStart;
      final elapsed = _config.clock.now().difference(_startedAt) - waited;
      if (elapsed >= max) {
        return BudgetLimit.duration;
      }
    }
    return null;
  }

  /// Забирает всю очередь steering одним опросом, если следующий шаг
  /// начнётся: ход не отменён, бюджет не исчерпан, лимит шагов steering не
  /// достигнут (LOOP-8). Возвращает, был ли новый ввод.
  Future<bool> _pollSteering() async {
    final queue = _config.steering;
    if (queue == null ||
        queue.isEmpty ||
        _steeringSteps >= _config.maxSteeringSteps ||
        _cancel.isCancelled ||
        _budgetExceeded() != null) {
      return false;
    }
    _steeringSteps++;
    for (final item in queue.takeAll()) {
      await _append(item.message, origin: item.origin);
    }
    return true;
  }

  Future<void> _appendNudge(int attempt) => _append(
    UserMessage([
      const TextContent(emptyResponseNudge),
    ], timestamp: _config.clock.now()),
    origin: LoopNudgeOrigin(LoopNudgeReason.emptyResponse, attempt),
  );

  /// Заметка — не шаг: без `StepStarted`, бюджет не тратит. Приходит как
  /// обычный текст ответа, чтобы клиент показал её без особой проекции.
  Future<void> _appendEmptyNote(int attempts) async {
    final text = emptyResponseNote(attempts);
    AssistantMessage note(List<ContentBlock> content) => AssistantMessage(
      content: content,
      model: _config.model,
      usage: Usage.zero,
      stopReason: StopReason.stop,
      timestamp: _config.clock.now(),
    );
    final partial = note(const []);
    final full = note([TextContent(text)]);
    _transcript.add(full);
    _added.add(full);
    await _emit(
      MessageStarted(
        _session,
        message: partial,
        origin: const LoopNoteOrigin(LoopNudgeReason.emptyResponse),
      ),
    );
    await _emit(MessageDelta(_session, delta: text, partial: full));
    await _emit(MessageEnded(_session, message: full));
    _log(LogLevel.warning, 'loop.empty_response.stopped', {
      'attempts': attempts,
    });
  }

  void _log(LogLevel level, String event, Map<String, Object?> fields) =>
      _config.logger?.log(level, event, fields: fields);

  Future<void> _append(Message message, {MessageOrigin? origin}) async {
    _transcript.add(message);
    _added.add(message);
    await _emit(MessageStarted(_session, message: message, origin: origin));
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

  /// Один запрос к модели; 400 из-за парности повторяется один раз с
  /// пересобранным payload (§5.4, шаг 14; design.md, D8). [note] — заметка
  /// `Revise`, она уходит только в payload.
  Future<AssistantMessage> _request(UserMessage? note) async {
    var retried = false;
    while (true) {
      final payload = await buildPayload(
        _transcript,
        cancel: _cancel,
        transform: _config.transformContext,
        note: note,
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
      final estimated = _config.estimateTokens?.call(context) ?? 0;
      final window = effectiveContextWindow(
        model,
        cap: _config.contextWindowCap,
      );
      // Шаг 4 §5.2: payload больше окна (не порога) — один аварийный
      // вызов и пересборка; иначе ответ overflow без обращения к провайдеру.
      if (_config.estimateTokens != null && estimated > window) {
        if (await _compactEmergency(EmergencyCause.preflight)) {
          continue;
        }
        return _exhausted();
      }
      await _emit(
        ModelRequested(
          _session,
          model: model,
          estimatedTokens: estimated,
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
      // Шаг 14a §5.4: overflow — сжатие и повтор того же шага; ответ с
      // ошибкой, после которого был повтор, в транскрипт не входит.
      if (!started &&
          response.errorClass == LlmErrorClass.overflow &&
          await _compactEmergency(EmergencyCause.overflow)) {
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

  /// Один аварийный вызов за ход (CMP-8): новый контекст заменяет
  /// транскрипт хода. `false` — вызова нет, он уже был или сжатие не
  /// помогло.
  Future<bool> _compactEmergency(EmergencyCause cause) async {
    final hook = _config.emergencyCompact;
    if (hook == null || _emergencyUsed) {
      return false;
    }
    _emergencyUsed = true;
    final LoopContext? context;
    try {
      context = await hook(cause, _cancel);
    } on CancelledException {
      return false;
    }
    if (context == null) {
      return false;
    }
    _context = context;
    _transcript
      ..clear()
      ..addAll(context.messages);
    _history = context.messages;
    _historyFrom = _added.length;
    return true;
  }

  /// Синтетический ответ `overflow`: провайдер не вызывается (§5.2, шаг 4).
  Future<AssistantMessage> _exhausted() async {
    final response = AssistantMessage(
      content: const [],
      model: _config.model,
      usage: Usage.zero,
      stopReason: StopReason.error,
      errorClass: LlmErrorClass.overflow,
      errorMessage: contextExhaustedText,
      timestamp: _config.clock.now(),
    );
    _transcript.add(response);
    _added.add(response);
    await _emit(MessageStarted(_session, message: response));
    await _emit(MessageEnded(_session, message: response));
    return response;
  }

  /// Читает ответ: первый блок кладёт снимок в транскрипт с
  /// `MessageStarted`, дельты текста и рассуждения становятся `MessageDelta`
  /// и `ThoughtDelta`. Возвращает итоговое сообщение и признак того, что
  /// `MessageStarted` уже эмитирован.
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

  /// Id вызовов уникальны во всём транскрипте (LOOP-11): повтор получает
  /// `_2`, `_3`… в первый же момент, когда вызов виден.
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
      misuse: _misuse,
      supportsImages: _config.model.supportsImages,
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

  /// Отмена причиной `StorageFailure` — сбой журнала, а не решение
  /// пользователя: ход завершается `failed` (SES-8).
  TurnEndReason get _cancelledReason => _cancel.reason is StorageFailure
      ? TurnEndReason.failed
      : TurnEndReason.cancelled;

  TurnEndReason _failureReason(AssistantMessage response) => switch ((
    response.stopReason,
    response.errorClass,
  )) {
    (StopReason.aborted, _) || (_, LlmErrorClass.aborted) => _cancelledReason,
    (_, LlmErrorClass.terminalFinish) => TurnEndReason.refused,
    _ => TurnEndReason.failed,
  };
}
