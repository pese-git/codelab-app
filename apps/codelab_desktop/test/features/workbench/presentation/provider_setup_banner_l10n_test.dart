// Красный тест задачи 3.3 change `add-desktop-localization`: InfoBar настройки
// провайдера встроенного агента на русском (spec agent-workbench-ui
// «Встроенный агент без провайдера», app-settings «Локализация интерфейса
// app»; design.md D5, D7).
//
// Сборка как в `provider_setup_banner_test.dart`: встроенный агент — двойник,
// который первым открытием бросает ошибку конфигурации, признак «нужен
// провайдер» — шов `providerSetupProbe`. Здесь язык `ru` приходит швом
// `CodeLabTestBinding(locale:)`. Подпись кнопки — «Добавить провайдера» по
// глоссарию («provider — провайдер»); текст баннера — вне глоссария, он
// перечислен в отчёте задачи 3.3. Сырой текст проблем конфигурации по-прежнему
// не показывается (это текст агента).

import 'dart:async';

import 'package:codelab_acp_testing/codelab_acp_testing.dart';
import 'package:codelab_desktop/app/codelab_app_widget.dart';
import 'package:codelab_desktop/features/workbench/application/shell_cubit.dart';
import 'package:codelab_embedded/codelab_embedded.dart'
    show EmbeddedAgent, EmbeddedAgentConfigException, McpStatusPort;
import 'package:codelab_setup/codelab_setup.dart'
    show ConfigIssue, ConfigIssueKind;
import 'package:fluent_ui/fluent_ui.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../../support/in_memory_profile_store.dart';
import '../../../support/start_agent.dart';
import '../../../support/test_app_scope.dart';

final class _Agent implements EmbeddedAgent {
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
  testWidgets('встроенный агент без провайдера: текст и кнопка на русском, '
      'сырые проблемы конфигурации не показаны', (tester) async {
    final view = TestWidgetsFlutterBinding.ensureInitialized()
        .platformDispatcher
        .views
        .single;
    view.physicalSize = const Size(1440, 1400);
    view.devicePixelRatio = 1.0;
    addTearDown(view.resetPhysicalSize);
    addTearDown(view.resetDevicePixelRatio);

    var opens = 0;
    final binding = CodeLabTestBinding(
      project: '/workspace',
      locale: const Locale('ru'),
      stdioDefault: false,
      profileStore: InMemoryProfileStore(),
      embeddedOpener: ({required cwd, required hostProfile}) async {
        opens++;
        if (opens == 1) {
          throw EmbeddedAgentConfigException([
            ConfigIssue(
              kind: ConfigIssueKind.value,
              key: 'agent.default_model',
              source: '/home/u/.codelab/config.yaml',
              message: 'required',
            ),
          ], home: '/home/u/.codelab');
        }
        return _Agent();
      },
      providerSetupProbe: (cwd) async => true,
    );
    await tester.pumpWidget(
      binding.bootstrap(child: const CodeLabApp(startOnLaunch: false)),
    );
    await tester.pump();
    final shell = binding.scope.resolve<CodeLabShellCubit>();
    unawaited(shell.startWith());
    for (var i = 0; i < 10; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }

    expect(
      find.text('Для встроенного агента не настроен провайдер модели.'),
      findsOneWidget,
    );
    expect(
      find.descendant(
        of: find.byKey(const ValueKey('connection-banner-add-provider')),
        matching: find.text('Добавить провайдера'),
      ),
      findsOneWidget,
    );
    expect(find.textContaining('agent.default_model'), findsNothing);
    await tester.pumpWidget(const SizedBox.shrink());
  });
}
