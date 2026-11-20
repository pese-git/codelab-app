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
  String workbenchRestartMessageEmbedded(int count, String sessions) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count выполняющейся сессии',
      many: '$count выполняющихся сессий',
      few: '$count выполняющиеся сессии',
      one: '$count выполняющуюся сессию',
    );
    return 'Перезапустить встроенного агента? Это прервёт $_temp0: $sessions. Промпты в очереди сохранятся.';
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

  @override
  String get commonSave => 'Сохранить';

  @override
  String get commonRemove => 'Удалить';

  @override
  String get commonBack => 'Назад';

  @override
  String get commonNext => 'Далее';

  @override
  String get commonDone => 'Готово';

  @override
  String get commonEdit => 'Изменить';

  @override
  String get commonCheck => 'Проверить';

  @override
  String get commonDefault => 'По умолчанию';

  @override
  String get commonContinue => 'Продолжить';

  @override
  String get connectionAddProfile => 'Добавить профиль';

  @override
  String get connectionSectionProfiles => 'Профили';

  @override
  String get connectionSectionBehavior => 'Поведение';

  @override
  String get connectionProfilesHelp =>
      'Общие с codelab_cli через profiles.json в \$CODELAB_HOME. Профиль по умолчанию используется при запуске агента, пока вы не выберете другой кнопкой «Использовать».';

  @override
  String get connectionJoinCliTitle =>
      'Присоединиться к сессии, запущенной в CLI';

  @override
  String get connectionJoinCliBody =>
      'На хосте выполните codelab-agent serve --ws <port>; CLI подключается командой codelab -a <profile>. Выберите здесь тот же профиль WebSocket; его сессии появятся в боковой панели.';

  @override
  String get connectionBadgeCurrent => 'Текущий';

  @override
  String get connectionBadgeSelected => 'Выбрано';

  @override
  String get connectionStatusConnecting => 'Подключение…';

  @override
  String get connectionStatusConnected => 'Подключено';

  @override
  String get connectionStatusFailed => 'Сбой';

  @override
  String get connectionRowUse => 'Использовать';

  @override
  String get connectionRowRename => 'Переименовать';

  @override
  String get connectionRowUseAnotherFirst => 'Сначала выберите другой профиль.';

  @override
  String get connectionRowNotSaved => 'Текущее подключение (не сохранено)';

  @override
  String get connectionRenameName => 'Имя';

  @override
  String get connectionEmbeddedAgentTitle => 'Встроенный агент';

  @override
  String get connectionEmbeddedAgentSummary =>
      'Работает внутри CodeLab, отдельного процесса нет.';

  @override
  String get connectionTokenNone => 'Без токена';

  @override
  String connectionTokenFromEnv(String variable) {
    return 'Из $variable';
  }

  @override
  String tokenEnvNotSet(String name) {
    return '$name не задана в окружении CodeLab.';
  }

  @override
  String connectionTokenSecret(String name) {
    return 'Секрет токена «$name»';
  }

  @override
  String connectionTokenSecretSet(String backend) {
    return '$backend · задан';
  }

  @override
  String connectionTokenSecretMissing(String backend) {
    return '$backend · отсутствует';
  }

  @override
  String get connectionTokenUnsupported =>
      'нераспознанная ссылка на токен (в этой версии не поддерживается)';

  @override
  String connectionReadOnlyTitle(String origin) {
    return 'Только чтение: агент работает на $origin';
  }

  @override
  String get settingsRemoteHostHint =>
      'Изменить провайдеров и MCP можно на том хосте: codelab provider add, codelab mcp add, codelab config set.';

  @override
  String get connectionIgnoredDefault =>
      'Профиль «default» в profiles.json игнорируется: default — это встроенный агент. Удалите его командой codelab profiles remove default.';

  @override
  String get connectionIgnoredDefaultRemoveTitle =>
      'Удалить игнорируемый профиль «default»?';

  @override
  String get connectionIgnoredDefaultRemoveDetails =>
      'Из profiles.json удаляется только запись «default»; остальные профили остаются.';

  @override
  String connectionUnreadableWithPath(String path, String reason) {
    return 'Не удаётся прочитать $path: $reason. Исправьте или удалите файл; CodeLab его не перезапишет.';
  }

  @override
  String connectionUnreadableWithoutPath(String reason) {
    return 'Не удаётся использовать профили: $reason.';
  }

  @override
  String get connectionUnreadableUnsupported =>
      'файл имеет неподдерживаемую версию или неверную структуру';

  @override
  String connectionUnreadableCannotRead(String errorType) {
    return 'файл не удаётся прочитать ($errorType)';
  }

  @override
  String get connectionFailureSaveFailed =>
      'Не удалось сохранить изменение. Повторите попытку.';

  @override
  String connectionFailureTokenNotDeleted(String name) {
    return 'Профиль удалён, но сохранённый токен «$name» не удалён. Удалите его командой codelab secret delete $name.';
  }

  @override
  String connectionRemoveTitle(String name) {
    return 'Удалить профиль $name?';
  }

  @override
  String get connectionRemoveDetails =>
      'Запись удаляется из profiles.json. Переменные окружения и другие настройки не затрагиваются.';

  @override
  String connectionRemoveDeleteToken(String name) {
    return 'Также удалить сохранённый токен «$name»';
  }

  @override
  String get connectionReconnect => 'Переподключиться';

  @override
  String get connectionRestartButton => 'Перезапустить';

  @override
  String get connectionRestartHint => 'Запустится, когда вы откроете проект.';

  @override
  String connectionRestartDescription(String subject) {
    return 'Переподключает $subject и перезагружает открытые сессии. Выполняющийся ход прерывается; промпты в очереди сохраняются.';
  }

  @override
  String get connectionRestartDescriptionEmbedded =>
      'Переподключает встроенного агента и перезагружает открытые сессии. Выполняющийся ход прерывается; промпты в очереди сохраняются.';

  @override
  String get connectionRestartSubjectWindow => 'профиль этого окна';

  @override
  String connectionRestartToUse(String subject) {
    return 'Перезапустите агента, чтобы использовать $subject.';
  }

  @override
  String get connectionRestartToUseEmbedded =>
      'Перезапустите агента, чтобы переключиться на встроенного агента.';

  @override
  String get addProfileTitle => 'Добавить профиль подключения';

  @override
  String addProfileSubtitle(String path, String command) {
    return 'Сохраняется в $path и доступен в codelab_cli как $command.';
  }

  @override
  String get addProfileFieldType => 'Тип';

  @override
  String get addProfileFieldName => 'Имя';

  @override
  String get addProfileFieldCommand => 'Команда';

  @override
  String get addProfileFieldArguments => 'Аргументы';

  @override
  String get addProfileFieldFolder => 'Папка';

  @override
  String get addProfileFieldEnvironment => 'Окружение';

  @override
  String get addProfileFieldToken => 'Токен';

  @override
  String get addProfileFieldAfterSaving => 'После сохранения';

  @override
  String get addProfileTypeSemantics => 'Тип профиля';

  @override
  String get addProfileTypeStdio => 'Локальный stdio';

  @override
  String get addProfileTypeStdioNote =>
      'Запускает агента как дочерний процесс для каждого окна и говорит по ACP через stdin/stdout.';

  @override
  String get addProfileTypeWebSocketNote =>
      'Подключается к codelab-agent serve --ws на этой или другой машине.';

  @override
  String get addProfileIdCannotChange => '· нельзя изменить после сохранения';

  @override
  String get addProfileNamePlaceholder => 'devbox 2';

  @override
  String get addProfileArgumentsNote =>
      'Разбираются как в командной оболочке: кавычки и экранирование работают.';

  @override
  String get addProfileRunInProject => 'Запускать в папке проекта';

  @override
  String get addProfileUseByDefault => 'Использовать по умолчанию';

  @override
  String get addProfileUsedWhenAgentStarts =>
      'Используется при запуске агента.';

  @override
  String get addProfileTokenNone => 'Без токена';

  @override
  String get addProfileTokenStored => 'Использовать сохранённый секрет';

  @override
  String get addProfileTokenNew => 'Сохранить новый токен';

  @override
  String get addProfileTokenEnv => 'Из переменной окружения';

  @override
  String get addProfileTokenPaste => 'Вставьте токен';

  @override
  String get addProfileTokenEnvNote =>
      'CodeLab читает токен из этой переменной окружения при подключении. Значения токенов не сохраняются в profiles.json.';

  @override
  String get addProfileTokenEnvFinderNote =>
      'Приложения, открытые из Finder, не видят переменных, заданных в профиле вашей оболочки.';

  @override
  String addProfileStoredSecretsHint(String backend) {
    return 'В $backend нет сохранённых секретов.';
  }

  @override
  String addProfileNewTokenHint(String name, String backend) {
    return 'Сохраняется как «$name» в $backend. Значение больше не показывается и не записывается в profiles.json.';
  }

  @override
  String addProfileSecretStoreReadOnly(String backend) {
    return 'Хранилище секретов $backend доступно только для чтения.';
  }

  @override
  String get addProfileWarningTokenPlaintext =>
      'ws:// к другой машине: токен передаётся без шифрования.';

  @override
  String get addProfileWarningTrafficPlaintext =>
      'ws:// к другой машине: трафик передаётся без шифрования.';

  @override
  String get addProfilePlaintextTitle => 'Соединение без шифрования';

  @override
  String addProfilePlaintextWithToken(String origin) {
    return 'Токен для $origin будет передан открытым текстом. Используйте wss://, если хост это поддерживает.';
  }

  @override
  String addProfilePlaintextWithoutToken(String origin) {
    return 'Промпты и файлы, отправленные на $origin, будут переданы открытым текстом. Используйте wss://, если хост это поддерживает.';
  }

  @override
  String get addProfileSaveAnyway => 'Всё равно сохранить';

  @override
  String get addProfileErrorLabelEmpty => 'Введите имя.';

  @override
  String get addProfileErrorIdEmpty => 'Укажите id.';

  @override
  String addProfileErrorIdReserved(String id) {
    return '«$id» зарезервирован для встроенного агента.';
  }

  @override
  String addProfileErrorIdTaken(String id) {
    return 'Профиль с id «$id» уже существует.';
  }

  @override
  String get addProfileErrorIdInvalid =>
      'Используйте строчные буквы, цифры, «.», «_» и «-» (до 64 символов).';

  @override
  String get addProfileErrorCommandEmpty =>
      'Введите команду, которая запускает агента.';

  @override
  String get addProfileErrorArgsInvalid => 'В аргументах не закрыта кавычка.';

  @override
  String get addProfileErrorUrlInvalid => 'Укажите ws:// или wss:// и хост.';

  @override
  String get addProfileErrorUrlUserInfo =>
      'Уберите имя пользователя и пароль из URL; вместо этого используйте поле «Токен».';

  @override
  String get addProfileErrorTokenEnvNameInvalid =>
      'Имя переменной: буквы, цифры и «_», не может начинаться с цифры.';

  @override
  String get addProfileErrorTokenSecretNameInvalid =>
      'Имя секрета: строчные буквы, цифры и . _ / -, до 128 символов.';

  @override
  String get addProfileErrorTokenSecretEmpty => 'Введите токен.';

  @override
  String get addProfileErrorTokenSecretIdInvalid =>
      'Этот id не подходит для имени сохранённого токена; избегайте «..».';

  @override
  String addProfileErrorTokenSecretExists(String name, String backend) {
    return 'Сохранённый токен «$name» уже есть в $backend. Выберите его в варианте «Использовать сохранённый секрет» или удалите командой codelab secret delete.';
  }

  @override
  String get addProfileSavedTitle => 'Профиль сохранён';

  @override
  String addProfileSavedMessage(String id) {
    return 'Добавлен в profiles.json как «$id»';
  }

  @override
  String get addProfileSavedUsedByDefault => ' · используется по умолчанию';

  @override
  String get addProfileSavedNote =>
      'Работающий агент не изменился. Выберите профиль кнопкой «Использовать» в его строке; применит его «Перезапустить агента».';

  @override
  String get addProfileAddAnother => 'Добавить ещё';

  @override
  String get addProfileFailureProfile =>
      'Не удалось сохранить профиль. Повторите попытку.';

  @override
  String get addProfileFailureSecret =>
      'Не удалось сохранить токен. Повторите попытку.';

  @override
  String addProfileFailureOrphanedToken(String backend, String name) {
    return 'Профиль не сохранён; токен остался в $backend под именем «$name». Удалите его командой codelab secret delete $name.';
  }

  @override
  String get secretStoreReadOnly =>
      'Хранилище секретов доступно только для чтения.';

  @override
  String addProfileErrorEnvSecretLike(String key, String syntax) {
    return '$key похоже на секрет. Задайте его в системном окружении или сошлитесь на него в конфигурации агента как $syntax.';
  }

  @override
  String get providersAdd => 'Добавить провайдера';

  @override
  String get providersDefaultModel => 'Модель по умолчанию';

  @override
  String get providersUsedByNewSessions => 'Используется новыми сессиями.';

  @override
  String providersActiveInSession(String model) {
    return 'Активна в этой сессии: $model';
  }

  @override
  String get providersChooseModel => 'Выберите модель';

  @override
  String providersKeyStorage(String backend) {
    return 'Хранилище ключей: $backend';
  }

  @override
  String get providersKeyStorageDescription =>
      'Читаются только имена и наличие ключей — значения никогда не попадают в приложение';

  @override
  String get providersStorageWritable => 'запись разрешена';

  @override
  String get providersStorageReadOnly => 'только чтение';

  @override
  String providersKeysInOpenFile(String path) {
    return 'Ключи хранятся в открытом файле $path (режим 0600).';
  }

  @override
  String get providersConfigured => 'Настроенные провайдеры';

  @override
  String get providersEmpty =>
      'Провайдеров пока нет. Встроенному агенту нужен хотя бы один, чтобы выполнить ход.';

  @override
  String providersConfigFile(String path) {
    return 'Файл конфигурации: $path';
  }

  @override
  String get providersRemoveHelp =>
      'При удалении запрашивается подтверждение с флажком «Также удалить сохранённый ключ»; при удалении провайдера по умолчанию запрашивается «Новая модель по умолчанию». Строки, определённые в файле проекта, здесь не редактируются.';

  @override
  String providersReadOnlyTitle(String origin) {
    return 'Только чтение: агент работает на $origin.';
  }

  @override
  String providersNotManaged(String agent) {
    return 'Настройками провайдеров управляет $agent.';
  }

  @override
  String get providersUnreadable =>
      'Не удаётся прочитать конфигурацию агента. Исправьте или удалите файл; CodeLab его не перезапишет.';

  @override
  String get providersProblemNoHome => 'Домашняя папка CodeLab недоступна.';

  @override
  String get providersProblemCannotReadSettings =>
      'Не удаётся прочитать настройки агента.';

  @override
  String get providersProblemUserConfig =>
      'Пользовательский config.yaml не удаётся прочитать.';

  @override
  String get providersUnknownKind => 'Неизвестный вид';

  @override
  String providersModelCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count модели',
      many: '$count моделей',
      few: '$count модели',
      one: '$count модель',
    );
    return '$_temp0';
  }

  @override
  String providersDefinedIn(String path) {
    return 'определён в $path';
  }

  @override
  String get providersDefinedInEnvironment => 'определён в окружении';

  @override
  String get providersSourceEnvironment => 'Окружение';

  @override
  String providersKeyLabelInStore(String backend) {
    return 'Ключ: в хранилище $backend';
  }

  @override
  String providersKeyLabelMissing(String backend) {
    return 'Ключ: нет в хранилище $backend';
  }

  @override
  String providersKeyLabelEnvSet(String name) {
    return 'Ключ: переменная $name (задана)';
  }

  @override
  String providersKeyLabelEnvNotSet(String name) {
    return 'Ключ: переменная $name (не задана)';
  }

  @override
  String get providersKeyLabelLiteral =>
      'Ключ: в файле конфигурации (открытым текстом)';

  @override
  String get providersKeyLabelNone => 'Без ключа';

  @override
  String providersKeyInStore(String backend, String name) {
    return 'В $backend как «$name»';
  }

  @override
  String providersKeyNotStored(String backend, String name) {
    return 'Нет в $backend как «$name»';
  }

  @override
  String providersKeyEnvSet(String name) {
    return 'Переменная окружения $name (задана)';
  }

  @override
  String providersKeyEnvNotSet(String name) {
    return 'Переменная окружения $name (не задана)';
  }

  @override
  String get providersKeyLiteral => 'В файле конфигурации (открытым текстом)';

  @override
  String get providersKeyHintLiteral =>
      'Ключ записан в config.yaml. Перенесите его в хранилище секретов: codelab secret migrate.';

  @override
  String settingsKeyUnencryptedToHost(String host) {
    return 'Ключ отправляется в открытом виде на $host.';
  }

  @override
  String providersCheckUnavailable(String kind) {
    return 'Проверка для провайдеров $kind пока недоступна.';
  }

  @override
  String get providersRemoveLast =>
      'Агенту нужен хотя бы один провайдер. Сначала добавьте другого.';

  @override
  String get providersRefusalNotEditable =>
      'Этот провайдер определён в файле только для чтения. Измените его там.';

  @override
  String get providersRefusalSeveralFiles =>
      'Этот провайдер определён в нескольких файлах конфигурации. Измените его там.';

  @override
  String get providersRefusalNewDefault =>
      'Выберите новую модель по умолчанию.';

  @override
  String get providersRefusalDefaultOverridden =>
      'Модель по умолчанию задана в файле, в который CodeLab не пишет. Сначала измените её там.';

  @override
  String get providersRefusalChanged =>
      'Настройки провайдеров изменились. Проверьте страницу и повторите попытку.';

  @override
  String get providersCheckNotChecked => 'не проверялся';

  @override
  String get providersCheckNotCheckedYet => 'Ещё не проверялся';

  @override
  String get providersCheckRunning => 'проверка…';

  @override
  String get providersCheckRunningDetail => 'Проверка…';

  @override
  String providersCheckOkLabel(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count модели',
      many: '$count моделей',
      few: '$count модели',
      one: '$count модель',
    );
    return 'успешно, $_temp0';
  }

  @override
  String providersCheckOkDetail(String time, int count, int ms) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count модели',
      many: '$count моделей',
      few: '$count модели',
      one: '$count модель',
    );
    return '$time · $_temp0 · $ms мс';
  }

  @override
  String providersCheckFailedDetail(String time, String label) {
    return '$time · $label';
  }

  @override
  String providersCheckFailedDetailStatus(
    String time,
    String label,
    int status,
  ) {
    return '$time · $label (HTTP $status)';
  }

  @override
  String get providersCheckUnauthorized => 'не авторизован';

  @override
  String get providersCheckNotFound => 'не найдено';

  @override
  String get providersCheckUnreachable => 'недоступен';

  @override
  String get providersCheckTimeout => 'тайм-аут';

  @override
  String get providersCheckTlsError => 'ошибка TLS';

  @override
  String get providersCheckBadResponse => 'неверный ответ';

  @override
  String get providersCheckKeyMissing => 'Ключ: нет';

  @override
  String get providersCheckKeyMissingDetail => 'Не проверялся: ключа нет';

  @override
  String get providersRowKey => 'Ключ';

  @override
  String get providersRowLastCheck => 'Последняя проверка';

  @override
  String get providersRowSource => 'Источник';

  @override
  String providersRemoveTitle(String id) {
    return 'Удалить провайдера $id?';
  }

  @override
  String get providersRemoveDetails =>
      'Провайдер удаляется из файла конфигурации. Сессии, использующие его модели, продолжают работать, пока агент не перезагрузится.';

  @override
  String get providersRemoveDeleteKey => 'Также удалить сохранённый ключ';

  @override
  String get providersRemoveNewDefault => 'Новая модель по умолчанию';

  @override
  String get providersBannerDefaultModelSaved =>
      'Модель по умолчанию сохранена.';

  @override
  String providersBannerRemoved(String id) {
    return 'Провайдер $id удалён.';
  }

  @override
  String providersBannerRemovedKeyDeleted(String id) {
    return 'Провайдер $id удалён. Его сохранённый ключ удалён.';
  }

  @override
  String providersBannerRemovedKeyKept(String id, String secret) {
    return 'Провайдер $id удалён. Сохранённый ключ «$secret» оставлен, потому что его используют другие настройки.';
  }

  @override
  String providersBannerRemovedKeyFailed(String id, String secret) {
    return 'Провайдер $id удалён, но его сохранённый ключ удалить не удалось. Удалите его командой: codelab secret delete $secret';
  }

  @override
  String get configConflict =>
      'Конфигурация изменилась на диске, поэтому ничего не сохранено. Страница перезагружена; проверьте её и повторите попытку.';

  @override
  String configNotSavedRejected(String issues) {
    return 'Конфигурация не сохранена: $issues';
  }

  @override
  String configNotSavedInlineSecret(String key) {
    return 'Конфигурация не сохранена: $key не должен содержать секрет в открытом виде.';
  }

  @override
  String get configNotSavedPlain => 'Конфигурация не сохранена.';

  @override
  String configNotSavedErrorType(String errorType) {
    return 'Конфигурация не сохранена ($errorType).';
  }

  @override
  String get providersBannerCannotOpenWizard =>
      'Не удаётся открыть мастер провайдера: конфигурация агента не читается.';

  @override
  String get providersBannerSavedNextStart =>
      'Сохранено. Агент использует провайдера при следующем запуске.';

  @override
  String providersBannerSaved(String id) {
    return 'Провайдер $id сохранён.';
  }

  @override
  String providersBannerSavedKeyRestart(String id) {
    return 'Провайдер $id сохранён. Новый ключ вступит в силу после «Перезапустить агента» (Настройки › Подключение).';
  }

  @override
  String providersBannerSavedModelsRestart(String id) {
    return 'Провайдер $id сохранён. Его модели станут доступны после «Перезапустить агента» (Настройки › Подключение).';
  }

  @override
  String get wizardTitleAdd => 'Добавить провайдера';

  @override
  String wizardTitleEdit(String id) {
    return 'Изменить провайдера $id';
  }

  @override
  String get wizardStepApiType => 'Тип API';

  @override
  String get wizardStepBaseUrl => 'Базовый URL';

  @override
  String get wizardStepKey => 'Ключ';

  @override
  String get wizardStepCheck => 'Проверка';

  @override
  String get wizardStepModel => 'Модель';

  @override
  String get wizardStepReview => 'Обзор';

  @override
  String get wizardSummaryType => 'Тип';

  @override
  String get wizardSummaryProvider => 'Провайдер';

  @override
  String get wizardSummaryFile => 'Файл';

  @override
  String get wizardPresetOllama => 'Ollama (локально, без ключа)';

  @override
  String get wizardPresetCustomOpenAi => 'Свой адрес, совместимый с OpenAI';

  @override
  String get wizardPresetCustomAnthropic =>
      'Свой адрес, совместимый с Anthropic';

  @override
  String get wizardTypeCustomOpenAi => 'Свой адрес, совместимый с OpenAI';

  @override
  String get wizardTypeCustomAnthropic => 'Свой адрес, совместимый с Anthropic';

  @override
  String wizardSummaryKeyStore(String backend, String name) {
    return 'Сохранить в $backend как «$name»';
  }

  @override
  String wizardSummaryKeyUseStored(String name) {
    return 'Использовать сохранённый ключ «$name»';
  }

  @override
  String get wizardKeepCurrentKey => 'Оставить текущий ключ';

  @override
  String wizardSummaryKeyEnv(String name) {
    return 'Читать из переменной окружения ($name)';
  }

  @override
  String wizardPlanKeySecret(String name, String backend) {
    return 'секрет «$name» ($backend)';
  }

  @override
  String get wizardPlanKeyKept => 'оставлен как есть';

  @override
  String wizardPlanKeyEnv(String name) {
    return 'переменная окружения $name';
  }

  @override
  String get wizardPlanKeyNone => 'нет';

  @override
  String wizardFailKeyRejectedStatus(int status) {
    return 'Ключ отклонён ($status)';
  }

  @override
  String get wizardFailKeyRejected => 'Ключ отклонён';

  @override
  String wizardFailNotFound(int status) {
    return 'Список моделей не найден ($status)';
  }

  @override
  String get wizardFailUnreachable => 'Сервер недоступен';

  @override
  String wizardFailTimeout(int seconds) {
    return 'Время ожидания истекло: $seconds с';
  }

  @override
  String get wizardFailTls => 'Ошибка TLS';

  @override
  String wizardFailUnexpectedStatus(int status) {
    return 'Неожиданный ответ ($status)';
  }

  @override
  String get wizardFailUnexpected => 'Неожиданный ответ';

  @override
  String get wizardFailNotFoundNote =>
      'Сервер ответил, но GET /models не существует. Серверы OpenAI-compatible обычно находятся по адресу /v1.';

  @override
  String get wizardKeyUseStored => 'Использовать сохранённый ключ';

  @override
  String get wizardKeyReplace => 'Заменить его';

  @override
  String wizardKeyStore(String backend, String name) {
    return 'Сохранить в $backend как «$name»';
  }

  @override
  String get wizardKeyEnv => 'Читать из переменной окружения';

  @override
  String wizardKeyEnvNamed(String name) {
    return 'Читать из переменной окружения ($name)';
  }

  @override
  String get wizardKeySourceLabel => 'Источник ключа API';

  @override
  String get wizardKeyFieldLabel => 'Ключ API';

  @override
  String get wizardKeyEnvFieldLabel => 'Имя переменной';

  @override
  String get wizardErrorAddressInvalid => 'Введите адрес http или https.';

  @override
  String get wizardErrorAddressUserInfo =>
      'Уберите имя пользователя и пароль из адреса.';

  @override
  String get wizardErrorKeyEmpty => 'Введите ключ API.';

  @override
  String wizardErrorKeyAlreadyStored(String name, String backend) {
    return 'Сохранённый ключ «$name» уже есть в $backend.';
  }

  @override
  String get wizardErrorNothingToKeep =>
      'Нет сохранённого ключа, который можно оставить.';

  @override
  String get wizardErrorEnvVarEmpty => 'Введите имя переменной окружения.';

  @override
  String get wizardErrorContextWindow =>
      'Окно контекста должно быть положительным числом.';

  @override
  String get wizardErrorMaxOutput =>
      'Максимум токенов вывода должен быть положительным числом.';

  @override
  String get wizardErrorProviderId =>
      'Id провайдера должен быть свободен и соответствовать [a-z0-9_-]+.';

  @override
  String get wizardErrorTargetUnavailable => 'Эта цель недоступна.';

  @override
  String get wizardRefusalProviderExists =>
      'Провайдер с таким id уже существует.';

  @override
  String get wizardRefusalProviderMissing =>
      'Провайдера больше нет в конфигурации.';

  @override
  String get wizardRefusalNotEditable =>
      'Этот провайдер нельзя изменить здесь.';

  @override
  String get wizardRefusalSeveralFiles =>
      'Этот провайдер определён в нескольких файлах конфигурации.';

  @override
  String get wizardRefusalLayerUnreadable => 'Файл конфигурации не читается.';

  @override
  String get wizardKeyNoticeLiteral =>
      'Ключ записан в config.yaml. Выберите, где его хранить вместо этого.';

  @override
  String wizardNotVerified(String reason) {
    return 'Не проверено: $reason';
  }

  @override
  String get wizardNotVerifiedUnreachable => 'сервер недоступен';

  @override
  String get wizardNotVerifiedTimeout => 'истекло время ожидания';

  @override
  String get wizardInsecureConfirm => 'Всё равно использовать http';

  @override
  String get wizardChecking => 'Проверяем адрес и ключ…';

  @override
  String get wizardContinueQuestion => 'Как продолжить?';

  @override
  String wizardUseAddress(String address) {
    return 'Использовать $address';
  }

  @override
  String get wizardEnterModelManually => 'Ввести модель вручную';

  @override
  String get wizardModelId => 'ID модели';

  @override
  String get wizardSkipWarning =>
      'Адрес и ключ не проверены, список моделей недоступен. Модель придётся ввести самостоятельно.';

  @override
  String get wizardSkipConfirm => 'Продолжить без проверки';

  @override
  String get wizardSaveWithoutCheck => 'Сохранить без проверки';

  @override
  String get wizardModelNotChecked =>
      'Список моделей не проверен: введите ID модели.';

  @override
  String get wizardModelFilter => 'Модель (введите для фильтра)';

  @override
  String get wizardModelManual => 'Ввести ID модели вручную';

  @override
  String wizardLimitsOf(String model) {
    return 'Ограничения $model';
  }

  @override
  String get wizardContextWindow => 'Окно контекста';

  @override
  String get wizardMaxOutputTokens => 'Максимум токенов вывода (необязательно)';

  @override
  String get wizardMakeDefault => 'Сделать моделью по умолчанию';

  @override
  String get wizardProjectOnly => 'Только этот проект';

  @override
  String get wizardSaving => 'Сохранение…';

  @override
  String get wizardReviewConflict =>
      'Конфигурация изменилась на диске — проверьте и сохраните снова';

  @override
  String wizardSaveKeyReplaced(String name) {
    return 'Сохранённый ключ «$name» уже заменён.';
  }

  @override
  String wizardSaveKeyStillStored(String name) {
    return 'Новый ключ «$name» остался в хранилище секретов. Удалите его командой: codelab secret delete $name';
  }

  @override
  String get wizardKeyNone => 'Без ключа';

  @override
  String get agentSettingLabel_budget_max_steps => 'Лимит шагов';

  @override
  String get agentSettingDescription_budget_max_steps =>
      'Запросов к модели за ход.';

  @override
  String get agentSettingLabel_budget_max_tokens => 'Лимит токенов';

  @override
  String get agentSettingDescription_budget_max_tokens =>
      'Сумма входных и выходных токенов за ход.';

  @override
  String get agentSettingLabel_budget_max_cost => 'Лимит стоимости';

  @override
  String get agentSettingDescription_budget_max_cost =>
      'USD за ход; работает только при известных ценах.';

  @override
  String get agentSettingLabel_budget_max_duration => 'Лимит длительности';

  @override
  String get agentSettingDescription_budget_max_duration =>
      'Время хода без ожидания одобрений.';

  @override
  String get agentSettingLabel_subagents_enabled => 'Субагенты';

  @override
  String get agentSettingDescription_subagents_enabled =>
      'Разрешить агенту запускать субагентов (только новые сессии).';

  @override
  String get agentSettingLabel_subagents_max_depth => 'Лимит глубины';

  @override
  String get agentSettingDescription_subagents_max_depth =>
      'Насколько глубоко могут вкладываться субагенты (только новые сессии).';

  @override
  String get agentSettingLabel_subagents_max_concurrent =>
      'Лимит одновременных';

  @override
  String get agentSettingDescription_subagents_max_concurrent =>
      'Субагентов, работающих одновременно в одном дереве сессии.';

  @override
  String get agentSettingLabel_subagents_max_per_turn => 'Лимит за ход';

  @override
  String get agentSettingDescription_subagents_max_per_turn =>
      'Субагентов, запущенных за ход сессии.';

  @override
  String get agentSettingLabel_subagents_max_steps => 'Лимит шагов';

  @override
  String get agentSettingDescription_subagents_max_steps =>
      'Запросов к модели одного субагента.';

  @override
  String get agentSettingLabel_subagents_max_tokens => 'Лимит токенов';

  @override
  String get agentSettingDescription_subagents_max_tokens =>
      'Входных и выходных токенов одного субагента.';

  @override
  String get agentSettingLabel_subagents_max_cost => 'Лимит стоимости';

  @override
  String get agentSettingDescription_subagents_max_cost =>
      'USD одного субагента; работает только при известных ценах.';

  @override
  String get agentSettingLabel_subagents_max_duration => 'Лимит длительности';

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
    return 'Источник значения: $source; изменить здесь нельзя.';
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
    return 'Сохранено для всех проектов; значение переопределено (источник: $source), агент использует $effective.';
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
  String get settingsGeneralSectionStartup => 'Запуск и файлы';

  @override
  String get settingsGeneralReopenTitle =>
      'Открывать последний проект и его вкладки';

  @override
  String get settingsGeneralReopenDescription =>
      'Включено: открывать последний проект и его открытые сессии. Выключено: начинать с недавних проектов в боковой панели. Применится при следующем запуске.';

  @override
  String get settingsGeneralStartupSaveFailed =>
      'Не удалось сохранить настройку. При следующем запуске применится прежнее значение.';

  @override
  String get settingsGeneralSectionAbout => 'О программе';

  @override
  String settingsGeneralAboutSubtitle(String platform, String agentVersion) {
    return '$platform · встроенный агент $agentVersion';
  }

  @override
  String get settingsGeneralAboutLicense => 'Лицензия';

  @override
  String get settingsGeneralAboutConfigFolder => 'Папка настроек';

  @override
  String get settingsGeneralAboutCopyDiagnostics => 'Копировать диагностику';

  @override
  String get settingsGeneralAboutThirdParty => 'Сторонние уведомления';

  @override
  String get settingsGeneralAboutReleaseNotes => 'Заметки о выпуске';

  @override
  String get settingsGeneralAboutOpenLogs => 'Открыть папку журналов';

  @override
  String get settingsGeneralAboutUpdates =>
      'Обновления приходят из установщика или менеджера пакетов — приложение само не обновляется.';

  @override
  String get settingsGeneralAboutCopied => 'Диагностика скопирована.';

  @override
  String get settingsGeneralAboutReleaseNotesFailed =>
      'Не удалось открыть заметки о выпуске.';

  @override
  String get settingsGeneralAboutLogsFailed =>
      'Не удалось открыть папку журналов.';

  @override
  String get settingsGeneralAboutPackageLicenses => 'Лицензии пакетов';

  @override
  String get settingsGeneralAboutClose => 'Закрыть';

  @override
  String get settingsGeneralUnreadableCannotRead =>
      'Не удаётся прочитать настройки агента.';

  @override
  String get settingsGeneralUnreadableHome => 'Папка CodeLab недоступна.';

  @override
  String get settingsGeneralUnreadableUserLayer =>
      'Пользовательский config.yaml не читается.';

  @override
  String get settingsGeneralAboutCopyFailed =>
      'Не удалось скопировать диагностику.';

  @override
  String get settingsGeneralAboutLoadFailed =>
      'Не удалось загрузить раздел «О программе».';

  @override
  String get settingsSearchKeywordsConnection => 'профиль, токен, перезапуск';

  @override
  String get settingsSearchKeywordsProviders =>
      'провайдер, модель, ключ api, хранилище ключей, базовый url';

  @override
  String get settingsSearchKeywordsMcpServers =>
      'сервер, инструменты, заголовки';

  @override
  String get settingsSearchKeywordsAgentsAndModes =>
      'режим, разрешение, план, рассуждение, определение, субагент';

  @override
  String get settingsSearchKeywordsSkillsAndExtensions =>
      'навык, контекст, шаблон, промпт, расширение';

  @override
  String get settingsSearchKeywordsGeneral =>
      'язык, бюджет, шаги, сжатие, субагент, уровень журнала, запуск, открывать, игнорируемые, о программе, версия, лицензия, диагностика';

  @override
  String get settingsGeneralGroupBudget => 'Бюджет';

  @override
  String get settingsGeneralGroupAgent => 'Агент';

  @override
  String get settingsGeneralGroupSubagents => 'Субагенты';

  @override
  String get settingsGeneralGroupLogging => 'Журнал агента';

  @override
  String get settingsGeneralAboutThirdPartyCaption =>
      'Записи реестра сторонних уведомлений CodeLab в том виде, в каком они хранятся в репозитории.';

  @override
  String get mcpAddServer => 'Добавить сервер';

  @override
  String mcpServerCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count сервера',
      many: '$count серверов',
      few: '$count сервера',
      one: '$count сервер',
    );
    return '$_temp0';
  }

  @override
  String get mcpCompositionCaption =>
      'Состав из конфигурации · состояние агента ниже';

  @override
  String get mcpEmpty => 'MCP-серверов пока нет.';

  @override
  String get mcpNewServer => 'Новый сервер';

  @override
  String mcpRemoveTitle(String name) {
    return 'Удалить «$name»?';
  }

  @override
  String get mcpRemoveBody => 'Сервер удаляется из файла конфигурации.';

  @override
  String get mcpRemoveSecretsIntro =>
      'Эти секреты из хранилища будут удалены, если ими больше никто не пользуется:';

  @override
  String get mcpReconnect => 'Переподключить';

  @override
  String get mcpReloadAll => 'Переподключить все';

  @override
  String get mcpRefresh => 'Обновить';

  @override
  String get mcpDisableHere => 'Отключить здесь';

  @override
  String get mcpEnableHere => 'Включить здесь';

  @override
  String get mcpOn => 'Вкл';

  @override
  String get mcpOff => 'Выкл';

  @override
  String mcpNoteProjectFile(String name) {
    return 'Сервер «$name» задан в файле проекта: здесь его нельзя изменить или удалить; «Отключить здесь» записывает enabled: false в .codelab/config.local.yaml.';
  }

  @override
  String mcpNoteDisabledHere(String name) {
    return 'Сервер «$name» отключён в .codelab/config.local.yaml. «Включить здесь» снимает это переопределение.';
  }

  @override
  String get mcpFieldName => 'Имя';

  @override
  String get mcpFieldType => 'Тип';

  @override
  String get mcpFieldCommand => 'Команда';

  @override
  String get mcpFieldArguments => 'Аргументы';

  @override
  String get mcpFieldUrl => 'URL';

  @override
  String get mcpFieldHeaders => 'Заголовки';

  @override
  String get mcpFieldEnvironment => 'Окружение';

  @override
  String get mcpFieldSaveTo => 'Куда сохранить';

  @override
  String get mcpArgumentsNote => 'Один аргумент на строку.';

  @override
  String get mcpAddHeader => '+ Добавить заголовок';

  @override
  String get mcpAddVariable => '+ Добавить переменную';

  @override
  String get mcpMoveNote =>
      'Чтобы перенести сервер в другой файл, удалите его и добавьте снова.';

  @override
  String get mcpTargetUser => 'Пользовательская конфигурация';

  @override
  String get mcpTargetProject => 'Только этот проект';

  @override
  String get mcpValueSecretPlaceholder => 'Значение секрета';

  @override
  String get mcpValueStored => 'сохранён';

  @override
  String get mcpValuePlaceholder => 'Значение';

  @override
  String get mcpHiddenHint => 'Скрыто — оставьте пустым, чтобы не менять';

  @override
  String mcpSecretStoredIn(String backend) {
    return 'Секрет — хранится в $backend';
  }

  @override
  String mcpSecretStoredInAs(String backend, String name) {
    return 'Секрет — хранится в $backend как «$name»';
  }

  @override
  String get mcpReplaceTitle => 'Секрет с таким именем уже есть в хранилище';

  @override
  String get mcpReplaceNewValue =>
      'Новое значение заменит секрет у каждого сервера, который на него ссылается.';

  @override
  String get mcpReplaceRunning =>
      'Работающий агент сохраняет прежнее значение, пока сервер не переподключится.';

  @override
  String get mcpReplaceConfirm => 'Заменить';

  @override
  String get mcpReplaceKeep => 'Оставить';

  @override
  String get mcpProblemNameInvalid =>
      'Используйте имя без пробелов и символов «[», «]», «\"».';

  @override
  String get mcpProblemRenameNotAllowed =>
      'Чтобы переименовать сервер, удалите его и добавьте снова.';

  @override
  String get mcpProblemNameTaken => 'Сервер с таким именем уже есть.';

  @override
  String get mcpProblemCommandEmpty => 'Введите команду.';

  @override
  String get mcpProblemUrlInvalid => 'Введите URL http или https.';

  @override
  String get mcpProblemUrlHasUserinfo =>
      'Уберите имя пользователя и пароль из URL.';

  @override
  String mcpProblemKeyHasSpaces(String key) {
    return 'Уберите пробелы вокруг имени $key.';
  }

  @override
  String mcpProblemKeyDuplicate(String key) {
    return 'Два значения названы $key.';
  }

  @override
  String get mcpProblemKeyEmpty => 'Введите имя для каждого значения.';

  @override
  String mcpProblemSecretValueEmpty(String key) {
    return 'Введите значение секрета для $key.';
  }

  @override
  String mcpProblemSecretNameCollision(String key) {
    return 'Два значения секрета получают одно имя в хранилище; переименуйте $key.';
  }

  @override
  String mcpBannerSaved(String server) {
    return 'Сервер «$server» сохранён.';
  }

  @override
  String mcpBannerSavedRestart(String server) {
    return 'Сервер «$server» сохранён. Он запустится после «Перезапустить агента» (Настройки › Подключение).';
  }

  @override
  String mcpBannerEnabledRestart(String server) {
    return 'Сервер «$server» включён. Он запустится после «Перезапустить агента» (Настройки › Подключение).';
  }

  @override
  String mcpBannerRemoved(String server) {
    return 'Сервер «$server» удалён.';
  }

  @override
  String mcpSecretKept(String name) {
    return 'Секрет «$name» оставлен: он создан не этой страницей.';
  }

  @override
  String mcpSecretStillUsed(String name) {
    return 'Секрет «$name» оставлен: его ещё используют другие настройки.';
  }

  @override
  String mcpSecretDeleteFailed(String name) {
    return 'Не удалось удалить секрет «$name». Удалите его командой: codelab secret delete $name';
  }

  @override
  String mcpSecretNotStored(String reason) {
    return 'Секрет не сохранён, поэтому ничего не записано: $reason';
  }

  @override
  String mcpSecretNotRestored(String name) {
    return 'Сохранённое значение секрета «$name» уже заменено и не может быть восстановлено.';
  }

  @override
  String get mcpRefusalChanged =>
      'Настройки MCP изменились. Проверьте страницу и повторите.';

  @override
  String get mcpRefusalNotEditable =>
      'Этот сервер задан в файле только для чтения. Измените его там.';

  @override
  String get mcpRefusalNotProject =>
      'Здесь можно отключить только сервер из файла проекта.';

  @override
  String get mcpRefusalNoProjectTarget =>
      'Папка проекта неизвестна, поэтому в .codelab/config.local.yaml ничего записать нельзя.';

  @override
  String get mcpFailSettingsChanged =>
      'Настройки MCP-серверов изменились. Проверьте страницу и повторите.';

  @override
  String get mcpFailSecretStore =>
      'Хранилище секретов не удалось прочитать, поэтому ничего не записано.';

  @override
  String get mcpFailChange => 'Изменение не сохранено из-за ошибки.';

  @override
  String get mcpFailConflict =>
      'Файл конфигурации изменился на диске, поэтому ничего не записано. Страница перечитана; проверьте её и повторите.';

  @override
  String mcpFailRejected(String issues) {
    return 'Конфигурация не сохранена: $issues';
  }

  @override
  String get mcpFailConfig => 'Конфигурация не сохранена из-за ошибки.';

  @override
  String get mcpRejectedAfterSave =>
      'Сохранено, но агент отклонил новую конфигурацию';

  @override
  String get mcpRejectedOnOpen => 'Агент отклоняет текущую конфигурацию';

  @override
  String get mcpConfigInvalid => 'Конфигурация: недействительна';

  @override
  String get mcpKeepsRunning =>
      'Пока это не исправлено, агент продолжает работать на прежней конфигурации.';

  @override
  String mcpEditServer(String server) {
    return 'Изменить «$server»';
  }

  @override
  String get mcpStatusTitle => 'Состояние агента';

  @override
  String get mcpColServer => 'Сервер';

  @override
  String get mcpColState => 'Состояние';

  @override
  String get mcpColTools => 'Инструменты';

  @override
  String get mcpColLastError => 'Последняя ошибка';

  @override
  String get mcpStateConnecting => 'подключается';

  @override
  String get mcpStateConnected => 'подключён';

  @override
  String get mcpStateDisabled => 'отключён';

  @override
  String get mcpStateFailed => 'сбой';

  @override
  String mcpStateFailedRetry(String seconds) {
    return 'сбой · повтор через $seconds с';
  }

  @override
  String get mcpStatusUnavailable => 'Откройте сессию, чтобы увидеть состояние';

  @override
  String mcpStatusLive(String time) {
    return 'Текущие данные встроенного агента · $time';
  }

  @override
  String get mcpStatusFooter =>
      'От встроенного агента. Для stdio- и удалённого агента панель показывает ответ /mcp list текстом.';

  @override
  String get mcpListFailed =>
      'Команда /mcp list не завершилась. Нажмите «Обновить» ещё раз.';

  @override
  String get configSourceDefault => 'по умолчанию';

  @override
  String get configSourceUser => 'пользователь';

  @override
  String get configSourceProject => 'проект';

  @override
  String get configSourceLocal => 'локально';

  @override
  String get configSourceFile => 'файл';

  @override
  String get configSourceConfig => 'файл';

  @override
  String get configSourceEnv => 'окружение';

  @override
  String get mcpSourceThisProject => 'этот проект';

  @override
  String mcpSourceDefinedIn(String file) {
    return 'определён в $file';
  }

  @override
  String get agentsSaveToTitle => 'Куда сохранить';

  @override
  String get agentsSaveToDescription =>
      'Одна цель для режима и уровня рассуждения.';

  @override
  String get agentsTargetAll => 'Все проекты';

  @override
  String get agentsTargetProject => 'Только этот проект';

  @override
  String get agentsModeSection => 'Режим разрешений по умолчанию';

  @override
  String get agentsModeCaption =>
      'Новые сессии запускаются в нём после «Перезапустить агента»; для одной сессии измените его в поле ввода.';

  @override
  String agentsModeEffective(String mode) {
    return 'Действует: $mode';
  }

  @override
  String agentsModeSource(String source) {
    return 'Источник: $source';
  }

  @override
  String agentsModeBlocked(String mode) {
    return '$mode (правки и команды запрещены режимом plan)';
  }

  @override
  String get agentsAutopilotHint =>
      'Только как флаг запуска агента (codelab-agent serve --permission-mode autopilot); в конфиге не сохраняется никогда.';

  @override
  String agentsModeNarrowed(String mode) {
    return 'Этот проект недоверенный, поэтому его конфигурация может только ужесточить режим. Новые сессии здесь используют $mode.';
  }

  @override
  String agentsEffortTitle(String source) {
    return 'Уровень рассуждения · $source';
  }

  @override
  String get agentsEffortSection => 'Уровень рассуждения по умолчанию';

  @override
  String get agentsEffortDescription =>
      'Передаётся как опция сессии, только если модель поддерживает рассуждение; для одной сессии измените его в поле ввода.';

  @override
  String get agentsBypassTitle => 'Использовать bypass для новых сессий?';

  @override
  String get agentsBypassBody =>
      'Запрос подтверждения остаётся только для критичных команд, изменений конфигурации агента и сетевых инструментов. Остальные команды выполняются без запроса и тоже могут выходить в сеть. Используйте bypass только в одноразовой копии проекта.';

  @override
  String get agentsBypassConfirm => 'Использовать bypass';

  @override
  String agentsBannerSaved(String value, String when) {
    String _temp0 = intl.Intl.selectLogic(when, {
      'now': 'Сохранено. Новые сессии используют $value.',
      'afterRestart':
          'Сохранено. Новые сессии будут использовать $value после «Перезапустить агента».',
      'whenAgentStarts':
          'Сохранено. Новые сессии будут использовать $value при запуске агента.',
      'other': 'Сохранено. Новые сессии используют $value.',
    });
    return '$_temp0';
  }

  @override
  String agentsBannerOverridden(
    String target,
    String source,
    String value,
    String when,
  ) {
    String _temp0 = intl.Intl.selectLogic(when, {
      'now':
          'Сохранено: $target; значение переопределено (источник: $source), новые сессии используют $value.',
      'afterRestart':
          'Сохранено: $target; значение переопределено (источник: $source), новые сессии будут использовать $value после «Перезапустить агента».',
      'whenAgentStarts':
          'Сохранено: $target; значение переопределено (источник: $source), новые сессии будут использовать $value при запуске агента.',
      'other':
          'Сохранено: $target; значение переопределено (источник: $source), новые сессии используют $value.',
    });
    return '$_temp0';
  }

  @override
  String agentsBannerNarrowed(String target, String value, String when) {
    String _temp0 = intl.Intl.selectLogic(when, {
      'now':
          'Сохранено: $target; режим сужен недоверенным проектом, новые сессии используют $value.',
      'afterRestart':
          'Сохранено: $target; режим сужен недоверенным проектом, новые сессии будут использовать $value после «Перезапустить агента».',
      'whenAgentStarts':
          'Сохранено: $target; режим сужен недоверенным проектом, новые сессии будут использовать $value при запуске агента.',
      'other':
          'Сохранено: $target; режим сужен недоверенным проектом, новые сессии используют $value.',
    });
    return '$_temp0';
  }

  @override
  String agentsBannerSavedOnly(String target) {
    return 'Сохранено: $target.';
  }

  @override
  String get agentsBannerBypassStale =>
      'Настройки изменились, пока диалог был открыт; bypass не сохранён.';

  @override
  String get agentsBannerConflict =>
      'Файл конфигурации изменился на диске, поэтому ничего не записано. Страница перечитана; проверьте её и повторите.';

  @override
  String get agentsBannerNotSaved => 'Конфигурация не сохранена.';

  @override
  String get agentsBannerTargetUnavailable =>
      'Не удалось сохранить: целевой файл конфигурации недоступен.';

  @override
  String get agentsReadOnlyHint =>
      'Измените режимы и агентов на том хосте: codelab config set, .codelab/agents.';

  @override
  String agentsReadOnlyManaged(String agent) {
    return 'Настройками агента управляет $agent.';
  }

  @override
  String get agentsDefinitionsSection => 'Определения агентов';

  @override
  String get agentsDefinitionsCaption =>
      'Определения читаются при создании сессии; для одной сессии выберите определение в меню агента в поле ввода.';

  @override
  String get agentsOpenFolder => 'Открыть папку';

  @override
  String agentsOpenUserFolder(String folder) {
    return 'Определения пользователя ($folder)';
  }

  @override
  String get agentsOpenProjectFolder => 'Этот проект (.codelab/agents)';

  @override
  String get agentsOpenProjectMissing =>
      'Создайте .codelab/agents в проекте, чтобы добавить определения.';

  @override
  String get agentsReload => 'Перечитать';

  @override
  String get agentsColName => 'Имя';

  @override
  String get agentsColDescription => 'Описание';

  @override
  String get agentsColSource => 'Источник';

  @override
  String get agentsColAvailableIn => 'Доступен в';

  @override
  String get agentsColTools => 'Инструменты';

  @override
  String get agentsColModel => 'Модель';

  @override
  String get agentsColStatus => 'Статус';

  @override
  String get agentsColPath => 'Путь';

  @override
  String get agentsColMessage => 'Сообщение';

  @override
  String get agentsBuiltIn => 'встроенный';

  @override
  String get agentsAllTools => 'все';

  @override
  String get agentsSessionModel => 'модель сессии';

  @override
  String get agentsStatusAvailable => 'Доступно';

  @override
  String get agentsStatusOverridden => 'Переопределено';

  @override
  String agentsStatusOverriddenBy(String path) {
    return 'Переопределено: $path';
  }

  @override
  String get agentsStatusModelNotConfigured => 'Модель не настроена';

  @override
  String get agentsStatusError => 'Ошибка';

  @override
  String agentsStatusErrorLine(int line) {
    return 'Ошибка · строка $line';
  }

  @override
  String get agentsStatusDuplicate => 'Не загружено: повторяющееся имя';

  @override
  String get agentsStatusShadowed => 'Перекрыто проектом';

  @override
  String get agentsStatusSubagentsOff => 'Субагенты отключены';

  @override
  String get agentsScopeSession => 'сессия';

  @override
  String get agentsScopeSubagent => 'субагент';

  @override
  String get agentsScopeBoth => 'сессия и субагент';

  @override
  String get agentsErrorTitle => 'Не удалось загрузить определение';

  @override
  String agentsErrorTitleLine(int line) {
    return 'Не удалось загрузить определение · строка $line';
  }

  @override
  String get agentsUntrustedTitle => 'Определения проекта не читаются';

  @override
  String agentsUntrustedBody(String project) {
    return 'Определения в $project/.codelab/agents не читаются: проект недоверенный.';
  }

  @override
  String get agentsUntrustedBodyNoPath =>
      'Определения проекта в .codelab/agents не читаются: проект недоверенный.';

  @override
  String get agentsTimedOut => 'Определения агентов не прочитаны за 5 с.';

  @override
  String get agentsFailed => 'Не удалось прочитать определения агентов.';

  @override
  String get agentsOpenFailedTitle => 'Не удалось открыть папку';

  @override
  String agentsOpenFailedBody(String label) {
    return 'Не удалось открыть $label.';
  }

  @override
  String skillsOpenCodelabTooltipHome(String home) {
    return 'Открыть домашнюю папку CodeLab: $home';
  }

  @override
  String get skillsOpenCodelabTooltipDefault =>
      'Открыть домашнюю папку CodeLab';

  @override
  String skillsOpenCodelabTooltip(String folder) {
    return 'Открыть $folder';
  }

  @override
  String skillsOpenCodelabTooltipOr(String folder, String home) {
    return 'Открыть $folder или $home, если её нет';
  }

  @override
  String get skillsOpenCodelabButton => 'Открыть папку .codelab';

  @override
  String get skillsReload => 'Перечитать';

  @override
  String get skillsNoFolder =>
      'Откройте папку проекта, чтобы увидеть файлы контекста, навыки и шаблоны промптов, которые агент использует в ней.';

  @override
  String get skillsReadOnlyHint =>
      'Навыки, файлы контекста и шаблоны промптов читаются на том хосте: codelab-agent config check.';

  @override
  String skillsReadOnlyManaged(String agent) {
    return 'Навыками управляет $agent.';
  }

  @override
  String get skillsBannerSaved => 'Сохранено';

  @override
  String get skillsBannerNotSaved => 'Не сохранено';

  @override
  String get skillsBannerCannotOpen => 'Не удалось открыть папку';

  @override
  String skillsMsgOpenFailed(String path) {
    return 'Не удалось открыть $path.';
  }

  @override
  String get skillsMsgSaved =>
      'Сохранено. Новые сессии используют это; у открытых сессий навыки остаются прежними.';

  @override
  String get skillsMsgConflict =>
      'Файл конфигурации изменился на диске, поэтому ничего не записано. Страница перечитана; проверьте её и повторите.';

  @override
  String skillsMsgRejected(String issues) {
    return 'Конфигурация не сохранена: $issues';
  }

  @override
  String get skillsMsgNotSaved => 'Конфигурация не сохранена.';

  @override
  String skillsRefusalNotEditable(String source) {
    return 'Задано в $source; измените этот файл.';
  }

  @override
  String skillsRefusalDisabledByProject(String source) {
    return 'Отключено конфигурацией проекта ($source).';
  }

  @override
  String skillsRefusalUntrusted(String element) {
    return 'Сделайте проект доверенным, чтобы читать $element.';
  }

  @override
  String get skillsRefusalUntrustedFolder =>
      'Сделайте проект доверенным, чтобы читать эту папку.';

  @override
  String get skillsRefusalLayerUnreadable =>
      'Файл конфигурации этого слоя не читается. Сначала исправьте его.';

  @override
  String get skillsUntrustedTitle =>
      'Этого проекта нет в trusted_projects, поэтому агент не читает его навыки и шаблоны промптов. Показаны ваши навыки и файлы AGENTS.md.';

  @override
  String skillsUntrustedHint(String path) {
    return 'Доверие задаётся в trusted_projects файла $path.';
  }

  @override
  String get skillsSectionContext => 'Файлы контекста';

  @override
  String get skillsSectionTemplates => 'Шаблоны промптов';

  @override
  String get skillsSectionSkills => 'Навыки';

  @override
  String get skillsContextEmpty => 'Для этой папки нет файлов AGENTS.md.';

  @override
  String get skillsColFile => 'Файл';

  @override
  String get skillsColSize => 'Размер';

  @override
  String get skillsColCommand => 'Команда';

  @override
  String get skillsColSource => 'Источник';

  @override
  String get skillsColSkill => 'Навык';

  @override
  String get skillsColInvokeAs => 'Вызов как';

  @override
  String get skillsColOtherAgents => 'Навыки других агентов';

  @override
  String get skillsColMessage => 'Сообщение';

  @override
  String skillsContextTotal(int count, String size) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count файла',
      many: '$count файлов',
      few: '$count файла',
      one: '$count файл',
    );
    return '$_temp0 · $size';
  }

  @override
  String get skillsContextClaudeAlias =>
      'используется, потому что в этой папке нет AGENTS.md';

  @override
  String get skillsContextOmitted => 'не включён (бюджет)';

  @override
  String skillsContextTruncated(String size) {
    return 'усечён до $size';
  }

  @override
  String get skillsOpen => 'Открыть';

  @override
  String get skillsTemplatesEmpty => 'Шаблонов промптов нет.';

  @override
  String get skillsEmpty => 'Навыки не найдены.';

  @override
  String get skillsSearchOrder =>
      'Порядок поиска: .codelab/skills, затем .agents/skills от этой папки до корня репозитория; затем \$CODELAB_HOME/skills, ~/.agents/skills; дополнительные папки — последними. Ближайший навык переопределяет дальний.';

  @override
  String get skillsListFixed =>
      'Список фиксируется при открытии сессии: новые и изменённые навыки применяются к новым сессиям.';

  @override
  String get skillsTagCommandOnly => 'Только команда';

  @override
  String get skillsInvokeModelOnly => 'Только модель';

  @override
  String skillsToggleLabel(String name) {
    return 'Включён: $name';
  }

  @override
  String get skillsOverridesUser => 'Переопределяет навык пользователя';

  @override
  String get skillsOverridesProject => 'Переопределяет навык проекта';

  @override
  String get skillsOverridesExtra =>
      'Переопределяет навык из дополнительной папки';

  @override
  String get skillsOverridesOther => 'Переопределяет другой навык';

  @override
  String skillsExtraRoot(String entry) {
    return '$entry (дополнительная папка)';
  }

  @override
  String get skillsUnknownRoot => '(неизвестная папка)';

  @override
  String skillsWarningCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count предупреждения',
      many: '$count предупреждений',
      few: '$count предупреждения',
      one: '$count предупреждение',
    );
    return '$_temp0';
  }

  @override
  String skillsConsentRead(String entry) {
    return 'Читать $entry';
  }

  @override
  String skillsConsentFound(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'Найдено $count папки навыков.',
      many: 'Найдено $count папок навыков.',
      few: 'Найдено $count папки навыков.',
      one: 'Найдена $count папка навыков.',
    );
    return '$_temp0';
  }

  @override
  String get skillsConsentNotCounted => 'Число папок навыков не подсчитано.';

  @override
  String get skillsConsentEveryProject =>
      'Согласие действует во всех доверенных проектах.';

  @override
  String get skillsConsentAgentsFolder =>
      'Папка .agents/skills доверенного проекта читается без согласия.';

  @override
  String get skillsPhaseTimedOutContext =>
      'Файлы контекста не прочитаны за 5 с.';

  @override
  String get skillsPhaseTimedOutTemplates =>
      'Шаблоны промптов не прочитаны за 5 с.';

  @override
  String get skillsPhaseTimedOutSkills => 'Навыки не прочитаны за 5 с.';

  @override
  String skillsPhaseFailedContext(String errorType) {
    return 'Файлы контекста не удалось прочитать ($errorType).';
  }

  @override
  String skillsPhaseFailedTemplates(String errorType) {
    return 'Шаблоны промптов не удалось прочитать ($errorType).';
  }

  @override
  String skillsPhaseFailedSkills(String errorType) {
    return 'Навыки не удалось прочитать ($errorType).';
  }

  @override
  String skillsPhaseOff(String source) {
    return 'Навыки отключены: skills.enabled равно false в $source.';
  }

  @override
  String skillsSizeBytes(String size) {
    return '$size Б';
  }

  @override
  String skillsSizeKilobytes(String size) {
    return '$size КБ';
  }

  @override
  String skillsSizeMegabytes(String size) {
    return '$size МБ';
  }

  @override
  String get settingsProblemCannotReadExtensions =>
      'Не удалось прочитать навыки и расширения этой папки.';

  @override
  String get agentsErrorFallbackModel =>
      'Модель этого определения не настроена.';

  @override
  String get agentsErrorFallbackDuplicate =>
      'Не загружено: у другого определения то же имя.';

  @override
  String get agentsErrorFallbackOther => 'Определение не удаётся загрузить.';

  @override
  String get settingsKeyboardTitle => 'Сочетания клавиш';

  @override
  String get settingsKeyboardSearchPlaceholder =>
      'Поиск по действию или клавише';

  @override
  String get settingsKeyboardReadOnly =>
      'Только для чтения. Сочетания заданы в приложении.';

  @override
  String get settingsKeyboardColumnAction => 'Действие';

  @override
  String get settingsKeyboardColumnShortcut => 'Сочетание';

  @override
  String get settingsKeyboardColumnWhere => 'Где';

  @override
  String get settingsKeyboardGroupGlobal => 'Общие';

  @override
  String get settingsKeyboardGroupNavigation => 'Навигация';

  @override
  String get settingsKeyboardGroupTranscript => 'Лента';

  @override
  String get settingsKeyboardGroupComposer => 'Поле ввода';

  @override
  String get settingsKeyboardGroupApprovals => 'Одобрения';

  @override
  String get settingsKeyboardFooter =>
      'У команд агента нет сочетаний — открывайте их из палитры команд.';

  @override
  String settingsKeyboardEmpty(String query) {
    return 'Нет сочетаний по запросу «$query»';
  }

  @override
  String get settingsKeyboardActionCommandPalette => 'Открыть палитру команд';

  @override
  String get settingsKeyboardActionOpenSettings => 'Открыть настройки';

  @override
  String get settingsKeyboardActionCloseOverlay =>
      'Закрыть палитру команд, диалог или выдвижную панель';

  @override
  String get settingsKeyboardActionLeaveSettings =>
      'Вернуться на рабочее место';

  @override
  String get settingsKeyboardActionToggleSidebar =>
      'Показать или скрыть боковую панель';

  @override
  String get settingsKeyboardActionToggleFiles =>
      'Показать или скрыть панель файлов';

  @override
  String get settingsKeyboardActionFileTreeMove => 'Перемещаться по файлам';

  @override
  String get settingsKeyboardActionFileTreeFold =>
      'Раскрыть или свернуть папку';

  @override
  String get settingsKeyboardActionFileTreeOpen =>
      'Открыть файл или раскрыть папку';

  @override
  String get settingsKeyboardActionCancelTurn => 'Отменить идущий ход';

  @override
  String get settingsKeyboardActionSend =>
      'Отправить сообщение; пока сессия занята, оно встаёт в очередь';

  @override
  String get settingsKeyboardActionCommandMenuMove =>
      'Перемещаться по командам';

  @override
  String get settingsKeyboardActionCommandMenuRun =>
      'Выполнить выбранную команду';

  @override
  String get settingsKeyboardActionCommandMenuClose => 'Закрыть меню команд';

  @override
  String get settingsKeyboardActionAllowOnce => 'Разрешить только сейчас';

  @override
  String get settingsKeyboardActionAllowAlways => 'Всегда разрешать';

  @override
  String get settingsKeyboardActionRejectOnce => 'Отклонить только сейчас';

  @override
  String get settingsKeyboardActionRejectAlways => 'Всегда отклонять';

  @override
  String get settingsKeyboardWhereWorkbench => 'Рабочее место';

  @override
  String get settingsKeyboardWhereWorkbenchProject =>
      'Рабочее место, когда выбран проект';

  @override
  String get settingsKeyboardWhereOverlay =>
      'Палитра команд, диалог или выдвижная панель';

  @override
  String get settingsKeyboardWhereSettings => 'Настройки';

  @override
  String get settingsKeyboardWhereWorkbenchFiles =>
      'Рабочее место, когда доступна панель файлов';

  @override
  String get settingsKeyboardWhereFilesTree => 'Дерево файлов';

  @override
  String get settingsKeyboardWhereFilesTreeFolder => 'Дерево файлов, на папке';

  @override
  String get settingsKeyboardWhereTurnRunning =>
      'Рабочее место или поле ввода, пока идёт ход';

  @override
  String get settingsKeyboardWhereComposer => 'Поле ввода';

  @override
  String get settingsKeyboardWhereCommandMenu => 'Меню команд после /';

  @override
  String get settingsKeyboardWhereApprovalAnywhere =>
      'Рабочее место, самое раннее ожидающее одобрение, если в нём есть этот вариант';

  @override
  String get settingsSearchKeywordsKeyboard =>
      'сочетание, горячие клавиши, клавиатура, клавиша';

  @override
  String get settingsKeyboardActionGoToApproval => 'Перейти к одобрению';

  @override
  String get settingsKeyboardWhereApprovalPending =>
      'Рабочее место, пока ждёт одобрение';
}
