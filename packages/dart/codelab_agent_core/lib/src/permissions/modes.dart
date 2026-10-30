import '../tools/agent_tool.dart';

/// Permission modes and tiers (`agent-core-architecture` §7.3).

/// The order of declaration is the order of softness (§7.3.1).
enum PermissionMode { alwaysAsk, write, acceptEdits, yolo, autopilot }

/// A per-tool rule of the configuration (`permissions.tools`).
enum ToolPolicy { allow, deny, ask }

enum TierDecision { allow, ask, deny }

/// The `mode × tier` table of §7.3; «ask» is a call of the gate.
TierDecision tierDecision(PermissionMode mode, ToolTier tier) => switch ((
  mode,
  tier,
)) {
  (PermissionMode.alwaysAsk, _) => TierDecision.ask,
  (_, ToolTier.read) => TierDecision.allow,
  (PermissionMode.autopilot, ToolTier.network) => TierDecision.deny,
  (_, ToolTier.network) => TierDecision.ask,
  (PermissionMode.write, _) => TierDecision.ask,
  (PermissionMode.acceptEdits, ToolTier.write) => TierDecision.allow,
  (PermissionMode.acceptEdits, _) => TierDecision.ask,
  (PermissionMode.yolo || PermissionMode.autopilot, _) => TierDecision.allow,
};

/// A mode of the session as the client sees it (§13.6). `autopilot` is not
/// a mode id: it is enabled only by a launch flag (CFG-4; design.md change
/// `add-agent-core-permission-policy`, D3).
extension type const ModeId._(String value) {
  static const plan = ModeId._('plan');
  static const ask = ModeId._('ask');
  static const standard = ModeId._('standard');
  static const acceptEdits = ModeId._('accept-edits');
  static const bypass = ModeId._('bypass');

  static const values = [plan, ask, standard, acceptEdits, bypass];

  /// Only the main ids; the ACP adapter normalizes synonyms (stage 4).
  static ModeId parse(String id) =>
      values.where((m) => m.value == id).firstOrNull ??
      (throw ArgumentError.value(id, 'id', 'unknown mode'));

  PermissionMode get permissionMode => switch (value) {
    'ask' => PermissionMode.alwaysAsk,
    'accept-edits' => PermissionMode.acceptEdits,
    'bypass' => PermissionMode.yolo,
    _ => PermissionMode.write,
  };

  /// Мягкость режима: чем больше, тем мягче (§7.3.1). `plan` строже всех:
  /// он запрещает запись и команды. Нужна для «пола» режима при выборе агента
  /// (design.md change `add-agent-project-files`, D11): определение агента не
  /// может сделать режим мягче режима конфигурации.
  ///
  /// Все пять идентификаторов перечислены явно, без ветки «по умолчанию»:
  /// неизвестный идентификатор не получает ранга (`null`) и не может
  /// оказаться «средним» по ошибке. Сравнивать нужно через [fitsFloor], где
  /// отсутствие ранга трактуется в сторону запрета (fail-closed).
  int? get softness {
    if (value == 'plan') {
      return 0;
    }
    if (value == 'ask') {
      return 1;
    }
    if (value == 'standard') {
      return 2;
    }
    if (value == 'accept-edits') {
      return 3;
    }
    if (value == 'bypass') {
      return 4;
    }
    return null;
  }

  /// Режим не мягче [floor] (D11, OQ3).
  ///
  /// Fail-closed: неизвестный кандидат не подходит никогда (он мог бы быть
  /// мягче чего угодно), а при неизвестном поле не подходит ни один режим.
  bool fitsFloor(ModeId floor) {
    final mine = softness;
    final limit = floor.softness;
    if (mine == null || limit == null) {
      return false;
    }
    return mine <= limit;
  }

  /// Tiers the mode forbids without asking: `plan` forbids changes.
  Set<ToolTier> get deniedTiers =>
      value == 'plan' ? const {ToolTier.write, ToolTier.exec} : const {};
}
