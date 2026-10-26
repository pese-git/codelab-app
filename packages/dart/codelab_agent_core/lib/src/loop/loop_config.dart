import 'dart:async';
import 'dart:collection';

import '../cancel/cancel_token.dart';
import '../llm/messages.dart';
import '../llm/model_ref.dart';
import '../llm/stream_function.dart';
import '../llm/usage.dart';
import '../tools/agent_tool.dart';
import '../tools/executor.dart';
import '../tools/misuse.dart';
import '../util/clock.dart';
import '../util/ids.dart';
import '../util/logger.dart';
import 'agent_events.dart';
import 'turn_budget.dart';

/// Конфигурация и хуки хода (`agent-core-architecture` §5.2).

/// Приёмник событий хода; цикл ждёт каждый вызов (LOOP-2).
typedef AgentEventSink = FutureOr<void> Function(AgentEvent event);

/// Перед каждым запросом к модели; меняет только payload (LOOP-7).
typedef TransformContextHook =
    Future<List<Message>> Function(List<Message> messages, CancelToken cancel);

/// После валидации, до исполнения; первый [Block] останавливает цепочку.
/// Первым звеном всегда стоит проверка разрешений (PERM-1).
typedef BeforeToolCallHook =
    Future<Block?> Function(
      ToolCall call,
      Map<String, Object?> args,
      ToolContext ctx,
    );

/// После исполнения, до `ToolCallFinished`; переопределяет результат по
/// полям.
typedef AfterToolCallHook =
    Future<ResultOverride?> Function(
      ToolCall call,
      ToolExecutionResult result,
      bool isError,
    );

/// После `StepEnded`: заменить контекст или модель следующего шага.
typedef PrepareNextStepHook = Future<StepUpdate?> Function(StepResult step);

/// Финальный гейт ответа (LOOP-13): шаг закончился без вызовов, ход готов
/// остановиться. В MVP хук не регистрируется — поведение совпадает с
/// [Accept]; после MVP его собирает сессия из проверок (§17.12.4).
typedef BeforeFinalResponseHook =
    Future<ResponseVerdict> Function(AssistantMessage message, TurnInfo turn);

/// Оценка размера payload запроса в токенах (§9.3); цикл кладёт её в
/// `ModelRequested.estimatedTokens` и сравнивает с окном перед запросом.
typedef EstimateTokens = int Function(LlmContext context);

/// Что вызвало аварийное сжатие (§9.5).
enum EmergencyCause {
  /// Оценка payload больше окна — до обращения к провайдеру.
  preflight,

  /// Провайдер ответил `errorClass: overflow`.
  overflow,
}

/// Аварийное сжатие внутри хода (§5.2, шаг 4; §5.4, шаг 14a).
///
/// Возвращает новый контекст шага — сообщения проекции журнала после
/// сжатия — или `null`, если сжать нечего или сжатие не удалось. Цикл
/// вызывает его не больше одного раза за ход (CMP-8).
typedef EmergencyCompact =
    Future<LoopContext?> Function(EmergencyCause cause, CancelToken cancel);

final class Block {
  const Block(this.reason, {this.outcome = ToolOutcome.rejected});

  /// Текст результата-ошибки для модели.
  final String reason;
  final ToolOutcome outcome;
}

final class ResultOverride {
  const ResultOverride({this.content, this.isError});

  final List<ContentBlock>? content;
  final bool? isError;
}

final class StepUpdate {
  const StepUpdate({this.context, this.model});

  final LoopContext? context;
  final ModelRef? model;
}

final class StepResult {
  StepResult({
    required this.stepIndex,
    required this.response,
    required List<ToolResultMessage> results,
    required this.usage,
  }) : results = List.unmodifiable(results);

  final int stepIndex;
  final AssistantMessage response;

  /// В порядке вызовов [response].
  final List<ToolResultMessage> results;
  final Usage usage;
}

/// Решение финального гейта.
sealed class ResponseVerdict {
  const ResponseVerdict();
}

/// Ответ принят, ход завершается.
final class Accept extends ResponseVerdict {
  const Accept();
}

/// Ещё один шаг: [note] уходит модели последним `user`-сообщением payload и
/// не входит в транскрипт; не больше `maxResponseRevisions` раз за ход.
final class Revise extends ResponseVerdict {
  const Revise(this.note);

  final String note;
}

/// Ход завершается с ответом, помеченным `TurnEnded.held`.
final class Hold extends ResponseVerdict {
  const Hold(this.reason);

  final String reason;
}

/// Сведения о ходе для финального гейта (§17.12.4).
final class TurnInfo {
  TurnInfo({
    required this.turnId,
    required this.stepIndex,
    required this.revisions,
    required this.model,
    required this.usage,
    required List<Message> turnMessages,
  }) : turnMessages = List.unmodifiable(turnMessages);

  final TurnId turnId;

  /// Шаг, давший ответ-кандидат.
  final int stepIndex;

  /// Сколько `Revise` уже было в этом ходе.
  final int revisions;
  final ModelRef model;

  /// Расход хода на момент проверки.
  final Usage usage;

  /// Сообщения хода, включая кандидата.
  final List<Message> turnMessages;
}

/// Очередь сообщений, которую цикл опрашивает на границах шагов (§5.2).
///
/// Почему интерфейс: очередь наполняет `Agent` (а после MVP — субагенты и
/// пользовательский steering со своими правилами приёма, §17.7), а цикл
/// только забирает из неё.
abstract interface class MessageQueue<T> {
  bool get isEmpty;
  int get length;
  void add(T item);

  /// Одно сообщение на точку опроса (follow-up); `null` — пусто.
  T? takeOne();

  /// Все элементы в порядке FIFO за один опрос (steering).
  List<T> takeAll();
}

/// [MessageQueue] в памяти — очереди `Agent`.
final class ListMessageQueue<T> implements MessageQueue<T> {
  final _items = Queue<T>();

  @override
  bool get isEmpty => _items.isEmpty;

  @override
  int get length => _items.length;

  @override
  void add(T item) => _items.add(item);

  @override
  T? takeOne() => _items.isEmpty ? null : _items.removeFirst();

  @override
  List<T> takeAll() {
    final all = _items.toList();
    _items.clear();
    return all;
  }
}

/// Сообщение steering: корректировка текущей работы на ближайшей границе
/// шага (§5.6). [origin] — кто его написал, если не человек (после MVP —
/// уведомления субагентов, §17.3.8).
final class SteeringItem {
  const SteeringItem(this.message, {this.origin});

  final Message message;
  final MessageOrigin? origin;
}

final class LoopContext {
  LoopContext({
    required this.systemPrompt,
    required List<Message> messages,
    required List<AgentTool> tools,
  }) : messages = List.unmodifiable(messages),
       tools = List.unmodifiable(tools);

  final String systemPrompt;
  final List<Message> messages;

  /// Схемы шага — `tools.map(toSchema)`.
  final List<AgentTool> tools;
}

/// Всё, что нужно функции хода, кроме контекста и токена отмены.
///
/// Как использовать: `Agent` и тесты собирают значение один раз и меняют
/// его между ходами через [copyWith] (модель, очереди). Поля этапа 3 и
/// после MVP добавляются как необязательные (design.md, D7).
final class AgentLoopConfig {
  AgentLoopConfig({
    required this.sessionId,
    required this.model,
    required this.stream,
    required this.executor,
    required this.clock,
    required this.ids,
    this.budget = const TurnBudget(),
    this.transformContext,
    List<BeforeToolCallHook> beforeToolCall = const [],
    List<AfterToolCallHook> afterToolCall = const [],
    this.prepareNextStep,
    this.beforeFinalResponse,
    this.maxResponseRevisions = 2,
    this.maxSteeringSteps = 20,
    this.emptyResponseRetries = 2,
    this.misuse = const MisuseLimits(),
    this.steering,
    this.followUp,
    this.approvalWait,
    this.logger,
    this.estimateTokens,
    this.emergencyCompact,
    this.contextWindowCap,
  }) : beforeToolCall = List.unmodifiable(beforeToolCall),
       afterToolCall = List.unmodifiable(afterToolCall);

  final SessionId sessionId;
  final ModelRef model;
  final StreamFunction stream;

  /// Единая точка исполнения (§6.3.1).
  final ToolExecutor executor;
  final Clock clock;
  final IdGenerator ids;
  final TurnBudget budget;
  final TransformContextHook? transformContext;

  /// `[0]` — всегда проверка разрешений (PERM-1).
  final List<BeforeToolCallHook> beforeToolCall;
  final List<AfterToolCallHook> afterToolCall;
  final PrepareNextStepHook? prepareNextStep;

  /// `null` — ответ всегда принимается (MVP, LOOP-13).
  final BeforeFinalResponseHook? beforeFinalResponse;
  final int maxResponseRevisions;

  /// Сколько шагов за ход может добавить steering (LOOP-8).
  final int maxSteeringSteps;

  /// Повторы пустого ответа подряд (§5.4.1), `loop.empty_response_retries`.
  final int emptyResponseRetries;

  /// Предохранитель неверных вызовов (§6.3.7), `loop.misuse.*`.
  final MisuseLimits misuse;
  final MessageQueue<SteeringItem>? steering;
  final MessageQueue<Message>? followUp;

  /// Ожидание одобрения за ход: вычитается из времени хода для
  /// `maxDuration` (design.md, D6). Тот же счётчик, что у
  /// `ToolServices.approvalWait`; `null` — ожидание не учитывается.
  final ApprovalWaitMeter? approvalWait;

  /// Логи цикла (`loop.empty_response` и др., §5.4.1); `null` — без логов.
  final Logger? logger;

  /// Оценка payload (§9.3); `null` — размер не проверяется, а
  /// `ModelRequested.estimatedTokens` равен 0 (поведение этапа 2).
  final EstimateTokens? estimateTokens;

  /// Аварийное сжатие (design.md change
  /// `add-agent-core-sessions-and-compaction`, D8); `null` — `overflow`
  /// остаётся обычной ошибкой шага.
  final EmergencyCompact? emergencyCompact;

  /// Ограничение окна для проверки перед запросом:
  /// `effectiveContextWindow(model, cap)` (CMP-6).
  final int? contextWindowCap;

  AgentLoopConfig copyWith({
    ModelRef? model,
    MessageQueue<SteeringItem>? steering,
    MessageQueue<Message>? followUp,
  }) => AgentLoopConfig(
    sessionId: sessionId,
    model: model ?? this.model,
    stream: stream,
    executor: executor,
    clock: clock,
    ids: ids,
    budget: budget,
    transformContext: transformContext,
    beforeToolCall: beforeToolCall,
    afterToolCall: afterToolCall,
    prepareNextStep: prepareNextStep,
    beforeFinalResponse: beforeFinalResponse,
    maxResponseRevisions: maxResponseRevisions,
    maxSteeringSteps: maxSteeringSteps,
    emptyResponseRetries: emptyResponseRetries,
    misuse: misuse,
    steering: steering ?? this.steering,
    followUp: followUp ?? this.followUp,
    approvalWait: approvalWait,
    logger: logger,
    estimateTokens: estimateTokens,
    emergencyCompact: emergencyCompact,
    contextWindowCap: contextWindowCap,
  );
}
