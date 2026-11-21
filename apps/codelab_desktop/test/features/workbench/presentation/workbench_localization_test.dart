// Красные тесты задачи 3.3 change `add-desktop-localization`: рабочее место на
// русском с первого кадра (spec app-settings «Локализация интерфейса app»,
// сценарии «Заметка исхода хода на русском», «Ответ агента не переводится»,
// «Поиск команды хоста по английской подписи на русском», «Команда агента в
// палитре не переводится»; design.md D4, D5, D6, D7).
//
// Приложение собрано целиком с языком `ru` в шве `CodeLabTestBinding(locale:)`;
// тексты кита уже переведены итерацией 2, поэтому проверки сосредоточены на
// том, что подставляет app: подписи мапперов, стартовые экраны, `Retry`,
// баннеры и диалоги рабочего места. Строки кита (`Настроить подключение`,
// `Открыть папку…`, `Настройки`) входят как защита от регрессии и зелёные уже
// сейчас; красные — строки app, которые 3.4 переведёт.
//
// Русские строки — по глоссарию `docs/architecture/l10n-glossary.md`; строки
// вне глоссария перечислены в отчёте задачи 3.3 для вычитки. Строки с
// пометкой `security` (подтверждение корня диска) вычитывает пользователь
// (задача 3.5).

import 'package:codelab_acp_protocol/codelab_acp_protocol.dart';
import 'package:codelab_acp_testing/codelab_acp_testing.dart';
import 'package:codelab_ui/codelab_ui.dart';
import 'package:fluent_ui/fluent_ui.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../../support/live_scene.dart';
import '../../../support/start_agent.dart';
import '../application/shell_cubit_characterization/harness.dart'
    show ThrowingStartTransport;

const _ru = Locale('ru');

const _withListAndLoad = AgentCapabilities(
  loadSession: true,
  sessionCapabilities: SessionCapabilities(list: SessionListCapabilities()),
);

Finder _inKey(String key, Finder matching) =>
    find.descendant(of: find.byKey(ValueKey(key)), matching: matching);

void main() {
  group('стартовые экраны и сайдбар', () {
    testWidgets('без проекта: приглашение, группа без проекта, «Открыть '
        'папку…»', (tester) async {
      final scene = await LiveScene.open(
        tester,
        locale: _ru,
        project: null,
        connect: false,
      );

      // Экран кадра 11a (change `add-empty-project-screen`): заголовок,
      // кнопка и зона перетаскивания на русском.
      expect(find.text('Откройте проект'), findsOneWidget);
      expect(
        _inKey('start-open-project', find.text('Открыть папку…')),
        findsOneWidget,
      );
      expect(
        find.text('Перетащите папку сюда, чтобы открыть её'),
        findsOneWidget,
      );
      // Пустой сайдбар: подпись каталога кита вместо группы без проекта.
      expect(find.text('Недавних проектов пока нет.'), findsOneWidget);
      // Шапка сессии: подпись текущей сессии строит `SessionsCubit`.
      expect(find.text('Нет активной сессии'), findsOneWidget);
      // Кит (итерация 2): «Settings» сайдбара.
      expect(find.text('Настройки'), findsWidgets);

      await scene.close();
    });

    testWidgets('с проектом: приглашение называет папку, кнопка «Новая '
        'сессия»', (tester) async {
      final scene = await LiveScene.open(
        tester,
        locale: _ru,
        project: '/work/app',
        connect: false,
      );

      expect(find.text('Начните новую сессию в app.'), findsOneWidget);
      expect(
        _inKey('start-new-session', find.text('Новая сессия')),
        findsOneWidget,
      );

      await scene.close();
    });

    testWidgets('сессия без сообщений: подсказка ленты, подпись сессии, '
        'строка статуса без usage', (tester) async {
      final scene = await LiveScene.open(tester, locale: _ru);
      await scene.newSession('s1');

      expect(find.text('Отправьте сообщение, чтобы начать.'), findsOneWidget);
      // Название по умолчанию в сайдбаре; подпись `updatedLabel` кит не
      // рисует, поэтому она проверяется по данным строки.
      expect(find.text('Новая сессия'), findsWidgets);
      expect(
        scene.cubit.state.sessions.map((s) => s.updatedLabel),
        contains('Активна'),
      );
      final status = scene.textOf(find.byType(CodeLabSessionStatusBar));
      expect(status, contains('расход: —'));
      // Кит: подсказка композера.
      expect(
        tester
            .widgetList<TextBox>(find.byType(TextBox))
            .map((box) => box.placeholder),
        contains('Сообщение агенту'),
      );

      await scene.close();
    });

    testWidgets('сессия из session/list: «Сессия <id>» и «Не загружена»', (
      tester,
    ) async {
      final scene = await LiveScene.open(
        tester,
        locale: _ru,
        capabilities: _withListAndLoad,
        listed: const {'s-old': '/work/app'},
      );

      // Заголовок — `title` агента (здесь равен id), подпись времени без
      // даты: агент её не прислал. Статус — слово кита.
      expect(find.text('Не загружена'), findsOneWidget);

      await scene.close();
    });
  });

  group('соединение', () {
    testWidgets('экран сбоя запуска: «Повторить» и «Настроить подключение»', (
      tester,
    ) async {
      final scene = await LiveScene.open(
        tester,
        locale: _ru,
        stdioTransportFactory: (_) =>
            ThrowingStartTransport(StateError('agent exited')),
        connect: false,
      );
      await tester.runAsync(() => scene.cubit.startWith());
      await scene.flush();

      expect(
        scene.cubit.state.connectionStatus,
        CodeLabConnectionStatus.failed,
      );
      // Подпись кнопки экрана передаёт app (`reconnectLabel`).
      expect(
        _inKeyType(CodeLabConnectionScreen, find.text('Повторить')),
        findsOneWidget,
      );
      // Кит: кнопка экрана подключения.
      expect(find.text('Настроить подключение'), findsWidgets);

      await scene.close();
    });

    testWidgets('баннер потери соединения над лентой: «Повторить», заметка '
        'сбоя на русском', (tester) async {
      final scene = await LiveScene.open(tester, locale: _ru);
      await scene.newSession('s1');
      final turn = await scene.prompt('hello agent');
      scene.agent.fail(
        const AcpTransportException(
          code: AcpTransportErrorCode.closed,
          message: 'Stdio ACP agent exited unexpectedly with code -9.',
        ),
      );
      await tester.runAsync(() => Future<void>.delayed(Duration.zero));
      await scene.flush();

      expect(scene.cubit.state.connectionStatus, CodeLabConnectionStatus.lost);
      // Кит: текст баннера.
      // Тот же текст теперь и у заголовка заметки сбоя в ленте (решение
      // пользователя 2026-11-19), поэтому в баннере — по ключевому типу.
      expect(
        _inKeyType(
          CodeLabConnectionBanner,
          find.text('Подключение к агенту потеряно'),
        ),
        findsOneWidget,
      );
      expect(
        _inKeyType(CodeLabConnectionBanner, find.text('Повторить')),
        findsOneWidget,
      );
      final transcript = scene.textOf(find.byType(CodeLabTranscriptPanel));
      expect(transcript, contains('Подключение к агенту потеряно'));
      // Текст ошибки ядра уходит в раскрытие и остаётся английским (D7).
      expect(turn.method, sessionPromptMethod);

      await scene.close();
    });
  });

  group('лента', () {
    testWidgets('заметка max_tokens и ответ агента', (tester) async {
      final scene = await LiveScene.open(tester, locale: _ru);
      await scene.newSession('s1');
      final turn = await scene.prompt('explain the repo');
      await scene.agentText('s1', 'Done. 3 files changed.');
      await scene.endTurn(turn, stopReason: 'max_tokens');

      final transcript = scene.textOf(find.byType(CodeLabTranscriptPanel));
      expect(
        transcript,
        contains('Модель достигла лимита токенов, поэтому ход завершён.'),
      );
      // Ответ агента не переводится.
      expect(transcript, contains('Done. 3 files changed.'));
      expect(transcript, isNot(contains('The model reached its token limit')));

      await scene.close();
    });

    testWidgets('сбой хода: заголовок на русском, «Повторить» у заметки', (
      tester,
    ) async {
      final scene = await LiveScene.open(tester, locale: _ru);
      await scene.newSession('s1');
      final turn = await scene.prompt('hello');
      await scene.failTurn(turn);

      final transcript = scene.textOf(find.byType(CodeLabTranscriptPanel));
      expect(transcript, contains('Агенту не удалось завершить ход'));
      // Сообщение агента — как есть.
      expect(transcript, contains('Internal error'));
      expect(
        _inKeyType(CodeLabTranscriptPanel, find.text('Повторить')),
        findsOneWidget,
      );

      await scene.close();
    });

    testWidgets('идущий вызов: метка по виду на русском, заголовок агента '
        'как есть', (tester) async {
      final scene = await LiveScene.open(tester, locale: _ru);
      await scene.newSession('s1');
      await scene.prompt('run it');
      await scene.toolCall('s1', toolCallId: 'c1', title: 'Run echo hi');

      final transcript = scene.textOf(find.byType(CodeLabTranscriptPanel));
      // Кит: тег статуса; app: метка вида `execute`.
      expect(transcript, contains('Выполняется'));
      expect(transcript, contains('Запуск'));
      expect(transcript, isNot(contains('Run echo hi')));

      await scene.close();
    });

    testWidgets('вызов вида other показывает заголовок агента', (tester) async {
      final scene = await LiveScene.open(tester, locale: _ru);
      await scene.newSession('s1');
      await scene.prompt('do it');
      await scene.toolCall(
        's1',
        toolCallId: 'c1',
        title: 'Fetch my coffee',
        kind: 'other',
      );

      final transcript = scene.textOf(find.byType(CodeLabTranscriptPanel));
      expect(transcript, contains('Fetch my coffee'));

      await scene.close();
    });
  });

  group('палитра', () {
    testWidgets('пункты хоста и описания на русском, команда агента без '
        'перевода', (tester) async {
      final scene = await LiveScene.open(tester, locale: _ru);
      await scene.newSession('s1');
      await scene.update('s1', {
        'sessionUpdate': 'available_commands_update',
        'availableCommands': [
          {'name': 'review', 'description': 'Review the plan'},
        ],
      });

      scene.cubit.openCommandPalette();
      await scene.flush();
      final palette = scene.textOf(find.byType(CodeLabCommandPaletteSurface));

      for (final text in const [
        'Новая сессия',
        'Начать новую ACP-сессию.',
        'Журналы',
        'Открыть журналы протокола и диагностики.',
        // Профиль сцены — локальный stdio: пункт `reconnect` называется
        // «Restart agent» (Q24, D22), как на `en`.
        'Перезапустить агента',
        'Перезапустить агента выбранным профилем и перезагрузить открытые '
            'сессии.',
      ]) {
        expect(palette, contains(text));
      }
      // Команда агента в конце списка выходит за видимую часть палитры; по
      // запросу она видна: имя и описание агента без перевода.
      await tester.enterText(
        find.byKey(CodeLabCommandPaletteSurface.queryFieldKey),
        'review',
      );
      await tester.pump();
      expect(
        scene.textOf(find.byType(CodeLabCommandPaletteSurface)),
        contains('Review the plan'),
      );

      await scene.close();
    });

    testWidgets('пункты Files, Agents, Usage переведены вместе с описаниями', (
      tester,
    ) async {
      final scene = await LiveScene.open(
        tester,
        locale: _ru,
        capabilities: const AgentCapabilities(
          meta: {
            'codelab': {
              'usage': {'version': 1},
            },
          },
        ),
      );
      await scene.newSession('s1');

      final actions = scene.cubit.state.paletteActions;
      final usage = actions.firstWhere((action) => action.id == 'usage-pane');
      expect(usage.label, 'Расход');
      expect(usage.description, 'Перейти к панели расхода.');
      expect(usage.slashCommand, '/usage-pane');

      await scene.close();
    });

    testWidgets('поиск по английской подписи на русском находит /new', (
      tester,
    ) async {
      final scene = await LiveScene.open(tester, locale: _ru);
      await scene.newSession('s1');
      scene.cubit.openCommandPalette();
      await scene.flush();

      await tester.enterText(
        find.byKey(CodeLabCommandPaletteSurface.queryFieldKey),
        'session',
      );
      await tester.pump();
      final palette = scene.textOf(find.byType(CodeLabCommandPaletteSurface));

      expect(palette, contains('Новая сессия'));
      expect(palette, isNot(contains('Журналы')));

      await scene.close();
    });

    testWidgets('поиск по переведённой подписи находит /new', (tester) async {
      final scene = await LiveScene.open(tester, locale: _ru);
      await scene.newSession('s1');
      scene.cubit.openCommandPalette();
      await scene.flush();

      await tester.enterText(
        find.byKey(CodeLabCommandPaletteSurface.queryFieldKey),
        'Новая сес',
      );
      await tester.pump();

      expect(
        scene.textOf(find.byType(CodeLabCommandPaletteSurface)),
        contains('Начать новую ACP-сессию.'),
      );

      await scene.close();
    });

    testWidgets('inline `/logs` из композера: «Журналы» первой, имя '
        'не переведено', (tester) async {
      final scene = await LiveScene.open(tester, locale: _ru);
      await scene.newSession('s1');

      final found = scene.cubit.state.searchPalette('/logs');

      expect(found.first.id, 'logs');
      expect(found.first.label, 'Журналы');
      expect(found.first.slashCommand, '/logs');

      await scene.close();
    });

    testWidgets('команда агента `review` по `review the` — с описанием '
        'агента', (tester) async {
      final scene = await LiveScene.open(tester, locale: _ru);
      await scene.newSession('s1');
      await scene.update('s1', {
        'sessionUpdate': 'available_commands_update',
        'availableCommands': [
          {'name': 'review', 'description': 'Review the plan'},
        ],
      });
      scene.cubit.openCommandPalette();
      await scene.flush();

      await tester.enterText(
        find.byKey(CodeLabCommandPaletteSurface.queryFieldKey),
        'review the',
      );
      await tester.pump();
      final palette = scene.textOf(find.byType(CodeLabCommandPaletteSurface));

      expect(palette, contains('Review the plan'));
      expect(palette, isNot(contains('Новая сессия')));

      await scene.close();
    });
  });

  group('панель Protocol: диагностика не переводится (D7)', () {
    testWidgets('заголовки «Журнал отладки» и «Инспектор» переведены, '
        'содержимое Inspector как есть', (tester) async {
      final scene = await LiveScene.open(tester, locale: _ru, connect: false);
      scene.cubit.openPane(ToolPane.protocol);
      await scene.flush();

      final pane = scene.textOf(
        find.byKey(CodeLabToolDock.paneKey(ToolPane.protocol)),
      );
      // Заголовки вкладок — по глоссарию (Q3 (а)).
      expect(pane, contains('Журнал отладки'));
      expect(pane, contains('Инспектор'));
      // Содержимое строит ядро клиента и журнал: оно совпадает с тем, что
      // пользователь пришлёт в отчёте об ошибке.
      expect(pane, contains('Protocol log'));
      expect(pane, contains('Start a session to inspect ACP activity.'));

      await scene.close();
    });
  });

  group('подтверждение корня диска (security)', () {
    testWidgets('диалог на русском; кнопки «Открыть» и «Отмена»', (
      tester,
    ) async {
      final scene = await LiveScene.open(
        tester,
        locale: _ru,
        capabilities: _withListAndLoad,
        listed: const {'s-root': '/'},
      );

      scene.cubit.selectSession('s-root');
      await scene.flush();

      final dialog = find.byKey(const ValueKey('root-session-dialog'));
      expect(dialog, findsOneWidget);
      // Заголовок и текст сохраняют силу предупреждения: «весь диск»,
      // «всё равно» (D14); путь — плейсхолдер.
      expect(find.text('Открыть сессию в корне диска?'), findsOneWidget);
      expect(
        find.text(
          'Эта сессия работает в корне диска (/). Агент получит доступ ко '
          'всему диску. Всё равно открыть?',
        ),
        findsOneWidget,
      );
      expect(_inKey('root-session-open', find.text('Открыть')), findsOneWidget);
      expect(
        _inKey('root-session-cancel', find.text('Отмена')),
        findsOneWidget,
      );

      await scene.close();
    });
  });
}

/// Совпадение [matching] внутри виджета типа [type].
Finder _inKeyType(Type type, Finder matching) =>
    find.descendant(of: find.byType(type), matching: matching);
