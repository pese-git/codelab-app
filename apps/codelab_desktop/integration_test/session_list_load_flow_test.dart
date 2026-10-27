// E2e списка и загрузки сессий (tasks 5.5 change `add-session-list-and-reload`;
// spec testing-quality «Интеграционный тест списка и загрузки сессий»;
// строка Must D-03 матрицы паритета).
//
// Только scripted-агент: бинарь `codelab-agent` с `--llm-script` держит
// сессии в памяти и не объявляет `loadSession` (`agent_host.dart`), поэтому
// по ACP клиент не вправе вызывать `session/load`.

import 'dart:io';

import 'package:codelab_acp_testing/codelab_acp_testing.dart';
import 'package:codelab_desktop/app/app_scope.dart';
import 'package:codelab_desktop/app/codelab_app_widget.dart';
import 'package:codelab_desktop/features/workbench/application/shell_cubit.dart';
import 'package:codelab_ui/codelab_ui.dart';
import 'package:fluent_ui/fluent_ui.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

import 'support/e2e_agent.dart';

CodeLabShellCubit _cubit(WidgetTester tester) =>
    codeLabDependenciesOf(tester.element(find.byType(CodeLabApp))).shellCubit;

/// Вводит команду агента в форму и подключается (как в
/// stdio_connect_flow_test.dart).
Future<void> _connect(WidgetTester tester, E2eLaunch launch) async {
  await tester.tap(
    find.byKey(const ValueKey('command-bar-configure-connection')),
  );
  await tester.pumpAndSettle();
  await tester.enterText(
    find.byKey(const ValueKey('transport-field-Command')),
    launch.command,
  );
  await tester.enterText(
    find.byKey(const ValueKey('transport-field-Args')),
    launch.args,
  );
  await tester.tap(find.widgetWithText(Button, 'Close'));
  await tester.pumpAndSettle();
  await tester.tap(find.widgetWithText(CodeLabButton, 'Connect').first);
  await tester.pump();
  await _waitFor(
    tester,
    () =>
        _cubit(tester).state.connectionStatus ==
        CodeLabConnectionStatus.connected,
  );
}

/// Ждёт [condition] не дольше 10 секунд, прокачивая кадры.
Future<void> _waitFor(WidgetTester tester, bool Function() condition) async {
  final deadline = DateTime.now().add(const Duration(seconds: 10));
  while (!condition() && DateTime.now().isBefore(deadline)) {
    await tester.pump(const Duration(milliseconds: 100));
  }
  await tester.pump(const Duration(milliseconds: 300));
  expect(condition(), isTrue);
}

List<String?> _transcript(WidgetTester tester) => [
  for (final entry in _cubit(tester).state.transcriptEntries) entry.body,
];

/// Создаёт сессию и проводит в ней ход [text]; агент отвечает `echo: …`.
Future<String> _sessionWithTurn(WidgetTester tester, String text) async {
  await tester.tap(find.byKey(const ValueKey('new-session-button')));
  await tester.pumpAndSettle();
  final id = _cubit(tester).state.activeSessionId!;
  await tester.tap(find.byKey(const ValueKey('composer-text-box')));
  await tester.pump();
  await tester.enterText(find.byKey(const ValueKey('composer-text-box')), text);
  await tester.pump();
  await tester.tap(find.byKey(const ValueKey('composer-send-button')));
  await tester.pump();
  await _waitFor(
    tester,
    () =>
        _transcript(tester).contains('echo: $text') &&
        !_cubit(tester).state.isPromptSubmitting,
  );
  return id;
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets(
    'the sidebar lists the agent sessions, Reconnect and an app restart '
    'restore the active session, and selecting another restores its '
    'transcript',
    tags: scriptedOnly,
    (tester) async {
      final project = await Directory.systemTemp.createTemp(
        'codelab_session_list_e2e_',
      );
      addTearDown(() async {
        if (await project.exists()) {
          await project.delete(recursive: true);
        }
      });
      final launch = await E2eAgent.current.launch(
        project,
        mode: CodelabCompatibleStdioAgentMode.withSessionList,
      );

      await tester.pumpWidget(const CodeLabBootstrap(child: CodeLabApp()));
      await tester.pumpAndSettle();
      await _cubit(tester).selectProject(project.path);
      await tester.pumpAndSettle();
      await _connect(tester, launch);

      final first = await _sessionWithTurn(tester, 'first task');
      final second = await _sessionWithTurn(tester, 'second task');
      expect(_cubit(tester).state.activeSessionId, second);

      // Reconnect: новый процесс агента, активная сессия загружается заново.
      await _cubit(tester).reconnect();
      await _waitFor(
        tester,
        () =>
            _cubit(tester).state.connectionStatus ==
                CodeLabConnectionStatus.connected &&
            _transcript(tester).contains('echo: second task'),
      );
      expect(_transcript(tester), ['second task', 'echo: second task']);
      expect(
        _cubit(tester).state.sessions.where(
          (row) => row.status == CodeLabSessionStatus.detached,
        ),
        isEmpty,
      );

      // Перезапуск app: корневой scope создаётся заново с теми же
      // `shared_preferences`, снимок рабочего пространства переживает его.
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpAndSettle();
      await closeCodeLabRootScope();
      await tester.pumpWidget(const CodeLabBootstrap(child: CodeLabApp()));
      await tester.pumpAndSettle();

      expect(_cubit(tester).state.selectedProjectPath, project.path);
      await _connect(tester, launch);
      await _waitFor(
        tester,
        () =>
            _cubit(tester).state.activeSessionId == second &&
            _transcript(tester).contains('echo: second task'),
      );
      expect(_transcript(tester), ['second task', 'echo: second task']);
      final rows = {
        for (final row in _cubit(tester).state.sessions) row.id: row.status,
      };
      expect(rows.keys, containsAll([first, second]));
      expect(rows[first], CodeLabSessionStatus.notLoaded);

      // Выбор незагруженной сессии в сайдбаре загружает её транскрипт.
      await tester.tap(
        find.descendant(
          of: find.byType(CodeLabSessionSidebar),
          matching: find.text('first task'),
        ),
      );
      await tester.pump();
      await _waitFor(
        tester,
        () =>
            _cubit(tester).state.activeSessionId == first &&
            _transcript(tester).contains('echo: first task'),
      );
      expect(_transcript(tester), ['first task', 'echo: first task']);
    },
  );
}
