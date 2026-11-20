// Сторож 2 для записей app: каждая запись каталога проверена нажатием
// (задача 1.5 change `add-app-keyboard-page`; design.md D3, Risks; spec
// app-settings «Сочетания app и страница «Keyboard» не расходятся», сценарии
// «Каждая строка проверена нажатием» и «Отправка и одобрение на одной
// клавише»; «Страница «Keyboard»: обозначения клавиш», сценарии подсказок).
//
// Записи кита (палитра, Files, композер, одобрение, выдвижная панель) нажимает
// `codelab_shortcut_bindings_test.dart` кита. Здесь — записи, привязки которых
// живут в app или зависят от сборки app:
// - `leave-settings`: Esc на экране настроек во время хода возвращает на
//   рабочее место без `session/cancel`;
// - `close-overlay`: Esc закрывает «Add connection profile», мастер
//   провайдера, подтверждение `bypass` и палитру рабочего места;
// - Cmd/Ctrl+Enter при ожидающем одобрении: с фокусом на одобрении — вариант
//   `allow_once`, с фокусом в композере — сообщение в очереди;
// - подсказки шапки и сайдбара берут клавиши из каталога.
//
// Клавиши берутся из `CodeLabShortcut` (`pressShortcut`). Esc диалогов
// закрывает их без записи: хранилище профилей, секреты и конфиг агента не
// меняются.

import 'dart:async';

import 'package:codelab_acp_protocol/codelab_acp_protocol.dart';
import 'package:codelab_acp_testing/codelab_acp_testing.dart';
import 'package:codelab_desktop/app/codelab_app_widget.dart';
import 'package:codelab_desktop/app/navigation/settings_page.dart';
import 'package:codelab_desktop/core/platform/connection_preferences.dart';
import 'package:codelab_desktop/features/settings/application/add_profile_cubit.dart';
import 'package:codelab_desktop/features/settings/application/agents_modes_cubit.dart';
import 'package:codelab_desktop/features/settings/application/provider_wizard_cubit.dart';
import 'package:codelab_desktop/features/settings/presentation/add_profile_dialog.dart';
import 'package:codelab_desktop/features/settings/presentation/agents_modes_page.dart';
import 'package:codelab_desktop/features/settings/presentation/provider_wizard_dialog.dart';
import 'package:codelab_desktop/features/workbench/application/shell_cubit.dart';
import 'package:codelab_desktop/l10n/app_localizations_en.dart';
import 'package:codelab_client_core/codelab_client_core.dart';
import 'package:codelab_setup/codelab_setup.dart' show ConfigLayer;
import 'package:codelab_ui/codelab_ui.dart';
import 'package:fluent_ui/fluent_ui.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../support/app_strings.dart';
import '../../../support/fake_agents_modes_cubit.dart';
import '../../../support/fake_profile_secrets.dart';
import '../../../support/fake_provider_settings.dart';
import '../../../support/in_memory_profile_store.dart';
import '../../../support/l10n_app.dart';
import '../../../support/press_shortcut.dart';
import '../../../support/start_agent.dart';
import '../../../support/test_app_scope.dart';

Finder _key(String key) => find.byKey(ValueKey(key));

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    final view = TestWidgetsFlutterBinding.ensureInitialized()
        .platformDispatcher
        .views
        .single;
    view.physicalSize = const Size(1440, 1400);
    view.devicePixelRatio = 1.0;
    addTearDown(view.resetPhysicalSize);
    addTearDown(view.resetDevicePixelRatio);
  });

  Future<void> frames(WidgetTester tester, [int n = 8]) async {
    for (var i = 0; i < n; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
  }

  // -------------------------------------------------------------------------
  // Рабочее место с живым агентом: leave-settings, палитра, одобрение.

  group('в дереве CodeLabApp', () {
    late FakeAcpTransport agent;
    late CodeLabShellCubit cubit;
    late CodeLabTestBinding binding;

    /// Кадры вместо `pumpAndSettle`: при ходе индикаторы анимируются
    /// бесконечно.
    Future<void> shortFrames(WidgetTester tester) async {
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
    }

    Future<void> settle(WidgetTester tester) async {
      await tester.runAsync(() => Future<void>.delayed(Duration.zero));
      await tester.pump();
    }

    Future<void> createSession(WidgetTester tester, String id) async {
      agent.drainSentMessages();
      unawaited(cubit.createSession());
      await settle(tester);
      final request = agent.sentMessages
          .whereType<JsonRpcRequest>()
          .singleWhere((r) => r.method == sessionNewMethod);
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
            options: const [
              PermissionOption(
                optionId: PermissionOptionId('allow-once'),
                name: 'Allow once',
                kind: PermissionOptionKind.allowOnce,
              ),
              PermissionOption(
                optionId: PermissionOptionId('reject-once'),
                name: 'Reject',
                kind: PermissionOptionKind.rejectOnce,
              ),
            ],
          ).toJson(),
        ),
      );
    }

    Future<void> pumpConnected(WidgetTester tester) async {
      agent = FakeAcpTransport();
      binding = CodeLabTestBinding(
        project: '/workspace',
        transport: FakeAcpTransport(),
        stdioTransportFactory: (_) => agent,
        settingsPages: const SettingsPages(
          available: {SettingsPage.connection},
        ),
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

    Finder composerField() => find
        .descendant(
          of: find.byType(CodeLabPromptComposer),
          matching: find.byType(EditableText),
        )
        .last;

    /// Переводит фокус клавиатуры внутрь ожидающего одобрения клавишей Tab:
    /// сочетания вариантов действуют, когда фокус внутри полосы решения
    /// (spec agent-workbench-ui).
    ///
    /// Почему явно: полоса не берёт фокус сама (change `fix-approval-focus`,
    /// D1), пользователь попадает в неё Tab-ом, щелчком по кнопке или
    /// сочетанием перехода. Tab нажимается с верхней границей, пока фокус не
    /// окажется внутри полосы.
    Future<void> focusApproval(WidgetTester tester) async {
      bool inApproval() =>
          FocusManager.instance.primaryFocus?.context
              ?.findAncestorWidgetOfExactType<CodeLabApprovalPrompt>() !=
          null;
      for (var i = 0; i < 60 && !inApproval(); i++) {
        await tester.sendKeyEvent(LogicalKeyboardKey.tab);
        await tester.pump();
      }
      expect(inApproval(), isTrue, reason: 'Tab не довёл фокус до одобрения');
    }

    /// Ответы клиента на `session/request_permission` (id — запроса агента).
    List<JsonRpcResponse> permissionAnswers() =>
        agent.sentMessages.whereType<JsonRpcResponse>().toList();

    String? chosenOption(JsonRpcResponse response) =>
        ((response.result! as Map)['outcome'] as Map)['optionId'] as String?;

    testWidgets('leave-settings: Esc на экране настроек во время хода '
        'возвращает на рабочее место без session/cancel', (tester) async {
      await pumpConnected(tester);
      await createSession(tester, 'session-1');
      await startTurn(tester);
      await pressShortcut(tester, CodeLabShortcut.openSettings);
      await shortFrames(tester);
      expect(_key('settings-nav-connection'), findsOneWidget);
      agent.drainSentMessages();

      await pressShortcut(tester, CodeLabShortcut.leaveSettings);
      await shortFrames(tester);

      expect(_key('settings-nav-connection'), findsNothing);
      expect(
        agent.sentMessages.whereType<JsonRpcNotification>().where(
          (m) => m.method == sessionCancelMethod,
        ),
        isEmpty,
        reason: 'Esc настроек не отменяет ход',
      );
      await tearDownApp(tester);
    });

    testWidgets('close-overlay: Esc закрывает палитру рабочего места', (
      tester,
    ) async {
      await pumpConnected(tester);
      await pressShortcut(tester, CodeLabShortcut.commandPalette);
      await shortFrames(tester);
      expect(find.byType(CodeLabCommandPaletteSurface), findsOneWidget);

      await pressShortcut(tester, CodeLabShortcut.closeOverlay);
      await shortFrames(tester);

      expect(find.byType(CodeLabCommandPaletteSurface), findsNothing);
      await tearDownApp(tester);
    });

    for (final useMeta in const [false, true]) {
      final modifier = useMeta ? 'Cmd' : 'Ctrl';

      testWidgets('$modifier+Enter с фокусом на одобрении выбирает '
          'allow_once', (tester) async {
        await pumpConnected(tester);
        await createSession(tester, 'session-1');
        await startTurn(tester);
        ask('session-1', 901);
        await settle(tester);
        await shortFrames(tester);
        expect(find.byType(CodeLabApprovalPrompt), findsOneWidget);
        expect(cubit.state.queuedPrompts, isEmpty);
        await focusApproval(tester);

        await pressShortcut(
          tester,
          CodeLabShortcut.allowOnce,
          useMeta: useMeta,
        );
        await settle(tester);

        final answers = permissionAnswers();
        expect(answers, hasLength(1));
        expect(answers.single.id, const JsonRpcId.integer(901));
        expect(chosenOption(answers.single), 'allow-once');
        expect(cubit.state.queuedPrompts, isEmpty);
        await tearDownApp(tester);
      });

      testWidgets('$modifier+Enter с фокусом в композере ставит сообщение в '
          'очередь, одобрение ждёт', (tester) async {
        await pumpConnected(tester);
        await createSession(tester, 'session-1');
        await startTurn(tester);
        ask('session-1', 902);
        await settle(tester);
        await shortFrames(tester);

        await tester.tap(composerField());
        await tester.enterText(composerField(), 'later');
        await tester.pump();
        await pressShortcut(tester, CodeLabShortcut.send, useMeta: useMeta);
        await settle(tester);

        expect(cubit.state.queuedPrompts, hasLength(1));
        expect(cubit.state.queuedPrompts.single.content, 'later');
        expect(permissionAnswers(), isEmpty, reason: 'одобрение не отвечено');
        expect(find.byType(CodeLabApprovalPrompt), findsOneWidget);
        await tearDownApp(tester);
      });
    }

    // Подсказки шапки и сайдбара строит каталог (D3, D4): `⌘K` и `⌘N` на
    // macOS, `Ctrl+K` и `Ctrl+N` на остальных ОС. Литералы — из спецификации.
    final hintPlatforms = TargetPlatformVariant.only(TargetPlatform.macOS);
    testWidgets('подсказки шапки и сайдбара на macOS: ⌘K и ⌘N из каталога', (
      tester,
    ) async {
      await pumpConnected(tester);
      await frames(tester, 3);

      expect(find.text('⌘K'), findsOneWidget);
      expect(find.text('⌘N'), findsOneWidget);
      expect(
        CodeLabShortcut.commandPalette.combos.single.compactFor(
          defaultTargetPlatform,
        ),
        '⌘K',
      );
      expect(
        CodeLabShortcut.newSession.combos.single.compactFor(
          defaultTargetPlatform,
        ),
        '⌘N',
      );
      await tearDownApp(tester);
    }, variant: hintPlatforms);

    testWidgets(
      'подсказки шапки и сайдбара на Linux: Ctrl+K и Ctrl+N из каталога',
      (tester) async {
        await pumpConnected(tester);
        await frames(tester, 3);

        expect(find.text('Ctrl+K'), findsOneWidget);
        expect(find.text('Ctrl+N'), findsOneWidget);
        expect(
          CodeLabShortcut.commandPalette.combos.single.compactFor(
            defaultTargetPlatform,
          ),
          'Ctrl+K',
        );
        expect(
          CodeLabShortcut.newSession.combos.single.compactFor(
            defaultTargetPlatform,
          ),
          'Ctrl+N',
        );
        await tearDownApp(tester);
      },
      variant: TargetPlatformVariant.only(TargetPlatform.linux),
    );
  });

  // -------------------------------------------------------------------------
  // Диалоги настроек: Esc из записи close-overlay.

  group('диалоги: close-overlay', () {
    testWidgets('Esc закрывает «Add connection profile»', (tester) async {
      final secrets = FakeProfileSecrets();
      final profiles = InMemoryProfileStore();
      final cubit = AddProfileCubit(
        strings: FixedAppStrings(AppLocalizationsEn()),
        store: profiles,
        openSecrets: () async => secrets,
        preferences: const SharedPreferencesConnectionPreferences(),
        kinds: const [ProfileKind.stdio, ProfileKind.webSocket],
        environment: const {},
      );
      addTearDown(cubit.close);
      await cubit.start();
      await tester.pumpWidget(
        localizedFluentApp(
          Builder(
            builder: (context) => Center(
              child: Button(
                key: const ValueKey('open-dialog'),
                onPressed: () => showAddProfileDialog(context, cubit),
                child: const Text('open'),
              ),
            ),
          ),
        ),
      );
      await tester.tap(_key('open-dialog'));
      await tester.pumpAndSettle();
      expect(find.text('Add connection profile'), findsOneWidget);

      await pressShortcut(tester, CodeLabShortcut.closeOverlay);
      await tester.pumpAndSettle();

      expect(find.text('Add connection profile'), findsNothing);
      // Esc — отмена: ни профиль, ни секрет не записаны.
      expect(profiles.profiles, isEmpty);
      expect(secrets.values, isEmpty);
    });

    testWidgets('Esc закрывает мастер провайдера', (tester) async {
      Map<String, Object?> existing() => {
        'agent': {'default_model': 'local/qwen'},
        'providers': {
          'local': providerMap(
            baseUrl: 'http://localhost:11434/v1',
            models: ['qwen'],
          ),
        },
      };
      final store = FakeAgentConfigStore(user: existing());
      final session = FakeProviderSettingsSession(store);
      final flow = (await tester.runAsync(() => session.openWizard()))!;
      final cubit = ProviderWizardCubit(
        strings: FixedAppStrings(AppLocalizationsEn()),
        flow: flow,
        access: session.access,
        backendId: store.backend.id,
        forceDefault: false,
        isAgentConnected: () => true,
      );
      addTearDown(cubit.close);
      late Future<void> dialog;
      await tester.pumpWidget(
        localizedFluentApp(
          Builder(
            builder: (context) => Center(
              child: Button(
                key: const ValueKey('open'),
                onPressed: () =>
                    dialog = showProviderWizardDialog(context, cubit),
                child: const Text('open'),
              ),
            ),
          ),
        ),
      );
      await tester.tap(_key('open'));
      await frames(tester);
      expect(_key('provider-wizard'), findsOneWidget);

      await pressShortcut(tester, CodeLabShortcut.closeOverlay);
      await frames(tester);
      await dialog;

      expect(_key('provider-wizard'), findsNothing);
      // Esc — отмена: конфиг агента не записан и не изменён.
      expect(store.applied, isEmpty);
      expect(store.user, existing());
    });

    testWidgets('Esc закрывает подтверждение bypass', (tester) async {
      final cubit = FakeAgentsModesCubit(
        const AgentsModesReady(
          mode: 'standard',
          effort: 'medium',
          target: ConfigLayer.user,
          canTargetProject: true,
          saving: false,
        ),
      );
      addTearDown(cubit.close);
      // Страница берёт тексты из ARB (`add-desktop-localization`, итерация 5),
      // поэтому `FluentApp` — с делегатами локализации.
      await tester.pumpWidget(
        localizedFluentApp(
          ScaffoldPage(
            content: SingleChildScrollView(
              child: BlocProvider<AgentsModesCubit>.value(
                value: cubit,
                child: const AgentsModesPage(),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(_key('agents-modes-mode-bypass'));
      await tester.pumpAndSettle();
      expect(_key('agents-modes-bypass-confirm'), findsOneWidget);

      await pressShortcut(tester, CodeLabShortcut.closeOverlay);
      await tester.pumpAndSettle();

      expect(_key('agents-modes-bypass-confirm'), findsNothing);
      expect(cubit.calls, ['beginBypass', 'cancelBypass']);
    });
  });
}
