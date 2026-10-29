import '../env/execution_env.dart';
import '../llm/model_catalog.dart';
import '../llm/model_ref.dart';
import '../loop/turn_budget.dart';
import '../mcp/mcp_connector.dart';
import '../mcp/mcp_server_config.dart';
import '../permissions/gate.dart';
import '../permissions/modes.dart';
import '../permissions/policy.dart';
import '../session/session_store.dart';
import '../util/clock.dart';
import '../util/ids.dart';
import '../util/logger.dart';

/// Всё внешнее, что хост передаёт ядру (`agent-core-architecture` §10.3).
///
/// Почему одним объектом: ядро не создаёт порты само (PKG-6), а сборка
/// проверяет, что у каждой включённой capability есть её сервис (HOST-3).
///
/// Как использовать: хост заполняет поля и передаёт объект в
/// `buildAgentCore`; следующие этапы добавляют сервисы.
final class AgentCoreServices {
  const AgentCoreServices({
    required this.baseEnv,
    required this.logger,
    required this.clock,
    required this.ids,
    required this.sessions,
    this.gate,
    this.platform = 'unknown',
    this.models,
    this.mcp,
  });

  /// Local | ACP client | memory (tests).
  final ExecutionEnv baseEnv;

  /// `null` → `interactiveApproval` is off.
  final PermissionGate? gate;
  final Logger logger;
  final Clock clock;
  final IdGenerator ids;

  /// Хранилище журналов (§8.3). Обязательно: журнал пишется всегда, а
  /// выключенная `sessionPersistence` означает лишь «не на постоянном
  /// носителе» (design.md этапа 3, D12).
  final SessionStore sessions;

  /// Платформа хоста для системного промпта (`linux`, `macos`, `windows`,
  /// `web`). Почему сервис: ядро web-безопасно и не читает
  /// `Platform.operatingSystem`, а модели полезно знать, какой shell и какие
  /// пути её ждут (§11.5). Хост на `dart:io` передаёт
  /// `Platform.operatingSystem`.
  final String platform;

  /// Каталог моделей для опции `model` и смены модели сессии (§2.12.2,
  /// §13.6). `null` — каталог из одной `CoreConfig.defaultModel`: тесты и
  /// хосты без конфига провайдеров (design.md change
  /// `add-dart-agent-acp-server`, D3).
  final ModelCatalog? models;

  /// Подключение MCP-серверов сессии (§10.3; design.md change
  /// `add-agent-mcp-client`, D3). `null` — capability `mcp` выключена с
  /// причиной «сервис MCP не передан»: серверы сессии пропускаются, сессия
  /// создаётся.
  final McpConnector? mcp;
}

/// The permissions part of the configuration.
final class PermissionsConfig {
  const PermissionsConfig({
    this.mode,
    this.modeOverride,
    this.rules = const PolicyRules(),
  });

  /// Replaces the default mode of the profile (§10.5).
  final ModeId? mode;

  /// `autopilot` and other launch-flag modes (design.md of
  /// `add-agent-core-permission-policy`, D3).
  final PermissionMode? modeOverride;
  final PolicyRules rules;
}

/// Проверенная конфигурация ядра.
///
/// Почему одно значение: сборка ядра (`buildAgentCore`) и все сессии
/// читают настройки из одного места, а хост собирает его из своих
/// источников. Чтение из файлов приходит на этапах 4 и 8 (design.md change
/// `add-agent-core-loop-and-tools`, D12).
///
/// Как использовать: хост создаёт значение и передаёт в `buildAgentCore`;
/// поля по умолчанию дают поведение без переопределений.
final class CoreConfig {
  const CoreConfig({
    required this.defaultModel,
    this.permissions = const PermissionsConfig(),
    this.budget = const TurnBudget(),
    this.compaction = const CompactionOverrides(),
    this.effort = ReasoningEffort.medium,
    this.mcpServers = const [],
  });

  final ModelRef defaultModel;

  /// Уровень рассуждения новой сессии (`agent.effort`, §2.12.3, §15.4);
  /// доходит до запроса только у модели с рассуждением.
  final ReasoningEffort effort;
  final PermissionsConfig permissions;
  final TurnBudget budget;

  /// Настройки сжатия контекста (§9.4, §15).
  final CompactionOverrides compaction;

  /// MCP-серверы конфигурации (`origin: config`); пусто, пока ключи
  /// `mcp.servers` не читаются из файлов (этап 8.5). Сервер клиента с тем же
  /// `name` заменяет сервер конфига (§13.4, шаг 2; D6).
  final List<McpServerConfig> mcpServers;
}

/// Переопределения порогов сжатия из конфигурации (`agent-core-architecture`
/// §9.4, ключи `compaction.*` §15; design.md change
/// `add-agent-core-sessions-and-compaction`, D8).
///
/// Почему переопределения, а не готовые числа: пороги зависят от окна
/// модели (`CompactionSettings.forWindow`), а модель сессии может меняться.
/// Заданное значение заменяет вычисленное и проходит те же ограничения
/// сверху `w/4` и `w/2`, поэтому настройка не делает порог отрицательным.
///
/// Как использовать: `null` в поле — значение из таблицы §9.4.
/// [contextWindowCap] ограничивает окно для порога, проверки перед запросом
/// и оценки в `ModelRequested` (CMP-6). `enabled: false` выключает
/// capability `compaction` при сборке ядра.
final class CompactionOverrides {
  const CompactionOverrides({
    this.reserveTokens,
    this.keepRecentTokens,
    this.keepRecentUserTurns,
    this.contextWindowCap,
    this.enabled = true,
  });

  final int? reserveTokens;
  final int? keepRecentTokens;
  final int? keepRecentUserTurns;
  final int? contextWindowCap;
  final bool enabled;
}
