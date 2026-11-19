import 'package:codelab_setup/codelab_setup.dart'
    show AgentRowScope, AgentRowStatus;

import '../../../l10n/app_localizations.dart';
import '../application/agents_modes_messages.dart';

/// Подпись режима разрешений: id режима без перевода, для `ask` — с
/// переведённой пометкой `(edits and commands blocked by plan)` (D7).
///
/// Заглушка задачи 5.1c: возвращает пустую строку; реализация — задача 5.2.
String agentModeLabel(
  AppLocalizations l10n,
  String mode, {
  required bool blocksWriteAndExec,
}) => '';

/// Текст тега статуса строки определения: `Available`, `Error · line 4` (с
/// [line]), `Overridden by <путь>` (с [overriddenBy]), `Not loaded: duplicate
/// name` и т. д. (D5).
///
/// Заглушка задачи 5.1c: возвращает пустую строку; реализация — задача 5.2.
String agentRowStatusText(
  AppLocalizations l10n,
  AgentRowStatus status, {
  int? line,
  String? overriddenBy,
}) => '';

/// Подпись области «Available in»: `session`, `subagent`, `both` (D5).
///
/// Заглушка задачи 5.1c: возвращает пустую строку; реализация — задача 5.2.
String agentRowScopeText(AppLocalizations l10n, AgentRowScope scope) => '';

/// Текст баннера записи страницы «Agents & modes»: целые фразы по виду
/// баннера и «когда применится», без склейки основы и хвоста (D5).
///
/// Заглушка задачи 5.1c: возвращает пустую строку; реализация — задача 5.2.
String agentsModesMessageText(
  AppLocalizations l10n,
  AgentsModesMessage message,
) => '';
