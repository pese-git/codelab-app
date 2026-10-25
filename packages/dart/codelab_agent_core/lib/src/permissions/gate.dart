import '../cancel/cancel_token.dart';
import '../tools/agent_tool.dart';

/// The approval port (`agent-core-architecture` §7.2): the agent asks the
/// user through it. The ACP adapter implements it with
/// `session/request_permission` (stage 4); without a gate every question
/// is a denial (PERM-5).
abstract interface class PermissionGate {
  Future<PermissionDecision> request(PermissionRequest req, CancelToken cancel);
}

enum PermissionDecision {
  allowOnce,
  allowAlways,
  rejectOnce,
  rejectAlways,
  cancelled,
}

final class PermissionRequest {
  PermissionRequest({
    required this.toolCallId,
    required this.tool,
    required this.kind,
    required this.tier,
    required this.title,
    required Map<String, Object?> rawInput,
    List<Location> locations = const [],
    List<FileDiff> diffs = const [],
    this.pattern,
    this.reason,
    this.criticalLabel,
    this.allowAlwaysOffered = true,
  }) : rawInput = Map.unmodifiable(rawInput),
       locations = List.unmodifiable(locations),
       diffs = List.unmodifiable(diffs);

  final String toolCallId, tool, title;
  final ToolKind kind;
  final ToolTier tier;

  /// The coerced arguments that will be executed (PERM-6).
  final Map<String, Object?> rawInput;
  final List<Location> locations;

  /// One per changed file.
  final List<FileDiff> diffs;

  /// Шаблон «разрешить всегда» (`AgentTool.permissionPattern`, §7.5): им
  /// клиент называет варианты `allow_always` и `reject_always`, чтобы
  /// пользователь видел область решения (§13.9). `null` — без шаблона.
  final String? pattern;

  /// For example `critical command: recursive delete of a protected path`.
  final String? reason;

  /// Метка правила критической команды (§7.6), например
  /// `recursive delete of a protected path`; `null` — команда не
  /// критическая. ACP-адаптер ставит по ней `_meta.codelab.critical` (§7.8).
  final String? criticalLabel;

  /// `false` for critical patterns.
  final bool allowAlwaysOffered;
}
