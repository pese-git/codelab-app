// `ProviderWizardDialog` (задача 3.4 change `add-provider-setup-ui`; spec
// app-settings «Мастер провайдера в app», сценарии «Провайдер с ключом в
// хранилище», «Только переменная при read-only бэкенде», «Отказ проверки по
// ключу», «Esc во время проверки»; design.md D7 «Шаги диалога app и ключи»,
// D21, D24; артборд `Wizard`).
//
// Проверяется поведение (какие шаги и кнопки видны, что послано автомату,
// что заблокировано), а не пиксели. Автомат, конфиг, ключи и проверка —
// двойники; их порядок записи проверяет мост.

import 'dart:async';

import 'package:codelab_desktop/features/settings/application/provider_wizard_cubit.dart';
import 'package:codelab_desktop/features/settings/presentation/provider_wizard_dialog.dart';
import 'package:codelab_setup/codelab_setup.dart';
import 'package:codelab_ui/codelab_ui.dart';
import 'package:fluent_ui/fluent_ui.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../../support/fake_provider_settings.dart';
import '../../../support/recording_logger.dart';

Finder _key(String key) => find.byKey(ValueKey(key));

Map<String, Object?> _existing() => {
  'agent': {'default_model': 'local/qwen'},
  'providers': {
    'local': providerMap(
      baseUrl: 'http://localhost:11434/v1',
      models: ['qwen'],
    ),
  },
};

void main() {
  late FakeAgentConfigStore store;
  late FakeProviderSettingsSession session;
  late RecordingLogger log;
  late ProviderWizardCubit cubit;
  late Future<void> dialog;

  setUp(() {
    final view = TestWidgetsFlutterBinding.ensureInitialized()
        .platformDispatcher
        .views
        .single;
    view.physicalSize = const Size(1440, 1400);
    view.devicePixelRatio = 1.0;
    addTearDown(view.resetPhysicalSize);
    addTearDown(view.resetDevicePixelRatio);
    store = FakeAgentConfigStore(user: _existing());
    session = FakeProviderSettingsSession(store);
    log = RecordingLogger();
  });

  Future<void> frames(WidgetTester tester, [int n = 8]) async {
    for (var i = 0; i < n; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
  }

  Future<void> open(
    WidgetTester tester, {
    ProviderEntryView? editing,
    bool forceDefault = false,
    EditableSettings? access,
  }) async {
    if (access != null) {
      session.access = access;
    }
    final flow = (await tester.runAsync(
      () => session.openWizard(editing: editing, forceDefault: forceDefault),
    ))!;
    cubit = ProviderWizardCubit(
      flow: flow,
      access: session.access,
      backendId: store.backend.id,
      editingId: editing?.id,
      forceDefault: forceDefault,
      isAgentConnected: () => true,
    );
    addTearDown(cubit.close);
    await tester.pumpWidget(
      FluentApp(
        home: Builder(
          builder: (context) => Center(
            child: Button(
              key: const ValueKey('open'),
              onPressed: () =>
                  dialog = showProviderWizardDialog(context, cubit),
              child: const Text('open'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(_key('open'));
    await frames(tester);
  }

  Future<void> next(WidgetTester tester) async {
    await tester.tap(_key('provider-wizard-next'));
    await frames(tester);
  }

  /// Выбирает custom-пресет и вводит адрес.
  Future<void> toKeyStep(WidgetTester tester) async {
    await tester.tap(_key('provider-wizard-preset-custom-openai'));
    await frames(tester, 2);
    await next(tester);
    await tester.enterText(
      _key('provider-wizard-base-url-field'),
      'https://llm.example/v1',
    );
    await next(tester);
  }

  /// Ключ вводит «пользователь»: до проверки.
  Future<void> toCheckStep(WidgetTester tester) async {
    await toKeyStep(tester);
    await tester.tap(_key('provider-wizard-key-store'));
    await frames(tester, 2);
    await tester.enterText(_key('provider-wizard-key-field'), leakMarker);
    await next(tester);
  }

  Future<void> toReview(WidgetTester tester) async {
    await toCheckStep(tester);
    session.wizardCheck.respond(
      const CheckOk([RemoteModel('m1', contextWindow: 8000)]),
    );
    await frames(tester);
    await tester.tap(_key('provider-wizard-model-m1'));
    await frames(tester);
  }

  testWidgets('the first step shows the title, the breadcrumb and the six '
      'presets of CliSetup', (tester) async {
    await open(tester);

    expect(_key('provider-wizard'), findsOneWidget);
    expect(find.text('Add provider'), findsOneWidget);
    final breadcrumb = tester.widget<CodeLabStepBreadcrumb>(
      find.byType(CodeLabStepBreadcrumb),
    );
    expect(breadcrumb.steps, [
      'API type',
      'Base URL',
      'Key',
      'Check',
      'Model',
      'Review',
    ]);
    expect(breadcrumb.current, 0);
    expect(_key('provider-wizard-type'), findsOneWidget);
    for (final label in const [
      'OpenAI',
      'Anthropic',
      'OpenRouter',
      'Ollama (local, no key)',
      'Custom OpenAI-compatible endpoint',
      'Custom Anthropic-compatible endpoint',
    ]) {
      expect(find.text(label), findsOneWidget);
    }
    expect(_key('provider-wizard-back'), findsNothing);
    expect(_key('provider-wizard-cancel'), findsOneWidget);
    await tester.tap(_key('provider-wizard-cancel'));
    await frames(tester);
    await dialog;
  });

  testWidgets('each step keeps its key, the breadcrumb advances and the '
      'summary of passed steps appears', (tester) async {
    await open(tester);
    await tester.tap(_key('provider-wizard-preset-custom-openai'));
    await frames(tester, 2);
    await next(tester);

    expect(_key('provider-wizard-base-url'), findsOneWidget);
    expect(
      tester
          .widget<CodeLabStepBreadcrumb>(find.byType(CodeLabStepBreadcrumb))
          .current,
      1,
    );
    expect(find.text('Custom OpenAI-compatible'), findsOneWidget);

    await tester.enterText(
      _key('provider-wizard-base-url-field'),
      'https://llm.example/v1',
    );
    await next(tester);
    expect(_key('provider-wizard-key'), findsOneWidget);
    expect(find.text('https://llm.example/v1'), findsOneWidget);
    expect(_key('provider-wizard-back'), findsOneWidget);

    await tester.tap(_key('provider-wizard-back'));
    await frames(tester);
    expect(_key('provider-wizard-base-url'), findsOneWidget);
    await tester.tap(_key('provider-wizard-cancel'));
    await frames(tester);
    await dialog;
  });

  testWidgets('a base URL with a password is an error of the step; the '
      'address is not accepted', (tester) async {
    await open(tester);
    await tester.tap(_key('provider-wizard-preset-custom-openai'));
    await frames(tester, 2);
    await next(tester);
    await tester.enterText(
      _key('provider-wizard-base-url-field'),
      'https://user:pw@llm.example/v1',
    );
    await next(tester);

    expect(
      find.text('Remove the user name and password from the address.'),
      findsOneWidget,
    );
    expect(_key('provider-wizard-base-url'), findsOneWidget);
    await tester.tap(_key('provider-wizard-cancel'));
    await frames(tester);
    await dialog;
  });

  testWidgets('the key field is a hidden password box that cannot be '
      'revealed', (tester) async {
    await open(tester);
    await toKeyStep(tester);

    expect(find.text('API key source'), findsOneWidget);
    expect(find.text('Store in file as "codelab/llm-example"'), findsOneWidget);
    expect(find.text('No key'), findsOneWidget);
    await tester.tap(_key('provider-wizard-key-store'));
    await frames(tester, 2);

    final field = tester.widget<PasswordBox>(_key('provider-wizard-key-field'));
    expect(field.revealMode, PasswordRevealMode.hidden);
    await tester.tap(_key('provider-wizard-cancel'));
    await frames(tester);
    await dialog;
  });

  testWidgets('a read-only backend: no "Store in" option, the reason is '
      'shown, the variable and "No key" remain', (tester) async {
    store.backend = const SecretBackendInfo(
      id: 'env',
      writable: false,
      unavailableReason: 'Secrets are read from the environment.',
    );
    session.readOnlyHint = 'Set CODELAB_SECRET_<NAME> instead.';
    await open(tester);
    await toKeyStep(tester);

    expect(_key('provider-wizard-key-store'), findsNothing);
    expect(find.text('Set CODELAB_SECRET_<NAME> instead.'), findsOneWidget);
    expect(_key('provider-wizard-key-env'), findsOneWidget);
    expect(_key('provider-wizard-key-none'), findsOneWidget);
    await tester.tap(_key('provider-wizard-cancel'));
    await frames(tester);
    await dialog;
  });

  testWidgets('an existing secret offers "Use the stored key" and "Replace '
      'it"', (tester) async {
    session.secrets['codelab/llm-example'] = 'old-value';
    await open(tester);
    await toKeyStep(tester);

    expect(
      find.text('A stored key codelab/llm-example already exists in file.'),
      findsOneWidget,
    );
    expect(_key('provider-wizard-key-keep'), findsOneWidget);
    expect(_key('provider-wizard-key-replace'), findsOneWidget);
    await tester.tap(_key('provider-wizard-cancel'));
    await frames(tester);
    await dialog;
  });

  testWidgets('the check step shows the progress and the request address '
      'without the query', (tester) async {
    await open(tester);
    await toCheckStep(tester);

    expect(_key('provider-wizard-check'), findsOneWidget);
    expect(find.byType(ProgressRing), findsWidgets);
    expect(find.text('GET https://llm.example/v1/models'), findsOneWidget);
    expect(session.wizardCheck.calls.single.key, leakMarker);
    await tester.tap(_key('provider-wizard-cancel'));
    await frames(tester);
    await dialog;
  });

  testWidgets('401: the title, the request line, Retry and Back; no skip', (
    tester,
  ) async {
    await open(tester);
    await toCheckStep(tester);
    session.wizardCheck.respond(
      const CheckFailure(
        ProviderCheckFailure(
          kind: ProviderCheckFailureKind.unauthorized,
          message: 'x',
          statusCode: 401,
        ),
      ),
    );
    await frames(tester);

    expect(find.text('Key rejected (401)'), findsOneWidget);
    expect(
      find.textContaining('GET https://llm.example/v1/models → 401 · '),
      findsOneWidget,
    );
    expect(_key('provider-wizard-retry'), findsOneWidget);
    expect(_key('provider-wizard-back'), findsOneWidget);
    expect(_key('provider-wizard-skip-check'), findsNothing);

    await tester.tap(_key('provider-wizard-retry'));
    await frames(tester);
    expect(session.wizardCheck.calls, hasLength(2));
    await tester.tap(_key('provider-wizard-cancel'));
    await frames(tester);
    await dialog;
  });

  testWidgets('404: the explanation and the options "Use <url>/v1" and '
      '"Enter the model manually"', (tester) async {
    await open(tester);
    await toCheckStep(tester);
    session.wizardCheck.respond(
      const CheckFailure(
        ProviderCheckFailure(
          kind: ProviderCheckFailureKind.notFound,
          message: 'x',
          statusCode: 404,
        ),
      ),
    );
    await frames(tester);

    expect(find.text('Model list not found (404)'), findsOneWidget);
    expect(
      find.textContaining('OpenAI-compatible servers usually live under /v1.'),
      findsOneWidget,
    );
    expect(_key('provider-wizard-manual-model'), findsOneWidget);
    expect(_key('provider-wizard-use-v1'), findsNothing);
    await tester.tap(_key('provider-wizard-cancel'));
    await frames(tester);
    await dialog;
  });

  testWidgets('404 without /v1 offers the /v1 address and re-checks it', (
    tester,
  ) async {
    await open(tester);
    await tester.tap(_key('provider-wizard-preset-custom-openai'));
    await frames(tester, 2);
    await next(tester);
    await tester.enterText(
      _key('provider-wizard-base-url-field'),
      'https://llm.example',
    );
    await next(tester);
    await tester.tap(_key('provider-wizard-key-none'));
    await frames(tester, 2);
    await next(tester);
    session.wizardCheck.respond(
      const CheckFailure(
        ProviderCheckFailure(
          kind: ProviderCheckFailureKind.notFound,
          message: 'x',
          statusCode: 404,
        ),
      ),
    );
    await frames(tester);

    expect(find.text('Use https://llm.example/v1'), findsOneWidget);
    await tester.tap(_key('provider-wizard-use-v1'));
    await frames(tester, 2);
    await tester.tap(_key('provider-wizard-retry'));
    await frames(tester);
    expect(
      session.wizardCheck.calls.last.baseUrl.toString(),
      'https://llm.example/v1',
    );
    await tester.tap(_key('provider-wizard-cancel'));
    await frames(tester);
    await dialog;
  });

  testWidgets('unreachable: "Save without check" needs a confirmation with '
      'the warning', (tester) async {
    await open(tester);
    await toCheckStep(tester);
    session.wizardCheck.respond(
      const CheckFailure(
        ProviderCheckFailure(
          kind: ProviderCheckFailureKind.unreachable,
          message: 'x',
        ),
      ),
    );
    await frames(tester);

    expect(find.text('Server unreachable'), findsOneWidget);
    await tester.tap(_key('provider-wizard-skip-check'));
    await frames(tester, 2);
    expect(_key('provider-wizard-check'), findsOneWidget);
    expect(_key('provider-wizard-skip-confirm'), findsOneWidget);

    await tester.tap(_key('provider-wizard-skip-confirm'));
    await frames(tester);
    expect(_key('provider-wizard-model'), findsOneWidget);
    await tester.tap(_key('provider-wizard-cancel'));
    await frames(tester);
    await dialog;
  });

  testWidgets('model step: filter, pick, then Review with the summary, '
      '"Make default" and "This project only"', (tester) async {
    await open(tester);
    await toCheckStep(tester);
    session.wizardCheck.respond(
      const CheckOk([
        RemoteModel('alpha', contextWindow: 8000),
        RemoteModel('beta', contextWindow: 8000),
      ]),
    );
    await frames(tester);

    expect(_key('provider-wizard-model'), findsOneWidget);
    await tester.enterText(_key('provider-wizard-model-filter'), 'bet');
    await frames(tester, 2);
    expect(_key('provider-wizard-model-alpha'), findsNothing);
    await tester.tap(_key('provider-wizard-model-beta'));
    await frames(tester);

    expect(_key('provider-wizard-review'), findsOneWidget);
    expect(_key('provider-wizard-make-default'), findsOneWidget);
    expect(_key('provider-wizard-project-only'), findsOneWidget);
    expect(_key('provider-wizard-save'), findsOneWidget);
    expect(find.text('llm-example/beta'), findsOneWidget);
    await tester.tap(_key('provider-wizard-cancel'));
    await frames(tester);
    await dialog;
  });

  testWidgets('without a project folder there is no "This project only"', (
    tester,
  ) async {
    await open(
      tester,
      access: const EditableSettings(
        ConfigPaths(codelabHome: '/home/u/.codelab'),
      ),
    );
    await toReview(tester);

    expect(_key('provider-wizard-review'), findsOneWidget);
    expect(_key('provider-wizard-project-only'), findsNothing);
    await tester.tap(_key('provider-wizard-cancel'));
    await frames(tester);
    await dialog;
  });

  testWidgets('forceDefault: "Make default" is checked and disabled', (
    tester,
  ) async {
    store.user = {};
    await open(tester, forceDefault: true);
    await toReview(tester);

    final box = tester.widget<Checkbox>(_key('provider-wizard-make-default'));
    expect(box.checked, isTrue);
    expect(box.onChanged, isNull);
    await tester.tap(_key('provider-wizard-cancel'));
    await frames(tester);
    await dialog;
  });

  testWidgets('Edit: the title, no "This project only", starts at the '
      'address with the type marked passed', (tester) async {
    final snapshot = (await tester.runAsync(
      () => store.snapshot(cwd: '/work/app'),
    ))!;
    final entries = (await tester.runAsync(
      () => providerEntriesOf(
        snapshot,
        environment: const {},
        isSecretSet: session.isSecretSet,
      ),
    ))!;
    await open(tester, editing: entries.single);

    expect(find.text('Edit provider local'), findsOneWidget);
    expect(_key('provider-wizard-base-url'), findsOneWidget);
    expect(
      tester
          .widget<CodeLabStepBreadcrumb>(find.byType(CodeLabStepBreadcrumb))
          .current,
      1,
    );
    expect(_key('provider-wizard-back'), findsNothing);
    await tester.tap(_key('provider-wizard-cancel'));
    await frames(tester);
    await dialog;
  });

  testWidgets('the dialog keeps its height between the first steps and the '
      'check (it does not jump)', (tester) async {
    await open(tester);
    double height() => tester.getSize(_key('provider-wizard')).height;
    final preset = height();
    await tester.tap(_key('provider-wizard-preset-custom-openai'));
    await frames(tester, 2);
    await next(tester);
    final url = height();
    await tester.enterText(
      _key('provider-wizard-base-url-field'),
      'https://llm.example/v1',
    );
    await next(tester);
    await tester.tap(_key('provider-wizard-key-none'));
    await frames(tester, 2);
    await next(tester);
    final check = height();

    expect(url, preset);
    expect(check, preset);
    await tester.tap(_key('provider-wizard-cancel'));
    await frames(tester);
    await dialog;
  });

  testWidgets('Edit marks the current model in the list', (tester) async {
    final snapshot = (await tester.runAsync(
      () => store.snapshot(cwd: '/work/app'),
    ))!;
    final entries = (await tester.runAsync(
      () => providerEntriesOf(
        snapshot,
        environment: const {},
        isSecretSet: session.isSecretSet,
      ),
    ))!;
    await open(tester, editing: entries.single);
    await next(tester);
    await tester.tap(_key('provider-wizard-key-none'));
    await frames(tester, 2);
    await next(tester);
    session.wizardCheck.respond(
      const CheckOk([RemoteModel('other'), RemoteModel('qwen')]),
    );
    await frames(tester);

    expect(
      find.descendant(
        of: _key('provider-wizard-model-qwen'),
        matching: _key('provider-wizard-model-current'),
      ),
      findsOneWidget,
    );
    expect(
      find.descendant(
        of: _key('provider-wizard-model-other'),
        matching: _key('provider-wizard-model-current'),
      ),
      findsNothing,
    );
    await tester.tap(_key('provider-wizard-cancel'));
    await frames(tester);
    await dialog;
  });

  testWidgets('Saving: Cancel, Back, Save and Esc are blocked; the dialog '
      'closes itself after the result', (tester) async {
    final gate = Completer<void>();
    store.onApply = () => gate.future;
    await open(tester);
    await toReview(tester);

    await tester.tap(_key('provider-wizard-save'));
    await frames(tester);
    expect(cubit.state.setup, isA<Saving>());
    expect(
      tester.widget<CodeLabButton>(_key('provider-wizard-cancel')).onPressed,
      isNull,
    );
    expect(
      tester.widget<CodeLabButton>(_key('provider-wizard-save')).onPressed,
      isNull,
    );

    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await frames(tester);
    expect(_key('provider-wizard'), findsOneWidget);
    expect(cubit.state.setup, isA<Saving>());

    gate.complete();
    await frames(tester, 12);
    await dialog;
    expect(cubit.state.setup, isA<Done>());
    expect(_key('provider-wizard'), findsNothing);
    expect(store.applied, hasLength(1));
  });

  testWidgets('Esc while checking closes the dialog, cancels the request and '
      'writes nothing', (tester) async {
    await open(tester);
    await toCheckStep(tester);
    final call = session.wizardCheck.calls.single;

    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await frames(tester);
    await dialog;

    expect(_key('provider-wizard'), findsNothing);
    expect(call.cancel!.isCancelled, isTrue);
    session.wizardCheck.respond(const CheckOk([RemoteModel('m1')]));
    await frames(tester);
    expect(cubit.state.setup, isA<Cancelled>());
    expect(store.applied, isEmpty);
    expect(
      session.wizardLog.entries.map((e) => e['event']),
      contains('provider_wizard.check_discarded'),
    );
  });

  testWidgets('a conflict returns to Review with the banner', (tester) async {
    store.nextOutcome = const ConfigConflict(FakeAgentConfigStore.userPath);
    await open(tester);
    await toReview(tester);
    await tester.tap(_key('provider-wizard-save'));
    await frames(tester, 12);

    expect(_key('provider-wizard-review'), findsOneWidget);
    expect(
      find.text('Config changed on disk — review and save again'),
      findsOneWidget,
    );
    expect(_key('provider-wizard-save'), findsOneWidget);
    await tester.tap(_key('provider-wizard-cancel'));
    await frames(tester);
    await dialog;
  });

  testWidgets('Save again after a conflict saves; a provider that appeared '
      'meanwhile shows the typed refusal and Save is inactive', (tester) async {
    store.firstOutcome = const ConfigConflict(FakeAgentConfigStore.userPath);
    // Провайдера добавил другой процесс во время первой записи.
    store.onApply = () =>
        (store.user['providers']! as Map)['llm-example'] = providerMap();
    await open(tester);
    await toReview(tester);
    await tester.tap(_key('provider-wizard-save'));
    await frames(tester, 12);
    expect(_key('provider-wizard-review-notice'), findsOneWidget);

    await tester.tap(_key('provider-wizard-save'));
    await frames(tester, 12);

    expect(
      find.text('A provider with this id already exists.'),
      findsOneWidget,
    );
    expect(_key('provider-wizard-refusal'), findsOneWidget);
    expect(
      tester.widget<CodeLabButton>(_key('provider-wizard-save')).onPressed,
      isNull,
    );
    expect(store.applied, hasLength(1));
    await tester.tap(_key('provider-wizard-cancel'));
    await frames(tester);
    await dialog;
  });

  testWidgets('Save again after a conflict closes the dialog with Done', (
    tester,
  ) async {
    store.firstOutcome = const ConfigConflict(FakeAgentConfigStore.userPath);
    await open(tester);
    await toReview(tester);
    await tester.tap(_key('provider-wizard-save'));
    await frames(tester, 12);
    await tester.tap(_key('provider-wizard-save'));
    await frames(tester, 12);
    await dialog;

    expect(cubit.state.setup, isA<Done>());
    expect(store.applied, hasLength(2));
  });

  testWidgets('the secret marker is in no text of the dialog; the key field '
      'is cleared when the dialog goes away', (tester) async {
    await open(tester);
    await toReview(tester);
    await tester.tap(_key('provider-wizard-save'));
    await frames(tester, 12);
    await dialog;

    expect(session.secrets['codelab/llm-example'], leakMarker);
    final texts = tester
        .widgetList<Text>(find.byType(Text, skipOffstage: false))
        .map((t) => t.data ?? t.textSpan?.toPlainText() ?? '')
        .join('\n');
    expect(texts, isNot(contains(leakMarker)));
    expect(
      '${log.entries}${session.wizardLog.entries}',
      isNot(contains(leakMarker)),
    );
  });
}
