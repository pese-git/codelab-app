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

  /// Пока не `null`, [append] ждёт его завершения до записи: тест удерживает
  /// запись и отпускает её сам (SES-16, CMP-12). Каждая запись берёт замок,
  /// действовавший на момент вызова.
  Future<void>? appendGate;

  /// Ограничивает [appendGate] записями, для которых вернулось `true`
  /// (`null` — замок на каждой записи).
  bool Function(SessionRecord record)? gateWhen;

  /// Сколько записей сейчас ждут [appendGate]: тест дожидается, что запись
  /// дошла до хранилища, не прибегая к таймерам.
  var waiting = 0;

  /// Сколько ближайших записей упадут (после [appendGate]) и перестанут
  /// падать сами: сбой одной записи в очереди писателя (SES-16).
  var failNextAppends = 0;

  @override
  Future<void> create(SessionHeader header) => inner.create(header);

  @override
  Future<String> createChild(SessionHeader header) => inner.createChild(header);

  @override
  Future<SessionSnapshot> openChild(
    String journal, {
    required SessionId rootSessionId,
  }) => inner.openChild(journal, rootSessionId: rootSessionId);

  @override
  Future<SessionSnapshot> openChildReadOnly(
    String journal, {
    required SessionId rootSessionId,
  }) => inner.openChildReadOnly(journal, rootSessionId: rootSessionId);

  @override
  Future<void> append(
    SessionId id,
    SessionRecord record, {
    bool durable = false,
  }) async {
    final gate = appendGate;
    if (gate != null && (gateWhen?.call(record) ?? true)) {
      waiting++;
      try {
        await gate;
      } finally {
        waiting--;
      }
    }
    if (failNextAppends > 0) {
      failNextAppends--;
      throw StateError('disk full');
    }
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
