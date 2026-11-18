import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:intl/intl.dart' as intl;

import 'codelab_localizations_en.dart';
import 'codelab_localizations_ru.dart';

// ignore_for_file: type=lint

/// Callers can lookup localized strings with an instance of CodeLabLocalizations
/// returned by `CodeLabLocalizations.of(context)`.
///
/// Applications need to include `CodeLabLocalizations.delegate()` in their app's
/// `localizationDelegates` list, and the locales they support in the app's
/// `supportedLocales` list. For example:
///
/// ```dart
/// import 'l10n/codelab_localizations.dart';
///
/// return MaterialApp(
///   localizationsDelegates: CodeLabLocalizations.localizationsDelegates,
///   supportedLocales: CodeLabLocalizations.supportedLocales,
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
/// be consistent with the languages listed in the CodeLabLocalizations.supportedLocales
/// property.
abstract class CodeLabLocalizations {
  CodeLabLocalizations(String locale)
    : localeName = intl.Intl.canonicalizedLocale(locale.toString());

  final String localeName;

  static CodeLabLocalizations? of(BuildContext context) {
    return Localizations.of<CodeLabLocalizations>(
      context,
      CodeLabLocalizations,
    );
  }

  static const LocalizationsDelegate<CodeLabLocalizations> delegate =
      _CodeLabLocalizationsDelegate();

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

  /// Тег вызова, который ждёт решения корня, и бейдж шага субагента. Метка security (D14): перевод не смягчает смысл.
  ///
  /// In en, this message translates to:
  /// **'Awaiting approval'**
  String get codeLabApprovalAwaiting;

  /// Кнопка решения «разрешить» в полосе одобрения. Метка security (D14): перевод не смягчает смысл.
  ///
  /// In en, this message translates to:
  /// **'Allow'**
  String get codeLabApprovalAllow;

  /// Кнопка решения «отклонить» в полосе одобрения. Метка security (D14): перевод не смягчает смысл.
  ///
  /// In en, this message translates to:
  /// **'Reject'**
  String get codeLabApprovalReject;

  /// Охват решения: один раз. Метка security (D14): перевод не смягчает смысл.
  ///
  /// In en, this message translates to:
  /// **'Only this time'**
  String get codeLabApprovalScopeOnce;

  /// Охват решения: постоянно, пункт выпадающего списка охвата. Метка security (D14): перевод не смягчает смысл.
  ///
  /// In en, this message translates to:
  /// **'Always'**
  String get codeLabApprovalScopeAlways;

  /// Подсказка и подпись для скринридера значка, который показывает исходные параметры вызова. Метка security (D14): перевод не смягчает смысл.
  ///
  /// In en, this message translates to:
  /// **'View raw input'**
  String get codeLabApprovalViewRawInput;

  /// Подсказка значка, когда исходные параметры уже показаны. Метка security (D14): перевод не смягчает смысл.
  ///
  /// In en, this message translates to:
  /// **'Hide raw input'**
  String get codeLabApprovalHideRawInput;

  /// Подсказка недоступной кнопки решения: у агента нет варианта для выбранного охвата. Метка security (D14): перевод не смягчает смысл.
  ///
  /// In en, this message translates to:
  /// **'The agent offers no such option'**
  String get codeLabApprovalNoSuchOption;

  /// Бейдж выбранного варианта в группе вариантов одобрения.
  ///
  /// In en, this message translates to:
  /// **'Selected'**
  String get codeLabApprovalSelected;

  /// Бейдж нейтрального варианта в группе вариантов одобрения.
  ///
  /// In en, this message translates to:
  /// **'Info'**
  String get codeLabApprovalToneInfo;

  /// Бейдж варианта-акцента в группе вариантов одобрения.
  ///
  /// In en, this message translates to:
  /// **'Option'**
  String get codeLabApprovalToneOption;

  /// Бейдж безопасного варианта в группе вариантов одобрения. Метка security (D14): перевод не смягчает смысл.
  ///
  /// In en, this message translates to:
  /// **'Safe'**
  String get codeLabApprovalToneSafe;

  /// Бейдж варианта, который стоит проверить, в группе вариантов одобрения. Метка security (D14): перевод не смягчает смысл.
  ///
  /// In en, this message translates to:
  /// **'Review'**
  String get codeLabApprovalToneReview;

  /// Бейдж рискованного варианта в группе вариантов одобрения. Метка security (D14): перевод не смягчает смысл.
  ///
  /// In en, this message translates to:
  /// **'Risk'**
  String get codeLabApprovalToneRisk;

  /// Тег риска вызова: действие только читает. Метка security (D14): перевод не смягчает смысл.
  ///
  /// In en, this message translates to:
  /// **'Read-only'**
  String get codeLabRiskReadOnly;

  /// Тег риска вызова, когда агент не сообщил вид действия. Метка security (D14): перевод не смягчает смысл.
  ///
  /// In en, this message translates to:
  /// **'Unknown risk'**
  String get codeLabRiskUnknown;

  /// Тег риска вызова: запись в локальные файлы. Метка security (D14): перевод не смягчает смысл.
  ///
  /// In en, this message translates to:
  /// **'Local write'**
  String get codeLabRiskLocalWrite;

  /// Тег риска вызова: обращение к сети. Метка security (D14): перевод не смягчает смысл.
  ///
  /// In en, this message translates to:
  /// **'Network'**
  String get codeLabRiskNetwork;

  /// Тег риска вызова: выполнение команды в оболочке. Метка security (D14): перевод не смягчает смысл.
  ///
  /// In en, this message translates to:
  /// **'Shell'**
  String get codeLabRiskShell;

  /// Тег риска вызова: действие может необратимо удалить или изменить данные. Метка security (D14): перевод не смягчает смысл.
  ///
  /// In en, this message translates to:
  /// **'Destructive'**
  String get codeLabRiskDestructive;

  /// Статус вызова инструмента: вызов поставлен в очередь и ещё не выполняется.
  ///
  /// In en, this message translates to:
  /// **'Queued'**
  String get codeLabCallQueued;

  /// Статус вызова инструмента: выполняется.
  ///
  /// In en, this message translates to:
  /// **'Running'**
  String get codeLabCallRunning;

  /// Статус вызова инструмента: успешно завершён.
  ///
  /// In en, this message translates to:
  /// **'Done'**
  String get codeLabCallDone;

  /// Статус вызова инструмента: завершился ошибкой.
  ///
  /// In en, this message translates to:
  /// **'Failed'**
  String get codeLabCallFailed;

  /// Статус вызова инструмента: отменён.
  ///
  /// In en, this message translates to:
  /// **'Cancelled'**
  String get codeLabCallCancelled;

  /// Ссылка под командой вызова: скрыть длинную команду.
  ///
  /// In en, this message translates to:
  /// **'Show less'**
  String get codeLabCallShowLess;

  /// Ссылка под командой вызова: показать команду без обрезки.
  ///
  /// In en, this message translates to:
  /// **'Show full command'**
  String get codeLabCallShowFullCommand;

  /// Строка под хвостом вызовов субагента: сколько вызовов не поместилось. Плейсхолдер count — число скрытых вызовов.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, other{+{count} more tool calls}}'**
  String codeLabCallMoreToolCalls(int count);

  /// Подпись раскрывающегося блока подробностей в заметке ленты.
  ///
  /// In en, this message translates to:
  /// **'Details'**
  String get codeLabTranscriptNoticeDetails;

  /// Текст пустой ленты сессии, когда в ней ещё нет строк.
  ///
  /// In en, this message translates to:
  /// **'No transcript yet'**
  String get codeLabTranscriptEmpty;

  /// Бейдж сессии в боковой панели: идёт ход.
  ///
  /// In en, this message translates to:
  /// **'Running'**
  String get codeLabSessionRunning;

  /// Бейдж сессии в боковой панели: ждёт решения об одобрении.
  ///
  /// In en, this message translates to:
  /// **'Approval'**
  String get codeLabSessionApproval;

  /// Бейдж сессии в боковой панели: ход завершился ошибкой.
  ///
  /// In en, this message translates to:
  /// **'Failed'**
  String get codeLabSessionFailed;

  /// Бейдж сессии в боковой панели: ход отменён.
  ///
  /// In en, this message translates to:
  /// **'Cancelled'**
  String get codeLabSessionCancelled;

  /// Бейдж сессии в боковой панели: сессия есть в списке агента, но не загружена в клиент.
  ///
  /// In en, this message translates to:
  /// **'Not loaded'**
  String get codeLabSessionNotLoaded;

  /// Бейдж сессии в боковой панели: сессия потеряла связь с процессом агента.
  ///
  /// In en, this message translates to:
  /// **'Detached'**
  String get codeLabSessionDetached;

  /// Статус соединения в строке подключения: подключение ещё не начиналось.
  ///
  /// In en, this message translates to:
  /// **'Idle'**
  String get codeLabConnectionIdle;

  /// Статус соединения в строке подключения: идёт подключение.
  ///
  /// In en, this message translates to:
  /// **'Connecting'**
  String get codeLabConnectionConnecting;

  /// Статус соединения: установлено. Строка подключения и бейдж app bar.
  ///
  /// In en, this message translates to:
  /// **'Connected'**
  String get codeLabConnectionConnected;

  /// Статус соединения в строке подключения: идёт переподключение.
  ///
  /// In en, this message translates to:
  /// **'Reconnecting'**
  String get codeLabConnectionReconnecting;

  /// Статус соединения: нет подключения. Строка подключения и бейдж app bar.
  ///
  /// In en, this message translates to:
  /// **'Disconnected'**
  String get codeLabConnectionDisconnected;

  /// Статус соединения: установленное соединение оборвалось. Строка подключения и бейдж app bar.
  ///
  /// In en, this message translates to:
  /// **'Connection lost'**
  String get codeLabConnectionLost;

  /// Статус соединения в строке подключения: подключиться не удалось.
  ///
  /// In en, this message translates to:
  /// **'Failed'**
  String get codeLabConnectionFailed;

  /// Подпись бейджа соединения в app bar во время подключения.
  ///
  /// In en, this message translates to:
  /// **'Connecting…'**
  String get codeLabAppBarConnecting;

  /// Подпись бейджа соединения в app bar во время переподключения.
  ///
  /// In en, this message translates to:
  /// **'Reconnecting…'**
  String get codeLabAppBarReconnecting;

  /// Подпись бейджа соединения в app bar, когда подключиться не удалось.
  ///
  /// In en, this message translates to:
  /// **'Connection failed'**
  String get codeLabAppBarConnectionFailed;

  /// Заголовок баннера над лентой: соединение с агентом оборвалось.
  ///
  /// In en, this message translates to:
  /// **'Connection to the agent lost'**
  String get codeLabBannerLost;

  /// Заголовок баннера над лентой: подключиться к агенту не удалось.
  ///
  /// In en, this message translates to:
  /// **'Could not connect to the agent'**
  String get codeLabBannerFailed;

  /// Заголовок баннера над лентой во время переподключения.
  ///
  /// In en, this message translates to:
  /// **'Reconnecting…'**
  String get codeLabBannerReconnecting;

  /// Кнопка баннера: открыть настройки подключения.
  ///
  /// In en, this message translates to:
  /// **'Connection settings'**
  String get codeLabBannerConnectionSettings;

  /// Кнопка экрана подключения: открыть настройки подключения.
  ///
  /// In en, this message translates to:
  /// **'Configure connection'**
  String get codeLabConnectionScreenConfigure;

  /// Кнопка отправки сообщения в композере.
  ///
  /// In en, this message translates to:
  /// **'Send'**
  String get codeLabActionSend;

  /// Кнопка отмены хода в композере.
  ///
  /// In en, this message translates to:
  /// **'Cancel'**
  String get codeLabActionCancel;

  /// Кнопка копирования блока кода и пункт контекстного меню выделения.
  ///
  /// In en, this message translates to:
  /// **'Copy'**
  String get codeLabActionCopy;

  /// Кнопка копирования относительного пути файла в просмотре файла.
  ///
  /// In en, this message translates to:
  /// **'Copy path'**
  String get codeLabActionCopyPath;

  /// Кнопка повтора подключения в app bar.
  ///
  /// In en, this message translates to:
  /// **'Retry'**
  String get codeLabActionRetry;

  /// Кнопка переподключения по умолчанию в баннере и на экране подключения.
  ///
  /// In en, this message translates to:
  /// **'Reconnect'**
  String get codeLabActionReconnect;

  /// Кнопка подключения в app bar и на экране подключения.
  ///
  /// In en, this message translates to:
  /// **'Connect'**
  String get codeLabActionConnect;

  /// Подсказка кнопки изменения сообщения в очереди промптов.
  ///
  /// In en, this message translates to:
  /// **'Edit'**
  String get codeLabActionEdit;

  /// Подсказка кнопки немедленной отправки сообщения из очереди промптов.
  ///
  /// In en, this message translates to:
  /// **'Send now'**
  String get codeLabActionSendNow;

  /// Подсказка кнопки удаления сообщения из очереди промптов.
  ///
  /// In en, this message translates to:
  /// **'Delete'**
  String get codeLabActionDelete;

  /// Подсказка кнопки очистки всей очереди промптов.
  ///
  /// In en, this message translates to:
  /// **'Clear all'**
  String get codeLabActionClearAll;

  /// Ссылка в панели Agents: перейти к вызову, который ждёт одобрения.
  ///
  /// In en, this message translates to:
  /// **'Go to approval'**
  String get codeLabActionGoToApproval;

  /// Ссылка в панели Agents: показать строку субагента в ленте.
  ///
  /// In en, this message translates to:
  /// **'Show in transcript'**
  String get codeLabActionShowInTranscript;

  /// Бейдж команды палитры, которая ещё не реализована.
  ///
  /// In en, this message translates to:
  /// **'Coming soon'**
  String get codeLabActionComingSoon;

  /// Подсказка в пустом поле ввода композера.
  ///
  /// In en, this message translates to:
  /// **'Message the agent'**
  String get codeLabComposerPlaceholder;

  /// Подпись индикатора занятого хода в строке статуса для скринридера.
  ///
  /// In en, this message translates to:
  /// **'Turn in progress'**
  String get codeLabStatusBarTurnInProgress;

  /// Подпись для скринридера заголовка блока размышлений, пока модель размышляет.
  ///
  /// In en, this message translates to:
  /// **'Thinking'**
  String get codeLabThoughtThinkingSemantics;

  /// Заголовок блока размышлений, пока модель размышляет.
  ///
  /// In en, this message translates to:
  /// **'Thinking…'**
  String get codeLabThoughtThinking;

  /// Заголовок завершённого блока размышлений.
  ///
  /// In en, this message translates to:
  /// **'Thoughts'**
  String get codeLabThoughtThoughts;

  /// Чип в шапке сессии: ход идёт.
  ///
  /// In en, this message translates to:
  /// **'Turn running'**
  String get codeLabTurnRunning;

  /// Чип в шапке сессии: ход ждёт решения об одобрении.
  ///
  /// In en, this message translates to:
  /// **'Waiting for approval'**
  String get codeLabTurnWaitingApproval;

  /// Чип в шапке сессии: ход отменяется.
  ///
  /// In en, this message translates to:
  /// **'Cancelling…'**
  String get codeLabTurnCancelling;

  /// Заголовок секции плана в панели активности.
  ///
  /// In en, this message translates to:
  /// **'Plan'**
  String get codeLabPlanTitle;

  /// Метка перед текущей задачей плана в свёрнутой секции.
  ///
  /// In en, this message translates to:
  /// **'Current:'**
  String get codeLabPlanCurrent;

  /// Сколько задач плана ждёт выполнения, в свёрнутой секции плана.
  ///
  /// In en, this message translates to:
  /// **'{count} left'**
  String codeLabPlanLeft(int count);

  /// Число задач плана, пока ни одна не выполнена. Плейсхолдер count — число задач.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, other{{count} Tasks}}'**
  String codeLabPlanTasks(int count);

  /// Подсказка кнопки скрытия плана.
  ///
  /// In en, this message translates to:
  /// **'Clear plan'**
  String get codeLabPlanClear;

  /// Подпись задачи плана, которая ждёт другие задачи. ids — список вида «#1, #2», не переводить.
  ///
  /// In en, this message translates to:
  /// **'blocked by {ids}'**
  String codeLabPlanBlockedBy(String ids);

  /// Тег приоритета задачи плана: высокий.
  ///
  /// In en, this message translates to:
  /// **'High'**
  String get codeLabPlanPriorityHigh;

  /// Тег приоритета задачи плана: средний.
  ///
  /// In en, this message translates to:
  /// **'Medium'**
  String get codeLabPlanPriorityMedium;

  /// Тег приоритета задачи плана: низкий.
  ///
  /// In en, this message translates to:
  /// **'Low'**
  String get codeLabPlanPriorityLow;

  /// Заголовок секции очереди промптов в панели активности.
  ///
  /// In en, this message translates to:
  /// **'Queue'**
  String get codeLabQueueTitle;

  /// Сколько сообщений стоит в очереди промптов.
  ///
  /// In en, this message translates to:
  /// **'{count} queued'**
  String codeLabQueueCount(int count);

  /// Кнопка создания сессии в боковой панели.
  ///
  /// In en, this message translates to:
  /// **'New session'**
  String get codeLabSidebarNewSession;

  /// Подсказка свёрнутой кнопки создания сессии. shortcut — сочетание клавиш, не переводить.
  ///
  /// In en, this message translates to:
  /// **'New session ({shortcut})'**
  String codeLabSidebarNewSessionTooltip(String shortcut);

  /// Подсказка в поле поиска по сессиям.
  ///
  /// In en, this message translates to:
  /// **'Search sessions'**
  String get codeLabSidebarSearchSessions;

  /// Заголовок списка проектов в боковой панели.
  ///
  /// In en, this message translates to:
  /// **'Projects'**
  String get codeLabSidebarProjects;

  /// Кнопка выбора папки проекта в боковой панели и её подсказка в свёрнутом режиме.
  ///
  /// In en, this message translates to:
  /// **'Open folder…'**
  String get codeLabSidebarOpenFolder;

  /// Кнопка перехода в настройки в боковой панели и её подсказка.
  ///
  /// In en, this message translates to:
  /// **'Settings'**
  String get codeLabSidebarSettings;

  /// Текст проекта без сессий в боковой панели.
  ///
  /// In en, this message translates to:
  /// **'No sessions yet'**
  String get codeLabSidebarNoSessions;

  /// Текст проекта, в котором ни одна сессия не подошла под поиск.
  ///
  /// In en, this message translates to:
  /// **'No matching sessions'**
  String get codeLabSidebarNoMatchingSessions;

  /// Кнопка догрузки следующей страницы списка сессий.
  ///
  /// In en, this message translates to:
  /// **'Load more sessions'**
  String get codeLabSidebarLoadMore;

  /// Подпись поля app bar, которое открывает палитру команд.
  ///
  /// In en, this message translates to:
  /// **'Search or run a command'**
  String get codeLabAppBarSearch;

  /// Подсказка кнопки поиска в узком app bar. shortcut — сочетание клавиш, не переводить.
  ///
  /// In en, this message translates to:
  /// **'Search or run a command ({shortcut})'**
  String codeLabAppBarSearchTooltip(String shortcut);

  /// Заголовок поверхности палитры команд.
  ///
  /// In en, this message translates to:
  /// **'Command palette'**
  String get codeLabPaletteTitle;

  /// Текст палитры, когда ни одна команда не подошла под запрос.
  ///
  /// In en, this message translates to:
  /// **'No matching commands'**
  String get codeLabPaletteEmpty;

  /// Заголовок секции команд, объявленных агентом, в палитре команд.
  ///
  /// In en, this message translates to:
  /// **'From agent'**
  String get codeLabPaletteAgentSection;

  /// Название панели дока: дерево файлов проекта.
  ///
  /// In en, this message translates to:
  /// **'Files'**
  String get codeLabPaneFiles;

  /// Название панели дока: различия файлов.
  ///
  /// In en, this message translates to:
  /// **'Diff'**
  String get codeLabPaneDiff;

  /// Название панели дока: терминал.
  ///
  /// In en, this message translates to:
  /// **'Terminal'**
  String get codeLabPaneTerminal;

  /// Название панели дока: план хода.
  ///
  /// In en, this message translates to:
  /// **'Plan'**
  String get codeLabPanePlan;

  /// Название панели дока: хронология сессии.
  ///
  /// In en, this message translates to:
  /// **'Timeline'**
  String get codeLabPaneTimeline;

  /// Название панели дока: субагенты сессии.
  ///
  /// In en, this message translates to:
  /// **'Agents'**
  String get codeLabPaneAgents;

  /// Название панели дока: расход токенов и стоимость.
  ///
  /// In en, this message translates to:
  /// **'Usage'**
  String get codeLabPaneUsage;

  /// Название панели дока: ветки сессии.
  ///
  /// In en, this message translates to:
  /// **'Branches'**
  String get codeLabPaneBranches;

  /// Название панели дока: протокол ACP.
  ///
  /// In en, this message translates to:
  /// **'Protocol'**
  String get codeLabPaneProtocol;

  /// Текст панели Terminal, когда нет открытой сессии.
  ///
  /// In en, this message translates to:
  /// **'Open a session to use the terminal'**
  String get codeLabTerminalNoSession;

  /// Кнопка панели Terminal без вкладок: открыть первый терминал.
  ///
  /// In en, this message translates to:
  /// **'New terminal'**
  String get codeLabTerminalNew;

  /// Начало заголовка панели Agents, после него идут счётчики состояний.
  ///
  /// In en, this message translates to:
  /// **'Subagents'**
  String get codeLabAgentsTitle;

  /// Заголовок дерева шагов выбранного субагента.
  ///
  /// In en, this message translates to:
  /// **'Steps'**
  String get codeLabAgentsSteps;

  /// Слово состояния субагента в строке панели Agents: выполняется. Строчные буквы.
  ///
  /// In en, this message translates to:
  /// **'running'**
  String get codeLabAgentsStateRunning;

  /// Слово состояния субагента: ждёт решения об одобрении. Строчные буквы.
  ///
  /// In en, this message translates to:
  /// **'waiting for approval'**
  String get codeLabAgentsStateWaiting;

  /// Слово состояния субагента: завершён. Строчные буквы.
  ///
  /// In en, this message translates to:
  /// **'done'**
  String get codeLabAgentsStateDone;

  /// Слово состояния субагента: завершился ошибкой. Строчные буквы.
  ///
  /// In en, this message translates to:
  /// **'failed'**
  String get codeLabAgentsStateFailed;

  /// Слово состояния субагента: отменён. Строчные буквы.
  ///
  /// In en, this message translates to:
  /// **'cancelled'**
  String get codeLabAgentsStateCancelled;

  /// Счётчик в заголовке панели Agents: сколько субагентов выполняется.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, other{{count} running}}'**
  String codeLabAgentsCountRunning(int count);

  /// Счётчик в заголовке панели Agents: сколько субагентов ждёт одобрения.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, other{{count} waiting for approval}}'**
  String codeLabAgentsCountWaiting(int count);

  /// Счётчик в заголовке панели Agents: сколько субагентов завершено.
  ///
  /// In en, this message translates to:
  /// **'{count} done'**
  String codeLabAgentsCountDone(int count);

  /// Счётчик в заголовке панели Agents: сколько субагентов завершилось ошибкой.
  ///
  /// In en, this message translates to:
  /// **'{count} failed'**
  String codeLabAgentsCountFailed(int count);

  /// Счётчик в заголовке панели Agents: сколько субагентов отменено.
  ///
  /// In en, this message translates to:
  /// **'{count} cancelled'**
  String codeLabAgentsCountCancelled(int count);

  /// Текст просмотра файла, который не текст. sizeLabel — готовый размер от app, например «12 KB».
  ///
  /// In en, this message translates to:
  /// **'Binary file ({sizeLabel})'**
  String codeLabFileBinary(String sizeLabel);

  /// Текст просмотра файла, когда файл больше предела просмотра. sizeLabel — готовый размер от app.
  ///
  /// In en, this message translates to:
  /// **'File too large to preview ({sizeLabel})'**
  String codeLabFileTooLarge(String sizeLabel);

  /// Предупреждение над просмотром файла, чьё имя похоже на файл с секретами. Метка security (D14): перевод не смягчает смысл.
  ///
  /// In en, this message translates to:
  /// **'This file may contain secrets.'**
  String get codeLabFileSecretWarning;

  /// Подпись ссылки дерева файлов, которая ведёт за пределы проекта и не открывается. Метка security (D14): перевод не смягчает смысл.
  ///
  /// In en, this message translates to:
  /// **'outside, not opened'**
  String get codeLabFileOutsideLink;

  /// Подпись индикатора загрузки панели Usage для скринридера.
  ///
  /// In en, this message translates to:
  /// **'Loading usage history'**
  String get codeLabUsageLoading;

  /// Кнопка панели Usage: пересобрать учёт расхода из журнала сессий.
  ///
  /// In en, this message translates to:
  /// **'Rebuild from log'**
  String get codeLabUsageRebuild;

  /// Кнопка панели Usage: выгрузить расход в файл CSV. CSV — название формата, не переводить.
  ///
  /// In en, this message translates to:
  /// **'Export CSV'**
  String get codeLabUsageExportCsv;

  /// Заголовок таблицы расхода по ходам в панели Usage.
  ///
  /// In en, this message translates to:
  /// **'Per turn'**
  String get codeLabUsagePerTurn;

  /// Заголовок таблицы расхода по моделям в панели Usage.
  ///
  /// In en, this message translates to:
  /// **'Per model'**
  String get codeLabUsagePerModel;

  /// Заголовок столбца входных токенов в таблицах Usage. Короткий.
  ///
  /// In en, this message translates to:
  /// **'Input'**
  String get codeLabUsageColumnInput;

  /// Заголовок столбца выходных токенов в таблицах Usage. Короткий.
  ///
  /// In en, this message translates to:
  /// **'Output'**
  String get codeLabUsageColumnOutput;

  /// Заголовок столбца стоимости в таблицах Usage. Короткий.
  ///
  /// In en, this message translates to:
  /// **'Cost'**
  String get codeLabUsageColumnCost;

  /// Тег строки хода, который ещё идёт, в таблице Usage. Строчные буквы.
  ///
  /// In en, this message translates to:
  /// **'running'**
  String get codeLabUsageRunning;

  /// Подпись для скринридера области app bar в раскладке рабочего места.
  ///
  /// In en, this message translates to:
  /// **'App bar'**
  String get codeLabLayoutAppBar;

  /// Подпись для скринридера области боковой панели сессий.
  ///
  /// In en, this message translates to:
  /// **'Sessions sidebar'**
  String get codeLabLayoutSessionsSidebar;

  /// Подпись для скринридера области сессии с лентой и композером.
  ///
  /// In en, this message translates to:
  /// **'Session pane'**
  String get codeLabLayoutSessionPane;

  /// Подпись для скринридера области дока инструментов.
  ///
  /// In en, this message translates to:
  /// **'Tool dock'**
  String get codeLabLayoutToolDock;

  /// Заголовок окна настроек в строке заголовка навигации настроек.
  ///
  /// In en, this message translates to:
  /// **'Settings'**
  String get codeLabSettingsTitle;

  /// Подсказка в поле поиска по настройкам.
  ///
  /// In en, this message translates to:
  /// **'Find a setting'**
  String get codeLabSettingsFind;

  /// Строка вместо пунктов навигации настроек, когда поиск ничего не нашёл. query — текст запроса пользователя, не переводить.
  ///
  /// In en, this message translates to:
  /// **'No settings match \"{query}\"'**
  String codeLabSettingsNoMatch(String query);

  /// Подпись для скринридера столбца действий таблицы состояния.
  ///
  /// In en, this message translates to:
  /// **'Actions'**
  String get codeLabStatusTableActions;

  /// Пункт контекстного меню выделения ответа агента.
  ///
  /// In en, this message translates to:
  /// **'Select all'**
  String get codeLabMarkdownSelectAll;

  /// Пояснение под блоком, который не удалось разобрать как markdown из-за глубокой вложенности.
  ///
  /// In en, this message translates to:
  /// **'Shown as plain text: nesting is too deep.'**
  String get codeLabMarkdownNestingTooDeep;

  /// Подпись для скринридера отмеченного флажка списка задач в ответе агента.
  ///
  /// In en, this message translates to:
  /// **'Task done'**
  String get codeLabMarkdownTaskDone;

  /// Подпись для скринридера неотмеченного флажка списка задач в ответе агента.
  ///
  /// In en, this message translates to:
  /// **'Task open'**
  String get codeLabMarkdownTaskOpen;

  /// Начало подписи заглушки изображения в ответе агента, дальше идут хост и имя файла.
  ///
  /// In en, this message translates to:
  /// **'Image'**
  String get codeLabMarkdownImage;

  /// Кнопка заглушки изображения: загрузить и показать картинку.
  ///
  /// In en, this message translates to:
  /// **'Show image'**
  String get codeLabMarkdownShowImage;
}

class _CodeLabLocalizationsDelegate
    extends LocalizationsDelegate<CodeLabLocalizations> {
  const _CodeLabLocalizationsDelegate();

  @override
  Future<CodeLabLocalizations> load(Locale locale) {
    return SynchronousFuture<CodeLabLocalizations>(
      lookupCodeLabLocalizations(locale),
    );
  }

  @override
  bool isSupported(Locale locale) =>
      <String>['en', 'ru'].contains(locale.languageCode);

  @override
  bool shouldReload(_CodeLabLocalizationsDelegate old) => false;
}

CodeLabLocalizations lookupCodeLabLocalizations(Locale locale) {
  // Lookup logic when only language code is specified.
  switch (locale.languageCode) {
    case 'en':
      return CodeLabLocalizationsEn();
    case 'ru':
      return CodeLabLocalizationsRu();
  }

  throw FlutterError(
    'CodeLabLocalizations.delegate failed to load unsupported locale "$locale". This is likely '
    'an issue with the localizations generation tool. Please file an issue '
    'on GitHub with a reproducible sample app and the gen-l10n configuration '
    'that was used.',
  );
}
