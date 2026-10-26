import 'dart:convert';

import 'package:codelab_acp_protocol/codelab_acp_protocol.dart';
import 'package:freezed_annotation/freezed_annotation.dart';

part 'workspace_snapshot.freezed.dart';

/// Ссылка на открытую сессию в снимке: id и рабочая папка.
///
/// Для чего: этого хватает, чтобы после перезапуска загрузить сессию через
/// `session/load` (`03-Session Setup.md`, «Loading a Session»).
@freezed
abstract class SessionRef with _$SessionRef {
  const factory SessionRef({required SessionId id, required String cwd}) =
      _SessionRef;
}

/// Снимок рабочего пространства для восстановления после перезапуска хоста.
///
/// Почему: открытые сессии живут в памяти и теряются при перезапуске, а
/// агент хранит их у себя; чтобы вернуться к работе, хватает проекта,
/// активной сессии и списка открытых (design D6 change
/// `add-session-list-and-reload`).
///
/// Для чего: содержимое [WorkspaceSnapshotStore]. Курсоров `session/list`
/// (ACP запрещает их сохранять), транскриптов (их отдаёт реплей агента),
/// очередей, профилей и секретов в снимке нет.
///
/// Как использовать: kit сам кодирует ([encode]) и разбирает ([decode])
/// снимок; хранилище видит только строку JSON
/// `{"version": 1, "windows": {"main": {…}}}`. Ключ `windows` — по окну
/// хоста; сейчас окно одно.
@freezed
abstract class WorkspaceSnapshot with _$WorkspaceSnapshot {
  const WorkspaceSnapshot._();

  const factory WorkspaceSnapshot({
    String? projectDirectory,
    SessionId? activeSessionId,
    @Default([]) List<SessionRef> openSessions,
  }) = _WorkspaceSnapshot;

  /// Версия формата; другая версия при чтении — битый снимок.
  static const version = 1;

  static const _window = 'main';

  String encode() => jsonEncode({
    'version': version,
    'windows': {
      _window: {
        'projectDirectory': ?projectDirectory,
        'activeSessionId': ?activeSessionId?.value,
        'openSessions': [
          for (final session in openSessions)
            {'id': session.id.value, 'cwd': session.cwd},
        ],
      },
    },
  });

  /// Разбирает [json]; битый JSON, другая версия или неверная форма —
  /// [FormatException].
  static WorkspaceSnapshot decode(String json) {
    final root = jsonDecode(json);
    if (root is! Map || root['version'] != version) {
      throw const FormatException('Unsupported workspace snapshot version.');
    }
    final windows = root['windows'];
    final window = windows is Map ? windows[_window] : null;
    if (window is! Map) {
      throw const FormatException('Workspace snapshot has no main window.');
    }
    final project = window['projectDirectory'];
    final active = window['activeSessionId'];
    final open = window['openSessions'] ?? const <Object?>[];
    if ((project != null && project is! String) ||
        (active != null && active is! String) ||
        open is! List) {
      throw const FormatException('Workspace snapshot is malformed.');
    }
    return WorkspaceSnapshot(
      projectDirectory: project as String?,
      activeSessionId: active == null ? null : SessionId(active as String),
      openSessions: [
        for (final session in open)
          if (session case {'id': final String id, 'cwd': final String cwd})
            SessionRef(id: SessionId(id), cwd: cwd)
          else
            throw const FormatException('Workspace snapshot is malformed.'),
      ],
    );
  }
}

/// Хранилище снимка рабочего пространства — порт kit.
///
/// Почему: где хранить снимок, решает хост: app — `shared_preferences`, CLI
/// снимок не читает (design D6).
///
/// Для чего: читать, писать и удалять одну строку JSON снимка; разбор и
/// версии — забота kit.
///
/// Как использовать: передать в `ClientWorkspace(snapshots: …)`. Ошибки
/// записи kit превращает в диагностику; `read` без снимка — `null`.
abstract interface class WorkspaceSnapshotStore {
  Future<String?> read();

  Future<void> write(String snapshot);

  Future<void> clear();
}

/// [WorkspaceSnapshotStore] в памяти — для тестов и хостов без постоянного
/// хранилища.
final class InMemoryWorkspaceSnapshotStore implements WorkspaceSnapshotStore {
  InMemoryWorkspaceSnapshotStore([this.value]);

  /// Сохранённый снимок; `null` — снимка нет.
  String? value;

  @override
  Future<String?> read() async => value;

  @override
  Future<void> write(String snapshot) async => value = snapshot;

  @override
  Future<void> clear() async => value = null;
}
