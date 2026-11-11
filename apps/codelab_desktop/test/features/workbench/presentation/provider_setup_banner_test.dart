// Баннер «Встроенный агент без провайдера» (задача 3.12 change
// `add-provider-setup-ui`; agent-workbench-ui «Встроенный агент без
// провайдера», сценарии «Новая установка», «Провайдер добавлен из баннера»,
// «Другой профиль за время мастера», «Прочая ошибка конфига»; design.md D21,
// D26).
//
// Приложение собрано целиком; встроенный агент — открыватель-двойник (первый
// вызов бросает ошибку конфига), признак «нужен провайдер» — шов
// `providerSetupProbe` (настоящую функцию по снимку проверяет
// `provider_setup_probe_test.dart`), сессия настроек — двойник.

import 'dart:async';

import 'package:codelab_acp_testing/codelab_acp_testing.dart';
import 'package:codelab_client_core/codelab_client_core.dart';
import 'package:codelab_desktop/app/codelab_app_widget.dart';
import 'package:codelab_desktop/features/workbench/application/shell_cubit.dart';
import 'package:codelab_embedded/codelab_embedded.dart'
    show EmbeddedAgent, EmbeddedAgentConfigException, McpStatusPort;
import 'package:codelab_setup/codelab_setup.dart'
    show
        CheckOk,
        ConfigIssue,
        ConfigIssueKind,
        ProviderWizardEntry,
        RemoteModel;
import 'package:codelab_ui/codelab_ui.dart';
import 'package:fluent_ui/fluent_ui.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../../support/fake_provider_settings.dart';
import '../../../support/in_memory_profile_store.dart';
import '../../../support/test_app_scope.dart';

const _noProvider = 'No model provider is configured for the embedded agent.';

Finder _key(String key) => find.byKey(ValueKey(key));

final class _Agent implements EmbeddedAgent {
  // Статус MCP в этом тесте не нужен: фейк сессий не открывает.
  @override
  McpStatusPort? mcpStatus(String sessionId) => null;

  final _closed = Completer<void>();

  @override
  bool get secretsInConfig => false;

  @override
  AcpTransport get clientTransport => FakeAcpTransport();

  @override
  Future<void> get closed => _closed.future;

  @override
  Future<void> dispose() async {
    if (!_closed.isCompleted) _closed.complete();
  }
}

void main() {
  late FakeAgentConfigStore store;
  late FakeProviderSettingsSession session;
  Future<void>? openGate;
  late int sessionOpens;
  late int opens;
  late bool probeAnswer;
  late ({String key, String message}) configIssue;
  late CodeLabTestBinding binding;
  late CodeLabShellCubit shell;

  setUp(() {
    final view = TestWidgetsFlutterBinding.ensureInitialized()
        .platformDispatcher
        .views
        .single;
    view.physicalSize = const Size(1440, 1400);
    view.devicePixelRatio = 1.0;
    addTearDown(view.resetPhysicalSize);
    addTearDown(view.resetDevicePixelRatio);
    // Изменяемый слой: двойник дописывает в него сохранённые правки.
    store = FakeAgentConfigStore(user: <String, Object?>{});
    session = FakeProviderSettingsSession(store);
    opens = 0;
    openGate = null;
    sessionOpens = 0;
    probeAnswer = true;
    configIssue = (key: 'agent.default_model', message: 'required');
  });

  Future<void> frames(WidgetTester tester, [int n = 10]) async {
    for (var i = 0; i < n; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
  }

  /// Подключение окна идёт через настоящие асинхронные операции
  /// (`SharedPreferences`, проверка папки): без реальных тиков кадры его не
  /// продвигают.
  Future<void> realTime(WidgetTester tester) async {
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 300)),
    );
    await frames(tester, 10);
  }

  Future<void> start(WidgetTester tester) async {
    binding = CodeLabTestBinding(
      project: '/workspace',
      stdioDefault: false,
      profileStore: InMemoryProfileStore(),
      webSocketTransportFactory: (config) =>
          throw StateError('the other agent is unreachable'),
      embeddedOpener: ({required cwd, required hostProfile}) async {
        opens++;
        if (opens == 1) {
          // Message — как у настоящего исключения: проблемы и подсказка.
          throw EmbeddedAgentConfigException([
            ConfigIssue(
              kind: ConfigIssueKind.value,
              key: configIssue.key,
              source: '/home/u/.codelab/config.yaml',
              message: configIssue.message,
            ),
          ], home: '/home/u/.codelab');
        }
        return _Agent();
      },
      providerSetupProbe: (cwd) async => probeAnswer,
      providerSettingsOpener: (access, env) async {
        sessionOpens++;
        await openGate;
        return session;
      },
    );
    await tester.pumpWidget(binding.bootstrap(child: const CodeLabApp()));
    await tester.pump();
    shell = binding.scope.resolve<CodeLabShellCubit>();
    unawaited(shell.connect());
    await frames(tester);
  }

  Future<void> walkWizard(WidgetTester tester) async {
    await tester.tap(_key('provider-wizard-preset-custom-openai'));
    await frames(tester, 2);
    await tester.tap(_key('provider-wizard-next'));
    await frames(tester);
    await tester.enterText(
      _key('provider-wizard-base-url-field'),
      'https://llm.example/v1',
    );
    await tester.tap(_key('provider-wizard-next'));
    await frames(tester);
    await tester.tap(_key('provider-wizard-key-none'));
    await frames(tester, 2);
    await tester.tap(_key('provider-wizard-next'));
    await frames(tester);
    session.wizardCheck.respond(
      const CheckOk([RemoteModel('m1', contextWindow: 8000)]),
    );
    await frames(tester);
    await tester.tap(_key('provider-wizard-model-m1'));
    await frames(tester);
  }

  testWidgets('a new install: the banner text and "Add provider" replace '
      'the raw problems', (tester) async {
    await start(tester);

    expect(find.text(_noProvider), findsOneWidget);
    expect(_key('connection-banner-add-provider'), findsOneWidget);
    expect(find.textContaining('agent.default_model'), findsNothing);
    expect(find.textContaining('codelab config check'), findsNothing);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('the provider is added from the banner: forced default, the '
      'embedded agent is reconnected, the banner is gone', (tester) async {
    await start(tester);

    await tester.tap(_key('connection-banner-add-provider'));
    await frames(tester);
    expect(_key('provider-wizard'), findsOneWidget);
    expect(session.wizards.single.forceDefault, isTrue);
    expect(session.wizards.single.entry, ProviderWizardEntry.banner);

    await walkWizard(tester);
    await tester.tap(_key('provider-wizard-save'));
    await frames(tester, 20);
    await realTime(tester);

    expect(_key('provider-wizard'), findsNothing);
    expect(store.user['agent'], {'default_model': 'llm-example/m1'});
    expect(opens, 2);
    expect(_key('connection-banner-add-provider'), findsNothing);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('a double click on "Add provider" opens one wizard (the owner '
      'ignores the second click while opening)', (tester) async {
    await start(tester);
    final gate = Completer<void>();
    openGate = gate.future;

    await tester.tap(_key('connection-banner-add-provider'));
    await tester.pump();
    await tester.tap(_key('connection-banner-add-provider'));
    await tester.pump();
    expect(sessionOpens, 1);

    gate.complete();
    await frames(tester);
    expect(session.wizards, hasLength(1));
    expect(_key('provider-wizard'), findsOneWidget);
    await tester.tap(_key('provider-wizard-cancel'));
    await frames(tester);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('with the notice the card has one primary action and no '
      'Reconnect (the row fits the card; width is a manual check)', (
    tester,
  ) async {
    await start(tester);

    expect(find.text('Reconnect'), findsNothing);
    expect(find.text('Connect'), findsOneWidget);
    expect(find.text('Configure connection'), findsOneWidget);
    final primaries = tester
        .widgetList<CodeLabButton>(
          find.descendant(
            of: find.byType(CodeLabConnectionScreen),
            matching: find.byType(CodeLabButton),
          ),
        )
        .where((b) => b.emphasis == CodeLabButtonEmphasis.primary);
    expect(primaries.map((b) => b.label), ['Add provider']);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('Cancel of the wizard leaves the banner', (tester) async {
    await start(tester);

    await tester.tap(_key('connection-banner-add-provider'));
    await frames(tester);
    await tester.tap(_key('provider-wizard-cancel'));
    await frames(tester);

    expect(_key('provider-wizard'), findsNothing);
    expect(find.text(_noProvider), findsOneWidget);
    expect(opens, 1);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('another attempt during the wizard: the config is written but '
      'the embedded agent is not reconnected', (tester) async {
    await start(tester);
    await tester.tap(_key('connection-banner-add-provider'));
    await frames(tester);
    await walkWizard(tester);

    // Диалог модальный, поэтому попытку начинает тест программно.
    unawaited(
      shell.connect(
        ConnectionProfile.webSocket(
          id: 'other',
          label: 'Other',
          uri: Uri.parse('ws://other.example:1/acp'),
        ),
      ),
    );
    await frames(tester, 3);
    await tester.tap(_key('provider-wizard-save'));
    await frames(tester, 20);
    await realTime(tester);

    expect(store.user['agent'], {'default_model': 'llm-example/m1'});
    expect(opens, 1);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  for (final issue in const [
    (key: 'budget.max_steps', message: 'must be positive'),
    (
      key: 'agent.default_model',
      message: 'gw/typo is not in the model catalog',
    ),
  ]) {
    testWidgets('another config error (${issue.key}) keeps the old text and '
        'has no "Add provider"', (tester) async {
      probeAnswer = false;
      configIssue = issue;
      await start(tester);

      expect(find.textContaining(issue.message), findsOneWidget);
      expect(find.textContaining('codelab config check'), findsOneWidget);
      expect(find.text(_noProvider), findsNothing);
      expect(_key('connection-banner-add-provider'), findsNothing);
      await tester.pumpWidget(const SizedBox.shrink());
    });
  }
}
