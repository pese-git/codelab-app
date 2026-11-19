// Тесты задачи 4.2 change `add-desktop-localization`: мастер провайдера на
// экране — ошибки по типу и дедупликация сообщения о существующем ключе
// (D5 п. 5, D6 «Тексты моста настроек», «Дедупликация в диалоге»; spec
// app-settings «Сообщения мастера провайдера на русском»).
//
// Что проверяется. Сообщение «сохранённый ключ уже есть» показано ровно один
// раз на `en` и на `ru`, в том числе после `KeySubmitted(StoreSecret)` при
// существующем секрете (там автомат ставит ошибку `keyAlreadyStored`); ошибки
// деталей модели и пояснение литерального ключа берутся по коду и признаку.

import 'package:codelab_acp_testing/codelab_acp_testing.dart';
import 'package:codelab_desktop/app/codelab_app_widget.dart';
import 'package:codelab_desktop/app/navigation/settings_page.dart';
import 'package:codelab_desktop/features/settings/application/provider_wizard_cubit.dart';
import 'package:codelab_setup/codelab_setup.dart';
import 'package:codelab_ui/codelab_ui.dart';
import 'package:fluent_ui/fluent_ui.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../../support/fake_provider_settings.dart';
import '../../../support/in_memory_profile_store.dart';
import '../../../support/test_app_scope.dart';

const _pages = SettingsPages(
  available: {SettingsPage.connection, SettingsPage.providers},
);

Finder _key(String key) => find.byKey(ValueKey(key));

void main() {
  late FakeAgentConfigStore store;
  late FakeProviderSettingsSession session;

  setUp(() {
    final view = TestWidgetsFlutterBinding.ensureInitialized()
        .platformDispatcher
        .views
        .single;
    view.physicalSize = const Size(1440, 1400);
    view.devicePixelRatio = 1.0;
    addTearDown(view.resetPhysicalSize);
    addTearDown(view.resetDevicePixelRatio);
    store = FakeAgentConfigStore(
      user: {
        'agent': {'default_model': 'local/qwen'},
        'providers': {
          'local': providerMap(
            baseUrl: 'http://localhost:11434/v1',
            models: ['qwen'],
          ),
          'lit': {...providerMap(), 'api_key': leakMarker},
        },
      },
    );
    session = FakeProviderSettingsSession(store);
  });

  Future<void> frames(WidgetTester tester, [int n = 8]) async {
    for (var i = 0; i < n; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
  }

  Future<void> openPage(WidgetTester tester, Locale locale) async {
    final binding = CodeLabTestBinding(
      project: '/workspace',
      locale: locale,
      stdioDefault: false,
      profileStore: InMemoryProfileStore(),
      environment: {'HOME': '/home/u'},
      settingsPages: _pages,
      stdioTransportFactory: (_) => FakeAcpTransport(),
      providerSettingsOpener: (access, env) async => session,
    );
    await tester.pumpWidget(
      binding.bootstrap(child: const CodeLabApp(startOnLaunch: false)),
    );
    await tester.pump();
    await tester.tap(find.byKey(CodeLabSessionSidebar.settingsKey));
    await tester.pumpAndSettle();
    await tester.tap(_key(SettingsPage.providers.navKey));
    await tester.pumpAndSettle();
  }

  Future<void> next(WidgetTester tester) async {
    await tester.tap(_key('provider-wizard-next'));
    await frames(tester);
  }

  Future<void> toKey(WidgetTester tester) async {
    await tester.tap(_key('providers-add'));
    await frames(tester);
    await tester.tap(_key('provider-wizard-preset-custom-openai'));
    await frames(tester, 2);
    await next(tester);
    await tester.enterText(
      _key('provider-wizard-base-url-field'),
      'https://llm.example/v1',
    );
    await next(tester);
  }

  ProviderWizardCubit wizardOf(WidgetTester tester) =>
      tester.element(_key('provider-wizard')).read<ProviderWizardCubit>();

  Future<void> tearDownApp(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox.shrink());
    await closeCodeLabRootScopeInTest();
  }

  for (final (locale, existing, english) in [
    (
      const Locale('en'),
      'A stored key codelab/llm-example already exists in file.',
      true,
    ),
    (
      const Locale('ru'),
      'Сохранённый ключ «codelab/llm-example» уже есть в file.',
      false,
    ),
  ]) {
    group('${locale.languageCode}: сообщение о существующем ключе', () {
      testWidgets('показано один раз при входе на шаг ключа', (tester) async {
        session.secrets['codelab/llm-example'] = 'old-value';
        await openPage(tester, locale);

        await toKey(tester);

        expect(find.text(existing), findsOneWidget);
        await tester.tap(_key('provider-wizard-cancel'));
        await frames(tester);
        await tearDownApp(tester);
      });

      testWidgets('после `KeySubmitted(StoreSecret)` ошибка `keyAlreadyStored` '
          'не дублирует подпись', (tester) async {
        session.secrets['codelab/llm-example'] = 'old-value';
        await openPage(tester, locale);
        await toKey(tester);

        wizardOf(tester).dispatch(KeySubmitted(StoreSecret(SecretValue('v'))));
        await frames(tester);

        expect(
          (wizardOf(tester).state.setup as ChoosingKey).errorCode,
          ProviderSetupErrorCode.keyAlreadyStored,
        );
        expect(find.text(existing), findsOneWidget);
        // Английская строка моста не просачивается на экран ни на каком языке.
        expect(
          find.text('A stored key codelab/llm-example already exists in file.'),
          english ? findsOneWidget : findsNothing,
        );
        await tester.tap(_key('provider-wizard-cancel'));
        await frames(tester);
        await tearDownApp(tester);
      });
    });
  }

  group('ru: шаги по коду и признаку', () {
    testWidgets('ошибки деталей модели', (tester) async {
      await openPage(tester, const Locale('ru'));
      await toKey(tester);
      await tester.tap(_key('provider-wizard-key-none'));
      await frames(tester, 2);
      await next(tester);
      session.wizardCheck.respond(
        const CheckFailure(
          ProviderCheckFailure(
            kind: ProviderCheckFailureKind.unreachable,
            message: 'x',
          ),
        ),
      );
      await frames(tester);
      await tester.tap(_key('provider-wizard-skip-check'));
      await frames(tester, 2);
      await tester.tap(_key('provider-wizard-skip-confirm'));
      await frames(tester);
      await tester.enterText(
        _key('provider-wizard-model-manual-field'),
        'my-model',
      );
      await next(tester);
      await tester.enterText(_key('provider-wizard-context-window'), '0');

      await next(tester);

      expect(
        find.text('Окно контекста должно быть положительным числом.'),
        findsOneWidget,
      );
      await tester.tap(_key('provider-wizard-cancel'));
      await frames(tester);
      await tearDownApp(tester);
    });

    testWidgets('пояснение литерального ключа при правке', (tester) async {
      await openPage(tester, const Locale('ru'));

      await tester.tap(_key('providers-edit-lit'));
      await frames(tester);
      await next(tester);

      expect(
        find.text(
          'Ключ записан в config.yaml. Выберите, где его хранить вместо этого.',
        ),
        findsOneWidget,
      );
      expect(
        find.text(
          'The key is written in config.yaml. Choose where to keep it instead.',
        ),
        findsNothing,
      );
      await tester.tap(_key('provider-wizard-cancel'));
      await frames(tester);
      await tearDownApp(tester);
    });
  });
}
