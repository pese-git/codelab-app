// Глобальные сочетания ответа на одобрение (задача 7.4 change
// `fix-approval-focus`; design.md D14, D15, D9; spec agent-workbench-ui
// «Ответ на одобрение сочетанием с любого места рабочего места»).
//
// Почему: пользователь выбрал ответ «как в Zed» — ⌘Y, ⌥⌘Y, ⌥⌘Z, ⌥⇧⌘Z на
// macOS и Alt+Shift+Y, Q, X, W на остальных ОС с любого места рабочего места,
// включая композер. Ответ на запрос, которого пользователь не видит или не
// успел увидеть, уходить не должен (AGENTS.md §2 п. 1, §10), поэтому
// сочетание отвечает только активному одобрению, чья полоса видна и которое
// активно не меньше 500 мс, и не отвечает на автоповтор.
//
// Для чего: сквозная проверка в дереве `CodeLabApp` с фейковым транспортом;
// ответ наблюдается на проводе (`JsonRpcResponse` в `sentMessages`), события
// журнала — в `LogBuffer`. Сценарии привязаны к платформе вариантами
// `TargetPlatformVariant`: платформу сочетаний выбирает каталог по
// `defaultTargetPlatform` (D15).
//
// Как читать: красные до задач 7.2 и 7.5 — сценарии, где ответа ждут
// (глобального сочетания нет) и где ждут события журнала; зелёные и до
// реализации — сценарии «не отвечает» (они закрепляют границу, пока ответа
// сочетанием нет вовсе, и защищают от лишнего ответа после 7.5).
//
// Часы: рабочее место получает управляемые часы (`CodeLabTestBinding(clock:)`),
// тест двигает их явно (`advance`, `afterSettling`), реального ожидания нет
// (`testing.md` §20). Те же часы отсчитывают, сколько Alt и Shift зажаты до
// буквы на Windows и Linux (`modifiers_not_held`, порог 150 мс).

import 'dart:async';

import 'package:codelab_acp_protocol/codelab_acp_protocol.dart';
import 'package:codelab_acp_testing/codelab_acp_testing.dart';
import 'package:codelab_desktop/app/codelab_app_widget.dart';
import 'package:codelab_desktop/app/navigation/settings_page.dart';
import 'package:codelab_desktop/features/workbench/application/shell_cubit.dart';
import 'package:codelab_ui/codelab_ui.dart';
import 'package:fluent_ui/fluent_ui.dart';
import 'package:flutter/foundation.dart' show defaultTargetPlatform;
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:structured_log_flutter/structured_log_flutter.dart'
    show LogBuffer;
import 'package:xterm2/ui.dart' show TerminalView;

import '../../../support/fake_user_shell_launcher.dart';
import '../../../support/layout_keys.dart';
import '../../../support/press_shortcut.dart';
import '../../../support/start_agent.dart';
import '../../../support/test_app_scope.dart';

const _answerEvent = 'workbench.approval_answer';
const _skippedEvent = 'workbench.approval_shortcut_skipped';

const _fourOptions = [
  PermissionOption(
    optionId: PermissionOptionId('allow-once'),
    name: 'Allow once',
    kind: PermissionOptionKind.allowOnce,
  ),
  PermissionOption(
    optionId: PermissionOptionId('allow-always'),
    name: 'Always allow echo *',
    kind: PermissionOptionKind.allowAlways,
  ),
  PermissionOption(
    optionId: PermissionOptionId('reject-once'),
    name: 'Reject',
    kind: PermissionOptionKind.rejectOnce,
  ),
  PermissionOption(
    optionId: PermissionOptionId('reject-always'),
    name: 'Always reject echo *',
    kind: PermissionOptionKind.rejectAlways,
  ),
];

void main() {
  late FakeAcpTransport agent;
  late CodeLabShellCubit cubit;
  late CodeLabTestBinding binding;
  var now = DateTime.utc(2026, 11, 20, 12);

  setUp(() {
    now = DateTime.utc(2026, 11, 20, 12);
    final view = TestWidgetsFlutterBinding.ensureInitialized()
        .platformDispatcher
        .views
        .single;
    view.physicalSize = const Size(1440, 1400);
    view.devicePixelRatio = 1.0;
    addTearDown(view.resetPhysicalSize);
    addTearDown(view.resetDevicePixelRatio);
  });

  Future<void> shortFrames(WidgetTester tester) async {
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
  }

  Future<void> settle(WidgetTester tester) async {
    await tester.runAsync(() => Future<void>.delayed(Duration.zero));
    await tester.pump();
  }

  /// Сдвигает управляемые часы и кадры на [by].
  Future<void> advance(WidgetTester tester, Duration by) async {
    now = now.add(by);
    await tester.pump(by);
  }

  /// Задержка после появления (D14, п. 2): 600 мс на управляемых часах.
  Future<void> afterSettling(WidgetTester tester) =>
      advance(tester, const Duration(milliseconds: 600));

  /// Нажимает сочетание ответа так, как его нажимает пользователь: на Windows
  /// и Linux Alt и Shift зажаты заранее ([hold]), на macOS условия нет.
  Future<void> pressAnswerShortcut(
    WidgetTester tester,
    CodeLabShortcut shortcut, {
    Duration hold = const Duration(milliseconds: 200),
  }) => pressShortcut(
    tester,
    shortcut,
    afterModifiers: defaultTargetPlatform == TargetPlatform.macOS
        ? null
        : () => now = now.add(hold),
  );

  Future<void> pumpConnected(
    WidgetTester tester, {
    SettingsPages? settingsPages,
    FakeUserShellLauncher? shells,
    FakeAcpTransport? withAgent,
    Map<String, String> listed = const {},
  }) async {
    agent = withAgent ?? FakeAcpTransport();
    binding = CodeLabTestBinding(
      project: '/workspace',
      transport: FakeAcpTransport(),
      stdioTransportFactory: (_) => agent,
      settingsPages: settingsPages,
      userShellLauncher: shells,
      clock: () => now,
    );
    await tester.pumpWidget(
      binding.bootstrap(child: const CodeLabApp(startOnLaunch: false)),
    );
    await tester.pump();
    cubit = binding.scope.resolve<CodeLabShellCubit>();
    if (listed.isEmpty) {
      await tester.runAsync(() => cubit.startWith());
    } else {
      // Агент отдаёт список сессий: запуск ждёт ответа на `session/list`.
      await tester.runAsync(() async {
        final request = agent.sent.firstWhere(
          (m) => m is JsonRpcRequest && m.method == sessionListMethod,
        );
        final started = cubit.startWith();
        final list = await request as JsonRpcRequest;
        agent.emitInbound(
          JsonRpcMessage.response(
            id: list.id,
            result: ListSessionsResponse(
              sessions: [
                for (final entry in listed.entries)
                  SessionInfo(
                    sessionId: SessionId(entry.key),
                    cwd: entry.value,
                    title: entry.key,
                  ),
              ],
            ).toJson(),
          ),
        );
        await started;
      });
    }
    await tester.pump();
  }

  Future<void> tearDownApp(WidgetTester tester) async {
    // В полёте остаются таймеры запросов; без паузы они переживают дерево.
    await tester.pump(const Duration(seconds: 10));
    await tester.pumpWidget(const SizedBox.shrink());
    await closeCodeLabRootScopeInTest();
  }

  Future<void> createSession(WidgetTester tester, String id) async {
    agent.drainSentMessages();
    unawaited(cubit.createSession());
    await settle(tester);
    final request = agent.sentMessages.whereType<JsonRpcRequest>().singleWhere(
      (r) => r.method == sessionNewMethod,
    );
    agent.emitInbound(
      JsonRpcMessage.response(id: request.id, result: {'sessionId': id}),
    );
    await settle(tester);
  }

  /// Запрос разрешения привязывается к ходу, поэтому сначала идёт ход.
  Future<void> startTurn(WidgetTester tester) async {
    unawaited(cubit.submitPrompt('run a command'));
    await settle(tester);
  }

  void ask(
    String sessionId,
    int id, {
    String? toolCallId,
    List<PermissionOption> options = _fourOptions,
  }) {
    agent.emitInbound(
      JsonRpcMessage.request(
        id: JsonRpcId.integer(id),
        method: sessionRequestPermissionMethod,
        params: RequestPermissionRequest(
          sessionId: SessionId(sessionId),
          toolCall: ToolCallUpdate(
            toolCallId: ToolCallId(toolCallId ?? 'call-$id'),
            title: 'Run echo',
            kind: ToolKind.execute,
            status: ToolCallStatus.inProgress,
            rawInput: const {'command': 'echo hi'},
          ),
          options: options,
        ).toJson(),
      ),
    );
  }

  /// Сессия с идущим ходом и ожидающим одобрением [id].
  Future<void> sessionWithApproval(
    WidgetTester tester,
    int id, {
    List<PermissionOption> options = _fourOptions,
  }) async {
    await createSession(tester, 'session-1');
    await startTurn(tester);
    ask('session-1', id, options: options);
    await settle(tester);
    await shortFrames(tester);
  }

  List<JsonRpcResponse> answers() =>
      agent.sentMessages.whereType<JsonRpcResponse>().toList();

  String? chosenOption(JsonRpcResponse response) =>
      ((response.result! as Map)['outcome'] as Map)['optionId'] as String?;

  List<Map<String, Object?>> journal(String event) => [
    for (final entry in binding.scope.resolve<LogBuffer>().entries.value)
      if (entry['event'] == event) entry,
  ];

  bool focusInside<T extends Widget>() =>
      FocusManager.instance.primaryFocus?.context
          ?.findAncestorWidgetOfExactType<T>() !=
      null;

  final composerField = find
      .descendant(
        of: find.byType(CodeLabPromptComposer),
        matching: find.byType(EditableText),
      )
      .last;

  String composerText(WidgetTester tester) =>
      tester.widget<EditableText>(composerField).controller.text;

  Future<void> focusComposer(WidgetTester tester, {String? text}) async {
    await tester.tap(composerField);
    if (text != null) {
      await tester.enterText(composerField, text);
    }
    await tester.pump();
    expect(focusInside<CodeLabPromptComposer>(), isTrue);
  }

  /// Нажимает клавишу с произвольным набором модификаторов.
  Future<void> pressKey(
    WidgetTester tester,
    LogicalKeyboardKey key, {
    bool meta = false,
    bool control = false,
    bool alt = false,
    bool shift = false,
    int repeats = 0,
  }) async {
    final modifiers = [
      if (control) LogicalKeyboardKey.controlLeft,
      if (meta) LogicalKeyboardKey.metaLeft,
      if (alt) LogicalKeyboardKey.altLeft,
      if (shift) LogicalKeyboardKey.shiftLeft,
    ];
    for (final modifier in modifiers) {
      await tester.sendKeyDownEvent(modifier);
    }
    await tester.sendKeyDownEvent(key);
    for (var i = 0; i < repeats; i++) {
      await tester.sendKeyRepeatEvent(key);
    }
    await tester.sendKeyUpEvent(key);
    for (final modifier in modifiers.reversed) {
      await tester.sendKeyUpEvent(modifier);
    }
    await tester.pump(const Duration(milliseconds: 100));
    await settle(tester);
  }

  final prompts = find.byType(CodeLabApprovalPrompt);
  final macOS = TargetPlatformVariant.only(TargetPlatform.macOS);
  final linux = TargetPlatformVariant.only(TargetPlatform.linux);
  final windows = TargetPlatformVariant.only(TargetPlatform.windows);

  // ---------------------------------------------------------------------
  // Ответ: из композера, по платформам, «Отклонить всегда», журнал.

  group('ответ сочетанием', () {
    testWidgets('Ответ из композера: ⌘Y выбирает allow_once, текст и фокус '
        'композера целы, в журнале source: shortcut', (tester) async {
      await pumpConnected(tester);
      await createSession(tester, 'session-1');
      await startTurn(tester);
      await focusComposer(tester, text: 'draft');
      ask('session-1', 801);
      await settle(tester);
      await shortFrames(tester);
      await afterSettling(tester);

      await pressAnswerShortcut(tester, CodeLabShortcut.allowOnce);
      await settle(tester);

      final given = answers();
      expect(given, hasLength(1));
      expect(given.single.id, const JsonRpcId.integer(801));
      expect(chosenOption(given.single), 'allow-once');
      expect(composerText(tester), 'draft');
      expect(focusInside<CodeLabPromptComposer>(), isTrue);

      final logged = journal(_answerEvent);
      expect(logged, hasLength(1));
      expect(logged.single['level'], 'info');
      expect(logged.single['session_id'], 'session-1');
      expect(logged.single['request_id'], 'permission-801');
      expect(logged.single['tool_call_id'], 'call-801');
      expect(logged.single['kind'], 'allow_once');
      expect(logged.single['source'], 'shortcut');
      // Сырые аргументы, заголовок и подписи агента в журнал не попадают.
      final text = '${logged.single}';
      expect(text, isNot(contains('echo hi')));
      expect(text, isNot(contains('Run echo')));
      expect(text, isNot(contains('Always allow')));
      await tearDownApp(tester);
    }, variant: macOS);

    testWidgets('Ответ на Windows и Linux: Alt+Shift+Q — allow_always, '
        'Alt+Shift+X — reject_once', (tester) async {
      await pumpConnected(tester);
      await createSession(tester, 'session-1');
      await startTurn(tester);
      await focusComposer(tester);
      ask('session-1', 802);
      await settle(tester);
      await shortFrames(tester);
      await afterSettling(tester);

      await pressAnswerShortcut(tester, CodeLabShortcut.allowAlways);
      await shortFrames(tester);
      ask('session-1', 803);
      await settle(tester);
      await shortFrames(tester);
      await afterSettling(tester);
      await pressAnswerShortcut(tester, CodeLabShortcut.rejectOnce);
      await settle(tester);

      final given = answers();
      expect(given.map((r) => r.id), [
        const JsonRpcId.integer(802),
        const JsonRpcId.integer(803),
      ]);
      expect(given.map(chosenOption), ['allow-always', 'reject-once']);
      await tearDownApp(tester);
    }, variant: linux);

    for (final entry in {
      'macOS': macOS,
      'Linux': linux,
      'Windows': windows,
    }.entries) {
      testWidgets('Отклонить всегда (${entry.key}): ⌥⇧⌘Z / Alt+Shift+W '
          'выбирает reject_always', (tester) async {
        await pumpConnected(tester);
        await sessionWithApproval(tester, 804);
        await focusComposer(tester);
        await afterSettling(tester);

        await pressAnswerShortcut(tester, CodeLabShortcut.rejectAlways);
        await settle(tester);

        final given = answers();
        expect(given, hasLength(1));
        expect(chosenOption(given.single), 'reject-always');
        expect(journal(_answerEvent).single['kind'], 'reject_always');
        await tearDownApp(tester);
      }, variant: entry.value);
    }

    testWidgets('Ответ кнопкой журналируется: source: button, без сырых '
        'аргументов и команды', (tester) async {
      await pumpConnected(tester);
      await sessionWithApproval(tester, 805);

      await tester.tap(find.byKey(CodeLabApprovalPrompt.allowKey));
      await tester.pump(const Duration(milliseconds: 100));
      await settle(tester);

      expect(chosenOption(answers().single), 'allow-once');
      final logged = journal(_answerEvent);
      expect(logged, hasLength(1));
      expect(logged.single['source'], 'button');
      expect(logged.single['request_id'], 'permission-805');
      expect('${logged.single}', isNot(contains('echo hi')));
      await tearDownApp(tester);
    });
  });

  // ---------------------------------------------------------------------
  // Клавиши, которые не должны отвечать.

  group('чужие клавиши и правка текста', () {
    testWidgets('Отмена и повтор правки на macOS не отвечают: ⌘Z и ⇧⌘Z', (
      tester,
    ) async {
      await pumpConnected(tester);
      await sessionWithApproval(tester, 811);
      await focusComposer(tester, text: 'a');
      await tester.pump(const Duration(milliseconds: 600));
      await tester.enterText(composerField, 'ab');
      await tester.pump(const Duration(milliseconds: 600));
      await afterSettling(tester);

      await pressKey(tester, LogicalKeyboardKey.keyZ, meta: true);
      expect(composerText(tester), 'a', reason: '⌘Z отменяет правку');
      await pressKey(tester, LogicalKeyboardKey.keyZ, meta: true, shift: true);
      expect(composerText(tester), 'ab', reason: '⇧⌘Z повторяет правку');

      expect(answers(), isEmpty);
      expect(prompts, findsOneWidget);
      await tearDownApp(tester);
    }, variant: macOS);

    testWidgets('Повтор правки в композере не отвечает (Windows): Ctrl+Z, '
        'Ctrl+Y', (tester) async {
      await pumpConnected(tester);
      await sessionWithApproval(tester, 812);
      await focusComposer(tester, text: 'a');
      await tester.pump(const Duration(milliseconds: 600));
      await tester.enterText(composerField, 'ab');
      await tester.pump(const Duration(milliseconds: 600));
      await afterSettling(tester);

      await pressKey(tester, LogicalKeyboardKey.keyZ, control: true);
      expect(composerText(tester), 'a', reason: 'Ctrl+Z отменяет правку');
      // Ctrl+Y в поле Flutter не привязан к повтору (повтор — Ctrl+Shift+Z),
      // но и ответом он быть не должен (спека «Повтор правки в композере не
      // отвечает»): текст прежний, ответа нет.
      await pressKey(tester, LogicalKeyboardKey.keyY, control: true);
      expect(answers(), isEmpty);
      await pressKey(
        tester,
        LogicalKeyboardKey.keyZ,
        control: true,
        shift: true,
      );
      expect(composerText(tester), 'ab', reason: 'Ctrl+Shift+Z повторяет');

      expect(answers(), isEmpty);
      expect(prompts, findsOneWidget);
      await tearDownApp(tester);
    }, variant: windows);

    testWidgets('Чужие модификаторы не отвечают (macOS): Ctrl+Y', (
      tester,
    ) async {
      await pumpConnected(tester);
      await sessionWithApproval(tester, 813);
      await focusComposer(tester);
      await afterSettling(tester);

      await pressKey(tester, LogicalKeyboardKey.keyY, control: true);

      expect(answers(), isEmpty);
      await tearDownApp(tester);
    }, variant: macOS);

    testWidgets('Чужие модификаторы не отвечают (Linux): Ctrl+Y и Cmd+Y', (
      tester,
    ) async {
      await pumpConnected(tester);
      await sessionWithApproval(tester, 814);
      await focusComposer(tester);
      await afterSettling(tester);

      await pressKey(tester, LogicalKeyboardKey.keyY, control: true);
      await pressKey(tester, LogicalKeyboardKey.keyY, meta: true);

      expect(answers(), isEmpty);
      await tearDownApp(tester);
    }, variant: linux);

    testWidgets('Отправка остаётся отправкой: Cmd/Ctrl+Enter ставит '
        'сообщение в очередь, одобрение ждёт', (tester) async {
      await pumpConnected(tester);
      await sessionWithApproval(tester, 815);
      await focusComposer(tester, text: 'run tests');
      await afterSettling(tester);

      await pressShortcut(tester, CodeLabShortcut.send);
      await settle(tester);

      expect(cubit.state.queuedPrompts, hasLength(1));
      expect(cubit.state.queuedPrompts.single.content, 'run tests');
      expect(answers(), isEmpty);
      expect(prompts, findsOneWidget);
      await tearDownApp(tester);
    });
  });

  // ---------------------------------------------------------------------
  // Компенсирующие меры: видимость, задержка, автоповтор.

  group('компенсирующие меры', () {
    Map<String, Object?> fillerCall(int i) => {
      'sessionUpdate': 'tool_call',
      'toolCallId': 'filler$i',
      'title': 'Read filler$i',
      'kind': 'read',
      'status': 'completed',
      'rawInput': {'path': '/workspace/filler$i.dart'},
    };

    Future<void> frames(
      WidgetTester tester,
      Iterable<Map<String, Object?>> updates,
    ) async {
      for (final update in updates) {
        agent.emitInbound(
          JsonRpcMessage.notification(
            method: sessionUpdateMethod,
            params: {'sessionId': 'session-1', 'update': update},
          ),
        );
      }
      await settle(tester);
    }

    testWidgets('Полоса не видна — первое нажатие показывает: ответа нет, '
        'фокус прежний, в журнале not_visible; отсчёт 500 мс идёт от показа, '
        'а не от активации', (tester) async {
      await pumpConnected(tester);
      await createSession(tester, 'session-1');
      await startTurn(tester);
      // Строки до вопроса: лента держит ожидающее одобрение в поле зрения
      // сама, поэтому полосу уводит за край только прокрутка пользователя.
      await frames(tester, [for (var i = 0; i < 60; i++) fillerCall(i)]);
      await shortFrames(tester);
      ask('session-1', 821);
      await settle(tester);
      await shortFrames(tester);
      expect(prompts, findsOneWidget);
      await focusComposer(tester);
      // Пользователь прокрутил ленту вверх: полоса ушла за нижний край.
      await tester.drag(
        find.descendant(
          of: find.byType(CodeLabTranscriptPanel),
          matching: find.byType(ListView),
        ),
        const Offset(0, 5000),
      );
      await tester.pump();
      await tester.pump();
      await afterSettling(tester);
      expect(prompts, findsNothing, reason: 'полоса вне области, не построена');

      await pressAnswerShortcut(tester, CodeLabShortcut.allowOnce);
      await shortFrames(tester);

      expect(answers(), isEmpty);
      expect(prompts, findsOneWidget, reason: 'лента прокручена к полосе');
      expect(focusInside<CodeLabPromptComposer>(), isTrue);
      final skipped = journal(_skippedEvent);
      expect(skipped, hasLength(1));
      expect(skipped.single['reason'], 'not_visible');
      // Диагностика причины: на момент записи полоса уже показана, поэтому
      // деталь — одна из записей ленты, а не пустая.
      expect(skipped.single['visibility_detail'], isA<String>());
      expect(skipped.single['request_id'], 'permission-821');
      expect(skipped.single['session_id'], 'session-1');

      // Запрос активен давно, но полосу показали только что: через 100 мс
      // после показа сочетание ещё не отвечает (D14, п. 2).
      await advance(tester, const Duration(milliseconds: 100));
      await pressAnswerShortcut(tester, CodeLabShortcut.allowOnce);
      await settle(tester);
      expect(answers(), isEmpty, reason: '100 мс после показа — рано');
      expect(journal(_skippedEvent).last['reason'], 'settling');

      // Через 500 мс после показа сочетание отвечает (часы уже ушли вперёд
      // на срок зажатия модификаторов, поэтому добавляем остаток с запасом).
      await advance(tester, const Duration(milliseconds: 500));
      await pressAnswerShortcut(tester, CodeLabShortcut.allowOnce);
      await settle(tester);

      final given = answers();
      expect(given, hasLength(1));
      expect(chosenOption(given.single), 'allow-once');
      await tearDownApp(tester);
    });

    testWidgets('Запрос только что появился: ответа нет, в журнале settling; '
        'после 500 мс сочетание отвечает', (tester) async {
      await pumpConnected(tester);
      await createSession(tester, 'session-1');
      await startTurn(tester);
      await focusComposer(tester);
      ask('session-1', 822);
      await settle(tester);
      // Полоса построена, но прошло заведомо меньше 500 мс.
      await advance(tester, const Duration(milliseconds: 100));
      expect(prompts, findsOneWidget);

      await pressAnswerShortcut(tester, CodeLabShortcut.allowOnce);
      await settle(tester);

      expect(answers(), isEmpty);
      final skipped = journal(_skippedEvent);
      expect(skipped, hasLength(1));
      expect(skipped.single['reason'], 'settling');
      expect(skipped.single['request_id'], 'permission-822');

      await afterSettling(tester);
      await pressAnswerShortcut(tester, CodeLabShortcut.allowOnce);
      await settle(tester);

      expect(chosenOption(answers().single), 'allow-once');
      await tearDownApp(tester);
    });

    testWidgets('Двойное нажатие после ответа: B ждёт', (tester) async {
      await pumpConnected(tester);
      await createSession(tester, 'session-1');
      await startTurn(tester);
      await focusComposer(tester);
      ask('session-1', 823);
      await settle(tester);
      ask('session-1', 824);
      await settle(tester);
      await shortFrames(tester);
      await afterSettling(tester);

      await pressAnswerShortcut(tester, CodeLabShortcut.allowOnce);
      await settle(tester);
      expect(answers(), hasLength(1));
      expect(answers().single.id, const JsonRpcId.integer(823));

      // B стало активным; через 100 мс пользователь нажимает снова.
      await advance(tester, const Duration(milliseconds: 100));
      await pressAnswerShortcut(tester, CodeLabShortcut.allowOnce);
      await settle(tester);

      expect(answers(), hasLength(1), reason: 'ответ на B не отправлен');
      expect(prompts, findsOneWidget);
      final skipped = journal(_skippedEvent);
      expect(skipped.single['reason'], 'settling');
      expect(skipped.single['request_id'], 'permission-824');
      await tearDownApp(tester);
    });

    testWidgets('Удержание клавиши: автоповтор не отвечает, ответ ровно '
        'один', (tester) async {
      await pumpConnected(tester);
      await createSession(tester, 'session-1');
      await startTurn(tester);
      await focusComposer(tester);
      ask('session-1', 825);
      await settle(tester);
      ask('session-1', 826);
      await settle(tester);
      await shortFrames(tester);
      await afterSettling(tester);

      final combo = CodeLabShortcut.allowOnce
          .combosFor(defaultTargetPlatform)
          .single;
      await tester.sendKeyDownEvent(LogicalKeyboardKey.metaLeft);
      await tester.sendKeyDownEvent(combo.key);
      await settle(tester);
      expect(answers(), hasLength(1), reason: 'нажатие отвечает на A');
      // К моменту событий автоповтора B уже активно дольше 500 мс: без
      // защиты от автоповтора оно получило бы ответ.
      await afterSettling(tester);
      await tester.sendKeyRepeatEvent(combo.key);
      await tester.sendKeyRepeatEvent(combo.key);
      await tester.sendKeyUpEvent(combo.key);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.metaLeft);
      await settle(tester);

      expect(answers(), hasLength(1), reason: 'B автоповтор не отвечает');
      expect(prompts, findsOneWidget);
      await tearDownApp(tester);
    }, variant: macOS);
  });

  // ---------------------------------------------------------------------
  // Windows и Linux: Alt и Shift зажаты заранее (решение пользователя
  // 2026-11-20): Alt+Shift — ещё и смена раскладки.

  group('Alt и Shift зажаты заранее (Windows и Linux)', () {
    for (final entry in {'Linux': linux, 'Windows': windows}.entries) {
      testWidgets('${entry.key}: вместе с буквой и меньше 150 мс не отвечает, '
          '150 мс и больше отвечает', (tester) async {
        await pumpConnected(tester);
        await sessionWithApproval(tester, 851);
        await focusComposer(tester);
        await afterSettling(tester);

        // Модификаторы нажаты одновременно с буквой.
        await pressShortcut(tester, CodeLabShortcut.allowOnce);
        await settle(tester);
        expect(answers(), isEmpty, reason: 'вместе с буквой');
        // Смена раскладки не повод прокручивать ленту к полосе.
        expect(focusInside<CodeLabPromptComposer>(), isTrue);

        await pressShortcut(
          tester,
          CodeLabShortcut.allowOnce,
          afterModifiers: () =>
              now = now.add(const Duration(milliseconds: 149)),
        );
        await settle(tester);
        expect(answers(), isEmpty, reason: '149 мс');

        final skipped = journal(_skippedEvent);
        expect(skipped, hasLength(2));
        for (final entry in skipped) {
          expect(entry['reason'], 'modifiers_not_held');
          expect(entry['request_id'], 'permission-851');
          expect(entry['session_id'], 'session-1');
        }

        await pressShortcut(
          tester,
          CodeLabShortcut.allowOnce,
          afterModifiers: () =>
              now = now.add(const Duration(milliseconds: 150)),
        );
        await settle(tester);

        final given = answers();
        expect(given, hasLength(1));
        expect(chosenOption(given.single), 'allow-once');
        expect(journal(_skippedEvent), hasLength(2));
        await tearDownApp(tester);
      }, variant: entry.value);
    }

    testWidgets('macOS: ⌘Y отвечает без условия зажатия', (tester) async {
      await pumpConnected(tester);
      await sessionWithApproval(tester, 852);
      await focusComposer(tester);
      await afterSettling(tester);

      await pressShortcut(tester, CodeLabShortcut.allowOnce);
      await settle(tester);

      expect(answers(), hasLength(1));
      expect(journal(_skippedEvent), isEmpty);
      await tearDownApp(tester);
    }, variant: macOS);
  });

  // ---------------------------------------------------------------------
  // Раскладка ввода (итерация 8, задача 8.3; design.md D16; spec
  // agent-workbench-ui «Сочетания app не зависят от раскладки ввода»).
  // Красные до реализации 8.2, кроме «кириллица без модификаторов» — он
  // закрепляет границу и защищает от лишнего ответа после 8.2.

  group('раскладка ввода (D16)', () {
    testWidgets('Русская раскладка macOS: ⌘«н» выбирает allow_once', (
      tester,
    ) async {
      await pumpConnected(tester);
      await sessionWithApproval(tester, 861);
      await focusComposer(tester);
      await afterSettling(tester);

      await pressLayoutKey(
        tester,
        russianKey(LogicalKeyboardKey.keyY),
        meta: true,
      );
      await settle(tester);

      final given = answers();
      expect(given, hasLength(1));
      expect(chosenOption(given.single), 'allow-once');
      expect(journal(_answerEvent).single['source'], 'shortcut');
      await tearDownApp(tester);
    }, variant: macOS);

    for (final entry in {'Linux': linux, 'Windows': windows}.entries) {
      testWidgets('Русская раскладка (${entry.key}): Alt+Shift+«н» — удержание '
          'по-прежнему нужно', (tester) async {
        await pumpConnected(tester);
        await sessionWithApproval(tester, 862);
        await focusComposer(tester);
        await afterSettling(tester);
        final y = russianKey(LogicalKeyboardKey.keyY);

        // Через 50 мс после модификаторов: ответа нет.
        await pressLayoutKey(
          tester,
          y,
          alt: true,
          shift: true,
          afterModifiers: () => now = now.add(const Duration(milliseconds: 50)),
        );
        await settle(tester);
        expect(answers(), isEmpty);
        final skipped = journal(_skippedEvent);
        expect(skipped, hasLength(1));
        expect(skipped.single['reason'], 'modifiers_not_held');

        // Через 200 мс: allow_once.
        await pressLayoutKey(
          tester,
          y,
          alt: true,
          shift: true,
          afterModifiers: () =>
              now = now.add(const Duration(milliseconds: 200)),
        );
        await settle(tester);
        final given = answers();
        expect(given, hasLength(1));
        expect(chosenOption(given.single), 'allow-once');
        await tearDownApp(tester);
      }, variant: entry.value);
    }

    testWidgets('AZERTY (macOS): ⌥⌘ и напечатанная Z — reject_once, физическая '
        'Z с логической w — нет', (tester) async {
      await pumpConnected(tester);
      await sessionWithApproval(tester, 863);
      await focusComposer(tester);
      await afterSettling(tester);

      await pressLayoutKey(tester, azertyW, meta: true, alt: true);
      await settle(tester);
      expect(answers(), isEmpty, reason: 'логическая w — не Z');

      await pressLayoutKey(tester, azertyZ, meta: true, alt: true);
      await settle(tester);
      final given = answers();
      expect(given, hasLength(1));
      expect(chosenOption(given.single), 'reject-once');
      await tearDownApp(tester);
    }, variant: macOS);

    for (final entry in {'macOS': macOS, 'Windows': windows}.entries) {
      testWidgets('Кириллица без модификаторов не отвечает (${entry.key}): '
          '«нйлф»', (tester) async {
        await pumpConnected(tester);
        await sessionWithApproval(tester, 864);
        await focusComposer(tester);
        await afterSettling(tester);

        for (final latin in const [
          LogicalKeyboardKey.keyY,
          LogicalKeyboardKey.keyQ,
          LogicalKeyboardKey.keyK,
          LogicalKeyboardKey.keyA,
        ]) {
          await pressLayoutKey(tester, russianKey(latin));
        }
        await settle(tester);

        expect(answers(), isEmpty);
        expect(find.byType(CodeLabCommandPaletteSurface), findsNothing);
        expect(prompts, findsOneWidget);
        expect(focusInside<CodeLabPromptComposer>(), isTrue);
        await tearDownApp(tester);
      }, variant: entry.value);
    }
  });

  // ---------------------------------------------------------------------
  // Предыдущий ответ в полёте.

  group('предыдущий ответ в полёте', () {
    testWidgets('второе нажатие до ответа не отправляет второй ответ и '
        'оставляет answer_in_flight в журнале', (tester) async {
      await pumpConnected(tester);
      await sessionWithApproval(tester, 861);
      await afterSettling(tester);

      // Два нажатия подряд, пока первый ответ не завершён.
      void press() => cubit.answerApprovalByShortcut(
        CodeLabApprovalOptionKind.allowOnce,
        isVisible: (_, _) => true,
        modifiersHeldFor: null,
      );
      press();
      press();
      await settle(tester);

      expect(answers(), hasLength(1));
      final skipped = journal(_skippedEvent);
      expect(skipped, hasLength(1));
      expect(skipped.single['reason'], 'answer_in_flight');
      expect(skipped.single['request_id'], 'permission-861');
      expect(skipped.single['session_id'], 'session-1');
      await tearDownApp(tester);
    });
  });

  // ---------------------------------------------------------------------
  // Цель и вариант.

  group('цель и вариант', () {
    testWidgets('Несколько одобрений — ответ самому раннему: ⌥⌘Z', (
      tester,
    ) async {
      await pumpConnected(tester);
      await createSession(tester, 'session-1');
      await startTurn(tester);
      await focusComposer(tester);
      ask('session-1', 831);
      await settle(tester);
      ask('session-1', 832);
      await settle(tester);
      await shortFrames(tester);
      expect(prompts, findsNWidgets(2));
      await afterSettling(tester);

      await pressAnswerShortcut(tester, CodeLabShortcut.rejectOnce);
      await settle(tester);

      final given = answers();
      expect(given, hasLength(1));
      expect(given.single.id, const JsonRpcId.integer(831));
      expect(chosenOption(given.single), 'reject-once');
      expect(prompts, findsOneWidget, reason: 'B ждёт');
      await tearDownApp(tester);
    }, variant: macOS);

    testWidgets('Одобрение субагента: ⌘Y выбирает allow_once, строка agent '
        'корня остаётся свёрнутой', (tester) async {
      await pumpConnected(tester);
      await createSession(tester, 'session-1');
      await startTurn(tester);
      Map<String, Object?> agentCall(
        String id,
        String type,
        String subagentId, {
        String? parent,
      }) => {
        'sessionUpdate': 'tool_call',
        'toolCallId': id,
        'title': 'Subagent $type: Find auth code',
        'kind': 'think',
        'status': 'in_progress',
        'rawInput': {'type': type, 'description': 'Find auth code'},
        '_meta': {
          'codelab': {
            'parentToolCallId': ?parent,
            'subagent': {'id': subagentId, 'type': type},
          },
        },
      };
      for (final update in [
        agentCall('call_1', 'review', 'sub_a1'),
        agentCall('call_1/call_2', 'explore', 'sub_b2', parent: 'call_1'),
        {
          'sessionUpdate': 'tool_call',
          'toolCallId': 'call_1/call_2/call_3',
          'title': 'Run git diff --stat',
          'kind': 'execute',
          'status': 'pending',
          'rawInput': {'command': 'git diff --stat'},
          '_meta': {
            'codelab': {'parentToolCallId': 'call_1/call_2'},
          },
        },
      ]) {
        agent.emitInbound(
          JsonRpcMessage.notification(
            method: sessionUpdateMethod,
            params: {'sessionId': 'session-1', 'update': update},
          ),
        );
      }
      await settle(tester);
      agent.emitInbound(
        JsonRpcMessage.request(
          id: const JsonRpcId.integer(833),
          method: sessionRequestPermissionMethod,
          params: RequestPermissionRequest(
            sessionId: const SessionId('session-1'),
            toolCall: ToolCallUpdate(
              toolCallId: const ToolCallId('call_1/call_2/call_3'),
              title: 'Run git diff --stat',
              kind: ToolKind.execute,
              status: ToolCallStatus.pending,
              rawInput: const {'command': 'git diff --stat'},
              meta: const {
                'codelab': {
                  'subagent': {
                    'id': 'sub_b2',
                    'type': 'explore',
                    'description': 'Find callers',
                    'depth': 2,
                    'path': <String>[],
                    'parentToolCallId': 'call_1',
                  },
                },
              },
            ),
            options: _fourOptions,
          ).toJson(),
        ),
      );
      await settle(tester);
      await shortFrames(tester);
      await focusComposer(tester);
      await afterSettling(tester);
      expect(prompts, findsOneWidget, reason: 'блок под строкой agent виден');

      await pressAnswerShortcut(tester, CodeLabShortcut.allowOnce);
      await settle(tester);

      final given = answers();
      expect(given, hasLength(1));
      expect(given.single.id, const JsonRpcId.integer(833));
      expect(chosenOption(given.single), 'allow-once');
      expect(
        cubit.state.transcriptExpansion.values,
        everyElement(isNot(isTrue)),
        reason: 'строка agent корня не раскрыта',
      );
      await tearDownApp(tester);
    }, variant: macOS);

    testWidgets('Нет варианта этого вида: ⌥⌘Y при allow_once и reject_once '
        'не отвечает, в журнале no_option', (tester) async {
      await pumpConnected(tester);
      await sessionWithApproval(
        tester,
        834,
        options: [_fourOptions.first, _fourOptions[2]],
      );
      await focusComposer(tester);
      await afterSettling(tester);

      await pressAnswerShortcut(tester, CodeLabShortcut.allowAlways);
      await settle(tester);

      expect(answers(), isEmpty);
      final skipped = journal(_skippedEvent);
      expect(skipped, hasLength(1));
      expect(skipped.single['reason'], 'no_option');
      expect(skipped.single['request_id'], 'permission-834');
      await tearDownApp(tester);
    }, variant: macOS);
  });

  // ---------------------------------------------------------------------
  // Где сочетание не действует.

  group('вне рабочего места сочетание не действует', () {
    testWidgets('экран настроек: ⌘Y не отвечает', (tester) async {
      await pumpConnected(
        tester,
        settingsPages: const SettingsPages(
          available: {SettingsPage.connection},
        ),
      );
      await sessionWithApproval(tester, 841);
      await afterSettling(tester);
      await pressShortcut(tester, CodeLabShortcut.openSettings);
      await shortFrames(tester);
      expect(
        find.byKey(const ValueKey('settings-nav-connection')),
        findsOneWidget,
      );

      await pressAnswerShortcut(tester, CodeLabShortcut.allowOnce);
      await settle(tester);

      expect(answers(), isEmpty);
      await tearDownApp(tester);
    }, variant: macOS);

    testWidgets('палитра команд открыта: ⌘Y не отвечает', (tester) async {
      await pumpConnected(tester);
      await sessionWithApproval(tester, 842);
      await afterSettling(tester);
      await pressShortcut(tester, CodeLabShortcut.commandPalette);
      await shortFrames(tester);
      expect(find.byType(CodeLabCommandPaletteSurface), findsOneWidget);

      await pressAnswerShortcut(tester, CodeLabShortcut.allowOnce);
      await settle(tester);

      expect(answers(), isEmpty);
      expect(find.byType(CodeLabCommandPaletteSurface), findsOneWidget);
      await tearDownApp(tester);
    }, variant: macOS);

    testWidgets('диалог «Add connection profile»: ⌘Y не отвечает', (
      tester,
    ) async {
      await pumpConnected(
        tester,
        settingsPages: const SettingsPages(
          available: {SettingsPage.connection},
        ),
      );
      await sessionWithApproval(tester, 843);
      await afterSettling(tester);
      await pressShortcut(tester, CodeLabShortcut.openSettings);
      await shortFrames(tester);
      await tester.tap(find.byKey(const ValueKey('connection-add-profile')));
      await tester.pumpAndSettle();
      expect(find.text('Add connection profile'), findsOneWidget);

      await pressAnswerShortcut(tester, CodeLabShortcut.allowOnce);
      await settle(tester);

      expect(answers(), isEmpty);
      expect(find.text('Add connection profile'), findsOneWidget);
      await tearDownApp(tester);
    }, variant: macOS);

    testWidgets('диалог открытия сессии в корне диска: ⌘Y не отвечает', (
      tester,
    ) async {
      await pumpConnected(
        tester,
        withAgent: FakeAcpTransport()
          ..initializeAgentCapabilities = const AgentCapabilities(
            loadSession: true,
            sessionCapabilities: SessionCapabilities(
              list: SessionListCapabilities(),
            ),
          ),
        listed: const {'s-root': '/'},
      );
      await sessionWithApproval(tester, 846);
      await afterSettling(tester);
      cubit.selectSession('s-root');
      await settle(tester);
      await shortFrames(tester);
      expect(cubit.state.pendingRootSession, isNotNull);

      await pressAnswerShortcut(tester, CodeLabShortcut.allowOnce);
      await settle(tester);

      expect(answers(), isEmpty, reason: 'диалог закрывает рабочее место');
      // Не полагаемся на проверку видимости: даже если лента сочтёт полосу
      // видимой, пока диалог открыт, решение отвечать не должно. Первое
      // нажатие перезапустило отсчёт (not_visible), поэтому ждём заново.
      await afterSettling(tester);
      cubit.answerApprovalByShortcut(
        CodeLabApprovalOptionKind.allowOnce,
        isVisible: (_, _) => true,
        modifiersHeldFor: null,
      );
      await settle(tester);
      expect(answers(), isEmpty, reason: 'диалог закрывает рабочее место');
      expect(cubit.state.pendingRootSession, isNotNull);
      await tearDownApp(tester);
    }, variant: macOS);

    for (final entry in {'macOS': macOS, 'Linux': linux}.entries) {
      testWidgets('терминал пользователя (${entry.key}): клавиши ответа не '
          'отвечают на одобрение', (tester) async {
        final shells = FakeUserShellLauncher()..shellsExitOnHangUp = true;
        await pumpConnected(tester, shells: shells);
        await sessionWithApproval(tester, 844);
        // Переключатель вызывается обработчиком: в шрифте Ahem подписи шире
        // реальных, и попадание по координате ненадёжно.
        tester
            .widget<ToggleButton>(
              find.byKey(CodeLabAppBar.toggleKey(ToolPane.terminal)),
            )
            .onChanged!(true);
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 50));
        await tester.pump(const Duration(milliseconds: 50));
        await tester.tap(find.byType(TerminalView));
        await tester.pump();
        expect(find.byType(TerminalView), findsOneWidget);
        expect(
          focusInside<CodeLabPromptComposer>(),
          isFalse,
          reason: 'фокус в терминале, не в композере',
        );
        await afterSettling(tester);

        for (final shortcut in const [
          CodeLabShortcut.allowOnce,
          CodeLabShortcut.allowAlways,
          CodeLabShortcut.rejectOnce,
          CodeLabShortcut.rejectAlways,
        ]) {
          await pressAnswerShortcut(tester, shortcut);
          await settle(tester);
        }

        expect(answers(), isEmpty, reason: 'ответа из терминала нет');
        await tearDownApp(tester);
      }, variant: entry.value);
    }

    testWidgets('Сессия detached после переподключения: ⌘Y не отвечает', (
      tester,
    ) async {
      // Первое подключение — старый агент, второе (перезапуск) — новый,
      // который сессию не загружает: она остаётся detached со старым
      // запросом (как в `settings_pending_approval_test.dart`).
      final old = FakeAcpTransport();
      final fresh = FakeAcpTransport();
      var starts = 0;
      agent = old;
      binding = CodeLabTestBinding(
        project: '/workspace',
        transport: FakeAcpTransport(),
        stdioTransportFactory: (_) => starts++ == 0 ? old : fresh,
        clock: () => now,
      );
      await tester.pumpWidget(
        binding.bootstrap(child: const CodeLabApp(startOnLaunch: false)),
      );
      await tester.pump();
      cubit = binding.scope.resolve<CodeLabShellCubit>();
      await tester.runAsync(() => cubit.startWith());
      await tester.pump();
      await sessionWithApproval(tester, 845);
      await tester.runAsync(() => cubit.restartAgent());
      await tester.runAsync(() => cubit.confirmRestart());
      await settle(tester);
      await shortFrames(tester);
      await afterSettling(tester);

      await pressAnswerShortcut(tester, CodeLabShortcut.allowOnce);
      await settle(tester);

      expect(
        old.sentMessages.whereType<JsonRpcResponse>().where(
          (r) => r.id == const JsonRpcId.integer(845),
        ),
        isEmpty,
        reason: 'ответа на запрос старого соединения нет',
      );
      await tearDownApp(tester);
    }, variant: macOS);
  });
}
