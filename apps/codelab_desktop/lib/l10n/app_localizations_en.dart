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
}
