import 'package:codelab_client_acp/codelab_client_acp.dart' show Logger;
import 'package:codelab_client_core/codelab_client_core.dart'
    show
        ClientWorkspace,
        Connected,
        Connecting,
        ConnectionFailed,
        ConnectionLost,
        ConnectionProfile,
        Disconnected,
        EmbeddedProfile,
        Reconnecting,
        StdioProfile,
        WebSocketProfile;
import 'package:codelab_embedded/codelab_embedded.dart'
    show embeddedAgentVersion;
import 'package:codelab_setup/codelab_setup.dart'
    show
        AgentLaunchKind,
        EditableSettings,
        NotManaged,
        RemoteReadOnly,
        resolveSettingsAccess;
import 'package:flutter/services.dart' show AssetBundle, rootBundle;

import '../core/platform/build_info.dart';
import '../core/platform/external_link_opener.dart';
import '../core/platform/home_path_label.dart';
import '../core/platform/local_folder_opener.dart';
import '../features/settings/application/about_diagnostics.dart';
import '../features/settings/application/about_ports.dart';
import '../features/settings/application/license_summary.dart';
import 'connection_environment.dart';

/// Собирает [AboutPorts] раздела «About» (design.md change
/// `add-app-general-page`, D11, D13).
///
/// Почему в composition root: версия агента, ресурсы лицензий, путь журналов и
/// окружение известны только ему; страница получает готовые данные и порты.
///
/// Для чего: [fixed] — шов тестов, готовые данные без чтения ресурсов; без
/// него версия берётся из `build_version.dart`, ОС и архитектура — из
/// `BuildInfo`, лицензия и уведомления — из ресурсов `assets/legal/` (читаются
/// лениво, один раз, без сети). [logDirectory] — тот же каталог, что у
/// `CodeLabLoggingModule`.
AboutPorts buildAboutPorts({
  required String version,
  required ConnectionEnvironment environment,
  required String logDirectory,
  required ClientWorkspace workspace,
  required Future<ConnectionProfile> Function() defaultProfile,
  required ExternalLinkOpener externalLinks,
  required LocalFolderOpener folders,
  AboutInfo? fixed,
  AssetBundle? bundle,
  Logger? logger,
}) {
  Future<AboutInfo>? cached;
  Future<AboutInfo> load() => cached ??= fixed != null
      ? Future.value(fixed)
      : _loadInfo(
          version: version,
          environment: environment,
          logDirectory: logDirectory,
          bundle: bundle ?? rootBundle,
        );
  return AboutPorts(
    info: load,
    window: () => _windowOf(workspace, defaultProfile, environment),
    externalLinks: externalLinks,
    folders: folders,
    logger: logger,
  );
}

Future<AboutInfo> _loadInfo({
  required String version,
  required ConnectionEnvironment environment,
  required String logDirectory,
  required AssetBundle bundle,
}) async {
  final license = await bundle.loadString('assets/legal/LICENSE');
  final notices = await bundle.loadString(
    'assets/legal/THIRD_PARTY_NOTICES.md',
  );
  final summary = licenseSummaryOf(license);
  final build = BuildInfo.current();
  final home = environment.codelabHome;
  return AboutInfo(
    version: version,
    os: build.os,
    arch: build.arch,
    embeddedAgentVersion: embeddedAgentVersion,
    licenseName: summary.name,
    licenseCopyright: summary.copyright,
    configHome: home == null || home.isEmpty
        ? '~/.codelab'
        : homePathLabel(home, environment.variables),
    logDirectory: logDirectory,
    thirdPartyNotices: notices,
  );
}

Future<AboutWindow> _windowOf(
  ClientWorkspace workspace,
  Future<ConnectionProfile> Function() defaultProfile,
  ConnectionEnvironment environment,
) async {
  final current = workspace.current;
  final profile = current.profile ?? await defaultProfile();
  final home = environment.codelabHome ?? '';
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
        defaultCodelabHome: home,
      )) {
        EditableSettings() => DiagnosticsAccess.editable,
        NotManaged() => DiagnosticsAccess.notManaged,
        RemoteReadOnly() => DiagnosticsAccess.remoteReadOnly,
      },
    ),
  };
  return (
    connection: kind,
    state: switch (current.connection) {
      Disconnected() => DiagnosticsConnectionState.disconnected,
      Connecting() => DiagnosticsConnectionState.connecting,
      Connected() => DiagnosticsConnectionState.connected,
      Reconnecting() => DiagnosticsConnectionState.reconnecting,
      ConnectionLost() => DiagnosticsConnectionState.disconnected,
      ConnectionFailed() => DiagnosticsConnectionState.failed,
    },
    access: access,
    customConfigHome: (environment.variables['CODELAB_HOME'] ?? '').isNotEmpty,
  );
}
