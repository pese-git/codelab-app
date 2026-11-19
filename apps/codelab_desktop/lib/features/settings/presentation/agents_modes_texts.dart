import 'package:codelab_setup/codelab_setup.dart'
    show AgentRowScope, AgentRowStatus, ConfigLayer;

import '../../../l10n/app_localizations.dart';
import '../application/agents_modes_messages.dart';
import 'config_source_label.dart';

/// Подпись режима разрешений: id режима без перевода, для `ask` — с
/// переведённой пометкой `(edits and commands blocked by plan)` (D7).
String agentModeLabel(
  AppLocalizations l10n,
  String mode, {
  required bool blocksWriteAndExec,
}) => blocksWriteAndExec ? l10n.agentsModeBlocked(mode) : mode;

/// Текст тега статуса строки определения: `Available`, `Error · line 4` (с
/// [line]), `Overridden by <путь>` (с [overriddenBy]), `Not loaded: duplicate
/// name` и т. д. (D5).
String agentRowStatusText(
  AppLocalizations l10n,
  AgentRowStatus status, {
  int? line,
  String? overriddenBy,
}) => switch (status) {
  AgentRowStatus.available => l10n.agentsStatusAvailable,
  AgentRowStatus.overridden =>
    overriddenBy == null
        ? l10n.agentsStatusOverridden
        : l10n.agentsStatusOverriddenBy(overriddenBy),
  AgentRowStatus.modelNotConfigured => l10n.agentsStatusModelNotConfigured,
  AgentRowStatus.error =>
    line == null ? l10n.agentsStatusError : l10n.agentsStatusErrorLine(line),
  AgentRowStatus.duplicate => l10n.agentsStatusDuplicate,
  AgentRowStatus.shadowed => l10n.agentsStatusShadowed,
  AgentRowStatus.subagentsOff => l10n.agentsStatusSubagentsOff,
};

/// Подпись области «Available in»: `session`, `subagent`, `both` (D5).
String agentRowScopeText(AppLocalizations l10n, AgentRowScope scope) =>
    switch (scope) {
      AgentRowScope.session => l10n.agentsScopeSession,
      AgentRowScope.subagent => l10n.agentsScopeSubagent,
      AgentRowScope.both => l10n.agentsScopeBoth,
    };

/// Название цели записи на языке интерфейса.
String agentsTargetName(AppLocalizations l10n, ConfigLayer layer) =>
    layer == ConfigLayer.projectLocal
    ? l10n.agentsTargetProject
    : l10n.agentsTargetAll;

/// Текст баннера записи страницы «Agents & modes»: целые фразы по виду
/// баннера и «когда применится» (ICU `select`), без склейки основы и хвоста
/// (D5, правило 7).
String agentsModesMessageText(
  AppLocalizations l10n,
  AgentsModesMessage message,
) {
  return switch (message) {
    AgentsSavedMessage(
      :final setting,
      :final value,
      when: final applyWhen,
      :final blocksWriteAndExec,
    ) =>
      l10n.agentsBannerSaved(
        _label(l10n, setting, value, blocksWriteAndExec),
        applyWhen.name,
      ),
    AgentsSavedOverriddenMessage(
      :final setting,
      :final target,
      :final source,
      :final value,
      when: final applyWhen,
      :final blocksWriteAndExec,
    ) =>
      l10n.agentsBannerOverridden(
        agentsTargetName(l10n, target),
        configSourceLabel(l10n, source),
        _label(l10n, setting, value, blocksWriteAndExec),
        applyWhen.name,
      ),
    AgentsSavedNarrowedMessage(
      :final target,
      :final value,
      when: final applyWhen,
      :final blocksWriteAndExec,
    ) =>
      l10n.agentsBannerNarrowed(
        agentsTargetName(l10n, target),
        _label(l10n, AgentsModesSetting.mode, value, blocksWriteAndExec),
        applyWhen.name,
      ),
    AgentsSavedOnlyMessage(:final target) => l10n.agentsBannerSavedOnly(
      agentsTargetName(l10n, target),
    ),
    AgentsBypassStaleMessage() => l10n.agentsBannerBypassStale,
    AgentsConflictMessage() => l10n.agentsBannerConflict,
    AgentsNotSavedMessage() => l10n.agentsBannerNotSaved,
    AgentsTargetUnavailableMessage() => l10n.agentsBannerTargetUnavailable,
  };
}

String _label(
  AppLocalizations l10n,
  AgentsModesSetting setting,
  String id,
  bool blocks,
) => setting == AgentsModesSetting.mode
    ? agentModeLabel(l10n, id, blocksWriteAndExec: blocks)
    : id;
