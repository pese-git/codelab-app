import 'package:codelab_client_acp/codelab_client_acp.dart' show Logger;
import 'package:codelab_client_core/codelab_client_core.dart'
    show ClientWorkspace, ConnectionProfile;
import 'package:codelab_embedded/codelab_embedded.dart'
    show embeddedAgentVersion;
import 'package:flutter/services.dart' show AssetBundle, rootBundle;

import '../core/platform/build_info.dart';
import '../core/platform/external_link_opener.dart';
import '../core/platform/home_path_label.dart';
import '../core/platform/local_folder_opener.dart';
import '../features/settings/application/about_diagnostics.dart';
import '../features/settings/application/about_ports.dart';
import '../features/settings/application/about_window.dart';
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
/// `BuildInfo`, лицензия — из ресурса `assets/legal/LICENSE` (читается
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
  );
}

Future<AboutWindow> _windowOf(
  ClientWorkspace workspace,
  Future<ConnectionProfile> Function() defaultProfile,
  ConnectionEnvironment environment,
) async {
  final current = workspace.current;
  return aboutWindowOf(
    profile: current.profile ?? await defaultProfile(),
    connection: current.connection,
    codelabHome: environment.codelabHome ?? '',
    environment: environment.variables,
  );
}
