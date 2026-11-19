import 'package:codelab_client_acp/codelab_client_acp.dart' show Logger;

import '../../../core/platform/external_link_opener.dart';
import '../../../core/platform/local_folder_opener.dart';
import 'about_diagnostics.dart';

/// Снимок окна для диагностики: вид подключения, его состояние, вид доступа к
/// настройкам агента и признак заданного `CODELAB_HOME`.
typedef AboutWindow = ({
  DiagnosticsConnection connection,
  DiagnosticsConnectionState state,
  DiagnosticsAccess access,
  bool customConfigHome,
});

/// Всё, что нужно разделу «About» страницы «General» от composition root.
///
/// Почему набор портов, а не Cubit: значения раздела не меняются за время
/// работы окна, а действия — открыть ссылку или каталог, скопировать текст —
/// это вызовы портов с исходом, который показывает сама страница (design.md
/// change `add-app-general-page`, D11). Виджет не создаёт адаптеров и не
/// решает, что безопасно открывать: адрес заметок — константа app, каталог
/// журналов — путь composition root (AGENTS.md §6, §10).
///
/// Как использовать: composition root собирает один раз
/// (`CodeLabDependencies.aboutPorts`); страница читает [info] при открытии
/// раздела и [window] в момент «Copy diagnostics».
final class AboutPorts {
  const AboutPorts({
    required this.info,
    required this.window,
    required this.externalLinks,
    required this.folders,
    this.logger,
  });

  /// Данные раздела; повторные вызовы возвращают одно и то же значение.
  final Future<AboutInfo> Function() info;

  /// Текущее подключение и доступ окна для диагностики.
  final Future<AboutWindow> Function() window;

  /// Открытие адреса заметок о выпуске.
  final ExternalLinkOpener externalLinks;

  /// Открытие каталога журналов без создания.
  final LocalFolderOpener folders;

  /// События `settings.about_action`: действие и исход, без путей и адресов.
  final Logger? logger;
}
