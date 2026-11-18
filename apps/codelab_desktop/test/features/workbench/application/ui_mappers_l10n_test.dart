// Красные тесты задачи 3.3 change `add-desktop-localization` (мапперы
// рабочего места на `ru` и `en`; design.md D4, D5, D6; spec app-settings
// «Локализация интерфейса app», сценарии «Заметка исхода хода на русском»,
// «Ответ агента не переводится», «Поиск команды хоста по английской подписи
// на русском», «Поиск команды хоста по переведённой подписи», «Поиск по имени
// команды при любом языке», «Команда агента в палитре не переводится»).
//
// Почему мапперы, а не экран: `ui_mappers.dart` строит модели кита с готовым
// текстом (D5, таблица «Производный текст в состоянии»), поэтому язык — явный
// вход мапперов: `AppLocalizations` параметром `l10n`. Заметки строятся по
// типизированной причине `NoticeReason` (D6), а не по английскому
// `NoticeItem.text`: в тестах `text` намеренно остаётся английским, и `ru`
// получается только из `reason`.
//
// Русские строки взяты из глоссария `docs/architecture/l10n-glossary.md`; для
// строк вне глоссария у теста помечено «вне глоссария» — их вычитывает
// пользователь вместе с итерацией, а ARB 3.4 повторяет эти строки слово в
// слово.
//
// Заглушки задачи 3.3: параметр `l10n` у мапперов принят и не используется,
// поэтому `ru`-проверки красные на `expect`, а проверки `en` и «без
// изменений» зелёные как защита от регрессии.

import 'package:codelab_acp_protocol/codelab_acp_protocol.dart';
import 'package:codelab_client_acp/codelab_client_acp.dart';
import 'package:codelab_client_core/codelab_client_core.dart';
import 'package:codelab_desktop/features/workbench/application/ui_mappers.dart';
import 'package:codelab_desktop/l10n/app_localizations.dart';
import 'package:codelab_desktop/l10n/app_localizations_en.dart';
import 'package:codelab_desktop/l10n/app_localizations_ru.dart';
import 'package:codelab_ui/codelab_ui.dart';
import 'package:flutter/widgets.dart' show VoidCallback;
import 'package:flutter_test/flutter_test.dart';

final _ru = AppLocalizationsRu();
final _en = AppLocalizationsEn();

List<CodeLabTranscriptRow> _rows(
  List<TranscriptItem> items, {
  required AppLocalizations l10n,
  VoidCallback? onRetry,
}) => transcriptRowsOf(
  items,
  cwd: '/work',
  approvalsEnabled: true,
  onApprovalSelected: (_, _) {},
  onRetry: onRetry,
  l10n: l10n,
);

CodeLabNoticeRow _notice(TranscriptItem item, AppLocalizations l10n) =>
    _rows([item], l10n: l10n).single as CodeLabNoticeRow;

TranscriptItem _stopped(
  String text,
  StopReason stopReason, {
  String? budgetLimit,
}) => TranscriptItem.notice(
  id: 't1/stopped',
  kind: NoticeKind.turnStopped,
  text: text,
  reason: TurnStoppedReason(stopReason, budgetLimit: budgetLimit),
);

CodeLabToolCallRow _tool(ToolKind kind, String title, AppLocalizations l10n) {
  final rows = _rows([
    TranscriptItem.toolCall(
      id: 't1/tool-call-1',
      toolCallId: const ToolCallId('call-1'),
      title: title,
      details: ToolCallView(
        kind: kind,
        status: ToolCallStatusView.running,
        paths: const ['/work/lib/a.dart'],
      ),
    ),
  ], l10n: l10n);
  return rows.single as CodeLabToolCallRow;
}

void main() {
  group('заметка исхода хода по NoticeReason', () {
    test('max_tokens на ru — перевод по причине, на en — прежний текст', () {
      const english = 'The model reached its token limit, so the turn ended.';
      final item = _stopped(english, StopReason.maxTokens);

      expect(
        _notice(item, _ru).body,
        'Модель достигла лимита токенов, поэтому ход завершён.',
      );
      expect(_notice(item, _en).body, english);
    });

    test('refusal на ru', () {
      final item = _stopped(
        'The agent refused to continue.',
        StopReason.refusal,
      );

      expect(_notice(item, _ru).body, 'Агент отказался продолжать.');
    });

    test('max_turn_requests с известным лимитом называет лимит как есть', () {
      final item = _stopped(
        'The turn stopped: budget exceeded: tokens.',
        StopReason.maxTurnRequests,
        budgetLimit: 'tokens',
      );

      // Имя лимита — значение провода (D7), оно подставляется плейсхолдером.
      expect(
        _notice(item, _ru).body,
        'Ход остановлен: превышен бюджет: tokens.',
      );
    });

    test('max_turn_requests без известного лимита — общий текст', () {
      final item = _stopped(
        'The turn reached the limit of model requests.',
        StopReason.maxTurnRequests,
      );

      expect(_notice(item, _ru).body, 'Ход достиг лимита запросов к модели.');
    });

    test('emptyTurn со stopReason и без него', () {
      final known = TranscriptItem.notice(
        id: 't1/completed',
        kind: NoticeKind.emptyTurn,
        text: 'Completed with stopReason cancelled.',
        reason: const EmptyTurnReason(StopReason.cancelled),
      );
      final unknown = TranscriptItem.notice(
        id: 't1/completed',
        kind: NoticeKind.emptyTurn,
        text: 'Completed with stopReason unknown.',
        reason: const EmptyTurnReason(null),
      );

      // stopReason — значение провода, не переводится (D7); вне глоссария.
      expect(_notice(known, _ru).body, 'Завершено с stopReason cancelled.');
      expect(_notice(unknown, _ru).body, 'Завершено, stopReason неизвестен.');
      expect(_notice(known, _en).body, 'Completed with stopReason cancelled.');
    });
  });

  group('заметки связи сессии с агентом', () {
    CodeLabNoticeRow detached(
      SessionRestoreReason reason,
      AppLocalizations l,
    ) => _notice(
      TranscriptItem.notice(
        id: 's1/detached',
        kind: NoticeKind.detached,
        text: 'The agent cannot restore sessions after reconnecting.',
        reason: reason,
      ),
      l,
    );

    CodeLabNoticeRow reconnected(
      SessionRestoreReason reason,
      AppLocalizations l,
    ) => _notice(
      TranscriptItem.notice(
        id: 's1/reconnected',
        kind: NoticeKind.reconnected,
        text: 'The agent cannot restore sessions; a new session was started.',
        reason: reason,
      ),
      l,
    );

    const cannot = SessionRestoreReason(SessionRestoreCause.agentCannotRestore);
    const failed = SessionRestoreReason(
      SessionRestoreCause.restoreFailed,
      sessionId: SessionId('s-42'),
    );

    test('detached: заголовок по глоссарию, тело по причине', () {
      final row = detached(cannot, _ru);

      expect(row.severity, CodeLabNoticeSeverity.warning);
      // «Detached» → «Отсоединена» (глоссарий); заголовок заметки — вне
      // глоссария.
      expect(row.title, 'Сессия отсоединена');
      expect(
        row.body,
        'Агент не восстанавливает сессии после переподключения.',
      );
      expect(
        detached(failed, _ru).body,
        'Не удалось восстановить сессию s-42 после переподключения.',
      );
    });

    test('reconnected: тело по причине, id сессии — плейсхолдер', () {
      expect(
        reconnected(cannot, _ru).body,
        'Агент не восстанавливает сессии; начата новая сессия.',
      );
      expect(
        reconnected(failed, _ru).body,
        'Не удалось восстановить сессию s-42; начата новая сессия.',
      );
    });

    test('на en заголовок и тело прежние', () {
      expect(detached(cannot, _en).title, 'Session detached');
      expect(
        detached(cannot, _en).body,
        'The agent cannot restore sessions after reconnecting.',
      );
    });
  });

  group('заметка сбоя хода', () {
    CodeLabNoticeRow error(PromptFailure failure, AppLocalizations l10n) =>
        _rows(
              [
                TranscriptItem.notice(
                  id: 't1/error',
                  kind: NoticeKind.error,
                  text: 'Failed to send prompt: 503 Service Unavailable',
                  failure: failure,
                ),
              ],
              l10n: l10n,
              onRetry: () {},
            ).single
            as CodeLabNoticeRow;

    test('заголовок по классу сбоя на ru, сообщение агента как есть', () {
      final row = error(
        const PromptFailure.agent(
          errorClass: 'server',
          message: '503 Service Unavailable',
        ),
        _ru,
      );

      expect(row.title, 'Провайдер модели недоступен');
      expect(row.body, '503 Service Unavailable');
      // Текст ядра уходит в раскрытие без перевода: диагностика (D7).
      expect(row.details, 'Failed to send prompt: 503 Service Unavailable');
      expect(row.action?.label, 'Повторить');
    });

    test('failureTitleOf: все классы сбоя на ru', () {
      String title(PromptFailure? failure) =>
          failureTitleOf(failure, l10n: _ru);

      // Все пять строк — вне глоссария.
      expect(
        title(const PromptFailure.agent(errorClass: 'auth', message: 'm')),
        'Агенту не удалось войти у провайдера модели',
      );
      expect(
        title(const PromptFailure.agent(errorClass: 'timeout', message: 'm')),
        'Провайдер модели недоступен',
      );
      expect(
        title(
          const PromptFailure.agent(errorClass: 'rateLimited', message: 'm'),
        ),
        'Достигнут лимит запросов провайдера модели',
      );
      expect(
        title(const PromptFailure.agent(errorClass: 'overflow', message: 'm')),
        'Диалог слишком длинный для модели',
      );
      expect(
        title(const PromptFailure.connectionLost()),
        'Связь с агентом потеряна',
      );
      expect(title(null), 'Агенту не удалось завершить ход');
    });

    test('потеря соединения: тело-подсказка на ru', () {
      final row = error(const PromptFailure.connectionLost(), _ru);

      expect(row.body, 'Повторите, чтобы продолжить работу с агентом.');
    });

    test('failureTitleOf на en прежний', () {
      expect(
        failureTitleOf(const PromptFailure.connectionLost(), l10n: _en),
        'The connection to the agent was lost',
      );
    });
  });

  group('метка вызова по ToolKind', () {
    test('виды ToolKind на ru; деталь без изменений', () {
      // Метки видов — вне глоссария (в `en` их выдаёт ядро клиента).
      const expected = {
        ToolKind.read: 'Чтение',
        ToolKind.edit: 'Правка',
        ToolKind.delete: 'Удаление',
        ToolKind.move: 'Перемещение',
        ToolKind.search: 'Поиск',
        ToolKind.execute: 'Запуск',
        ToolKind.fetch: 'Загрузка',
        ToolKind.think: 'Обдумывание',
        ToolKind.switchMode: 'Режим',
      };
      for (final entry in expected.entries) {
        final row = _tool(entry.key, 'whatever the agent wrote', _ru);
        expect(row.label, entry.value, reason: '${entry.key}');
      }
      expect(
        _tool(ToolKind.read, 'x', _ru).detail,
        _tool(ToolKind.read, 'x', _en).detail,
      );
    });

    test('на en метки прежние', () {
      expect(_tool(ToolKind.read, 'x', _en).label, 'Read');
      expect(_tool(ToolKind.execute, 'x', _en).label, 'Run');
    });

    test('other показывает заголовок агента, а не перевод', () {
      expect(
        _tool(ToolKind.other, 'Fetch my coffee', _ru).label,
        'Fetch my coffee',
      );
    });

    test('вызов субагента остаётся строкой агента и ядра', () {
      final rows = _rows([
        TranscriptItem.toolCall(
          id: 't1/tool-call-1',
          toolCallId: const ToolCallId('call-1'),
          title: 'agent',
          details: const ToolCallView(
            kind: ToolKind.think,
            status: ToolCallStatusView.running,
            rawInput: {
              'type': 'explore',
              'description': 'Find auth code',
              'task': 'Where is the session restored?',
            },
            subagentCall: SubagentCallView(id: 'sub_a1', type: 'explore'),
          ),
        ),
      ], l10n: _ru);

      expect(
        (rows.single as CodeLabToolCallRow).label,
        'Subagent explore: Find auth code',
      );
    });
  });

  test('ответ агента, запрос пользователя и мысли не меняются на ru', () {
    final rows = _rows(const [
      TranscriptItem.user(id: 't1/user', text: 'run the tests'),
      TranscriptItem.thought(id: 't1/thought', text: 'Thinking about it.'),
      TranscriptItem.agentText(id: 't1/agent', text: 'Done. 3 files changed.'),
    ], l10n: _ru);

    expect(
      rows.map(
        (row) => switch (row) {
          CodeLabUserRow(:final text) ||
          CodeLabThoughtRow(:final text) ||
          CodeLabAgentTextRow(:final text) => text,
          _ => '',
        },
      ),
      ['run the tests', 'Thinking about it.', 'Done. 3 files changed.'],
    );
  });

  group('сайдбар и статусная строка', () {
    test('сессия без заголовка и подпись «Active» на ru', () {
      final item = sessionListItemOf(
        const AcpSession(id: SessionId('s1'), cwd: '/work'),
        l10n: _ru,
      );

      // «New session» — глоссарий; «Active» → «Активна» — вне глоссария.
      expect(item.title, 'Новая сессия');
      expect(item.updatedLabel, 'Активна');
    });

    test('заголовок от агента и первый промпт не переводятся', () {
      final titled = sessionListItemOf(
        const AcpSession(id: SessionId('s1'), cwd: '/work', title: 'Fix tests'),
        l10n: _ru,
      );

      expect(titled.title, 'Fix tests');
    });

    test('сессия из session/list: название по умолчанию и подпись времени', () {
      final item = sessionListItemOfSummary(
        SessionSummaryView(
          id: const SessionId('s-7'),
          cwd: '/work',
          status: SessionStatusView.idle,
          updatedAt: DateTime(2026, 11, 18, 9, 5),
        ),
        l10n: _ru,
      );

      // «Session {id}» → «Сессия {id}», «Updated» → «Обновлено» — вне
      // глоссария; формат даты общий для языков (D8).
      expect(item.title, 'Сессия s-7');
      expect(item.updatedLabel, 'Обновлено 2026-11-18 09:05');
    });

    test('группа без проекта на ru', () {
      final groups = sidebarProjectsOf(
        selectedProjectPath: null,
        sessions: const [],
        recentProjects: const [],
        l10n: _ru,
      );

      // Вне глоссария.
      expect(groups.single.name, 'Нет проекта');
    });

    test('строка статуса без usage на ru: подпись и подсказка', () {
      final data = sessionStatusDataOf(
        const SessionView(revision: 1, status: SessionStatusView.idle),
        l10n: _ru,
      );

      // «usage» → «Расход» (глоссарий); обе строки — вне глоссария.
      expect(data.usage?.label, 'расход: —');
      expect(data.usage?.tooltip, 'агент не сообщает расход');
    });
  });

  group('каталог палитры на ru и en', () {
    const agentReview = AgentCommandView(
      name: 'review',
      description: 'Review the plan',
    );

    HostCommand host(CommandCatalog catalog, String id) => catalog.commands
        .whereType<HostCatalogCommand>()
        .map((command) => command.command)
        .firstWhere((command) => command.id == id);

    test('ru: перевод в label и description, английское — в searchAliases', () {
      final catalog = paletteCatalogOf(const [], l10n: _ru);
      final created = host(catalog, 'new');

      expect(created.name, 'new');
      expect(created.label, 'Новая сессия');
      // Вне глоссария: описания команд хоста.
      expect(created.description, 'Начать новую ACP-сессию.');
      expect(created.searchAliases, [
        'New session',
        'Start a fresh ACP session.',
      ]);
      expect(host(catalog, 'logs').label, 'Журналы');
      expect(host(catalog, 'reconnect').label, 'Переподключиться');
    });

    test('en: прежние подпись и описание, searchAliases пуст', () {
      final catalog = paletteCatalogOf(const [], l10n: _en);

      for (final command in catalog.commands.whereType<HostCatalogCommand>()) {
        expect(command.command.searchAliases, isEmpty);
      }
      expect(host(catalog, 'new').label, 'New session');
      expect(host(catalog, 'new').description, 'Start a fresh ACP session.');
    });

    test('необязательные пункты Files, Agents, Usage переведены на ru', () {
      final catalog = paletteCatalogOf(
        const [],
        filesAvailable: true,
        agentsAvailable: true,
        usageAvailable: true,
        l10n: _ru,
      );

      // «Files», «Agents», «Usage» — глоссарий; описания — вне глоссария.
      expect(host(catalog, 'files').label, 'Файлы');
      expect(
        host(catalog, 'files').description,
        'Перейти к панели файлов проекта.',
      );
      expect(host(catalog, 'files').searchAliases, [
        'Files',
        'Go to the project files panel.',
      ]);
      expect(host(catalog, 'agents').label, 'Агенты');
      expect(
        host(catalog, 'agents').description,
        'Перейти к панели субагентов.',
      );
      expect(host(catalog, 'usage-pane').label, 'Расход');
      expect(
        host(catalog, 'usage-pane').description,
        'Перейти к панели расхода.',
      );
      expect(host(catalog, 'usage-pane').name, 'usage-pane');
    });

    test('у команд агента на ru нет перевода и дополнительных строк', () {
      final catalog = paletteCatalogOf(const [agentReview], l10n: _ru);

      final agent = catalog.commands
          .whereType<AgentCatalogCommand>()
          .single
          .command;
      expect(agent, agentReview);
      expect(catalog.commands.whereType<AgentCatalogCommand>().length, 1);
    });

    test('строка палитры показывает перевод; значок и /команда те же', () {
      final catalog = paletteCatalogOf(const [], l10n: _ru);
      final actions = paletteActionsOf(catalog);

      final created = actions.firstWhere((action) => action.id == 'new');
      expect(created.label, 'Новая сессия');
      expect(created.description, 'Начать новую ACP-сессию.');
      expect(created.slashCommand, '/new');
      expect(
        actions.firstWhere((action) => action.id == 'logs').label,
        'Журналы',
      );
    });

    test('поиск `session` на ru находит /new по английской подписи', () {
      final catalog = paletteCatalogOf(const [], l10n: _ru);

      final found = searchPaletteActions(catalog, 'session');

      // Ни имя `new`, ни перевод не содержат `session`.
      expect(found.map((action) => action.id), ['new']);
      expect(found.single.label, 'Новая сессия');
    });

    test('поиск по части перевода подписи находит /new', () {
      final catalog = paletteCatalogOf(const [], l10n: _ru);

      expect(searchPaletteActions(catalog, 'Новая сес').map((a) => a.id), [
        'new',
      ]);
    });

    test('поиск по имени команды работает на любом языке', () {
      final catalog = paletteCatalogOf(const [], l10n: _ru);

      final found = searchPaletteActions(catalog, '/logs');

      expect(found.first.id, 'logs');
      expect(found.first.label, 'Журналы');
    });

    test('команда агента по `review the` — с описанием агента', () {
      final catalog = paletteCatalogOf(const [agentReview], l10n: _ru);

      final found = searchPaletteActions(catalog, 'review the');

      expect(found.map((action) => action.id), ['agent-review']);
      expect(found.single.description, 'Review the plan');
      expect(found.single.label, 'review');
    });

    test(
      'на en поиск совпадает с прежним каталогом без дополнительных строк',
      () {
        final previous = CommandCatalog(
          host: [
            for (final action in CodeLabCommandAction.defaults)
              HostCommand(
                id: action.id,
                name: action.slashCommand.substring(1),
                label: action.label,
                description: action.description,
                isAvailable: action.isAvailable,
              ),
          ],
          agent: const [agentReview],
        );
        final current = paletteCatalogOf(const [agentReview], l10n: _en);

        for (final query in ['', '/', 'new', 'session', 'plan', 're', '/re']) {
          expect(
            [for (final c in current.search(query)) c.name],
            [for (final c in previous.search(query)) c.name],
            reason: 'запрос «$query»',
          );
        }
      },
    );

    test('en → ru → en: строки не дублируются и не смешиваются', () {
      final first = paletteCatalogOf(const [], l10n: _en);
      final russian = paletteCatalogOf(const [], l10n: _ru);
      final second = paletteCatalogOf(const [], l10n: _en);

      // Русский каталог получает ровно две английские строки команды `new`,
      // а не накопленные с прошлого вызова.
      expect(host(russian, 'new').searchAliases, hasLength(2));
      expect(host(russian, 'new').label, 'Новая сессия');
      // Английский после русского — как до него.
      expect(host(second, 'new').label, 'New session');
      expect(host(second, 'new').searchAliases, isEmpty);
      expect(host(first, 'new'), host(second, 'new'));
      // Русские строки английский каталог не находит.
      expect(searchPaletteActions(second, 'сессия'), isEmpty);
      expect(searchPaletteActions(second, 'session').map((a) => a.id), ['new']);
    });
  });
}
