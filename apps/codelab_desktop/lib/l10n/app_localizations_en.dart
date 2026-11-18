// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for English (`en`).
class AppLocalizationsEn extends AppLocalizations {
  AppLocalizationsEn([String locale = 'en']) : super(locale);

  @override
  String get settingsPageGeneralTitle => 'General';

  @override
  String get settingsLanguageTitle => 'Language';

  @override
  String get settingsLanguageSystem => 'System';

  @override
  String get settingsLanguageEnglish => 'English';

  @override
  String get settingsLanguageRussian => 'Русский';

  @override
  String get settingsLanguageSaveFailed =>
      'Couldn\'t save the language. CodeLab will use the previous language after restart.';

  @override
  String get settingsGroupAgent => 'Agent';

  @override
  String get settingsGroupApp => 'App';

  @override
  String get settingsPageConnectionTitle => 'Connection';

  @override
  String get settingsPageProvidersTitle => 'Providers';

  @override
  String get settingsPageMcpServersTitle => 'MCP servers';

  @override
  String get settingsPageAgentsAndModesTitle => 'Agents & modes';

  @override
  String get settingsPagePermissionsAndToolsTitle => 'Permissions & tools';

  @override
  String get settingsPageRedactionTitle => 'Redaction';

  @override
  String get settingsPageSkillsAndExtensionsTitle => 'Skills & extensions';

  @override
  String get settingsPageCodeAndWebTitle => 'Code & web';

  @override
  String get settingsPageAppearanceTitle => 'Appearance';

  @override
  String get settingsPageKeyboardTitle => 'Keyboard';

  @override
  String get settingsGeneralSectionInterface => 'Interface';

  @override
  String get settingsLanguageSaveRetry => 'Retry';

  @override
  String get commonCancel => 'Cancel';

  @override
  String get commonClose => 'Close';

  @override
  String get commonOpen => 'Open';

  @override
  String get commonRetry => 'Retry';

  @override
  String get commonRestartAgent => 'Restart agent';

  @override
  String get commonNewSession => 'New session';

  @override
  String get workbenchSessionActive => 'Active';

  @override
  String workbenchSessionTitleWithId(String id) {
    return 'Session $id';
  }

  @override
  String workbenchSessionUpdated(String time) {
    return 'Updated $time';
  }

  @override
  String get workbenchNoProject => 'No project';

  @override
  String get workbenchNoActiveSession => 'No active session';

  @override
  String get workbenchOpenProjectHint => 'Open a project to start a session.';

  @override
  String get workbenchOpenFolder => 'Open folder…';

  @override
  String workbenchStartNewSessionIn(String project) {
    return 'Start a new session in $project.';
  }

  @override
  String workbenchStarting(String profile) {
    return 'Starting $profile…';
  }

  @override
  String get workbenchTranscriptEmptyNoSession =>
      'Start a new session to talk to the agent.';

  @override
  String get workbenchTranscriptEmptySession => 'Send a message to start.';

  @override
  String get workbenchTransportEmbedded => 'Embedded agent';

  @override
  String get workbenchConnectionStartFailed => 'Could not start the agent.';

  @override
  String workbenchConnectionFailedAgain(String reason, int repeat) {
    return '$reason Failed again ($repeat)';
  }

  @override
  String get workbenchNoProviderConfigured =>
      'No model provider is configured for the embedded agent.';

  @override
  String get workbenchAddProvider => 'Add provider';

  @override
  String workbenchProjectFolderMissing(String path) {
    return 'Project folder not found: $path. Choose an existing folder with Open folder….';
  }

  @override
  String get workbenchLinkOpenFailed => 'Couldn\'t open the link.';

  @override
  String get workbenchNoticeSessionDetached => 'Session detached';

  @override
  String get workbenchNoticeDetachedCannotRestore =>
      'The agent cannot restore sessions after reconnecting.';

  @override
  String workbenchNoticeDetachedRestoreFailed(String id) {
    return 'Session $id could not be restored after reconnecting.';
  }

  @override
  String get workbenchNoticeReconnectedCannotRestore =>
      'The agent cannot restore sessions; a new session was started.';

  @override
  String workbenchNoticeReconnectedRestoreFailed(String id) {
    return 'Session $id could not be restored; a new session was started.';
  }

  @override
  String get workbenchNoticeMaxTokens =>
      'The model reached its token limit, so the turn ended.';

  @override
  String get workbenchNoticeMaxTurnRequests =>
      'The turn reached the limit of model requests.';

  @override
  String workbenchNoticeBudgetExceeded(String limit) {
    return 'The turn stopped: budget exceeded: $limit.';
  }

  @override
  String get workbenchNoticeRefusal => 'The agent refused to continue.';

  @override
  String workbenchNoticeCompletedWithStopReason(String stopReason) {
    return 'Completed with stopReason $stopReason.';
  }

  @override
  String get workbenchNoticeCompletedStopReasonUnknown =>
      'Completed with stopReason unknown.';

  @override
  String get workbenchFailureAuth =>
      'The agent could not sign in to the model provider';

  @override
  String get workbenchFailureProviderUnavailable =>
      'The model provider is unavailable';

  @override
  String get workbenchFailureRateLimited =>
      'The model provider\'s rate limit was reached';

  @override
  String get workbenchFailureOverflow =>
      'The conversation is too long for the model';

  @override
  String get workbenchFailureConnectionLost =>
      'The connection to the agent was lost';

  @override
  String get workbenchFailureGeneric => 'The agent could not complete the turn';

  @override
  String get workbenchFailureConnectionLostBody =>
      'Retry to continue working with the agent.';

  @override
  String get workbenchToolKindRead => 'Read';

  @override
  String get workbenchToolKindEdit => 'Edit';

  @override
  String get workbenchToolKindDelete => 'Delete';

  @override
  String get workbenchToolKindMove => 'Move';

  @override
  String get workbenchToolKindSearch => 'Search';

  @override
  String get workbenchToolKindExecute => 'Run';

  @override
  String get workbenchToolKindFetch => 'Fetch';

  @override
  String get workbenchToolKindThink => 'Think';

  @override
  String get workbenchToolKindSwitchMode => 'Mode';

  @override
  String workbenchRequesterWantsToRun(String path) {
    return '$path wants to run';
  }

  @override
  String workbenchAgentRowTokens(String tokens) {
    return '$tokens tokens';
  }

  @override
  String workbenchAgentRowToolCalls(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count tool calls',
      one: '$count tool call',
    );
    return '$_temp0';
  }

  @override
  String get workbenchStatusUsageUnknown => 'usage: —';

  @override
  String get workbenchStatusUsageUnknownTooltip =>
      'agent does not report usage';

  @override
  String workbenchStatusTokenInput(int count) {
    return 'input $count';
  }

  @override
  String workbenchStatusTokenOutput(int count) {
    return 'output $count';
  }

  @override
  String workbenchStatusTokenCacheRead(int count) {
    return 'cache read $count';
  }

  @override
  String workbenchStatusTokenCacheWrite(int count) {
    return 'cache write $count';
  }

  @override
  String workbenchStatusTokenReasoning(int count) {
    return 'reasoning $count';
  }

  @override
  String workbenchStatusApproximate(String reasons) {
    return 'approximate: $reasons';
  }

  @override
  String get usagePartialNoUsage => 'agent sent no usage for some steps';

  @override
  String get usagePartialNoPrice => 'price unknown for some steps';

  @override
  String get usagePartialBeforeLoad => 'before the session was loaded';

  @override
  String get workbenchStatusPriceUnknown => 'price unknown';

  @override
  String workbenchStatusCostWithSession(String turn, String session) {
    return '$turn · session $session';
  }

  @override
  String workbenchStatusContext(String fill) {
    return '$fill context';
  }

  @override
  String workbenchStatusContextCompactionSoon(String fill) {
    return '$fill context · compaction soon';
  }

  @override
  String get workbenchRootSessionTitle => 'Open session in the disk root?';

  @override
  String workbenchRootSessionBody(String cwd) {
    return 'This session runs in the disk root ($cwd). The agent gets access to the whole disk. Open anyway?';
  }

  @override
  String get workbenchRestartTitle => 'Restart agent?';

  @override
  String workbenchRestartMessage(String title, int count, String sessions) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count running sessions',
      one: '$count running session',
    );
    return 'Restart $title? This interrupts $_temp0: $sessions. Queued prompts stay.';
  }

  @override
  String get workbenchInspectorTitle => 'Inspector';

  @override
  String get workbenchInspectorCategoryApproval => 'Approval';

  @override
  String get workbenchInspectorCategoryTool => 'Tool';

  @override
  String get workbenchInspectorCategoryProtocol => 'Protocol';

  @override
  String get workbenchInspectorCategoryDiagnostic => 'Diagnostic';

  @override
  String workbenchInspectorRisk(String risk) {
    return 'Risk $risk';
  }

  @override
  String get workbenchInspectorRawInput => 'Raw input';

  @override
  String get workbenchInspectorRawOutput => 'Raw output';

  @override
  String get workbenchDebugLogTitle => 'Debug log';

  @override
  String get workbenchDebugLogExpand => 'Expand';

  @override
  String get paletteNewLabel => 'New session';

  @override
  String get paletteNewDescription => 'Start a fresh ACP session.';

  @override
  String get palettePlanLabel => 'Plan mode';

  @override
  String get palettePlanDescription => 'Switch the prompt turn into planning.';

  @override
  String get palettePermissionsLabel => 'Permissions';

  @override
  String get palettePermissionsDescription => 'Open permission mode controls.';

  @override
  String get paletteLogsLabel => 'Logs';

  @override
  String get paletteLogsDescription => 'Open protocol and diagnostic logs.';

  @override
  String get paletteCompactLabel => 'Compact transcript';

  @override
  String get paletteCompactDescription =>
      'Prepare the transcript for compaction.';

  @override
  String get paletteReconnectLabel => 'Reconnect';

  @override
  String get paletteReconnectDescription =>
      'Retry the current agent connection.';

  @override
  String get paletteRestartDescription =>
      'Restart the agent with the selected profile and reload open sessions.';

  @override
  String get paletteFilesLabel => 'Files';

  @override
  String get paletteFilesDescription => 'Go to the project files panel.';

  @override
  String get paletteAgentsLabel => 'Agents';

  @override
  String get paletteAgentsDescription => 'Go to the subagents panel.';

  @override
  String get paletteUsageLabel => 'Usage';

  @override
  String get paletteUsageDescription => 'Go to the usage panel.';

  @override
  String get secretMigrationWarning =>
      'Secrets are stored in the agent config file.';

  @override
  String get secretMigrationMigrateSecrets => 'Migrate secrets';

  @override
  String get secretMigrationPlanning => 'Building the migration plan…';

  @override
  String get secretMigrationApplying => 'Moving secrets…';

  @override
  String get secretMigrationNothing => 'Nothing to migrate.';

  @override
  String get secretMigrationMoved =>
      'Secrets moved. Restart the embedded agent to use them.';

  @override
  String get secretMigrationAgentGone =>
      'The embedded agent is no longer connected.';

  @override
  String get secretMigrationWaitForTurn =>
      'Wait for the current turn to finish.';

  @override
  String secretMigrationPlanFailed(String errorClass) {
    return 'Planning failed: $errorClass.';
  }

  @override
  String secretMigrationApplyFailed(String errorClass) {
    return 'Migration failed: $errorClass.';
  }

  @override
  String get secretMigrationMigrate => 'Migrate';

  @override
  String get usageTitle => 'This session';

  @override
  String get usageCardInput => 'Input';

  @override
  String get usageCardOutput => 'Output';

  @override
  String get usageCardCost => 'Cost';

  @override
  String get usageCardTurns => 'Turns · steps';

  @override
  String usageDetailCache(String read, String write) {
    return 'cache read $read · write $write';
  }

  @override
  String usageDetailReasoning(String count) {
    return 'reasoning $count';
  }

  @override
  String get usageDetailNoUsageYet => 'no usage yet';

  @override
  String get usageDetailPriceUnknown => 'price unknown';

  @override
  String usageDetailAverageSteps(String average) {
    return 'avg $average steps per turn';
  }

  @override
  String usageStepLabel(int number, String title) {
    return 'step $number · $title';
  }

  @override
  String get usageStepReply => 'reply';

  @override
  String usageStepToolCalls(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count tool calls',
      one: '$count tool call',
    );
    return '$_temp0';
  }

  @override
  String usageTurnSubagents(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count runs',
      one: '$count run',
    );
    return 'subagents · $_temp0';
  }

  @override
  String get usageModelSubagents => 'Subagents';

  @override
  String get usageModelSummaries => 'Summaries';

  @override
  String usageModelRuns(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count runs',
      one: '$count run',
    );
    return '$_temp0';
  }

  @override
  String get usageLedgerUpToDate => 'Ledger: up to date';

  @override
  String get usageLedgerRebuilt => 'rebuilt from journal';

  @override
  String get usageLedgerInMemory => 'in memory';

  @override
  String get usageLedgerNotSaved => 'not saved';

  @override
  String usageLedgerRecords(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count records',
      one: '$count record',
    );
    return '$_temp0';
  }

  @override
  String usageLedgerReason(String reason) {
    return '($reason)';
  }

  @override
  String usageLedgerRefreshedHint(String reason) {
    return 'refreshed from the session journal ($reason)';
  }

  @override
  String get usageNoteLedgerFailed => 'Couldn\'t load usage history.';

  @override
  String get usageNoteNoLedger => 'This agent does not provide usage history.';

  @override
  String get usageNoteSaveFailed => 'Couldn\'t save the file.';

  @override
  String get usageBudgetThisTurn => 'This turn';

  @override
  String get usageBudgetLastTurn => 'Last turn';

  @override
  String get usageBudgetSteps => 'Steps';

  @override
  String get usageBudgetTokens => 'Tokens';

  @override
  String get usageBudgetTime => 'Time';

  @override
  String get usageBudgetTokensHint => 'input + output, including subagents';

  @override
  String get usageBudgetCostNote => 'not checked: price unknown';

  @override
  String get usageBudgetFootnote =>
      'When a limit is hit, the turn stops at the next step boundary.';

  @override
  String terminalTabTitle(int number) {
    return 'Terminal $number';
  }

  @override
  String get terminalStatusStarting => 'Starting';

  @override
  String get terminalStatusRunning => 'Running';

  @override
  String get terminalStatusExited => 'Exited';

  @override
  String terminalStatusExitedWithCode(int code) {
    return 'Exited $code';
  }

  @override
  String get terminalFailureShellNotFound => 'Shell not found';

  @override
  String get terminalFailureFolderNotFound => 'Folder not found';

  @override
  String get terminalFailureUnavailable => 'Terminal is unavailable';

  @override
  String get terminalDisclosure =>
      'Commands here run as you, outside the agent\'s approval flow. Output is shown as is and is not redacted for secrets.';

  @override
  String get terminalLinkTitle => 'Open link?';

  @override
  String get terminalLinkRefusal => 'Only http and https links can be opened.';

  @override
  String get projectFilesNoFolder =>
      'Select a project or start a session to browse its files.';

  @override
  String get projectFilesFolderMissing => 'The project folder does not exist.';

  @override
  String get projectFilesFolderUnreadable =>
      'The project folder cannot be read.';

  @override
  String projectFilesRootOutside(String root) {
    return '$root — outside the project folder';
  }

  @override
  String get projectFilesGitHidden => '.git is never shown';

  @override
  String get projectFilesRefresh => 'Refresh';

  @override
  String get projectFilesSelectFile => 'Select a file to preview it.';

  @override
  String get projectFilesFolderReadFailed => 'Cannot read this folder.';

  @override
  String projectFilesMore(int count) {
    return '… $count more';
  }

  @override
  String get projectFilesFailureOutsideRoot =>
      'This file is outside the project folder.';

  @override
  String get projectFilesFailureNotFound => 'The file was not found.';

  @override
  String get projectFilesFailureUnreadable => 'The file cannot be read.';

  @override
  String get projectFilesFailureInvalidPath => 'The file path is not valid.';

  @override
  String projectFilesSizeKilobytes(int count) {
    return '$count KB';
  }

  @override
  String projectFilesSizeMegabytes(int count) {
    return '$count MB';
  }

  @override
  String get settingsShellPendingApproval =>
      'Agent is waiting for your approval';

  @override
  String get settingsShellBackToSession => 'Back to session';

  @override
  String workbenchTokenRejected(int status) {
    return 'The agent rejected the token (HTTP $status).';
  }

  @override
  String workbenchTokenRequired(int status) {
    return 'The agent requires a token (HTTP $status).';
  }
}
