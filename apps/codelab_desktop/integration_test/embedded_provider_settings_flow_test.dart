// Страница «Providers» на устройстве (задача 2.12 change
// `add-provider-setup-ui`; шаги 2, 5 и 6 §12.4.13; spec app-settings
// «Страница «Providers»», «Доступ к настройкам агента на страницах Providers
// и MCP servers»; design.md D10).
//
// В `feature/*` файл только компилируется (`fvm flutter analyze`); на
// устройстве или симуляторе его запускает `release/<version>` (AGENTS.md
// §21). Настоящие `~/.codelab` и хранилище ОС не затрагиваются: дом —
// временный `CODELAB_HOME`, бэкенд секретов `file` в нём, `/models` отдаёт
// локальный `HttpServer`. Шаг 6 (WebSocket) нужен процесс
// `codelab-agent serve --ws` (`CODELAB_E2E_AGENT=dart`), иначе пропускается.
// Шаги 1, 3 и 4 §12.4.13 относятся к мастеру провайдера (итерация 3).

import 'dart:io';

import 'package:codelab_desktop/app/app_scope.dart';
import 'package:codelab_desktop/app/codelab_app_widget.dart';
import 'package:codelab_desktop/app/embedded_logger.dart';
import 'package:codelab_ui/codelab_ui.dart';
import 'package:codelab_setup/io.dart' show ClientSecretAccess;
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

import 'support/e2e_agent.dart';

/// Значение ключа, которое не должно выйти из хранилища на экран и в файл.
const _marker = 'sk-test-leak-0123456789';

Finder _key(String key) => find.byKey(ValueKey(key));

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

Future<void> _openProviders(WidgetTester tester) async {
  await tester.tap(find.byKey(CodeLabSessionSidebar.settingsKey));
  await tester.pumpAndSettle();
  await tester.tap(_key('settings-nav-providers'));
  await tester.pumpAndSettle();
}

/// Отвечает на `/models` кодом [status] и считает запросы; тело ошибки
/// специально содержит маркер, который страница показывать не должна.
Future<(HttpServer, int Function())> _modelsServer(int status) async {
  final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
  var requests = 0;
  server.listen((request) async {
    requests++;
    request.response
      ..statusCode = status
      ..write('{"error":"$_marker"}');
    await request.response.close();
  });
  addTearDown(() => server.close(force: true));
  return (server, () => requests);
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets(
    'Check with a wrong key shows unauthorized, and Remove with the box '
    'deletes the provider and its stored key',
    (tester) async {
      final (server, requests) = await _modelsServer(401);
      final home = File(E2eAgent.current.profilesPath).parent.path;
      File('$home/config.yaml').writeAsStringSync('''
secrets:
  backend: file
agent:
  default_model: anthropic/m
providers:
  anthropic:
    kind: openai-compatible
    base_url: http://127.0.0.1:${server.port}/v1
    api_key_secret: codelab/anthropic
    models:
      m:
        context_window: 32000
  local:
    kind: openai-compatible
    base_url: http://127.0.0.1:${server.port}/v1
    api_key_secret: codelab/local
    models:
      qwen:
        context_window: 32000
''');
      final secrets = await E2eAgent.current.openFileSecrets();
      final access = await ClientSecretAccess.open(
        codelabHome: home,
        environment: {...Platform.environment, 'CODELAB_HOME': home},
        logger: CodeLabEmbeddedLogger(),
      );
      await access.admin.store('codelab/anthropic', _marker);
      await access.admin.store('codelab/local', _marker);

      await tester.pumpWidget(
        E2eAgent.current.bootstrap(profileSecrets: secrets),
      );
      await tester.pumpAndSettle();
      await _openProviders(tester);

      // Шаг 2: Check с неверным ключом.
      expect(
        find.textContaining('Key: in file'),
        findsNWidgets(2),
        reason: 'the key status comes from names, not from values',
      );
      await tester.tap(_key('providers-check-anthropic'));
      await _pumpUntil(
        tester,
        find.descendant(
          of: _key('providers-status-anthropic'),
          matching: find.text('unauthorized'),
        ),
      );
      expect(requests(), 1);
      expect(find.textContaining(_marker), findsNothing);

      // Шаг 5: Remove с флажком — провайдер и секрет удалены.
      await tester.tap(_key('providers-remove-local'));
      await tester.pumpAndSettle();
      expect(_key('providers-remove-delete-key'), findsOneWidget);
      await tester.tap(_key('providers-remove-confirm'));
      await tester.pumpAndSettle();
      expect(_key('providers-row-local'), findsNothing);
      final config = File('$home/config.yaml').readAsStringSync();
      expect(config, isNot(contains('local:')));
      expect(config, isNot(contains(_marker)));
      final fresh = await ClientSecretAccess.open(
        codelabHome: home,
        environment: {...Platform.environment, 'CODELAB_HOME': home},
        logger: CodeLabEmbeddedLogger(),
      );
      expect(await fresh.isSet('codelab/local'), isFalse);
      expect(await fresh.isSet('codelab/anthropic'), isTrue);

      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpAndSettle();
      await closeCodeLabRootScope();
    },
  );

  testWidgets(
    'a WebSocket profile: read-only banner, no write controls and no rows '
    'of the local config',
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
      final shellCubit = codeLabDependenciesOf(
        tester.element(find.byType(CodeLabApp)),
      ).shellCubit;
      await agent.connect(tester, shellCubit);

      await _openProviders(tester);

      // Шаг 6: баннер только для чтения без пути `/acp`, кнопок записи нет.
      expect(_key('providers-read-only'), findsOneWidget);
      expect(
        find.textContaining('Read-only: this agent runs on ws://127.0.0.1:'),
        findsOneWidget,
      );
      expect(find.textContaining('/acp'), findsNothing);
      expect(_key('providers-add'), findsNothing);
      expect(_key('providers-default-model'), findsNothing);

      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpAndSettle();
      await closeCodeLabRootScope();
    },
    skip: E2eAgent.current.skipWebSocketAgent,
  );
}
