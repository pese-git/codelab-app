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
