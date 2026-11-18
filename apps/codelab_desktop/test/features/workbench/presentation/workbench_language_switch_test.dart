// Красные тесты задачи 3.3 change `add-desktop-localization`: смена языка на
// живом рабочем месте (spec app-settings «Язык интерфейса app», сценарии
// «Живое рабочее место пересобирается», «Ввод пользователя сохраняется»,
// «Возврат к английскому»; design.md D5, D9, R1, R6).
//
// Сцена одна и та же: приложение на `en` с ответом агента, заметками хода
// (`turnStopped` и `error`), идущим вызовом, ожидающим одобрением и сессией
// прошлого запуска в сайдбаре; затем `AppLanguageCubit.select(ru)` — как
// выбор на странице «General», — и проверка двух вещей. Первая: ни одна
// строка каталога `en` не осталась на экране (`expectNoStaleLanguage`, от
// каталога app и от каталога кита). Вторая — явные русские строки, чтобы тест
// был красным, пока 3.4 не переведёт эти места, а не только тогда, когда
// помощник что-то находит. Ответ агента при этом не меняется.
//
// Ввод пользователя (текст композера, прокрутка ленты) смена языка не
// трогает, а агенту при смене ничего не уходит (R6).

import 'package:codelab_acp_protocol/codelab_acp_protocol.dart';
import 'package:codelab_acp_testing/codelab_acp_testing.dart';
import 'package:codelab_desktop/core/platform/app_language_preferences.dart';
import 'package:codelab_desktop/features/terminal/application/terminal_tabs_cubit.dart';
import 'package:codelab_desktop/l10n/app_localizations_en.dart';
import 'package:codelab_desktop/l10n/app_localizations_ru.dart';
import 'package:codelab_ui/codelab_ui.dart';
import 'package:fluent_ui/fluent_ui.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../../support/fake_project_files.dart';
import '../../../support/fake_user_shell_launcher.dart';
import '../../../support/l10n_mix.dart';
import '../../../support/live_scene.dart';

/// Снимок usage идущего хода с бюджетом: блок «Turn budget» панели Usage.
Map<String, Object?> _budgetSnapshot() => {
  'sessionId': 's1',
  'seq': 1,
  'trigger': 'step',
  'turnId': 'turn-3',
  'turn': {
    'steps': 3,
    'tokens': {'input': 100, 'output': 20, 'cacheRead': 0, 'cacheWrite': 0},
    'cost': '0.41',
  },
  'session': {
    'turns': 1,
    'steps': 3,
    'tokens': {'input': 100, 'output': 20, 'cacheRead': 0, 'cacheWrite': 0},
    'cost': '0.41',
  },
  'currency': 'USD',
  'budget': {
    'steps': {'used': 3, 'limit': 50},
    'tokens': {'used': 92000, 'limit': 200000},
    'cost': {'used': '0.41', 'limit': '0.5'},
    'duration': {'usedMs': 180000, 'limitMs': 600000},
  },
};

FakeProjectFiles _files() => FakeProjectFiles(
  listings: {
    '/work/app': {
      '': listingOf('', [fileEntry('README.md')]),
    },
  },
);

/// Сцена на `en`: данные есть на всех поверхностях рабочего места.
Future<LiveScene> _openLive(WidgetTester tester) async {
  final scene = await LiveScene.open(
    tester,
    capabilities: const AgentCapabilities(
      loadSession: true,
      sessionCapabilities: SessionCapabilities(list: SessionListCapabilities()),
      meta: {
        'codelab': {
          'usage': {'version': 1},
        },
      },
    ),
    listed: const {'s-old': '/work/app'},
    projectFiles: _files(),
    userShellLauncher: FakeUserShellLauncher(),
    // Широкое окно: в тестовом шрифте Ahem ряд кнопок одобрения на `ru`
    // не помещается в 696 px ленты при окне 1440 px (находка задачи 3.3).
    size: const Size(2000, 1000),
  );
  await scene.newSession('s1');

  // Ход 1: ответ агента и заметка `turnStopped` (max_tokens).
  final first = await scene.prompt('explain the repo');
  await scene.agentText('s1', 'Done. 3 files changed.');
  await scene.endTurn(first, stopReason: 'max_tokens');

  // Ход 2: сбой агента, заметка `error`.
  final second = await scene.prompt('summarize');
  await scene.failTurn(second);

  // Ход 3 остаётся идущим: вызов `running` и ожидающее одобрение.
  await scene.prompt('run the tests');
  await scene.toolCall('s1', toolCallId: 'c1', title: 'Run echo hi');
  await scene.requestPermission(id: 100, sessionId: 's1', toolCallId: 'c2');
  scene.agent.emitInbound(
    JsonRpcMessage.notification(
      method: '_codelab/session/usage',
      params: _budgetSnapshot(),
    ),
  );
  await scene.flush();
  return scene;
}

String _transcript(LiveScene scene) =>
    scene.textOf(find.byType(CodeLabTranscriptPanel));

void main() {
  final en = AppLocalizationsEn();
  final ru = AppLocalizationsRu();

  testWidgets('смена языка пересобирает ленту, заметки и сайдбар живого '
      'рабочего места', (tester) async {
    final scene = await _openLive(tester);
    expect(_transcript(scene), contains('The model reached its token limit'));
    expect(find.text('Not loaded'), findsOneWidget);

    await scene.selectLanguage(AppLanguagePreference.ru);

    final transcript = _transcript(scene);
    // Заметка `turnStopped` показана раньше и перерисована по NoticeReason.
    expect(
      transcript,
      contains('Модель достигла лимита токенов, поэтому ход завершён.'),
    );
    expect(transcript, isNot(contains('The model reached its token limit')));
    // Заметка сбоя и метка вызова; тег статуса вызова — слово кита.
    expect(transcript, contains('Агенту не удалось завершить ход'));
    expect(transcript, contains('Запуск'));
    expect(transcript, contains('Выполняется'));
    // Ответ агента и сообщение агента об ошибке не изменились.
    expect(transcript, contains('Done. 3 files changed.'));
    expect(transcript, contains('Internal error'));
    // Сайдбар: статусы сессий и подписи строк.
    expect(find.text('Не загружена'), findsOneWidget);
    expect(find.text('Ждёт одобрения'), findsWidgets);
    expect(find.text('Активна'), findsOneWidget);

    await expectNoStaleLanguage(tester, from: en, to: ru);
    await scene.close();
  });

  testWidgets('возврат к английскому: строки снова на en, ответ агента '
      'тот же', (tester) async {
    final scene = await _openLive(tester);
    await scene.selectLanguage(AppLanguagePreference.ru);
    // Без этого шага проверка возврата прошла бы и при непереведённом ru.
    expect(
      _transcript(scene),
      contains('Модель достигла лимита токенов, поэтому ход завершён.'),
    );
    await scene.selectLanguage(AppLanguagePreference.en);

    final transcript = _transcript(scene);
    expect(transcript, contains('The model reached its token limit'));
    expect(transcript, contains('The agent could not complete the turn'));
    expect(transcript, contains('Done. 3 files changed.'));
    expect(transcript, isNot(contains('Модель достигла')));
    expect(find.text('Not loaded'), findsOneWidget);

    await expectNoStaleLanguage(tester, from: ru, to: en);
    await scene.close();
  });

  testWidgets('ввод сохраняется: текст композера, прокрутка ленты, фокус; '
      'агенту ничего не отправлено', (tester) async {
    final scene = await _openLive(tester);
    // Длинный ответ, чтобы ленту было куда прокручивать.
    await scene.agentText(
      's1',
      List.generate(80, (i) => 'line $i of the long answer').join('\n\n'),
    );
    final composer = find
        .descendant(
          of: find.byType(CodeLabPromptComposer),
          matching: find.byType(EditableText),
        )
        .last;
    await tester.enterText(composer, 'unsent draft');
    await tester.pump();
    final scrollable = find
        .descendant(
          of: find.byType(CodeLabTranscriptPanel),
          matching: find.byType(Scrollable),
        )
        .first;
    await tester.drag(scrollable, const Offset(0, 300));
    await tester.pump();
    final offset = tester.state<ScrollableState>(scrollable).position.pixels;
    final focused = tester.widget<EditableText>(composer).focusNode.hasFocus;
    scene.agent.drainSentMessages();

    await scene.selectLanguage(AppLanguagePreference.ru);

    // Язык действительно сменился (иначе проверка ввода ничего не доказывает).
    expect(_transcript(scene), contains('Модель достигла лимита токенов'));
    expect(
      tester.widget<EditableText>(composer).controller.text,
      'unsent draft',
    );
    expect(tester.state<ScrollableState>(scrollable).position.pixels, offset);
    expect(tester.widget<EditableText>(composer).focusNode.hasFocus, focused);
    expect(scene.agent.sentMessages, isEmpty);

    await scene.close();
  });

  testWidgets('открытая палитра пересобирается: подписи команд на ru, '
      'строка запроса остаётся', (tester) async {
    final scene = await _openLive(tester);
    scene.cubit.openCommandPalette();
    await scene.flush();
    await tester.enterText(
      find.byKey(CodeLabCommandPaletteSurface.queryFieldKey),
      'sess',
    );
    await tester.pump();
    expect(
      scene.textOf(find.byType(CodeLabCommandPaletteSurface)),
      contains('New session'),
    );

    await scene.selectLanguage(AppLanguagePreference.ru);

    final palette = scene.textOf(find.byType(CodeLabCommandPaletteSurface));
    expect(palette, contains('Новая сессия'));
    expect(palette, isNot(contains('New session')));
    await expectNoStaleLanguage(tester, from: en, to: ru);

    await scene.selectLanguage(AppLanguagePreference.en);
    expect(
      scene.textOf(find.byType(CodeLabCommandPaletteSurface)),
      contains('New session'),
    );
    await scene.close();
  });

  testWidgets('баннер потери соединения: «Retry» баннера и заметка сбоя '
      'пересобираются', (tester) async {
    final scene = await LiveScene.open(tester);
    await scene.newSession('s1');
    await scene.prompt('hello agent');
    await scene.toolCall('s1', toolCallId: 'c1', title: 'Run echo hi');
    scene.agent.fail(
      const AcpTransportException(
        code: AcpTransportErrorCode.closed,
        message: 'Stdio ACP agent exited unexpectedly with code -9.',
      ),
    );
    await tester.runAsync(() => Future<void>.delayed(Duration.zero));
    await scene.flush();
    expect(find.text('Connection to the agent lost'), findsOneWidget);

    await scene.selectLanguage(AppLanguagePreference.ru);

    expect(find.text('Подключение к агенту потеряно'), findsOneWidget);
    expect(
      find.descendant(
        of: find.byType(CodeLabConnectionBanner),
        matching: find.text('Повторить'),
      ),
      findsOneWidget,
    );
    expect(_transcript(scene), contains('Связь с агентом потеряна'));
    await expectNoStaleLanguage(tester, from: en, to: ru);

    await scene.selectLanguage(AppLanguagePreference.en);
    expect(find.text('Connection to the agent lost'), findsOneWidget);
    await scene.close();
  });

  group('доки', () {
    Future<void> openAndSwitch(
      LiveScene scene,
      ToolPane pane,
      WidgetTester tester,
    ) async {
      scene.cubit.openPane(pane);
      await scene.flush();
      await scene.selectLanguage(AppLanguagePreference.ru);
      await expectNoStaleLanguage(tester, from: en, to: ru);
    }

    testWidgets('Files: пустой выбор и обновление на ru', (tester) async {
      final scene = await _openLive(tester);

      await openAndSwitch(scene, ToolPane.files, tester);

      final pane = scene.textOf(
        find.byKey(CodeLabToolDock.paneKey(ToolPane.files)),
      );
      expect(pane, contains('Выберите файл для просмотра.'));
      expect(pane, contains('Обновить'));
      expect(pane, contains('.git никогда не показывается'));

      await scene.selectLanguage(AppLanguagePreference.en);
      expect(
        scene.textOf(find.byKey(CodeLabToolDock.paneKey(ToolPane.files))),
        contains('Select a file to preview it.'),
      );
      await scene.close();
    });

    testWidgets('Usage: блок «Turn budget» с заголовком, строками и числами '
        'ядра', (tester) async {
      final scene = await _openLive(tester);

      await openAndSwitch(scene, ToolPane.usage, tester);

      final budget = scene.textOf(find.byKey(const ValueKey('usage-budget')));
      expect(budget, contains('Этот ход'));
      expect(budget, contains('Шаги'));
      expect(budget, contains('Токены'));
      expect(budget, contains('Стоимость'));
      expect(budget, contains('Время'));
      // Числа — формат ядра: точка, `k`, без пробелов между разрядами (D8).
      expect(budget, contains('92.0k'));
      expect(budget, contains(r'$0.41'));

      await scene.close();
    });

    testWidgets('Terminal: подпись вкладки и предупреждение на ru', (
      tester,
    ) async {
      final scene = await _openLive(tester);
      await tester.runAsync(
        () => scene.binding.scope.resolve<TerminalTabsCubit>().ensureTab(),
      );

      await openAndSwitch(scene, ToolPane.terminal, tester);

      final pane = scene.textOf(find.byType(CodeLabTerminalPane));
      expect(pane, contains('Терминал 1'));
      expect(pane, contains('Выполняется'));

      await scene.close();
    });
  });
}
