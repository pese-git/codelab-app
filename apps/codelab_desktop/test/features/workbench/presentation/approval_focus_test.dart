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
import 'package:codelab_desktop/app/codelab_app_widget.dart';
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
  }) async {
    agent = FakeAcpTransport();
    final binding = CodeLabTestBinding(
      project: '/workspace',
      transport: FakeAcpTransport(),
      stdioTransportFactory: (_) => agent,
      projectFiles: projectFiles,
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

  void ask(String sessionId, int id) {
    agent.emitInbound(
      JsonRpcMessage.request(
        id: JsonRpcId.integer(id),
        method: sessionRequestPermissionMethod,
        params: RequestPermissionRequest(
          sessionId: SessionId(sessionId),
          toolCall: ToolCallUpdate(
            toolCallId: ToolCallId('call-$id'),
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

  /// Tab, пока фокус не окажется внутри [finder] (с верхней границей).
  Future<void> tabTo(WidgetTester tester, Finder finder) async {
    final target = finder.evaluate().first;
    bool inside() {
      final context = FocusManager.instance.primaryFocus?.context;
      if (context == null) return false;
      if (identical(context, target)) return true;
      var found = false;
      context.visitAncestorElements((element) {
        if (identical(element, target)) found = true;
        return !found;
      });
      return found;
    }

    for (var i = 0; i < 60 && !inside(); i++) {
      await tester.sendKeyEvent(LogicalKeyboardKey.tab);
      await tester.pump();
    }
    expect(inside(), isTrue, reason: 'Tab не довёл фокус до $finder');
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
}
