import 'package:codelab_agent_core/codelab_agent_core.dart';

/// [SessionStore] over [MemorySessionStore] that records appends and
/// flushes and can fail appends on demand.
final class RecordingStore implements SessionStore {
  RecordingStore([MemorySessionStore? inner])
    : inner = inner ?? MemorySessionStore();

  final MemorySessionStore inner;
  final appended = <({SessionRecord record, bool durable})>[];
  var flushes = 0;

  /// While `true`, [append] throws without writing.
  var failAppends = false;

  @override
  Future<void> create(SessionHeader header) => inner.create(header);

  @override
  Future<void> append(
    SessionId id,
    SessionRecord record, {
    bool durable = false,
  }) async {
    if (failAppends) {
      throw StateError('disk full');
    }
    await inner.append(id, record, durable: durable);
    appended.add((record: record, durable: durable));
  }

  @override
  Future<void> flush(SessionId id) async {
    flushes++;
    await inner.flush(id);
  }

  @override
  Future<SessionSnapshot> open(SessionId id) => inner.open(id);

  @override
  Future<SessionPage> list({String? cwd, String? cursor, int pageSize = 50}) =>
      inner.list(cwd: cwd, cursor: cursor, pageSize: pageSize);

  @override
  Future<void> close(SessionId id) => inner.close(id);
}
