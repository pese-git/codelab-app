// Тесты задачи 4.2 change `add-desktop-localization`: русский текст не
// переполняет узкие места итерации 4 при ширине окна 760 px (D8, «Длина
// строк»): диалог «Add connection profile» (все варианты токена, предупреждение
// `ws://`), строки провайдеров и шапка мастера. Проверяется поведение —
// `tester.takeException()` пуст, а не пиксели.

import 'package:codelab_acp_testing/codelab_acp_testing.dart';
import 'package:codelab_desktop/features/settings/application/provider_settings_session.dart';
import 'package:codelab_setup/codelab_setup.dart';
import 'package:codelab_desktop/app/codelab_app_widget.dart';
import 'package:codelab_desktop/app/navigation/settings_page.dart';
import 'package:codelab_ui/codelab_ui.dart';
import 'package:fluent_ui/fluent_ui.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../../support/fake_profile_secrets.dart';
import '../../../support/fake_provider_settings.dart';
import '../../../support/in_memory_profile_store.dart';
import '../../../support/test_app_scope.dart';

const _pages = SettingsPages(
  available: {SettingsPage.connection, SettingsPage.providers},
);

Finder _key(String key) => find.byKey(ValueKey(key));

void main() {
  setUp(() {
    final view = TestWidgetsFlutterBinding.ensureInitialized()
        .platformDispatcher
        .views
        .single;
    // Открываем настройки в обычном окне: в узком сайдбар свёрнут.
    view.physicalSize = const Size(1440, 900);
    view.devicePixelRatio = 1.0;
    addTearDown(view.resetPhysicalSize);
    addTearDown(view.resetDevicePixelRatio);
  });

  Future<void> frames(WidgetTester tester, [int n = 6]) async {
    for (var i = 0; i < n; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
  }

  Future<void> tearDownApp(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox.shrink());
    await closeCodeLabRootScopeInTest();
  }

  /// Страница настроек [page] на русском в окне 760 px.
  Future<void> openSettings(
    WidgetTester tester,
    SettingsPage page, {
    ProviderSettingsSession? session,
    FakeProfileSecrets? secrets,
    Map<String, String> environment = const {},
  }) async {
    final binding = CodeLabTestBinding(
      project: '/workspace',
      locale: const Locale('ru'),
      stdioDefault: false,
      profileStore: InMemoryProfileStore(),
      profileSecrets: secrets,
      environment: {'HOME': '/home/u', ...environment},
      settingsPages: _pages,
      stdioTransportFactory: (_) => FakeAcpTransport(),
      webSocketTransportFactory: (_) => FakeAcpTransport(),
      providerSettingsOpener: session == null
          ? null
          : (access, env) async => session,
    );
    await tester.pumpWidget(
      binding.bootstrap(child: const CodeLabApp(startOnLaunch: false)),
    );
    await tester.pump();
    await tester.tap(find.byKey(CodeLabSessionSidebar.settingsKey));
    await tester.pumpAndSettle();
    if (page != SettingsPage.connection) {
      await tester.tap(_key(page.navKey));
      await tester.pumpAndSettle();
    }
    // Затем окно сужается до 760 px (D8): страница и диалоги перестраиваются.
    TestWidgetsFlutterBinding.ensureInitialized()
        .platformDispatcher
        .views
        .single
        .physicalSize = const Size(
      760,
      900,
    );
    await tester.pumpAndSettle();
  }

  group('ru, 760 px', () {
    testWidgets('диалог профиля: stdio, WebSocket, все варианты токена и '
        'предупреждение ws://', (tester) async {
      await openSettings(
        tester,
        SettingsPage.connection,
        secrets: FakeProfileSecrets(values: {'codelab/ci/token': 'v'}),
      );
      await tester.tap(_key('connection-add-profile'));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull, reason: 'stdio');

      await tester.enterText(_key('add-profile-env'), 'API_KEY=x');
      await tester.enterText(_key('add-profile-command'), '');
      await tester.enterText(_key('add-profile-args'), 'serve "unclosed');
      await tester.pump();
      expect(tester.takeException(), isNull, reason: 'ошибки stdio');

      await tester.tap(_key('add-profile-type-websocket'));
      await tester.pumpAndSettle();
      await tester.enterText(_key('add-profile-name'), 'Box');
      await tester.enterText(_key('add-profile-url'), 'ws://box:7420');
      await tester.pump();
      expect(tester.takeException(), isNull, reason: 'WebSocket');

      for (final token in const ['stored', 'new', 'env', 'none']) {
        await tester.tap(_key('add-profile-token-$token'));
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull, reason: 'токен: $token');
      }

      await tester.tap(_key('add-profile-token-env'));
      await tester.pumpAndSettle();
      await tester.enterText(_key('add-profile-token-env-name'), 'MISSING_VAR');
      await tester.tap(_key('add-profile-save'));
      await tester.pumpAndSettle();
      expect(_key('add-profile-unencrypted'), findsOneWidget);
      expect(tester.takeException(), isNull, reason: 'подтверждение ws://');

      await tester.tap(_key('add-profile-cancel'));
      await tester.pumpAndSettle();
      await tearDownApp(tester);
    });

    testWidgets('строки провайдеров: свёрнутые и раскрытые, подсказки и '
        'теги', (tester) async {
      final store = FakeAgentConfigStore(
        user: {
          'agent': {'default_model': 'anthropic/m'},
          'providers': {
            'anthropic': providerMap(
              kind: 'anthropic',
              baseUrl: null,
              secret: 'codelab/anthropic',
            ),
            'remote': providerMap(
              baseUrl: 'http://api.example.com/v1',
              env: 'REMOTE_KEY',
              models: ['a', 'b', 'c', 'd', 'e'],
            ),
            'lit': {...providerMap(), 'api_key': leakMarker},
            'g': providerMap(kind: 'gemini', baseUrl: null, env: 'G'),
          },
        },
      );
      final session = FakeProviderSettingsSession(
        store,
        secrets: {'codelab/anthropic': leakMarker},
      );
      session.checkResult = () async => const CheckFailure(
        ProviderCheckFailure(
          kind: ProviderCheckFailureKind.unauthorized,
          statusCode: 401,
          message: 'x',
        ),
      );
      await openSettings(tester, SettingsPage.providers, session: session);
      expect(tester.takeException(), isNull, reason: 'свёрнутые');

      await tester.tap(_key('providers-check-anthropic'));
      await tester.pumpAndSettle();
      for (final id in const ['anthropic', 'remote', 'lit', 'g']) {
        await tester.tap(_key('providers-row-$id'));
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull, reason: 'раскрыта: $id');
        await tester.tap(_key('providers-row-$id'));
        await tester.pumpAndSettle();
      }
      await tearDownApp(tester);
    });

    testWidgets('шапка мастера: строка шагов, сводка и подпись шагов на всём '
        'пути', (tester) async {
      final store = FakeAgentConfigStore(
        user: {
          'providers': {
            'local': providerMap(
              baseUrl: 'http://localhost:11434/v1',
              models: ['qwen'],
            ),
          },
        },
      );
      final session = FakeProviderSettingsSession(store);
      await openSettings(tester, SettingsPage.providers, session: session);

      await tester.tap(_key('providers-add'));
      await frames(tester);
      expect(tester.takeException(), isNull, reason: 'тип API');
      await tester.tap(_key('provider-wizard-preset-custom-anthropic'));
      await frames(tester, 2);
      await tester.tap(_key('provider-wizard-next'));
      await frames(tester);
      expect(tester.takeException(), isNull, reason: 'базовый URL');
      await tester.enterText(
        _key('provider-wizard-base-url-field'),
        'https://llm.example/v1',
      );
      await tester.tap(_key('provider-wizard-next'));
      await frames(tester);
      expect(tester.takeException(), isNull, reason: 'ключ');
      await tester.tap(_key('provider-wizard-key-store'));
      await frames(tester, 2);
      await tester.tap(_key('provider-wizard-next'));
      await frames(tester);
      expect(tester.takeException(), isNull, reason: 'ошибка ключа');
      await tester.tap(_key('provider-wizard-key-none'));
      await frames(tester, 2);
      await tester.tap(_key('provider-wizard-next'));
      await frames(tester);
      expect(tester.takeException(), isNull, reason: 'проверка');
      session.wizardCheck.respond(
        const CheckOk([RemoteModel('m1', contextWindow: 8000)]),
      );
      await frames(tester);
      expect(tester.takeException(), isNull, reason: 'модель');
      await tester.tap(_key('provider-wizard-model-m1'));
      await frames(tester);
      expect(tester.takeException(), isNull, reason: 'обзор');

      await tester.tap(_key('provider-wizard-cancel'));
      await frames(tester);
      await tearDownApp(tester);
    });
  });
}
