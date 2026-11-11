import 'dart:async';

import 'package:codelab_acp_protocol/codelab_acp_protocol.dart' show SessionId;
import 'package:codelab_client_core/codelab_client_core.dart';
import 'package:flutter_test/flutter_test.dart';

/// Сессия с заданной рабочей папкой; остальное тестам терминала не нужно.
final class FakeSessionHandle extends Fake implements SessionHandle {
  FakeSessionHandle(this.id, this.cwd);

  @override
  final SessionId id;

  @override
  final String cwd;
}

/// Двойник [ClientWorkspace] с управляемыми `current`, `state` и `session(id)`.
///
/// Почему: `TerminalTabsCubit` читает только активную сессию, профиль и
/// `SessionHandle.cwd` (D5); настоящее рабочее пространство требует транспорта.
///
/// Для чего: тест меняет состояние напрямую и видит реакцию Cubit.
///
/// Как использовать: [openSession] регистрирует сессию и делает её активной;
/// [emit] публикует произвольное `WorkspaceState` (например, разрыв
/// соединения или смену профиля при прежнем `activeSessionId`, как делает
/// настоящий `ClientWorkspace`, D5). Поток доставляется синхронно, как у
/// настоящего.
final class FakeClientWorkspace extends Fake implements ClientWorkspace {
  FakeClientWorkspace([WorkspaceState initial = const WorkspaceState()])
    : _current = initial;

  WorkspaceState _current;
  final StreamController<WorkspaceState> _state =
      StreamController<WorkspaceState>.broadcast(sync: true);
  final Map<SessionId, SessionHandle> _sessions = {};

  @override
  WorkspaceState get current => _current;

  @override
  Stream<WorkspaceState> get state => _state.stream;

  @override
  SessionHandle? session(SessionId id) => _sessions[id];

  /// Есть ли подписчики `state` (Cubit освобождает подписку на `close`).
  bool get hasStateListeners => _state.hasListener;

  /// Регистрирует сессию [id] с папкой [cwd], если она ещё не известна.
  void addSession(SessionId id, String cwd) =>
      _sessions[id] = FakeSessionHandle(id, cwd);

  /// Забывает сессию: `session(id)` вернёт `null`, `activeSessionId` остаётся.
  void removeSession(SessionId id) => _sessions.remove(id);

  void emit(WorkspaceState next) {
    _current = next;
    _state.add(next);
  }

  /// Делает [id] активной сессией профиля [profile] (папка сессии — [cwd]).
  void openSession(
    ConnectionProfile profile,
    SessionId id, {
    String cwd = '/work/a',
  }) {
    addSession(id, cwd);
    emit(_current.copyWith(profile: profile, activeSessionId: id));
  }

  Future<void> close() => _state.close();
}
