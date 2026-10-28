import 'package:codelab_acp_protocol/codelab_acp_protocol.dart';

import '../diagnostics/diagnostics.dart';
import '../workspace/client_workspace.dart';
import '../workspace/workspace_state.dart';
import 'workspace_snapshot.dart';

/// Что рабочее пространство даёт [WorkspaceRestorer]; в публичный API kit не
/// входит.
///
/// Почему: восстановлению нужны операции, которых у хоста нет — добавить
/// сессии снимка в список и создать сессию с уведомлением; отдельный
/// интерфейс держит алгоритм вне `client_workspace.dart`.
abstract interface class RestoreHost {
  WorkspaceState get current;

  AgentCapabilities get capabilities;

  /// Добавляет [sessions] в список строками `notLoaded`, если их там нет.
  void rememberSessions(List<SessionRef> sessions);

  Future<SessionHandle> loadSession(SessionId id, {required String cwd});

  void activate(SessionId id);

  /// Создаёт сессию в [cwd], делает её активной и добавляет в её транскрипт
  /// уведомление `reconnected` с текстом [notice].
  Future<SessionHandle> newSessionWithNotice(String cwd, String notice);

  void report(WorkspaceDiagnostic diagnostic);
}

/// Восстановление рабочего пространства после перезапуска хоста и запись
/// снимка.
///
/// Почему: после перезапуска открытые сессии потеряны, хотя агент их
/// хранит; снимок позволяет вернуться к активной сессии с её транскриптом
/// (строка Must D-03 матрицы паритета; design D6 change
/// `add-session-list-and-reload`).
///
/// Для чего: шаг 1 — [readProject] при старте хоста; шаги 2–4 —
/// [restoreAfterConnect] при первом успешном подключении в запуске; запись
/// снимка — [observe] на каждое изменение `WorkspaceState`.
///
/// Как использовать: создаёт и вызывает `DefaultClientWorkspace`, если хост
/// передал `WorkspaceSnapshotStore`. Пока [readProject] не вызван, снимок не
/// пишется: иначе пустое рабочее пространство стёрло бы снимок прошлого
/// запуска до восстановления.
final class WorkspaceRestorer {
  WorkspaceRestorer(this._store, this._host);

  final WorkspaceSnapshotStore _store;
  final RestoreHost _host;

  /// Снимок прошлого запуска, ещё не восстановленный; `null` — восстанавливать
  /// нечего.
  WorkspaceSnapshot? _restoring;

  /// Сессии снимка, которые в этом запуске ещё не открыты: они остаются в
  /// снимке, пока пользователь их не откроет (ленивая загрузка, D6 шаг 2).
  final _pending = <SessionId, SessionRef>{};

  /// Проект, которому принадлежат [_restoring] и [_pending]; `null` — снимок
  /// без проекта или восстанавливать уже нечего.
  String? _snapshotProject;

  var _started = false;
  WorkspaceSnapshot? _written;
  WorkspaceSnapshot? _wanted;
  Future<void>? _writing;

  /// Шаг 1: читает снимок и возвращает его проект; битый снимок или
  /// неизвестная версия — диагностика, снимок удаляется.
  Future<String?> readProject() async {
    _started = true;
    final String? json;
    try {
      json = await _store.read();
    } on Object catch (error) {
      _warn('Failed to read workspace snapshot: ${describeFailure(error)}');
      return null;
    }
    if (json == null) {
      return null;
    }
    final WorkspaceSnapshot snapshot;
    try {
      snapshot = WorkspaceSnapshot.decode(json);
    } on FormatException {
      _warn('Workspace snapshot is invalid; starting fresh.');
      await _store.clear();
      return null;
    }
    _written = snapshot;
    _restoring = snapshot;
    _snapshotProject = snapshot.projectDirectory;
    for (final session in snapshot.openSessions) {
      _pending[session.id] = session;
    }
    return snapshot.projectDirectory;
  }

  /// Шаги 2–4 при первом успешном подключении: сессии снимка — в список,
  /// активная загружается; агент без `loadSession` или ошибка загрузки —
  /// новая сессия с уведомлением. Промпты и ответы на одобрения не
  /// отправляются. Повторный вызов — no-op.
  Future<void> restoreAfterConnect() async {
    final snapshot = _restoring;
    _restoring = null;
    if (snapshot == null) {
      return;
    }
    final project = snapshot.projectDirectory ?? _host.current.projectDirectory;
    final active = snapshot.activeSessionId;
    final canLoad = _host.capabilities.loadSession;
    if (canLoad) {
      _host.rememberSessions(snapshot.openSessions);
    } else {
      // Без `loadSession` сессии снимка не открыть ни сейчас, ни по выбору.
      _pending.clear();
    }
    if (active == null || project == null) {
      _observeCurrent();
      return;
    }
    final cwd =
        snapshot.openSessions.where((s) => s.id == active).firstOrNull?.cwd ??
        project;
    try {
      if (!canLoad) {
        await _host.newSessionWithNotice(
          project,
          'The agent cannot restore sessions; a new session was started.',
        );
      } else {
        try {
          await _host.loadSession(active, cwd: cwd);
          _host.activate(active);
        } on Object {
          _pending.remove(active);
          await _host.newSessionWithNotice(
            project,
            'Session ${active.value} could not be restored; '
            'a new session was started.',
          );
        }
      }
    } on Object catch (error) {
      _warn('Failed to restore the workspace: ${describeFailure(error)}');
    }
    _observeCurrent();
  }

  /// Записывает снимок для [state], если он изменился. Проект, отличный от
  /// проекта снимка, отменяет ещё не выполненное восстановление и убирает
  /// неоткрытые сессии снимка из следующей записи.
  void observe(WorkspaceState state) {
    if (!_started) {
      return;
    }
    // Пользователь перешёл в другой проект: сессии снимка принадлежат
    // прошлому, и восстанавливать их в новом проекте нельзя — иначе первое
    // подключение загрузило бы чужие сессии, а при неудаче создало бы
    // `session/new` в папке прошлого проекта.
    final project = state.projectDirectory;
    if (_snapshotProject != null &&
        project != null &&
        project != _snapshotProject) {
      _restoring = null;
      _pending.clear();
      _snapshotProject = null;
    }
    final opened = [
      for (final session in state.sessions)
        if (session.status != SessionStatusView.notLoaded)
          SessionRef(id: session.id, cwd: session.cwd),
    ];
    final openedIds = {for (final session in opened) session.id};
    final next = WorkspaceSnapshot(
      projectDirectory: state.projectDirectory ?? _restoring?.projectDirectory,
      activeSessionId: state.activeSessionId ?? _restoring?.activeSessionId,
      openSessions: [
        ...opened,
        for (final session in _pending.values)
          if (!openedIds.contains(session.id)) session,
      ],
    );
    if (next == (_wanted ?? _written)) {
      return;
    }
    _wanted = next;
    _writing ??= _drain();
  }

  /// Дожидается записи снимка, начатой или запрошенной до вызова.
  Future<void> flush() => _writing ?? Future<void>.value();

  void _observeCurrent() => observe(_host.current);

  /// Записи не накладываются: изменения во время записи склеиваются в одну
  /// следующую запись с последним снимком, а синхронная серия изменений — в
  /// одну запись (старт в следующей микрозадаче). Таймера нет: в тестах UI
  /// он оставался бы висеть, а последняя запись не ждёт паузы.
  Future<void> _drain() async {
    try {
      await Future<void>.value();
      while (true) {
        final next = _wanted;
        if (next == null) {
          break;
        }
        _wanted = null;
        if (next == _written) {
          continue;
        }
        try {
          await _store.write(next.encode());
        } on Object catch (error) {
          _warn('Failed to save workspace snapshot: ${describeFailure(error)}');
        }
        _written = next;
      }
    } finally {
      _writing = null;
    }
  }

  void _warn(String message) => _host.report(
    WorkspaceDiagnostic(
      severity: DiagnosticSeverity.warning,
      source: 'restore',
      message: message,
    ),
  );
}
