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

  /// Текст подтверждения перезапуска, когда перезапускается встроенный агент: отдельная фраза без подстановки подписи профиля. Плейсхолдеры: count — число идущих сессий, sessions — названия сессий через запятую; не переводить.
  ///
  /// In en, this message translates to:
  /// **'Restart the embedded agent? This interrupts {count, plural, one{{count} running session} other{{count} running sessions}}: {sessions}. Queued prompts stay.'**
  String workbenchRestartMessageEmbedded(int count, String sessions);

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

  /// Кнопка «Сохранить» в формах и редакторах настроек.
  ///
  /// In en, this message translates to:
  /// **'Save'**
  String get commonSave;

  /// Кнопка удаления записи (профиль, провайдер) в строке и в диалоге подтверждения.
  ///
  /// In en, this message translates to:
  /// **'Remove'**
  String get commonRemove;

  /// Кнопка возврата на предыдущий шаг мастера.
  ///
  /// In en, this message translates to:
  /// **'Back'**
  String get commonBack;

  /// Кнопка перехода на следующий шаг мастера.
  ///
  /// In en, this message translates to:
  /// **'Next'**
  String get commonNext;

  /// Кнопка завершения диалога после успешной записи.
  ///
  /// In en, this message translates to:
  /// **'Done'**
  String get commonDone;

  /// Кнопка правки записи в строке списка.
  ///
  /// In en, this message translates to:
  /// **'Edit'**
  String get commonEdit;

  /// Кнопка проверки провайдера в строке списка.
  ///
  /// In en, this message translates to:
  /// **'Check'**
  String get commonCheck;

  /// Метка записи, которая используется по умолчанию (профиль, провайдер).
  ///
  /// In en, this message translates to:
  /// **'Default'**
  String get commonDefault;

  /// Кнопка продолжения шага мастера.
  ///
  /// In en, this message translates to:
  /// **'Continue'**
  String get commonContinue;

  /// Кнопка страницы Connection: открыть диалог добавления профиля подключения.
  ///
  /// In en, this message translates to:
  /// **'Add profile'**
  String get connectionAddProfile;

  /// Заголовок секции списка профилей на странице Connection.
  ///
  /// In en, this message translates to:
  /// **'Profiles'**
  String get connectionSectionProfiles;

  /// Заголовок секции Behavior на странице Connection (перезапуск агента).
  ///
  /// In en, this message translates to:
  /// **'Behavior'**
  String get connectionSectionBehavior;

  /// Пояснение под заголовком секции профилей. codelab_cli, profiles.json и $CODELAB_HOME — имена программы, файла и переменной окружения, не переводить. «Use» — подпись кнопки строки (connectionRowUse).
  ///
  /// In en, this message translates to:
  /// **'Shared with codelab_cli through profiles.json in \$CODELAB_HOME. The default profile is used when the agent starts, until you choose another with Use.'**
  String get connectionProfilesHelp;

  /// Заголовок раскрывающейся справки о подключении к сессии, запущенной в CLI.
  ///
  /// In en, this message translates to:
  /// **'Join a session started in the CLI'**
  String get connectionJoinCliTitle;

  /// Справка о подключении к агенту из CLI. Команды (codelab-agent serve --ws <port>, codelab -a <profile>) и WebSocket не переводить.
  ///
  /// In en, this message translates to:
  /// **'On the host run codelab-agent serve --ws <port>; the CLI connects with codelab -a <profile>. Choose the same WebSocket profile here; its sessions appear in the sidebar.'**
  String get connectionJoinCliBody;

  /// Метка профиля, к которому подключено окно.
  ///
  /// In en, this message translates to:
  /// **'Current'**
  String get connectionBadgeCurrent;

  /// Метка профиля, выбранного для следующего старта агента.
  ///
  /// In en, this message translates to:
  /// **'Selected'**
  String get connectionBadgeSelected;

  /// Бейдж попытки подключения профиля: идёт попытка.
  ///
  /// In en, this message translates to:
  /// **'Connecting…'**
  String get connectionStatusConnecting;

  /// Бейдж попытки подключения профиля: подключено.
  ///
  /// In en, this message translates to:
  /// **'Connected'**
  String get connectionStatusConnected;

  /// Бейдж попытки подключения профиля: сбой.
  ///
  /// In en, this message translates to:
  /// **'Failed'**
  String get connectionStatusFailed;

  /// Кнопка строки профиля: выбрать профиль для следующего старта агента.
  ///
  /// In en, this message translates to:
  /// **'Use'**
  String get connectionRowUse;

  /// Кнопка строки профиля: переименовать.
  ///
  /// In en, this message translates to:
  /// **'Rename'**
  String get connectionRowRename;

  /// Подсказка неактивной кнопки удаления текущего или выбранного профиля.
  ///
  /// In en, this message translates to:
  /// **'Use another profile first.'**
  String get connectionRowUseAnotherFirst;

  /// Подпись строки профиля окна, которого нет в profiles.json.
  ///
  /// In en, this message translates to:
  /// **'Current connection (not saved)'**
  String get connectionRowNotSaved;

  /// Подсказка поля имени в редакторе переименования профиля.
  ///
  /// In en, this message translates to:
  /// **'Name'**
  String get connectionRenameName;

  /// Подпись профиля встроенного агента (в списке профилей, в шапке рабочего места, в подсказке соединения).
  ///
  /// In en, this message translates to:
  /// **'Embedded agent'**
  String get connectionEmbeddedAgentTitle;

  /// Сводка строки профиля встроенного агента. CodeLab — название продукта, не переводить.
  ///
  /// In en, this message translates to:
  /// **'Runs inside CodeLab; no separate process.'**
  String get connectionEmbeddedAgentSummary;

  /// Источник токена профиля WebSocket: токена нет.
  ///
  /// In en, this message translates to:
  /// **'No token'**
  String get connectionTokenNone;

  /// Источник токена: переменная окружения. Плейсхолдер variable — имя переменной со знаком доллара, не переводить. Значения токена в тексте нет.
  ///
  /// In en, this message translates to:
  /// **'From {variable}'**
  String connectionTokenFromEnv(String variable);

  /// Заметка: переменная окружения токена не задана. Плейсхолдер name — имя переменной, не переводить. CodeLab — название продукта.
  ///
  /// In en, this message translates to:
  /// **'{name} is not set in CodeLab\'s environment.'**
  String tokenEnvNotSet(String name);

  /// Источник токена: секрет хранилища. Плейсхолдер name — имя секрета, не переводить. Значения секрета в тексте нет.
  ///
  /// In en, this message translates to:
  /// **'Token secret {name}'**
  String connectionTokenSecret(String name);

  /// Тег секрета токена: секрет есть в хранилище. Плейсхолдер backend — id бэкенда хранилища (file, env), не переводить.
  ///
  /// In en, this message translates to:
  /// **'{backend} · set'**
  String connectionTokenSecretSet(String backend);

  /// Тег секрета токена: секрета нет в хранилище. Плейсхолдер backend — id бэкенда хранилища, не переводить.
  ///
  /// In en, this message translates to:
  /// **'{backend} · missing'**
  String connectionTokenSecretMissing(String backend);

  /// Источник токена: ссылка, которую эта версия не разбирает. Саму ссылку не показываем: в ней мог оказаться токен.
  ///
  /// In en, this message translates to:
  /// **'unrecognized token reference (not supported in this version)'**
  String get connectionTokenUnsupported;

  /// Заголовок InfoBar страницы Connection при подключении к удалённому агенту. Плейсхолдер origin — адрес scheme://host:port, не переводить.
  ///
  /// In en, this message translates to:
  /// **'Read-only: this agent runs on {origin}'**
  String connectionReadOnlyTitle(String origin);

  /// Подсказка InfoBar «только чтение» для удалённого агента. Команды codelab … и MCP не переводить.
  ///
  /// In en, this message translates to:
  /// **'Change providers and MCP on that host: codelab provider add, codelab mcp add, codelab config set.'**
  String get settingsRemoteHostHint;

  /// InfoBar: в profiles.json осталась прежняя запись default. default, profiles.json и команда codelab profiles remove default — не переводить.
  ///
  /// In en, this message translates to:
  /// **'Profile \"default\" in profiles.json is ignored: default is the built-in agent. Remove it with codelab profiles remove default.'**
  String get connectionIgnoredDefault;

  /// Заголовок диалога подтверждения удаления игнорируемой записи default.
  ///
  /// In en, this message translates to:
  /// **'Remove the ignored \"default\" profile?'**
  String get connectionIgnoredDefaultRemoveTitle;

  /// Пояснение диалога удаления игнорируемой записи default. profiles.json и default не переводить.
  ///
  /// In en, this message translates to:
  /// **'Only the \"default\" entry is deleted from profiles.json; other profiles stay.'**
  String get connectionIgnoredDefaultRemoveDetails;

  /// Ошибка чтения profiles.json. Плейсхолдер path — путь файла, reason — причина (connectionUnreadableUnsupported / connectionUnreadableCannotRead), не переводить.
  ///
  /// In en, this message translates to:
  /// **'Cannot read {path}: {reason}. Fix or remove the file; CodeLab will not overwrite it.'**
  String connectionUnreadableWithPath(String path, String reason);

  /// Ошибка недоступности профилей (недопустимый CODELAB_HOME). Плейсхолдер reason — текст причины из composition root (английский, как есть).
  ///
  /// In en, this message translates to:
  /// **'Cannot use the profiles: {reason}.'**
  String connectionUnreadableWithoutPath(String reason);

  /// Причина: profiles.json неподдерживаемой версии или с неверной структурой. Вставляется в connectionUnreadableWithPath.
  ///
  /// In en, this message translates to:
  /// **'the file has an unsupported version or an invalid structure'**
  String get connectionUnreadableUnsupported;

  /// Причина: файл не читается. Плейсхолдер errorType — имя типа исключения, не переводить. Текста исключения нет.
  ///
  /// In en, this message translates to:
  /// **'the file cannot be read ({errorType})'**
  String connectionUnreadableCannotRead(String errorType);

  /// Разовое сообщение: запись изменения (переименование, удаление, выбор профиля) не удалась. Текста исключения нет.
  ///
  /// In en, this message translates to:
  /// **'Could not save the change. Try again.'**
  String get connectionFailureSaveFailed;

  /// Разовое сообщение: профиль удалён, секрет токена остался. Плейсхолдер name — имя секрета; команда codelab secret delete не переводится. Метка security (D14): перевод не смягчает смысл предупреждения.
  ///
  /// In en, this message translates to:
  /// **'The profile was removed, but the stored token {name} was not deleted. Remove it with codelab secret delete {name}.'**
  String connectionFailureTokenNotDeleted(String name);

  /// Заголовок диалога подтверждения удаления профиля. Плейсхолдер name — имя профиля пользователя, не переводить.
  ///
  /// In en, this message translates to:
  /// **'Remove profile {name}?'**
  String connectionRemoveTitle(String name);

  /// Пояснение диалога удаления профиля. profiles.json не переводить.
  ///
  /// In en, this message translates to:
  /// **'The entry is deleted from profiles.json. Environment variables and other settings are not touched.'**
  String get connectionRemoveDetails;

  /// Флажок диалога удаления профиля. Плейсхолдер name — имя секрета, не переводить.
  ///
  /// In en, this message translates to:
  /// **'Also delete the stored token {name}'**
  String connectionRemoveDeleteToken(String name);

  /// Заголовок и кнопка блока Behavior для удалённого (WebSocket) агента.
  ///
  /// In en, this message translates to:
  /// **'Reconnect'**
  String get connectionReconnect;

  /// Кнопка блока Behavior для локального агента.
  ///
  /// In en, this message translates to:
  /// **'Restart'**
  String get connectionRestartButton;

  /// Подсказка недоступной кнопки перезапуска: агент запускается при открытии проекта.
  ///
  /// In en, this message translates to:
  /// **'Starts when you open a project.'**
  String get connectionRestartHint;

  /// Описание блока Behavior. Плейсхолдер subject — имя профиля (либо connectionRestartSubjectWindow), не переводить.
  ///
  /// In en, this message translates to:
  /// **'Reconnects {subject} and reloads open sessions. A running turn is interrupted; queued prompts stay.'**
  String connectionRestartDescription(String subject);

  /// Описание блока Behavior, когда цель перезапуска — встроенный агент. Отдельная фраза без подстановки подписи профиля: «Встроенный агент» в середине предложения на русском не склоняется и пишется с заглавной.
  ///
  /// In en, this message translates to:
  /// **'Reconnects the embedded agent and reloads open sessions. A running turn is interrupted; queued prompts stay.'**
  String get connectionRestartDescriptionEmbedded;

  /// Подлежащее описания перезапуска, пока цели перезапуска ещё нет. Вставляется в connectionRestartDescription.
  ///
  /// In en, this message translates to:
  /// **'the profile of this window'**
  String get connectionRestartSubjectWindow;

  /// Описание блока Behavior, когда выбран не тот профиль, что работает. Плейсхолдер subject — имя выбранного профиля, не переводить.
  ///
  /// In en, this message translates to:
  /// **'Restart {subject} to use it.'**
  String connectionRestartToUse(String subject);

  /// Описание блока Behavior, когда выбран встроенный агент, а работает другой профиль. Отдельная фраза без подстановки подписи профиля.
  ///
  /// In en, this message translates to:
  /// **'Restart the agent to switch to the embedded agent.'**
  String get connectionRestartToUseEmbedded;

  /// Заголовок диалога добавления профиля подключения.
  ///
  /// In en, this message translates to:
  /// **'Add connection profile'**
  String get addProfileTitle;

  /// Подзаголовок диалога. Плейсхолдеры path (путь profiles.json) и command (команда codelab -a <id>) — не переводить; codelab_cli — имя программы.
  ///
  /// In en, this message translates to:
  /// **'Saved to {path} and shared with codelab_cli as {command}.'**
  String addProfileSubtitle(String path, String command);

  /// Подпись поля выбора типа профиля (stdio или WebSocket).
  ///
  /// In en, this message translates to:
  /// **'Type'**
  String get addProfileFieldType;

  /// Подпись поля имени профиля.
  ///
  /// In en, this message translates to:
  /// **'Name'**
  String get addProfileFieldName;

  /// Подпись поля команды запуска агента (профиль stdio).
  ///
  /// In en, this message translates to:
  /// **'Command'**
  String get addProfileFieldCommand;

  /// Подпись поля аргументов команды.
  ///
  /// In en, this message translates to:
  /// **'Arguments'**
  String get addProfileFieldArguments;

  /// Подпись строки выбора рабочей папки процесса агента.
  ///
  /// In en, this message translates to:
  /// **'Folder'**
  String get addProfileFieldFolder;

  /// Подпись поля переменных окружения процесса агента.
  ///
  /// In en, this message translates to:
  /// **'Environment'**
  String get addProfileFieldEnvironment;

  /// Подпись строки выбора источника токена WebSocket-профиля.
  ///
  /// In en, this message translates to:
  /// **'Token'**
  String get addProfileFieldToken;

  /// Подпись строки с флажком «Использовать по умолчанию».
  ///
  /// In en, this message translates to:
  /// **'After saving'**
  String get addProfileFieldAfterSaving;

  /// Подпись переключателя типа профиля для скринридера.
  ///
  /// In en, this message translates to:
  /// **'Profile type'**
  String get addProfileTypeSemantics;

  /// Сегмент типа профиля: локальный процесс по stdio. stdio не переводить.
  ///
  /// In en, this message translates to:
  /// **'Local stdio'**
  String get addProfileTypeStdio;

  /// Пояснение под переключателем типа: stdio-профиль. ACP, stdin и stdout не переводить.
  ///
  /// In en, this message translates to:
  /// **'Starts the agent as a child process per window and talks ACP over stdin/stdout.'**
  String get addProfileTypeStdioNote;

  /// Пояснение под переключателем типа: WebSocket-профиль. Команда codelab-agent serve --ws не переводится.
  ///
  /// In en, this message translates to:
  /// **'Connects to codelab-agent serve --ws on this or another machine.'**
  String get addProfileTypeWebSocketNote;

  /// Подпись рядом с полем id: после сохранения id не меняется.
  ///
  /// In en, this message translates to:
  /// **'· cannot change after saving'**
  String get addProfileIdCannotChange;

  /// Пример имени профиля в подсказке поля. Не переводить.
  ///
  /// In en, this message translates to:
  /// **'devbox 2'**
  String get addProfileNamePlaceholder;

  /// Пояснение под полем аргументов.
  ///
  /// In en, this message translates to:
  /// **'Parsed like a shell: quotes and escapes work.'**
  String get addProfileArgumentsNote;

  /// Флажок: процесс агента запускается в папке проекта.
  ///
  /// In en, this message translates to:
  /// **'Run in the project folder'**
  String get addProfileRunInProject;

  /// Флажок: сделать профиль профилем по умолчанию.
  ///
  /// In en, this message translates to:
  /// **'Use by default'**
  String get addProfileUseByDefault;

  /// Пояснение под флажком «Использовать по умолчанию».
  ///
  /// In en, this message translates to:
  /// **'Used when the agent starts.'**
  String get addProfileUsedWhenAgentStarts;

  /// Вариант токена: без токена.
  ///
  /// In en, this message translates to:
  /// **'No token'**
  String get addProfileTokenNone;

  /// Вариант токена: взять секрет из хранилища секретов.
  ///
  /// In en, this message translates to:
  /// **'Use stored secret'**
  String get addProfileTokenStored;

  /// Вариант токена: ввести значение и сохранить его в хранилище секретов.
  ///
  /// In en, this message translates to:
  /// **'Store a new token'**
  String get addProfileTokenNew;

  /// Вариант токена: брать значение из переменной окружения.
  ///
  /// In en, this message translates to:
  /// **'From environment variable'**
  String get addProfileTokenEnv;

  /// Подсказка скрытого поля ввода нового токена. Значение не показывается.
  ///
  /// In en, this message translates to:
  /// **'Paste the token'**
  String get addProfileTokenPaste;

  /// Пояснение варианта «Из переменной окружения». CodeLab и profiles.json не переводить. Метка security (D14): перевод не смягчает смысл предупреждения.
  ///
  /// In en, this message translates to:
  /// **'CodeLab reads the token from this environment variable when it connects. Token values are not saved in profiles.json.'**
  String get addProfileTokenEnvNote;

  /// Пояснение варианта «Из переменной окружения»: macOS Finder не передаёт переменные оболочки. Finder — название программы, не переводить.
  ///
  /// In en, this message translates to:
  /// **'Apps opened from Finder do not see variables set in your shell profile.'**
  String get addProfileTokenEnvFinderNote;

  /// Подсказка недоступного варианта «Использовать сохранённый секрет». Плейсхолдер backend — id бэкенда хранилища, не переводить.
  ///
  /// In en, this message translates to:
  /// **'No stored secrets in {backend}.'**
  String addProfileStoredSecretsHint(String backend);

  /// Подсказка варианта «Сохранить новый токен». Плейсхолдеры: name — имя секрета (или codelab/profiles/<id>/token), backend — id бэкенда; не переводить. Метка security (D14): перевод не смягчает смысл предупреждения.
  ///
  /// In en, this message translates to:
  /// **'Saved as {name} in {backend}. The value is never shown again or written to profiles.json.'**
  String addProfileNewTokenHint(String name, String backend);

  /// Первая фраза под недоступным вариантом «Сохранить новый токен»: хранилище только для чтения; причину, названную хранилищем, показываем под ней как есть. Плейсхолдер backend — id бэкенда, не переводить.
  ///
  /// In en, this message translates to:
  /// **'Secret store {backend} is read-only.'**
  String addProfileSecretStoreReadOnly(String backend);

  /// Предупреждение под URL: токен по ws:// уходит без шифрования. ws:// не переводить. Метка security (D14): перевод не смягчает смысл предупреждения.
  ///
  /// In en, this message translates to:
  /// **'ws:// to another machine: the token is sent unencrypted.'**
  String get addProfileWarningTokenPlaintext;

  /// Предупреждение под URL: трафик по ws:// уходит без шифрования. ws:// не переводить. Метка security (D14): перевод не смягчает смысл предупреждения.
  ///
  /// In en, this message translates to:
  /// **'ws:// to another machine: traffic is sent unencrypted.'**
  String get addProfileWarningTrafficPlaintext;

  /// Заголовок подтверждения ws:// перед записью профиля. Метка security (D14): перевод не смягчает смысл предупреждения.
  ///
  /// In en, this message translates to:
  /// **'Unencrypted connection'**
  String get addProfilePlaintextTitle;

  /// Подтверждение ws:// с токеном. Плейсхолдер origin — scheme://host:port без пути и учётных данных, не переводить. Метка security (D14): перевод не смягчает смысл предупреждения.
  ///
  /// In en, this message translates to:
  /// **'The token for {origin} will travel in clear text. Use wss:// if the host supports it.'**
  String addProfilePlaintextWithToken(String origin);

  /// Подтверждение ws:// без токена. Плейсхолдер origin — scheme://host:port, не переводить. Метка security (D14): перевод не смягчает смысл предупреждения.
  ///
  /// In en, this message translates to:
  /// **'Prompts and files sent to {origin} will travel in clear text. Use wss:// if the host supports it.'**
  String addProfilePlaintextWithoutToken(String origin);

  /// Кнопка подтверждения записи профиля с ws:// без шифрования. Метка security (D14): перевод не смягчает смысл предупреждения.
  ///
  /// In en, this message translates to:
  /// **'Save anyway'**
  String get addProfileSaveAnyway;

  /// Ошибка поля имени: пусто.
  ///
  /// In en, this message translates to:
  /// **'Enter a name.'**
  String get addProfileErrorLabelEmpty;

  /// Ошибка поля id: пусто.
  ///
  /// In en, this message translates to:
  /// **'Id is required.'**
  String get addProfileErrorIdEmpty;

  /// Ошибка поля id: зарезервированный id. Плейсхолдер id — идентификатор профиля, не переводить.
  ///
  /// In en, this message translates to:
  /// **'\"{id}\" is reserved for the built-in agent.'**
  String addProfileErrorIdReserved(String id);

  /// Ошибка поля id: id занят. Плейсхолдер id — идентификатор профиля, не переводить.
  ///
  /// In en, this message translates to:
  /// **'A profile with id \"{id}\" already exists.'**
  String addProfileErrorIdTaken(String id);

  /// Ошибка поля id: недопустимые символы.
  ///
  /// In en, this message translates to:
  /// **'Use lowercase letters, digits, \".\", \"_\" and \"-\" (up to 64 characters).'**
  String get addProfileErrorIdInvalid;

  /// Ошибка поля команды: пусто.
  ///
  /// In en, this message translates to:
  /// **'Enter the command that starts the agent.'**
  String get addProfileErrorCommandEmpty;

  /// Ошибка поля аргументов: не закрыта кавычка.
  ///
  /// In en, this message translates to:
  /// **'Arguments have an unclosed quote.'**
  String get addProfileErrorArgsInvalid;

  /// Ошибка поля URL: нужна схема ws:// или wss:// и хост. ws:// и wss:// не переводить.
  ///
  /// In en, this message translates to:
  /// **'Use ws:// or wss:// with a host.'**
  String get addProfileErrorUrlInvalid;

  /// Ошибка поля URL: в адресе учётные данные. «Токен» — подпись поля addProfileFieldToken. Метка security (D14): перевод не смягчает смысл предупреждения.
  ///
  /// In en, this message translates to:
  /// **'Remove the user name and password from the URL; use the Token setting instead.'**
  String get addProfileErrorUrlUserInfo;

  /// Ошибка имени переменной токена.
  ///
  /// In en, this message translates to:
  /// **'Variable name: letters, digits and \"_\", not starting with a digit.'**
  String get addProfileErrorTokenEnvNameInvalid;

  /// Ошибка имени выбранного секрета хранилища.
  ///
  /// In en, this message translates to:
  /// **'Secret name: lowercase letters, digits and . _ / -, up to 128 characters.'**
  String get addProfileErrorTokenSecretNameInvalid;

  /// Ошибка поля токена: значение не введено.
  ///
  /// In en, this message translates to:
  /// **'Enter the token.'**
  String get addProfileErrorTokenSecretEmpty;

  /// Ошибка поля id: из него нельзя построить имя секрета токена.
  ///
  /// In en, this message translates to:
  /// **'This id cannot name a stored token; avoid \"..\".'**
  String get addProfileErrorTokenSecretIdInvalid;

  /// Ошибка поля токена: секрет с таким именем уже есть. Плейсхолдеры name (имя секрета) и backend (id бэкенда) не переводить; команда codelab secret delete не переводится; «Использовать сохранённый секрет» — addProfileTokenStored. Метка security (D14): перевод не смягчает смысл предупреждения.
  ///
  /// In en, this message translates to:
  /// **'A stored token {name} already exists in {backend}. Choose it with \"Use stored secret\" or remove it with codelab secret delete.'**
  String addProfileErrorTokenSecretExists(String name, String backend);

  /// Заголовок экрана после успешной записи профиля.
  ///
  /// In en, this message translates to:
  /// **'Profile saved'**
  String get addProfileSavedTitle;

  /// Строка экрана «Профиль сохранён». Плейсхолдер id — идентификатор профиля, не переводить; profiles.json не переводить.
  ///
  /// In en, this message translates to:
  /// **'Added to profiles.json as {id}'**
  String addProfileSavedMessage(String id);

  /// Продолжение строки экрана «Профиль сохранён»: профиль стал профилем по умолчанию. Ведущий пробел и точку-разделитель сохранить.
  ///
  /// In en, this message translates to:
  /// **' · used by default'**
  String get addProfileSavedUsedByDefault;

  /// Пояснение экрана «Профиль сохранён». «Использовать» — connectionRowUse, «Перезапустить агента» — commonRestartAgent.
  ///
  /// In en, this message translates to:
  /// **'The running agent is unchanged. Select it with Use in the profile row; Restart agent applies it.'**
  String get addProfileSavedNote;

  /// Кнопка экрана «Профиль сохранён»: добавить ещё один профиль.
  ///
  /// In en, this message translates to:
  /// **'Add another'**
  String get addProfileAddAnother;

  /// Разовое сообщение: запись профиля не удалась. Текста исключения нет.
  ///
  /// In en, this message translates to:
  /// **'Could not save the profile. Try again.'**
  String get addProfileFailureProfile;

  /// Разовое сообщение: запись секрета токена не удалась. Значения токена и текста исключения нет. Метка security (D14): перевод не смягчает смысл предупреждения.
  ///
  /// In en, this message translates to:
  /// **'Could not store the token. Try again.'**
  String get addProfileFailureSecret;

  /// Разовое сообщение: профиль не записан, а секрет токена остался. Плейсхолдеры backend (id бэкенда) и name (имя секрета) не переводить; команда codelab secret delete не переводится. Метка security (D14): перевод не смягчает смысл предупреждения.
  ///
  /// In en, this message translates to:
  /// **'The profile was not saved; the token stays in {backend} as {name}. Remove it with codelab secret delete {name}.'**
  String addProfileFailureOrphanedToken(String backend, String name);

  /// Заголовок отказа записи секрета (диалог профиля, шаг ключа мастера провайдера): хранилище только для чтения. Причину и подсказку, названные самим хранилищем, показываем под заголовком как есть. Метка security (D14): перевод не смягчает смысл.
  ///
  /// In en, this message translates to:
  /// **'The secret store is read-only.'**
  String get secretStoreReadOnly;

  /// Ошибка поля окружения: имя переменной похоже на секрет. Плейсхолдеры key (имя переменной) и syntax (синтаксис конфигурации агента) не переводить. Метка security (D14): перевод не смягчает смысл предупреждения.
  ///
  /// In en, this message translates to:
  /// **'{key} looks like a secret. Set it in the system environment or reference it from the agent config as {syntax}.'**
  String addProfileErrorEnvSecretLike(String key, String syntax);

  /// Кнопка добавления провайдера (страница Providers, пустое состояние) и заголовок мастера.
  ///
  /// In en, this message translates to:
  /// **'Add provider'**
  String get providersAdd;

  /// Подпись строки выбора модели по умолчанию на странице Providers.
  ///
  /// In en, this message translates to:
  /// **'Default model'**
  String get providersDefaultModel;

  /// Описание строки «Модель по умолчанию».
  ///
  /// In en, this message translates to:
  /// **'Used by new sessions.'**
  String get providersUsedByNewSessions;

  /// Описание: модель активной сессии. Плейсхолдер model — id модели, не переводить.
  ///
  /// In en, this message translates to:
  /// **'Active in this session: {model}'**
  String providersActiveInSession(String model);

  /// Подсказка выпадающего списка моделей, когда выбора ещё нет.
  ///
  /// In en, this message translates to:
  /// **'Choose a model'**
  String get providersChooseModel;

  /// Заголовок строки хранилища ключей. Плейсхолдер backend — id бэкенда (file, env), не переводить.
  ///
  /// In en, this message translates to:
  /// **'Key storage: {backend}'**
  String providersKeyStorage(String backend);

  /// Описание строки хранилища ключей.
  ///
  /// In en, this message translates to:
  /// **'Only key names and presence are read — values never enter the app'**
  String get providersKeyStorageDescription;

  /// Тег хранилища ключей: запись разрешена.
  ///
  /// In en, this message translates to:
  /// **'writable'**
  String get providersStorageWritable;

  /// Тег хранилища ключей: только чтение.
  ///
  /// In en, this message translates to:
  /// **'read-only'**
  String get providersStorageReadOnly;

  /// Предупреждение: ключи лежат в открытом файле. Плейсхолдер path — путь файла, не переводить; 0600 — режим файла, не переводить. Метка security (D14): перевод не смягчает смысл предупреждения.
  ///
  /// In en, this message translates to:
  /// **'Keys are stored in an open file {path} (mode 0600).'**
  String providersKeysInOpenFile(String path);

  /// Заголовок списка провайдеров.
  ///
  /// In en, this message translates to:
  /// **'Configured providers'**
  String get providersConfigured;

  /// Пустое состояние страницы Providers.
  ///
  /// In en, this message translates to:
  /// **'No providers yet. The embedded agent needs one to run a turn.'**
  String get providersEmpty;

  /// Подвал страницы Providers. Плейсхолдер path — путь config.yaml, не переводить.
  ///
  /// In en, this message translates to:
  /// **'Config file: {path}'**
  String providersConfigFile(String path);

  /// Пояснение в подвале страницы Providers. Названия флажка и выбора совпадают с providersRemoveDeleteKey и providersRemoveNewDefault.
  ///
  /// In en, this message translates to:
  /// **'Remove asks to confirm with “Also delete the stored key”; removing the default provider asks for a “New default model”. Rows defined in the project file are not editable here.'**
  String get providersRemoveHelp;

  /// InfoBar страницы Providers для удалённого агента. Плейсхолдер origin — scheme://host:port, не переводить.
  ///
  /// In en, this message translates to:
  /// **'Read-only: this agent runs on {origin}.'**
  String providersReadOnlyTitle(String origin);

  /// InfoBar страницы Providers для стороннего агента. Плейсхолдер agent — имя агента, не переводить.
  ///
  /// In en, this message translates to:
  /// **'Provider settings are managed by {agent}.'**
  String providersNotManaged(String agent);

  /// Заголовок InfoBar нечитаемого config.yaml; проблемы загрузчика идут отдельными строками как есть.
  ///
  /// In en, this message translates to:
  /// **'Cannot read the agent config. Fix or remove the file; CodeLab will not overwrite it.'**
  String get providersUnreadable;

  /// Проблема нечитаемой конфигурации: нет домашней папки CodeLab.
  ///
  /// In en, this message translates to:
  /// **'The CodeLab home folder is not available.'**
  String get providersProblemNoHome;

  /// Проблема нечитаемой конфигурации: сессию настроек не удалось открыть.
  ///
  /// In en, this message translates to:
  /// **'Cannot read the agent settings.'**
  String get providersProblemCannotReadSettings;

  /// Проблема нечитаемой конфигурации: пользовательский слой config.yaml не читается. config.yaml не переводить.
  ///
  /// In en, this message translates to:
  /// **'The user config.yaml cannot be read.'**
  String get providersProblemUserConfig;

  /// Подпись строки провайдера с неизвестным видом (kind в конфигурации не задан).
  ///
  /// In en, this message translates to:
  /// **'Unknown kind'**
  String get providersUnknownKind;

  /// Число моделей провайдера в подписи строки.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, one{{count} model} other{{count} models}}'**
  String providersModelCount(int count);

  /// Подпись провайдера из нередактируемого файла. Плейсхолдер path — путь файла, не переводить.
  ///
  /// In en, this message translates to:
  /// **'defined in {path}'**
  String providersDefinedIn(String path);

  /// Подпись провайдера, заданного переменными окружения.
  ///
  /// In en, this message translates to:
  /// **'defined in the environment'**
  String get providersDefinedInEnvironment;

  /// Строка «Источник» раскрытой карточки: провайдер из окружения.
  ///
  /// In en, this message translates to:
  /// **'Environment'**
  String get providersSourceEnvironment;

  /// Статус ключа: секрет есть в хранилище. Плейсхолдер backend — id бэкенда, не переводить.
  ///
  /// In en, this message translates to:
  /// **'Key: in {backend}'**
  String providersKeyLabelInStore(String backend);

  /// Статус ключа: секрета нет в хранилище. Плейсхолдер backend — id бэкенда, не переводить.
  ///
  /// In en, this message translates to:
  /// **'Key: missing in {backend}'**
  String providersKeyLabelMissing(String backend);

  /// Статус ключа: переменная окружения задана. Плейсхолдер name — имя переменной, не переводить.
  ///
  /// In en, this message translates to:
  /// **'Key: env {name} (set)'**
  String providersKeyLabelEnvSet(String name);

  /// Статус ключа: переменная окружения не задана. Плейсхолдер name — имя переменной, не переводить.
  ///
  /// In en, this message translates to:
  /// **'Key: env {name} (not set)'**
  String providersKeyLabelEnvNotSet(String name);

  /// Статус ключа: значение записано в config.yaml открытым текстом. Метка security (D14): перевод не смягчает смысл предупреждения.
  ///
  /// In en, this message translates to:
  /// **'Key: in config file (plain text)'**
  String get providersKeyLabelLiteral;

  /// Статус ключа: ключа нет. Также подпись шага «без ключа» в мастере.
  ///
  /// In en, this message translates to:
  /// **'No key'**
  String get providersKeyLabelNone;

  /// Строка «Ключ» раскрытой карточки: секрет в хранилище. Плейсхолдеры backend (id бэкенда) и name (имя секрета) — не переводить. Имя секрета выводится моноширинным шрифтом.
  ///
  /// In en, this message translates to:
  /// **'In {backend} as {name}'**
  String providersKeyInStore(String backend, String name);

  /// Строка «Ключ» раскрытой карточки: секрета нет в хранилище. Плейсхолдеры backend и name не переводить.
  ///
  /// In en, this message translates to:
  /// **'Not stored in {backend} as {name}'**
  String providersKeyNotStored(String backend, String name);

  /// Строка «Ключ» раскрытой карточки: переменная задана. Плейсхолдер name не переводить.
  ///
  /// In en, this message translates to:
  /// **'Environment variable {name} (set)'**
  String providersKeyEnvSet(String name);

  /// Строка «Ключ» раскрытой карточки: переменная не задана. Плейсхолдер name не переводить.
  ///
  /// In en, this message translates to:
  /// **'Environment variable {name} (not set)'**
  String providersKeyEnvNotSet(String name);

  /// Строка «Ключ» раскрытой карточки: значение в config.yaml открытым текстом. Метка security (D14): перевод не смягчает смысл предупреждения.
  ///
  /// In en, this message translates to:
  /// **'In the config file (plain text)'**
  String get providersKeyLiteral;

  /// Подсказка под строкой: ключ открытым текстом. config.yaml и команда codelab secret migrate не переводятся. Метка security (D14): перевод не смягчает смысл предупреждения.
  ///
  /// In en, this message translates to:
  /// **'The key is written in config.yaml. Move it to the secret store: codelab secret migrate.'**
  String get providersKeyHintLiteral;

  /// Предупреждение: ключ уходит по http:// без шифрования. Плейсхолдер host — имя хоста, не переводить. Метка security (D14): перевод не смягчает смысл предупреждения.
  ///
  /// In en, this message translates to:
  /// **'The key is sent unencrypted to {host}.'**
  String settingsKeyUnencryptedToHost(String host);

  /// Подсказка неактивной кнопки проверки. Плейсхолдер kind — вид провайдера из конфигурации (gemini), не переводить.
  ///
  /// In en, this message translates to:
  /// **'Check is not available for {kind} providers yet.'**
  String providersCheckUnavailable(String kind);

  /// Подсказка неактивной кнопки удаления последнего провайдера.
  ///
  /// In en, this message translates to:
  /// **'The agent needs at least one provider. Add another provider first.'**
  String get providersRemoveLast;

  /// Отказ правки или удаления: провайдер в файле, в который CodeLab не пишет.
  ///
  /// In en, this message translates to:
  /// **'This provider is defined in a read-only file. Change it there.'**
  String get providersRefusalNotEditable;

  /// Отказ правки или удаления: провайдер определён в нескольких файлах.
  ///
  /// In en, this message translates to:
  /// **'This provider is defined in several config files. Change it there.'**
  String get providersRefusalSeveralFiles;

  /// Отказ удаления: нужна новая модель по умолчанию.
  ///
  /// In en, this message translates to:
  /// **'Choose a new default model.'**
  String get providersRefusalNewDefault;

  /// Отказ удаления: модель по умолчанию задана в нередактируемом файле.
  ///
  /// In en, this message translates to:
  /// **'The default model is set in a file CodeLab does not write. Change it there first.'**
  String get providersRefusalDefaultOverridden;

  /// Отказ удаления: настройки изменились на диске.
  ///
  /// In en, this message translates to:
  /// **'The provider settings changed. Review the page and try again.'**
  String get providersRefusalChanged;

  /// Тег проверки: проверок за жизнь страницы не было.
  ///
  /// In en, this message translates to:
  /// **'not checked'**
  String get providersCheckNotChecked;

  /// Строка «Последняя проверка»: проверок не было.
  ///
  /// In en, this message translates to:
  /// **'Not checked yet'**
  String get providersCheckNotCheckedYet;

  /// Тег проверки: запрос идёт.
  ///
  /// In en, this message translates to:
  /// **'checking…'**
  String get providersCheckRunning;

  /// Строка «Последняя проверка»: запрос идёт.
  ///
  /// In en, this message translates to:
  /// **'Checking…'**
  String get providersCheckRunningDetail;

  /// Тег проверки: успех и число моделей.
  ///
  /// In en, this message translates to:
  /// **'ok, {count, plural, one{{count} model} other{{count} models}}'**
  String providersCheckOkLabel(int count);

  /// Строка «Последняя проверка»: время, число моделей и длительность. Плейсхолдер time (чч:мм) не переводить; ms — миллисекунды.
  ///
  /// In en, this message translates to:
  /// **'{time} · {count, plural, one{{count} model} other{{count} models}} · {ms} ms'**
  String providersCheckOkDetail(String time, int count, int ms);

  /// Строка «Последняя проверка»: отказ без кода HTTP. Плейсхолдеры time и label (тег отказа) не переводить.
  ///
  /// In en, this message translates to:
  /// **'{time} · {label}'**
  String providersCheckFailedDetail(String time, String label);

  /// Строка «Последняя проверка»: отказ с кодом HTTP. Плейсхолдеры time, label и status не переводить.
  ///
  /// In en, this message translates to:
  /// **'{time} · {label} (HTTP {status})'**
  String providersCheckFailedDetailStatus(
    String time,
    String label,
    int status,
  );

  /// Тег отказа проверки: сервер отклонил ключ.
  ///
  /// In en, this message translates to:
  /// **'unauthorized'**
  String get providersCheckUnauthorized;

  /// Тег отказа проверки: список моделей не найден.
  ///
  /// In en, this message translates to:
  /// **'not found'**
  String get providersCheckNotFound;

  /// Тег отказа проверки: сервер недоступен.
  ///
  /// In en, this message translates to:
  /// **'unreachable'**
  String get providersCheckUnreachable;

  /// Тег отказа проверки: время ожидания истекло.
  ///
  /// In en, this message translates to:
  /// **'timeout'**
  String get providersCheckTimeout;

  /// Тег отказа проверки: ошибка TLS.
  ///
  /// In en, this message translates to:
  /// **'TLS error'**
  String get providersCheckTlsError;

  /// Тег отказа проверки: неожиданный ответ.
  ///
  /// In en, this message translates to:
  /// **'bad response'**
  String get providersCheckBadResponse;

  /// Тег проверки: ключа нет, запрос не отправлялся.
  ///
  /// In en, this message translates to:
  /// **'Key: missing'**
  String get providersCheckKeyMissing;

  /// Строка «Последняя проверка»: ключа нет, запрос не отправлялся.
  ///
  /// In en, this message translates to:
  /// **'Not checked: the key is missing'**
  String get providersCheckKeyMissingDetail;

  /// Подпись строки «Ключ» раскрытой карточки провайдера.
  ///
  /// In en, this message translates to:
  /// **'Key'**
  String get providersRowKey;

  /// Подпись строки «Последняя проверка» раскрытой карточки провайдера.
  ///
  /// In en, this message translates to:
  /// **'Last check'**
  String get providersRowLastCheck;

  /// Подпись строки «Источник» раскрытой карточки провайдера.
  ///
  /// In en, this message translates to:
  /// **'Source'**
  String get providersRowSource;

  /// Заголовок диалога удаления провайдера. Плейсхолдер id — id провайдера, не переводить.
  ///
  /// In en, this message translates to:
  /// **'Remove provider {id}?'**
  String providersRemoveTitle(String id);

  /// Пояснение диалога удаления провайдера.
  ///
  /// In en, this message translates to:
  /// **'The provider is removed from the config file. Sessions that use its models keep running until the agent reloads.'**
  String get providersRemoveDetails;

  /// Флажок диалога удаления провайдера.
  ///
  /// In en, this message translates to:
  /// **'Also delete the stored key'**
  String get providersRemoveDeleteKey;

  /// Подпись выбора новой модели по умолчанию в диалоге удаления провайдера.
  ///
  /// In en, this message translates to:
  /// **'New default model'**
  String get providersRemoveNewDefault;

  /// Баннер страницы Providers: модель по умолчанию записана.
  ///
  /// In en, this message translates to:
  /// **'Default model saved.'**
  String get providersBannerDefaultModelSaved;

  /// Баннер: провайдер удалён. Плейсхолдер id не переводить.
  ///
  /// In en, this message translates to:
  /// **'Provider {id} removed.'**
  String providersBannerRemoved(String id);

  /// Баннер: провайдер удалён вместе с ключом. Плейсхолдер id не переводить.
  ///
  /// In en, this message translates to:
  /// **'Provider {id} removed. Its stored key was deleted.'**
  String providersBannerRemovedKeyDeleted(String id);

  /// Баннер: провайдер удалён, ключ нужен другим настройкам. Плейсхолдеры id и secret (имя секрета) не переводить.
  ///
  /// In en, this message translates to:
  /// **'Provider {id} removed. The stored key {secret} is kept because other settings still use it.'**
  String providersBannerRemovedKeyKept(String id, String secret);

  /// Баннер: провайдер удалён, секрет остался. Плейсхолдеры id и secret не переводить; команда codelab secret delete не переводится. Метка security (D14): перевод не смягчает смысл предупреждения.
  ///
  /// In en, this message translates to:
  /// **'Provider {id} removed, but its stored key could not be deleted. Delete it with: codelab secret delete {secret}'**
  String providersBannerRemovedKeyFailed(String id, String secret);

  /// Баннер: конфликт записи конфигурации, ничего не записано.
  ///
  /// In en, this message translates to:
  /// **'The config changed on disk, so nothing was saved. The page was reloaded; review it and try again.'**
  String get configConflict;

  /// Конфигурация отклонена проверкой. Плейсхолдер issues — тексты проверки ядра агента (английские, как есть), не переводить.
  ///
  /// In en, this message translates to:
  /// **'The config was not saved: {issues}'**
  String configNotSavedRejected(String issues);

  /// Конфигурация отклонена: секрет значением. Плейсхолдер key — путь ключа конфигурации, не переводить. Метка security (D14): перевод не смягчает смысл предупреждения.
  ///
  /// In en, this message translates to:
  /// **'The config was not saved: {key} must not hold a literal secret.'**
  String configNotSavedInlineSecret(String key);

  /// Запись конфигурации не удалась, тип ошибки неизвестен.
  ///
  /// In en, this message translates to:
  /// **'The config was not saved.'**
  String get configNotSavedPlain;

  /// Запись конфигурации не удалась. Плейсхолдер errorType — имя типа исключения, не переводить; текста исключения нет.
  ///
  /// In en, this message translates to:
  /// **'The config was not saved ({errorType}).'**
  String configNotSavedErrorType(String errorType);

  /// Баннер: мастер провайдера не открылся, конфигурация не читается.
  ///
  /// In en, this message translates to:
  /// **'Cannot open the provider wizard: the agent config cannot be read.'**
  String get providersBannerCannotOpenWizard;

  /// Баннер после мастера: агент не запущен.
  ///
  /// In en, this message translates to:
  /// **'Saved. The agent uses it the next time it starts.'**
  String get providersBannerSavedNextStart;

  /// Баннер после мастера: провайдер записан. Плейсхолдер id не переводить.
  ///
  /// In en, this message translates to:
  /// **'Provider {id} saved.'**
  String providersBannerSaved(String id);

  /// Баннер после мастера: ключ заменён. Плейсхолдер id не переводить; названия кнопки и страницы совпадают с commonRestartAgent и settingsPageConnectionTitle.
  ///
  /// In en, this message translates to:
  /// **'Provider {id} saved. The new key is used after Restart agent (Settings › Connection).'**
  String providersBannerSavedKeyRestart(String id);

  /// Баннер после мастера: модели появятся после перезапуска. Плейсхолдер id не переводить.
  ///
  /// In en, this message translates to:
  /// **'Provider {id} saved. Its models are available after Restart agent (Settings › Connection).'**
  String providersBannerSavedModelsRestart(String id);

  /// Заголовок мастера: добавление провайдера.
  ///
  /// In en, this message translates to:
  /// **'Add provider'**
  String get wizardTitleAdd;

  /// Заголовок мастера: правка провайдера. Плейсхолдер id — id провайдера, не переводить.
  ///
  /// In en, this message translates to:
  /// **'Edit provider {id}'**
  String wizardTitleEdit(String id);

  /// Шаг мастера и заголовок шага: тип API провайдера.
  ///
  /// In en, this message translates to:
  /// **'API type'**
  String get wizardStepApiType;

  /// Шаг мастера и заголовок шага: базовый URL.
  ///
  /// In en, this message translates to:
  /// **'Base URL'**
  String get wizardStepBaseUrl;

  /// Шаг мастера: ключ. Также подпись строки сводки.
  ///
  /// In en, this message translates to:
  /// **'Key'**
  String get wizardStepKey;

  /// Шаг мастера: проверка адреса и ключа.
  ///
  /// In en, this message translates to:
  /// **'Check'**
  String get wizardStepCheck;

  /// Шаг мастера: модель. Также подпись строки сводки.
  ///
  /// In en, this message translates to:
  /// **'Model'**
  String get wizardStepModel;

  /// Шаг мастера: обзор перед записью.
  ///
  /// In en, this message translates to:
  /// **'Review'**
  String get wizardStepReview;

  /// Подпись строки сводки: тип провайдера.
  ///
  /// In en, this message translates to:
  /// **'Type'**
  String get wizardSummaryType;

  /// Подпись строки сводки обзора: провайдер.
  ///
  /// In en, this message translates to:
  /// **'Provider'**
  String get wizardSummaryProvider;

  /// Подпись строки сводки обзора: файл конфигурации.
  ///
  /// In en, this message translates to:
  /// **'File'**
  String get wizardSummaryFile;

  /// Подпись пресета ollama в списке типов API. Ollama — название продукта, не переводить.
  ///
  /// In en, this message translates to:
  /// **'Ollama (local, no key)'**
  String get wizardPresetOllama;

  /// Подпись пресета custom-openai в списке типов API. OpenAI — название продукта, не переводить.
  ///
  /// In en, this message translates to:
  /// **'Custom OpenAI-compatible endpoint'**
  String get wizardPresetCustomOpenAi;

  /// Подпись пресета custom-anthropic в списке типов API. Anthropic — название продукта, не переводить.
  ///
  /// In en, this message translates to:
  /// **'Custom Anthropic-compatible endpoint'**
  String get wizardPresetCustomAnthropic;

  /// Значение строки «Тип» сводки для пресета custom-openai.
  ///
  /// In en, this message translates to:
  /// **'Custom OpenAI-compatible'**
  String get wizardTypeCustomOpenAi;

  /// Значение строки «Тип» сводки для пресета custom-anthropic.
  ///
  /// In en, this message translates to:
  /// **'Custom Anthropic-compatible'**
  String get wizardTypeCustomAnthropic;

  /// Строка «Ключ» сводки: будет записан в хранилище. Плейсхолдеры backend и name (id бэкенда и имя секрета) не переводить.
  ///
  /// In en, this message translates to:
  /// **'Store in {backend} as {name}'**
  String wizardSummaryKeyStore(String backend, String name);

  /// Строка «Ключ» сводки: взять уже сохранённый ключ. Плейсхолдер name — имя секрета, не переводить.
  ///
  /// In en, this message translates to:
  /// **'Use the stored key {name}'**
  String wizardSummaryKeyUseStored(String name);

  /// Вариант шага ключа и значение строки «Ключ» сводки при правке: ключ не меняется.
  ///
  /// In en, this message translates to:
  /// **'Keep the current key'**
  String get wizardKeepCurrentKey;

  /// Строка «Ключ» сводки: ключ из переменной окружения. Плейсхолдер name — имя переменной, не переводить.
  ///
  /// In en, this message translates to:
  /// **'Read from environment variable ({name})'**
  String wizardSummaryKeyEnv(String name);

  /// Строка «Ключ» обзора: секрет в хранилище. Плейсхолдеры name и backend не переводить.
  ///
  /// In en, this message translates to:
  /// **'secret \"{name}\" ({backend})'**
  String wizardPlanKeySecret(String name, String backend);

  /// Строка «Ключ» обзора: ключ не меняется.
  ///
  /// In en, this message translates to:
  /// **'kept as is'**
  String get wizardPlanKeyKept;

  /// Строка «Ключ» обзора: ключ из переменной окружения. Плейсхолдер name не переводить.
  ///
  /// In en, this message translates to:
  /// **'environment variable {name}'**
  String wizardPlanKeyEnv(String name);

  /// Строка «Ключ» обзора: ключа нет.
  ///
  /// In en, this message translates to:
  /// **'none'**
  String get wizardPlanKeyNone;

  /// Заголовок отказа проверки: сервер отклонил ключ. Плейсхолдер status — код HTTP, не переводить.
  ///
  /// In en, this message translates to:
  /// **'Key rejected ({status})'**
  String wizardFailKeyRejectedStatus(int status);

  /// Заголовок отказа проверки: сервер отклонил ключ, кода нет.
  ///
  /// In en, this message translates to:
  /// **'Key rejected'**
  String get wizardFailKeyRejected;

  /// Заголовок отказа проверки: список моделей не найден. Плейсхолдер status — код HTTP, не переводить.
  ///
  /// In en, this message translates to:
  /// **'Model list not found ({status})'**
  String wizardFailNotFound(int status);

  /// Заголовок отказа проверки: сервер недоступен.
  ///
  /// In en, this message translates to:
  /// **'Server unreachable'**
  String get wizardFailUnreachable;

  /// Заголовок отказа проверки: время ожидания. Плейсхолдер seconds — секунды, не переводить.
  ///
  /// In en, this message translates to:
  /// **'Timed out after {seconds} s'**
  String wizardFailTimeout(int seconds);

  /// Заголовок отказа проверки: ошибка TLS.
  ///
  /// In en, this message translates to:
  /// **'TLS error'**
  String get wizardFailTls;

  /// Заголовок отказа проверки: неожиданный ответ. Плейсхолдер status — код HTTP, не переводить.
  ///
  /// In en, this message translates to:
  /// **'Unexpected response ({status})'**
  String wizardFailUnexpectedStatus(int status);

  /// Заголовок отказа проверки: неожиданный ответ, кода нет.
  ///
  /// In en, this message translates to:
  /// **'Unexpected response'**
  String get wizardFailUnexpected;

  /// Пояснение к отказу «Список моделей не найден». GET /models, OpenAI-compatible и /v1 не переводить.
  ///
  /// In en, this message translates to:
  /// **'The server answered, but GET /models does not exist. OpenAI-compatible servers usually live under /v1.'**
  String get wizardFailNotFoundNote;

  /// Вариант шага ключа: использовать уже сохранённый ключ.
  ///
  /// In en, this message translates to:
  /// **'Use the stored key'**
  String get wizardKeyUseStored;

  /// Вариант шага ключа: заменить сохранённый ключ новым.
  ///
  /// In en, this message translates to:
  /// **'Replace it'**
  String get wizardKeyReplace;

  /// Вариант шага ключа: записать в хранилище секретов. Плейсхолдеры backend и name не переводить. Метка security (D14): перевод не смягчает смысл предупреждения.
  ///
  /// In en, this message translates to:
  /// **'Store in {backend} as \"{name}\"'**
  String wizardKeyStore(String backend, String name);

  /// Вариант шага ключа: читать из переменной окружения.
  ///
  /// In en, this message translates to:
  /// **'Read from environment variable'**
  String get wizardKeyEnv;

  /// Вариант шага ключа: переменная окружения с подсказанным именем. Плейсхолдер name не переводить.
  ///
  /// In en, this message translates to:
  /// **'Read from environment variable ({name})'**
  String wizardKeyEnvNamed(String name);

  /// Подпись шага ключа.
  ///
  /// In en, this message translates to:
  /// **'API key source'**
  String get wizardKeySourceLabel;

  /// Подпись скрытого поля ввода ключа API. Значение не показывается.
  ///
  /// In en, this message translates to:
  /// **'API key'**
  String get wizardKeyFieldLabel;

  /// Подпись поля имени переменной окружения.
  ///
  /// In en, this message translates to:
  /// **'Variable name'**
  String get wizardKeyEnvFieldLabel;

  /// Ошибка шага адреса: схема не http и не https.
  ///
  /// In en, this message translates to:
  /// **'Enter an http or https address.'**
  String get wizardErrorAddressInvalid;

  /// Ошибка шага адреса: в адресе учётные данные. Метка security (D14): перевод не смягчает смысл предупреждения.
  ///
  /// In en, this message translates to:
  /// **'Remove the user name and password from the address.'**
  String get wizardErrorAddressUserInfo;

  /// Ошибка шага ключа: ключ не введён.
  ///
  /// In en, this message translates to:
  /// **'Enter the API key.'**
  String get wizardErrorKeyEmpty;

  /// Замечание шага ключа: сохранённый ключ уже есть. Плейсхолдеры name (имя секрета) и backend (id бэкенда) не переводить. Метка security (D14): перевод не смягчает смысл предупреждения.
  ///
  /// In en, this message translates to:
  /// **'A stored key {name} already exists in {backend}.'**
  String wizardErrorKeyAlreadyStored(String name, String backend);

  /// Ошибка шага ключа: оставлять нечего.
  ///
  /// In en, this message translates to:
  /// **'There is no stored key to keep.'**
  String get wizardErrorNothingToKeep;

  /// Ошибка шага ключа: имя переменной не введено.
  ///
  /// In en, this message translates to:
  /// **'Enter the environment variable name.'**
  String get wizardErrorEnvVarEmpty;

  /// Ошибка шага ограничений модели.
  ///
  /// In en, this message translates to:
  /// **'Context window must be a positive number.'**
  String get wizardErrorContextWindow;

  /// Ошибка шага ограничений модели.
  ///
  /// In en, this message translates to:
  /// **'Max output tokens must be a positive number.'**
  String get wizardErrorMaxOutput;

  /// Ошибка правки id провайдера на обзоре. Шаблон [a-z0-9_-]+ не переводить.
  ///
  /// In en, this message translates to:
  /// **'Provider id must be unused and match [a-z0-9_-]+.'**
  String get wizardErrorProviderId;

  /// Ошибка обзора: файл для записи недоступен.
  ///
  /// In en, this message translates to:
  /// **'This target is not available.'**
  String get wizardErrorTargetUnavailable;

  /// Отказ записи плана: id провайдера занят.
  ///
  /// In en, this message translates to:
  /// **'A provider with this id already exists.'**
  String get wizardRefusalProviderExists;

  /// Отказ записи плана: провайдера нет в свежем снимке.
  ///
  /// In en, this message translates to:
  /// **'The provider is no longer in the config.'**
  String get wizardRefusalProviderMissing;

  /// Отказ записи плана: провайдер в нередактируемом слое.
  ///
  /// In en, this message translates to:
  /// **'This provider cannot be edited here.'**
  String get wizardRefusalNotEditable;

  /// Отказ записи плана: провайдер в нескольких файлах.
  ///
  /// In en, this message translates to:
  /// **'This provider is defined in several config files.'**
  String get wizardRefusalSeveralFiles;

  /// Отказ записи плана: файл слоя записи не читается.
  ///
  /// In en, this message translates to:
  /// **'The config file cannot be read.'**
  String get wizardRefusalLayerUnreadable;

  /// Пояснение шага ключа при правке провайдера с ключом открытым текстом. config.yaml не переводить. Метка security (D14): перевод не смягчает смысл предупреждения.
  ///
  /// In en, this message translates to:
  /// **'The key is written in config.yaml. Choose where to keep it instead.'**
  String get wizardKeyNoticeLiteral;

  /// Предупреждение обзора: проверка пропущена. Плейсхолдер reason — вид пропуска (wizardNotVerifiedUnreachable, wizardNotVerifiedTimeout) или значение провода как есть.
  ///
  /// In en, this message translates to:
  /// **'Not verified: {reason}'**
  String wizardNotVerified(String reason);

  /// Вид пропущенной проверки: сервер недоступен. На en — значение провода.
  ///
  /// In en, this message translates to:
  /// **'unreachable'**
  String get wizardNotVerifiedUnreachable;

  /// Вид пропущенной проверки: время ожидания истекло. На en — значение провода.
  ///
  /// In en, this message translates to:
  /// **'timeout'**
  String get wizardNotVerifiedTimeout;

  /// Кнопка подтверждения адреса http:// к другой машине. Метка security (D14): перевод не смягчает смысл предупреждения.
  ///
  /// In en, this message translates to:
  /// **'Use http anyway'**
  String get wizardInsecureConfirm;

  /// Подпись шага проверки: запрос идёт.
  ///
  /// In en, this message translates to:
  /// **'Checking the address and the key…'**
  String get wizardChecking;

  /// Заголовок выбора после отказа «Список моделей не найден».
  ///
  /// In en, this message translates to:
  /// **'How do you want to continue?'**
  String get wizardContinueQuestion;

  /// Вариант после отказа: добавить /v1 к адресу. Плейсхолдер address — адрес, не переводить.
  ///
  /// In en, this message translates to:
  /// **'Use {address}'**
  String wizardUseAddress(String address);

  /// Вариант после отказа: ввести модель вручную.
  ///
  /// In en, this message translates to:
  /// **'Enter the model manually'**
  String get wizardEnterModelManually;

  /// Подпись и подсказка поля идентификатора модели.
  ///
  /// In en, this message translates to:
  /// **'Model id'**
  String get wizardModelId;

  /// Предупреждение перед записью без проверки. Метка security (D14): перевод не смягчает смысл предупреждения.
  ///
  /// In en, this message translates to:
  /// **'The address and the key are not verified, and the model list is not available. You will enter the model yourself.'**
  String get wizardSkipWarning;

  /// Кнопка подтверждения записи без проверки. Метка security (D14): перевод не смягчает смысл предупреждения.
  ///
  /// In en, this message translates to:
  /// **'Continue without check'**
  String get wizardSkipConfirm;

  /// Кнопка: пропустить проверку и сохранить.
  ///
  /// In en, this message translates to:
  /// **'Save without check'**
  String get wizardSaveWithoutCheck;

  /// Пояснение шага модели после пропущенной проверки.
  ///
  /// In en, this message translates to:
  /// **'The model list was not checked: enter the model id.'**
  String get wizardModelNotChecked;

  /// Подпись поля фильтра списка моделей.
  ///
  /// In en, this message translates to:
  /// **'Model (type to filter)'**
  String get wizardModelFilter;

  /// Пункт списка моделей: ввести идентификатор вручную.
  ///
  /// In en, this message translates to:
  /// **'Enter model id manually'**
  String get wizardModelManual;

  /// Заголовок шага ограничений модели. Плейсхолдер model — id модели, не переводить.
  ///
  /// In en, this message translates to:
  /// **'Limits of {model}'**
  String wizardLimitsOf(String model);

  /// Подпись поля окна контекста модели.
  ///
  /// In en, this message translates to:
  /// **'Context window'**
  String get wizardContextWindow;

  /// Подпись поля лимита вывода модели.
  ///
  /// In en, this message translates to:
  /// **'Max output tokens (optional)'**
  String get wizardMaxOutputTokens;

  /// Флажок обзора: сделать модель моделью по умолчанию.
  ///
  /// In en, this message translates to:
  /// **'Make default model'**
  String get wizardMakeDefault;

  /// Флажок обзора: записать только в файл проекта.
  ///
  /// In en, this message translates to:
  /// **'This project only'**
  String get wizardProjectOnly;

  /// Подпись индикатора записи.
  ///
  /// In en, this message translates to:
  /// **'Saving…'**
  String get wizardSaving;

  /// Уведомление обзора после конфликта записи.
  ///
  /// In en, this message translates to:
  /// **'Config changed on disk — review and save again'**
  String get wizardReviewConflict;

  /// Продолжение отказа записи: прежний ключ уже заменён новым. Плейсхолдер name — имя секрета, не переводить. Метка security (D14): перевод не смягчает смысл предупреждения.
  ///
  /// In en, this message translates to:
  /// **'The stored key {name} was already replaced.'**
  String wizardSaveKeyReplaced(String name);

  /// Продолжение отказа записи: откат ключа не удался. Плейсхолдер name — имя секрета; команда codelab secret delete не переводится. Метка security (D14): перевод не смягчает смысл предупреждения.
  ///
  /// In en, this message translates to:
  /// **'The new key {name} is still in the secret store. Delete it with: codelab secret delete {name}'**
  String wizardSaveKeyStillStored(String name);

  /// Вариант шага ключа и значение строки «Ключ» сводки: без ключа.
  ///
  /// In en, this message translates to:
  /// **'No key'**
  String get wizardKeyNone;

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

  /// Ключевые слова поиска «Find a setting» для страницы Connection: слова и короткие фразы через запятую, запятой внутри слова нет, пробелы по краям отбрасываются. Перевод — по глоссарию, строчными буквами; число и порядок слов в переводе не обязаны совпадать с английскими; слова другой страницы не добавлять. Ключи конфигурации, имена протоколов и файлов (stdio, websocket, mcp, agents.md) не переводятся и в перевод не включаются: английские слова ищутся всегда.
  ///
  /// In en, this message translates to:
  /// **'profile, stdio, websocket, token, restart'**
  String get settingsSearchKeywordsConnection;

  /// Ключевые слова поиска «Find a setting» для страницы Providers: слова и короткие фразы через запятую, запятой внутри слова нет, пробелы по краям отбрасываются. Перевод — по глоссарию, строчными буквами; число и порядок слов в переводе не обязаны совпадать с английскими; слова другой страницы не добавлять. Ключи конфигурации, имена протоколов и файлов (stdio, websocket, mcp, agents.md) не переводятся и в перевод не включаются: английские слова ищутся всегда.
  ///
  /// In en, this message translates to:
  /// **'provider, model, api key, key storage, base url'**
  String get settingsSearchKeywordsProviders;

  /// Ключевые слова поиска «Find a setting» для страницы MCP servers: слова и короткие фразы через запятую, запятой внутри слова нет, пробелы по краям отбрасываются. Перевод — по глоссарию, строчными буквами; число и порядок слов в переводе не обязаны совпадать с английскими; слова другой страницы не добавлять. Ключи конфигурации, имена протоколов и файлов (stdio, websocket, mcp, agents.md) не переводятся и в перевод не включаются: английские слова ищутся всегда.
  ///
  /// In en, this message translates to:
  /// **'mcp, server, tools, headers'**
  String get settingsSearchKeywordsMcpServers;

  /// Ключевые слова поиска «Find a setting» для страницы Agents & modes: слова и короткие фразы через запятую, запятой внутри слова нет, пробелы по краям отбрасываются. Перевод — по глоссарию, строчными буквами; число и порядок слов в переводе не обязаны совпадать с английскими; слова другой страницы не добавлять. Ключи конфигурации, имена протоколов и файлов (stdio, websocket, mcp, agents.md) не переводятся и в перевод не включаются: английские слова ищутся всегда.
  ///
  /// In en, this message translates to:
  /// **'mode, permission, bypass, plan, effort, reasoning, agent, definition, subagent'**
  String get settingsSearchKeywordsAgentsAndModes;

  /// Ключевые слова поиска «Find a setting» для страницы Skills & extensions: слова и короткие фразы через запятую, запятой внутри слова нет, пробелы по краям отбрасываются. Перевод — по глоссарию, строчными буквами; число и порядок слов в переводе не обязаны совпадать с английскими; слова другой страницы не добавлять. Ключи конфигурации, имена протоколов и файлов (stdio, websocket, mcp, agents.md) не переводятся и в перевод не включаются: английские слова ищутся всегда.
  ///
  /// In en, this message translates to:
  /// **'skill, agents.md, context, template, prompt, extension'**
  String get settingsSearchKeywordsSkillsAndExtensions;

  /// Ключевые слова поиска «Find a setting» для страницы General: слова и короткие фразы через запятую, запятой внутри слова нет, пробелы по краям отбрасываются. Перевод — по глоссарию, строчными буквами; число и порядок слов в переводе не обязаны совпадать с английскими; слова другой страницы не добавлять. Ключи конфигурации, имена протоколов и файлов (stdio, websocket, mcp, agents.md) не переводятся и в перевод не включаются: английские слова ищутся всегда.
  ///
  /// In en, this message translates to:
  /// **'language, budget, steps, compaction, subagent, log level, startup, reopen, ignored, about, version, license, diagnostics'**
  String get settingsSearchKeywordsGeneral;

  /// Подзаголовок группы строк Agent defaults: раздел реестра настроек агента Budget (ключи budget.*). Английский текст равен имени раздела реестра.
  ///
  /// In en, this message translates to:
  /// **'Budget'**
  String get settingsGeneralGroupBudget;

  /// Подзаголовок группы строк Agent defaults: раздел реестра Agent (compaction.enabled). Английский текст равен имени раздела реестра.
  ///
  /// In en, this message translates to:
  /// **'Agent'**
  String get settingsGeneralGroupAgent;

  /// Подзаголовок группы строк Agent defaults: раздел реестра Subagents (ключи subagents.*). Английский текст равен имени раздела реестра.
  ///
  /// In en, this message translates to:
  /// **'Subagents'**
  String get settingsGeneralGroupSubagents;

  /// Подзаголовок группы строк Agent defaults: раздел реестра Logging (logging.level); речь о журнале агента, а не журнале app. Английский текст равен имени раздела реестра.
  ///
  /// In en, this message translates to:
  /// **'Logging'**
  String get settingsGeneralGroupLogging;

  /// Подпись над записями в диалоге Third-party notices: сами записи показываются как есть, на языке реестра (русский), и не переводятся; подпись объясняет это при любом языке интерфейса. CodeLab — название продукта, не переводить.
  ///
  /// In en, this message translates to:
  /// **'Entries of the CodeLab third-party notices register, as kept in the repository.'**
  String get settingsGeneralAboutThirdPartyCaption;

  /// Заголовок страницы настроек «Keyboard».
  ///
  /// In en, this message translates to:
  /// **'Keyboard shortcuts'**
  String get settingsKeyboardTitle;

  /// Подсказка поля поиска страницы «Keyboard»: ищет по тексту действия и по клавишам в любой нотации.
  ///
  /// In en, this message translates to:
  /// **'Search by action or key'**
  String get settingsKeyboardSearchPlaceholder;

  /// Подпись под полем поиска страницы «Keyboard»: сочетания нельзя менять.
  ///
  /// In en, this message translates to:
  /// **'Read-only list. Shortcuts are fixed in the app.'**
  String get settingsKeyboardReadOnly;

  /// Заголовок колонки таблицы сочетаний: что делает сочетание.
  ///
  /// In en, this message translates to:
  /// **'Action'**
  String get settingsKeyboardColumnAction;

  /// Заголовок колонки таблицы сочетаний: клавиши.
  ///
  /// In en, this message translates to:
  /// **'Shortcut'**
  String get settingsKeyboardColumnShortcut;

  /// Заголовок колонки таблицы сочетаний: где сочетание действует.
  ///
  /// In en, this message translates to:
  /// **'Where'**
  String get settingsKeyboardColumnWhere;

  /// Заголовок группы таблицы сочетаний: сочетания рабочего места, настроек и диалогов.
  ///
  /// In en, this message translates to:
  /// **'Global'**
  String get settingsKeyboardGroupGlobal;

  /// Заголовок группы таблицы сочетаний: сайдбар, панель файлов, дерево файлов.
  ///
  /// In en, this message translates to:
  /// **'Navigation'**
  String get settingsKeyboardGroupNavigation;

  /// Заголовок группы таблицы сочетаний: действия над идущим ходом в ленте.
  ///
  /// In en, this message translates to:
  /// **'Transcript'**
  String get settingsKeyboardGroupTranscript;

  /// Заголовок группы таблицы сочетаний: поле ввода сообщения и меню команд.
  ///
  /// In en, this message translates to:
  /// **'Composer'**
  String get settingsKeyboardGroupComposer;

  /// Заголовок группы таблицы сочетаний: ответы на запросы разрешения агента. Метка security (D14): перевод не смягчает смысл.
  ///
  /// In en, this message translates to:
  /// **'Approvals'**
  String get settingsKeyboardGroupApprovals;

  /// Строка под таблицей сочетаний.
  ///
  /// In en, this message translates to:
  /// **'Agent commands have no shortcuts; open them from the command palette.'**
  String get settingsKeyboardFooter;

  /// Строка вместо таблицы, когда поиск ничего не нашёл. Плейсхолдер query — запрос пользователя как есть, не переводить.
  ///
  /// In en, this message translates to:
  /// **'No shortcuts match \"{query}\"'**
  String settingsKeyboardEmpty(String query);

  /// Действие сочетания Cmd/Ctrl+K в таблице страницы «Keyboard».
  ///
  /// In en, this message translates to:
  /// **'Open the command palette'**
  String get settingsKeyboardActionCommandPalette;

  /// Действие сочетания Cmd/Ctrl+, в таблице страницы «Keyboard».
  ///
  /// In en, this message translates to:
  /// **'Open settings'**
  String get settingsKeyboardActionOpenSettings;

  /// Действие Esc в палитре, диалоге или выдвижной панели.
  ///
  /// In en, this message translates to:
  /// **'Close the command palette, a dialog or a sliding panel'**
  String get settingsKeyboardActionCloseOverlay;

  /// Действие Esc на экране настроек.
  ///
  /// In en, this message translates to:
  /// **'Back to the workbench'**
  String get settingsKeyboardActionLeaveSettings;

  /// Действие сочетания Cmd/Ctrl+B.
  ///
  /// In en, this message translates to:
  /// **'Show or hide the sidebar'**
  String get settingsKeyboardActionToggleSidebar;

  /// Действие сочетания Cmd/Ctrl+Shift+E. Files — название панели.
  ///
  /// In en, this message translates to:
  /// **'Show or hide the Files pane'**
  String get settingsKeyboardActionToggleFiles;

  /// Действие стрелок ↑ и ↓ в дереве файлов.
  ///
  /// In en, this message translates to:
  /// **'Move through files'**
  String get settingsKeyboardActionFileTreeMove;

  /// Действие стрелок → и ← в дереве файлов.
  ///
  /// In en, this message translates to:
  /// **'Expand or collapse a folder'**
  String get settingsKeyboardActionFileTreeFold;

  /// Действие Enter в дереве файлов.
  ///
  /// In en, this message translates to:
  /// **'Open a file or expand a folder'**
  String get settingsKeyboardActionFileTreeOpen;

  /// Действие Esc, пока идёт ход агента.
  ///
  /// In en, this message translates to:
  /// **'Cancel the running turn'**
  String get settingsKeyboardActionCancelTurn;

  /// Действие сочетания Cmd/Ctrl+Enter в поле ввода.
  ///
  /// In en, this message translates to:
  /// **'Send the message; it is queued while the session is busy'**
  String get settingsKeyboardActionSend;

  /// Действие стрелок ↑ и ↓ в меню команд после /.
  ///
  /// In en, this message translates to:
  /// **'Move through commands'**
  String get settingsKeyboardActionCommandMenuMove;

  /// Действие Enter в меню команд после /.
  ///
  /// In en, this message translates to:
  /// **'Run the highlighted command'**
  String get settingsKeyboardActionCommandMenuRun;

  /// Действие Esc в меню команд после /.
  ///
  /// In en, this message translates to:
  /// **'Close the command menu'**
  String get settingsKeyboardActionCommandMenuClose;

  /// Действие сочетания Cmd/Ctrl+Enter при ожидающем одобрении: разрешить один раз. Метка security (D14): перевод не смягчает смысл.
  ///
  /// In en, this message translates to:
  /// **'Allow once'**
  String get settingsKeyboardActionAllowOnce;

  /// Действие сочетания Cmd/Ctrl+Alt+Enter при ожидающем одобрении: разрешить всегда. Метка security (D14): перевод не смягчает смысл.
  ///
  /// In en, this message translates to:
  /// **'Allow always'**
  String get settingsKeyboardActionAllowAlways;

  /// Действие сочетания Cmd/Ctrl+Backspace при ожидающем одобрении: отклонить один раз. Метка security (D14): перевод не смягчает смысл.
  ///
  /// In en, this message translates to:
  /// **'Reject once'**
  String get settingsKeyboardActionRejectOnce;

  /// Действие сочетания Cmd/Ctrl+Alt+Backspace при ожидающем одобрении: отклонить всегда. Метка security (D14): перевод не смягчает смысл.
  ///
  /// In en, this message translates to:
  /// **'Reject always'**
  String get settingsKeyboardActionRejectAlways;

  /// Колонка «Где»: рабочее место.
  ///
  /// In en, this message translates to:
  /// **'Workbench'**
  String get settingsKeyboardWhereWorkbench;

  /// Колонка «Где»: рабочее место при выбранном проекте.
  ///
  /// In en, this message translates to:
  /// **'Workbench, when a project is selected'**
  String get settingsKeyboardWhereWorkbenchProject;

  /// Колонка «Где»: поверхности, которые закрывает Esc.
  ///
  /// In en, this message translates to:
  /// **'Command palette, dialog or sliding panel'**
  String get settingsKeyboardWhereOverlay;

  /// Колонка «Где»: экран настроек.
  ///
  /// In en, this message translates to:
  /// **'Settings'**
  String get settingsKeyboardWhereSettings;

  /// Колонка «Где»: рабочее место при доступной панели Files.
  ///
  /// In en, this message translates to:
  /// **'Workbench, when the Files pane is available'**
  String get settingsKeyboardWhereWorkbenchFiles;

  /// Колонка «Где»: дерево файлов.
  ///
  /// In en, this message translates to:
  /// **'Files tree'**
  String get settingsKeyboardWhereFilesTree;

  /// Колонка «Где»: дерево файлов при выбранной папке.
  ///
  /// In en, this message translates to:
  /// **'Files tree, on a folder'**
  String get settingsKeyboardWhereFilesTreeFolder;

  /// Колонка «Где»: рабочее место или поле ввода во время хода.
  ///
  /// In en, this message translates to:
  /// **'Workbench or composer, while a turn runs'**
  String get settingsKeyboardWhereTurnRunning;

  /// Колонка «Где»: поле ввода сообщения.
  ///
  /// In en, this message translates to:
  /// **'Composer'**
  String get settingsKeyboardWhereComposer;

  /// Колонка «Где»: меню команд, открытое символом /. Символ / не переводится.
  ///
  /// In en, this message translates to:
  /// **'Command menu after /'**
  String get settingsKeyboardWhereCommandMenu;

  /// Колонка «Где» строк одобрения. Метка security (D14): перевод не смягчает смысл.
  ///
  /// In en, this message translates to:
  /// **'Pending approval in focus, when the agent offers this option'**
  String get settingsKeyboardWhereApproval;

  /// Ключевые слова поиска «Find a setting» для страницы Keyboard: слова и короткие фразы через запятую, запятой внутри слова нет, пробелы по краям отбрасываются. Перевод — по глоссарию, строчными буквами; число и порядок слов в переводе не обязаны совпадать с английскими; слова другой страницы не добавлять.
  ///
  /// In en, this message translates to:
  /// **'shortcut, hotkey, keybinding, key'**
  String get settingsSearchKeywordsKeyboard;
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
