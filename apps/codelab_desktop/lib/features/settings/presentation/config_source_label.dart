import 'package:codelab_setup/codelab_setup.dart' show ConfigSourceKind;

import '../../../l10n/app_localizations.dart';

/// Подпись источника значения конфигурации на языке интерфейса (D7, решение
/// пользователя 2026-11-19 В1).
///
/// Почему одна функция: подписи `default`, `user`, `project`, `local`, файл
/// `--config` и `env` встречаются на страницах «Agents & modes» и «General»
/// (в том числе внутри фраз с `{source}`), и «один термин — один перевод»
/// требует одного места. `null` — значение задано умолчанием реестра.
/// Подпись стоит в именительной форме: в `ru` она идёт после «источник:», в
/// скобках или после тире; фразы с другим падежом переформулированы.
///
/// Для чего: Cubit-ы хранят `ConfigSourceKind?`, а текст строит эта функция по
/// `context.l10n` (D5, «Уточнение итерации 5»).
///
/// Как использовать: [forGeneral] выбирает прежнюю английскую подпись
/// страницы «General» для файла `--config` (`config`; на «Agents & modes» —
/// `file`); в `ru` обе подписи — «файл».
String configSourceLabel(
  AppLocalizations l10n,
  ConfigSourceKind? kind, {
  bool forGeneral = false,
}) => switch (kind) {
  null => l10n.configSourceDefault,
  ConfigSourceKind.user => l10n.configSourceUser,
  ConfigSourceKind.project => l10n.configSourceProject,
  ConfigSourceKind.projectLocal => l10n.configSourceLocal,
  ConfigSourceKind.extraFile =>
    forGeneral ? l10n.configSourceConfig : l10n.configSourceFile,
  ConfigSourceKind.environment => l10n.configSourceEnv,
};

/// Подпись источника строки MCP-сервера: `user`, `this project` или
/// `defined in <file>` (слой 3, `--config`, окружение). [file] — путь с `~`.
String mcpSourceLabel(
  AppLocalizations l10n,
  ConfigSourceKind kind, {
  String? file,
}) {
  switch (kind) {
    case ConfigSourceKind.user:
      return l10n.configSourceUser;
    case ConfigSourceKind.projectLocal:
      return l10n.mcpSourceThisProject;
    default:
      // Путь файла обязателен для слоя 3, `--config` и окружения.
      assert(file != null, 'defined in: нужен путь файла');
      return l10n.mcpSourceDefinedIn(file ?? '');
  }
}
