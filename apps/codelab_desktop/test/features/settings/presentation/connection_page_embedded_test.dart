// Встроенный агент на странице «Connection» (задача 2.4 change
// `add-app-settings-shell`; agent-workbench-ui «Тип подключения «Встроенный
// агент»», сценарии «Выбор встроенного агента» и «Встроенный агент по
// умолчанию»; design.md D5, D6). Заменяет `connection_setup_dialog_embedded_test`.
//
// Проверяется поведение выбора, а не пиксели: «Connect» в строке «Embedded
// agent» подключает встроенного агента, а на новой установке «Connect» экрана
// подключения выбирает встроенного без визита в настройки.

import 'package:codelab_acp_protocol/codelab_acp_protocol.dart';
import 'package:codelab_acp_testing/codelab_acp_testing.dart';
import 'package:codelab_client_core/codelab_client_core.dart';
import 'package:codelab_desktop/app/app_scope.dart';
import 'package:codelab_desktop/app/codelab_app_widget.dart';
import 'package:codelab_desktop/app/navigation/settings_page.dart';
import 'package:codelab_desktop/features/workbench/application/shell_cubit.dart';
import 'package:codelab_embedded/codelab_embedded.dart'
    show EmbeddedAgentConfigException;
import 'package:codelab_ui/codelab_ui.dart';
import 'package:fluent_ui/fluent_ui.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../../support/in_memory_profile_store.dart';
import '../../../support/test_app_scope.dart';

void main() {
  setUp(() {
    final view = TestWidgetsFlutterBinding.ensureInitialized()
        .platformDispatcher
        .views
        .single;
    view.physicalSize = const Size(1440, 900);
    view.devicePixelRatio = 1.0;
    addTearDown(view.resetPhysicalSize);
    addTearDown(view.resetDevicePixelRatio);
  });

  /// Открыватель встроенного агента, который падает конфигурацией: до
  /// транспорта дело не доходит, зато виден профиль и исход подключения.
  var openerCalls = 0;
  Future<Never> failingOpener({
    required String cwd,
    required String hostProfile,
  }) async {
    openerCalls++;
    throw EmbeddedAgentConfigException(const [], home: '/h');
  }

  Future<CodeLabTestBinding> pump(
    WidgetTester tester, {
    InMemoryProfileStore? store,
  }) async {
    openerCalls = 0;
    final binding = CodeLabTestBinding(
      project: '/workspace',
      stdioDefault: false,
      profileStore: store ?? InMemoryProfileStore(),
      embeddedOpener: failingOpener,
      settingsPages: const SettingsPages(available: {SettingsPage.connection}),
    );
    await tester.pumpWidget(
      binding.bootstrap(child: const CodeLabApp(startOnLaunch: false)),
    );
    await tester.pump();
    return binding;
  }

  Future<void> tearDownApp(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox.shrink());
    await closeCodeLabRootScope();
  }

  // Ручного Connect нет (D18): встроенный агент — профиль окна по умолчанию
  // («Selected»), «Restart agent» страницы «Connection» стартует его.
  testWidgets('Restart agent of the Connection page starts the selected '
      'embedded agent', (tester) async {
    final binding = await pump(tester);
    await tester.tap(find.byKey(CodeLabSessionSidebar.settingsKey));
    await tester.pumpAndSettle();

    expect(
      find.byKey(const ValueKey('connection-profile-use-embedded')),
      findsNothing,
    );
    await tester.tap(find.byKey(const ValueKey('connection-restart-agent')));
    await tester.pumpAndSettle();

    final shell = binding.scope.resolve<CodeLabShellCubit>();
    expect(openerCalls, 1);
    expect(shell.state.profileLabel, 'Embedded agent');
    expect(
      shell.state.connectionDetail,
      'codelab_embedded (embedded-app-desktop)',
    );
    await tearDownApp(tester);
  });

  testWidgets('on a new install New session of the start screen starts the '
      'embedded agent', (tester) async {
    final binding = await pump(tester);
    final shell = binding.scope.resolve<CodeLabShellCubit>();
    expect(shell.state.profileLabel, 'Embedded agent');

    await tester.tap(find.byKey(const ValueKey('start-new-session')));
    await tester.pumpAndSettle();

    expect(openerCalls, 1);
    await tearDownApp(tester);
  });

  testWidgets('with a saved default profile New session of the start screen '
      'starts that profile, not the embedded agent', (tester) async {
    final started = <String>[];
    final agent = FakeAcpTransport();
    final binding = CodeLabTestBinding(
      project: '/workspace',
      stdioDefault: false,
      preferences: const {'codelab.connection.default_profile': 'dev'},
      profileStore: InMemoryProfileStore([
        const ConnectionProfile.stdio(
          id: 'dev',
          label: 'Dev',
          command: 'codelab-agent',
          args: ['serve', '--stdio'],
        ),
      ]),
      stdioTransportFactory: (config) {
        started.add(config.command);
        return agent;
      },
    );
    await tester.pumpWidget(
      binding.bootstrap(child: const CodeLabApp(startOnLaunch: false)),
    );
    await tester.pump();
    // Профиль виден в состоянии фасада; стартовый экран его не называет (D18).
    expect(
      binding.scope.resolve<CodeLabShellCubit>().state.profileLabel,
      'Dev',
    );

    await tester.tap(find.byKey(const ValueKey('start-new-session')));
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 50)),
    );
    await tester.pumpAndSettle();

    expect(started, ['codelab-agent']);
    // «New session» после старта шлёт `session/new`; ответ снимает таймер
    // запроса kit, иначе он остался бы после теста.
    final request = agent.sentMessages.whereType<JsonRpcRequest>().firstWhere(
      (r) => r.method == sessionNewMethod,
    );
    agent.emitInbound(
      JsonRpcMessage.response(id: request.id, result: {'sessionId': 's1'}),
    );
    await tester.pump(const Duration(seconds: 3));
    await tearDownApp(tester);
  });

  testWidgets('"Configure connection" on the failure screen opens the '
      'Connection settings page', (tester) async {
    await pump(tester);
    // Экран подключения теперь — экран сбоя старта (D18): старт упал.
    await tester.tap(find.byKey(const ValueKey('start-new-session')));
    await tester.pumpAndSettle();

    await tester.tap(
      find.descendant(
        of: find.byType(CodeLabConnectionScreen),
        matching: find.text('Configure connection'),
      ),
    );
    await tester.pumpAndSettle();

    expect(
      find.byKey(const ValueKey('connection-profile-row-embedded')),
      findsOneWidget,
    );
    await tearDownApp(tester);
  });
}
