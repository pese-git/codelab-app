// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'codelab_localizations.dart';

// ignore_for_file: type=lint

/// The translations for Russian (`ru`).
class CodeLabLocalizationsRu extends CodeLabLocalizations {
  CodeLabLocalizationsRu([String locale = 'ru']) : super(locale);

  @override
  String get codeLabApprovalAwaiting => 'Ждёт одобрения';

  @override
  String get codeLabApprovalAllow => 'Разрешить';

  @override
  String get codeLabApprovalReject => 'Отклонить';

  @override
  String get codeLabApprovalScopeOnce => 'Только сейчас';

  @override
  String get codeLabApprovalScopeAlways => 'Всегда';

  @override
  String get codeLabApprovalViewRawInput => 'Показать исходные параметры';

  @override
  String get codeLabApprovalHideRawInput => 'Скрыть исходные параметры';

  @override
  String get codeLabApprovalNoSuchOption =>
      'Агент не предлагает такого варианта';

  @override
  String get codeLabApprovalSelected => 'Выбрано';

  @override
  String get codeLabApprovalToneInfo => 'Сведения';

  @override
  String get codeLabApprovalToneOption => 'Вариант';

  @override
  String get codeLabApprovalToneSafe => 'Безопасно';

  @override
  String get codeLabApprovalToneReview => 'Требует проверки';

  @override
  String get codeLabApprovalToneRisk => 'Риск';

  @override
  String get codeLabRiskReadOnly => 'Только чтение';

  @override
  String get codeLabRiskUnknown => 'Неизвестный риск';

  @override
  String get codeLabRiskLocalWrite => 'Локальная запись';

  @override
  String get codeLabRiskNetwork => 'Сеть';

  @override
  String get codeLabRiskShell => 'Оболочка';

  @override
  String get codeLabRiskDestructive => 'Разрушительное';

  @override
  String get codeLabCallQueued => 'В очереди';

  @override
  String get codeLabCallRunning => 'Выполняется';

  @override
  String get codeLabCallDone => 'Готово';

  @override
  String get codeLabCallFailed => 'Сбой';

  @override
  String get codeLabCallCancelled => 'Отменено';

  @override
  String get codeLabCallShowLess => 'Свернуть';

  @override
  String get codeLabCallShowFullCommand => 'Показать команду целиком';

  @override
  String codeLabCallMoreToolCalls(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'ещё $count вызова инструмента',
      many: 'ещё $count вызовов инструментов',
      few: 'ещё $count вызова инструмента',
      one: 'ещё $count вызов инструмента',
    );
    return '$_temp0';
  }

  @override
  String get codeLabTranscriptNoticeDetails => 'Подробности';

  @override
  String get codeLabTranscriptEmpty => 'Лента пока пуста';

  @override
  String get codeLabSessionRunning => 'Выполняется';

  @override
  String get codeLabSessionApproval => 'Ждёт одобрения';

  @override
  String get codeLabSessionFailed => 'Сбой';

  @override
  String get codeLabSessionCancelled => 'Отменено';

  @override
  String get codeLabSessionNotLoaded => 'Не загружена';

  @override
  String get codeLabSessionDetached => 'Отсоединена';

  @override
  String get codeLabConnectionIdle => 'Ожидание';

  @override
  String get codeLabConnectionConnecting => 'Подключение…';

  @override
  String get codeLabConnectionConnected => 'Подключено';

  @override
  String get codeLabConnectionReconnecting => 'Переподключение…';

  @override
  String get codeLabConnectionDisconnected => 'Нет подключения';

  @override
  String get codeLabConnectionLost => 'Подключение потеряно';

  @override
  String get codeLabConnectionFailed => 'Сбой';

  @override
  String get codeLabAppBarConnecting => 'Подключение…';

  @override
  String get codeLabAppBarReconnecting => 'Переподключение…';

  @override
  String get codeLabAppBarConnectionFailed => 'Не удалось подключиться';

  @override
  String get codeLabBannerLost => 'Подключение к агенту потеряно';

  @override
  String get codeLabBannerFailed => 'Не удалось подключиться к агенту';

  @override
  String get codeLabBannerReconnecting => 'Переподключение…';

  @override
  String get codeLabBannerConnectionSettings => 'Настройки подключения';

  @override
  String get codeLabConnectionScreenConfigure => 'Настроить подключение';

  @override
  String get codeLabActionSend => 'Отправить';

  @override
  String get codeLabActionCancel => 'Отмена';

  @override
  String get codeLabActionCopy => 'Копировать';

  @override
  String get codeLabActionCopyPath => 'Копировать путь';

  @override
  String get codeLabActionRetry => 'Повторить';

  @override
  String get codeLabActionReconnect => 'Переподключиться';

  @override
  String get codeLabActionConnect => 'Подключиться';

  @override
  String get codeLabActionEdit => 'Изменить';

  @override
  String get codeLabActionSendNow => 'Отправить сейчас';

  @override
  String get codeLabActionDelete => 'Удалить';

  @override
  String get codeLabActionClearAll => 'Очистить всё';

  @override
  String get codeLabActionGoToApproval => 'Перейти к одобрению';

  @override
  String get codeLabActionShowInTranscript => 'Показать в ленте';

  @override
  String get codeLabActionComingSoon => 'Скоро';

  @override
  String get codeLabComposerPlaceholder => 'Сообщение агенту';

  @override
  String get codeLabStatusBarTurnInProgress => 'Ход выполняется';

  @override
  String get codeLabThoughtThinkingSemantics => 'Размышление';

  @override
  String get codeLabThoughtThinking => 'Размышление…';

  @override
  String get codeLabThoughtThoughts => 'Размышления';

  @override
  String get codeLabTurnRunning => 'Ход выполняется';

  @override
  String get codeLabTurnWaitingApproval => 'Ждёт одобрения';

  @override
  String get codeLabTurnCancelling => 'Отменяется…';

  @override
  String get codeLabPlanTitle => 'План';

  @override
  String get codeLabPlanCurrent => 'Сейчас:';

  @override
  String codeLabPlanLeft(int count) {
    return 'осталось $count';
  }

  @override
  String codeLabPlanTasks(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count задачи',
      many: '$count задач',
      few: '$count задачи',
      one: '$count задача',
    );
    return '$_temp0';
  }

  @override
  String get codeLabPlanClear => 'Очистить план';

  @override
  String codeLabPlanBlockedBy(String ids) {
    return 'заблокировано: $ids';
  }

  @override
  String get codeLabPlanPriorityHigh => 'Высокий';

  @override
  String get codeLabPlanPriorityMedium => 'Средний';

  @override
  String get codeLabPlanPriorityLow => 'Низкий';

  @override
  String get codeLabQueueTitle => 'Очередь';

  @override
  String codeLabQueueCount(int count) {
    return 'в очереди: $count';
  }

  @override
  String get codeLabSidebarNewSession => 'Новая сессия';

  @override
  String codeLabSidebarNewSessionTooltip(String shortcut) {
    return 'Новая сессия ($shortcut)';
  }

  @override
  String get codeLabSidebarSearchSessions => 'Поиск сессий';

  @override
  String get codeLabSidebarProjects => 'Проекты';

  @override
  String get codeLabSidebarOpenFolder => 'Открыть папку…';

  @override
  String get codeLabSidebarNoRecentProjects => 'Недавних проектов пока нет.';

  @override
  String get codeLabSidebarSettings => 'Настройки';

  @override
  String get codeLabSidebarNoSessions => 'Сессий пока нет';

  @override
  String get codeLabSidebarNoMatchingSessions => 'Нет подходящих сессий';

  @override
  String get codeLabSidebarLoadMore => 'Загрузить ещё сессии';

  @override
  String get codeLabAppBarSearch => 'Найдите или выполните команду';

  @override
  String codeLabAppBarSearchTooltip(String shortcut) {
    return 'Найдите или выполните команду ($shortcut)';
  }

  @override
  String get codeLabPaletteTitle => 'Палитра команд';

  @override
  String get codeLabPaletteEmpty => 'Нет подходящих команд';

  @override
  String get codeLabPaletteAgentSection => 'От агента';

  @override
  String get codeLabPaneFiles => 'Файлы';

  @override
  String get codeLabPaneDiff => 'Различия';

  @override
  String get codeLabPaneTerminal => 'Терминал';

  @override
  String get codeLabPanePlan => 'План';

  @override
  String get codeLabPaneTimeline => 'Хронология';

  @override
  String get codeLabPaneAgents => 'Агенты';

  @override
  String get codeLabPaneUsage => 'Расход';

  @override
  String get codeLabPaneBranches => 'Ветки';

  @override
  String get codeLabPaneProtocol => 'Протокол';

  @override
  String get codeLabTerminalNoSession =>
      'Откройте сессию, чтобы пользоваться терминалом';

  @override
  String get codeLabTerminalNew => 'Новый терминал';

  @override
  String get codeLabAgentsTitle => 'Субагенты';

  @override
  String get codeLabAgentsSteps => 'Шаги';

  @override
  String get codeLabAgentsStateRunning => 'выполняется';

  @override
  String get codeLabAgentsStateWaiting => 'ждёт одобрения';

  @override
  String get codeLabAgentsStateDone => 'готово';

  @override
  String get codeLabAgentsStateFailed => 'сбой';

  @override
  String get codeLabAgentsStateCancelled => 'отменено';

  @override
  String codeLabAgentsCountRunning(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count выполняются',
      many: '$count выполняются',
      few: '$count выполняются',
      one: '$count выполняется',
    );
    return '$_temp0';
  }

  @override
  String codeLabAgentsCountWaiting(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count ждут одобрения',
      many: '$count ждут одобрения',
      few: '$count ждут одобрения',
      one: '$count ждёт одобрения',
    );
    return '$_temp0';
  }

  @override
  String codeLabAgentsCountDone(int count) {
    return '$count готово';
  }

  @override
  String codeLabAgentsCountFailed(int count) {
    return '$count со сбоем';
  }

  @override
  String codeLabAgentsCountCancelled(int count) {
    return '$count отменено';
  }

  @override
  String codeLabFileBinary(String sizeLabel) {
    return 'Двоичный файл ($sizeLabel)';
  }

  @override
  String codeLabFileTooLarge(String sizeLabel) {
    return 'Файл слишком велик для просмотра ($sizeLabel)';
  }

  @override
  String get codeLabFileSecretWarning => 'Этот файл может содержать секреты.';

  @override
  String get codeLabFileOutsideLink => 'за пределами проекта, не открыт';

  @override
  String get codeLabUsageLoading => 'Загрузка истории расхода';

  @override
  String get codeLabUsageRebuild => 'Пересобрать из журнала';

  @override
  String get codeLabUsageExportCsv => 'Экспорт в CSV';

  @override
  String get codeLabUsagePerTurn => 'По ходам';

  @override
  String get codeLabUsagePerModel => 'По моделям';

  @override
  String get codeLabUsageColumnInput => 'Ввод';

  @override
  String get codeLabUsageColumnOutput => 'Вывод';

  @override
  String get codeLabUsageColumnCost => 'Стоимость';

  @override
  String get codeLabUsageRunning => 'выполняется';

  @override
  String get codeLabLayoutAppBar => 'Верхняя панель';

  @override
  String get codeLabLayoutSessionsSidebar => 'Боковая панель сессий';

  @override
  String get codeLabLayoutSessionPane => 'Панель сессии';

  @override
  String get codeLabLayoutToolDock => 'Док инструментов';

  @override
  String get codeLabSettingsTitle => 'Настройки';

  @override
  String get codeLabSettingsFind => 'Найти настройку';

  @override
  String codeLabSettingsNoMatch(String query) {
    return 'Нет настроек по запросу «$query»';
  }

  @override
  String get codeLabStatusTableActions => 'Действия';

  @override
  String get codeLabMarkdownSelectAll => 'Выделить всё';

  @override
  String get codeLabMarkdownNestingTooDeep =>
      'Показано простым текстом: слишком глубокая вложенность.';

  @override
  String get codeLabMarkdownTaskDone => 'Задача выполнена';

  @override
  String get codeLabMarkdownTaskOpen => 'Задача не выполнена';

  @override
  String get codeLabMarkdownImage => 'Изображение';

  @override
  String get codeLabMarkdownShowImage => 'Показать изображение';

  @override
  String codeLabShortcutAlternatives(String first, String second) {
    return '$first или $second';
  }

  @override
  String codeLabSetupStepPosition(int index, int total) {
    return 'Шаг $index из $total';
  }

  @override
  String get codeLabProtocolViewFrames => 'Кадры';

  @override
  String get codeLabProtocolViewLog => 'Журнал';

  @override
  String get codeLabProtocolSelectFrame =>
      'Выберите кадр, чтобы увидеть подробности.';

  @override
  String get codeLabProtocolSelectRecord =>
      'Выберите запись, чтобы увидеть её поля.';

  @override
  String get codeLabProtocolMasked => '••••••• (замаскировано)';

  @override
  String get codeLabDockMoreActions => 'Ещё действия';
}
