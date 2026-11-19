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
  String get commonCancel => 'Отмена';

  @override
  String get commonClose => 'Закрыть';

  @override
  String get commonOpen => 'Открыть';

  @override
  String get commonRetry => 'Повторить';

  @override
  String get commonRestartAgent => 'Перезапустить агента';

  @override
  String get commonNewSession => 'Новая сессия';

  @override
  String get workbenchSessionActive => 'Активна';

  @override
  String workbenchSessionTitleWithId(String id) {
    return 'Сессия $id';
  }

  @override
  String workbenchSessionUpdated(String time) {
    return 'Обновлено $time';
  }

  @override
  String get workbenchNoProject => 'Нет проекта';

  @override
  String get workbenchNoActiveSession => 'Нет активной сессии';

  @override
  String get workbenchOpenProjectHint =>
      'Откройте проект, чтобы начать сессию.';

  @override
  String get workbenchOpenFolder => 'Открыть папку…';

  @override
  String workbenchStartNewSessionIn(String project) {
    return 'Начните новую сессию в $project.';
  }

  @override
  String workbenchStarting(String profile) {
    return 'Запускается $profile…';
  }

  @override
  String get workbenchTranscriptEmptyNoSession =>
      'Начните новую сессию, чтобы поговорить с агентом.';

  @override
  String get workbenchTranscriptEmptySession =>
      'Отправьте сообщение, чтобы начать.';

  @override
  String get workbenchTransportEmbedded => 'Встроенный агент';

  @override
  String get workbenchConnectionStartFailed => 'Не удалось запустить агента.';

  @override
  String workbenchConnectionFailedAgain(String reason, int repeat) {
    return '$reason Повторный сбой ($repeat)';
  }

  @override
  String get workbenchNoProviderConfigured =>
      'Для встроенного агента не настроен провайдер модели.';

  @override
  String get workbenchAddProvider => 'Добавить провайдера';

  @override
  String workbenchProjectFolderMissing(String path) {
    return 'Папка проекта не найдена: $path. Выберите существующую папку через «Открыть папку…».';
  }

  @override
  String get workbenchLinkOpenFailed => 'Не удалось открыть ссылку.';

  @override
  String get workbenchNoticeSessionDetached => 'Сессия отсоединена';

  @override
  String get workbenchNoticeDetachedCannotRestore =>
      'Агент не восстанавливает сессии после переподключения.';

  @override
  String workbenchNoticeDetachedRestoreFailed(String id) {
    return 'Не удалось восстановить сессию $id после переподключения.';
  }

  @override
  String get workbenchNoticeReconnectedCannotRestore =>
      'Агент не восстанавливает сессии; начата новая сессия.';

  @override
  String workbenchNoticeReconnectedRestoreFailed(String id) {
    return 'Не удалось восстановить сессию $id; начата новая сессия.';
  }

  @override
  String get workbenchNoticeMaxTokens =>
      'Модель достигла лимита токенов, поэтому ход завершён.';

  @override
  String get workbenchNoticeMaxTurnRequests =>
      'Ход достиг лимита запросов к модели.';

  @override
  String workbenchNoticeBudgetExceeded(String limit) {
    return 'Ход остановлен: превышен бюджет: $limit.';
  }

  @override
  String get workbenchNoticeRefusal => 'Агент отказался продолжать.';

  @override
  String workbenchNoticeCompletedWithStopReason(String stopReason) {
    return 'Завершено с stopReason $stopReason.';
  }

  @override
  String get workbenchNoticeCompletedStopReasonUnknown =>
      'Завершено, stopReason неизвестен.';

  @override
  String get workbenchFailureAuth =>
      'Агенту не удалось авторизоваться у провайдера модели';

  @override
  String get workbenchFailureProviderUnavailable =>
      'Провайдер модели недоступен';

  @override
  String get workbenchFailureRateLimited =>
      'Достигнут лимит запросов провайдера модели';

  @override
  String get workbenchFailureOverflow => 'Переписка слишком длинная для модели';

  @override
  String get workbenchFailureConnectionLost => 'Подключение к агенту потеряно';

  @override
  String get workbenchFailureGeneric => 'Агенту не удалось завершить ход';

  @override
  String get workbenchFailureConnectionLostBody =>
      'Повторите, чтобы продолжить работу с агентом.';

  @override
  String get workbenchToolKindRead => 'Чтение';

  @override
  String get workbenchToolKindEdit => 'Правка';

  @override
  String get workbenchToolKindDelete => 'Удаление';

  @override
  String get workbenchToolKindMove => 'Перемещение';

  @override
  String get workbenchToolKindSearch => 'Поиск';

  @override
  String get workbenchToolKindExecute => 'Запуск';

  @override
  String get workbenchToolKindFetch => 'Загрузка';

  @override
  String get workbenchApprovalCancelled => 'Отменено';

  @override
  String get workbenchApprovalResolved => 'Решено';

  @override
  String get workbenchToolKindThink => 'Обдумывание';

  @override
  String get workbenchToolKindSwitchMode => 'Режим';

  @override
  String workbenchRequesterWantsToRun(String path) {
    return '$path хочет выполнить';
  }

  @override
  String workbenchAgentRowTokens(String tokens) {
    return 'токены: $tokens';
  }

  @override
  String workbenchAgentRowToolCalls(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count вызова инструмента',
      many: '$count вызовов инструментов',
      few: '$count вызова инструмента',
      one: '$count вызов инструмента',
    );
    return '$_temp0';
  }

  @override
  String get workbenchStatusUsageUnknown => 'расход: —';

  @override
  String get workbenchStatusUsageUnknownTooltip => 'агент не сообщает расход';

  @override
  String workbenchStatusTokenInput(int count) {
    return 'ввод $count';
  }

  @override
  String workbenchStatusTokenOutput(int count) {
    return 'вывод $count';
  }

  @override
  String workbenchStatusTokenCacheRead(int count) {
    return 'чтение кэша $count';
  }

  @override
  String workbenchStatusTokenCacheWrite(int count) {
    return 'запись кэша $count';
  }

  @override
  String workbenchStatusTokenReasoning(int count) {
    return 'рассуждение $count';
  }

  @override
  String workbenchStatusApproximate(String reasons) {
    return 'приблизительно: $reasons';
  }

  @override
  String get usagePartialNoUsage => 'агент не прислал расход для части шагов';

  @override
  String get usagePartialNoPrice => 'цена части шагов неизвестна';

  @override
  String get usagePartialBeforeLoad => 'до загрузки сессии';

  @override
  String get workbenchStatusPriceUnknown => 'цена неизвестна';

  @override
  String workbenchStatusCostWithSession(String turn, String session) {
    return '$turn · сессия $session';
  }

  @override
  String workbenchStatusContext(String fill) {
    return 'контекст $fill';
  }

  @override
  String workbenchStatusContextCompactionSoon(String fill) {
    return 'контекст $fill · скоро сжатие';
  }

  @override
  String get workbenchRootSessionTitle => 'Открыть сессию в корне диска?';

  @override
  String workbenchRootSessionBody(String cwd) {
    return 'Эта сессия работает в корне диска ($cwd). Агент получит доступ ко всему диску. Всё равно открыть?';
  }

  @override
  String get workbenchRestartTitle => 'Перезапустить агента?';

  @override
  String workbenchRestartMessage(String title, int count, String sessions) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count выполняющейся сессии',
      many: '$count выполняющихся сессий',
      few: '$count выполняющиеся сессии',
      one: '$count выполняющуюся сессию',
    );
    return 'Перезапустить $title? Это прервёт $_temp0: $sessions. Промпты в очереди сохранятся.';
  }

  @override
  String get workbenchInspectorTitle => 'Инспектор';

  @override
  String get workbenchInspectorCategoryApproval => 'Одобрение';

  @override
  String get workbenchInspectorCategoryTool => 'Инструмент';

  @override
  String get workbenchInspectorCategoryProtocol => 'Протокол';

  @override
  String get workbenchInspectorCategoryDiagnostic => 'Диагностика';

  @override
  String workbenchInspectorRisk(String risk) {
    return 'Риск $risk';
  }

  @override
  String get workbenchInspectorRawInput => 'Исходные параметры';

  @override
  String get workbenchInspectorRawOutput => 'Исходный вывод';

  @override
  String get workbenchDebugLogTitle => 'Журнал отладки';

  @override
  String get workbenchDebugLogExpand => 'Развернуть';

  @override
  String get paletteNewLabel => 'Новая сессия';

  @override
  String get paletteNewDescription => 'Начать новую ACP-сессию.';

  @override
  String get palettePlanLabel => 'Режим плана';

  @override
  String get palettePlanDescription => 'Перевести ход в планирование.';

  @override
  String get palettePermissionsLabel => 'Разрешения';

  @override
  String get palettePermissionsDescription =>
      'Открыть управление режимом разрешений.';

  @override
  String get paletteLogsLabel => 'Журналы';

  @override
  String get paletteLogsDescription =>
      'Открыть журналы протокола и диагностики.';

  @override
  String get paletteCompactLabel => 'Сжать ленту';

  @override
  String get paletteCompactDescription => 'Подготовить ленту к сжатию.';

  @override
  String get paletteReconnectLabel => 'Переподключиться';

  @override
  String get paletteReconnectDescription =>
      'Повторить текущее подключение к агенту.';

  @override
  String get paletteRestartDescription =>
      'Перезапустить агента выбранным профилем и перезагрузить открытые сессии.';

  @override
  String get paletteFilesLabel => 'Файлы';

  @override
  String get paletteFilesDescription => 'Перейти к панели файлов проекта.';

  @override
  String get paletteAgentsLabel => 'Агенты';

  @override
  String get paletteAgentsDescription => 'Перейти к панели субагентов.';

  @override
  String get paletteUsageLabel => 'Расход';

  @override
  String get paletteUsageDescription => 'Перейти к панели расхода.';

  @override
  String get secretMigrationWarning =>
      'Секреты хранятся в файле конфигурации агента.';

  @override
  String get secretMigrationMigrateSecrets => 'Перенести секреты';

  @override
  String get secretMigrationPlanning => 'Строится план переноса…';

  @override
  String get secretMigrationApplying => 'Секреты переносятся…';

  @override
  String get secretMigrationNothing => 'Переносить нечего.';

  @override
  String get secretMigrationMoved =>
      'Секреты перенесены. Перезапустите встроенного агента, чтобы они вступили в силу.';

  @override
  String get secretMigrationAgentGone =>
      'Встроенный агент больше не подключён.';

  @override
  String get secretMigrationWaitForTurn =>
      'Дождитесь завершения текущего хода.';

  @override
  String secretMigrationPlanFailed(String errorClass) {
    return 'Не удалось построить план: $errorClass.';
  }

  @override
  String secretMigrationApplyFailed(String errorClass) {
    return 'Не удалось выполнить перенос: $errorClass.';
  }

  @override
  String get secretMigrationMigrate => 'Перенести';

  @override
  String get usageTitle => 'Эта сессия';

  @override
  String get usageCardInput => 'Ввод';

  @override
  String get usageCardOutput => 'Вывод';

  @override
  String get usageCardCost => 'Стоимость';

  @override
  String get usageCardTurns => 'Ходы · шаги';

  @override
  String usageDetailCache(String read, String write) {
    return 'чтение кэша $read · запись $write';
  }

  @override
  String usageDetailReasoning(String count) {
    return 'рассуждение $count';
  }

  @override
  String get usageDetailNoUsageYet => 'расхода пока нет';

  @override
  String get usageDetailPriceUnknown => 'цена неизвестна';

  @override
  String usageDetailAverageSteps(String average) {
    return 'в среднем $average шага на ход';
  }

  @override
  String usageStepLabel(int number, String title) {
    return 'шаг $number · $title';
  }

  @override
  String get usageStepReply => 'ответ';

  @override
  String usageStepToolCalls(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count вызова инструмента',
      many: '$count вызовов инструментов',
      few: '$count вызова инструмента',
      one: '$count вызов инструмента',
    );
    return '$_temp0';
  }

  @override
  String usageTurnLabel(int index, String title) {
    return '$index · «$title»';
  }

  @override
  String usageTurnSubagents(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count запуска',
      many: '$count запусков',
      few: '$count запуска',
      one: '$count запуск',
    );
    return 'субагенты · $_temp0';
  }

  @override
  String get usageModelSubagents => 'Субагенты';

  @override
  String get usageModelSummaries => 'Сводки';

  @override
  String usageModelRuns(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count запуска',
      many: '$count запусков',
      few: '$count запуска',
      one: '$count запуск',
    );
    return '$_temp0';
  }

  @override
  String get usageLedgerUpToDate => 'История расхода: актуальна';

  @override
  String get usageLedgerRebuilt => 'пересобрана из журнала';

  @override
  String get usageLedgerInMemory => 'в памяти';

  @override
  String get usageLedgerNotSaved => 'не сохранена';

  @override
  String usageLedgerRecords(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count записи',
      many: '$count записей',
      few: '$count записи',
      one: '$count запись',
    );
    return '$_temp0';
  }

  @override
  String usageLedgerReason(String reason) {
    return '($reason)';
  }

  @override
  String usageLedgerRefreshedHint(String reason) {
    return 'обновлена из журнала сессии ($reason)';
  }

  @override
  String get usageNoteLedgerFailed => 'Не удалось загрузить историю расхода.';

  @override
  String get usageNoteNoLedger =>
      'Этот агент не предоставляет историю расхода.';

  @override
  String get usageNoteSaveFailed => 'Не удалось сохранить файл.';

  @override
  String get usageBudgetThisTurn => 'Этот ход';

  @override
  String get usageBudgetLastTurn => 'Прошлый ход';

  @override
  String get usageBudgetSteps => 'Шаги';

  @override
  String get usageBudgetTokens => 'Токены';

  @override
  String get usageBudgetTime => 'Время';

  @override
  String get usageBudgetTokensHint => 'ввод + вывод, включая субагентов';

  @override
  String get usageBudgetCostNote => 'не проверяется: цена неизвестна';

  @override
  String get usageBudgetFootnote =>
      'При достижении лимита ход останавливается на границе следующего шага.';

  @override
  String terminalTabTitle(int number) {
    return 'Терминал $number';
  }

  @override
  String get terminalStatusStarting => 'Запускается';

  @override
  String get terminalStatusRunning => 'Выполняется';

  @override
  String get terminalStatusExited => 'Завершён';

  @override
  String terminalStatusExitedWithCode(int code) {
    return 'Завершён с кодом $code';
  }

  @override
  String get terminalFailureShellNotFound => 'Оболочка не найдена';

  @override
  String get terminalFailureFolderNotFound => 'Папка не найдена';

  @override
  String get terminalFailureUnavailable => 'Терминал недоступен';

  @override
  String get terminalDisclosure =>
      'Команды здесь выполняются от вашего имени, в обход одобрений агента. Вывод показывается как есть и не очищается от секретов.';

  @override
  String get terminalLinkTitle => 'Открыть ссылку?';

  @override
  String get terminalLinkRefusal =>
      'Можно открывать только ссылки http и https.';

  @override
  String get projectFilesNoFolder =>
      'Выберите проект или начните сессию, чтобы просмотреть его файлы.';

  @override
  String get projectFilesFolderMissing => 'Папка проекта не существует.';

  @override
  String get projectFilesFolderUnreadable =>
      'Не удаётся прочитать папку проекта.';

  @override
  String projectFilesRootOutside(String root) {
    return '$root — за пределами папки проекта';
  }

  @override
  String get projectFilesGitHidden => '.git никогда не показывается';

  @override
  String get projectFilesRefresh => 'Обновить';

  @override
  String get projectFilesSelectFile => 'Выберите файл для просмотра.';

  @override
  String get projectFilesFolderReadFailed => 'Не удаётся прочитать эту папку.';

  @override
  String projectFilesMore(int count) {
    return '… ещё $count';
  }

  @override
  String get projectFilesFailureOutsideRoot =>
      'Этот файл за пределами папки проекта.';

  @override
  String get projectFilesFailureNotFound => 'Файл не найден.';

  @override
  String get projectFilesFailureUnreadable => 'Не удаётся прочитать файл.';

  @override
  String get projectFilesFailureInvalidPath => 'Недопустимый путь к файлу.';

  @override
  String projectFilesSizeKilobytes(int count) {
    return '$count КБ';
  }

  @override
  String projectFilesSizeMegabytes(int count) {
    return '$count МБ';
  }

  @override
  String get settingsShellPendingApproval => 'Агент ждёт вашего одобрения';

  @override
  String get settingsShellBackToSession => 'Вернуться к сессии';

  @override
  String workbenchTokenRejected(int status) {
    return 'Агент отклонил токен (HTTP $status).';
  }

  @override
  String workbenchTokenRequired(int status) {
    return 'Агент требует токен (HTTP $status).';
  }
}
