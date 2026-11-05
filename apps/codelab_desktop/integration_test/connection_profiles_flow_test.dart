// Профили подключения на устройстве (задача 3.9 change
// `add-app-settings-shell`; spec app-settings «Диалог «Add connection
// profile»», «Rename» и «Remove» профиля»; design.md D12–D14, D19).
//
// В `feature/*` файл только компилируется (`fvm flutter analyze`); на
// устройстве или симуляторе его запускает `release/<version>` (AGENTS.md
// §21). WebSocket-сценарий нужен процесс `codelab-agent serve --ws`
// (`CODELAB_E2E_AGENT=dart`), поэтому в других режимах пропускается.

import 'dart:io';

import 'package:codelab_client_core/codelab_client_core.dart'
    show ProfileStore, WebSocketProfile;
import 'package:codelab_client_io/codelab_client_io.dart'
    show JsonFileProfileStore;
import 'package:codelab_desktop/app/app_scope.dart';
import 'package:codelab_ui/codelab_ui.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

import 'support/e2e_agent.dart';

Finder _key(String key) => find.byKey(ValueKey(key));

/// Опрашивает кадрами до появления [finder]: проба и подключение идут через
/// настоящие процессы и сокеты, которые `pumpAndSettle` не ждёт.
Future<void> _pumpUntil(
  WidgetTester tester,
  Finder finder, {
  Duration timeout = const Duration(seconds: 20),
}) async {
  final deadline = DateTime.now().add(timeout);
  while (finder.evaluate().isEmpty && DateTime.now().isBefore(deadline)) {
    await tester.pump(const Duration(milliseconds: 100));
  }
  expect(finder, findsWidgets, reason: 'did not appear in $timeout');
}

Future<void> _openConnectionPage(WidgetTester tester) async {
  await tester.tap(find.byKey(CodeLabSessionSidebar.settingsKey));
  await tester.pumpAndSettle();
}

Future<void> _enter(WidgetTester tester, String key, String text) async {
  await tester.enterText(_key(key), text);
  await tester.pump();
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets(
    'WebSocket agent with a token from env: Reachable, Save, the file keeps '
    'only the reference, Remove of the active profile is unavailable',
    (tester) async {
      await tester.pumpWidget(E2eAgent.current.bootstrap());
      await tester.pumpAndSettle();
      final tempDir = await Directory.systemTemp.createTemp('codelab_ws_e2e_');
      addTearDown(() => tempDir.delete(recursive: true));
      final agent = await E2eAgent.current.startWebSocketAgent(
        tempDir,
        script: 'normal',
      );
      addTearDown(agent.stop);

      await _openConnectionPage(tester);
      await tester.tap(_key('connection-add-profile'));
      await tester.pumpAndSettle();
      await tester.tap(_key('add-profile-type-websocket'));
      await tester.pumpAndSettle();
      await _enter(tester, 'add-profile-name', 'Devbox');
      await _enter(tester, 'add-profile-url', agent.endpoint);
      await tester.tap(_key('add-profile-token-env'));
      await tester.pumpAndSettle();
      await _enter(
        tester,
        'add-profile-token-env-name',
        E2eAgent.webSocketTokenVariable,
      );

      await tester.tap(_key('add-profile-test'));
      await _pumpUntil(tester, _key('add-profile-probe-result'));
      expect(find.textContaining('Reachable'), findsWidgets);

      await tester.tap(_key('add-profile-save'));
      await tester.pumpAndSettle();
      expect(_key('add-profile-saved'), findsOneWidget);
      await tester.tap(_key('add-profile-done'));
      await tester.pumpAndSettle();

      // Файл общий с CLI: `codelab profiles list` читает его тем же
      // хранилищем, а значения токена в нём нет.
      final file = E2eAgent.current.profilesPath;
      final ProfileStore store = JsonFileProfileStore(file);
      final saved = (await store.load())
          .whereType<WebSocketProfile>()
          .singleWhere((profile) => profile.id == 'devbox');
      expect(saved.tokenRef, 'env:${E2eAgent.webSocketTokenVariable}');
      expect(
        await File(file).readAsString(),
        isNot(contains(E2eWebSocketAgent.token)),
      );

      // «Remove» у профиля текущего подключения недоступна.
      await tester.tap(_key('connection-profile-connect-devbox'));
      await _pumpUntil(tester, _key('connection-profile-status-devbox'));
      expect(
        tester
            .widget<CodeLabButton>(_key('connection-profile-remove-devbox'))
            .onPressed,
        isNull,
      );

      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpAndSettle();
      await closeCodeLabRootScope();
    },
    skip: E2eAgent.current.skipWebSocketAgent,
  );

  testWidgets('stdio with a missing command: "Command not found", saved as '
      '"Not tested"', (tester) async {
    await tester.pumpWidget(E2eAgent.current.bootstrap());
    await tester.pumpAndSettle();

    await _openConnectionPage(tester);
    await tester.tap(_key('connection-add-profile'));
    await tester.pumpAndSettle();
    await tester.tap(_key('add-profile-type-stdio'));
    await tester.pumpAndSettle();
    await _enter(tester, 'add-profile-name', 'Missing');
    await _enter(tester, 'add-profile-command', '/nonexistent/agent');

    await tester.tap(_key('add-profile-test'));
    await _pumpUntil(tester, _key('add-profile-probe-result'));
    expect(find.text('Command not found'), findsOneWidget);

    await tester.tap(_key('add-profile-save'));
    await tester.pumpAndSettle();
    await tester.tap(_key('add-profile-done'));
    await tester.pumpAndSettle();

    expect(
      find.descendant(
        of: _key('connection-profile-row-missing'),
        matching: find.text('Not tested'),
      ),
      findsOneWidget,
    );

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pumpAndSettle();
    await closeCodeLabRootScope();
  });
}
