// Проводка обработчика выхода в `CodeLabBootstrap`: запрос выхода от ОС
// доходит до `CodeLabRootLifecycle.dispose()` — закрываются вкладки Terminal
// (`add-integrated-terminal`, 2.15; D4 «Выход из app», D15 п. 9) и ядро
// клиента (`add-client-process-shutdown-on-exit`, задача 3.3; D1).
// Проверяется поведение: ответ `exit`, `hangUp` живой вкладке, закрытый
// транспорт, `app.exit_closed`; после снятия дерева слушателя нет.
import 'dart:ui' show AppExitResponse;

import 'package:codelab_acp_protocol/codelab_acp_protocol.dart';
import 'package:codelab_acp_testing/codelab_acp_testing.dart';
import 'package:codelab_desktop/features/terminal/application/terminal_tabs_cubit.dart';
import 'package:codelab_desktop/features/workbench/application/shell_cubit.dart';
import 'package:codelab_ui/codelab_ui.dart' show CodeLabConnectionStatus;
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:structured_log_flutter/structured_log_flutter.dart'
    show LogBuffer;

import '../support/fake_user_shell_launcher.dart';
import '../support/start_agent.dart';
import '../support/test_app_scope.dart';

void main() {
  /// Дерево с одной открытой fake-вкладкой терминала.
  Future<
    ({FakeUserShell shell, CodeLabTestBinding binding, TerminalTabsCubit tabs})
  >
  pumpWithTab(WidgetTester tester) async {
    final agent = FakeAcpTransport();
    final launcher = FakeUserShellLauncher()..shellsExitOnHangUp = true;
    final binding = CodeLabTestBinding(
      stdioTransportFactory: (_) => agent,
      userShellLauncher: launcher,
    );
    await tester.pumpWidget(binding.bootstrap(child: const SizedBox.shrink()));
    final shell = binding.scope.resolve<CodeLabShellCubit>();
    await tester.runAsync(() async {
      await shell.selectProject('/work/a');
      if (shell.state.connectionStatus != CodeLabConnectionStatus.connected) {
        await shell.startWith();
      }
      final sent = agent.sent.firstWhere(
        (m) => m is JsonRpcRequest && m.method == sessionNewMethod,
      );
      final created = shell.createSession();
      final request = await sent as JsonRpcRequest;
      agent.emitInbound(
        JsonRpcMessage.response(
          id: request.id,
          result: {'sessionId': 'session-a'},
        ),
      );
      await created;
    });
    await tester.pump();
    final tabs = binding.scope.resolve<TerminalTabsCubit>();
    await tabs.newTab();
    return (shell: launcher.shells.single, binding: binding, tabs: tabs);
  }

  /// Запрос выхода от ОС с докруткой fake-async зоны.
  ///
  /// Почему: scope собран в fake-async зоне, а закрытие Cubit-ов и
  /// рабочего пространства возобновляет настоящий ввод-вывод; `await` без
  /// чередования `runAsync` и `idle` в `testWidgets` не завершился бы (так же
  /// устроен `closeCodeLabRootScopeInTest`). Предел 5 с здесь не срабатывает:
  /// закрытие укладывается в доли секунды.
  Future<AppExitResponse> requestExit(WidgetTester tester) async {
    var done = false;
    final exiting = tester.binding.handleRequestAppExit().whenComplete(
      () => done = true,
    );
    while (!done) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 5)),
      );
      await tester.idle();
    }
    return exiting;
  }

  testWidgets('запрос выхода от ОС: CodeLabRootLifecycle.dispose — hangUp '
      'вкладке, закрытый транспорт, app.exit_closed', (tester) async {
    final env = await pumpWithTab(tester);

    final response = await requestExit(tester);

    expect(response, AppExitResponse.exit);
    expect(env.shell.hangUps, 1);
    expect(env.binding.transport.state, AcpTransportState.closed);
    expect(
      env.binding.scope.resolve<LogBuffer>().entries.value.map(
        (e) => e['event'],
      ),
      containsAllInOrder(['app.exit_requested', 'app.exit_closed']),
    );
  });

  testWidgets('после снятия дерева слушатель освобождён: Cubit не трогается', (
    tester,
  ) async {
    final env = await pumpWithTab(tester);

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
    final logs = env.binding.scope.resolve<LogBuffer>();
    int exitRequests() => logs.entries.value
        .where((e) => e['event'] == 'app.exit_requested')
        .length;
    final before = exitRequests();
    // `CodeLabBootstrap.dispose` сам закрывает scope (`closeAll()` из root
    // lifecycle) — это один `hangUp`; запрос выхода после него нового не даёт.
    final afterDispose = env.shell.hangUps;
    final response = await requestExit(tester);

    expect(response, AppExitResponse.exit);
    expect(env.shell.hangUps, afterDispose);
    // Живой слушатель записал бы `app.exit_requested`.
    expect(exitRequests(), before);
  });
}
