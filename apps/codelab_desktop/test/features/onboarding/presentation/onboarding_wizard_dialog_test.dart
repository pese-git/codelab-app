// Мастер провайдера на шаге «Choose a model» в полном дереве app (исправление
// дефекта ручной проверки 2026-11-21: после «Set up OpenAI…» диалог не
// появлялся, мастер закрывался сразу; change `add-app-onboarding`, D8).
//
// Почему не в `onboarding_screen_test.dart`: там изолированный harness без
// корневого виджета; дефект проявлялся только в настоящем дереве
// (`CodeLabApp` на `CodeLabTestBinding(onboarding:)`), поэтому открыватель —
// настоящий (`OnboardingWizardOpener` из scope) на сессии-двойнике.

import 'package:codelab_desktop/app/codelab_app_widget.dart';
import 'package:codelab_desktop/app/onboarding/onboarding_start.dart';
import 'package:codelab_setup/codelab_setup.dart';
import 'package:fluent_ui/fluent_ui.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../../support/fake_onboarding.dart';
import '../../../support/fake_provider_settings.dart';
import '../../../support/test_app_scope.dart';

Finder _key(String key) => find.byKey(ValueKey(key));

void main() {
  late FakeAgentConfigStore store;
  late FakeProviderSettingsSession session;
  late FakeOnboardingPreferences preferences;

  setUp(() {
    store = FakeAgentConfigStore();
    session = FakeProviderSettingsSession(store);
    preferences = FakeOnboardingPreferences();
  });

  Future<void> pumpAtModelStep(WidgetTester tester) async {
    tester.view.physicalSize = const Size(1400, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final binding = CodeLabTestBinding(
      onboarding: const OnboardingStart(show: true),
      onboardingProbe: FakeOnboardingProbe(
        onboardingFacts(const NoProviderConfigured(), backend: 'file'),
      ),
      onboardingPreferences: preferences,
      // Настоящий открыватель мастера (`OnboardingWizardOpener`) открывает
      // сессию настроек по доступу из фактов; сессия — двойник.
      providerSettingsOpener: (access, environment) async => session,
      environment: {'CODELAB_HOME': '/home/u/.codelab'},
    );
    await tester.pumpWidget(
      binding.bootstrap(child: const CodeLabApp(startOnLaunch: false)),
    );
    await tester.pumpAndSettle();
    await tester.tap(_key('onboarding-next'));
    await tester.pumpAndSettle();
    await tester.tap(_key('onboarding-next'));
    await tester.pumpAndSettle();
  }

  testWidgets('«Set up OpenAI…» открывает диалог мастера на «Base URL»', (
    tester,
  ) async {
    await pumpAtModelStep(tester);
    await tester.tap(_key('onboarding-preset-openai'));
    await tester.pumpAndSettle();

    await tester.tap(_key('onboarding-model-setup'));
    await tester.pump(const Duration(milliseconds: 300));
    await tester.pump(const Duration(milliseconds: 300));

    expect(_key('provider-wizard-base-url-field'), findsOneWidget);
    expect(
      session.wizards.single.entry,
      ProviderWizardEntry.onboarding,
      reason: 'мастер открыт по onboarding и не закрыт сразу',
    );
    expect(_key('onboarding-step-model'), findsOneWidget);

    await tester.tap(_key('provider-wizard-cancel'));
    await tester.pumpAndSettle();
    expect(_key('onboarding-model-later'), findsOneWidget);
    expect(_key('onboarding-next'), findsNothing);
  });

  testWidgets('в том же дереве «Set up later» ведёт на «Privacy», а ссылки '
      'открывают документ', (tester) async {
    await pumpAtModelStep(tester);

    await tester.tap(_key('onboarding-model-later'));
    await tester.pumpAndSettle();

    expect(_key('onboarding-step-privacy'), findsOneWidget);
    await tester.tap(_key('onboarding-privacy-policy'));
    await tester.pumpAndSettle();
    expect(_key('onboarding-document'), findsOneWidget);
  });
}
