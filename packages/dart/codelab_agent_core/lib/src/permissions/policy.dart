import '../cancel/cancel_token.dart';
import '../loop/agent_events.dart' show ToolOutcome;
import '../loop/loop_config.dart';
import '../tools/agent_tool.dart';
import '../tools/builtin/common.dart' show pathPattern;
import 'critical_patterns.dart';
import '../util/logger.dart';
import 'gate.dart';
import 'modes.dart';
import 'pattern.dart';

/// Правила политики из конфигурации (§7.3).
final class PolicyRules {
  const PolicyRules({
    this.toolPolicies = const {},
    this.denyPatterns = const {},
  });

  /// `permissions.tools` конфигурации.
  final Map<String, ToolPolicy> toolPolicies;

  /// Явные запреты конфигурации.
  final Set<PermissionKey> denyPatterns;
}

sealed class PolicyOutcome {
  const PolicyOutcome();
}

final class Allowed extends PolicyOutcome {
  const Allowed(this.rule);

  final String rule;
}

final class Denied extends PolicyOutcome {
  const Denied(this.reason);

  final String reason;
}

/// Критический шаблон вызова (§7.6): метки через `; ` или `null`.
///
/// Почему функция, а не вызов напрямую: тесты политики подменяют её, чтобы
/// проверять порядок правил без разбора команд. [cwd] — корень сессии:
/// цели команды (`.codelab/config.yaml`) сравниваются относительно него.
typedef CriticalFinder =
    String? Function(AgentTool tool, Map<String, Object?> args, String cwd);

/// Критические шаблоны команды `exec` по таблице §7.6 (шаг 3 `decide`).
String? defaultCriticalFinder(
  AgentTool tool,
  Map<String, Object?> args,
  String cwd,
) => switch ((tool.name, args['command'])) {
  ('exec', final String command) => findCritical(command, cwd: cwd)?.label,
  _ => null,
};

/// Решает, можно ли исполнить вызов инструмента (§7.4).
///
/// Почему отдельный объект: ни один инструмент, зарегистрированный любым
/// способом, не исполняется без решения политики (PERM-1), а правила
/// (режим × уровень, «разрешить всегда», критические команды и пути) должны
/// быть одними для всех инструментов.
///
/// Как использовать: сборка ядра создаёт политику на сессию и ставит
/// [asHook] первым звеном `beforeToolCall`. Отказ — данные для модели, ход
/// продолжается (PERM-7); `AgentSession.prompt` вызывает [clearTurnGrants].
final class PermissionPolicy {
  PermissionPolicy({
    required this.mode,
    this.modeOverride,
    this.gate,
    this.rules = const PolicyRules(),
    PermissionDecisionStore? decisions,
    required this.logger,
    this.findCritical = defaultCriticalFinder,
  }) : decisions = decisions ?? PermissionDecisionStore();

  /// Режим сессии; смена действует со следующего вызова.
  ModeId mode;

  /// Перекрывает режим сессии (`autopilot` из флага запуска).
  final PermissionMode? modeOverride;
  final PermissionGate? gate;
  final PolicyRules rules;
  final PermissionDecisionStore decisions;
  final Logger logger;

  /// Критические шаблоны команд (§7.6).
  final CriticalFinder findCritical;

  final _turnAllow = <String>{};
  final _turnDeny = <String>{};

  PermissionMode get effectiveMode => modeOverride ?? mode.permissionMode;

  /// Разрешения и запреты по имени инструмента только на текущий ход.
  void grantForTurn({
    Set<String> allow = const {},
    Set<String> deny = const {},
  }) {
    _turnAllow.addAll(allow);
    _turnDeny.addAll(deny);
  }

  /// Вызывается в начале каждого `prompt()` (PERM-8).
  void clearTurnGrants() {
    _turnAllow.clear();
    _turnDeny.clear();
  }

  /// Хук политики для цепочки `beforeToolCall`; [lookup] находит
  /// инструмент вызова.
  BeforeToolCallHook asHook(
    AgentTool? Function(String name) lookup,
  ) => (call, args, ctx) async {
    final tool = lookup(call.name);
    if (tool == null) {
      return null;
    }
    return switch (await decide(tool, args, ctx)) {
      Allowed() => null,
      Denied(:final reason) => Block(
        'Permission denied for ${tool.name}: $reason. Do not retry the same '
        'call; choose another approach or ask the user.',
        // Ход отменён, пока шёл вопрос: вызов отменён до старта, а не
        // отклонён человеком (§13.7, «Статусы вызова»). Отказ `cancelled`
        // клиента без отмены хода остаётся `rejected` (PERM-7).
        outcome: ctx.cancel.isCancelled
            ? ToolOutcome.cancelled
            : ToolOutcome.rejected,
      ),
    };
  };

  Future<PolicyOutcome> decide(
    AgentTool tool,
    Map<String, Object?> args,
    ToolContext ctx,
  ) async {
    final outcome = await _decide(tool, args, ctx);
    if (outcome case Denied(:final reason)) {
      logger.log(
        LogLevel.info,
        'permission.denied',
        fields: {
          'tool_call_id': ctx.toolCallId,
          'tool': tool.name,
          'reason': reason,
        },
      );
    }
    return outcome;
  }

  Future<PolicyOutcome> _decide(
    AgentTool tool,
    Map<String, Object?> args,
    ToolContext ctx,
  ) async {
    final key = PermissionKey(
      tool.name,
      tool.permissionPattern(args, ctx.env.cwd),
    );
    final policy = rules.toolPolicies[tool.name];
    final tier = tool.tierOf(args);
    if (policy == ToolPolicy.deny || rules.denyPatterns.contains(key)) {
      return const Denied('denied by configuration');
    }
    if (decisions.rejectAlways.contains(key)) {
      return const Denied('previously rejected by the user');
    }
    if (_turnDeny.contains(tool.name)) {
      return const Denied('not allowed in this turn');
    }
    if (modeOverride == null && mode.deniedTiers.contains(tier)) {
      return const Denied('plan mode: changes are not allowed');
    }
    final effective = effectiveMode;
    // Критический путь правки (§7.6.1, PERM-11): конфигурацию агента меняет
    // только человек, «разрешить всегда» на неё не действует.
    if (_agentConfigTarget(tool, args, ctx.env.cwd) case final path?) {
      if (effective == PermissionMode.autopilot || gate == null) {
        return Denied('Editing agent configuration requires a human: $path');
      }
      return _ask(
        tool,
        args,
        ctx,
        key,
        reason: 'agent configuration: $path',
        allowAlways: false,
      );
    }
    if (findCritical(tool, args, ctx.env.cwd) case final label?) {
      if (effective == PermissionMode.autopilot) {
        return Denied('critical command blocked in autopilot: $label');
      }
      return _ask(
        tool,
        args,
        ctx,
        key,
        reason: 'critical command: $label',
        criticalLabel: label,
        allowAlways: false,
      );
    }
    switch (policy) {
      case ToolPolicy.allow:
        return const Allowed('tool policy');
      case ToolPolicy.ask:
        return _ask(tool, args, ctx, key);
      case ToolPolicy.deny || null:
        break;
    }
    if (_turnAllow.contains(tool.name)) {
      return const Allowed('turn grant');
    }
    if (decisions.allowAlways.contains(key)) {
      return const Allowed('always allowed');
    }
    return switch (tierDecision(effective, tier)) {
      TierDecision.allow => const Allowed('mode'),
      TierDecision.ask => _ask(tool, args, ctx, key),
      TierDecision.deny => const Denied(
        'network access needs approval and autopilot has no approver',
      ),
    };
  }

  /// Цель правки из списка §7.6.1 относительно корня сессии или `null`.
  /// Правку файла узнаём по `lockPath`: путь блокируют именно инструменты,
  /// которые меняют файл (`write`, `edit`).
  static String? _agentConfigTarget(
    AgentTool tool,
    Map<String, Object?> args,
    String cwd,
  ) {
    final raw = tool.lockPath(args);
    if (raw == null) {
      return null;
    }
    final relative = pathPattern(raw, cwd);
    return isAgentConfigPath(relative) ? relative : null;
  }

  Future<PolicyOutcome> _ask(
    AgentTool tool,
    Map<String, Object?> args,
    ToolContext ctx,
    PermissionKey key, {
    String? reason,
    String? criticalLabel,
    bool allowAlways = true,
  }) async {
    final gate = this.gate;
    if (gate == null) {
      return const Denied('no approval interface is available');
    }
    final offered = allowAlways && tool.offersAllowAlways(args);
    ToolPresentation presentation;
    try {
      presentation = await tool.present(args, ctx);
    } on Object {
      presentation = ToolPresentation(title: tool.name);
    }
    logger.log(
      LogLevel.debug,
      'permission.asked',
      fields: {
        'tool_call_id': ctx.toolCallId,
        'tool': tool.name,
        'tier': tool.tierOf(args).name,
        'critical': reason != null,
      },
    );
    final clock = ctx.services.clock;
    final started = clock.now();
    PermissionDecision decision;
    try {
      decision = await raceCancel(
        gate.request(
          PermissionRequest(
            toolCallId: ctx.toolCallId,
            tool: tool.name,
            kind: tool.kindOf(args),
            tier: tool.tierOf(args),
            title: presentation.title,
            rawInput: args,
            locations: presentation.locations,
            diffs: presentation.diffs,
            pattern: key.pattern,
            reason: reason,
            criticalLabel: criticalLabel,
            allowAlwaysOffered: offered,
          ),
          ctx.cancel,
        ),
        ctx.cancel,
      );
    } on CancelledException {
      decision = PermissionDecision.cancelled;
    } finally {
      ctx.services.approvalWait.add(clock.now().difference(started));
    }
    logger.log(
      LogLevel.debug,
      'permission.decided',
      fields: {'tool_call_id': ctx.toolCallId, 'decision': decision.name},
    );
    switch (decision) {
      case PermissionDecision.allowOnce:
        return const Allowed('user');
      case PermissionDecision.allowAlways:
        if (offered) {
          decisions.allowAlways.add(key);
        }
        return const Allowed('user');
      case PermissionDecision.rejectOnce:
        return const Denied('rejected by the user');
      case PermissionDecision.rejectAlways:
        decisions.rejectAlways.add(key);
        return const Denied('rejected by the user');
      case PermissionDecision.cancelled:
        return const Denied('permission request was cancelled');
    }
  }
}
