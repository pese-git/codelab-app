// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'codelab_localizations.dart';

// ignore_for_file: type=lint

/// The translations for English (`en`).
class CodeLabLocalizationsEn extends CodeLabLocalizations {
  CodeLabLocalizationsEn([String locale = 'en']) : super(locale);

  @override
  String get codeLabApprovalAwaiting => 'Awaiting approval';

  @override
  String get codeLabApprovalAllow => 'Allow';

  @override
  String get codeLabApprovalReject => 'Reject';

  @override
  String get codeLabApprovalScopeOnce => 'Only this time';

  @override
  String get codeLabApprovalScopeAlways => 'Always';

  @override
  String get codeLabApprovalViewRawInput => 'View raw input';

  @override
  String get codeLabApprovalHideRawInput => 'Hide raw input';

  @override
  String get codeLabApprovalNoSuchOption => 'The agent offers no such option';

  @override
  String get codeLabApprovalSelected => 'Selected';

  @override
  String get codeLabApprovalToneInfo => 'Info';

  @override
  String get codeLabApprovalToneOption => 'Option';

  @override
  String get codeLabApprovalToneSafe => 'Safe';

  @override
  String get codeLabApprovalToneReview => 'Review';

  @override
  String get codeLabApprovalToneRisk => 'Risk';

  @override
  String get codeLabRiskReadOnly => 'Read-only';

  @override
  String get codeLabRiskUnknown => 'Unknown risk';

  @override
  String get codeLabRiskLocalWrite => 'Local write';

  @override
  String get codeLabRiskNetwork => 'Network';

  @override
  String get codeLabRiskShell => 'Shell';

  @override
  String get codeLabRiskDestructive => 'Destructive';

  @override
  String get codeLabCallQueued => 'Queued';

  @override
  String get codeLabCallRunning => 'Running';

  @override
  String get codeLabCallDone => 'Done';

  @override
  String get codeLabCallFailed => 'Failed';

  @override
  String get codeLabCallCancelled => 'Cancelled';

  @override
  String get codeLabCallShowLess => 'Show less';

  @override
  String get codeLabCallShowFullCommand => 'Show full command';

  @override
  String codeLabCallMoreToolCalls(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '+$count more tool calls',
    );
    return '$_temp0';
  }

  @override
  String get codeLabTranscriptNoticeDetails => 'Details';

  @override
  String get codeLabTranscriptEmpty => 'No transcript yet';

  @override
  String get codeLabSessionRunning => 'Running';

  @override
  String get codeLabSessionApproval => 'Approval';

  @override
  String get codeLabSessionFailed => 'Failed';

  @override
  String get codeLabSessionCancelled => 'Cancelled';

  @override
  String get codeLabSessionNotLoaded => 'Not loaded';

  @override
  String get codeLabSessionDetached => 'Detached';

  @override
  String get codeLabConnectionIdle => 'Idle';

  @override
  String get codeLabConnectionConnecting => 'Connecting';

  @override
  String get codeLabConnectionConnected => 'Connected';

  @override
  String get codeLabConnectionReconnecting => 'Reconnecting';

  @override
  String get codeLabConnectionDisconnected => 'Disconnected';

  @override
  String get codeLabConnectionLost => 'Connection lost';

  @override
  String get codeLabConnectionFailed => 'Failed';

  @override
  String get codeLabAppBarConnecting => 'Connecting…';

  @override
  String get codeLabAppBarReconnecting => 'Reconnecting…';

  @override
  String get codeLabAppBarConnectionFailed => 'Connection failed';

  @override
  String get codeLabBannerLost => 'Connection to the agent lost';

  @override
  String get codeLabBannerFailed => 'Could not connect to the agent';

  @override
  String get codeLabBannerReconnecting => 'Reconnecting…';

  @override
  String get codeLabBannerConnectionSettings => 'Connection settings';

  @override
  String get codeLabConnectionScreenConfigure => 'Configure connection';

  @override
  String get codeLabActionSend => 'Send';

  @override
  String get codeLabActionCancel => 'Cancel';

  @override
  String get codeLabActionCopy => 'Copy';

  @override
  String get codeLabActionCopyPath => 'Copy path';

  @override
  String get codeLabActionRetry => 'Retry';

  @override
  String get codeLabActionReconnect => 'Reconnect';

  @override
  String get codeLabActionConnect => 'Connect';

  @override
  String get codeLabActionEdit => 'Edit';

  @override
  String get codeLabActionSendNow => 'Send now';

  @override
  String get codeLabActionDelete => 'Delete';

  @override
  String get codeLabActionClearAll => 'Clear all';

  @override
  String get codeLabActionGoToApproval => 'Go to approval';

  @override
  String get codeLabActionShowInTranscript => 'Show in transcript';

  @override
  String get codeLabActionComingSoon => 'Coming soon';

  @override
  String get codeLabComposerPlaceholder => 'Message the agent';

  @override
  String get codeLabStatusBarTurnInProgress => 'Turn in progress';

  @override
  String get codeLabThoughtThinkingSemantics => 'Thinking';

  @override
  String get codeLabThoughtThinking => 'Thinking…';

  @override
  String get codeLabThoughtThoughts => 'Thoughts';

  @override
  String get codeLabTurnRunning => 'Turn running';

  @override
  String get codeLabTurnWaitingApproval => 'Waiting for approval';

  @override
  String get codeLabTurnCancelling => 'Cancelling…';

  @override
  String get codeLabPlanTitle => 'Plan';

  @override
  String get codeLabPlanCurrent => 'Current:';

  @override
  String codeLabPlanLeft(int count) {
    return '$count left';
  }

  @override
  String codeLabPlanTasks(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count Tasks',
    );
    return '$_temp0';
  }

  @override
  String get codeLabPlanClear => 'Clear plan';

  @override
  String codeLabPlanBlockedBy(String ids) {
    return 'blocked by $ids';
  }

  @override
  String get codeLabPlanPriorityHigh => 'High';

  @override
  String get codeLabPlanPriorityMedium => 'Medium';

  @override
  String get codeLabPlanPriorityLow => 'Low';

  @override
  String get codeLabQueueTitle => 'Queue';

  @override
  String codeLabQueueCount(int count) {
    return '$count queued';
  }

  @override
  String get codeLabSidebarNewSession => 'New session';

  @override
  String codeLabSidebarNewSessionTooltip(String shortcut) {
    return 'New session ($shortcut)';
  }

  @override
  String get codeLabSidebarSearchSessions => 'Search sessions';

  @override
  String get codeLabSidebarProjects => 'Projects';

  @override
  String get codeLabSidebarOpenFolder => 'Open folder…';

  @override
  String get codeLabSidebarSettings => 'Settings';

  @override
  String get codeLabSidebarNoSessions => 'No sessions yet';

  @override
  String get codeLabSidebarNoMatchingSessions => 'No matching sessions';

  @override
  String get codeLabSidebarLoadMore => 'Load more sessions';

  @override
  String get codeLabAppBarSearch => 'Search or run a command';

  @override
  String codeLabAppBarSearchTooltip(String shortcut) {
    return 'Search or run a command ($shortcut)';
  }

  @override
  String get codeLabPaletteTitle => 'Command palette';

  @override
  String get codeLabPaletteEmpty => 'No matching commands';

  @override
  String get codeLabPaletteAgentSection => 'From agent';

  @override
  String get codeLabPaneFiles => 'Files';

  @override
  String get codeLabPaneDiff => 'Diff';

  @override
  String get codeLabPaneTerminal => 'Terminal';

  @override
  String get codeLabPanePlan => 'Plan';

  @override
  String get codeLabPaneTimeline => 'Timeline';

  @override
  String get codeLabPaneAgents => 'Agents';

  @override
  String get codeLabPaneUsage => 'Usage';

  @override
  String get codeLabPaneBranches => 'Branches';

  @override
  String get codeLabPaneProtocol => 'Protocol';

  @override
  String get codeLabTerminalNoSession => 'Open a session to use the terminal';

  @override
  String get codeLabTerminalNew => 'New terminal';

  @override
  String get codeLabAgentsTitle => 'Subagents';

  @override
  String get codeLabAgentsSteps => 'Steps';

  @override
  String get codeLabAgentsStateRunning => 'running';

  @override
  String get codeLabAgentsStateWaiting => 'waiting for approval';

  @override
  String get codeLabAgentsStateDone => 'done';

  @override
  String get codeLabAgentsStateFailed => 'failed';

  @override
  String get codeLabAgentsStateCancelled => 'cancelled';

  @override
  String codeLabAgentsCountRunning(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count running',
    );
    return '$_temp0';
  }

  @override
  String codeLabAgentsCountWaiting(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count waiting for approval',
    );
    return '$_temp0';
  }

  @override
  String codeLabAgentsCountDone(int count) {
    return '$count done';
  }

  @override
  String codeLabAgentsCountFailed(int count) {
    return '$count failed';
  }

  @override
  String codeLabAgentsCountCancelled(int count) {
    return '$count cancelled';
  }

  @override
  String codeLabFileBinary(String sizeLabel) {
    return 'Binary file ($sizeLabel)';
  }

  @override
  String codeLabFileTooLarge(String sizeLabel) {
    return 'File too large to preview ($sizeLabel)';
  }

  @override
  String get codeLabFileSecretWarning => 'This file may contain secrets.';

  @override
  String get codeLabFileOutsideLink => 'outside, not opened';

  @override
  String get codeLabUsageLoading => 'Loading usage history';

  @override
  String get codeLabUsageRebuild => 'Rebuild from log';

  @override
  String get codeLabUsageExportCsv => 'Export CSV';

  @override
  String get codeLabUsagePerTurn => 'Per turn';

  @override
  String get codeLabUsagePerModel => 'Per model';

  @override
  String get codeLabUsageColumnInput => 'Input';

  @override
  String get codeLabUsageColumnOutput => 'Output';

  @override
  String get codeLabUsageColumnCost => 'Cost';

  @override
  String get codeLabUsageRunning => 'running';

  @override
  String get codeLabLayoutAppBar => 'App bar';

  @override
  String get codeLabLayoutSessionsSidebar => 'Sessions sidebar';

  @override
  String get codeLabLayoutSessionPane => 'Session pane';

  @override
  String get codeLabLayoutToolDock => 'Tool dock';

  @override
  String get codeLabSettingsTitle => 'Settings';

  @override
  String get codeLabSettingsFind => 'Find a setting';

  @override
  String codeLabSettingsNoMatch(String query) {
    return 'No settings match \"$query\"';
  }

  @override
  String get codeLabStatusTableActions => 'Actions';

  @override
  String get codeLabMarkdownSelectAll => 'Select all';

  @override
  String get codeLabMarkdownNestingTooDeep =>
      'Shown as plain text: nesting is too deep.';

  @override
  String get codeLabMarkdownTaskDone => 'Task done';

  @override
  String get codeLabMarkdownTaskOpen => 'Task open';

  @override
  String get codeLabMarkdownImage => 'Image';

  @override
  String get codeLabMarkdownShowImage => 'Show image';

  @override
  String codeLabShortcutAlternatives(String first, String second) {
    return '$first or $second';
  }
}
