/// Данные раздела «About» и текст «Copy diagnostics» (design.md change
/// `add-app-general-page`, D11, D12).
///
/// Почему отбор по белому списку, а не дамп состояния и маскирование: в
/// состоянии окна есть URL, id профилей, папка проекта и команды stdio;
/// маскирование задним числом ловит только известные виды секретов и не
/// скрывает пути пользователя. Отчёт строится из фиксированных строк и
/// перечислений, поэтому утечка закрыта по построению (AGENTS.md §16;
/// приоритет 1).
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
///
/// Для чего: отчёт об ошибке без секретов и путей (spec app-settings
/// «Диагностика для отчёта без секретов и путей»). Не зависит от языка
/// интерфейса: подписи не переводятся, язык показывает только строка
/// `UI language`. Пути, URL, id профилей, значения конфигурации и тексты
/// исключений в отчёт попасть не могут: у [DiagnosticsContext] таких полей нет,
/// а из [AboutInfo] берутся версии и платформа.
///
/// Как использовать: страница зовёт функцию в момент нажатия и кладёт текст в
/// буфер обмена; семь строк разделены `\n`.
String diagnosticsReportOf(AboutInfo about, DiagnosticsContext context) {
  final access = switch (context.access) {
    DiagnosticsAccess.editable => 'editable',
    DiagnosticsAccess.remoteReadOnly => 'remote-read-only',
    DiagnosticsAccess.notManaged => 'not-managed',
  };
  return [
    'CodeLab ${about.version}',
    'OS: ${about.os} ${about.arch}',
    'Embedded agent: ${about.embeddedAgentVersion}',
    'UI language: ${context.locale} '
        '(preference: ${context.languagePreference.name})',
    'Connection: ${context.connection.name} · ${context.connectionState.name}',
    'Agent settings: $access',
    'Config folder: ${context.customConfigHome ? 'custom' : 'default'}',
  ].join('\n');
}
