import '../env/execution_env.dart';
import '../llm/model_ref.dart';
import '../loop/turn_budget.dart';
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

/// The validated configuration of the core; loading from files arrives at
/// stages 4 and 8 (design.md, D12).
final class CoreConfig {
  const CoreConfig({
    required this.defaultModel,
    this.permissions = const PermissionsConfig(),
    this.budget = const TurnBudget(),
  });

  final ModelRef defaultModel;
  final PermissionsConfig permissions;
  final TurnBudget budget;
}
