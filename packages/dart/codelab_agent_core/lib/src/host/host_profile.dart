import '../permissions/modes.dart';

/// Capabilities and profiles of hosts (`agent-core-architecture` §10.2,
/// §10.4). Значения появляются вместе с подсистемами: три — этап 2,
/// `compaction` и `sessionPersistence` — этап 3 (design.md change
/// `add-agent-core-sessions-and-compaction`, D12), `mcp` — этап 8.
enum HostCapability {
  shellExec,
  fileListing,
  interactiveApproval,

  /// Автоматическое и аварийное сжатие контекста (§9).
  compaction,

  /// Журнал на постоянном носителе, `session/load`, `session/list`.
  /// Выключенная — журнал в памяти (`MemorySessionStore`): тесты и хосты
  /// без носителя.
  sessionPersistence,

  /// Подключение MCP-серверов сессии (§10.2; design.md change
  /// `add-agent-mcp-client`, D3). Транспорты — `stdio` (процесс) и `http`
  /// (streamable HTTP); профиль без процессов сужается до `{http}`.
  mcp,
}

sealed class CapabilityState {
  const CapabilityState();
}

final class CapabilityOn extends CapabilityState {
  const CapabilityOn();
}

final class CapabilityOff extends CapabilityState {
  const CapabilityOff(this.reason);

  final String reason;
}

final class CapabilityTransport extends CapabilityState {
  const CapabilityTransport(this.transports, this.reason);

  final Set<String> transports;

  /// Why exactly this set.
  final String reason;
}

/// A wiring mistake of the host — found at assembly, not during a turn.
final class HostWiringException implements Exception {
  const HostWiringException(this.message);

  final String message;

  @override
  String toString() => 'HostWiringException: $message';
}

final class HostProfile {
  HostProfile._(
    this.name,
    Map<HostCapability, CapabilityState> states,
    this.defaultMode,
  ) : states = Map.unmodifiable(states);

  /// The built-in profiles of §10.4; [ArgumentError] for an unknown name.
  factory HostProfile.of(String name) => switch (name) {
    'agent-serve' => HostProfile._(name, const {
      HostCapability.shellExec: CapabilityTransport({
        'acp-terminal',
        'local',
      }, 'клиент объявил terminal или задан флаг --local-exec'),
      HostCapability.fileListing: CapabilityTransport({
        'local',
      }, 'stdio-клиент всегда на той же машине'),
      HostCapability.interactiveApproval: CapabilityTransport({
        'acp',
      }, 'вопрос через session/request_permission'),
      HostCapability.compaction: CapabilityOn(),
      HostCapability.sessionPersistence: CapabilityTransport({
        'jsonl-file',
      }, 'журнал JSONL в \$CODELAB_HOME/sessions'),
      HostCapability.mcp: CapabilityTransport({
        'stdio',
        'http',
      }, 'серверы MCP: процесс клиента и streamable HTTP'),
    }, ModeId.standard),
    'embedded-cli' => HostProfile._(name, const {
      HostCapability.shellExec: CapabilityTransport({
        'local',
      }, 'процессы хоста'),
      HostCapability.fileListing: CapabilityTransport({'local'}, 'файлы хоста'),
      HostCapability.interactiveApproval: CapabilityTransport({
        'acp',
      }, 'вопрос через встроенный ACP-клиент'),
      HostCapability.compaction: CapabilityOn(),
      HostCapability.sessionPersistence: CapabilityTransport({
        'jsonl-file',
      }, 'журнал JSONL в \$CODELAB_HOME/sessions'),
      HostCapability.mcp: CapabilityTransport({
        'stdio',
        'http',
      }, 'серверы MCP: процессы хоста и streamable HTTP'),
    }, ModeId.standard),
    _ => throw ArgumentError.value(name, 'name', 'unknown host profile'),
  };

  final String name;

  /// An explicit state of every capability (HOST-1).
  final Map<HostCapability, CapabilityState> states;

  /// The mode of a new session (§10.5).
  final ModeId defaultMode;

  bool isOn(HostCapability capability) => states[capability] is! CapabilityOff;

  /// Only narrows (HOST-2): on → transport → off, and a transport to a
  /// subset of itself.
  HostProfile narrowed(Map<HostCapability, CapabilityState> overrides) {
    final next = {...states};
    for (final MapEntry(key: capability, value: state) in overrides.entries) {
      final current = states[capability]!;
      final allowed = switch ((current, state)) {
        (_, CapabilityOff()) => true,
        (CapabilityOn(), _) => true,
        (
          CapabilityTransport(transports: final a),
          CapabilityTransport(transports: final b),
        ) =>
          a.containsAll(b),
        _ => false,
      };
      if (!allowed) {
        throw HostWiringException(
          'capability ${capability.name}: нельзя расширить ${_describe(current)} '
          'до ${_describe(state)} в профиле $name',
        );
      }
      next[capability] = state;
    }
    return HostProfile._(name, next, defaultMode);
  }

  static String _describe(CapabilityState state) => switch (state) {
    CapabilityOn() => 'on',
    CapabilityOff() => 'off',
    CapabilityTransport(:final transports) =>
      '{${(transports.toList()..sort()).join(', ')}}',
  };
}
