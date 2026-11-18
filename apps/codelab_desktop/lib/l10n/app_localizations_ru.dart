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

  @override
  String get settingsGeneralAgentDefaultsTitle => 'Умолчания агента';

  @override
  String get settingsGeneralAgentDefaultsCaption =>
      'Изменения сохраняются для всех проектов.';

  @override
  String settingsGeneralSharedInfo(String home) {
    return 'Общие с CLI codelab. Строки с тегом «Общая» берутся из реестра настроек агента и сохраняются в $home/config.yaml; их показывает и codelab /settings.';
  }

  @override
  String get settingsGeneralTagShared => 'Общая';

  @override
  String get settingsGeneralNotSet => 'Не задано';

  @override
  String get settingsGeneralAppliesAfterRestart =>
      '(применится после перезапуска)';

  @override
  String settingsGeneralOverriddenBy(String source) {
    return 'Этот проект переопределяет значение ($source).';
  }

  @override
  String get settingsGeneralRefusalSecret =>
      'Измените командой codelab secret set.';

  @override
  String get settingsGeneralRefusalMasked =>
      'Значение содержит секрет; измените его в файле конфигурации.';

  @override
  String settingsGeneralRefusalExternal(String source) {
    return 'Задано источником $source; изменить здесь нельзя.';
  }

  @override
  String get settingsGeneralRefusalOther =>
      'Эту настройку здесь изменить нельзя.';

  @override
  String settingsGeneralHintIntMin(String min) {
    return 'Введите целое число не меньше $min.';
  }

  @override
  String settingsGeneralHintIntRange(String min, String max) {
    return 'Введите целое число от $min до $max.';
  }

  @override
  String get settingsGeneralHintInt => 'Введите целое число.';

  @override
  String get settingsGeneralHintNumber => 'Введите число.';

  @override
  String get settingsGeneralHintDuration =>
      'Введите длительность, например 500ms, 30s, 2m или 1h.';

  @override
  String get settingsGeneralSaved => 'Сохранено.';

  @override
  String get settingsGeneralTailAfterRestart =>
      'Применится после «Перезапустить агента».';

  @override
  String get settingsGeneralTailWhenStarts => 'Применится при запуске агента.';

  @override
  String settingsGeneralSavedOverridden(String source, String effective) {
    return 'Сохранено для всех проектов; $source переопределяет значение: агент использует $effective.';
  }

  @override
  String settingsGeneralSavedUnverified(String home) {
    return 'Сохранено в $home/config.yaml.';
  }

  @override
  String get settingsGeneralConflict =>
      'Файл конфигурации изменился на диске; страница перечитана. Повторите правку.';

  @override
  String get settingsGeneralRejected => 'Конфигурация не сохранена.';

  @override
  String settingsGeneralReadOnlyRemote(String origin) {
    return 'Только чтение: агент работает на $origin. Измените его настройки на том хосте: codelab config set.';
  }

  @override
  String settingsGeneralReadOnlyManaged(String agent) {
    return 'Настройками агента управляет $agent.';
  }

  @override
  String get settingsGeneralUnreadable =>
      'Не удаётся прочитать конфигурацию агента.';

  @override
  String get settingsSearchKeywordsGeneral =>
      'язык, бюджет, шаги, сжатие, субагент, уровень журнала, запуск, открывать, игнорируемые, о программе, версия, лицензия, диагностика';
}
