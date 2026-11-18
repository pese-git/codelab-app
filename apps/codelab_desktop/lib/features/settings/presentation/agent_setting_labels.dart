import '../../../l10n/app_localizations.dart';

/// Подпись ключа реестра на языке интерфейса (design.md change
/// `add-app-general-page`, D2).
///
/// Почему таблица, а не поиск по идентификатору: `gen-l10n` создаёт типизи-
/// рованные геттеры, динамического доступа к сообщению по строке у него нет.
/// Состав ключей совпадает с таблицей классификации `agent_defaults_rows.dart`
/// (владелец `general`); тест `agent_defaults_rows_test.dart` сверяет сообщения
/// ARB с реестром, а новый ключ без подписи падает здесь на `null`, и страница
/// показывает сам ключ, чтобы строка не пропала молча.
///
/// Как использовать: `agentSettingLabelOf(context.l10n, 'budget.max_steps')`.
String? agentSettingLabelOf(AppLocalizations l10n, String key) => switch (key) {
  'budget.max_steps' => l10n.agentSettingLabel_budget_max_steps,
  'budget.max_tokens' => l10n.agentSettingLabel_budget_max_tokens,
  'budget.max_cost' => l10n.agentSettingLabel_budget_max_cost,
  'budget.max_duration' => l10n.agentSettingLabel_budget_max_duration,
  'subagents.enabled' => l10n.agentSettingLabel_subagents_enabled,
  'subagents.max_depth' => l10n.agentSettingLabel_subagents_max_depth,
  'subagents.max_concurrent' => l10n.agentSettingLabel_subagents_max_concurrent,
  'subagents.max_per_turn' => l10n.agentSettingLabel_subagents_max_per_turn,
  'subagents.max_steps' => l10n.agentSettingLabel_subagents_max_steps,
  'subagents.max_tokens' => l10n.agentSettingLabel_subagents_max_tokens,
  'subagents.max_cost' => l10n.agentSettingLabel_subagents_max_cost,
  'subagents.max_duration' => l10n.agentSettingLabel_subagents_max_duration,
  'subagents.report_max_bytes' =>
    l10n.agentSettingLabel_subagents_report_max_bytes,
  'subagents.progress_interval' =>
    l10n.agentSettingLabel_subagents_progress_interval,
  'subagents.heartbeat_interval' =>
    l10n.agentSettingLabel_subagents_heartbeat_interval,
  'subagents.cancel_grace' => l10n.agentSettingLabel_subagents_cancel_grace,
  'compaction.enabled' => l10n.agentSettingLabel_compaction_enabled,
  'logging.level' => l10n.agentSettingLabel_logging_level,
  _ => null,
};

/// Описание ключа реестра на языке интерфейса — вторая строка строки
/// страницы (D2); `null` у ключа без сообщения.
String? agentSettingDescriptionOf(AppLocalizations l10n, String key) =>
    switch (key) {
      'budget.max_steps' => l10n.agentSettingDescription_budget_max_steps,
      'budget.max_tokens' => l10n.agentSettingDescription_budget_max_tokens,
      'budget.max_cost' => l10n.agentSettingDescription_budget_max_cost,
      'budget.max_duration' => l10n.agentSettingDescription_budget_max_duration,
      'subagents.enabled' => l10n.agentSettingDescription_subagents_enabled,
      'subagents.max_depth' => l10n.agentSettingDescription_subagents_max_depth,
      'subagents.max_concurrent' =>
        l10n.agentSettingDescription_subagents_max_concurrent,
      'subagents.max_per_turn' =>
        l10n.agentSettingDescription_subagents_max_per_turn,
      'subagents.max_steps' => l10n.agentSettingDescription_subagents_max_steps,
      'subagents.max_tokens' =>
        l10n.agentSettingDescription_subagents_max_tokens,
      'subagents.max_cost' => l10n.agentSettingDescription_subagents_max_cost,
      'subagents.max_duration' =>
        l10n.agentSettingDescription_subagents_max_duration,
      'subagents.report_max_bytes' =>
        l10n.agentSettingDescription_subagents_report_max_bytes,
      'subagents.progress_interval' =>
        l10n.agentSettingDescription_subagents_progress_interval,
      'subagents.heartbeat_interval' =>
        l10n.agentSettingDescription_subagents_heartbeat_interval,
      'subagents.cancel_grace' =>
        l10n.agentSettingDescription_subagents_cancel_grace,
      'compaction.enabled' => l10n.agentSettingDescription_compaction_enabled,
      'logging.level' => l10n.agentSettingDescription_logging_level,
      _ => null,
    };
