import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:intl/intl.dart' as intl;

import 'app_localizations_en.dart';
import 'app_localizations_ru.dart';

// ignore_for_file: type=lint

/// Callers can lookup localized strings with an instance of AppLocalizations
/// returned by `AppLocalizations.of(context)`.
///
/// Applications need to include `AppLocalizations.delegate()` in their app's
/// `localizationDelegates` list, and the locales they support in the app's
/// `supportedLocales` list. For example:
///
/// ```dart
/// import 'l10n/app_localizations.dart';
///
/// return MaterialApp(
///   localizationsDelegates: AppLocalizations.localizationsDelegates,
///   supportedLocales: AppLocalizations.supportedLocales,
///   home: MyApplicationHome(),
/// );
/// ```
///
/// ## Update pubspec.yaml
///
/// Please make sure to update your pubspec.yaml to include the following
/// packages:
///
/// ```yaml
/// dependencies:
///   # Internationalization support.
///   flutter_localizations:
///     sdk: flutter
///   intl: any # Use the pinned version from flutter_localizations
///
///   # Rest of dependencies
/// ```
///
/// ## iOS Applications
///
/// iOS applications define key application metadata, including supported
/// locales, in an Info.plist file that is built into the application bundle.
/// To configure the locales supported by your app, you’ll need to edit this
/// file.
///
/// First, open your project’s ios/Runner.xcworkspace Xcode workspace file.
/// Then, in the Project Navigator, open the Info.plist file under the Runner
/// project’s Runner folder.
///
/// Next, select the Information Property List item, select Add Item from the
/// Editor menu, then select Localizations from the pop-up menu.
///
/// Select and expand the newly-created Localizations item then, for each
/// locale your application supports, add a new item and select the locale
/// you wish to add from the pop-up menu in the Value field. This list should
/// be consistent with the languages listed in the AppLocalizations.supportedLocales
/// property.
abstract class AppLocalizations {
  AppLocalizations(String locale)
    : localeName = intl.Intl.canonicalizedLocale(locale.toString());

  final String localeName;

  static AppLocalizations of(BuildContext context) {
    return Localizations.of<AppLocalizations>(context, AppLocalizations)!;
  }

  static const LocalizationsDelegate<AppLocalizations> delegate =
      _AppLocalizationsDelegate();

  /// A list of this localizations delegate along with the default localizations
  /// delegates.
  ///
  /// Returns a list of localizations delegates containing this delegate along with
  /// GlobalMaterialLocalizations.delegate, GlobalCupertinoLocalizations.delegate,
  /// and GlobalWidgetsLocalizations.delegate.
  ///
  /// Additional delegates can be added by appending to this list in
  /// MaterialApp. This list does not have to be used at all if a custom list
  /// of delegates is preferred or required.
  static const List<LocalizationsDelegate<dynamic>> localizationsDelegates =
      <LocalizationsDelegate<dynamic>>[
        delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
      ];

  /// A list of this localizations delegate's supported locales.
  static const List<Locale> supportedLocales = <Locale>[
    Locale('en'),
    Locale('ru'),
  ];

  /// Заголовок страницы настроек General и пункта навигации.
  ///
  /// In en, this message translates to:
  /// **'General'**
  String get settingsPageGeneralTitle;

  /// Подпись строки выбора языка интерфейса на странице General.
  ///
  /// In en, this message translates to:
  /// **'Language'**
  String get settingsLanguageTitle;

  /// Значение выбора языка: язык системы.
  ///
  /// In en, this message translates to:
  /// **'System'**
  String get settingsLanguageSystem;

  /// Значение выбора языка: английский. Эндоним, не переводить.
  ///
  /// In en, this message translates to:
  /// **'English'**
  String get settingsLanguageEnglish;

  /// Значение выбора языка: русский. Эндоним, не переводить.
  ///
  /// In en, this message translates to:
  /// **'Русский'**
  String get settingsLanguageRussian;

  /// Ошибка на странице General, когда выбранный язык не удалось записать в хранилище. CodeLab — название продукта, не переводить.
  ///
  /// In en, this message translates to:
  /// **'Couldn\'t save the language. CodeLab will use the previous language after restart.'**
  String get settingsLanguageSaveFailed;

  /// Заголовок группы «Agent» в навигации настроек.
  ///
  /// In en, this message translates to:
  /// **'Agent'**
  String get settingsGroupAgent;

  /// Заголовок группы «App» в навигации настроек.
  ///
  /// In en, this message translates to:
  /// **'App'**
  String get settingsGroupApp;

  /// Пункт навигации и заголовок страницы настроек Connection.
  ///
  /// In en, this message translates to:
  /// **'Connection'**
  String get settingsPageConnectionTitle;

  /// Пункт навигации страницы настроек Providers.
  ///
  /// In en, this message translates to:
  /// **'Providers'**
  String get settingsPageProvidersTitle;

  /// Пункт навигации страницы настроек MCP servers. MCP — название протокола, не переводить.
  ///
  /// In en, this message translates to:
  /// **'MCP servers'**
  String get settingsPageMcpServersTitle;

  /// Пункт навигации страницы настроек Agents & modes.
  ///
  /// In en, this message translates to:
  /// **'Agents & modes'**
  String get settingsPageAgentsAndModesTitle;

  /// Пункт навигации страницы настроек Permissions & tools.
  ///
  /// In en, this message translates to:
  /// **'Permissions & tools'**
  String get settingsPagePermissionsAndToolsTitle;

  /// Пункт навигации страницы настроек Redaction (скрытие секретов в тексте).
  ///
  /// In en, this message translates to:
  /// **'Redaction'**
  String get settingsPageRedactionTitle;

  /// Пункт навигации страницы настроек Skills & extensions.
  ///
  /// In en, this message translates to:
  /// **'Skills & extensions'**
  String get settingsPageSkillsAndExtensionsTitle;

  /// Пункт навигации страницы настроек Code & web.
  ///
  /// In en, this message translates to:
  /// **'Code & web'**
  String get settingsPageCodeAndWebTitle;

  /// Пункт навигации страницы настроек Appearance.
  ///
  /// In en, this message translates to:
  /// **'Appearance'**
  String get settingsPageAppearanceTitle;

  /// Пункт навигации страницы настроек Keyboard.
  ///
  /// In en, this message translates to:
  /// **'Keyboard'**
  String get settingsPageKeyboardTitle;

  /// Заголовок секции страницы General, в которой выбирается язык интерфейса.
  ///
  /// In en, this message translates to:
  /// **'Interface'**
  String get settingsGeneralSectionInterface;

  /// Кнопка в предупреждении о сбое записи языка на странице General: повторить запись выбранного языка.
  ///
  /// In en, this message translates to:
  /// **'Retry'**
  String get settingsLanguageSaveRetry;

  /// Строка блока Agent defaults страницы General: подпись ключа конфигурации агента `budget.max_steps`. Текст совпадает с реестром настроек агента; ключ конфигурации не переводится.
  ///
  /// In en, this message translates to:
  /// **'Max steps'**
  String get agentSettingLabel_budget_max_steps;

  /// Строка блока Agent defaults страницы General: описание ключа конфигурации агента `budget.max_steps`. Текст совпадает с реестром настроек агента; ключ конфигурации не переводится.
  ///
  /// In en, this message translates to:
  /// **'Model requests per turn.'**
  String get agentSettingDescription_budget_max_steps;

  /// Строка блока Agent defaults страницы General: подпись ключа конфигурации агента `budget.max_tokens`. Текст совпадает с реестром настроек агента; ключ конфигурации не переводится.
  ///
  /// In en, this message translates to:
  /// **'Max tokens'**
  String get agentSettingLabel_budget_max_tokens;

  /// Строка блока Agent defaults страницы General: описание ключа конфигурации агента `budget.max_tokens`. Текст совпадает с реестром настроек агента; ключ конфигурации не переводится.
  ///
  /// In en, this message translates to:
  /// **'Sum of input and output tokens per turn.'**
  String get agentSettingDescription_budget_max_tokens;

  /// Строка блока Agent defaults страницы General: подпись ключа конфигурации агента `budget.max_cost`. Текст совпадает с реестром настроек агента; ключ конфигурации не переводится.
  ///
  /// In en, this message translates to:
  /// **'Max cost'**
  String get agentSettingLabel_budget_max_cost;

  /// Строка блока Agent defaults страницы General: описание ключа конфигурации агента `budget.max_cost`. Текст совпадает с реестром настроек агента; ключ конфигурации не переводится.
  ///
  /// In en, this message translates to:
  /// **'USD per turn; works only with known prices.'**
  String get agentSettingDescription_budget_max_cost;

  /// Строка блока Agent defaults страницы General: подпись ключа конфигурации агента `budget.max_duration`. Текст совпадает с реестром настроек агента; ключ конфигурации не переводится.
  ///
  /// In en, this message translates to:
  /// **'Max duration'**
  String get agentSettingLabel_budget_max_duration;

  /// Строка блока Agent defaults страницы General: описание ключа конфигурации агента `budget.max_duration`. Текст совпадает с реестром настроек агента; ключ конфигурации не переводится.
  ///
  /// In en, this message translates to:
  /// **'Turn time without waiting for approvals.'**
  String get agentSettingDescription_budget_max_duration;

  /// Строка блока Agent defaults страницы General: подпись ключа конфигурации агента `subagents.enabled`. Текст совпадает с реестром настроек агента; ключ конфигурации не переводится.
  ///
  /// In en, this message translates to:
  /// **'Subagents'**
  String get agentSettingLabel_subagents_enabled;

  /// Строка блока Agent defaults страницы General: описание ключа конфигурации агента `subagents.enabled`. Текст совпадает с реестром настроек агента; ключ конфигурации не переводится.
  ///
  /// In en, this message translates to:
  /// **'Let the agent start subagents (new sessions only).'**
  String get agentSettingDescription_subagents_enabled;

  /// Строка блока Agent defaults страницы General: подпись ключа конфигурации агента `subagents.max_depth`. Текст совпадает с реестром настроек агента; ключ конфигурации не переводится.
  ///
  /// In en, this message translates to:
  /// **'Max depth'**
  String get agentSettingLabel_subagents_max_depth;

  /// Строка блока Agent defaults страницы General: описание ключа конфигурации агента `subagents.max_depth`. Текст совпадает с реестром настроек агента; ключ конфигурации не переводится.
  ///
  /// In en, this message translates to:
  /// **'How deep subagents may nest (new sessions only).'**
  String get agentSettingDescription_subagents_max_depth;

  /// Строка блока Agent defaults страницы General: подпись ключа конфигурации агента `subagents.max_concurrent`. Текст совпадает с реестром настроек агента; ключ конфигурации не переводится.
  ///
  /// In en, this message translates to:
  /// **'Max concurrent'**
  String get agentSettingLabel_subagents_max_concurrent;

  /// Строка блока Agent defaults страницы General: описание ключа конфигурации агента `subagents.max_concurrent`. Текст совпадает с реестром настроек агента; ключ конфигурации не переводится.
  ///
  /// In en, this message translates to:
  /// **'Subagents working at the same time in one session tree.'**
  String get agentSettingDescription_subagents_max_concurrent;

  /// Строка блока Agent defaults страницы General: подпись ключа конфигурации агента `subagents.max_per_turn`. Текст совпадает с реестром настроек агента; ключ конфигурации не переводится.
  ///
  /// In en, this message translates to:
  /// **'Max per turn'**
  String get agentSettingLabel_subagents_max_per_turn;

  /// Строка блока Agent defaults страницы General: описание ключа конфигурации агента `subagents.max_per_turn`. Текст совпадает с реестром настроек агента; ключ конфигурации не переводится.
  ///
  /// In en, this message translates to:
  /// **'Subagents started per turn of the session.'**
  String get agentSettingDescription_subagents_max_per_turn;

  /// Строка блока Agent defaults страницы General: подпись ключа конфигурации агента `subagents.max_steps`. Текст совпадает с реестром настроек агента; ключ конфигурации не переводится.
  ///
  /// In en, this message translates to:
  /// **'Max steps'**
  String get agentSettingLabel_subagents_max_steps;

  /// Строка блока Agent defaults страницы General: описание ключа конфигурации агента `subagents.max_steps`. Текст совпадает с реестром настроек агента; ключ конфигурации не переводится.
  ///
  /// In en, this message translates to:
  /// **'Model requests of one subagent.'**
  String get agentSettingDescription_subagents_max_steps;

  /// Строка блока Agent defaults страницы General: подпись ключа конфигурации агента `subagents.max_tokens`. Текст совпадает с реестром настроек агента; ключ конфигурации не переводится.
  ///
  /// In en, this message translates to:
  /// **'Max tokens'**
  String get agentSettingLabel_subagents_max_tokens;

  /// Строка блока Agent defaults страницы General: описание ключа конфигурации агента `subagents.max_tokens`. Текст совпадает с реестром настроек агента; ключ конфигурации не переводится.
  ///
  /// In en, this message translates to:
  /// **'Input and output tokens of one subagent.'**
  String get agentSettingDescription_subagents_max_tokens;

  /// Строка блока Agent defaults страницы General: подпись ключа конфигурации агента `subagents.max_cost`. Текст совпадает с реестром настроек агента; ключ конфигурации не переводится.
  ///
  /// In en, this message translates to:
  /// **'Max cost'**
  String get agentSettingLabel_subagents_max_cost;

  /// Строка блока Agent defaults страницы General: описание ключа конфигурации агента `subagents.max_cost`. Текст совпадает с реестром настроек агента; ключ конфигурации не переводится.
  ///
  /// In en, this message translates to:
  /// **'USD of one subagent; works only with known prices.'**
  String get agentSettingDescription_subagents_max_cost;

  /// Строка блока Agent defaults страницы General: подпись ключа конфигурации агента `subagents.max_duration`. Текст совпадает с реестром настроек агента; ключ конфигурации не переводится.
  ///
  /// In en, this message translates to:
  /// **'Max duration'**
  String get agentSettingLabel_subagents_max_duration;

  /// Строка блока Agent defaults страницы General: описание ключа конфигурации агента `subagents.max_duration`. Текст совпадает с реестром настроек агента; ключ конфигурации не переводится.
  ///
  /// In en, this message translates to:
  /// **'Time of one subagent without waiting for approvals.'**
  String get agentSettingDescription_subagents_max_duration;

  /// Строка блока Agent defaults страницы General: подпись ключа конфигурации агента `subagents.report_max_bytes`. Текст совпадает с реестром настроек агента; ключ конфигурации не переводится.
  ///
  /// In en, this message translates to:
  /// **'Report size'**
  String get agentSettingLabel_subagents_report_max_bytes;

  /// Строка блока Agent defaults страницы General: описание ключа конфигурации агента `subagents.report_max_bytes`. Текст совпадает с реестром настроек агента; ключ конфигурации не переводится.
  ///
  /// In en, this message translates to:
  /// **'Largest report a subagent returns, in bytes.'**
  String get agentSettingDescription_subagents_report_max_bytes;

  /// Строка блока Agent defaults страницы General: подпись ключа конфигурации агента `subagents.progress_interval`. Текст совпадает с реестром настроек агента; ключ конфигурации не переводится.
  ///
  /// In en, this message translates to:
  /// **'Progress interval'**
  String get agentSettingLabel_subagents_progress_interval;

  /// Строка блока Agent defaults страницы General: описание ключа конфигурации агента `subagents.progress_interval`. Текст совпадает с реестром настроек агента; ключ конфигурации не переводится.
  ///
  /// In en, this message translates to:
  /// **'Shortest pause between progress lines of a subagent call.'**
  String get agentSettingDescription_subagents_progress_interval;

  /// Строка блока Agent defaults страницы General: подпись ключа конфигурации агента `subagents.heartbeat_interval`. Текст совпадает с реестром настроек агента; ключ конфигурации не переводится.
  ///
  /// In en, this message translates to:
  /// **'Heartbeat interval'**
  String get agentSettingLabel_subagents_heartbeat_interval;

  /// Строка блока Agent defaults страницы General: описание ключа конфигурации агента `subagents.heartbeat_interval`. Текст совпадает с реестром настроек агента; ключ конфигурации не переводится.
  ///
  /// In en, this message translates to:
  /// **'Pause after which a silent subagent call reports that it is alive.'**
  String get agentSettingDescription_subagents_heartbeat_interval;

  /// Строка блока Agent defaults страницы General: подпись ключа конфигурации агента `subagents.cancel_grace`. Текст совпадает с реестром настроек агента; ключ конфигурации не переводится.
  ///
  /// In en, this message translates to:
  /// **'Cancel grace'**
  String get agentSettingLabel_subagents_cancel_grace;

  /// Строка блока Agent defaults страницы General: описание ключа конфигурации агента `subagents.cancel_grace`. Текст совпадает с реестром настроек агента; ключ конфигурации не переводится.
  ///
  /// In en, this message translates to:
  /// **'How long a call waits for subagents to stop after a cancel.'**
  String get agentSettingDescription_subagents_cancel_grace;

  /// Строка блока Agent defaults страницы General: подпись ключа конфигурации агента `compaction.enabled`. Текст совпадает с реестром настроек агента; ключ конфигурации не переводится.
  ///
  /// In en, this message translates to:
  /// **'Automatic compaction'**
  String get agentSettingLabel_compaction_enabled;

  /// Строка блока Agent defaults страницы General: описание ключа конфигурации агента `compaction.enabled`. Текст совпадает с реестром настроек агента; ключ конфигурации не переводится.
  ///
  /// In en, this message translates to:
  /// **'Compact the context automatically when it grows.'**
  String get agentSettingDescription_compaction_enabled;

  /// Строка блока Agent defaults страницы General: подпись ключа конфигурации агента `logging.level`. Текст совпадает с реестром настроек агента; ключ конфигурации не переводится.
  ///
  /// In en, this message translates to:
  /// **'Log level'**
  String get agentSettingLabel_logging_level;

  /// Строка блока Agent defaults страницы General: описание ключа конфигурации агента `logging.level`. Текст совпадает с реестром настроек агента; ключ конфигурации не переводится.
  ///
  /// In en, this message translates to:
  /// **'Verbosity of the agent log.'**
  String get agentSettingDescription_logging_level;

  /// Заголовок блока страницы General со строками конфигурации агента, общими с CLI.
  ///
  /// In en, this message translates to:
  /// **'Agent defaults'**
  String get settingsGeneralAgentDefaultsTitle;

  /// Подпись под заголовком блока Agent defaults: запись идёт в пользовательский config.yaml, а не в проект.
  ///
  /// In en, this message translates to:
  /// **'Changes are saved for all projects.'**
  String get settingsGeneralAgentDefaultsCaption;

  /// InfoBar над блоком Agent defaults. {home} — папка CODELAB_HOME с ~ вместо домашнего каталога (путь, не переводить). codelab и codelab /settings — имя и команда CLI, не переводить.
  ///
  /// In en, this message translates to:
  /// **'Shared with the codelab CLI. Rows marked shared come from the agent\'s settings registry and are saved to {home}/config.yaml; codelab /settings shows them too.'**
  String settingsGeneralSharedInfo(String home);

  /// Тег строки реестра настроек агента, которую видит и CLI.
  ///
  /// In en, this message translates to:
  /// **'shared'**
  String get settingsGeneralTagShared;

  /// Значение ключа, который нигде не задан и не имеет умолчания.
  ///
  /// In en, this message translates to:
  /// **'Not set'**
  String get settingsGeneralNotSet;

  /// Пометка у ключа, изменение которого вступает в силу после перезапуска агента.
  ///
  /// In en, this message translates to:
  /// **'(applies after restart)'**
  String get settingsGeneralAppliesAfterRestart;

  /// Подпись строки, значение которой задаёт проектный файл. {source} — слой конфигурации (project, local), не переводить.
  ///
  /// In en, this message translates to:
  /// **'This project overrides it ({source}).'**
  String settingsGeneralOverriddenBy(String source);

  /// Причина, по которой строку нельзя править здесь: ключ хранит имя секрета. codelab secret set — команда CLI, не переводить.
  ///
  /// In en, this message translates to:
  /// **'Change it with codelab secret set.'**
  String get settingsGeneralRefusalSecret;

  /// Причина, по которой строку нельзя править здесь: значение замаскировано.
  ///
  /// In en, this message translates to:
  /// **'This value contains a secret; change it in the config file.'**
  String get settingsGeneralRefusalMasked;

  /// Причина, по которой строку нельзя править здесь: значение пришло из окружения или файла --config. {source} — env или config, не переводить.
  ///
  /// In en, this message translates to:
  /// **'Set by {source}; it cannot be changed here.'**
  String settingsGeneralRefusalExternal(String source);

  /// Причина отказа в правке для ключа, которого нет на странице (запасной текст).
  ///
  /// In en, this message translates to:
  /// **'This setting cannot be changed here.'**
  String get settingsGeneralRefusalOther;

  /// Подсказка формата под полем: целое число с нижней границей.
  ///
  /// In en, this message translates to:
  /// **'Enter a whole number of {min} or greater.'**
  String settingsGeneralHintIntMin(String min);

  /// Подсказка формата под полем: целое число в диапазоне.
  ///
  /// In en, this message translates to:
  /// **'Enter a whole number from {min} to {max}.'**
  String settingsGeneralHintIntRange(String min, String max);

  /// Подсказка формата под полем: целое число без границ.
  ///
  /// In en, this message translates to:
  /// **'Enter a whole number.'**
  String get settingsGeneralHintInt;

  /// Подсказка формата под полем: число.
  ///
  /// In en, this message translates to:
  /// **'Enter a number.'**
  String get settingsGeneralHintNumber;

  /// Подсказка формата под полем: длительность. Примеры 500ms, 30s, 2m, 1h не переводить.
  ///
  /// In en, this message translates to:
  /// **'Enter a duration like 500ms, 30s, 2m or 1h.'**
  String get settingsGeneralHintDuration;

  /// Баннер после записи ключа на странице General.
  ///
  /// In en, this message translates to:
  /// **'Saved.'**
  String get settingsGeneralSaved;

  /// Хвост баннера записи: ключ вступит в силу после действия Restart agent.
  ///
  /// In en, this message translates to:
  /// **'Applies after Restart agent.'**
  String get settingsGeneralTailAfterRestart;

  /// Хвост баннера записи: агент не подключён, ключ вступит в силу при его запуске.
  ///
  /// In en, this message translates to:
  /// **'Applies when the agent starts.'**
  String get settingsGeneralTailWhenStarts;

  /// Баннер записи, значение которой перекрыто другим слоем. {source} — слой (local, project, env, config), {effective} — действующее значение; оба не переводить.
  ///
  /// In en, this message translates to:
  /// **'Saved to all projects; {source} overrides it: the agent uses {effective}.'**
  String settingsGeneralSavedOverridden(String source, String effective);

  /// Баннер записи, после которой конфигурацию не удалось перечитать. {home} — папка CODELAB_HOME с ~, путь не переводить.
  ///
  /// In en, this message translates to:
  /// **'Saved to {home}/config.yaml.'**
  String settingsGeneralSavedUnverified(String home);

  /// Баннер конфликта записи: файл изменили вне app.
  ///
  /// In en, this message translates to:
  /// **'The config file changed on disk; the page was reloaded. Try again.'**
  String get settingsGeneralConflict;

  /// Баннер ошибки записи, когда писатель не назвал проблему.
  ///
  /// In en, this message translates to:
  /// **'The config was not saved.'**
  String get settingsGeneralRejected;

  /// Предупреждение блока Agent defaults для удалённого агента. {origin} — адрес вида wss://host:port, codelab config set — команда CLI; оба не переводить.
  ///
  /// In en, this message translates to:
  /// **'Read-only: this agent runs on {origin}. Change its settings on that host: codelab config set.'**
  String settingsGeneralReadOnlyRemote(String origin);

  /// Предупреждение блока Agent defaults для стороннего агента. {agent} — имя агента, не переводить.
  ///
  /// In en, this message translates to:
  /// **'Agent settings are managed by {agent}.'**
  String settingsGeneralReadOnlyManaged(String agent);

  /// Заголовок InfoBar блока Agent defaults, когда config.yaml не разбирается; ниже проблемы загрузчика.
  ///
  /// In en, this message translates to:
  /// **'The agent config cannot be read.'**
  String get settingsGeneralUnreadable;

  /// Заголовок секции страницы General со строками запуска и файлов.
  ///
  /// In en, this message translates to:
  /// **'Startup and files'**
  String get settingsGeneralSectionStartup;

  /// Подпись строки-переключателя: открывать ли при запуске проект прошлого запуска и его открытые сессии.
  ///
  /// In en, this message translates to:
  /// **'Reopen the last project and its tabs'**
  String get settingsGeneralReopenTitle;

  /// Пояснение строки «Reopen the last project and its tabs».
  ///
  /// In en, this message translates to:
  /// **'On: open the last project and its open sessions. Off: start with recent projects in the sidebar. Applies at the next start.'**
  String get settingsGeneralReopenDescription;

  /// Предупреждение на странице General, когда значение настройки запуска не удалось записать; кнопка Retry повторяет запись.
  ///
  /// In en, this message translates to:
  /// **'Couldn\'t save this setting. The previous value applies at the next start.'**
  String get settingsGeneralStartupSaveFailed;

  /// Заголовок секции страницы General с версией сборки, лицензией и диагностикой.
  ///
  /// In en, this message translates to:
  /// **'About'**
  String get settingsGeneralSectionAbout;

  /// Вторая строка заголовка раздела About: платформа и версия встроенного агента. {platform} — например macOS arm64, {agentVersion} — номер версии; не переводить.
  ///
  /// In en, this message translates to:
  /// **'{platform} · embedded agent {agentVersion}'**
  String settingsGeneralAboutSubtitle(String platform, String agentVersion);

  /// Подпись строки раздела About с названием лицензии. Значение MIT и строка авторского права не переводятся.
  ///
  /// In en, this message translates to:
  /// **'License'**
  String get settingsGeneralAboutLicense;

  /// Подпись строки раздела About с папкой CODELAB_HOME; путь не переводится.
  ///
  /// In en, this message translates to:
  /// **'Config folder'**
  String get settingsGeneralAboutConfigFolder;

  /// Кнопка раздела About: копирует в буфер обмена диагностику без секретов и путей. Сам текст диагностики не переводится.
  ///
  /// In en, this message translates to:
  /// **'Copy diagnostics'**
  String get settingsGeneralAboutCopyDiagnostics;

  /// Кнопка раздела About и заголовок диалога со сторонними уведомлениями и лицензиями пакетов.
  ///
  /// In en, this message translates to:
  /// **'Third-party notices'**
  String get settingsGeneralAboutThirdParty;

  /// Кнопка раздела About: открывает журнал изменений в браузере.
  ///
  /// In en, this message translates to:
  /// **'Release notes'**
  String get settingsGeneralAboutReleaseNotes;

  /// Кнопка раздела About: открывает папку журналов app в файловом менеджере.
  ///
  /// In en, this message translates to:
  /// **'Open log folder'**
  String get settingsGeneralAboutOpenLogs;

  /// InfoBar раздела About об источнике обновлений.
  ///
  /// In en, this message translates to:
  /// **'Updates come from the installer or your package manager — the app does not update itself.'**
  String get settingsGeneralAboutUpdates;

  /// Подтверждение после копирования диагностики в буфер обмена.
  ///
  /// In en, this message translates to:
  /// **'Diagnostics copied.'**
  String get settingsGeneralAboutCopied;

  /// Предупреждение раздела About, когда адрес журнала изменений не открылся.
  ///
  /// In en, this message translates to:
  /// **'Couldn\'t open the release notes.'**
  String get settingsGeneralAboutReleaseNotesFailed;

  /// Предупреждение раздела About, когда папка журналов не открылась.
  ///
  /// In en, this message translates to:
  /// **'Couldn\'t open the log folder.'**
  String get settingsGeneralAboutLogsFailed;

  /// Заголовок списка лицензий пакетов в диалоге сторонних уведомлений.
  ///
  /// In en, this message translates to:
  /// **'Package licenses'**
  String get settingsGeneralAboutPackageLicenses;

  /// Кнопка закрытия диалога сторонних уведомлений.
  ///
  /// In en, this message translates to:
  /// **'Close'**
  String get settingsGeneralAboutClose;

  /// Причина в InfoBar блока Agent defaults: сессия настроек или снимок конфигурации агента не открылись.
  ///
  /// In en, this message translates to:
  /// **'Cannot read the agent settings.'**
  String get settingsGeneralUnreadableCannotRead;

  /// Причина в InfoBar блока Agent defaults: не удалось определить папку CODELAB_HOME. CodeLab — название продукта, не переводить.
  ///
  /// In en, this message translates to:
  /// **'The CodeLab home folder is not available.'**
  String get settingsGeneralUnreadableHome;

  /// Причина в InfoBar блока Agent defaults: пользовательский файл конфигурации не читается. config.yaml — имя файла, не переводить.
  ///
  /// In en, this message translates to:
  /// **'The user config.yaml cannot be read.'**
  String get settingsGeneralUnreadableUserLayer;

  /// Предупреждение раздела About, когда диагностику не удалось скопировать в буфер обмена.
  ///
  /// In en, this message translates to:
  /// **'Couldn\'t copy the diagnostics.'**
  String get settingsGeneralAboutCopyFailed;

  /// Предупреждение вместо раздела About, когда его данные (ресурсы лицензий) не прочитались.
  ///
  /// In en, this message translates to:
  /// **'Couldn\'t load the About section.'**
  String get settingsGeneralAboutLoadFailed;

  /// Кнопка отмены в диалогах рабочего места.
  ///
  /// In en, this message translates to:
  /// **'Cancel'**
  String get commonCancel;

  /// Кнопка закрытия диалога.
  ///
  /// In en, this message translates to:
  /// **'Close'**
  String get commonClose;

  /// Кнопка подтверждения «открыть» в диалогах.
  ///
  /// In en, this message translates to:
  /// **'Open'**
  String get commonOpen;

  /// Кнопка повтора действия: экран подключения, баннер соединения, заметка о сбое хода, заметка панели Usage.
  ///
  /// In en, this message translates to:
  /// **'Retry'**
  String get commonRetry;

  /// Кнопка и пункт «перезапустить агента».
  ///
  /// In en, this message translates to:
  /// **'Restart agent'**
  String get commonRestartAgent;

  /// Название сессии без заголовка и промпта, кнопка стартового экрана, подпись пункта палитры /new.
  ///
  /// In en, this message translates to:
  /// **'New session'**
  String get commonNewSession;

  /// Подпись строки сайдбара для открытой в этом запуске сессии.
  ///
  /// In en, this message translates to:
  /// **'Active'**
  String get workbenchSessionActive;

  /// Название сессии агента без заголовка. Плейсхолдер id — идентификатор сессии, не переводить.
  ///
  /// In en, this message translates to:
  /// **'Session {id}'**
  String workbenchSessionTitleWithId(String id);

  /// Подпись строки сайдбара для сессии из списка агента. Плейсхолдер time — дата и время в формате yyyy-MM-dd HH:mm, не переводить.
  ///
  /// In en, this message translates to:
  /// **'Updated {time}'**
  String workbenchSessionUpdated(String time);

  /// Название группы сайдбара, когда проект не выбран.
  ///
  /// In en, this message translates to:
  /// **'No project'**
  String get workbenchNoProject;

  /// Название текущей сессии в шапке, когда сессии нет.
  ///
  /// In en, this message translates to:
  /// **'No active session'**
  String get workbenchNoActiveSession;

  /// Подсказка под названием текущей сессии и текст стартового экрана без проекта.
  ///
  /// In en, this message translates to:
  /// **'Open a project to start a session.'**
  String get workbenchOpenProjectHint;

  /// Кнопка стартового экрана без проекта; то же название кнопки сайдбара.
  ///
  /// In en, this message translates to:
  /// **'Open folder…'**
  String get workbenchOpenFolder;

  /// Текст стартового экрана с проектом. Плейсхолдер project — имя папки проекта, не переводить.
  ///
  /// In en, this message translates to:
  /// **'Start a new session in {project}.'**
  String workbenchStartNewSessionIn(String project);

  /// Индикатор стартового экрана, пока агент запускается. Плейсхолдер profile — название профиля подключения, не переводить.
  ///
  /// In en, this message translates to:
  /// **'Starting {profile}…'**
  String workbenchStarting(String profile);

  /// Подсказка пустой ленты, когда сессии нет.
  ///
  /// In en, this message translates to:
  /// **'Start a new session to talk to the agent.'**
  String get workbenchTranscriptEmptyNoSession;

  /// Подсказка пустой ленты открытой сессии.
  ///
  /// In en, this message translates to:
  /// **'Send a message to start.'**
  String get workbenchTranscriptEmptySession;

  /// Тип подключения «встроенный агент» в подсказке бейджа соединения и на экране подключения.
  ///
  /// In en, this message translates to:
  /// **'Embedded agent'**
  String get workbenchTransportEmbedded;

  /// Причина на экране сбоя старта, когда ядро клиента её не назвало.
  ///
  /// In en, this message translates to:
  /// **'Could not start the agent.'**
  String get workbenchConnectionStartFailed;

  /// Причина сбоя старта с числом повторов подряд. Плейсхолдеры: reason — причина, repeat — число повторов; не переводить.
  ///
  /// In en, this message translates to:
  /// **'{reason} Failed again ({repeat})'**
  String workbenchConnectionFailedAgain(String reason, int repeat);

  /// Текст баннера, когда встроенному агенту не настроен провайдер модели.
  ///
  /// In en, this message translates to:
  /// **'No model provider is configured for the embedded agent.'**
  String get workbenchNoProviderConfigured;

  /// Кнопка баннера соединения: открыть мастер провайдера.
  ///
  /// In en, this message translates to:
  /// **'Add provider'**
  String get workbenchAddProvider;

  /// Причина отказа подключения и загрузки сессии, когда папки нет на диске. Плейсхолдер path — путь папки, не переводить; «Open folder…» — название кнопки сайдбара.
  ///
  /// In en, this message translates to:
  /// **'Project folder not found: {path}. Choose an existing folder with Open folder….'**
  String workbenchProjectFolderMissing(String path);

  /// Заметка над лентой, когда платформа отказала открыть ссылку из ответа агента.
  ///
  /// In en, this message translates to:
  /// **'Couldn\'t open the link.'**
  String get workbenchLinkOpenFailed;

  /// Заголовок заметки: сессию не удалось привязать к новому соединению.
  ///
  /// In en, this message translates to:
  /// **'Session detached'**
  String get workbenchNoticeSessionDetached;

  /// Тело заметки detached: агент не умеет восстанавливать сессии.
  ///
  /// In en, this message translates to:
  /// **'The agent cannot restore sessions after reconnecting.'**
  String get workbenchNoticeDetachedCannotRestore;

  /// Тело заметки detached: восстановление сессии не удалось. Плейсхолдер id — идентификатор сессии, не переводить.
  ///
  /// In en, this message translates to:
  /// **'Session {id} could not be restored after reconnecting.'**
  String workbenchNoticeDetachedRestoreFailed(String id);

  /// Заметка после переподключения: агент не умеет восстанавливать сессии.
  ///
  /// In en, this message translates to:
  /// **'The agent cannot restore sessions; a new session was started.'**
  String get workbenchNoticeReconnectedCannotRestore;

  /// Заметка после переподключения: восстановление не удалось. Плейсхолдер id — идентификатор сессии, не переводить.
  ///
  /// In en, this message translates to:
  /// **'Session {id} could not be restored; a new session was started.'**
  String workbenchNoticeReconnectedRestoreFailed(String id);

  /// Заметка исхода хода: stopReason max_tokens.
  ///
  /// In en, this message translates to:
  /// **'The model reached its token limit, so the turn ended.'**
  String get workbenchNoticeMaxTokens;

  /// Заметка исхода хода: stopReason max_turn_requests без названного лимита.
  ///
  /// In en, this message translates to:
  /// **'The turn reached the limit of model requests.'**
  String get workbenchNoticeMaxTurnRequests;

  /// Заметка исхода хода: превышен бюджет хода. Плейсхолдер limit — имя лимита с провода (steps, tokens, cost, duration, deadline), не переводить.
  ///
  /// In en, this message translates to:
  /// **'The turn stopped: budget exceeded: {limit}.'**
  String workbenchNoticeBudgetExceeded(String limit);

  /// Заметка исхода хода: stopReason refusal.
  ///
  /// In en, this message translates to:
  /// **'The agent refused to continue.'**
  String get workbenchNoticeRefusal;

  /// Заметка завершённого хода без вывода агента. Плейсхолдер stopReason — значение причины остановки, не переводить; stopReason — имя поля протокола.
  ///
  /// In en, this message translates to:
  /// **'Completed with stopReason {stopReason}.'**
  String workbenchNoticeCompletedWithStopReason(String stopReason);

  /// Заметка завершённого хода, у которого причина остановки неизвестна. stopReason — имя поля протокола.
  ///
  /// In en, this message translates to:
  /// **'Completed with stopReason unknown.'**
  String get workbenchNoticeCompletedStopReasonUnknown;

  /// Заголовок заметки о сбое хода: ошибка входа у провайдера.
  ///
  /// In en, this message translates to:
  /// **'The agent could not sign in to the model provider'**
  String get workbenchFailureAuth;

  /// Заголовок заметки о сбое хода: сеть, таймаут или сервер провайдера.
  ///
  /// In en, this message translates to:
  /// **'The model provider is unavailable'**
  String get workbenchFailureProviderUnavailable;

  /// Заголовок заметки о сбое хода: лимит запросов провайдера.
  ///
  /// In en, this message translates to:
  /// **'The model provider\'s rate limit was reached'**
  String get workbenchFailureRateLimited;

  /// Заголовок заметки о сбое хода: переполнение контекста модели.
  ///
  /// In en, this message translates to:
  /// **'The conversation is too long for the model'**
  String get workbenchFailureOverflow;

  /// Заголовок заметки о сбое хода: связь с агентом потеряна.
  ///
  /// In en, this message translates to:
  /// **'The connection to the agent was lost'**
  String get workbenchFailureConnectionLost;

  /// Общий заголовок заметки о сбое хода.
  ///
  /// In en, this message translates to:
  /// **'The agent could not complete the turn'**
  String get workbenchFailureGeneric;

  /// Тело заметки о потере связи с агентом.
  ///
  /// In en, this message translates to:
  /// **'Retry to continue working with the agent.'**
  String get workbenchFailureConnectionLostBody;

  /// Метка вызова инструмента вида read.
  ///
  /// In en, this message translates to:
  /// **'Read'**
  String get workbenchToolKindRead;

  /// Метка вызова инструмента вида edit.
  ///
  /// In en, this message translates to:
  /// **'Edit'**
  String get workbenchToolKindEdit;

  /// Метка вызова инструмента вида delete.
  ///
  /// In en, this message translates to:
  /// **'Delete'**
  String get workbenchToolKindDelete;

  /// Метка вызова инструмента вида move.
  ///
  /// In en, this message translates to:
  /// **'Move'**
  String get workbenchToolKindMove;

  /// Метка вызова инструмента вида search.
  ///
  /// In en, this message translates to:
  /// **'Search'**
  String get workbenchToolKindSearch;

  /// Метка вызова инструмента вида execute.
  ///
  /// In en, this message translates to:
  /// **'Run'**
  String get workbenchToolKindExecute;

  /// Метка вызова инструмента вида fetch.
  ///
  /// In en, this message translates to:
  /// **'Fetch'**
  String get workbenchToolKindFetch;

  /// Метка решённого одобрения, отменённого без выбора варианта агента (ход отменён, пока запрос ждал решения).
  ///
  /// In en, this message translates to:
  /// **'Cancelled'**
  String get workbenchApprovalCancelled;

  /// Метка решённого одобрения, когда вариант агента не выбран и запрос не отменён; обычно название варианта приходит от агента и не переводится.
  ///
  /// In en, this message translates to:
  /// **'Resolved'**
  String get workbenchApprovalResolved;

  /// Метка вызова инструмента вида think.
  ///
  /// In en, this message translates to:
  /// **'Think'**
  String get workbenchToolKindThink;

  /// Метка вызова инструмента вида switch_mode (смена режима сессии).
  ///
  /// In en, this message translates to:
  /// **'Mode'**
  String get workbenchToolKindSwitchMode;

  /// Строка блока одобрения вызова субагента. Плейсхолдер path — путь субагента в дереве, не переводить.
  ///
  /// In en, this message translates to:
  /// **'{path} wants to run'**
  String workbenchRequesterWantsToRun(String path);

  /// Подпись токенов строки субагента. Плейсхолдер tokens — число в формате ядра клиента, не переводить.
  ///
  /// In en, this message translates to:
  /// **'{tokens} tokens'**
  String workbenchAgentRowTokens(String tokens);

  /// Число вызовов инструментов в строке субагента.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, one{{count} tool call} other{{count} tool calls}}'**
  String workbenchAgentRowToolCalls(int count);

  /// Подпись сегмента строки статуса, когда агент не сообщает расход.
  ///
  /// In en, this message translates to:
  /// **'usage: —'**
  String get workbenchStatusUsageUnknown;

  /// Подсказка сегмента строки статуса, когда агент не сообщает расход.
  ///
  /// In en, this message translates to:
  /// **'agent does not report usage'**
  String get workbenchStatusUsageUnknownTooltip;

  /// Строка подсказки токенов хода: входные токены. Плейсхолдер count — число.
  ///
  /// In en, this message translates to:
  /// **'input {count}'**
  String workbenchStatusTokenInput(int count);

  /// Строка подсказки токенов хода: выходные токены. Плейсхолдер count — число.
  ///
  /// In en, this message translates to:
  /// **'output {count}'**
  String workbenchStatusTokenOutput(int count);

  /// Строка подсказки токенов хода: чтение из кэша. Плейсхолдер count — число.
  ///
  /// In en, this message translates to:
  /// **'cache read {count}'**
  String workbenchStatusTokenCacheRead(int count);

  /// Строка подсказки токенов хода: запись в кэш. Плейсхолдер count — число.
  ///
  /// In en, this message translates to:
  /// **'cache write {count}'**
  String workbenchStatusTokenCacheWrite(int count);

  /// Строка подсказки токенов хода: токены рассуждения. Плейсхолдер count — число.
  ///
  /// In en, this message translates to:
  /// **'reasoning {count}'**
  String workbenchStatusTokenReasoning(int count);

  /// Строка подсказки токенов хода: перечень причин неполноты. Плейсхолдер reasons — причины через запятую.
  ///
  /// In en, this message translates to:
  /// **'approximate: {reasons}'**
  String workbenchStatusApproximate(String reasons);

  /// Причина неполной суммы расхода: агент не прислал usage.
  ///
  /// In en, this message translates to:
  /// **'agent sent no usage for some steps'**
  String get usagePartialNoUsage;

  /// Причина неполной суммы расхода: неизвестна цена.
  ///
  /// In en, this message translates to:
  /// **'price unknown for some steps'**
  String get usagePartialNoPrice;

  /// Причина неполной суммы расхода: часть расхода была до загрузки сессии.
  ///
  /// In en, this message translates to:
  /// **'before the session was loaded'**
  String get usagePartialBeforeLoad;

  /// Подсказка сегмента стоимости строки статуса, когда цена неизвестна.
  ///
  /// In en, this message translates to:
  /// **'price unknown'**
  String get workbenchStatusPriceUnknown;

  /// Сегмент стоимости строки статуса: стоимость хода и сессии. Плейсхолдеры — суммы в формате ядра клиента, не переводить.
  ///
  /// In en, this message translates to:
  /// **'{turn} · session {session}'**
  String workbenchStatusCostWithSession(String turn, String session);

  /// Сегмент заполнения контекста. Плейсхолдер fill — процент в формате ядра, не переводить.
  ///
  /// In en, this message translates to:
  /// **'{fill} context'**
  String workbenchStatusContext(String fill);

  /// Сегмент заполнения контекста с предупреждением о скором сжатии. Плейсхолдер fill — процент.
  ///
  /// In en, this message translates to:
  /// **'{fill} context · compaction soon'**
  String workbenchStatusContextCompactionSoon(String fill);

  /// Заголовок подтверждения: сессия работает в корне диска. Метка security (D14): перевод не смягчает смысл.
  ///
  /// In en, this message translates to:
  /// **'Open session in the disk root?'**
  String get workbenchRootSessionTitle;

  /// Текст подтверждения открытия сессии в корне диска. Плейсхолдер cwd — путь корня, не переводить. Метка security (D14): перевод не смягчает смысл.
  ///
  /// In en, this message translates to:
  /// **'This session runs in the disk root ({cwd}). The agent gets access to the whole disk. Open anyway?'**
  String workbenchRootSessionBody(String cwd);

  /// Заголовок подтверждения перезапуска агента при идущих сессиях.
  ///
  /// In en, this message translates to:
  /// **'Restart agent?'**
  String get workbenchRestartTitle;

  /// Текст подтверждения перезапуска агента. Плейсхолдеры: title — название профиля, count — число идущих сессий, sessions — названия сессий через запятую; не переводить.
  ///
  /// In en, this message translates to:
  /// **'Restart {title}? This interrupts {count, plural, one{{count} running session} other{{count} running sessions}}: {sessions}. Queued prompts stay.'**
  String workbenchRestartMessage(String title, int count, String sessions);

  /// Заголовок панели инспектора в панели Protocol. Содержимое инспектора не переводится.
  ///
  /// In en, this message translates to:
  /// **'Inspector'**
  String get workbenchInspectorTitle;

  /// Тег записи инспектора: одобрение.
  ///
  /// In en, this message translates to:
  /// **'Approval'**
  String get workbenchInspectorCategoryApproval;

  /// Тег записи инспектора: вызов инструмента.
  ///
  /// In en, this message translates to:
  /// **'Tool'**
  String get workbenchInspectorCategoryTool;

  /// Тег записи инспектора: протокол.
  ///
  /// In en, this message translates to:
  /// **'Protocol'**
  String get workbenchInspectorCategoryProtocol;

  /// Тег записи инспектора: диагностика.
  ///
  /// In en, this message translates to:
  /// **'Diagnostic'**
  String get workbenchInspectorCategoryDiagnostic;

  /// Бейдж риска записи инспектора. Плейсхолдер risk — значение риска из ядра клиента, не переводить.
  ///
  /// In en, this message translates to:
  /// **'Risk {risk}'**
  String workbenchInspectorRisk(String risk);

  /// Подпись блока исходных параметров записи инспектора.
  ///
  /// In en, this message translates to:
  /// **'Raw input'**
  String get workbenchInspectorRawInput;

  /// Подпись блока исходного вывода записи инспектора.
  ///
  /// In en, this message translates to:
  /// **'Raw output'**
  String get workbenchInspectorRawOutput;

  /// Заголовок панели журнала отладки. Содержимое журнала не переводится.
  ///
  /// In en, this message translates to:
  /// **'Debug log'**
  String get workbenchDebugLogTitle;

  /// Подсказка кнопки, которая открывает журнал отладки на весь экран.
  ///
  /// In en, this message translates to:
  /// **'Expand'**
  String get workbenchDebugLogExpand;

  /// Подпись команды палитры /new.
  ///
  /// In en, this message translates to:
  /// **'New session'**
  String get paletteNewLabel;

  /// Описание команды палитры /new.
  ///
  /// In en, this message translates to:
  /// **'Start a fresh ACP session.'**
  String get paletteNewDescription;

  /// Подпись команды палитры /plan.
  ///
  /// In en, this message translates to:
  /// **'Plan mode'**
  String get palettePlanLabel;

  /// Описание команды палитры /plan.
  ///
  /// In en, this message translates to:
  /// **'Switch the prompt turn into planning.'**
  String get palettePlanDescription;

  /// Подпись команды палитры /permissions.
  ///
  /// In en, this message translates to:
  /// **'Permissions'**
  String get palettePermissionsLabel;

  /// Описание команды палитры /permissions.
  ///
  /// In en, this message translates to:
  /// **'Open permission mode controls.'**
  String get palettePermissionsDescription;

  /// Подпись команды палитры /logs.
  ///
  /// In en, this message translates to:
  /// **'Logs'**
  String get paletteLogsLabel;

  /// Описание команды палитры /logs.
  ///
  /// In en, this message translates to:
  /// **'Open protocol and diagnostic logs.'**
  String get paletteLogsDescription;

  /// Подпись команды палитры /compact.
  ///
  /// In en, this message translates to:
  /// **'Compact transcript'**
  String get paletteCompactLabel;

  /// Описание команды палитры /compact.
  ///
  /// In en, this message translates to:
  /// **'Prepare the transcript for compaction.'**
  String get paletteCompactDescription;

  /// Подпись команды палитры /reconnect для удалённого агента.
  ///
  /// In en, this message translates to:
  /// **'Reconnect'**
  String get paletteReconnectLabel;

  /// Описание команды палитры /reconnect для удалённого агента.
  ///
  /// In en, this message translates to:
  /// **'Retry the current agent connection.'**
  String get paletteReconnectDescription;

  /// Описание команды палитры /reconnect для локального агента (подпись — «Restart agent»).
  ///
  /// In en, this message translates to:
  /// **'Restart the agent with the selected profile and reload open sessions.'**
  String get paletteRestartDescription;

  /// Подпись команды палитры /files.
  ///
  /// In en, this message translates to:
  /// **'Files'**
  String get paletteFilesLabel;

  /// Описание команды палитры /files.
  ///
  /// In en, this message translates to:
  /// **'Go to the project files panel.'**
  String get paletteFilesDescription;

  /// Подпись команды палитры /agents.
  ///
  /// In en, this message translates to:
  /// **'Agents'**
  String get paletteAgentsLabel;

  /// Описание команды палитры /agents.
  ///
  /// In en, this message translates to:
  /// **'Go to the subagents panel.'**
  String get paletteAgentsDescription;

  /// Подпись команды палитры /usage-pane.
  ///
  /// In en, this message translates to:
  /// **'Usage'**
  String get paletteUsageLabel;

  /// Описание команды палитры /usage-pane.
  ///
  /// In en, this message translates to:
  /// **'Go to the usage panel.'**
  String get paletteUsageDescription;

  /// Предупреждение над лентой: секреты лежат в файле конфигурации встроенного агента. Метка security (D14): перевод не смягчает смысл.
  ///
  /// In en, this message translates to:
  /// **'Secrets are stored in the agent config file.'**
  String get secretMigrationWarning;

  /// Кнопка предупреждения и заголовок диалога переноса секретов.
  ///
  /// In en, this message translates to:
  /// **'Migrate secrets'**
  String get secretMigrationMigrateSecrets;

  /// Ход построения плана переноса секретов.
  ///
  /// In en, this message translates to:
  /// **'Building the migration plan…'**
  String get secretMigrationPlanning;

  /// Ход записи при переносе секретов.
  ///
  /// In en, this message translates to:
  /// **'Moving secrets…'**
  String get secretMigrationApplying;

  /// Пояснение диалога, когда в плане нет пунктов.
  ///
  /// In en, this message translates to:
  /// **'Nothing to migrate.'**
  String get secretMigrationNothing;

  /// Итог переноса секретов.
  ///
  /// In en, this message translates to:
  /// **'Secrets moved. Restart the embedded agent to use them.'**
  String get secretMigrationMoved;

  /// Подсказка кнопки перезапуска, когда агент сменился или закрыт.
  ///
  /// In en, this message translates to:
  /// **'The embedded agent is no longer connected.'**
  String get secretMigrationAgentGone;

  /// Подсказка кнопки перезапуска, пока идёт ход.
  ///
  /// In en, this message translates to:
  /// **'Wait for the current turn to finish.'**
  String get secretMigrationWaitForTurn;

  /// Сбой построения плана переноса. Плейсхолдер errorClass — имя типа ошибки, не переводить.
  ///
  /// In en, this message translates to:
  /// **'Planning failed: {errorClass}.'**
  String secretMigrationPlanFailed(String errorClass);

  /// Сбой переноса секретов. Плейсхолдер errorClass — имя типа ошибки, не переводить.
  ///
  /// In en, this message translates to:
  /// **'Migration failed: {errorClass}.'**
  String secretMigrationApplyFailed(String errorClass);

  /// Кнопка выполнения переноса секретов в диалоге.
  ///
  /// In en, this message translates to:
  /// **'Migrate'**
  String get secretMigrationMigrate;

  /// Заголовок панели Usage.
  ///
  /// In en, this message translates to:
  /// **'This session'**
  String get usageTitle;

  /// Заголовок карточки входных токенов панели Usage.
  ///
  /// In en, this message translates to:
  /// **'Input'**
  String get usageCardInput;

  /// Заголовок карточки выходных токенов панели Usage.
  ///
  /// In en, this message translates to:
  /// **'Output'**
  String get usageCardOutput;

  /// Заголовок карточки стоимости панели Usage и строки бюджета хода.
  ///
  /// In en, this message translates to:
  /// **'Cost'**
  String get usageCardCost;

  /// Заголовок карточки числа ходов и шагов панели Usage.
  ///
  /// In en, this message translates to:
  /// **'Turns · steps'**
  String get usageCardTurns;

  /// Строка под карточкой входных токенов. Плейсхолдеры — числа в формате ядра клиента, не переводить.
  ///
  /// In en, this message translates to:
  /// **'cache read {read} · write {write}'**
  String usageDetailCache(String read, String write);

  /// Строка под карточкой выходных токенов: токены рассуждения. Плейсхолдер count — число.
  ///
  /// In en, this message translates to:
  /// **'reasoning {count}'**
  String usageDetailReasoning(String count);

  /// Строка под карточкой стоимости пустой сессии.
  ///
  /// In en, this message translates to:
  /// **'no usage yet'**
  String get usageDetailNoUsageYet;

  /// Строка под карточкой стоимости, когда цена неизвестна.
  ///
  /// In en, this message translates to:
  /// **'price unknown'**
  String get usageDetailPriceUnknown;

  /// Строка под карточкой ходов. Плейсхолдер average — десятичное число, не переводить.
  ///
  /// In en, this message translates to:
  /// **'avg {average} steps per turn'**
  String usageDetailAverageSteps(String average);

  /// Подпись шага в раскрытом ходе. Плейсхолдеры: number — номер шага, title — название шага; не переводить.
  ///
  /// In en, this message translates to:
  /// **'step {number} · {title}'**
  String usageStepLabel(int number, String title);

  /// Название шага журнала без вызовов инструментов.
  ///
  /// In en, this message translates to:
  /// **'reply'**
  String get usageStepReply;

  /// Название шага журнала, когда вызовы не найдены в ленте.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, one{{count} tool call} other{{count} tool calls}}'**
  String usageStepToolCalls(int count);

  /// Подпись хода в списке «По ходам»: номер хода и заголовок его промпта в кавычках языка. Плейсхолдеры: index — номер хода, title — текст промпта пользователя; не переводить.
  ///
  /// In en, this message translates to:
  /// **'{index} · “{title}”'**
  String usageTurnLabel(int index, String title);

  /// Подпись хода: сколько запусков субагентов было в ходе.
  ///
  /// In en, this message translates to:
  /// **'subagents · {count, plural, one{{count} run} other{{count} runs}}'**
  String usageTurnSubagents(int count);

  /// Название строки таблицы «Per model» с расходом субагентов.
  ///
  /// In en, this message translates to:
  /// **'Subagents'**
  String get usageModelSubagents;

  /// Название строки таблицы «Per model» с расходом сводок контекста.
  ///
  /// In en, this message translates to:
  /// **'Summaries'**
  String get usageModelSummaries;

  /// Число запусков в строке «Subagents» таблицы «Per model».
  ///
  /// In en, this message translates to:
  /// **'{count, plural, one{{count} run} other{{count} runs}}'**
  String usageModelRuns(int count);

  /// Состояние журнала расхода: актуален.
  ///
  /// In en, this message translates to:
  /// **'Ledger: up to date'**
  String get usageLedgerUpToDate;

  /// Состояние журнала расхода: пересобран из журнала сессии.
  ///
  /// In en, this message translates to:
  /// **'rebuilt from journal'**
  String get usageLedgerRebuilt;

  /// Состояние журнала расхода: только в памяти.
  ///
  /// In en, this message translates to:
  /// **'in memory'**
  String get usageLedgerInMemory;

  /// Состояние журнала расхода: не сохранён.
  ///
  /// In en, this message translates to:
  /// **'not saved'**
  String get usageLedgerNotSaved;

  /// Число записей журнала расхода в строке состояния.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, one{{count} record} other{{count} records}}'**
  String usageLedgerRecords(int count);

  /// Причина пересборки журнала в скобках. Плейсхолдер reason — значение с провода, не переводить.
  ///
  /// In en, this message translates to:
  /// **'({reason})'**
  String usageLedgerReason(String reason);

  /// Подсказка строки состояния: штатное обновление кэша журнала. Плейсхолдер reason — значение с провода, не переводить.
  ///
  /// In en, this message translates to:
  /// **'refreshed from the session journal ({reason})'**
  String usageLedgerRefreshedHint(String reason);

  /// Заметка панели Usage: журнал расхода не загрузился.
  ///
  /// In en, this message translates to:
  /// **'Couldn\'t load usage history.'**
  String get usageNoteLedgerFailed;

  /// Заметка панели Usage: агент не объявил журнал расхода.
  ///
  /// In en, this message translates to:
  /// **'This agent does not provide usage history.'**
  String get usageNoteNoLedger;

  /// Заметка панели Usage: файл CSV не записан.
  ///
  /// In en, this message translates to:
  /// **'Couldn\'t save the file.'**
  String get usageNoteSaveFailed;

  /// Заголовок блока бюджета идущего хода.
  ///
  /// In en, this message translates to:
  /// **'This turn'**
  String get usageBudgetThisTurn;

  /// Заголовок блока бюджета завершённого хода.
  ///
  /// In en, this message translates to:
  /// **'Last turn'**
  String get usageBudgetLastTurn;

  /// Строка бюджета хода: шаги.
  ///
  /// In en, this message translates to:
  /// **'Steps'**
  String get usageBudgetSteps;

  /// Строка бюджета хода: токены.
  ///
  /// In en, this message translates to:
  /// **'Tokens'**
  String get usageBudgetTokens;

  /// Строка бюджета хода: время.
  ///
  /// In en, this message translates to:
  /// **'Time'**
  String get usageBudgetTime;

  /// Подсказка строки токенов бюджета хода.
  ///
  /// In en, this message translates to:
  /// **'input + output, including subagents'**
  String get usageBudgetTokensHint;

  /// Пометка строки стоимости бюджета, когда цена модели неизвестна.
  ///
  /// In en, this message translates to:
  /// **'not checked: price unknown'**
  String get usageBudgetCostNote;

  /// Пояснение под блоком бюджета хода.
  ///
  /// In en, this message translates to:
  /// **'When a limit is hit, the turn stops at the next step boundary.'**
  String get usageBudgetFootnote;

  /// Заголовок вкладки терминала. Плейсхолдер number — порядковый номер.
  ///
  /// In en, this message translates to:
  /// **'Terminal {number}'**
  String terminalTabTitle(int number);

  /// Тег вкладки терминала: процесс запускается.
  ///
  /// In en, this message translates to:
  /// **'Starting'**
  String get terminalStatusStarting;

  /// Тег вкладки терминала: процесс работает.
  ///
  /// In en, this message translates to:
  /// **'Running'**
  String get terminalStatusRunning;

  /// Тег вкладки терминала: процесс вышел, код неизвестен.
  ///
  /// In en, this message translates to:
  /// **'Exited'**
  String get terminalStatusExited;

  /// Тег вкладки терминала: процесс вышел с кодом. Плейсхолдер code — код выхода.
  ///
  /// In en, this message translates to:
  /// **'Exited {code}'**
  String terminalStatusExitedWithCode(int code);

  /// Тег вкладки терминала: исполняемого файла оболочки нет.
  ///
  /// In en, this message translates to:
  /// **'Shell not found'**
  String get terminalFailureShellNotFound;

  /// Тег вкладки терминала: рабочей папки нет.
  ///
  /// In en, this message translates to:
  /// **'Folder not found'**
  String get terminalFailureFolderNotFound;

  /// Тег вкладки терминала: псевдотерминал не создан.
  ///
  /// In en, this message translates to:
  /// **'Terminal is unavailable'**
  String get terminalFailureUnavailable;

  /// Предупреждение панели терминала: команды идут вне одобрений агента, вывод не очищается от секретов. Метка security (D14): перевод не смягчает смысл.
  ///
  /// In en, this message translates to:
  /// **'Commands here run as you, outside the agent\'s approval flow. Output is shown as is and is not redacted for secrets.'**
  String get terminalDisclosure;

  /// Заголовок подтверждения открытия ссылки из вывода терминала. Метка security (D14): перевод не смягчает смысл.
  ///
  /// In en, this message translates to:
  /// **'Open link?'**
  String get terminalLinkTitle;

  /// Отказ для ссылки терминала с другой схемой. http и https — схемы адреса, не переводить. Метка security (D14): перевод не смягчает смысл.
  ///
  /// In en, this message translates to:
  /// **'Only http and https links can be opened.'**
  String get terminalLinkRefusal;

  /// Сообщение панели Files без папки проекта.
  ///
  /// In en, this message translates to:
  /// **'Select a project or start a session to browse its files.'**
  String get projectFilesNoFolder;

  /// Сообщение панели Files: папки проекта нет.
  ///
  /// In en, this message translates to:
  /// **'The project folder does not exist.'**
  String get projectFilesFolderMissing;

  /// Сообщение панели Files: папку проекта не прочитать.
  ///
  /// In en, this message translates to:
  /// **'The project folder cannot be read.'**
  String get projectFilesFolderUnreadable;

  /// Предупреждение панели Files: корень объявил агент, он вне папки проекта. Плейсхолдер root — путь, не переводить.
  ///
  /// In en, this message translates to:
  /// **'{root} — outside the project folder'**
  String projectFilesRootOutside(String root);

  /// Подпись над деревом панели Files. .git — имя папки, не переводить.
  ///
  /// In en, this message translates to:
  /// **'.git is never shown'**
  String get projectFilesGitHidden;

  /// Кнопка панели Files: перечитать дерево.
  ///
  /// In en, this message translates to:
  /// **'Refresh'**
  String get projectFilesRefresh;

  /// Пустой предпросмотр панели Files.
  ///
  /// In en, this message translates to:
  /// **'Select a file to preview it.'**
  String get projectFilesSelectFile;

  /// Строка дерева Files под папкой, содержимое которой не прочиталось.
  ///
  /// In en, this message translates to:
  /// **'Cannot read this folder.'**
  String get projectFilesFolderReadFailed;

  /// Строка дерева Files: сколько записей не показано. Плейсхолдер count — число.
  ///
  /// In en, this message translates to:
  /// **'… {count} more'**
  String projectFilesMore(int count);

  /// Причина отказа предпросмотра: файл вне папки проекта.
  ///
  /// In en, this message translates to:
  /// **'This file is outside the project folder.'**
  String get projectFilesFailureOutsideRoot;

  /// Причина отказа предпросмотра: файла нет.
  ///
  /// In en, this message translates to:
  /// **'The file was not found.'**
  String get projectFilesFailureNotFound;

  /// Причина отказа предпросмотра: файл не прочитать.
  ///
  /// In en, this message translates to:
  /// **'The file cannot be read.'**
  String get projectFilesFailureUnreadable;

  /// Причина отказа предпросмотра: путь недопустим.
  ///
  /// In en, this message translates to:
  /// **'The file path is not valid.'**
  String get projectFilesFailureInvalidPath;

  /// Размер файла в килобайтах в предпросмотре. Плейсхолдер count — число.
  ///
  /// In en, this message translates to:
  /// **'{count} KB'**
  String projectFilesSizeKilobytes(int count);

  /// Размер файла в мегабайтах в предпросмотре. Плейсхолдер count — число.
  ///
  /// In en, this message translates to:
  /// **'{count} MB'**
  String projectFilesSizeMegabytes(int count);

  /// InfoBar оболочки настроек: у агента есть запрос одобрения.
  ///
  /// In en, this message translates to:
  /// **'Agent is waiting for your approval'**
  String get settingsShellPendingApproval;

  /// Кнопка InfoBar оболочки настроек: вернуться к сессии с запросом.
  ///
  /// In en, this message translates to:
  /// **'Back to session'**
  String get settingsShellBackToSession;

  /// Причина отказа подключения: сервер отверг отправленный токен. Плейсхолдер status — HTTP-статус (401 или 403), не переводить. Значения токена в тексте нет. Метка security (D14): перевод не смягчает смысл.
  ///
  /// In en, this message translates to:
  /// **'The agent rejected the token (HTTP {status}).'**
  String workbenchTokenRejected(int status);

  /// Причина отказа подключения: сервер требует токен, а он не был отправлен. Плейсхолдер status — HTTP-статус (401 или 403), не переводить. Значения токена в тексте нет. Метка security (D14): перевод не смягчает смысл.
  ///
  /// In en, this message translates to:
  /// **'The agent requires a token (HTTP {status}).'**
  String workbenchTokenRequired(int status);
}

class _AppLocalizationsDelegate
    extends LocalizationsDelegate<AppLocalizations> {
  const _AppLocalizationsDelegate();

  @override
  Future<AppLocalizations> load(Locale locale) {
    return SynchronousFuture<AppLocalizations>(lookupAppLocalizations(locale));
  }

  @override
  bool isSupported(Locale locale) =>
      <String>['en', 'ru'].contains(locale.languageCode);

  @override
  bool shouldReload(_AppLocalizationsDelegate old) => false;
}

AppLocalizations lookupAppLocalizations(Locale locale) {
  // Lookup logic when only language code is specified.
  switch (locale.languageCode) {
    case 'en':
      return AppLocalizationsEn();
    case 'ru':
      return AppLocalizationsRu();
  }

  throw FlutterError(
    'AppLocalizations.delegate failed to load unsupported locale "$locale". This is likely '
    'an issue with the localizations generation tool. Please file an issue '
    'on GitHub with a reproducible sample app and the gen-l10n configuration '
    'that was used.',
  );
}
