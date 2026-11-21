// Экран onboarding (задача 3.3 change `add-app-onboarding`; design.md D4,
// D7–D10, D12, D14; spec app-onboarding «Шаг «What CodeLab does»», «Шаг
// «Permissions»», «Шаг «Choose a model» и мастер провайдера», «Шаг
// «Privacy»», «Локализация и доступность onboarding»; артборды
// `Onboarding*.dc.html`).
//
// Красные по причине компиляции: `features/onboarding/presentation/` и
// `onboarding_wizard_opener.dart` появляются в задачах 3.4 и 3.6.
//
// Проверяется поведение (какие шаги, тексты и кнопки видны, что вызвано), а не
// пиксели. Cubit — настоящий `OnboardingCubit` на двойниках портов; мастер
// провайдера — двойник открывателя.
//
// Контракт презентации (принят при реализации 3.4), сверх design.md:
// - `OnboardingScreen({openWizard})` читает `OnboardingCubit` из `BlocProvider`;
//   `openWizard` — `OnboardingWizardOpener = Future<ProviderWizardCubit?>
//   Function({required String presetId})`: открыватель сам отправляет
//   автомату `PresetChosen(presetId)` (диалог начинается с «Base URL», D8);
// - ключи: `onboarding-screen`, `onboarding-content` (колонка до 920 px),
//   `onboarding-steps`, `onboarding-title` (на `Focus` с `focusNode`),
//   `onboarding-step-{welcome,permissions,model,privacy}`, `onboarding-back`,
//   `onboarding-next`, `onboarding-finish`, `onboarding-preset-<id>`,
//   `onboarding-model-setup`, `onboarding-model-again`, `onboarding-model-later`,
//   `onboarding-permissions-mode` (InfoBar режима), `onboarding-model-notice`
//   (InfoBar пояснения шага), `onboarding-model-wizard-hint`,
//   `onboarding-model-connected` (сводка `Saved`), `onboarding-privacy-stays`,
//   `onboarding-privacy-nothing-to-agree`;
// - «Next» на шаге модели есть только в `Saved`; до этого — «Set up later».
//
// Раздел 5 change (исправления по двойному ревью 2026-11-21; design.md
// «Решения по двойному ревью», пп. 1, 2, 4, 6; задачи 5.1, 5.5, 5.7, 5.11).
// Красные по причине компиляции и содержательно; контракт сверх design.md:
// - `OnboardingScreen({openWizard, appLogsLabel})`: подпись каталога логов app
//   приходит из composition root (`CodeLabDependencies.onboardingAppLogsLabel`),
//   а не из фактов (п. 4);
// - `OnboardingWizardOpener = Future<ProviderWizardCubit?> Function({required
//   String presetId, required EditableSettings access})`; экран передаёт
//   `OnboardingFacts.access` (п. 2);
// - `OnboardingFacts(... access: EditableSettings ...)`: доступ, по которому
//   прочитан снимок (у внешнего профиля `null`);
// - шаг 2 при `FactsLoading`: строка `onboarding-permissions-loading` с
//   `ProgressRing` и `Reading the agent settings…`, InfoBar режима нет (п. 1);
// - Cubit: `wizardStarted()` (возвращает `false`, если мастер открывать нельзя)
//   и `wizardEnded()`, поле `wizard: ModelWizard.idle | active` у `ModelChoose`
//   и `ModelSaved` (п. 6); кнопки навигации шага при `active` неактивны.

import 'dart:async';

import 'package:codelab_desktop/features/onboarding/application/onboarding_cubit.dart';
import 'package:codelab_desktop/features/onboarding/application/onboarding_probe.dart';
import 'package:codelab_desktop/features/onboarding/presentation/onboarding_screen.dart';
import 'package:codelab_desktop/features/settings/application/provider_wizard_cubit.dart';
import 'package:codelab_desktop/l10n/app_localizations_en.dart';
import 'package:codelab_setup/codelab_setup.dart';
import 'package:fluent_ui/fluent_ui.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../../support/app_strings.dart';
import '../../../support/fake_onboarding.dart';
import '../../../support/fake_provider_settings.dart';
import '../../../support/l10n_app.dart';
import '../../../support/l10n_page_harness.dart' show expectNoEnglish;

Finder _key(String key) => find.byKey(ValueKey(key));

const _keyMissing = ProviderKeyMissing(
  providerId: 'openai',
  reference: 'secret codelab/openai',
  backend: SecretBackendInfo(id: 'file', writable: true),
);

const _keyMissingEnv = ProviderKeyMissing(
  providerId: 'openai',
  reference: 'env OPENAI_API_KEY',
  backend: SecretBackendInfo(id: 'env', writable: false),
);

const _broken = ConfigBroken([
  ConfigIssue(
    kind: ConfigIssueKind.value,
    key: 'budget.max_steps',
    source: 'config.yaml',
    message: 'must be positive',
  ),
  ConfigIssue(
    kind: ConfigIssueKind.value,
    key: 'agent.effort',
    source: 'config.yaml',
    message: 'unknown',
  ),
]);

Done _done({KeyChoice key = const KeepStoredSecret()}) => Done(
  ProviderSetupPlan(
    providerId: 'llm',
    kind: 'openai-compatible',
    baseUrl: 'http://localhost:1234/v1',
    key: key,
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
  late List<String> opened;
  late List<EditableSettings> openedAccess;
  // Затвор открывателя мастера: тест держит открытие «в полёте» (п. 6).
  Completer<ProviderWizardCubit?>? openGate;
  late int finished;
  late OnboardingCubit cubit;
  ProviderWizardCubit? wizardToReturn;

  setUp(() {
    preferences = FakeOnboardingPreferences();
    opened = [];
    openedAccess = [];
    openGate = null;
    finished = 0;
    wizardToReturn = null;
    final view = TestWidgetsFlutterBinding.ensureInitialized()
        .platformDispatcher
        .views
        .single;
    view.physicalSize = const Size(1400, 1000);
    view.devicePixelRatio = 1.0;
    addTearDown(view.resetPhysicalSize);
    addTearDown(view.resetDevicePixelRatio);
  });

  /// Экран на настоящем Cubit-е; факты — двойник порта.
  Future<void> pump(
    WidgetTester tester,
    FakeOnboardingProbe probe, {
    Locale locale = const Locale('en'),
  }) async {
    cubit = OnboardingCubit(
      probe: probe,
      preferences: preferences,
      onFinished: () => finished++,
    );
    // Повторный `close()` в teardown fake-async зоны не завершается: тест,
    // который закрыл Cubit сам, второй раз его не закрывает.
    addTearDown(() => cubit.isClosed ? Future<void>.value() : cubit.close());
    await tester.pumpWidget(
      localizedFluentApp(
        BlocProvider<OnboardingCubit>.value(
          value: cubit,
          child: OnboardingScreen(
            appLogsLabel: fakeLogsLabel,
            openWizard: ({required String presetId, required access}) async {
              opened.add(presetId);
              openedAccess.add(access);
              final gate = openGate;
              return gate != null ? gate.future : wizardToReturn;
            },
          ),
        ),
        locale: locale,
      ),
    );
    await tester.pumpAndSettle();
  }

  FakeOnboardingProbe probeOf(
    ProviderReadiness readiness, {
    String backend = 'env',
    String mode = 'standard',
  }) => FakeOnboardingProbe(
    onboardingFacts(readiness, backend: backend, mode: mode),
  );

  Future<void> tapKey(WidgetTester tester, String key) async {
    await tester.ensureVisible(_key(key));
    await tester.tap(_key(key));
    await tester.pumpAndSettle();
  }

  Future<void> toStep(WidgetTester tester, String step) async {
    for (
      var i = 0;
      i < 4 && _key('onboarding-step-$step').evaluate().isEmpty;
      i++
    ) {
      if (_key('onboarding-next').evaluate().isNotEmpty) {
        await tapKey(tester, 'onboarding-next');
      } else {
        await tapKey(tester, 'onboarding-model-later');
      }
    }
    expect(_key('onboarding-step-$step'), findsOneWidget);
  }

  Finder inKey(String key, String text) => find.descendant(
    of: _key(key),
    matching: find.textContaining(text, findRichText: true),
  );

  group('шаг «What CodeLab does»', () {
    testWidgets('заголовок, четыре карточки, подсказка и строка шагов', (
      tester,
    ) async {
      await pump(tester, probeOf(const NoProviderConfigured()));

      expect(_key('onboarding-step-welcome'), findsOneWidget);
      expect(
        find.text('An AI coding agent that works in your project'),
        findsOneWidget,
      );
      for (final card in [
        'Works in one project folder',
        'You approve the changes',
        'Your model, your key',
        'The agent runs inside the app',
        'Built-in',
      ]) {
        expect(find.text(card), findsOneWidget, reason: card);
      }
      expect(
        find.text(
          'Setup takes four short steps. You can change every choice later '
          'in Settings.',
        ),
        findsOneWidget,
      );
      // Строка шагов со всеми четырьмя подписями (D12).
      for (final label in [
        'What CodeLab does',
        'Permissions',
        'Choose a model',
        'Privacy',
      ]) {
        expect(
          find.descendant(
            of: _key('onboarding-steps'),
            matching: find.text(label),
          ),
          findsOneWidget,
          reason: label,
        );
      }
      expect(_key('onboarding-back'), findsNothing);
      expect(_key('onboarding-next'), findsOneWidget);
    });

    testWidgets('нет обещания связки ключей при бэкенде env (D9)', (
      tester,
    ) async {
      await pump(tester, probeOf(const NoProviderConfigured()));

      expect(
        find.textContaining(
          'keychain',
          findRichText: true,
          skipOffstage: false,
        ),
        findsNothing,
      );
      expect(
        find.textContaining('The key stays on this computer.'),
        findsOneWidget,
      );
    });
  });

  group('шаг «Permissions»', () {
    testWidgets('таблица режима standard и InfoBar по умолчанию (Q6, D7)', (
      tester,
    ) async {
      await pump(tester, probeOf(const NoProviderConfigured()));
      await toStep(tester, 'permissions');

      expect(
        find.text('The agent asks before it changes anything'),
        findsOneWidget,
      );
      for (final row in [
        'Read files in the project',
        'Edit and create files',
        'Run commands',
        'Anything outside the project folder',
      ]) {
        expect(find.text(row), findsOneWidget, reason: row);
      }
      expect(find.text('No prompt'), findsOneWidget);
      expect(find.text('Asks each time'), findsNWidgets(2));
      expect(find.text('Blocked'), findsOneWidget);
      expect(
        inKey(
          'onboarding-permissions-mode',
          'New sessions start in standard mode',
        ),
        findsOneWidget,
      );
      expect(
        inKey('onboarding-permissions-mode', 'Settings › Agents & modes'),
        findsOneWidget,
      );
      expect(_key('onboarding-back'), findsOneWidget);
    });

    testWidgets('режим из общего с CLI конфига называется честно (Q6)', (
      tester,
    ) async {
      await pump(tester, probeOf(const NoProviderConfigured(), mode: 'bypass'));
      await toStep(tester, 'permissions');

      expect(
        inKey(
          'onboarding-permissions-mode',
          'New sessions start in bypass mode',
        ),
        findsOneWidget,
      );
      expect(
        inKey(
          'onboarding-permissions-mode',
          'the table above describes standard mode',
        ),
        findsOneWidget,
      );
      expect(
        inKey('onboarding-permissions-mode', 'Settings › Agents & modes'),
        findsOneWidget,
      );
    });

    testWidgets('внешний профиль по умолчанию', (tester) async {
      await pump(tester, FakeOnboardingProbe(onboardingExternalFacts));
      await toStep(tester, 'permissions');

      expect(
        inKey(
          'onboarding-permissions-mode',
          'Your default connection is an external agent. It applies its own '
              'rules; approvals still appear in the conversation.',
        ),
        findsOneWidget,
      );
    });

    testWidgets('настройки не прочитаны: нейтральный текст, режим standard не '
        'утверждается (п. 1)', (tester) async {
      await pump(tester, FakeOnboardingProbe.failing(StateError('x')));
      await toStep(tester, 'permissions');

      expect(
        inKey(
          'onboarding-permissions-mode',
          'Agent settings could not be read. The mode for new sessions is '
              'shown in Settings › Agents & modes.',
        ),
        findsOneWidget,
      );
      expect(
        find.textContaining('New sessions start in standard mode'),
        findsNothing,
      );
    });

    testWidgets('настройки ещё читаются: индикатор вместо InfoBar режима, '
        'после чтения — InfoBar по действующему режиму (п. 1)', (tester) async {
      final probe = _GatedProbe();
      cubit = OnboardingCubit(
        probe: probe,
        preferences: preferences,
        onFinished: () => finished++,
      );
      addTearDown(cubit.close);
      await tester.pumpWidget(
        localizedFluentApp(
          BlocProvider<OnboardingCubit>.value(
            value: cubit,
            child: OnboardingScreen(
              appLogsLabel: fakeLogsLabel,
              openWizard: ({required presetId, required access}) async => null,
            ),
          ),
        ),
      );
      // Индикатор крутится бесконечно: `pumpAndSettle` здесь завис бы.
      await tester.pump(const Duration(milliseconds: 100));
      await tester.tap(_key('onboarding-next'));
      await tester.pump(const Duration(milliseconds: 100));
      expect(_key('onboarding-step-permissions'), findsOneWidget);

      expect(_key('onboarding-permissions-mode'), findsNothing);
      expect(
        find.descendant(
          of: _key('onboarding-permissions-loading'),
          matching: find.text('Reading the agent settings…'),
        ),
        findsOneWidget,
      );
      expect(
        find.descendant(
          of: _key('onboarding-permissions-loading'),
          matching: find.byType(ProgressRing),
        ),
        findsOneWidget,
      );
      expect(
        find.textContaining('New sessions start in'),
        findsNothing,
        reason: 'режим до чтения фактов не называется',
      );

      probe.gate.complete(onboardingFacts(const NoProviderConfigured()));
      await tester.pump(const Duration(milliseconds: 100));
      await tester.pump(const Duration(milliseconds: 100));

      expect(_key('onboarding-permissions-loading'), findsNothing);
      expect(
        inKey(
          'onboarding-permissions-mode',
          'New sessions start in standard mode',
        ),
        findsOneWidget,
      );
    });
  });

  group('шаг «Choose a model»', () {
    testWidgets('карточки пресетов мастера с подписями; «Set up» ждёт выбора', (
      tester,
    ) async {
      await pump(tester, probeOf(const NoProviderConfigured()));
      await toStep(tester, 'model');

      final l10n = AppLocalizationsEn();
      expect(find.text('Choose where the model runs'), findsOneWidget);
      for (final preset in ProviderPresets.all) {
        expect(
          _key('onboarding-preset-${preset.id}'),
          findsOneWidget,
          reason: preset.id,
        );
        expect(
          find.descendant(
            of: _key('onboarding-preset-${preset.id}'),
            matching: find.text(wizardPresetLabel(l10n, preset)),
          ),
          findsOneWidget,
          reason: preset.id,
        );
      }
      expect(
        inKey('onboarding-preset-openai', 'api.openai.com · key'),
        findsOneWidget,
      );
      expect(
        inKey('onboarding-preset-ollama', 'Local, no key'),
        findsOneWidget,
      );
      expect(
        inKey(
          'onboarding-preset-custom-openai',
          'Your server URL, optional key',
        ),
        findsOneWidget,
      );
      expect(_key('onboarding-model-later'), findsOneWidget);
      expect(_key('onboarding-next'), findsNothing);

      // Без выбранной карточки кнопка мастера ничего не открывает.
      await tester.tap(_key('onboarding-model-setup'));
      await tester.pumpAndSettle();
      expect(opened, isEmpty);

      await tapKey(tester, 'onboarding-preset-anthropic');
      expect(find.text('Set up Anthropic…'), findsOneWidget);
      await tapKey(tester, 'onboarding-model-setup');
      expect(opened, ['anthropic']);
    });

    testWidgets('только переменная окружения: InfoBar мастера (D9)', (
      tester,
    ) async {
      await pump(tester, probeOf(const NoProviderConfigured()));
      await toStep(tester, 'model');

      expect(
        inKey(
          'onboarding-model-wizard-hint',
          'The key is read from an environment variable.',
        ),
        findsOneWidget,
      );
      expect(
        inKey('onboarding-model-wizard-hint', 'is stored in'),
        findsNothing,
      );
    });

    testWidgets('записываемый бэкенд: InfoBar называет его id (D9)', (
      tester,
    ) async {
      await pump(
        tester,
        probeOf(const NoProviderConfigured(), backend: 'file'),
      );
      await toStep(tester, 'model');

      expect(
        inKey(
          'onboarding-model-wizard-hint',
          'The key is stored in file or read from an environment variable.',
        ),
        findsOneWidget,
      );
    });

    testWidgets('ключ не найден: InfoBar с id и именем секрета, карточки '
        'доступны', (tester) async {
      await pump(tester, probeOf(_keyMissing, backend: 'file'));
      await toStep(tester, 'model');

      for (final part in [
        'openai',
        'codelab/openai',
        'file',
        'Settings › Providers › Edit',
      ]) {
        expect(
          inKey('onboarding-model-notice', part),
          findsOneWidget,
          reason: part,
        );
      }
      await tapKey(tester, 'onboarding-preset-ollama');
      await tapKey(tester, 'onboarding-model-setup');
      expect(opened, ['ollama']);
    });

    testWidgets('ключ из переменной не найден: InfoBar называет переменную', (
      tester,
    ) async {
      await pump(tester, probeOf(_keyMissingEnv));
      await toStep(tester, 'model');

      expect(
        inKey('onboarding-model-notice', 'reads its key from OPENAI_API_KEY'),
        findsOneWidget,
      );
      expect(
        inKey(
          'onboarding-model-notice',
          'is not set where CodeLab was started',
        ),
        findsOneWidget,
      );
    });

    testWidgets('битый конфиг: подсказка config check, мастер недоступен, '
        '«Set up later» работает', (tester) async {
      await pump(tester, probeOf(_broken));
      await toStep(tester, 'model');

      expect(
        inKey('onboarding-model-notice', 'has 2 problems'),
        findsOneWidget,
      );
      expect(
        inKey('onboarding-model-notice', 'codelab config check'),
        findsOneWidget,
      );
      await tester.tap(_key('onboarding-preset-openai'));
      await tester.pumpAndSettle();
      await tester.tap(_key('onboarding-model-setup'));
      await tester.pumpAndSettle();
      expect(opened, isEmpty, reason: 'мастер не пишет поверх битого файла');

      await tapKey(tester, 'onboarding-model-later');
      expect(_key('onboarding-step-privacy'), findsOneWidget);
    });

    testWidgets('сбой чтения фактов: пояснение, мастер недоступен', (
      tester,
    ) async {
      await pump(tester, FakeOnboardingProbe.failing(StateError('x')));
      await toStep(tester, 'model');

      expect(
        inKey(
          'onboarding-model-notice',
          'Agent settings could not be read. You can set up a provider later '
              'in Settings › Providers.',
        ),
        findsOneWidget,
      );
      await tester.tap(_key('onboarding-preset-openai'));
      await tester.pumpAndSettle();
      await tester.tap(_key('onboarding-model-setup'));
      await tester.pumpAndSettle();
      expect(opened, isEmpty);
    });

    testWidgets('«Set up later» ведёт на «Privacy» без записи', (tester) async {
      await pump(tester, probeOf(const NoProviderConfigured()));
      await toStep(tester, 'model');

      await tapKey(tester, 'onboarding-model-later');

      expect(_key('onboarding-step-privacy'), findsOneWidget);
      expect(preferences.marked, 0);
    });

    testWidgets('после сохранения: «is connected», модель, где ключ, '
        '«Set up again…» и «Next»', (tester) async {
      await pump(
        tester,
        probeOf(const NoProviderConfigured(), backend: 'file'),
      );
      await toStep(tester, 'model');

      cubit.providerSaved(_done());
      await tester.pumpAndSettle();

      expect(
        inKey('onboarding-model-connected', 'llm is connected'),
        findsOneWidget,
      );
      expect(inKey('onboarding-model-connected', 'llm/m1'), findsOneWidget);
      expect(
        inKey('onboarding-model-connected', 'codelab/llm'),
        findsOneWidget,
      );
      expect(inKey('onboarding-model-connected', 'file'), findsOneWidget);
      expect(_key('onboarding-model-again'), findsOneWidget);
      expect(_key('onboarding-model-later'), findsNothing);

      await tapKey(tester, 'onboarding-next');
      expect(_key('onboarding-step-privacy'), findsOneWidget);
    });

    testWidgets('способ хранения ключа в сводке: переменная и без ключа', (
      tester,
    ) async {
      await pump(tester, probeOf(const NoProviderConfigured()));
      await toStep(tester, 'model');

      cubit.providerSaved(_done(key: const UseEnvVar('LLM_KEY')));
      await tester.pumpAndSettle();
      expect(inKey('onboarding-model-connected', 'LLM_KEY'), findsOneWidget);

      cubit.providerSaved(_done(key: const NoKey()));
      await tester.pumpAndSettle();
      expect(inKey('onboarding-model-connected', 'No key'), findsOneWidget);
    });

    testWidgets(
      'отмена мастера: шаг как был, «Next» нет, «Set up later» есть',
      (tester) async {
        final store = FakeAgentConfigStore();
        final session = FakeProviderSettingsSession(store);
        final flow = (await tester.runAsync(
          () => session.openWizard(
            forceDefault: true,
            entry: ProviderWizardEntry.onboarding,
          ),
        ))!;
        wizardToReturn = ProviderWizardCubit(
          strings: FixedAppStrings(AppLocalizationsEn()),
          flow: flow,
          access: session.access,
          backendId: store.backend.id,
          forceDefault: true,
          isAgentConnected: () => false,
        )..dispatch(const PresetChosen('anthropic'));
        addTearDown(wizardToReturn!.close);
        await pump(
          tester,
          probeOf(const NoProviderConfigured(), backend: 'file'),
        );
        await toStep(tester, 'model');
        await tapKey(tester, 'onboarding-preset-anthropic');

        await tester.tap(_key('onboarding-model-setup'));
        await tester.pump(const Duration(milliseconds: 300));
        await tester.pump(const Duration(milliseconds: 300));

        // Диалог начался с «Base URL», а не с выбора типа.
        expect(_key('provider-wizard-base-url-field'), findsOneWidget);
        await tester.tap(_key('provider-wizard-cancel'));
        await tester.pumpAndSettle();

        expect(_key('onboarding-step-model'), findsOneWidget);
        expect(_key('onboarding-next'), findsNothing);
        expect(_key('onboarding-model-later'), findsOneWidget);
        expect(store.applied, isEmpty);
      },
    );
  });

  group('шаг «Privacy»', () {
    testWidgets('строки сети и «Nothing to agree to» без ссылок на документы '
        '(D10, Q4)', (tester) async {
      await pump(tester, probeOf(const ProviderReady('llm/m1')));
      await toStep(tester, 'privacy');

      expect(find.text('What leaves this computer'), findsOneWidget);
      expect(
        find.text(
          'Only what the agent needs for the work you ask for, and only to '
          'services you set up. CodeLab itself collects nothing.',
        ),
        findsOneWidget,
      );
      for (final row in [
        'Your model provider',
        'Every turn',
        'MCP servers and web tools',
        'When used',
        'Telemetry, crash reports, usage analytics',
        'Never',
        'Stays here',
        'Local',
      ]) {
        expect(find.text(row), findsOneWidget, reason: row);
      }
      expect(
        inKey('onboarding-privacy-nothing-to-agree', 'Nothing to agree to'),
        findsOneWidget,
      );
      // Ссылок на документы и согласия нет (SETUP-17, D-29).
      expect(
        find.textContaining('privacy policy', findRichText: true),
        findsNothing,
      );
      expect(
        find.textContaining('Terms of use', findRichText: true),
        findsNothing,
      );
      expect(
        find.textContaining('Settings › Legal', findRichText: true),
        findsNothing,
      );
      expect(find.byType(Checkbox), findsNothing);
      expect(find.byType(ToggleSwitch), findsNothing);
      expect(_key('onboarding-next'), findsNothing);
      expect(_key('onboarding-finish'), findsOneWidget);
      expect(find.text('Start using CodeLab'), findsOneWidget);
    });

    testWidgets('ключи из переменных окружения: без слова keychain (D9)', (
      tester,
    ) async {
      await pump(tester, probeOf(const ProviderReady('llm/m1')));
      await toStep(tester, 'privacy');

      for (final part in [
        '~/.codelab',
        fakeLogsLabel,
        'API keys are read from environment variables',
      ]) {
        expect(
          inKey('onboarding-privacy-stays', part),
          findsOneWidget,
          reason: part,
        );
      }
      expect(find.textContaining('keychain', findRichText: true), findsNothing);
    });

    testWidgets('ключи в файле: secrets.yaml и unencrypted', (tester) async {
      await pump(
        tester,
        probeOf(const ProviderReady('llm/m1'), backend: 'file'),
      );
      await toStep(tester, 'privacy');

      expect(inKey('onboarding-privacy-stays', 'secrets.yaml'), findsOneWidget);
      expect(inKey('onboarding-privacy-stays', 'unencrypted'), findsOneWidget);
    });

    testWidgets('внешний профиль называет каталог логов', (tester) async {
      await pump(tester, FakeOnboardingProbe(onboardingExternalFacts));
      await toStep(tester, 'privacy');
      expect(
        inKey('onboarding-privacy-stays', 'managed by that agent'),
        findsOneWidget,
      );
      expect(inKey('onboarding-privacy-stays', fakeLogsLabel), findsOneWidget);
    });

    testWidgets('факты недоступны: каталог логов app из composition root есть, '
        'пути CODELAB_HOME нет (п. 4, D9)', (tester) async {
      await pump(tester, FakeOnboardingProbe.failing(StateError('x')));
      await toStep(tester, 'privacy');

      expect(inKey('onboarding-privacy-stays', fakeLogsLabel), findsOneWidget);
      expect(
        inKey(
          'onboarding-privacy-stays',
          "the agent's config and keys stay on this computer",
        ),
        findsOneWidget,
      );
      expect(inKey('onboarding-privacy-stays', '~/.codelab'), findsNothing);
    });

    testWidgets('«Start using CodeLab» пишет флаг и завершает onboarding', (
      tester,
    ) async {
      await pump(tester, probeOf(const ProviderReady('llm/m1')));
      await toStep(tester, 'privacy');

      await tester.tap(_key('onboarding-finish'));
      await tester.pumpAndSettle();

      expect(preferences.marked, 1);
      expect(finished, 1);
    });
  });

  group('локализация и доступность (D14)', () {
    testWidgets('русский интерфейс: тексты из ARB ru, пути и id без '
        'перевода', (tester) async {
      await pump(
        tester,
        probeOf(const ProviderReady('llm/m1'), backend: 'file'),
        locale: const Locale('ru'),
      );
      await toStep(tester, 'privacy');

      expectNoEnglish([
        'What leaves this computer',
        'Start using CodeLab',
        'Nothing to agree to',
        'Every turn',
        'Choose a model',
        'What CodeLab does',
      ]);
      expect(inKey('onboarding-privacy-stays', 'secrets.yaml'), findsOneWidget);
      expect(inKey('onboarding-privacy-stays', '~/.codelab'), findsOneWidget);
    });

    testWidgets('при показе шага фокус на его заголовке', (tester) async {
      await pump(tester, probeOf(const NoProviderConfigured()));
      Focus title() => tester.widget<Focus>(_key('onboarding-title'));

      expect(title().focusNode!.hasPrimaryFocus, isTrue);
      await tapKey(tester, 'onboarding-next');
      expect(_key('onboarding-step-permissions'), findsOneWidget);
      expect(title().focusNode!.hasPrimaryFocus, isTrue);
    });

    testWidgets('Esc не закрывает onboarding и не меняет шаг', (tester) async {
      await pump(tester, probeOf(const NoProviderConfigured()));
      await toStep(tester, 'permissions');

      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pumpAndSettle();

      expect(_key('onboarding-step-permissions'), findsOneWidget);
      expect(find.byType(OnboardingScreen), findsOneWidget);
    });

    testWidgets('контент не шире 920 px', (tester) async {
      await pump(tester, probeOf(const NoProviderConfigured()));

      expect(
        tester.getSize(_key('onboarding-content')).width,
        lessThanOrEqualTo(920),
      );
    });

    testWidgets('узкое окно 760 × 600: прокрутка, кнопки достижимы, '
        'переполнения нет', (tester) async {
      final view = tester.view;
      view.physicalSize = const Size(760, 600);
      await pump(tester, probeOf(const NoProviderConfigured()));
      await toStep(tester, 'model');

      expect(tester.takeException(), isNull);
      await tester.ensureVisible(_key('onboarding-model-later'));
      await tester.ensureVisible(_key('onboarding-back'));
      expect(tester.takeException(), isNull);
      await tapKey(tester, 'onboarding-model-later');
      expect(_key('onboarding-step-privacy'), findsOneWidget);
    });
  });

  group('мастер: доступ из фактов и навигация шага (п. 2, 6)', () {
    /// Cubit мастера на двойнике сессии: диалог начинается с «Base URL».
    Future<(ProviderWizardCubit, FakeAgentConfigStore)> makeWizard(
      WidgetTester tester, {
      bool spy = false,
    }) async {
      final store = FakeAgentConfigStore();
      final session = FakeProviderSettingsSession(store);
      final flow = (await tester.runAsync(
        () => session.openWizard(
          forceDefault: true,
          entry: ProviderWizardEntry.onboarding,
        ),
      ))!;
      final strings = FixedAppStrings(AppLocalizationsEn());
      final wizard = spy
          ? _SpyWizard(
              strings: strings,
              flow: flow,
              access: session.access,
              backendId: store.backend.id,
            )
          : ProviderWizardCubit(
              strings: strings,
              flow: flow,
              access: session.access,
              backendId: store.backend.id,
              forceDefault: true,
              isAgentConnected: () => false,
            );
      wizard.dispatch(const PresetChosen('anthropic'));
      // Шпион не закрывается по-настоящему: закрытие настоящего мастера ждёт
      // реальные Future и в fake-async зоне виджет-теста не завершается.
      if (!spy) {
        addTearDown(wizard.close);
      }
      return (wizard, store);
    }

    testWidgets('экран передаёт открывателю доступ из фактов', (tester) async {
      final access = EditableSettings(
        const ConfigPaths(codelabHome: '/agent-home'),
      );
      await pump(
        tester,
        FakeOnboardingProbe(
          OnboardingFacts(
            readiness: const NoProviderConfigured(),
            access: access,
            backendId: 'file',
            backendWritable: true,
            mode: 'standard',
            homeLabel: '/agent-home',
          ),
        ),
      );
      await toStep(tester, 'model');
      await tapKey(tester, 'onboarding-preset-openai');

      await tapKey(tester, 'onboarding-model-setup');

      expect(opened, ['openai']);
      expect(openedAccess.single, same(access));
    });

    testWidgets('пока мастер открывается: Back, «Set up later» и повторное '
        '«Set up…» не действуют; после диалога навигация снова работает', (
      tester,
    ) async {
      final (wizard, store) = await makeWizard(tester);
      openGate = Completer<ProviderWizardCubit?>();
      await pump(
        tester,
        probeOf(const NoProviderConfigured(), backend: 'file'),
      );
      await toStep(tester, 'model');
      await tapKey(tester, 'onboarding-preset-anthropic');

      await tapKey(tester, 'onboarding-model-setup');
      await tapKey(tester, 'onboarding-model-later');
      await tapKey(tester, 'onboarding-back');
      await tapKey(tester, 'onboarding-model-setup');

      expect(_key('onboarding-step-model'), findsOneWidget);
      expect(opened, hasLength(1), reason: 'повторное «Set up…» игнорируется');

      openGate!.complete(wizard);
      await tester.pump(const Duration(milliseconds: 300));
      await tester.pump(const Duration(milliseconds: 300));
      expect(_key('provider-wizard-base-url-field'), findsOneWidget);
      await tester.tap(_key('provider-wizard-cancel'));
      await tester.pumpAndSettle();

      expect(_key('onboarding-step-model'), findsOneWidget);
      expect(store.applied, isEmpty);
      await tapKey(tester, 'onboarding-model-later');
      expect(_key('onboarding-step-privacy'), findsOneWidget);
    });

    testWidgets('открыватель вернул мастер после закрытия onboarding: диалога '
        'нет, Cubit мастера закрыт, конфиг не тронут', (tester) async {
      final (wizard, store) = await makeWizard(tester, spy: true);
      openGate = Completer<ProviderWizardCubit?>();
      await pump(
        tester,
        probeOf(const NoProviderConfigured(), backend: 'file'),
      );
      await toStep(tester, 'model');
      await tapKey(tester, 'onboarding-preset-anthropic');
      await tapKey(tester, 'onboarding-model-setup');

      await cubit.close();
      openGate!.complete(wizard);
      await tester.pump(const Duration(milliseconds: 300));
      await tester.pump(const Duration(milliseconds: 300));

      expect(_key('provider-wizard-base-url-field'), findsNothing);
      expect(
        (wizard as _SpyWizard).closeCalls,
        1,
        reason: 'экран закрывает ненужный мастер',
      );
      expect(store.applied, isEmpty);
    });
  });
}

/// Порт фактов, чей итог тест отдаёт сам: шаг «Permissions» ждёт чтения.
final class _GatedProbe implements OnboardingProbe {
  final gate = Completer<OnboardingFacts>();

  @override
  Future<OnboardingFacts> read() => gate.future;
}

/// Мастер, который считает вызовы `close()` и не закрывается по-настоящему:
/// тест проверяет, что экран закрывает ненужный мастер (ревью 2026-11-21,
/// п. 6), а не поведение закрытия.
final class _SpyWizard extends ProviderWizardCubit {
  _SpyWizard({
    required super.strings,
    required super.flow,
    required super.access,
    required super.backendId,
  }) : super(forceDefault: true, isAgentConnected: _never);

  static bool _never() => false;

  var closeCalls = 0;

  @override
  // ignore: must_call_super, шпион намеренно не закрывает настоящий мастер
  Future<void> close() async {
    closeCalls++;
  }
}
