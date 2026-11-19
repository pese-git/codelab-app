// Одобрение не берёт клавиатурный фокус само (change `fix-approval-focus`,
// задача 1.3; design.md D1, D2, D6, Risks; spec agent-workbench-ui
// «Одобрение получает клавиатурный фокус только по действию пользователя» и
// MODIFIED «Approval card inside the tool call row», сценарий «Shortcut
// without keyboard focus in the bar»).
//
// Почему: `Focus(autofocus: true)` полосы решения ловил фокус, когда у
// рабочего места его не было (клик по пустой ленте, закрытая палитра), и
// тогда Cmd/Ctrl+Enter отвечал `allow_once` на запрос разрешения без явного
// действия пользователя (AGENTS.md §10).
//
// Для чего: сквозная проверка в дереве `CodeLabApp` с фейковым транспортом;
// ответ на `session/request_permission` наблюдается на проводе
// (`JsonRpcResponse` в `sentMessages`), а не по состоянию виджетов.
//
// Как читать: сценарии «без фокуса — не отвечает» красные, пока в ките есть
// `autofocus` (задача 1.2); сценарии с фокусом в композере, дереве Files или
// сайдбаре держат фокус рабочего места и зелёные и до правки — они
// закрепляют границу, а не дефект.

import 'dart:async';

import 'package:codelab_acp_protocol/codelab_acp_protocol.dart';
import 'package:codelab_acp_testing/codelab_acp_testing.dart';
import 'package:codelab_client_acp/codelab_client_acp.dart'
    show ApprovalRequestId;
import 'package:codelab_desktop/app/codelab_app_widget.dart';
import 'package:codelab_desktop/app/navigation/settings_page.dart';
import 'package:codelab_desktop/features/workbench/application/shell_cubit.dart';
import 'package:codelab_ui/codelab_ui.dart';
import 'package:fluent_ui/fluent_ui.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../../support/fake_project_files.dart';
import '../../../support/press_shortcut.dart';
import '../../../support/start_agent.dart';
import '../../../support/test_app_scope.dart';

void main() {
  late FakeAcpTransport agent;
  late CodeLabShellCubit cubit;

  // Четыре стандартных варианта: сочетания всех видов должны не отвечать.
  const fourOptions = [
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

  setUp(() {
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

  Future<void> pumpConnected(
    WidgetTester tester, {
    FakeProjectFiles? projectFiles,
    SettingsPages? settingsPages,
  }) async {
    agent = FakeAcpTransport();
    final binding = CodeLabTestBinding(
      project: '/workspace',
      transport: FakeAcpTransport(),
      stdioTransportFactory: (_) => agent,
      projectFiles: projectFiles,
      settingsPages: settingsPages,
    );
    await tester.pumpWidget(
      binding.bootstrap(child: const CodeLabApp(startOnLaunch: false)),
    );
    await tester.pump();
    cubit = binding.scope.resolve<CodeLabShellCubit>();
    await tester.runAsync(() => cubit.startWith());
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

  void ask(String sessionId, int id, {String? toolCallId}) {
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
          options: fourOptions,
        ).toJson(),
      ),
    );
  }

  /// Ответы клиента на `session/request_permission`.
  List<JsonRpcResponse> answers() =>
      agent.sentMessages.whereType<JsonRpcResponse>().toList();

  String? chosenOption(JsonRpcResponse response) =>
      ((response.result! as Map)['outcome'] as Map)['optionId'] as String?;

  /// Фокус Flutter сейчас внутри виджета типа [T].
  bool focusInside<T extends Widget>() =>
      FocusManager.instance.primaryFocus?.context
          ?.findAncestorWidgetOfExactType<T>() !=
      null;

  /// Фокус внутри полосы одобрения (она сама или её элемент).
  bool focusInApproval() => focusInside<CodeLabApprovalPrompt>();

  /// Состояние «фокуса нет ни у одного элемента рабочего места»: пользователь
  /// кликнул по пустому месту ленты или закрыл палитру.
  Future<void> dropFocus(WidgetTester tester) async {
    FocusManager.instance.primaryFocus?.unfocus();
    await tester.pump();
    expect(focusInside<CodeLabPromptComposer>(), isFalse);
    expect(focusInApproval(), isFalse);
  }

  /// Фокус Flutter сейчас на элементе внутри [finder] (или на нём самом).
  bool focusIn(Finder finder) {
    final target = finder.evaluate().firstOrNull;
    final context = FocusManager.instance.primaryFocus?.context;
    if (target == null || context == null) return false;
    if (identical(context, target)) return true;
    var found = false;
    context.visitAncestorElements((element) {
      if (identical(element, target)) found = true;
      return !found;
    });
    return found;
  }

  /// Tab, пока фокус не окажется внутри [finder] (с верхней границей).
  Future<void> tabTo(WidgetTester tester, Finder finder) async {
    for (var i = 0; i < 60 && !focusIn(finder); i++) {
      await tester.sendKeyEvent(LogicalKeyboardKey.tab);
      await tester.pump();
    }
    expect(focusIn(finder), isTrue, reason: 'Tab не довёл фокус до $finder');
  }

  /// Четыре сочетания одобрения из каталога в обоих вариантах модификатора.
  const approvalShortcuts = [
    CodeLabShortcut.allowOnce,
    CodeLabShortcut.allowAlways,
    CodeLabShortcut.rejectOnce,
    CodeLabShortcut.rejectAlways,
  ];

  group('одобрение не берёт фокус само', () {
    testWidgets('одобрение появилось без фокуса: Ctrl+Enter и Cmd+Enter не '
        'отвечают', (tester) async {
      await pumpConnected(tester);
      await createSession(tester, 'session-1');
      await startTurn(tester);
      await dropFocus(tester);

      ask('session-1', 801);
      await settle(tester);
      await shortFrames(tester);
      expect(find.byType(CodeLabApprovalPrompt), findsOneWidget);

      for (final useMeta in const [false, true]) {
        await pressShortcut(
          tester,
          CodeLabShortcut.allowOnce,
          useMeta: useMeta,
        );
        await settle(tester);
      }

      expect(answers(), isEmpty, reason: 'ответ без явного действия');
      expect(find.byType(CodeLabApprovalPrompt), findsOneWidget);
      // Появление одобрения не переносит фокус в полосу.
      expect(focusInApproval(), isFalse);
      await tearDownApp(tester);
    });

    testWidgets('одобрение появилось без фокуса: остальные сочетания '
        'одобрения не отвечают', (tester) async {
      await pumpConnected(tester);
      await createSession(tester, 'session-1');
      await startTurn(tester);
      await dropFocus(tester);

      ask('session-1', 802);
      await settle(tester);
      await shortFrames(tester);

      for (final shortcut in approvalShortcuts.skip(1)) {
        for (final useMeta in const [false, true]) {
          await pressShortcut(tester, shortcut, useMeta: useMeta);
          await settle(tester);
        }
      }

      expect(answers(), isEmpty, reason: 'ни один вариант не выбран');
      expect(find.byType(CodeLabApprovalPrompt), findsOneWidget);
      await tearDownApp(tester);
    });

    testWidgets('одобрение появилось после закрытия палитры', (tester) async {
      await pumpConnected(tester);
      await createSession(tester, 'session-1');
      await startTurn(tester);
      await pressShortcut(tester, CodeLabShortcut.commandPalette);
      await shortFrames(tester);
      expect(find.byType(CodeLabCommandPaletteSurface), findsOneWidget);
      await pressShortcut(tester, CodeLabShortcut.closeOverlay);
      await shortFrames(tester);
      expect(find.byType(CodeLabCommandPaletteSurface), findsNothing);

      ask('session-1', 803);
      await settle(tester);
      await shortFrames(tester);
      expect(find.byType(CodeLabApprovalPrompt), findsOneWidget);

      await pressShortcut(tester, CodeLabShortcut.allowOnce);
      await settle(tester);

      expect(answers(), isEmpty, reason: 'после палитры ответа нет');
      expect(find.byType(CodeLabApprovalPrompt), findsOneWidget);
      await tearDownApp(tester);
    });

    // MODIFIED «Approval card inside the tool call row»: сочетание варианта
    // `allow_always` без клавиатурного фокуса в полосе ничего не отправляет.
    testWidgets('Shortcut without keyboard focus in the bar: allow_always '
        'sends no answer', (tester) async {
      await pumpConnected(tester);
      await createSession(tester, 'session-1');
      await startTurn(tester);
      await dropFocus(tester);
      ask('session-1', 804);
      await settle(tester);
      await shortFrames(tester);

      for (final useMeta in const [false, true]) {
        await pressShortcut(
          tester,
          CodeLabShortcut.allowAlways,
          useMeta: useMeta,
        );
        await settle(tester);
      }

      expect(answers(), isEmpty);
      expect(find.byType(CodeLabApprovalPrompt), findsOneWidget);
      await tearDownApp(tester);
    });

    // Фокус рабочего места держит композер: `autofocus` полосы не срабатывает,
    // сценарий зелёный и до правки (закрепляет границу).
    testWidgets('фокус в композере не уходит к одобрению: сообщение в '
        'очереди, одобрение ждёт', (tester) async {
      await pumpConnected(tester);
      await createSession(tester, 'session-1');
      await startTurn(tester);
      final field = find
          .descendant(
            of: find.byType(CodeLabPromptComposer),
            matching: find.byType(EditableText),
          )
          .last;
      await tester.tap(field);
      await tester.enterText(field, 'run tests');
      await tester.pump();

      ask('session-1', 805);
      await settle(tester);
      await shortFrames(tester);
      expect(focusInside<CodeLabPromptComposer>(), isTrue);
      expect(focusInApproval(), isFalse);

      await pressShortcut(tester, CodeLabShortcut.send);
      await settle(tester);

      expect(focusInside<CodeLabPromptComposer>(), isTrue);
      expect(cubit.state.queuedPrompts, hasLength(1));
      expect(cubit.state.queuedPrompts.single.content, 'run tests');
      expect(answers(), isEmpty);
      expect(find.byType(CodeLabApprovalPrompt), findsOneWidget);
      await tearDownApp(tester);
    });

    // Фокус на узле дерева Files держит его: зелёный и до правки.
    testWidgets('фокус в дереве Files: Ctrl/Cmd+Enter и Backspace не отвечают '
        'и не ставят сообщение в очередь', (tester) async {
      await pumpConnected(
        tester,
        projectFiles: FakeProjectFiles(
          listings: {
            '/workspace': {
              '': listingOf('', [dirEntry('lib'), fileEntry('README.md')]),
            },
          },
        ),
      );
      await createSession(tester, 'session-1');
      await startTurn(tester);
      cubit.openPane(ToolPane.files);
      await settle(tester);
      await shortFrames(tester);
      ask('session-1', 806);
      await settle(tester);
      await shortFrames(tester);

      await tester.tap(find.byKey(const ValueKey('file-tree-row-lib')));
      await shortFrames(tester);
      expect(focusInside<CodeLabFileTree>(), isTrue);

      for (final shortcut in [
        CodeLabShortcut.allowOnce,
        CodeLabShortcut.rejectOnce,
      ]) {
        for (final useMeta in const [false, true]) {
          await pressShortcut(tester, shortcut, useMeta: useMeta);
          await settle(tester);
        }
      }

      expect(answers(), isEmpty);
      expect(cubit.state.queuedPrompts, isEmpty);
      await tearDownApp(tester);
    });

    // Фокус на строке сайдбара держит её: зелёный и до правки.
    testWidgets('фокус на строке сайдбара: Ctrl/Cmd+Enter и Backspace не '
        'отвечают и не ставят сообщение в очередь', (tester) async {
      await pumpConnected(tester);
      await createSession(tester, 'session-1');
      await startTurn(tester);
      ask('session-1', 807);
      await settle(tester);
      await shortFrames(tester);

      // Щелчок по строке сайдбара фокус не ставит (строка выбирается, но
      // `HoverButton` узел не просит): тест ставит фокус на узел строки сам,
      // как это сделал бы Tab пользователя.
      final row = find
          .byKey(CodeLabSessionSidebar.sessionKey('session-1'))
          .evaluate()
          .single;
      FocusManager.instance.rootScope.descendants.firstWhere((node) {
        var inside = false;
        node.context?.visitAncestorElements((element) {
          if (identical(element, row)) inside = true;
          return !inside;
        });
        return inside && node.canRequestFocus;
      }).requestFocus();
      await shortFrames(tester);
      expect(focusInside<CodeLabSessionSidebar>(), isTrue);

      for (final shortcut in [
        CodeLabShortcut.allowOnce,
        CodeLabShortcut.rejectOnce,
      ]) {
        for (final useMeta in const [false, true]) {
          await pressShortcut(tester, shortcut, useMeta: useMeta);
          await settle(tester);
        }
      }

      expect(answers(), isEmpty);
      expect(cubit.state.queuedPrompts, isEmpty);
      await tearDownApp(tester);
    });

    testWidgets('Tab до кнопки не самого раннего одобрения: сочетание не '
        'отвечает, Enter на кнопке отвечает на него', (tester) async {
      await pumpConnected(tester);
      await createSession(tester, 'session-1');
      await startTurn(tester);
      ask('session-1', 811);
      await settle(tester);
      ask('session-1', 812);
      await settle(tester);
      await shortFrames(tester);
      expect(find.byType(CodeLabApprovalPrompt), findsNWidgets(2));
      // Вторая полоса в ленте — позднее одобрение `B`.
      final allowOfB = find.byKey(CodeLabApprovalPrompt.allowKey).last;

      await tabTo(tester, allowOfB);
      for (final useMeta in const [false, true]) {
        await pressShortcut(
          tester,
          CodeLabShortcut.allowOnce,
          useMeta: useMeta,
        );
        await settle(tester);
      }
      expect(answers(), isEmpty, reason: 'ни `A`, ни `B` не отвечены');

      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pump(const Duration(milliseconds: 300));
      await settle(tester);

      final given = answers();
      expect(given, hasLength(1));
      expect(given.single.id, const JsonRpcId.integer(812));
      expect(chosenOption(given.single), 'allow-once');
      await tearDownApp(tester);
    });

    testWidgets('после Tab до «Allow» активного одобрения Ctrl+Enter '
        'выбирает allow_once', (tester) async {
      await pumpConnected(tester);
      await createSession(tester, 'session-1');
      await startTurn(tester);
      ask('session-1', 821);
      await settle(tester);
      await shortFrames(tester);

      await tabTo(tester, find.byKey(CodeLabApprovalPrompt.allowKey));
      await pressShortcut(tester, CodeLabShortcut.allowOnce);
      await settle(tester);

      final given = answers();
      expect(given, hasLength(1));
      expect(given.single.id, const JsonRpcId.integer(821));
      expect(chosenOption(given.single), 'allow-once');
      await tearDownApp(tester);
    });
  });

  // -------------------------------------------------------------------------
  // Переход «Go to approval» (задача 2.3 change `fix-approval-focus`;
  // design.md D3, D4, Risks; spec agent-workbench-ui «Переход к ожидающему
  // одобрению с клавиатуры»).
  //
  // Сочетание нажимается литералами Cmd/Ctrl+Shift+A (как в спецификации), а
  // не записью каталога: до задачи 2.2 у записи нет комбинаций, и каждый
  // сценарий падал бы на пустом каталоге, а не на отсутствии поведения.
  // Каталог проверяют `codelab_shortcuts_test.dart` и сторож 2 кита.
  group('переход к одобрению Cmd/Ctrl+Shift+A', () {
    Future<void> pressGoTo(WidgetTester tester, {bool meta = false}) async {
      final primary = meta
          ? LogicalKeyboardKey.metaLeft
          : LogicalKeyboardKey.controlLeft;
      await tester.sendKeyDownEvent(primary);
      await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
      await tester.sendKeyEvent(LogicalKeyboardKey.keyA);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
      await tester.sendKeyUpEvent(primary);
      await tester.pump(const Duration(milliseconds: 100));
      await settle(tester);
      await shortFrames(tester);
    }

    final composerField = find
        .descendant(
          of: find.byType(CodeLabPromptComposer),
          matching: find.byType(EditableText),
        )
        .last;
    final prompts = find.byType(CodeLabApprovalPrompt);
    final frame = find.byKey(CodeLabApprovalPrompt.focusFrameKey);

    /// Сессия с идущим ходом и фокусом в поле композера.
    Future<void> turnWithComposerFocus(WidgetTester tester) async {
      await createSession(tester, 'session-1');
      await startTurn(tester);
      await tester.tap(composerField);
      await tester.pump();
      expect(focusInside<CodeLabPromptComposer>(), isTrue);
    }

    /// Кадры `session/update` активной сессии.
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

    for (final meta in const [false, true]) {
      final modifier = meta ? 'Cmd' : 'Ctrl';

      testWidgets('$modifier: с клавиатуры доходит до одобрения и отвечает', (
        tester,
      ) async {
        await pumpConnected(tester);
        await turnWithComposerFocus(tester);
        ask('session-1', 901);
        await settle(tester);
        await shortFrames(tester);

        await pressGoTo(tester, meta: meta);

        expect(focusInApproval(), isTrue, reason: 'фокус на полосе');
        expect(frame, findsOneWidget, reason: 'рамка фокуса');
        expect(answers(), isEmpty, reason: 'переход не отвечает');

        await pressShortcut(tester, CodeLabShortcut.allowOnce, useMeta: meta);
        await settle(tester);

        final given = answers();
        expect(given, hasLength(1));
        expect(given.single.id, const JsonRpcId.integer(901));
        expect(chosenOption(given.single), 'allow-once');
        await tearDownApp(tester);
      });
    }

    testWidgets('переход и остальные сочетания: Alt+Backspace — '
        'reject_always', (tester) async {
      await pumpConnected(tester);
      await turnWithComposerFocus(tester);
      ask('session-1', 902);
      await settle(tester);
      await shortFrames(tester);

      await pressGoTo(tester);
      await pressShortcut(tester, CodeLabShortcut.rejectAlways);
      await settle(tester);

      final given = answers();
      expect(given, hasLength(1));
      expect(chosenOption(given.single), 'reject-always');
      await tearDownApp(tester);
    });

    testWidgets('Enter и Space на полосе ничего не выбирают', (tester) async {
      await pumpConnected(tester);
      await turnWithComposerFocus(tester);
      ask('session-1', 903);
      await settle(tester);
      await shortFrames(tester);
      await pressGoTo(tester);
      expect(focusInApproval(), isTrue);

      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.sendKeyEvent(LogicalKeyboardKey.space);
      await tester.pump(const Duration(milliseconds: 300));
      await settle(tester);

      expect(answers(), isEmpty);
      expect(prompts, findsOneWidget);
      expect(focusInApproval(), isTrue, reason: 'полоса осталась в фокусе');
      await tearDownApp(tester);
    });

    testWidgets('с клавиатуры через Tab: Reject и Enter — reject_once', (
      tester,
    ) async {
      await pumpConnected(tester);
      await turnWithComposerFocus(tester);
      ask('session-1', 904);
      await settle(tester);
      await shortFrames(tester);
      await pressGoTo(tester);
      expect(focusInApproval(), isTrue);

      await tabTo(tester, find.byKey(CodeLabApprovalPrompt.rejectKey));
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pump(const Duration(milliseconds: 300));
      await settle(tester);

      final given = answers();
      expect(given, hasLength(1));
      expect(chosenOption(given.single), 'reject-once');
      await tearDownApp(tester);
    });

    testWidgets('несколько одобрений — переход к самому раннему', (
      tester,
    ) async {
      await pumpConnected(tester);
      await turnWithComposerFocus(tester);
      ask('session-1', 911);
      await settle(tester);
      ask('session-1', 912);
      await settle(tester);
      await shortFrames(tester);
      expect(prompts, findsNWidgets(2));

      await pressGoTo(tester);
      expect(
        focusIn(prompts.first),
        isTrue,
        reason: 'фокус в полосе самого раннего одобрения',
      );
      expect(focusIn(prompts.last), isFalse);

      await pressShortcut(tester, CodeLabShortcut.allowOnce);
      await settle(tester);

      final given = answers();
      expect(given, hasLength(1));
      expect(given.single.id, const JsonRpcId.integer(911));
      expect(chosenOption(given.single), 'allow-once');
      expect(prompts, findsOneWidget, reason: 'позднее одобрение ждёт');
      expect(focusIn(prompts), isFalse, reason: 'и фокус не получило');
      await tearDownApp(tester);
    });

    testWidgets('одобрение субагента: блок под свёрнутой строкой agent '
        'получает фокус', (tester) async {
      await pumpConnected(tester);
      await turnWithComposerFocus(tester);
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
      await frames(tester, [
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
        // Строки после вопроса уводят блок из видимой части ленты.
        for (var i = 0; i < 60; i++)
          {
            'sessionUpdate': 'tool_call',
            'toolCallId': 'filler$i',
            'title': 'Read filler$i',
            'kind': 'read',
            'status': 'completed',
            'rawInput': {'path': '/workspace/filler$i.dart'},
          },
      ]);
      agent.emitInbound(
        JsonRpcMessage.request(
          id: const JsonRpcId.integer(921),
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
            options: fourOptions,
          ).toJson(),
        ),
      );
      await settle(tester);
      await shortFrames(tester);
      // Лента ленивая: блок уведён за край и не построен, пока к нему не
      // перешли (поэтому `prompts` до перехода пуст).

      await pressGoTo(tester);

      expect(prompts, findsOneWidget, reason: 'лента дошла до блока');
      expect(focusInApproval(), isTrue);
      final panel = tester.getRect(find.byType(CodeLabTranscriptPanel));
      final bar = tester.getRect(prompts);
      expect(
        panel.overlaps(bar),
        isTrue,
        reason: 'лента прокручена: полоса в видимой части',
      );
      expect(
        cubit.state.transcriptExpansion.values,
        everyElement(isNot(isTrue)),
        reason: 'строка agent корня не раскрыта',
      );
      await tearDownApp(tester);
    });

    testWidgets('ожидающего одобрения нет: фокус и сессия прежние', (
      tester,
    ) async {
      await pumpConnected(tester);
      await turnWithComposerFocus(tester);

      await pressGoTo(tester);

      expect(focusInside<CodeLabPromptComposer>(), isTrue);
      expect(answers(), isEmpty);
      await tearDownApp(tester);
    });

    testWidgets('у активной сессии одобрения нет, а у фоновой есть: переход '
        'ничего не делает', (tester) async {
      await pumpConnected(tester);
      await createSession(tester, 'session-1');
      await startTurn(tester);
      ask('session-1', 925);
      await settle(tester);
      // Вторая сессия становится активной; одобрение остаётся у первой.
      await createSession(tester, 'session-2');
      await shortFrames(tester);
      expect(prompts, findsNothing, reason: 'в активной сессии одобрения нет');
      await tester.tap(composerField);
      await tester.pump();
      expect(focusInside<CodeLabPromptComposer>(), isTrue);

      await pressGoTo(tester);

      expect(focusInside<CodeLabPromptComposer>(), isTrue);
      expect(prompts, findsNothing);
      expect(answers(), isEmpty);
      await tearDownApp(tester);
    });

    testWidgets('цель ушла до фокуса: другое одобрение фокус не получает', (
      tester,
    ) async {
      await pumpConnected(tester);
      await turnWithComposerFocus(tester);
      ask('session-1', 931);
      await settle(tester);
      await shortFrames(tester);

      // Нажатие и ответ на цель до того, как лента довела фокус; потом
      // приходит другое одобрение.
      await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
      await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
      await tester.sendKeyEvent(LogicalKeyboardKey.keyA);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
      await tester.runAsync(
        () => cubit.respondToApproval(
          approvalId: const ApprovalRequestId('permission-931'),
          sessionId: const SessionId('session-1'),
          optionId: 'reject-once',
        ),
      );
      ask('session-1', 932);
      await settle(tester);
      await shortFrames(tester);
      await shortFrames(tester);

      expect(prompts, findsOneWidget);
      expect(
        focusIn(prompts),
        isFalse,
        reason: 'позднее одобрение фокус не получило',
      );
      await tearDownApp(tester);
    });

    testWidgets('из настроек сочетание не действует', (tester) async {
      await pumpConnected(
        tester,
        settingsPages: const SettingsPages(
          available: {SettingsPage.connection},
        ),
      );
      await createSession(tester, 'session-1');
      await startTurn(tester);
      ask('session-1', 941);
      await settle(tester);
      await pressShortcut(tester, CodeLabShortcut.openSettings);
      await shortFrames(tester);
      final nav = find.byKey(const ValueKey('settings-nav-connection'));
      expect(nav, findsOneWidget);

      await pressGoTo(tester);

      expect(nav, findsOneWidget);
      expect(
        find.byKey(const ValueKey('settings-pending-approval')),
        findsOneWidget,
      );
      expect(focusInApproval(), isFalse);
      expect(answers(), isEmpty);
      await tearDownApp(tester);
    });

    testWidgets('палитра команд открыта: полоса фокус не получает', (
      tester,
    ) async {
      await pumpConnected(tester);
      await createSession(tester, 'session-1');
      await startTurn(tester);
      ask('session-1', 951);
      await settle(tester);
      await shortFrames(tester);
      await pressShortcut(tester, CodeLabShortcut.commandPalette);
      await shortFrames(tester);
      expect(find.byType(CodeLabCommandPaletteSurface), findsOneWidget);

      await pressGoTo(tester);

      expect(find.byType(CodeLabCommandPaletteSurface), findsOneWidget);
      expect(
        focusIn(find.byKey(CodeLabCommandPaletteSurface.queryFieldKey)),
        isTrue,
        reason: 'фокус в поле поиска палитры',
      );
      expect(focusInApproval(), isFalse);
      await tearDownApp(tester);
    });

    testWidgets('macOS: подсказка ⇧⌘A, после перехода её нет', (tester) async {
      await pumpConnected(tester);
      await turnWithComposerFocus(tester);
      ask('session-1', 961);
      await settle(tester);
      await shortFrames(tester);
      const hint = 'Press ⇧⌘A to answer from the keyboard';
      expect(find.text(hint), findsOneWidget);

      await pressGoTo(tester, meta: true);

      expect(find.text(hint), findsNothing);
      await tearDownApp(tester);
    }, variant: TargetPlatformVariant.only(TargetPlatform.macOS));

    testWidgets('Linux: подсказка Ctrl+Shift+A, после перехода её нет', (
      tester,
    ) async {
      await pumpConnected(tester);
      await turnWithComposerFocus(tester);
      ask('session-1', 962);
      await settle(tester);
      await shortFrames(tester);
      const hint = 'Press Ctrl+Shift+A to answer from the keyboard';
      expect(find.text(hint), findsOneWidget);

      await pressGoTo(tester);

      expect(find.text(hint), findsNothing);
      await tearDownApp(tester);
    }, variant: TargetPlatformVariant.only(TargetPlatform.linux));

    testWidgets('чтение с экрана на macOS: Awaiting approval и сочетания '
        'словами', (tester) async {
      final handle = tester.ensureSemantics();
      await pumpConnected(tester);
      await turnWithComposerFocus(tester);
      ask('session-1', 971);
      await settle(tester);
      await shortFrames(tester);

      await pressGoTo(tester, meta: true);

      final data = tester
          .getSemantics(find.bySemanticsLabel('Awaiting approval'))
          .getSemanticsData();
      expect(data.hint, contains('Allow once: Cmd+Enter'));
      expect(data.hint, contains('Reject: Cmd+Backspace'));
      expect(data.hint, isNot(contains('⌘')));
      handle.dispose();
      await tearDownApp(tester);
    }, variant: TargetPlatformVariant.only(TargetPlatform.macOS));

    // Риск design.md «Активное одобрение сменилось при фокусе в полосе»:
    // фокус на полосе `B` поставил пользователь, и когда `A` решена другим
    // путём, сочетания на `B` начинают действовать, а фокус не переходит.
    testWidgets('A решена, пока фокус на кнопке B: сочетания на B '
        'действуют, фокус остаётся', (tester) async {
      await pumpConnected(tester);
      await turnWithComposerFocus(tester);
      ask('session-1', 981);
      await settle(tester);
      ask('session-1', 982);
      await settle(tester);
      await shortFrames(tester);
      final allowOfB = find.byKey(CodeLabApprovalPrompt.allowKey).last;
      await tabTo(tester, allowOfB);

      await pressShortcut(tester, CodeLabShortcut.allowOnce);
      await settle(tester);
      expect(answers(), isEmpty, reason: 'B пока не активна');

      await tester.runAsync(
        () => cubit.respondToApproval(
          approvalId: const ApprovalRequestId('permission-981'),
          sessionId: const SessionId('session-1'),
          optionId: 'reject-once',
        ),
      );
      await settle(tester);
      await shortFrames(tester);
      expect(
        focusIn(prompts),
        isTrue,
        reason: 'фокус остался в полосе B, никуда не перешёл',
      );

      await pressShortcut(tester, CodeLabShortcut.allowOnce);
      await settle(tester);

      final given = answers();
      expect(given, hasLength(2));
      expect(given.last.id, const JsonRpcId.integer(982));
      expect(chosenOption(given.last), 'allow-once');
      await tearDownApp(tester);
    });

    // -----------------------------------------------------------------------
    // Фокус после ухода одобрения (задача 3.1 change `fix-approval-focus`;
    // design.md D5; spec «Фокус после ухода одобрения»). Возврат — в поле
    // композера активной сессии; следующее одобрение фокус само не берёт.

    bool focusInComposerField() => focusIn(composerField);

    // Во всех сценариях ниже перед переходом фокус стоит на строке сайдбара,
    // а не в композере: иначе Flutter сам вернул бы фокус узлу, который был до
    // полосы, и тест не отличил бы возврат в композер от этого совпадения.
    // Сочетание перехода при этом работает: фокус внутри рабочего места.
    Future<void> focusSidebarRow(WidgetTester tester) async {
      final row = find
          .byKey(CodeLabSessionSidebar.sessionKey('session-1'))
          .evaluate()
          .single;
      FocusManager.instance.rootScope.descendants.firstWhere((node) {
        var inside = false;
        node.context?.visitAncestorElements((element) {
          if (identical(element, row)) inside = true;
          return !inside;
        });
        return inside && node.canRequestFocus;
      }).requestFocus();
      await tester.pump();
      expect(focusInside<CodeLabSessionSidebar>(), isTrue);
    }

    testWidgets('ответ клавишами возвращает фокус в композер, следующее '
        'одобрение фокус не получает', (tester) async {
      await pumpConnected(tester);
      await createSession(tester, 'session-1');
      await startTurn(tester);
      await focusSidebarRow(tester);
      ask('session-1', 1001);
      await settle(tester);
      ask('session-1', 1002);
      await settle(tester);
      await shortFrames(tester);
      await pressGoTo(tester);
      expect(focusInApproval(), isTrue);

      await pressShortcut(tester, CodeLabShortcut.allowOnce);
      await settle(tester);
      await shortFrames(tester);

      expect(answers(), hasLength(1));
      expect(focusInComposerField(), isTrue, reason: 'фокус в поле композера');
      expect(prompts, findsOneWidget);
      expect(focusIn(prompts), isFalse, reason: 'полоса B фокус не получила');

      // Повторное Cmd/Ctrl+Enter уходит в композер: поле пусто, ничего не
      // отправляется и на B не отвечает.
      await pressShortcut(tester, CodeLabShortcut.allowOnce);
      await settle(tester);
      expect(answers(), hasLength(1));
      expect(cubit.state.queuedPrompts, isEmpty);
      await tearDownApp(tester);
    });

    testWidgets('отмена хода при фокусе в полосе: тег Cancelled и фокус в '
        'композере', (tester) async {
      await pumpConnected(tester);
      await createSession(tester, 'session-1');
      await startTurn(tester);
      final prompt = agent.sentMessages.whereType<JsonRpcRequest>().singleWhere(
        (r) => r.method == sessionPromptMethod,
      );
      ask('session-1', 1011);
      await settle(tester);
      await shortFrames(tester);
      await focusSidebarRow(tester);
      await pressGoTo(tester);
      expect(focusInApproval(), isTrue);

      unawaited(cubit.cancelTurn());
      await settle(tester);
      agent.emitInbound(
        JsonRpcMessage.response(
          id: prompt.id,
          result: const {'stopReason': 'cancelled'},
        ),
      );
      await settle(tester);
      await shortFrames(tester);

      expect(prompts, findsNothing);
      expect(find.textContaining('Cancelled'), findsWidgets);
      expect(focusInComposerField(), isTrue);
      await tearDownApp(tester);
    });

    // ВНИМАНИЕ: красный по причине вне итерации 3 — `_approvalFor` в
    // `transcript_projector.dart` (`codelab_client_core`) отдаёт строке вызова
    // первое одобрение вызова, то есть уже решённое, и новый запрос того же
    // вызова в строке не показывается (design.md D11: ядро не меняется).
    testWidgets('новый запрос того же вызова: полоса без фокуса, фокус в '
        'композере', (tester) async {
      await pumpConnected(tester);
      await createSession(tester, 'session-1');
      await startTurn(tester);
      await focusSidebarRow(tester);
      ask('session-1', 1021, toolCallId: 'call-same');
      await settle(tester);
      await shortFrames(tester);
      await pressGoTo(tester);
      expect(focusInApproval(), isTrue);

      await pressShortcut(tester, CodeLabShortcut.allowOnce);
      await settle(tester);
      ask('session-1', 1022, toolCallId: 'call-same');
      await settle(tester);
      await shortFrames(tester);

      expect(prompts, findsOneWidget, reason: 'новая полоса в той же строке');
      expect(focusIn(prompts), isFalse);
      expect(focusInComposerField(), isTrue);
      await tearDownApp(tester);
    });

    testWidgets('переключение сессии при фокусе в полосе: фокус в композере '
        'новой сессии', (tester) async {
      await pumpConnected(tester);
      await createSession(tester, 'session-1');
      await startTurn(tester);
      ask('session-1', 1031);
      await settle(tester);
      await createSession(tester, 'session-2');
      cubit.selectSession('session-1');
      await settle(tester);
      await shortFrames(tester);
      await focusSidebarRow(tester);
      await pressGoTo(tester);
      expect(focusInApproval(), isTrue);

      cubit.selectSession('session-2');
      await settle(tester);
      await shortFrames(tester);

      expect(prompts, findsNothing);
      expect(focusInComposerField(), isTrue);
      await tearDownApp(tester);
    });

    testWidgets('клик в дерево Files в том же кадре, что и ответ: фокус в '
        'дереве, а не в композере', (tester) async {
      await pumpConnected(
        tester,
        projectFiles: FakeProjectFiles(
          listings: {
            '/workspace': {
              '': listingOf('', [dirEntry('lib'), fileEntry('README.md')]),
            },
          },
        ),
      );
      await turnWithComposerFocus(tester);
      cubit.openPane(ToolPane.files);
      await settle(tester);
      await shortFrames(tester);
      ask('session-1', 1041);
      await settle(tester);
      await shortFrames(tester);
      await pressGoTo(tester);
      expect(focusInApproval(), isTrue);

      unawaited(
        cubit.respondToApproval(
          approvalId: const ApprovalRequestId('permission-1041'),
          sessionId: const SessionId('session-1'),
          optionId: 'allow-once',
        ),
      );
      await tester.tap(find.byKey(const ValueKey('file-tree-row-lib')));
      await settle(tester);
      await shortFrames(tester);

      expect(prompts, findsNothing);
      expect(focusInside<CodeLabFileTree>(), isTrue);
      expect(focusInComposerField(), isFalse);
      await tearDownApp(tester);
    });
  });
}
