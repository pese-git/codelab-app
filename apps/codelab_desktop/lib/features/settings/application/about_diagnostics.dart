/// Данные раздела «About» и текст «Copy diagnostics» (design.md change
/// `add-app-general-page`, D11, D12).
///
/// Заглушка итерации 5 (красные тесты 5.7): отчёт пустой, реализация — задача
/// 5.8.
library;

import '../../../core/platform/app_language_preferences.dart';

/// Неизменяемые данные раздела «About»; собирает composition root один раз.
///
/// Почему не Cubit: значения не меняются за время работы окна, состояние
/// блока — только «развёрнут ли» и заметка об исходе действия (D11).
final class AboutInfo {
  const AboutInfo({
    required this.version,
    required this.os,
    required this.arch,
    required this.embeddedAgentVersion,
    required this.licenseName,
    required this.licenseCopyright,
    required this.configHome,
    required this.logDirectory,
    required this.thirdPartyNotices,
  });

  /// Версия сборки app.
  final String version;

  /// `macOS`, `Linux`, `Windows`.
  final String os;

  /// `arm64`, `x64`.
  final String arch;

  /// `embeddedAgentVersion` моста `codelab_embedded`.
  final String embeddedAgentVersion;

  /// `MIT`.
  final String licenseName;

  /// Строка `Copyright (c) …`.
  final String licenseCopyright;

  /// `$CODELAB_HOME` с `~` вместо домашнего каталога (`homePathLabel`).
  final String configHome;

  /// Каталог журналов app: путь для `LocalFolderOpener`, в диагностику не
  /// попадает.
  final String logDirectory;

  /// Текст `THIRD_PARTY_NOTICES.md` из ресурсов сборки.
  final String thirdPartyNotices;
}

/// Вид подключения окна.
enum DiagnosticsConnection { embedded, stdio, websocket }

/// Состояние подключения окна.
enum DiagnosticsConnectionState {
  connecting,
  connected,
  reconnecting,
  failed,
  disconnected,
}

/// Вид доступа к настройкам агента окна.
enum DiagnosticsAccess { editable, remoteReadOnly, notManaged }

/// Типизированный контекст окна для диагностики: только перечисления и
/// признаки, без профилей, адресов, путей и значений (D12).
final class DiagnosticsContext {
  const DiagnosticsContext({
    required this.connection,
    required this.connectionState,
    required this.access,
    required this.locale,
    required this.languagePreference,
    required this.customConfigHome,
  });

  final DiagnosticsConnection connection;
  final DiagnosticsConnectionState connectionState;
  final DiagnosticsAccess access;

  /// Код применённого языка интерфейса: `en` или `ru`.
  final String locale;

  final AppLanguagePreference languagePreference;

  /// `CODELAB_HOME` задан явно.
  final bool customConfigHome;
}

/// Текст «Copy diagnostics»: фиксированный набор строк на английском.
String diagnosticsReportOf(AboutInfo about, DiagnosticsContext context) => '';
