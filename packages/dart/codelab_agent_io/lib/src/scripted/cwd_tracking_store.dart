import 'package:codelab_agent_core/codelab_agent_core.dart';

/// Журнал сценария, который помнит рабочую папку каждой сессии.
///
/// Почему: шаги `--llm-script` общие для сессий процесса, а `${cwd}` —
/// папка сессии запроса (D3 change `add-codelab-agent-binary`). Сценарий
/// узнаёт её по id сессии (`LlmContext.cacheKey`) через [cwdOf]. Папка
/// запоминается и при [open]: сессию, загруженную `session/load` после
/// перезапуска процесса, никто не создаёт заново (D2 change
/// `add-llm-script-session-store`).
///
/// Как использовать: хост оборачивает хранилище сценария —
/// `CwdTrackingStore(MemorySessionStore())` без `--sessions-dir`,
/// `CwdTrackingStore(JsonlSessionStore(...))` с ним — и передаёт [cwdOf] в
/// `LlmScript.load`.
final class CwdTrackingStore implements SessionStore {
  CwdTrackingStore(this._inner);

  final SessionStore _inner;
  final _cwd = <String, String>{};

  String? cwdOf(String sessionId) => _cwd[sessionId];

  @override
  Future<void> create(SessionHeader header) {
    _cwd[header.id.value] = header.cwd;
    return _inner.create(header);
  }

  @override
  Future<void> append(
    SessionId id,
    SessionRecord record, {
    bool durable = false,
  }) => _inner.append(id, record, durable: durable);

  @override
  Future<void> flush(SessionId id) => _inner.flush(id);

  @override
  Future<SessionSnapshot> open(SessionId id) async {
    final snapshot = await _inner.open(id);
    _cwd[snapshot.header.id.value] = snapshot.header.cwd;
    return snapshot;
  }

  @override
  Future<SessionPage> list({String? cwd, String? cursor, int pageSize = 50}) =>
      _inner.list(cwd: cwd, cursor: cursor, pageSize: pageSize);

  @override
  Future<void> close(SessionId id) => _inner.close(id);
}
