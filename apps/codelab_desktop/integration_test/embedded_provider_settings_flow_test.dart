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
//
// Мастер провайдера (задачи 3.9 и 3.14; шаги 1, 3 и 4 §12.4.13; spec
// app-settings «Мастер провайдера в app», agent-workbench-ui «Встроенный агент
// без провайдера»; design.md D7, D26): пустой дом → баннер → «Add provider» →
// мастер → переподключение; «Edit» с `KeepStoredSecret`; конфликт записи.
// Им нужен настоящий открыватель встроенного агента на временном
// `CODELAB_HOME`, поэтому в режиме `CODELAB_E2E_AGENT=embedded` (сценарий
// модели вместо конфига) они пропускаются.

import 'dart:async';
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

/// Сервер `/models`: `200` со списком из модели `m1` без окна контекста
/// (мастер спросит его); считает запросы.
Future<(HttpServer, int Function())> _modelsOkServer() async {
  final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
  var requests = 0;
  server.listen((request) async {
    requests++;
    request.response
      ..statusCode = 200
      ..headers.contentType = ContentType.json
      ..write('{"data":[{"id":"m1"}]}');
    await request.response.close();
  });
  addTearDown(() => server.close(force: true));
  return (server, () => requests);
}

Future<void> _tapKey(WidgetTester tester, String key) async {
  await _pumpUntil(tester, _key(key));
  await tester.tap(_key(key));
  await tester.pump(const Duration(milliseconds: 300));
}

/// Проходит мастер от пресета до «Review»: custom-пресет с адресом [url],
/// ключ — `provider-wizard-key-<keyKind>` (для `store` — [marker] в поле).
Future<void> _walkToReview(
  WidgetTester tester, {
  required String url,
  required String keyKind,
  String? marker,
}) async {
  await _tapKey(tester, 'provider-wizard-preset-custom-openai');
  await _tapKey(tester, 'provider-wizard-next');
  await _pumpUntil(tester, _key('provider-wizard-base-url-field'));
  await tester.enterText(_key('provider-wizard-base-url-field'), url);
  await _tapKey(tester, 'provider-wizard-next');
  await _tapKey(tester, 'provider-wizard-key-$keyKind');
  if (marker != null) {
    await tester.enterText(_key('provider-wizard-key-field'), marker);
  }
  await _tapKey(tester, 'provider-wizard-next');
  await _tapKey(tester, 'provider-wizard-model-m1');
  // `/models` без окна контекста: мастер спрашивает его (подсказка 32000).
  await _tapKey(tester, 'provider-wizard-next');
  await _pumpUntil(tester, _key('provider-wizard-review'));
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
    'an empty home: the banner offers Add provider, the wizard saves the '
    'provider with the key in the store, the embedded agent is reconnected '
    'and the model is in the composer',
    (tester) async {
      final (server, requests) = await _modelsOkServer();
      final secrets = await E2eAgent.current.openFileSecrets();
      final home = File(E2eAgent.current.profilesPath).parent.path;

      await tester.pumpWidget(
        E2eAgent.current.bootstrap(profileSecrets: secrets),
      );
      await tester.pumpAndSettle();
      final shellCubit = codeLabDependenciesOf(
        tester.element(find.byType(CodeLabApp)),
      ).shellCubit;
      unawaited(shellCubit.connect());

      // Новая установка: понятный текст вместо сырых проблем конфига.
      await _pumpUntil(tester, _key('connection-banner-add-provider'));
      expect(
        find.text('No model provider is configured for the embedded agent.'),
        findsOneWidget,
      );
      expect(find.textContaining('no model is configured'), findsNothing);
      expect(find.textContaining('codelab config check'), findsNothing);

      await tester.tap(_key('connection-banner-add-provider'));
      await _pumpUntil(tester, _key('provider-wizard'));
      await _walkToReview(
        tester,
        url: 'http://127.0.0.1:${server.port}/v1',
        keyKind: 'store',
        marker: _marker,
      );
      expect(requests(), 1);
      expect(find.textContaining(_marker), findsNothing);
      await tester.tap(_key('provider-wizard-save'));
      for (
        var i = 0;
        i < 100 && _key('provider-wizard').evaluate().isNotEmpty;
        i++
      ) {
        await tester.pump(const Duration(milliseconds: 100));
      }

      // Ключ — только в хранилище, ссылка и модель по умолчанию — в конфиге.
      final config = File('$home/config.yaml').readAsStringSync();
      expect(config, contains('api_key_secret: codelab/'));
      expect(config, contains('default_model:'));
      expect(config, isNot(contains(_marker)));
      final access = await ClientSecretAccess.open(
        codelabHome: home,
        environment: {...Platform.environment, 'CODELAB_HOME': home},
        logger: CodeLabEmbeddedLogger(),
      );
      // Имя секрета выводится из адреса: у локального хоста — `local-<порт>`
      // (`127.0.0.1:<порт>` → `local-<порт>`, design.md D7; адрес в id не попадает).
      expect(await access.isSet('codelab/local-${server.port}'), isTrue);

      // Переподключение без перезапуска: баннера нет, модель — в композере.
      for (
        var i = 0;
        i < 200 &&
            shellCubit.state.connectionStatus !=
                CodeLabConnectionStatus.connected;
        i++
      ) {
        await tester.pump(const Duration(milliseconds: 100));
      }
      expect(
        shellCubit.state.connectionStatus,
        CodeLabConnectionStatus.connected,
      );
      expect(_key('connection-banner-add-provider'), findsNothing);
      // Агент читает ключ при открытии: модели нового провайдера появляются
      // после «Restart agent» (Q17, задача 6.1a), поэтому тест перезапускает
      // агента кнопкой на странице «Connection», как пользователь.
      await tester.tap(find.byKey(CodeLabSessionSidebar.settingsKey));
      await tester.pumpAndSettle();
      await _tapKey(tester, 'settings-nav-connection');
      await _tapKey(tester, 'connection-restart-agent');
      await tester.pump(const Duration(seconds: 1));
      for (
        var i = 0;
        i < 200 &&
            shellCubit.state.connectionStatus !=
                CodeLabConnectionStatus.connected;
        i++
      ) {
        await tester.pump(const Duration(milliseconds: 100));
      }
      await shellCubit.createSession();
      for (
        var i = 0;
        i < 100 && !shellCubit.state.configOptions.any((o) => o.id == 'model');
        i++
      ) {
        await tester.pump(const Duration(milliseconds: 100));
      }
      final model = shellCubit.state.configOptions.firstWhere(
        (o) => o.id == 'model',
      );
      expect(model.values.any((v) => v.value.endsWith('/m1')), isTrue);

      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpAndSettle();
      await closeCodeLabRootScope();
    },
    skip: E2eAgent.current.kind == E2eAgentKind.embedded,
  );

  testWidgets(
    'Edit with the stored key kept: the address changes, the secret stays',
    (tester) async {
      final (server, _) = await _modelsOkServer();
      final home = File(E2eAgent.current.profilesPath).parent.path;
      File('$home/config.yaml').writeAsStringSync('''
secrets:
  backend: file
agent:
  default_model: team/m1
providers:
  team:
    kind: openai-compatible
    base_url: http://127.0.0.1:${server.port}/v1
    api_key_secret: codelab/team
    models:
      m1:
        context_window: 32000
''');
      final secrets = await E2eAgent.current.openFileSecrets();
      final access = await ClientSecretAccess.open(
        codelabHome: home,
        environment: {...Platform.environment, 'CODELAB_HOME': home},
        logger: CodeLabEmbeddedLogger(),
      );
      await access.admin.store('codelab/team', _marker);

      await tester.pumpWidget(
        E2eAgent.current.bootstrap(profileSecrets: secrets),
      );
      await tester.pumpAndSettle();
      await _openProviders(tester);

      await tester.tap(_key('providers-edit-team'));
      await _pumpUntil(tester, _key('provider-wizard-base-url-field'));
      await tester.enterText(
        _key('provider-wizard-base-url-field'),
        'http://127.0.0.1:${server.port}/alt',
      );
      await _tapKey(tester, 'provider-wizard-next');
      await _tapKey(tester, 'provider-wizard-key-keep');
      await _tapKey(tester, 'provider-wizard-next');
      await _tapKey(tester, 'provider-wizard-model-m1');
      await _tapKey(tester, 'provider-wizard-next');
      await _pumpUntil(tester, _key('provider-wizard-review'));
      await tester.tap(_key('provider-wizard-save'));
      for (
        var i = 0;
        i < 100 && _key('provider-wizard').evaluate().isNotEmpty;
        i++
      ) {
        await tester.pump(const Duration(milliseconds: 100));
      }

      final config = File('$home/config.yaml').readAsStringSync();
      expect(config, contains('/alt'));
      expect(config, contains('api_key_secret: codelab/team'));
      expect(config, isNot(contains(_marker)));
      expect(await access.read('codelab/team'), _marker);

      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpAndSettle();
      await closeCodeLabRootScope();
    },
  );

  testWidgets(
    'a config changed on disk during the wizard: the conflict banner, the '
    'draft stays, Save again writes over the fresh file',
    (tester) async {
      final (server, _) = await _modelsOkServer();
      final home = File(E2eAgent.current.profilesPath).parent.path;
      final file = File('$home/config.yaml')
        ..writeAsStringSync('''
agent:
  default_model: team/m1
providers:
  team:
    kind: openai-compatible
    base_url: http://127.0.0.1:${server.port}/v1
    models:
      m1:
        context_window: 32000
''');

      await tester.pumpWidget(E2eAgent.current.bootstrap());
      await tester.pumpAndSettle();
      await _openProviders(tester);

      await tester.tap(_key('providers-add'));
      await _pumpUntil(tester, _key('provider-wizard'));
      await _walkToReview(
        tester,
        url: 'http://127.0.0.1:${server.port}/v1',
        keyKind: 'none',
      );
      // Файл меняет другой процесс между чтением и записью.
      file.writeAsStringSync('${file.readAsStringSync()}# edited elsewhere\n');
      await tester.tap(_key('provider-wizard-save'));
      await _pumpUntil(tester, _key('provider-wizard-review-notice'));

      expect(
        find.text('Config changed on disk — review and save again'),
        findsOneWidget,
      );
      expect(_key('provider-wizard-save'), findsOneWidget);
      expect(file.readAsStringSync(), contains('# edited elsewhere'));
      expect(file.readAsStringSync(), isNot(contains('local-${server.port}')));

      // «Save» ещё раз: автомат перечитал снимок, запись идёт поверх свежего
      // файла, а внешняя правка цела (D9).
      await tester.tap(_key('provider-wizard-save'));
      for (
        var i = 0;
        i < 100 && _key('provider-wizard').evaluate().isNotEmpty;
        i++
      ) {
        await tester.pump(const Duration(milliseconds: 100));
      }
      expect(file.readAsStringSync(), contains('# edited elsewhere'));
      expect(file.readAsStringSync(), contains('local-${server.port}'));

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
