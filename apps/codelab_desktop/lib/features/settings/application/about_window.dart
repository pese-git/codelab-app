import 'package:codelab_client_core/codelab_client_core.dart'
    show
        Connected,
        Connecting,
        ConnectionFailed,
        ConnectionLost,
        ConnectionProfile,
        ConnectionView,
        Disconnected,
        EmbeddedProfile,
        Reconnecting,
        StdioProfile,
        WebSocketProfile;
import 'package:codelab_setup/codelab_setup.dart'
    show
        AgentLaunchKind,
        EditableSettings,
        NotManaged,
        RemoteReadOnly,
        resolveSettingsAccess;

import 'about_diagnostics.dart';
import 'about_ports.dart';

/// Снимок окна для «Copy diagnostics»: вид подключения, его состояние, вид
/// доступа к настройкам агента и признак заданного `CODELAB_HOME` (design.md
/// change `add-app-general-page`, D12).
///
/// Почему отдельная чистая функция: правило «какой это вид подключения и чьи
/// настройки» нужно диагностике, а composition root его только вызывает; в
/// корне оно не проверялось бы тестами. Доступ stdio-агента решает мост
/// `resolveSettingsAccess` (SETUP-2, SETUP-8), app его правил не повторяет.
///
/// Для чего: на выходе только перечисления и признак — ни адреса, ни id
/// профиля, ни команды, ни пути в результат попасть не могут (отбор по белому
/// списку, AGENTS.md §16).
///
/// Как использовать: [profile] — профиль окна (подключённый или по умолчанию),
/// [connection] — `WorkspaceState.connection`, [codelabHome] — разрешённый
/// `$CODELAB_HOME`, [environment] — окружение app (`CODELAB_HOME` задан явно,
/// если непуст). Оборванное соединение (`ConnectionLost`) для диагностики —
/// `disconnected`.
AboutWindow aboutWindowOf({
  required ConnectionProfile profile,
  required ConnectionView connection,
  required String codelabHome,
  required Map<String, String> environment,
}) {
  final (kind, access) = switch (profile) {
    EmbeddedProfile() => (
      DiagnosticsConnection.embedded,
      DiagnosticsAccess.editable,
    ),
    WebSocketProfile() => (
      DiagnosticsConnection.websocket,
      DiagnosticsAccess.remoteReadOnly,
    ),
    StdioProfile(:final command, :final args, :final env) => (
      DiagnosticsConnection.stdio,
      switch (resolveSettingsAccess(
        kind: AgentLaunchKind.stdio,
        command: command,
        args: args,
        env: env,
        defaultCodelabHome: codelabHome,
      )) {
        EditableSettings() => DiagnosticsAccess.editable,
        NotManaged() => DiagnosticsAccess.notManaged,
        RemoteReadOnly() => DiagnosticsAccess.remoteReadOnly,
      },
    ),
  };
  return (
    connection: kind,
    state: switch (connection) {
      Disconnected() => DiagnosticsConnectionState.disconnected,
      Connecting() => DiagnosticsConnectionState.connecting,
      Connected() => DiagnosticsConnectionState.connected,
      Reconnecting() => DiagnosticsConnectionState.reconnecting,
      ConnectionLost() => DiagnosticsConnectionState.disconnected,
      ConnectionFailed() => DiagnosticsConnectionState.failed,
    },
    access: access,
    customConfigHome: (environment['CODELAB_HOME'] ?? '').isNotEmpty,
  );
}
