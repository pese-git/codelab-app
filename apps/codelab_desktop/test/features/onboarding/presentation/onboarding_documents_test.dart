// Просмотр правовых документов внутри onboarding (задача 6.5 change
// `add-app-onboarding`; design.md D10 в редакции 2026-11-21; spec
// app-onboarding «Шаг «Privacy»» — сценарии «Политика внутри onboarding и
// возврат», «Условия на русском и Esc», «Кнопки шага под документом»).
//
// Красный по причине компиляции и содержательно: панели документа и ссылок
// ещё нет (задача 6.6).
//
// Почему не в `onboarding_screen_test.dart`: панель показывает `LegalPage` под
// `LegalPageHost`, а тот читает `CodeLabDependencies`, `NavigationCubit` и
// `AppLanguageCubit`. Поэтому тесты идут в настоящем дереве app
// (`CodeLabApp` на `CodeLabTestBinding(onboarding:)`), как `codelab_app_
// onboarding_test.dart`; порты документов — двойники `LegalFixture`.
//
// Контракт панели (принят при реализации 6.6), сверх design.md:
// - ключи: `onboarding-privacy-policy`, `onboarding-terms-of-use` (ссылки на
//   шаге), `onboarding-document` (панель поверх шага), `onboarding-document-back`
//   (кнопка «Back to setup»); тело панели — `LegalPage` (ключ `settings-legal`);
// - при открытии фокус на `onboarding-document-back`, при закрытии — на ссылке,
//   открывшей панель; Esc закрывает панель (`CallbackShortcuts`);
// - шаг под панелью не получает Enter и не принимает нажатий.

import 'package:codelab_desktop/app/codelab_app_widget.dart';
import 'package:codelab_desktop/app/navigation/app_destination.dart';
import 'package:codelab_desktop/app/navigation/navigation_cubit.dart';
import 'package:codelab_desktop/app/onboarding/onboarding_start.dart';
import 'package:codelab_desktop/features/onboarding/application/onboarding_cubit.dart';
import 'package:codelab_desktop/features/onboarding/application/onboarding_state.dart';
import 'package:codelab_desktop/features/onboarding/presentation/onboarding_screen.dart';
import 'package:codelab_setup/codelab_setup.dart';
import 'package:codelab_ui/codelab_ui.dart' show CodeLabShortcut;
import 'package:fluent_ui/fluent_ui.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:structured_log_flutter/structured_log_flutter.dart'
    show LogBuffer;

import '../../../support/fake_onboarding.dart';
import '../../../support/legal_fixture.dart';
import '../../../support/press_shortcut.dart';
import '../../../support/test_app_scope.dart';

Finder _key(String key) => find.byKey(ValueKey(key));

Finder _text(String value) => find.textContaining(value, findRichText: true);

Done _done() => Done(
  ProviderSetupPlan(
    providerId: 'llm',
    kind: 'openai-compatible',
    baseUrl: 'http://localhost:1234/v1',
    key: const KeepStoredSecret(),
    secretName: 'codelab/llm',
    replaceSecret: false,
    model: const PlannedModel(id: 'm1', contextWindow: 8000),
    makeDefault: true,
    target: const ConfigTarget.user(),
  ),
  const ProviderCommitted(
    saved: ConfigSaved(fingerprint: 'f', warnings: [], restartRequiredKeys: []),
    keyReplaced: false,
  ),
);

void main() {
  late FakeOnboardingPreferences preferences;
  late LegalFixture fixture;
  late CodeLabTestBinding binding;

  setUp(() {
    preferences = FakeOnboardingPreferences();
    fixture = LegalFixture();
  });

  /// Onboarding в настоящем дереве app с готовыми [readiness] и [locale].
  Future<void> pumpOnboarding(
    WidgetTester tester, {
    ProviderReadiness readiness = const NoProviderConfigured(),
    Locale locale = const Locale('en'),
  }) async {
    tester.view.physicalSize = const Size(1400, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    binding = CodeLabTestBinding(
      locale: locale,
      onboarding: const OnboardingStart(show: true),
      onboardingProbe: FakeOnboardingProbe(onboardingFacts(readiness)),
      onboardingPreferences: preferences,
      legalPorts: fixture.ports,
      externalLinkOpener: fixture.links,
    );
    await tester.pumpWidget(
      binding.bootstrap(child: const CodeLabApp(startOnLaunch: false)),
    );
    await tester.pumpAndSettle();
  }

  OnboardingCubit onboardingCubit(WidgetTester tester) =>
      BlocProvider.of<OnboardingCubit>(
        tester.element(find.byType(OnboardingScreen)),
      );

  /// Доводит onboarding до «Privacy» кнопками.
  Future<void> toPrivacy(WidgetTester tester) async {
    while (_key('onboarding-step-privacy').evaluate().isEmpty) {
      if (_key('onboarding-next').evaluate().isNotEmpty) {
        await tester.tap(_key('onboarding-next'));
      } else {
        await tester.tap(_key('onboarding-model-later'));
      }
      await tester.pumpAndSettle();
    }
  }

  List<Map<String, Object?>> events(String name) => [
    for (final entry in binding.scope.resolve<LogBuffer>().entries.value)
      if (entry['event'] == name) entry,
  ];

  /// Фокус внутри виджета с ключом [key].
  bool focusIn(String key) => find
      .ancestor(
        of: find.byElementPredicate(
          (e) => e == FocusManager.instance.primaryFocus?.context,
        ),
        matching: _key(key),
      )
      .evaluate()
      .isNotEmpty;

  testWidgets('политика внутри onboarding и возврат: назначение не меняется, '
      'сводка цела, фокус возвращается на ссылку', (tester) async {
    await pumpOnboarding(tester);
    await tester.tap(_key('onboarding-next'));
    await tester.pumpAndSettle();
    await tester.tap(_key('onboarding-next'));
    await tester.pumpAndSettle();
    onboardingCubit(tester).providerSaved(_done());
    await tester.pumpAndSettle();
    await toPrivacy(tester);

    await tester.tap(_key('onboarding-privacy-policy'));
    await tester.pumpAndSettle();

    expect(_key('onboarding-document'), findsOneWidget);
    expect(find.text('Back to setup'), findsOneWidget);
    expect(_key('settings-legal'), findsOneWidget);
    expect(_text('privacy-en-body'), findsWidgets);
    expect(fixture.reads, ['assets/legal/PRIVACY.md']);
    expect(
      binding.scope.resolve<NavigationCubit>().state,
      const OnboardingDestination(),
    );
    expect(focusIn('onboarding-document-back'), isTrue);
    expect(
      events('onboarding.document_opened').single['tab'],
      'privacy_policy',
    );

    await tester.tap(_key('onboarding-document-back'));
    await tester.pumpAndSettle();

    expect(_key('onboarding-document'), findsNothing);
    expect(_key('onboarding-step-privacy'), findsOneWidget);
    expect(focusIn('onboarding-privacy-policy'), isTrue);
    expect(
      binding.scope.resolve<NavigationCubit>().state,
      const OnboardingDestination(),
    );
    expect(
      events('onboarding.document_closed').single['tab'],
      'privacy_policy',
    );

    await tester.tap(_key('onboarding-back'));
    await tester.pumpAndSettle();
    expect(_key('onboarding-step-model'), findsOneWidget);
    expect(
      (onboardingCubit(tester).state.model as ModelSaved).summary.providerId,
      'llm',
    );
    expect(_key('onboarding-model-connected'), findsOneWidget);
  });

  testWidgets('условия на русском и Esc: TERMS.ru.md, шаг возвращён, журнал '
      'без путей', (tester) async {
    await pumpOnboarding(
      tester,
      readiness: const ProviderReady('llm/m1'),
      locale: const Locale('ru'),
    );
    await toPrivacy(tester);

    await tester.tap(_key('onboarding-terms-of-use'));
    await tester.pumpAndSettle();

    expect(_key('onboarding-document'), findsOneWidget);
    expect(_text('terms-ru-body'), findsWidgets);
    expect(fixture.reads, ['assets/legal/TERMS.ru.md']);

    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();

    expect(_key('onboarding-document'), findsNothing);
    expect(_key('onboarding-step-privacy'), findsOneWidget);
    expect(focusIn('onboarding-terms-of-use'), isTrue);
    expect(events('onboarding.document_opened').single['tab'], 'terms_of_use');
    expect(events('onboarding.document_closed'), hasLength(1));
    final dump = [
      ...events('onboarding.document_opened'),
      ...events('onboarding.document_closed'),
    ].toString();
    expect(dump, isNot(contains('assets/')));
    expect(dump, isNot(contains('TERMS')));
  });

  testWidgets('кнопки шага под документом: Enter и Cmd/Ctrl+, не завершают '
      'onboarding и не открывают настройки', (tester) async {
    await pumpOnboarding(tester, readiness: const ProviderReady('llm/m1'));
    await toPrivacy(tester);
    await tester.tap(_key('onboarding-privacy-policy'));
    await tester.pumpAndSettle();

    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await pressShortcut(tester, CodeLabShortcut.openSettings);
    await pressShortcut(tester, CodeLabShortcut.openSettings, useMeta: true);
    await tester.tap(_key('onboarding-finish'), warnIfMissed: false);
    await tester.pumpAndSettle();

    expect(preferences.marked, 0);
    expect(events('onboarding.completed'), isEmpty);
    expect(
      binding.scope.resolve<NavigationCubit>().state,
      const OnboardingDestination(),
    );
    expect(_key('onboarding-document'), findsOneWidget);
  });

  testWidgets('вторая ссылка открывает «Terms of use» на английском; панель '
      'закрывается, шаг можно завершить', (tester) async {
    await pumpOnboarding(tester, readiness: const ProviderReady('llm/m1'));
    await toPrivacy(tester);

    await tester.tap(_key('onboarding-terms-of-use'));
    await tester.pumpAndSettle();
    expect(_text('terms-en-body'), findsWidgets);
    expect(fixture.reads, ['assets/legal/TERMS.md']);
    await tester.tap(_key('onboarding-document-back'));
    await tester.pumpAndSettle();

    await tester.tap(_key('onboarding-finish'));
    await tester.pumpAndSettle();

    expect(preferences.marked, 1);
  });
}
