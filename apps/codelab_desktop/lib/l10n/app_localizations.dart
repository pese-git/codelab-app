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

  /// Ключевые слова поиска по настройкам для страницы General, через запятую; на русском — переводы английских слов.
  ///
  /// In en, this message translates to:
  /// **'language, budget, steps, compaction, subagent, log level, startup, reopen, ignored, about, version, license, diagnostics'**
  String get settingsSearchKeywordsGeneral;

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
