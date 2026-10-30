import '../agents/agent_definition.dart';
import '../cancel/cancel_token.dart';
import '../commands/slash_command.dart';
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
  ///
  /// Смены конфигурации ([setModel], [setEffort], [setAgent], [setMode])
  /// выполняются строго по очереди вызовов на сессию: итог параллельных
  /// вызовов равен последовательному (последний вызов побеждает), а сбой
  /// одного не блокирует остальные. Результат — [ConfigChangeResult].
  Future<ConfigChangeResult> setModel(ModelId id);

  /// Пишет `config_change {optionId: "effort"}`; действует со следующего
  /// шага.
  Future<void> setEffort(ReasoningEffort effort);

  /// Команды шаблонов проекта и пользователя в байтовом порядке имён
  /// (design.md change `add-agent-project-files`, D7, D9).
  ///
  /// Список строится при открытии сессии и не меняется до её закрытия. ACP-
  /// адаптер публикует его как `available_commands_update`; инструменты
  /// модели в него не входят (R-07). Без порта файлов проекта список пуст.
  List<SlashCommand> get commands;

  /// Определения агентов со `scope` `session` и `both` в байтовом порядке имён
  /// (design.md change `add-agent-project-files`, D10, D11; R-15).
  ///
  /// Список строится при открытии сессии и не меняется до её закрытия. ACP-
  /// адаптер строит из него опцию `agent` (D12); пуст — опции нет. Без порта
  /// файлов проекта список пуст.
  List<AgentDefinition> get agents;

  /// Имя текущего агента; [defaultAgentName] (`default`) — профиль не выбран.
  String get agent;

  /// Выбирает агента [name] или возвращает `default` (D11).
  ///
  /// Имя вне [agents] и не `default` — [ArgumentError] до любых изменений
  /// (ACP-адаптер отвечает `-32602` сам, до вызова). Повторный выбор текущего
  /// агента ничего не делает. Закрытая сессия — [StateError].
  ///
  /// Что меняется (всё со следующего шага, идущий вызов инструмента и
  /// остальные вызовы его пакета не прерываются и проверяются прежним набором инструментов и режимом
  /// политики; в отличие от [setMode], который действует со следующего вызова):
  /// - системный промпт получает последней секцию `agent_profile`;
  /// - модель — из определения (`model_change`, как у [setModel]), иначе
  ///   возвращается база;
  /// - режим — из определения, но только если он не мягче режима конфигурации
  ///   сессии; иначе режим не меняется и пишется `agent.mode.not_applied`. При
  ///   смене режима эмитится [ModeChanged] (для `current_mode_update`);
  /// - схемы инструментов — только из списка `tools` определения, вызов вне
  ///   списка отклоняется без запроса разрешения (CFG-7).
  ///
  /// База — режим и модель на момент перехода из `default`; возврат к
  /// `default` и переход между агентами считаются от неё. Журнал получает
  /// `config_change {optionId: agent}` раньше своих `model_change` и
  /// `mode_change`. `extraDeniedTiers`, `permissions.deny`, критические
  /// шаблоны и PERM-11 выбор агента не меняет.
  Future<ConfigChangeResult> setAgent(String name);

  /// Запускает ход; второй вызов во время хода — [StateError] (LOOP-10).
  /// Возвращается после `TurnEnded` и записи журнала.
  Future<TurnResult> prompt(List<ContentBlock> content, {CancelToken? cancel});

  Future<void> cancel();

  /// Действует со следующего вызова инструмента; пишет `mode_change` и
  /// эмитит [ModeChanged].
  Future<ConfigChangeResult> setMode(ModeId mode);

  /// Заменяет MCP-серверы клиента (`origin: session`) на [servers] — повторный
  /// `session/load` открытой сессии с другим набором (design.md change
  /// `add-agent-mcp-client`, D11).
  ///
  /// Совпавшие по `name` и параметрам серверы остаются подключёнными,
  /// исчезнувшие закрываются, новые подключаются; серверы конфига
  /// (`CoreConfig.mcpServers`) не затрагиваются. Список проходит те же
  /// слияние и фильтр, что при `createSession` (D6): пустое и повторное имя,
  /// выключенная capability и чужой транспорт дают `mcp.server.skipped`.
  ///
  /// Без хода набор меняется до завершения возвращённого `Future`. Во время
  /// хода вызов возвращается сразу, а набор меняется после `TurnEnded`
  /// (последний вызов за ход побеждает): набор инструментов посреди хода не
  /// меняется (D6). Следующий [prompt] дожидается применения. Сбой
  /// подключения не бросается: он пишется в лог, как при `createSession`.
  /// Вызов на закрытой сессии — [StateError].
  Future<void> setMcpServers(List<McpServerConfig> servers);

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

/// Итог смены конфигурации сессии: что именно изменил вызов.
///
/// Почему: смены идут по очереди вызовов, а события [ModeChanged] приходят
/// потоком; без номера адаптер не может сказать, какому запросу клиента
/// принадлежит эхо, и вынужден держать одно общее поле на сессию (гонка при
/// параллельных запросах). Результат вызова и событие несут один [changeId].
///
/// Для чего: ACP-адаптер шлёт `current_mode_update` только если режим
/// изменился именно этим вызовом, и дожидается своего эха.
///
/// Как использовать: `final r = await session.setAgent(name);` — если
/// `r.mode != null`, событие `ModeChanged(changeId: r.changeId)` уже
/// опубликовано (оно публикуется до завершения вызова). Адаптер подписывается
/// на `events` заранее и ищет эхо по `changeId`; вызов без изменений режима
/// (`mode == null`) эха не даёт.
final class ConfigChangeResult {
  const ConfigChangeResult({required this.changeId, this.mode, this.model});

  /// Номер вызова на сессии (возрастает с 1); совпадает с
  /// [ModeChanged.changeId] события, которое вызвал этот вызов.
  final int changeId;

  /// Новый режим, если вызов его изменил (и эмитил [ModeChanged]); иначе
  /// `null`. У `setMode` — всегда запрошенный режим.
  final ModeId? mode;

  /// Новая модель, если вызов записал `model_change`; иначе `null`.
  final ModelRef? model;
}
