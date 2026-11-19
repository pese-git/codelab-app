import 'package:codelab_setup/codelab_setup.dart' show ConfigSourceKind;

import '../../../l10n/app_localizations.dart';

/// Подпись источника значения конфигурации на языке интерфейса (D7, решение
/// пользователя 2026-11-19 В1).
///
/// Почему одна функция: подписи `default`, `user`, `project`, `local`,
/// `config`/файл и `env` встречаются на страницах «Agents & modes» и «General»
/// (в том числе внутри фраз с `{source}`), и «один термин — один перевод»
/// требует одного места. `null` — значение задано умолчанием реестра.
/// Подпись стоит в именительной форме: в `ru` она идёт после «источник:», в
/// скобках или после тире; фразы с другим падежом переформулированы.
///
/// Заглушка задачи 5.1c: возвращает пустую строку; реализация — задача 5.2.
String configSourceLabel(AppLocalizations l10n, ConfigSourceKind? kind) => '';

/// Подпись источника строки MCP-сервера: `user`, `this project` или
/// `defined in <file>` (слой 3, `--config`, окружение). [file] — путь с `~`.
///
/// Заглушка задачи 5.1c: возвращает пустую строку; реализация — задача 5.2.
String mcpSourceLabel(
  AppLocalizations l10n,
  ConfigSourceKind kind, {
  String? file,
}) => '';
