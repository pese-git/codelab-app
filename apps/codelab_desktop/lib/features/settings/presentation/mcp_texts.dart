import 'package:codelab_embedded/codelab_embedded.dart' show McpServerState;
import 'package:codelab_setup/codelab_setup.dart' show McpDraftProblem;

import '../../../l10n/app_localizations.dart';
import '../application/mcp_messages.dart';

/// Подпись состояния MCP-сервера в таблице «Agent status»: `connected`,
/// `failed · retry in 24 s` (с [retryIn] в секундах), `disabled` (D5, D8).
///
/// Заглушка задачи 5.1c: возвращает пустую строку; реализация — задача 5.2.
String mcpServerStateText(
  AppLocalizations l10n,
  McpServerState state, {
  Duration? retryIn,
}) => '';

/// Текст проблемы черновика MCP-сервера по её коду и аргументу (имя ключа);
/// при `code == null` — `message` как есть (проблема чужого источника).
///
/// Заглушка задачи 5.1c: возвращает пустую строку; реализация — задача 5.2.
String mcpDraftProblemText(AppLocalizations l10n, McpDraftProblem problem) =>
    '';

/// Строки баннера страницы «MCP servers» по сообщению: первая — итог, остальные
/// — подробности (секреты, предупреждения). Команда `codelab secret delete
/// <имя>` и тексты ядра агента и хранилища — без изменений.
///
/// Заглушка задачи 5.1c: возвращает пустой список; реализация — задача 5.2.
List<String> mcpMessageLines(AppLocalizations l10n, McpMessage message) =>
    const [];
