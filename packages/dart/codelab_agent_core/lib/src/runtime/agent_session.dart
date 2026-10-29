import '../cancel/cancel_token.dart';
import '../env/execution_env.dart';
import '../llm/messages.dart';
import '../llm/model_catalog.dart';
import '../llm/model_ref.dart';
import '../llm/usage.dart';
import '../loop/agent_events.dart';
import '../loop/loop_config.dart';
import '../loop/turn_budget.dart';
import '../mcp/mcp_server_config.dart';
import '../permissions/gate.dart';
import '../permissions/modes.dart';
import '../util/logger.dart';

/// Публичный API сессии (`agent-core-architecture` §5.6).
///
/// Почему интерфейс: хосты и ACP-адаптер работают только через него, а
/// цикл, инструменты и журнал остаются внутренними (PKG-5).
///
/// Как использовать: сессию создаёт или открывает `AgentRuntime`; ходы
/// запускает [prompt], события читаются из [events]. С этапа 3 сессия пишет
/// журнал, [replay] отдаёт его события для `session/load`, а [close]
/// дожидается записи (design.md change `add-agent-core-sessions-and-
/// compaction`, D4). Следующие этапы добавляют члены, не меняя этих.
abstract interface class AgentSession {
  SessionId get id;

  /// Широковещательный поток; поздний подписчик получает события текущего
  /// хода с его начала.
  Stream<AgentEvent> get events;

  ModeId get mode;

  /// Модель, которой идёт следующий шаг: ACP-адаптер показывает её в опции
  /// `model` (§13.6; design.md change `add-dart-agent-acp-server`, D3).
  ModelRef get model;

  /// Уровень рассуждения сессии; хранится и у модели без рассуждения, но в
  /// запрос уходит только у модели с `supportsReasoning` (§2.12.3).
  ReasoningEffort get effort;

  /// Модель каталога; пишет `model_change` и действует со следующего шага,
  /// идущий запрос не прерывается. Модели нет в каталоге — [ArgumentError].
  Future<void> setModel(ModelId id);

  /// Пишет `config_change {optionId: "effort"}`; действует со следующего
  /// шага.
  Future<void> setEffort(ReasoningEffort effort);

  /// Запускает ход; второй вызов во время хода — [StateError] (LOOP-10).
  /// Возвращается после `TurnEnded` и записи журнала.
  Future<TurnResult> prompt(List<ContentBlock> content, {CancelToken? cancel});

  Future<void> cancel();

  /// Действует со следующего вызова инструмента; пишет `mode_change` и
  /// эмитит [ModeChanged].
  Future<void> setMode(ModeId mode);

  /// События журнала активной ветки для `session/load` (§8.3, D4).
  Iterable<AgentEvent> replay();

  /// Отменяет идущий ход, дожидается очереди записи журнала и закрывает
  /// поток событий; журнал остаётся в хранилище.
  Future<void> close();
}

/// The fields of `TurnEnded`.
final class TurnResult {
  const TurnResult({
    required this.reason,
    required this.usage,
    this.budgetExceeded,
    this.held,
  });

  final TurnEndReason reason;
  final Usage usage;
  final BudgetLimit? budgetExceeded;
  final String? held;
}

/// Ports of one session; each falls back to `AgentCoreServices`.
///
/// [extraBeforeToolCall] и [extraAfterToolCall] — хуки хоста загруженной
/// сессии с тем же правилом сборки, что у `SessionSpec` (§10.7): у
/// `loadSession` нет спецификации, а ACP-адаптеру нужен там свой
/// `markInProgress` (design.md change `add-dart-agent-acp-server`, D4).
final class SessionHostPorts {
  const SessionHostPorts({
    this.env,
    this.gate,
    this.logger,
    this.extraBeforeToolCall = const [],
    this.extraAfterToolCall = const [],
  });

  final ExecutionEnv? env;
  final PermissionGate? gate;
  final Logger? logger;

  /// Последними в `beforeToolCall`, после проверки разрешений.
  final List<BeforeToolCallHook> extraBeforeToolCall;

  /// Первыми в `afterToolCall`.
  final List<AfterToolCallHook> extraAfterToolCall;
}

final class SessionSpec {
  SessionSpec({
    required this.cwd,
    this.mode,
    this.model,
    this.ports = const SessionHostPorts(),
    List<BeforeToolCallHook> extraBeforeToolCall = const [],
    List<AfterToolCallHook> extraAfterToolCall = const [],
    List<McpServerConfig> mcpServers = const [],
  }) : extraBeforeToolCall = List.unmodifiable(extraBeforeToolCall),
       extraAfterToolCall = List.unmodifiable(extraAfterToolCall),
       mcpServers = List.unmodifiable(mcpServers);

  /// The absolute root of the session.
  final String cwd;

  /// `null` — the configuration, then the profile (§10.5).
  final ModeId? mode;

  /// `null` — the default model of the configuration.
  final ModelRef? model;
  final SessionHostPorts ports;

  /// Host hooks; they go last in `beforeToolCall` (§10.7, step 6).
  final List<BeforeToolCallHook> extraBeforeToolCall;

  /// Host hooks; they go first in `afterToolCall`.
  final List<AfterToolCallHook> extraAfterToolCall;

  /// MCP-серверы клиента (`origin: session`), в порядке запроса; сервер с тем
  /// же `name`, что в `CoreConfig.mcpServers`, заменяет серверы конфига
  /// (§13.4, шаг 2; design.md change `add-agent-mcp-client`, D6).
  final List<McpServerConfig> mcpServers;
}
