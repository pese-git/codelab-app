// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for Russian (`ru`).
class AppLocalizationsRu extends AppLocalizations {
  AppLocalizationsRu([String locale = 'ru']) : super(locale);

  @override
  String get settingsPageGeneralTitle => 'Общие';

  @override
  String get settingsLanguageTitle => 'Язык';

  @override
  String get settingsLanguageSystem => 'Как в системе';

  @override
  String get settingsLanguageEnglish => 'English';

  @override
  String get settingsLanguageRussian => 'Русский';

  @override
  String get settingsLanguageSaveFailed =>
      'Не удалось сохранить язык. После перезапуска CodeLab будет использовать прежний язык.';

  @override
  String get settingsGroupAgent => 'Агент';

  @override
  String get settingsGroupApp => 'Приложение';

  @override
  String get settingsPageConnectionTitle => 'Подключение';

  @override
  String get settingsPageProvidersTitle => 'Провайдеры';

  @override
  String get settingsPageMcpServersTitle => 'MCP-серверы';

  @override
  String get settingsPageAgentsAndModesTitle => 'Агенты и режимы';

  @override
  String get settingsPagePermissionsAndToolsTitle => 'Разрешения и инструменты';

  @override
  String get settingsPageRedactionTitle => 'Маскирование';

  @override
  String get settingsPageSkillsAndExtensionsTitle => 'Навыки и расширения';

  @override
  String get settingsPageCodeAndWebTitle => 'Код и веб';

  @override
  String get settingsPageAppearanceTitle => 'Оформление';

  @override
  String get settingsPageKeyboardTitle => 'Клавиатура';

  @override
  String get settingsGeneralSectionInterface => 'Интерфейс';

  @override
  String get settingsLanguageSaveRetry => 'Повторить';

  @override
  String get agentSettingLabel_budget_max_steps => 'Макс. шагов';

  @override
  String get agentSettingDescription_budget_max_steps =>
      'Запросов к модели за ход.';

  @override
  String get agentSettingLabel_budget_max_tokens => 'Макс. токенов';

  @override
  String get agentSettingDescription_budget_max_tokens =>
      'Сумма входных и выходных токенов за ход.';

  @override
  String get agentSettingLabel_budget_max_cost => 'Макс. стоимость';

  @override
  String get agentSettingDescription_budget_max_cost =>
      'USD за ход; работает только при известных ценах.';

  @override
  String get agentSettingLabel_budget_max_duration => 'Макс. длительность';

  @override
  String get agentSettingDescription_budget_max_duration =>
      'Время хода без ожидания одобрений.';

  @override
  String get agentSettingLabel_subagents_enabled => 'Субагенты';

  @override
  String get agentSettingDescription_subagents_enabled =>
      'Разрешить агенту запускать субагентов (только новые сессии).';

  @override
  String get agentSettingLabel_subagents_max_depth => 'Макс. глубина';

  @override
  String get agentSettingDescription_subagents_max_depth =>
      'Насколько глубоко могут вкладываться субагенты (только новые сессии).';

  @override
  String get agentSettingLabel_subagents_max_concurrent => 'Макс. одновременно';

  @override
  String get agentSettingDescription_subagents_max_concurrent =>
      'Субагентов, работающих одновременно в одном дереве сессии.';

  @override
  String get agentSettingLabel_subagents_max_per_turn => 'Макс. за ход';

  @override
  String get agentSettingDescription_subagents_max_per_turn =>
      'Субагентов, запущенных за ход сессии.';

  @override
  String get agentSettingLabel_subagents_max_steps => 'Макс. шагов';

  @override
  String get agentSettingDescription_subagents_max_steps =>
      'Запросов к модели одного субагента.';

  @override
  String get agentSettingLabel_subagents_max_tokens => 'Макс. токенов';

  @override
  String get agentSettingDescription_subagents_max_tokens =>
      'Входных и выходных токенов одного субагента.';

  @override
  String get agentSettingLabel_subagents_max_cost => 'Макс. стоимость';

  @override
  String get agentSettingDescription_subagents_max_cost =>
      'USD одного субагента; работает только при известных ценах.';

  @override
  String get agentSettingLabel_subagents_max_duration => 'Макс. длительность';

  @override
  String get agentSettingDescription_subagents_max_duration =>
      'Время одного субагента без ожидания одобрений.';

  @override
  String get agentSettingLabel_subagents_report_max_bytes => 'Размер отчёта';

  @override
  String get agentSettingDescription_subagents_report_max_bytes =>
      'Наибольший отчёт субагента в байтах.';

  @override
  String get agentSettingLabel_subagents_progress_interval =>
      'Интервал прогресса';

  @override
  String get agentSettingDescription_subagents_progress_interval =>
      'Наименьшая пауза между строками прогресса вызова субагента.';

  @override
  String get agentSettingLabel_subagents_heartbeat_interval =>
      'Интервал сигнала';

  @override
  String get agentSettingDescription_subagents_heartbeat_interval =>
      'Пауза, после которой молчащий вызов субагента сообщает, что он жив.';

  @override
  String get agentSettingLabel_subagents_cancel_grace => 'Время на отмену';

  @override
  String get agentSettingDescription_subagents_cancel_grace =>
      'Сколько вызов ждёт остановки субагентов после отмены.';

  @override
  String get agentSettingLabel_compaction_enabled => 'Автоматическое сжатие';

  @override
  String get agentSettingDescription_compaction_enabled =>
      'Автоматически сжимать контекст, когда он разрастается.';

  @override
  String get agentSettingLabel_logging_level => 'Уровень журнала';

  @override
  String get agentSettingDescription_logging_level =>
      'Подробность журнала агента.';
}
