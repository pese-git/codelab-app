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
  String get workbenchApprovalCancelled => 'Cancelled';

  @override
  String get workbenchApprovalResolved => 'Resolved';

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
  String workbenchRestartMessageEmbedded(int count, String sessions) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count running sessions',
      one: '$count running session',
    );
    return 'Restart the embedded agent? This interrupts $_temp0: $sessions. Queued prompts stay.';
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
  String usageTurnLabel(int index, String title) {
    return '$index · “$title”';
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

  @override
  String get commonSave => 'Save';

  @override
  String get commonRemove => 'Remove';

  @override
  String get commonBack => 'Back';

  @override
  String get commonNext => 'Next';

  @override
  String get commonDone => 'Done';

  @override
  String get commonEdit => 'Edit';

  @override
  String get commonCheck => 'Check';

  @override
  String get commonDefault => 'Default';

  @override
  String get commonContinue => 'Continue';

  @override
  String get connectionAddProfile => 'Add profile';

  @override
  String get connectionSectionProfiles => 'Profiles';

  @override
  String get connectionSectionBehavior => 'Behavior';

  @override
  String get connectionProfilesHelp =>
      'Shared with codelab_cli through profiles.json in \$CODELAB_HOME. The default profile is used when the agent starts, until you choose another with Use.';

  @override
  String get connectionJoinCliTitle => 'Join a session started in the CLI';

  @override
  String get connectionJoinCliBody =>
      'On the host run codelab-agent serve --ws <port>; the CLI connects with codelab -a <profile>. Choose the same WebSocket profile here; its sessions appear in the sidebar.';

  @override
  String get connectionBadgeCurrent => 'Current';

  @override
  String get connectionBadgeSelected => 'Selected';

  @override
  String get connectionStatusConnecting => 'Connecting…';

  @override
  String get connectionStatusConnected => 'Connected';

  @override
  String get connectionStatusFailed => 'Failed';

  @override
  String get connectionRowUse => 'Use';

  @override
  String get connectionRowRename => 'Rename';

  @override
  String get connectionRowUseAnotherFirst => 'Use another profile first.';

  @override
  String get connectionRowNotSaved => 'Current connection (not saved)';

  @override
  String get connectionRenameName => 'Name';

  @override
  String get connectionEmbeddedAgentTitle => 'Embedded agent';

  @override
  String get connectionEmbeddedAgentSummary =>
      'Runs inside CodeLab; no separate process.';

  @override
  String get connectionTokenNone => 'No token';

  @override
  String connectionTokenFromEnv(String variable) {
    return 'From $variable';
  }

  @override
  String tokenEnvNotSet(String name) {
    return '$name is not set in CodeLab\'s environment.';
  }

  @override
  String connectionTokenSecret(String name) {
    return 'Token secret $name';
  }

  @override
  String connectionTokenSecretSet(String backend) {
    return '$backend · set';
  }

  @override
  String connectionTokenSecretMissing(String backend) {
    return '$backend · missing';
  }

  @override
  String get connectionTokenUnsupported =>
      'unrecognized token reference (not supported in this version)';

  @override
  String connectionReadOnlyTitle(String origin) {
    return 'Read-only: this agent runs on $origin';
  }

  @override
  String get settingsRemoteHostHint =>
      'Change providers and MCP on that host: codelab provider add, codelab mcp add, codelab config set.';

  @override
  String get connectionIgnoredDefault =>
      'Profile \"default\" in profiles.json is ignored: default is the built-in agent. Remove it with codelab profiles remove default.';

  @override
  String get connectionIgnoredDefaultRemoveTitle =>
      'Remove the ignored \"default\" profile?';

  @override
  String get connectionIgnoredDefaultRemoveDetails =>
      'Only the \"default\" entry is deleted from profiles.json; other profiles stay.';

  @override
  String connectionUnreadableWithPath(String path, String reason) {
    return 'Cannot read $path: $reason. Fix or remove the file; CodeLab will not overwrite it.';
  }

  @override
  String connectionUnreadableWithoutPath(String reason) {
    return 'Cannot use the profiles: $reason.';
  }

  @override
  String get connectionUnreadableUnsupported =>
      'the file has an unsupported version or an invalid structure';

  @override
  String connectionUnreadableCannotRead(String errorType) {
    return 'the file cannot be read ($errorType)';
  }

  @override
  String get connectionFailureSaveFailed =>
      'Could not save the change. Try again.';

  @override
  String connectionFailureTokenNotDeleted(String name) {
    return 'The profile was removed, but the stored token $name was not deleted. Remove it with codelab secret delete $name.';
  }

  @override
  String connectionRemoveTitle(String name) {
    return 'Remove profile $name?';
  }

  @override
  String get connectionRemoveDetails =>
      'The entry is deleted from profiles.json. Environment variables and other settings are not touched.';

  @override
  String connectionRemoveDeleteToken(String name) {
    return 'Also delete the stored token $name';
  }

  @override
  String get connectionReconnect => 'Reconnect';

  @override
  String get connectionRestartButton => 'Restart';

  @override
  String get connectionRestartHint => 'Starts when you open a project.';

  @override
  String connectionRestartDescription(String subject) {
    return 'Reconnects $subject and reloads open sessions. A running turn is interrupted; queued prompts stay.';
  }

  @override
  String get connectionRestartDescriptionEmbedded =>
      'Reconnects the embedded agent and reloads open sessions. A running turn is interrupted; queued prompts stay.';

  @override
  String get connectionRestartSubjectWindow => 'the profile of this window';

  @override
  String connectionRestartToUse(String subject) {
    return 'Restart $subject to use it.';
  }

  @override
  String get connectionRestartToUseEmbedded =>
      'Restart the agent to switch to the embedded agent.';

  @override
  String get addProfileTitle => 'Add connection profile';

  @override
  String addProfileSubtitle(String path, String command) {
    return 'Saved to $path and shared with codelab_cli as $command.';
  }

  @override
  String get addProfileFieldType => 'Type';

  @override
  String get addProfileFieldName => 'Name';

  @override
  String get addProfileFieldCommand => 'Command';

  @override
  String get addProfileFieldArguments => 'Arguments';

  @override
  String get addProfileFieldFolder => 'Folder';

  @override
  String get addProfileFieldEnvironment => 'Environment';

  @override
  String get addProfileFieldToken => 'Token';

  @override
  String get addProfileFieldAfterSaving => 'After saving';

  @override
  String get addProfileTypeSemantics => 'Profile type';

  @override
  String get addProfileTypeStdio => 'Local stdio';

  @override
  String get addProfileTypeStdioNote =>
      'Starts the agent as a child process per window and talks ACP over stdin/stdout.';

  @override
  String get addProfileTypeWebSocketNote =>
      'Connects to codelab-agent serve --ws on this or another machine.';

  @override
  String get addProfileIdCannotChange => '· cannot change after saving';

  @override
  String get addProfileNamePlaceholder => 'devbox 2';

  @override
  String get addProfileArgumentsNote =>
      'Parsed like a shell: quotes and escapes work.';

  @override
  String get addProfileRunInProject => 'Run in the project folder';

  @override
  String get addProfileUseByDefault => 'Use by default';

  @override
  String get addProfileUsedWhenAgentStarts => 'Used when the agent starts.';

  @override
  String get addProfileTokenNone => 'No token';

  @override
  String get addProfileTokenStored => 'Use stored secret';

  @override
  String get addProfileTokenNew => 'Store a new token';

  @override
  String get addProfileTokenEnv => 'From environment variable';

  @override
  String get addProfileTokenPaste => 'Paste the token';

  @override
  String get addProfileTokenEnvNote =>
      'CodeLab reads the token from this environment variable when it connects. Token values are not saved in profiles.json.';

  @override
  String get addProfileTokenEnvFinderNote =>
      'Apps opened from Finder do not see variables set in your shell profile.';

  @override
  String addProfileStoredSecretsHint(String backend) {
    return 'No stored secrets in $backend.';
  }

  @override
  String addProfileNewTokenHint(String name, String backend) {
    return 'Saved as $name in $backend. The value is never shown again or written to profiles.json.';
  }

  @override
  String addProfileSecretStoreReadOnly(String backend) {
    return 'Secret store $backend is read-only.';
  }

  @override
  String get addProfileWarningTokenPlaintext =>
      'ws:// to another machine: the token is sent unencrypted.';

  @override
  String get addProfileWarningTrafficPlaintext =>
      'ws:// to another machine: traffic is sent unencrypted.';

  @override
  String get addProfilePlaintextTitle => 'Unencrypted connection';

  @override
  String addProfilePlaintextWithToken(String origin) {
    return 'The token for $origin will travel in clear text. Use wss:// if the host supports it.';
  }

  @override
  String addProfilePlaintextWithoutToken(String origin) {
    return 'Prompts and files sent to $origin will travel in clear text. Use wss:// if the host supports it.';
  }

  @override
  String get addProfileSaveAnyway => 'Save anyway';

  @override
  String get addProfileErrorLabelEmpty => 'Enter a name.';

  @override
  String get addProfileErrorIdEmpty => 'Id is required.';

  @override
  String addProfileErrorIdReserved(String id) {
    return '\"$id\" is reserved for the built-in agent.';
  }

  @override
  String addProfileErrorIdTaken(String id) {
    return 'A profile with id \"$id\" already exists.';
  }

  @override
  String get addProfileErrorIdInvalid =>
      'Use lowercase letters, digits, \".\", \"_\" and \"-\" (up to 64 characters).';

  @override
  String get addProfileErrorCommandEmpty =>
      'Enter the command that starts the agent.';

  @override
  String get addProfileErrorArgsInvalid => 'Arguments have an unclosed quote.';

  @override
  String get addProfileErrorUrlInvalid => 'Use ws:// or wss:// with a host.';

  @override
  String get addProfileErrorUrlUserInfo =>
      'Remove the user name and password from the URL; use the Token setting instead.';

  @override
  String get addProfileErrorTokenEnvNameInvalid =>
      'Variable name: letters, digits and \"_\", not starting with a digit.';

  @override
  String get addProfileErrorTokenSecretNameInvalid =>
      'Secret name: lowercase letters, digits and . _ / -, up to 128 characters.';

  @override
  String get addProfileErrorTokenSecretEmpty => 'Enter the token.';

  @override
  String get addProfileErrorTokenSecretIdInvalid =>
      'This id cannot name a stored token; avoid \"..\".';

  @override
  String addProfileErrorTokenSecretExists(String name, String backend) {
    return 'A stored token $name already exists in $backend. Choose it with \"Use stored secret\" or remove it with codelab secret delete.';
  }

  @override
  String get addProfileSavedTitle => 'Profile saved';

  @override
  String addProfileSavedMessage(String id) {
    return 'Added to profiles.json as $id';
  }

  @override
  String get addProfileSavedUsedByDefault => ' · used by default';

  @override
  String get addProfileSavedNote =>
      'The running agent is unchanged. Select it with Use in the profile row; Restart agent applies it.';

  @override
  String get addProfileAddAnother => 'Add another';

  @override
  String get addProfileFailureProfile =>
      'Could not save the profile. Try again.';

  @override
  String get addProfileFailureSecret => 'Could not store the token. Try again.';

  @override
  String addProfileFailureOrphanedToken(String backend, String name) {
    return 'The profile was not saved; the token stays in $backend as $name. Remove it with codelab secret delete $name.';
  }

  @override
  String get secretStoreReadOnly => 'The secret store is read-only.';

  @override
  String addProfileErrorEnvSecretLike(String key, String syntax) {
    return '$key looks like a secret. Set it in the system environment or reference it from the agent config as $syntax.';
  }

  @override
  String get providersAdd => 'Add provider';

  @override
  String get providersDefaultModel => 'Default model';

  @override
  String get providersUsedByNewSessions => 'Used by new sessions.';

  @override
  String providersActiveInSession(String model) {
    return 'Active in this session: $model';
  }

  @override
  String get providersChooseModel => 'Choose a model';

  @override
  String providersKeyStorage(String backend) {
    return 'Key storage: $backend';
  }

  @override
  String get providersKeyStorageDescription =>
      'Only key names and presence are read — values never enter the app';

  @override
  String get providersStorageWritable => 'writable';

  @override
  String get providersStorageReadOnly => 'read-only';

  @override
  String providersKeysInOpenFile(String path) {
    return 'Keys are stored in an open file $path (mode 0600).';
  }

  @override
  String get providersConfigured => 'Configured providers';

  @override
  String get providersEmpty =>
      'No providers yet. The embedded agent needs one to run a turn.';

  @override
  String providersConfigFile(String path) {
    return 'Config file: $path';
  }

  @override
  String get providersRemoveHelp =>
      'Remove asks to confirm with “Also delete the stored key”; removing the default provider asks for a “New default model”. Rows defined in the project file are not editable here.';

  @override
  String providersReadOnlyTitle(String origin) {
    return 'Read-only: this agent runs on $origin.';
  }

  @override
  String providersNotManaged(String agent) {
    return 'Provider settings are managed by $agent.';
  }

  @override
  String get providersUnreadable =>
      'Cannot read the agent config. Fix or remove the file; CodeLab will not overwrite it.';

  @override
  String get providersProblemNoHome =>
      'The CodeLab home folder is not available.';

  @override
  String get providersProblemCannotReadSettings =>
      'Cannot read the agent settings.';

  @override
  String get providersProblemUserConfig =>
      'The user config.yaml cannot be read.';

  @override
  String get providersUnknownKind => 'Unknown kind';

  @override
  String providersModelCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count models',
      one: '$count model',
    );
    return '$_temp0';
  }

  @override
  String providersDefinedIn(String path) {
    return 'defined in $path';
  }

  @override
  String get providersDefinedInEnvironment => 'defined in the environment';

  @override
  String get providersSourceEnvironment => 'Environment';

  @override
  String providersKeyLabelInStore(String backend) {
    return 'Key: in $backend';
  }

  @override
  String providersKeyLabelMissing(String backend) {
    return 'Key: missing in $backend';
  }

  @override
  String providersKeyLabelEnvSet(String name) {
    return 'Key: env $name (set)';
  }

  @override
  String providersKeyLabelEnvNotSet(String name) {
    return 'Key: env $name (not set)';
  }

  @override
  String get providersKeyLabelLiteral => 'Key: in config file (plain text)';

  @override
  String get providersKeyLabelNone => 'No key';

  @override
  String providersKeyInStore(String backend, String name) {
    return 'In $backend as $name';
  }

  @override
  String providersKeyNotStored(String backend, String name) {
    return 'Not stored in $backend as $name';
  }

  @override
  String providersKeyEnvSet(String name) {
    return 'Environment variable $name (set)';
  }

  @override
  String providersKeyEnvNotSet(String name) {
    return 'Environment variable $name (not set)';
  }

  @override
  String get providersKeyLiteral => 'In the config file (plain text)';

  @override
  String get providersKeyHintLiteral =>
      'The key is written in config.yaml. Move it to the secret store: codelab secret migrate.';

  @override
  String settingsKeyUnencryptedToHost(String host) {
    return 'The key is sent unencrypted to $host.';
  }

  @override
  String providersCheckUnavailable(String kind) {
    return 'Check is not available for $kind providers yet.';
  }

  @override
  String get providersRemoveLast =>
      'The agent needs at least one provider. Add another provider first.';

  @override
  String get providersRefusalNotEditable =>
      'This provider is defined in a read-only file. Change it there.';

  @override
  String get providersRefusalSeveralFiles =>
      'This provider is defined in several config files. Change it there.';

  @override
  String get providersRefusalNewDefault => 'Choose a new default model.';

  @override
  String get providersRefusalDefaultOverridden =>
      'The default model is set in a file CodeLab does not write. Change it there first.';

  @override
  String get providersRefusalChanged =>
      'The provider settings changed. Review the page and try again.';

  @override
  String get providersCheckNotChecked => 'not checked';

  @override
  String get providersCheckNotCheckedYet => 'Not checked yet';

  @override
  String get providersCheckRunning => 'checking…';

  @override
  String get providersCheckRunningDetail => 'Checking…';

  @override
  String providersCheckOkLabel(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count models',
      one: '$count model',
    );
    return 'ok, $_temp0';
  }

  @override
  String providersCheckOkDetail(String time, int count, int ms) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count models',
      one: '$count model',
    );
    return '$time · $_temp0 · $ms ms';
  }

  @override
  String providersCheckFailedDetail(String time, String label) {
    return '$time · $label';
  }

  @override
  String providersCheckFailedDetailStatus(
    String time,
    String label,
    int status,
  ) {
    return '$time · $label (HTTP $status)';
  }

  @override
  String get providersCheckUnauthorized => 'unauthorized';

  @override
  String get providersCheckNotFound => 'not found';

  @override
  String get providersCheckUnreachable => 'unreachable';

  @override
  String get providersCheckTimeout => 'timeout';

  @override
  String get providersCheckTlsError => 'TLS error';

  @override
  String get providersCheckBadResponse => 'bad response';

  @override
  String get providersCheckKeyMissing => 'Key: missing';

  @override
  String get providersCheckKeyMissingDetail =>
      'Not checked: the key is missing';

  @override
  String get providersRowKey => 'Key';

  @override
  String get providersRowLastCheck => 'Last check';

  @override
  String get providersRowSource => 'Source';

  @override
  String providersRemoveTitle(String id) {
    return 'Remove provider $id?';
  }

  @override
  String get providersRemoveDetails =>
      'The provider is removed from the config file. Sessions that use its models keep running until the agent reloads.';

  @override
  String get providersRemoveDeleteKey => 'Also delete the stored key';

  @override
  String get providersRemoveNewDefault => 'New default model';

  @override
  String get providersBannerDefaultModelSaved => 'Default model saved.';

  @override
  String providersBannerRemoved(String id) {
    return 'Provider $id removed.';
  }

  @override
  String providersBannerRemovedKeyDeleted(String id) {
    return 'Provider $id removed. Its stored key was deleted.';
  }

  @override
  String providersBannerRemovedKeyKept(String id, String secret) {
    return 'Provider $id removed. The stored key $secret is kept because other settings still use it.';
  }

  @override
  String providersBannerRemovedKeyFailed(String id, String secret) {
    return 'Provider $id removed, but its stored key could not be deleted. Delete it with: codelab secret delete $secret';
  }

  @override
  String get configConflict =>
      'The config changed on disk, so nothing was saved. The page was reloaded; review it and try again.';

  @override
  String configNotSavedRejected(String issues) {
    return 'The config was not saved: $issues';
  }

  @override
  String configNotSavedInlineSecret(String key) {
    return 'The config was not saved: $key must not hold a literal secret.';
  }

  @override
  String get configNotSavedPlain => 'The config was not saved.';

  @override
  String configNotSavedErrorType(String errorType) {
    return 'The config was not saved ($errorType).';
  }

  @override
  String get providersBannerCannotOpenWizard =>
      'Cannot open the provider wizard: the agent config cannot be read.';

  @override
  String get providersBannerSavedNextStart =>
      'Saved. The agent uses it the next time it starts.';

  @override
  String providersBannerSaved(String id) {
    return 'Provider $id saved.';
  }

  @override
  String providersBannerSavedKeyRestart(String id) {
    return 'Provider $id saved. The new key is used after Restart agent (Settings › Connection).';
  }

  @override
  String providersBannerSavedModelsRestart(String id) {
    return 'Provider $id saved. Its models are available after Restart agent (Settings › Connection).';
  }

  @override
  String get wizardTitleAdd => 'Add provider';

  @override
  String wizardTitleEdit(String id) {
    return 'Edit provider $id';
  }

  @override
  String get wizardStepApiType => 'API type';

  @override
  String get wizardStepBaseUrl => 'Base URL';

  @override
  String get wizardStepKey => 'Key';

  @override
  String get wizardStepCheck => 'Check';

  @override
  String get wizardStepModel => 'Model';

  @override
  String get wizardStepReview => 'Review';

  @override
  String get wizardSummaryType => 'Type';

  @override
  String get wizardSummaryProvider => 'Provider';

  @override
  String get wizardSummaryFile => 'File';

  @override
  String get wizardPresetOllama => 'Ollama (local, no key)';

  @override
  String get wizardPresetCustomOpenAi => 'Custom OpenAI-compatible endpoint';

  @override
  String get wizardPresetCustomAnthropic =>
      'Custom Anthropic-compatible endpoint';

  @override
  String get wizardTypeCustomOpenAi => 'Custom OpenAI-compatible';

  @override
  String get wizardTypeCustomAnthropic => 'Custom Anthropic-compatible';

  @override
  String wizardSummaryKeyStore(String backend, String name) {
    return 'Store in $backend as $name';
  }

  @override
  String wizardSummaryKeyUseStored(String name) {
    return 'Use the stored key $name';
  }

  @override
  String get wizardKeepCurrentKey => 'Keep the current key';

  @override
  String wizardSummaryKeyEnv(String name) {
    return 'Read from environment variable ($name)';
  }

  @override
  String wizardPlanKeySecret(String name, String backend) {
    return 'secret \"$name\" ($backend)';
  }

  @override
  String get wizardPlanKeyKept => 'kept as is';

  @override
  String wizardPlanKeyEnv(String name) {
    return 'environment variable $name';
  }

  @override
  String get wizardPlanKeyNone => 'none';

  @override
  String wizardFailKeyRejectedStatus(int status) {
    return 'Key rejected ($status)';
  }

  @override
  String get wizardFailKeyRejected => 'Key rejected';

  @override
  String wizardFailNotFound(int status) {
    return 'Model list not found ($status)';
  }

  @override
  String get wizardFailUnreachable => 'Server unreachable';

  @override
  String wizardFailTimeout(int seconds) {
    return 'Timed out after $seconds s';
  }

  @override
  String get wizardFailTls => 'TLS error';

  @override
  String wizardFailUnexpectedStatus(int status) {
    return 'Unexpected response ($status)';
  }

  @override
  String get wizardFailUnexpected => 'Unexpected response';

  @override
  String get wizardFailNotFoundNote =>
      'The server answered, but GET /models does not exist. OpenAI-compatible servers usually live under /v1.';

  @override
  String get wizardKeyUseStored => 'Use the stored key';

  @override
  String get wizardKeyReplace => 'Replace it';

  @override
  String wizardKeyStore(String backend, String name) {
    return 'Store in $backend as \"$name\"';
  }

  @override
  String get wizardKeyEnv => 'Read from environment variable';

  @override
  String wizardKeyEnvNamed(String name) {
    return 'Read from environment variable ($name)';
  }

  @override
  String get wizardKeySourceLabel => 'API key source';

  @override
  String get wizardKeyFieldLabel => 'API key';

  @override
  String get wizardKeyEnvFieldLabel => 'Variable name';

  @override
  String get wizardErrorAddressInvalid => 'Enter an http or https address.';

  @override
  String get wizardErrorAddressUserInfo =>
      'Remove the user name and password from the address.';

  @override
  String get wizardErrorKeyEmpty => 'Enter the API key.';

  @override
  String wizardErrorKeyAlreadyStored(String name, String backend) {
    return 'A stored key $name already exists in $backend.';
  }

  @override
  String get wizardErrorNothingToKeep => 'There is no stored key to keep.';

  @override
  String get wizardErrorEnvVarEmpty => 'Enter the environment variable name.';

  @override
  String get wizardErrorContextWindow =>
      'Context window must be a positive number.';

  @override
  String get wizardErrorMaxOutput =>
      'Max output tokens must be a positive number.';

  @override
  String get wizardErrorProviderId =>
      'Provider id must be unused and match [a-z0-9_-]+.';

  @override
  String get wizardErrorTargetUnavailable => 'This target is not available.';

  @override
  String get wizardRefusalProviderExists =>
      'A provider with this id already exists.';

  @override
  String get wizardRefusalProviderMissing =>
      'The provider is no longer in the config.';

  @override
  String get wizardRefusalNotEditable => 'This provider cannot be edited here.';

  @override
  String get wizardRefusalSeveralFiles =>
      'This provider is defined in several config files.';

  @override
  String get wizardRefusalLayerUnreadable => 'The config file cannot be read.';

  @override
  String get wizardKeyNoticeLiteral =>
      'The key is written in config.yaml. Choose where to keep it instead.';

  @override
  String wizardNotVerified(String reason) {
    return 'Not verified: $reason';
  }

  @override
  String get wizardNotVerifiedUnreachable => 'unreachable';

  @override
  String get wizardNotVerifiedTimeout => 'timeout';

  @override
  String get wizardInsecureConfirm => 'Use http anyway';

  @override
  String get wizardChecking => 'Checking the address and the key…';

  @override
  String get wizardContinueQuestion => 'How do you want to continue?';

  @override
  String wizardUseAddress(String address) {
    return 'Use $address';
  }

  @override
  String get wizardEnterModelManually => 'Enter the model manually';

  @override
  String get wizardModelId => 'Model id';

  @override
  String get wizardSkipWarning =>
      'The address and the key are not verified, and the model list is not available. You will enter the model yourself.';

  @override
  String get wizardSkipConfirm => 'Continue without check';

  @override
  String get wizardSaveWithoutCheck => 'Save without check';

  @override
  String get wizardModelNotChecked =>
      'The model list was not checked: enter the model id.';

  @override
  String get wizardModelFilter => 'Model (type to filter)';

  @override
  String get wizardModelManual => 'Enter model id manually';

  @override
  String wizardLimitsOf(String model) {
    return 'Limits of $model';
  }

  @override
  String get wizardContextWindow => 'Context window';

  @override
  String get wizardMaxOutputTokens => 'Max output tokens (optional)';

  @override
  String get wizardMakeDefault => 'Make default model';

  @override
  String get wizardProjectOnly => 'This project only';

  @override
  String get wizardSaving => 'Saving…';

  @override
  String get wizardReviewConflict =>
      'Config changed on disk — review and save again';

  @override
  String wizardSaveKeyReplaced(String name) {
    return 'The stored key $name was already replaced.';
  }

  @override
  String wizardSaveKeyStillStored(String name) {
    return 'The new key $name is still in the secret store. Delete it with: codelab secret delete $name';
  }

  @override
  String get wizardKeyNone => 'No key';

  @override
  String get agentSettingLabel_budget_max_steps => 'Max steps';

  @override
  String get agentSettingDescription_budget_max_steps =>
      'Model requests per turn.';

  @override
  String get agentSettingLabel_budget_max_tokens => 'Max tokens';

  @override
  String get agentSettingDescription_budget_max_tokens =>
      'Sum of input and output tokens per turn.';

  @override
  String get agentSettingLabel_budget_max_cost => 'Max cost';

  @override
  String get agentSettingDescription_budget_max_cost =>
      'USD per turn; works only with known prices.';

  @override
  String get agentSettingLabel_budget_max_duration => 'Max duration';

  @override
  String get agentSettingDescription_budget_max_duration =>
      'Turn time without waiting for approvals.';

  @override
  String get agentSettingLabel_subagents_enabled => 'Subagents';

  @override
  String get agentSettingDescription_subagents_enabled =>
      'Let the agent start subagents (new sessions only).';

  @override
  String get agentSettingLabel_subagents_max_depth => 'Max depth';

  @override
  String get agentSettingDescription_subagents_max_depth =>
      'How deep subagents may nest (new sessions only).';

  @override
  String get agentSettingLabel_subagents_max_concurrent => 'Max concurrent';

  @override
  String get agentSettingDescription_subagents_max_concurrent =>
      'Subagents working at the same time in one session tree.';

  @override
  String get agentSettingLabel_subagents_max_per_turn => 'Max per turn';

  @override
  String get agentSettingDescription_subagents_max_per_turn =>
      'Subagents started per turn of the session.';

  @override
  String get agentSettingLabel_subagents_max_steps => 'Max steps';

  @override
  String get agentSettingDescription_subagents_max_steps =>
      'Model requests of one subagent.';

  @override
  String get agentSettingLabel_subagents_max_tokens => 'Max tokens';

  @override
  String get agentSettingDescription_subagents_max_tokens =>
      'Input and output tokens of one subagent.';

  @override
  String get agentSettingLabel_subagents_max_cost => 'Max cost';

  @override
  String get agentSettingDescription_subagents_max_cost =>
      'USD of one subagent; works only with known prices.';

  @override
  String get agentSettingLabel_subagents_max_duration => 'Max duration';

  @override
  String get agentSettingDescription_subagents_max_duration =>
      'Time of one subagent without waiting for approvals.';

  @override
  String get agentSettingLabel_subagents_report_max_bytes => 'Report size';

  @override
  String get agentSettingDescription_subagents_report_max_bytes =>
      'Largest report a subagent returns, in bytes.';

  @override
  String get agentSettingLabel_subagents_progress_interval =>
      'Progress interval';

  @override
  String get agentSettingDescription_subagents_progress_interval =>
      'Shortest pause between progress lines of a subagent call.';

  @override
  String get agentSettingLabel_subagents_heartbeat_interval =>
      'Heartbeat interval';

  @override
  String get agentSettingDescription_subagents_heartbeat_interval =>
      'Pause after which a silent subagent call reports that it is alive.';

  @override
  String get agentSettingLabel_subagents_cancel_grace => 'Cancel grace';

  @override
  String get agentSettingDescription_subagents_cancel_grace =>
      'How long a call waits for subagents to stop after a cancel.';

  @override
  String get agentSettingLabel_compaction_enabled => 'Automatic compaction';

  @override
  String get agentSettingDescription_compaction_enabled =>
      'Compact the context automatically when it grows.';

  @override
  String get agentSettingLabel_logging_level => 'Log level';

  @override
  String get agentSettingDescription_logging_level =>
      'Verbosity of the agent log.';

  @override
  String get settingsGeneralAgentDefaultsTitle => 'Agent defaults';

  @override
  String get settingsGeneralAgentDefaultsCaption =>
      'Changes are saved for all projects.';

  @override
  String settingsGeneralSharedInfo(String home) {
    return 'Shared with the codelab CLI. Rows marked shared come from the agent\'s settings registry and are saved to $home/config.yaml; codelab /settings shows them too.';
  }

  @override
  String get settingsGeneralTagShared => 'shared';

  @override
  String get settingsGeneralNotSet => 'Not set';

  @override
  String get settingsGeneralAppliesAfterRestart => '(applies after restart)';

  @override
  String settingsGeneralOverriddenBy(String source) {
    return 'This project overrides it ($source).';
  }

  @override
  String get settingsGeneralRefusalSecret =>
      'Change it with codelab secret set.';

  @override
  String get settingsGeneralRefusalMasked =>
      'This value contains a secret; change it in the config file.';

  @override
  String settingsGeneralRefusalExternal(String source) {
    return 'Set by $source; it cannot be changed here.';
  }

  @override
  String get settingsGeneralRefusalOther =>
      'This setting cannot be changed here.';

  @override
  String settingsGeneralHintIntMin(String min) {
    return 'Enter a whole number of $min or greater.';
  }

  @override
  String settingsGeneralHintIntRange(String min, String max) {
    return 'Enter a whole number from $min to $max.';
  }

  @override
  String get settingsGeneralHintInt => 'Enter a whole number.';

  @override
  String get settingsGeneralHintNumber => 'Enter a number.';

  @override
  String get settingsGeneralHintDuration =>
      'Enter a duration like 500ms, 30s, 2m or 1h.';

  @override
  String get settingsGeneralSaved => 'Saved.';

  @override
  String get settingsGeneralTailAfterRestart => 'Applies after Restart agent.';

  @override
  String get settingsGeneralTailWhenStarts => 'Applies when the agent starts.';

  @override
  String settingsGeneralSavedOverridden(String source, String effective) {
    return 'Saved to all projects; $source overrides it: the agent uses $effective.';
  }

  @override
  String settingsGeneralSavedUnverified(String home) {
    return 'Saved to $home/config.yaml.';
  }

  @override
  String get settingsGeneralConflict =>
      'The config file changed on disk; the page was reloaded. Try again.';

  @override
  String get settingsGeneralRejected => 'The config was not saved.';

  @override
  String settingsGeneralReadOnlyRemote(String origin) {
    return 'Read-only: this agent runs on $origin. Change its settings on that host: codelab config set.';
  }

  @override
  String settingsGeneralReadOnlyManaged(String agent) {
    return 'Agent settings are managed by $agent.';
  }

  @override
  String get settingsGeneralUnreadable => 'The agent config cannot be read.';

  @override
  String get settingsGeneralSectionStartup => 'Startup and files';

  @override
  String get settingsGeneralReopenTitle =>
      'Reopen the last project and its tabs';

  @override
  String get settingsGeneralReopenDescription =>
      'On: open the last project and its open sessions. Off: start with recent projects in the sidebar. Applies at the next start.';

  @override
  String get settingsGeneralStartupSaveFailed =>
      'Couldn\'t save this setting. The previous value applies at the next start.';

  @override
  String get settingsGeneralSectionAbout => 'About';

  @override
  String settingsGeneralAboutSubtitle(String platform, String agentVersion) {
    return '$platform · embedded agent $agentVersion';
  }

  @override
  String get settingsGeneralAboutLicense => 'License';

  @override
  String get settingsGeneralAboutConfigFolder => 'Config folder';

  @override
  String get settingsGeneralAboutCopyDiagnostics => 'Copy diagnostics';

  @override
  String get settingsGeneralAboutThirdParty => 'Third-party notices';

  @override
  String get settingsGeneralAboutReleaseNotes => 'Release notes';

  @override
  String get settingsGeneralAboutOpenLogs => 'Open log folder';

  @override
  String get settingsGeneralAboutUpdates =>
      'Updates come from the installer or your package manager — the app does not update itself.';

  @override
  String get settingsGeneralAboutCopied => 'Diagnostics copied.';

  @override
  String get settingsGeneralAboutReleaseNotesFailed =>
      'Couldn\'t open the release notes.';

  @override
  String get settingsGeneralAboutLogsFailed => 'Couldn\'t open the log folder.';

  @override
  String get settingsGeneralUnreadableCannotRead =>
      'Cannot read the agent settings.';

  @override
  String get settingsGeneralUnreadableHome =>
      'The CodeLab home folder is not available.';

  @override
  String get settingsGeneralUnreadableUserLayer =>
      'The user config.yaml cannot be read.';

  @override
  String get settingsGeneralAboutCopyFailed =>
      'Couldn\'t copy the diagnostics.';

  @override
  String get settingsGeneralAboutLoadFailed =>
      'Couldn\'t load the About section.';

  @override
  String get settingsSearchKeywordsConnection =>
      'profile, stdio, websocket, token, restart';

  @override
  String get settingsSearchKeywordsProviders =>
      'provider, model, api key, key storage, base url';

  @override
  String get settingsSearchKeywordsMcpServers => 'mcp, server, tools, headers';

  @override
  String get settingsSearchKeywordsAgentsAndModes =>
      'mode, permission, bypass, plan, effort, reasoning, agent, definition, subagent';

  @override
  String get settingsSearchKeywordsSkillsAndExtensions =>
      'skill, agents.md, context, template, prompt, extension';

  @override
  String get settingsSearchKeywordsGeneral =>
      'language, budget, steps, compaction, subagent, log level, startup, reopen, ignored, about, version, license, diagnostics, telemetry';

  @override
  String get settingsGeneralGroupBudget => 'Budget';

  @override
  String get settingsGeneralGroupAgent => 'Agent';

  @override
  String get settingsGeneralGroupSubagents => 'Subagents';

  @override
  String get settingsGeneralGroupLogging => 'Logging';

  @override
  String get mcpAddServer => 'Add server';

  @override
  String mcpServerCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count servers',
      one: '$count server',
    );
    return '$_temp0';
  }

  @override
  String get mcpCompositionCaption =>
      'Composition from the config · agent status below';

  @override
  String get mcpEmpty => 'No MCP servers yet.';

  @override
  String get mcpNewServer => 'New server';

  @override
  String mcpRemoveTitle(String name) {
    return 'Remove $name?';
  }

  @override
  String get mcpRemoveBody => 'The server is removed from the config file.';

  @override
  String get mcpRemoveSecretsIntro =>
      'These stored secrets will be deleted if nothing else uses them:';

  @override
  String get mcpReconnect => 'Reconnect';

  @override
  String get mcpReloadAll => 'Reload all';

  @override
  String get mcpRefresh => 'Refresh';

  @override
  String get mcpDisableHere => 'Disable here';

  @override
  String get mcpEnableHere => 'Enable here';

  @override
  String get mcpOn => 'On';

  @override
  String get mcpOff => 'Off';

  @override
  String mcpNoteProjectFile(String name) {
    return '$name comes from the project file: it can\'t be edited or removed here; \"Disable here\" writes enabled: false to .codelab/config.local.yaml.';
  }

  @override
  String mcpNoteDisabledHere(String name) {
    return '$name is disabled in .codelab/config.local.yaml. \"Enable here\" removes this override.';
  }

  @override
  String get mcpFieldName => 'Name';

  @override
  String get mcpFieldType => 'Type';

  @override
  String get mcpFieldCommand => 'Command';

  @override
  String get mcpFieldArguments => 'Arguments';

  @override
  String get mcpFieldUrl => 'URL';

  @override
  String get mcpFieldHeaders => 'Headers';

  @override
  String get mcpFieldEnvironment => 'Environment';

  @override
  String get mcpFieldSaveTo => 'Save to';

  @override
  String get mcpArgumentsNote => 'One argument per line.';

  @override
  String get mcpAddHeader => '+ Add header';

  @override
  String get mcpAddVariable => '+ Add variable';

  @override
  String get mcpMoveNote =>
      'To move a server to another file, remove it and add it again.';

  @override
  String get mcpTargetUser => 'User config';

  @override
  String get mcpTargetProject => 'This project only';

  @override
  String get mcpValueSecretPlaceholder => 'Secret value';

  @override
  String get mcpValueStored => 'stored';

  @override
  String get mcpValuePlaceholder => 'Value';

  @override
  String get mcpHiddenHint => 'Hidden — leave empty to keep';

  @override
  String mcpSecretStoredIn(String backend) {
    return 'Secret — stored in $backend';
  }

  @override
  String mcpSecretStoredInAs(String backend, String name) {
    return 'Secret — stored in $backend as $name';
  }

  @override
  String get mcpReplaceTitle => 'A secret with this name is already stored';

  @override
  String get mcpReplaceNewValue =>
      'The new value replaces the secret for every server that refers to it.';

  @override
  String get mcpReplaceRunning =>
      'A running agent keeps the old value until the server reconnects.';

  @override
  String get mcpReplaceConfirm => 'Replace it';

  @override
  String get mcpReplaceKeep => 'Keep it';

  @override
  String get mcpProblemNameInvalid => 'Use a name without spaces, [, ] or \".';

  @override
  String get mcpProblemRenameNotAllowed =>
      'Remove the server and add it again to rename it.';

  @override
  String get mcpProblemNameTaken => 'A server with this name already exists.';

  @override
  String get mcpProblemCommandEmpty => 'Enter the command.';

  @override
  String get mcpProblemUrlInvalid => 'Enter an http or https URL.';

  @override
  String get mcpProblemUrlHasUserinfo =>
      'Remove the user name and password from the URL.';

  @override
  String mcpProblemKeyHasSpaces(String key) {
    return 'Remove spaces around the name $key.';
  }

  @override
  String mcpProblemKeyDuplicate(String key) {
    return 'Two values are named $key.';
  }

  @override
  String get mcpProblemKeyEmpty => 'Enter a name for every value.';

  @override
  String mcpProblemSecretValueEmpty(String key) {
    return 'Enter the secret value for $key.';
  }

  @override
  String mcpProblemSecretNameCollision(String key) {
    return 'Two secret values get the same secret name; rename $key.';
  }

  @override
  String mcpBannerSaved(String server) {
    return 'Server $server saved.';
  }

  @override
  String mcpBannerSavedRestart(String server) {
    return 'Server $server saved. It starts after Restart agent (Settings › Connection).';
  }

  @override
  String mcpBannerEnabledRestart(String server) {
    return 'Server $server enabled. It starts after Restart agent (Settings › Connection).';
  }

  @override
  String mcpBannerRemoved(String server) {
    return 'Server $server removed.';
  }

  @override
  String mcpSecretKept(String name) {
    return '$name is kept: it was not created by this page.';
  }

  @override
  String mcpSecretStillUsed(String name) {
    return '$name is kept because other settings still use it.';
  }

  @override
  String mcpSecretDeleteFailed(String name) {
    return '$name could not be deleted. Delete it with: codelab secret delete $name';
  }

  @override
  String mcpSecretNotStored(String reason) {
    return 'The secret was not stored, so nothing was saved: $reason';
  }

  @override
  String mcpSecretNotRestored(String name) {
    return 'The stored value of $name was already replaced and could not be restored.';
  }

  @override
  String get mcpRefusalChanged =>
      'The MCP settings changed. Review the page and try again.';

  @override
  String get mcpRefusalNotEditable =>
      'This server is defined in a read-only file. Change it there.';

  @override
  String get mcpRefusalNotProject =>
      'Only a server from the project file can be disabled here.';

  @override
  String get mcpRefusalNoProjectTarget =>
      'The project folder is not known, so nothing can be written to .codelab/config.local.yaml.';

  @override
  String get mcpFailSettingsChanged =>
      'The MCP server settings changed. Review the page and try again.';

  @override
  String get mcpFailSecretStore =>
      'The secret store could not be read, so nothing was saved.';

  @override
  String get mcpFailChange => 'The change was not saved because of an error.';

  @override
  String get mcpFailConflict =>
      'The config changed on disk, so nothing was saved. The page was reloaded; review it and try again.';

  @override
  String mcpFailRejected(String issues) {
    return 'The config was not saved: $issues';
  }

  @override
  String get mcpFailConfig => 'The config was not saved because of an error.';

  @override
  String get mcpRejectedAfterSave =>
      'Saved, but the agent rejected the new config';

  @override
  String get mcpRejectedOnOpen => 'The agent rejects the current config';

  @override
  String get mcpConfigInvalid => 'Config: invalid';

  @override
  String get mcpKeepsRunning =>
      'The agent keeps running on the previous config until this is fixed.';

  @override
  String mcpEditServer(String server) {
    return 'Edit $server';
  }

  @override
  String get mcpStatusTitle => 'Agent status';

  @override
  String get mcpColServer => 'SERVER';

  @override
  String get mcpColState => 'STATE';

  @override
  String get mcpColTools => 'TOOLS';

  @override
  String get mcpColLastError => 'LAST ERROR';

  @override
  String get mcpStateConnecting => 'connecting';

  @override
  String get mcpStateConnected => 'connected';

  @override
  String get mcpStateDisabled => 'disabled';

  @override
  String get mcpStateFailed => 'failed';

  @override
  String mcpStateFailedRetry(String seconds) {
    return 'failed · retry in $seconds s';
  }

  @override
  String get mcpStatusUnavailable => 'Open a session to see live status';

  @override
  String mcpStatusLive(String time) {
    return 'Live from the embedded agent · $time';
  }

  @override
  String get mcpStatusFooter =>
      'From the embedded agent. For a stdio or remote agent this panel shows the reply of /mcp list as text.';

  @override
  String get mcpListFailed => '/mcp list did not complete. Try Refresh again.';

  @override
  String get configSourceDefault => 'default';

  @override
  String get configSourceUser => 'user';

  @override
  String get configSourceProject => 'project';

  @override
  String get configSourceLocal => 'local';

  @override
  String get configSourceFile => 'file';

  @override
  String get configSourceConfig => 'config';

  @override
  String get configSourceEnv => 'env';

  @override
  String get mcpSourceThisProject => 'this project';

  @override
  String mcpSourceDefinedIn(String file) {
    return 'defined in $file';
  }

  @override
  String get agentsSaveToTitle => 'Save to';

  @override
  String get agentsSaveToDescription =>
      'One target for the mode and the reasoning effort.';

  @override
  String get agentsTargetAll => 'All projects';

  @override
  String get agentsTargetProject => 'This project only';

  @override
  String get agentsModeSection => 'Default permission mode';

  @override
  String get agentsModeCaption =>
      'New sessions start in it after Restart agent; change it for one session from the composer.';

  @override
  String agentsModeEffective(String mode) {
    return 'Effective: $mode';
  }

  @override
  String agentsModeSource(String source) {
    return 'Source: $source';
  }

  @override
  String agentsModeBlocked(String mode) {
    return '$mode (edits and commands blocked by plan)';
  }

  @override
  String get agentsAutopilotHint =>
      'Only as a launch flag of the agent (codelab-agent serve --permission-mode autopilot); never saved in config.';

  @override
  String agentsModeNarrowed(String mode) {
    return 'This project is not trusted, so its config can only make the mode stricter. New sessions here use $mode.';
  }

  @override
  String agentsEffortTitle(String source) {
    return 'Reasoning effort · $source';
  }

  @override
  String get agentsEffortSection => 'Default reasoning effort';

  @override
  String get agentsEffortDescription =>
      'Sent as a session option only if the model supports reasoning; change it for one session from the composer.';

  @override
  String get agentsBypassTitle => 'Use bypass for new sessions?';

  @override
  String get agentsBypassBody =>
      'Only critical commands, changes to the agent\'s configuration and network tools still ask. Commands run without asking and can reach the network too. Use bypass only in a disposable checkout.';

  @override
  String get agentsBypassConfirm => 'Use bypass';

  @override
  String agentsBannerSaved(String value, String when) {
    String _temp0 = intl.Intl.selectLogic(when, {
      'now': 'Saved. New sessions use $value.',
      'afterRestart': 'Saved. New sessions use $value after Restart agent.',
      'whenAgentStarts':
          'Saved. New sessions use $value when the agent starts.',
      'other': 'Saved. New sessions use $value.',
    });
    return '$_temp0';
  }

  @override
  String agentsBannerOverridden(
    String target,
    String source,
    String value,
    String when,
  ) {
    String _temp0 = intl.Intl.selectLogic(when, {
      'now': 'Saved to $target; $source overrides it: new sessions use $value.',
      'afterRestart':
          'Saved to $target; $source overrides it: new sessions use $value after Restart agent.',
      'whenAgentStarts':
          'Saved to $target; $source overrides it: new sessions use $value when the agent starts.',
      'other':
          'Saved to $target; $source overrides it: new sessions use $value.',
    });
    return '$_temp0';
  }

  @override
  String agentsBannerNarrowed(String target, String value, String when) {
    String _temp0 = intl.Intl.selectLogic(when, {
      'now':
          'Saved to $target; the untrusted project overrides it: new sessions use $value.',
      'afterRestart':
          'Saved to $target; the untrusted project overrides it: new sessions use $value after Restart agent.',
      'whenAgentStarts':
          'Saved to $target; the untrusted project overrides it: new sessions use $value when the agent starts.',
      'other':
          'Saved to $target; the untrusted project overrides it: new sessions use $value.',
    });
    return '$_temp0';
  }

  @override
  String agentsBannerSavedOnly(String target) {
    return 'Saved to $target.';
  }

  @override
  String get agentsBannerBypassStale =>
      'Settings changed while the dialog was open; bypass was not saved.';

  @override
  String get agentsBannerConflict =>
      'The config changed on disk, so nothing was saved. The page was reloaded; review it and try again.';

  @override
  String get agentsBannerNotSaved => 'The config was not saved.';

  @override
  String get agentsBannerTargetUnavailable =>
      'Cannot save: the target config file is not available.';

  @override
  String get agentsReadOnlyHint =>
      'Change its modes and agents on that host: codelab config set, .codelab/agents.';

  @override
  String agentsReadOnlyManaged(String agent) {
    return 'Agent settings are managed by $agent.';
  }

  @override
  String get agentsDefinitionsSection => 'Agent definitions';

  @override
  String get agentsDefinitionsCaption =>
      'Definitions are read when a session is created; choose one for a single session in the composer agent menu.';

  @override
  String get agentsOpenFolder => 'Open folder';

  @override
  String agentsOpenUserFolder(String folder) {
    return 'User definitions ($folder)';
  }

  @override
  String get agentsOpenProjectFolder => 'This project (.codelab/agents)';

  @override
  String get agentsOpenProjectMissing =>
      'Create .codelab/agents in the project to add definitions.';

  @override
  String get agentsReload => 'Reload';

  @override
  String get agentsColName => 'Name';

  @override
  String get agentsColDescription => 'Description';

  @override
  String get agentsColSource => 'Source';

  @override
  String get agentsColAvailableIn => 'Available in';

  @override
  String get agentsColTools => 'Tools';

  @override
  String get agentsColModel => 'Model';

  @override
  String get agentsColStatus => 'Status';

  @override
  String get agentsColPath => 'PATH';

  @override
  String get agentsColMessage => 'MESSAGE';

  @override
  String get agentsBuiltIn => 'built-in';

  @override
  String get agentsAllTools => 'all';

  @override
  String get agentsSessionModel => 'session model';

  @override
  String get agentsStatusAvailable => 'Available';

  @override
  String get agentsStatusOverridden => 'Overridden';

  @override
  String agentsStatusOverriddenBy(String path) {
    return 'Overridden by $path';
  }

  @override
  String get agentsStatusModelNotConfigured => 'Model not configured';

  @override
  String get agentsStatusError => 'Error';

  @override
  String agentsStatusErrorLine(int line) {
    return 'Error · line $line';
  }

  @override
  String get agentsStatusDuplicate => 'Not loaded: duplicate name';

  @override
  String get agentsStatusShadowed => 'Shadowed by project';

  @override
  String get agentsStatusSubagentsOff => 'Subagents off';

  @override
  String get agentsScopeSession => 'session';

  @override
  String get agentsScopeSubagent => 'subagent';

  @override
  String get agentsScopeBoth => 'both';

  @override
  String get agentsErrorTitle => 'Cannot load the definition';

  @override
  String agentsErrorTitleLine(int line) {
    return 'Cannot load the definition · line $line';
  }

  @override
  String get agentsUntrustedTitle => 'Project definitions are not read';

  @override
  String agentsUntrustedBody(String project) {
    return 'Definitions in $project/.codelab/agents are not read: the project is not trusted.';
  }

  @override
  String get agentsUntrustedBodyNoPath =>
      'Project definitions in .codelab/agents are not read: the project is not trusted.';

  @override
  String get agentsTimedOut => 'Agent definitions were not read within 5 s.';

  @override
  String get agentsFailed => 'Agent definitions could not be read.';

  @override
  String get agentsOpenFailedTitle => 'Cannot open the folder';

  @override
  String agentsOpenFailedBody(String label) {
    return 'Could not open $label.';
  }

  @override
  String skillsOpenCodelabTooltipHome(String home) {
    return 'Open the CodeLab home folder: $home';
  }

  @override
  String get skillsOpenCodelabTooltipDefault => 'Open the CodeLab home folder';

  @override
  String skillsOpenCodelabTooltip(String folder) {
    return 'Open $folder';
  }

  @override
  String skillsOpenCodelabTooltipOr(String folder, String home) {
    return 'Open $folder, or $home if it does not exist';
  }

  @override
  String get skillsOpenCodelabButton => 'Open .codelab folder';

  @override
  String get skillsReload => 'Reload';

  @override
  String get skillsNoFolder =>
      'Open a project folder to see the context files, skills and prompt templates the agent uses there.';

  @override
  String get skillsReadOnlyHint =>
      'Its skills, context files and prompt templates are read on that host: codelab-agent config check.';

  @override
  String skillsReadOnlyManaged(String agent) {
    return 'Skills are managed by $agent.';
  }

  @override
  String get skillsBannerSaved => 'Saved';

  @override
  String get skillsBannerNotSaved => 'Not saved';

  @override
  String get skillsBannerCannotOpen => 'Cannot open the folder';

  @override
  String skillsMsgOpenFailed(String path) {
    return 'Could not open $path.';
  }

  @override
  String get skillsMsgSaved =>
      'Saved. New sessions use it; open sessions keep their skills.';

  @override
  String get skillsMsgConflict =>
      'The config changed on disk, so nothing was saved. The page was reloaded; review it and try again.';

  @override
  String skillsMsgRejected(String issues) {
    return 'The config was not saved: $issues';
  }

  @override
  String get skillsMsgNotSaved => 'The config was not saved.';

  @override
  String skillsRefusalNotEditable(String source) {
    return 'Set in $source; edit that file.';
  }

  @override
  String skillsRefusalDisabledByProject(String source) {
    return 'Disabled by the project config ($source).';
  }

  @override
  String skillsRefusalUntrusted(String element) {
    return 'Trust this project to read $element.';
  }

  @override
  String get skillsRefusalUntrustedFolder =>
      'Trust this project to read this folder.';

  @override
  String get skillsRefusalLayerUnreadable =>
      'The config file of this layer cannot be read. Fix it first.';

  @override
  String get skillsUntrustedTitle =>
      'This project is not in trusted_projects, so the agent does not read its skills and prompt templates. Your own skills and AGENTS.md files are shown.';

  @override
  String skillsUntrustedHint(String path) {
    return 'Trust is set in trusted_projects of $path.';
  }

  @override
  String get skillsSectionContext => 'Context files';

  @override
  String get skillsSectionTemplates => 'Prompt templates';

  @override
  String get skillsSectionSkills => 'Skills';

  @override
  String get skillsContextEmpty => 'No AGENTS.md files for this folder.';

  @override
  String get skillsColFile => 'FILE';

  @override
  String get skillsColSize => 'SIZE';

  @override
  String get skillsColCommand => 'COMMAND';

  @override
  String get skillsColSource => 'SOURCE';

  @override
  String get skillsColSkill => 'SKILL';

  @override
  String get skillsColInvokeAs => 'INVOKE AS';

  @override
  String get skillsColOtherAgents => 'SKILLS OF OTHER AGENTS';

  @override
  String get skillsColMessage => 'MESSAGE';

  @override
  String skillsContextTotal(int count, String size) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count files',
      one: '$count file',
    );
    return '$_temp0 · $size';
  }

  @override
  String get skillsContextClaudeAlias =>
      'used because this folder has no AGENTS.md';

  @override
  String get skillsContextOmitted => 'not included (budget)';

  @override
  String skillsContextTruncated(String size) {
    return 'truncated to $size';
  }

  @override
  String get skillsOpen => 'Open';

  @override
  String get skillsTemplatesEmpty => 'No prompt templates.';

  @override
  String get skillsEmpty => 'No skills found.';

  @override
  String get skillsSearchOrder =>
      'Search order: .codelab/skills, then .agents/skills from this folder up to the repository root; then \$CODELAB_HOME/skills, ~/.agents/skills; extra roots last. The nearest overrides the farthest.';

  @override
  String get skillsListFixed =>
      'The list is fixed when a session opens: new and changed skills apply to new sessions.';

  @override
  String get skillsTagCommandOnly => 'Command only';

  @override
  String get skillsInvokeModelOnly => 'Model only';

  @override
  String skillsToggleLabel(String name) {
    return 'Enabled: $name';
  }

  @override
  String get skillsOverridesUser => 'Overrides user skill';

  @override
  String get skillsOverridesProject => 'Overrides project skill';

  @override
  String get skillsOverridesExtra => 'Overrides extra skill';

  @override
  String get skillsOverridesOther => 'Overrides another skill';

  @override
  String skillsExtraRoot(String entry) {
    return '$entry (extra root)';
  }

  @override
  String get skillsUnknownRoot => '(unknown root)';

  @override
  String skillsWarningCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count warnings',
      one: '$count warning',
    );
    return '$_temp0';
  }

  @override
  String skillsConsentRead(String entry) {
    return 'Read $entry';
  }

  @override
  String skillsConsentFound(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count skill folders found.',
      one: '$count skill folder found.',
    );
    return '$_temp0';
  }

  @override
  String get skillsConsentNotCounted =>
      'The number of skill folders is not counted.';

  @override
  String get skillsConsentEveryProject =>
      'Consent applies in every trusted project.';

  @override
  String get skillsConsentAgentsFolder =>
      'The .agents/skills folder of a trusted project is read without consent.';

  @override
  String get skillsPhaseTimedOutContext =>
      'Context files were not read within 5 s.';

  @override
  String get skillsPhaseTimedOutTemplates =>
      'Prompt templates were not read within 5 s.';

  @override
  String get skillsPhaseTimedOutSkills => 'Skills were not read within 5 s.';

  @override
  String skillsPhaseFailedContext(String errorType) {
    return 'Context files could not be read ($errorType).';
  }

  @override
  String skillsPhaseFailedTemplates(String errorType) {
    return 'Prompt templates could not be read ($errorType).';
  }

  @override
  String skillsPhaseFailedSkills(String errorType) {
    return 'Skills could not be read ($errorType).';
  }

  @override
  String skillsPhaseOff(String source) {
    return 'Skills are switched off: skills.enabled is false in $source.';
  }

  @override
  String skillsSizeBytes(String size) {
    return '$size B';
  }

  @override
  String skillsSizeKilobytes(String size) {
    return '$size KB';
  }

  @override
  String skillsSizeMegabytes(String size) {
    return '$size MB';
  }

  @override
  String get settingsProblemCannotReadExtensions =>
      'Cannot read the skills and extensions of this folder.';

  @override
  String get agentsErrorFallbackModel =>
      'The model of this definition is not configured.';

  @override
  String get agentsErrorFallbackDuplicate =>
      'Not loaded: another definition has the same name.';

  @override
  String get agentsErrorFallbackOther => 'The definition cannot be loaded.';

  @override
  String get settingsSearchKeywordsAppearance =>
      'theme, dark, light, mode, color, accent, contrast, json';

  @override
  String get appearanceModeTitle => 'Mode';

  @override
  String get appearanceModeDescription =>
      'Light, dark, or follow the system setting';

  @override
  String get appearanceModeLight => 'Light';

  @override
  String get appearanceModeDark => 'Dark';

  @override
  String appearanceModeSystem(String current) {
    return 'Match system ($current)';
  }

  @override
  String get appearanceSystemLight => 'light';

  @override
  String get appearanceSystemDark => 'dark';

  @override
  String get appearanceAccentTitle => 'Accent color';

  @override
  String get appearanceAccentDescription =>
      'Buttons, selection and focus use the system accent';

  @override
  String get appearanceAccentToggle => 'Use system accent';

  @override
  String get appearanceThemesTitle => 'Color theme';

  @override
  String get appearanceThemeFluentLight => 'Fluent Light';

  @override
  String get appearanceThemeFluentDark => 'Fluent Dark';

  @override
  String get appearanceThemeHighContrast => 'High contrast';

  @override
  String get appearanceKindBuiltInDefault => 'Built-in · default';

  @override
  String get appearanceKindBuiltIn => 'Built-in';

  @override
  String appearanceKindCustom(String base) {
    return 'Custom · extends $base';
  }

  @override
  String get appearanceKindCustomUnknown => 'Custom';

  @override
  String get appearanceTagLightMode => 'Light mode';

  @override
  String get appearanceTagDarkMode => 'Dark mode';

  @override
  String get appearanceTagInvalid => 'Invalid';

  @override
  String appearanceWarningsBadge(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count warnings',
      one: '$count warning',
    );
    return '$_temp0';
  }

  @override
  String get appearanceCustomTitle => 'Custom themes';

  @override
  String get appearanceImportButton => 'Import JSON…';

  @override
  String appearanceIssuesSummary(String name, int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count warnings',
      one: '$count warning',
    );
    return '$name loaded with $_temp0';
  }

  @override
  String appearanceIssuesError(String name) {
    return '$name couldn\'t be loaded';
  }

  @override
  String get appearanceOpenFolder => 'Open folder';

  @override
  String get appearanceReload => 'Reload';

  @override
  String appearanceIssueUnknownKey(
    String file,
    int line,
    int column,
    String key,
  ) {
    return '$file:$line:$column unknown key \"$key\"';
  }

  @override
  String appearanceIssueUnknownKeyHint(String role) {
    return 'Ignored. Did you mean \"$role\"?';
  }

  @override
  String get appearanceIssueUnknownKeyNoHint => 'Ignored — not a theme role.';

  @override
  String appearanceIssueDuplicateKey(
    String file,
    int line,
    int column,
    String key,
  ) {
    return '$file:$line:$column duplicate key \"$key\"';
  }

  @override
  String get appearanceIssueDuplicateKeyHint => 'The last value is used.';

  @override
  String appearanceIssueTerminalColor(
    String file,
    int line,
    int column,
    String value,
  ) {
    return '$file:$line:$column terminal color \"$value\"';
  }

  @override
  String get appearanceIssueTerminalColorHint =>
      'Terminal colors are not used by the app; the role comes from extends.';

  @override
  String appearanceIssueLowContrast(String role, String ratio) {
    return 'Low contrast: $role, $ratio:1';
  }

  @override
  String get appearanceIssueLowContrastHint =>
      'Applied as set. Text roles need 4.5:1.';

  @override
  String get appearanceIssueTooLarge => 'The file is larger than 64 KiB.';

  @override
  String get appearanceIssueNotUtf8 => 'The file is not valid UTF-8.';

  @override
  String get appearanceIssueInvalidJson => 'The file is not valid JSON.';

  @override
  String get appearanceIssueNotAnObject =>
      'The top level must be a JSON object.';

  @override
  String get appearanceIssueMissingName => 'The \"name\" key is missing.';

  @override
  String get appearanceIssueInvalidName =>
      'The theme name must be 1–32 characters: a–z, 0–9 and hyphens.';

  @override
  String get appearanceIssueNameMismatch =>
      'The \"name\" value must match the file name.';

  @override
  String get appearanceIssueReservedName =>
      'The name is taken by a built-in theme.';

  @override
  String get appearanceIssueInvalidExtends =>
      '\"extends\" must be light, dark or high-contrast.';

  @override
  String get appearanceIssueInvalidValue =>
      'The color value is not valid: use #rrggbb, default, an ANSI color name or 256:n.';

  @override
  String get appearanceIssueUnreadable => 'The file could not be read.';

  @override
  String appearanceIssueWithPosition(
    String file,
    int line,
    int column,
    String problem,
  ) {
    return '$file:$line:$column $problem';
  }

  @override
  String appearanceUnsetRoles(int count, String base) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count roles not set',
      one: '$count role not set',
    );
    return '$_temp0 — taken from \"$base\"';
  }

  @override
  String get appearanceUnsetRolesNote => 'For reference, not a warning';

  @override
  String get appearancePreviewTitle => 'Preview';

  @override
  String get appearancePreviewLink => 'Link';

  @override
  String get appearancePreviewDone => 'Done';

  @override
  String get appearancePreviewContext => '84% context';

  @override
  String get appearancePreviewFailed => 'Failed';

  @override
  String get appearanceContrastTitle => 'Contrast on code background';

  @override
  String get appearanceContrastText => 'Text';

  @override
  String get appearanceContrastComment => 'Comment';

  @override
  String get appearanceContrastKeyword => 'Keyword';

  @override
  String get appearanceContrastError => 'Error';

  @override
  String get appearanceContrastPass => 'AA';

  @override
  String get appearanceContrastLow => 'Low';

  @override
  String get appearanceContrastNote =>
      'Text roles need 4.5:1. A role below that still applies, with a warning on its card.';

  @override
  String get appearanceReset => 'Reset';

  @override
  String appearanceUse(String name) {
    return 'Use $name';
  }

  @override
  String appearanceFallback(String name, String builtIn) {
    return '\"$name\" couldn\'t be loaded. Using $builtIn until it is fixed.';
  }

  @override
  String get appearanceSaveFailed =>
      'Couldn\'t save the appearance. CodeLab will use the previous appearance after restart.';

  @override
  String get appearanceSaveRetry => 'Retry';

  @override
  String appearanceImportFailed(String file, String problem) {
    return 'Couldn\'t import $file: $problem';
  }

  @override
  String get appearanceImportFailedGeneric =>
      'Couldn\'t import the theme. Check that the file is readable and try again.';

  @override
  String appearanceReplaceTitle(String name) {
    return 'Replace the theme \"$name\"?';
  }

  @override
  String get appearanceReplaceBody =>
      'A theme with this name is already in the folder. Its file will be replaced.';

  @override
  String get appearanceReplaceConfirm => 'Replace';

  @override
  String appearanceIssuePosition(int line, int column, String problem) {
    return '$line:$column $problem';
  }

  @override
  String appearanceCatalogFailed(String path) {
    return 'Couldn\'t read $path. Custom themes are not shown.';
  }

  @override
  String appearanceIssuesMore(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '… and $count more warnings',
      one: '… and $count more warning',
    );
    return '$_temp0';
  }

  @override
  String get appearanceImportPickerFailed => 'Couldn\'t open the file dialog.';

  @override
  String get appearanceImportSourceChanged =>
      'The file changed after you chose it. Choose it again.';

  @override
  String get settingsKeyboardTitle => 'Keyboard shortcuts';

  @override
  String get settingsKeyboardSearchPlaceholder => 'Search by action or key';

  @override
  String get settingsKeyboardReadOnly =>
      'Read-only list. Shortcuts are fixed in the app.';

  @override
  String get settingsKeyboardColumnAction => 'Action';

  @override
  String get settingsKeyboardColumnShortcut => 'Shortcut';

  @override
  String get settingsKeyboardColumnWhere => 'Where';

  @override
  String get settingsKeyboardGroupGlobal => 'Global';

  @override
  String get settingsKeyboardGroupNavigation => 'Navigation';

  @override
  String get settingsKeyboardGroupTranscript => 'Transcript';

  @override
  String get settingsKeyboardGroupComposer => 'Composer';

  @override
  String get settingsKeyboardGroupApprovals => 'Approvals';

  @override
  String get settingsKeyboardFooter =>
      'Agent commands have no shortcuts; open them from the command palette.';

  @override
  String settingsKeyboardEmpty(String query) {
    return 'No shortcuts match \"$query\"';
  }

  @override
  String get settingsKeyboardActionCommandPalette => 'Open the command palette';

  @override
  String get settingsKeyboardActionOpenSettings => 'Open settings';

  @override
  String get settingsKeyboardActionCloseOverlay =>
      'Close the command palette, a dialog or a sliding panel';

  @override
  String get settingsKeyboardActionLeaveSettings => 'Back to the workbench';

  @override
  String get settingsKeyboardActionToggleSidebar => 'Show or hide the sidebar';

  @override
  String get settingsKeyboardActionToggleFiles => 'Show or hide the Files pane';

  @override
  String get settingsKeyboardActionFileTreeMove => 'Move through files';

  @override
  String get settingsKeyboardActionFileTreeFold =>
      'Expand or collapse a folder';

  @override
  String get settingsKeyboardActionFileTreeOpen =>
      'Open a file or expand a folder';

  @override
  String get settingsKeyboardActionCancelTurn => 'Cancel the running turn';

  @override
  String get settingsKeyboardActionSend =>
      'Send the message; it is queued while the session is busy';

  @override
  String get settingsKeyboardActionCommandMenuMove => 'Move through commands';

  @override
  String get settingsKeyboardActionCommandMenuRun =>
      'Run the highlighted command';

  @override
  String get settingsKeyboardActionCommandMenuClose => 'Close the command menu';

  @override
  String get settingsKeyboardActionAllowOnce => 'Allow once';

  @override
  String get settingsKeyboardActionAllowAlways => 'Allow always';

  @override
  String get settingsKeyboardActionRejectOnce => 'Reject once';

  @override
  String get settingsKeyboardActionRejectAlways => 'Reject always';

  @override
  String get settingsKeyboardWhereWorkbench => 'Workbench';

  @override
  String get settingsKeyboardWhereWorkbenchProject =>
      'Workbench, when a project is selected';

  @override
  String get settingsKeyboardWhereOverlay =>
      'Command palette, dialog or sliding panel';

  @override
  String get settingsKeyboardWhereSettings => 'Settings';

  @override
  String get settingsKeyboardWhereWorkbenchFiles =>
      'Workbench, when the Files pane is available';

  @override
  String get settingsKeyboardWhereFilesTree => 'Files tree';

  @override
  String get settingsKeyboardWhereFilesTreeFolder => 'Files tree, on a folder';

  @override
  String get settingsKeyboardWhereTurnRunning =>
      'Workbench or composer, while a turn runs';

  @override
  String get settingsKeyboardWhereComposer => 'Composer';

  @override
  String get settingsKeyboardWhereCommandMenu => 'Command menu after /';

  @override
  String get settingsSearchKeywordsKeyboard =>
      'shortcut, hotkey, keybinding, key';

  @override
  String get appearanceIssuesHintUnknownKeys =>
      'Unknown keys were ignored; the theme is applied.';

  @override
  String get appearanceIssuesHintApplied =>
      'The theme is applied with warnings.';

  @override
  String appearanceIssuesHintExtends(String base, String builtIn) {
    return 'Missing roles come from extends: \"$base\" ($builtIn).';
  }

  @override
  String get settingsPageLegalTitle => 'Legal';

  @override
  String get settingsSearchKeywordsLegal =>
      'legal, privacy, terms, license, notices, third-party, telemetry, packages';

  @override
  String get settingsLegalTabsLabel => 'Legal documents';

  @override
  String get settingsLegalTabPrivacy => 'Privacy policy';

  @override
  String get settingsLegalTabTerms => 'Terms of use';

  @override
  String get settingsLegalTabLicense => 'License';

  @override
  String get settingsLegalTabNotices => 'Third-party notices';

  @override
  String settingsLegalSource(String version, String asset) {
    return 'Bundled with CodeLab $version as $asset · readable offline';
  }

  @override
  String get settingsLegalLoadFailed => 'Couldn\'t load this document.';

  @override
  String get settingsLegalLinkFailed => 'Couldn\'t open the link.';

  @override
  String get settingsLegalLicenseAllowed => 'Allowed';

  @override
  String get settingsLegalLicenseAllowedValue =>
      'Use, copy, modify, merge, publish, distribute, sublicense and sell copies';

  @override
  String get settingsLegalLicenseCondition => 'Condition';

  @override
  String get settingsLegalLicenseConditionValue =>
      'Keep the copyright and license notice in copies or substantial portions';

  @override
  String get settingsLegalLicenseNoWarranty => 'No warranty';

  @override
  String get settingsLegalLicenseNoWarrantyValue =>
      'Provided “as is”; the authors are not liable for damages';

  @override
  String get settingsLegalLicenseSummaryNote =>
      'This summary is not the license. The full text below is what applies.';

  @override
  String get settingsLegalComponentsTitle => 'Third-party components';

  @override
  String settingsLegalComponentsText(String link) {
    return 'Open-source packages bundled with CodeLab keep their own licenses. They are listed in $link.';
  }

  @override
  String get settingsLegalNoticesRegister => 'Notices register';

  @override
  String get settingsLegalNoticesCaption =>
      'Entries of the CodeLab third-party notices register, as kept in the repository.';

  @override
  String get settingsLegalPackageLicenses => 'Package licenses';

  @override
  String get settingsLegalPackagesInfo =>
      'Every package the build collected, including development tools of the workspace. A longer list is safe; a missing license would not be.';

  @override
  String get settingsLegalSearchHint => 'Search packages';

  @override
  String get settingsLegalSearchLabel => 'Search packages by name';

  @override
  String get settingsLegalClearSearch => 'Clear search';

  @override
  String settingsLegalPackagesCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count packages',
      one: '$count package',
    );
    return '$_temp0';
  }

  @override
  String settingsLegalPackagesMatched(int matched, int total) {
    String _temp0 = intl.Intl.pluralLogic(
      total,
      locale: localeName,
      other: '$total packages',
      one: '$total package',
    );
    return '$matched of $_temp0';
  }

  @override
  String settingsLegalLicensesCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count licenses',
      one: '$count license',
    );
    return '$_temp0';
  }

  @override
  String get settingsLegalEmptyTitle => 'No packages match';

  @override
  String settingsLegalEmptyText(String query) {
    return 'No package name contains “$query”. The notices register above is not affected by search.';
  }

  @override
  String get settingsGeneralSectionPrivacy => 'Privacy';

  @override
  String get settingsGeneralNoTelemetry => 'No telemetry';

  @override
  String get settingsGeneralNoTelemetryDescription =>
      'The app, the CLI and the agent send no usage analytics or crash reports. Prompts and files go only to the provider and tools you set up.';

  @override
  String get settingsKeyboardWhereApprovalAnywhere =>
      'Workbench, earliest pending approval, if it offers this option';

  @override
  String get settingsKeyboardActionGoToApproval => 'Go to approval';

  @override
  String get settingsKeyboardWhereApprovalPending =>
      'Workbench, while an approval is pending';
}
