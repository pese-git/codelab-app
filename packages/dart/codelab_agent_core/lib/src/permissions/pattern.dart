/// The key of «allow always» (`agent-core-architecture` §7.5): a tool and a
/// pattern of its arguments, never a kind of tool (PERM-3).
final class PermissionKey {
  const PermissionKey(this.tool, this.pattern);

  final String tool, pattern;

  @override
  bool operator ==(Object other) =>
      other is PermissionKey && other.tool == tool && other.pattern == pattern;

  @override
  int get hashCode => Object.hash(tool, pattern);

  @override
  String toString() => 'PermissionKey($tool, $pattern)';
}

/// «Always» decisions of a session, in memory until it closes.
final class PermissionDecisionStore {
  final allowAlways = <PermissionKey>{};
  final rejectAlways = <PermissionKey>{};
}
