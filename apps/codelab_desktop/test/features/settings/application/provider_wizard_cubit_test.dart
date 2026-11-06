// `ProviderWizardCubit` и модель отображения мастера (задача 3.4 change
// `add-provider-setup-ui`; spec app-settings «Мастер провайдера в app»;
// design.md D7 «Шаги диалога app и ключи», D9, D18, D21).
//
// Автомат `ProviderSetupFlow` и порядок записи проверяет мост (задачи 3.1,
// 3.2); здесь — что Cubit показывает состояния автомата по таблице D7,
// блокирует Cancel/Esc в `Saving`, не пускает поздний результат проверки и
// не выпускает значение ключа за пределы автомата. Конфиг, ключи и проверка —
// двойники. Маркер `sk-test-leak-…` лежит только в «хранилище» двойника и в
// поле, которое вводит «пользователь».

import 'dart:async';

import 'package:codelab_desktop/features/settings/application/provider_wizard_cubit.dart';
import 'package:codelab_setup/codelab_setup.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../../support/fake_provider_settings.dart';
import '../../../support/recording_logger.dart';

const _home = '/home/u/.codelab';

Map<String, Object?> _existing() => {
  'agent': {'default_model': 'local/qwen'},
  'providers': {
    'local': providerMap(
      baseUrl: 'http://localhost:11434/v1',
      models: ['qwen'],
    ),
  },
};

ProviderDraft _draft() =>
    const ProviderDraft(providerId: 'x', kind: 'openai-compatible');

CheckFailed _failed(
  ProviderCheckFailureKind kind, {
  int? status,
  bool v1 = false,
}) => CheckFailed(
  _draft(),
  ProviderCheckFailure(kind: kind, message: 'm', statusCode: status),
  Uri.parse('https://llm.internal.example/models'),
  const Duration(milliseconds: 212),
  canSkip: false,
  canUseV1: v1,
);

void main() {
  late FakeAgentConfigStore store;
  late FakeProviderSettingsSession session;
  late RecordingLogger log;
  late List<ProviderWizardCubit> cubits;
  var connected = true;

  setUp(() {
    store = FakeAgentConfigStore(user: _existing());
    session = FakeProviderSettingsSession(store);
    log = RecordingLogger();
    cubits = [];
    connected = true;
  });

  tearDown(() async {
    for (final cubit in cubits) {
      await cubit.close();
    }
  });

  Future<ProviderEntryView> entryOf(String id) async {
    final snapshot = await store.snapshot(cwd: '/work/app');
    final entries = await providerEntriesOf(
      snapshot,
      environment: const {},
      isSecretSet: session.isSecretSet,
    );
    return entries.firstWhere((e) => e.id == id);
  }

  Future<ProviderWizardCubit> open({
    ProviderEntryView? editing,
    bool forceDefault = false,
    EditableSettings? access,
  }) async {
    if (access != null) {
      session.access = access;
    }
    final flow = await session.openWizard(
      editing: editing,
      forceDefault: forceDefault,
    );
    final cubit = ProviderWizardCubit(
      flow: flow,
      access: session.access,
      backendId: store.backend.id,
      editingId: editing?.id,
      forceDefault: forceDefault,
      isAgentConnected: () => connected,
    );
    cubits.add(cubit);
    return cubit;
  }

  /// Шаги до «Review» для custom-пресета: ключ вводит «пользователь».
  Future<void> walkToReview(
    ProviderWizardCubit cubit, {
    KeyChoice? key,
    bool replaceExisting = false,
  }) async {
    cubit.dispatch(const PresetChosen('custom-openai'));
    await pumpEventQueue();
    cubit.dispatch(const BaseUrlSubmitted('https://llm.example/v1'));
    await pumpEventQueue();
    cubit.dispatch(
      KeySubmitted(
        key ?? StoreSecret(SecretValue(leakMarker)),
        replaceExisting: replaceExisting,
      ),
    );
    await pumpEventQueue();
    session.wizardCheck.respond(
      const CheckOk([RemoteModel('m1', contextWindow: 8000)]),
    );
    await pumpEventQueue();
    cubit.dispatch(const ModelChosen('m1'));
    await pumpEventQueue();
  }

  group('steps and summary (D7 table)', () {
    test('every state maps to its step of the breadcrumb', () async {
      final cubit = await open();
      expect(wizardStepLabels, [
        'API type',
        'Base URL',
        'Key',
        'Check',
        'Model',
        'Review',
      ]);
      expect(cubit.state.setup, isA<ChoosingPreset>());
      expect(cubit.state.stepIndex, 0);

      cubit.dispatch(const PresetChosen('custom-openai'));
      await pumpEventQueue();
      expect(cubit.state.setup, isA<EnteringBaseUrl>());
      expect(cubit.state.stepIndex, 1);

      cubit.dispatch(const BaseUrlSubmitted('https://llm.example/v1'));
      await pumpEventQueue();
      expect(cubit.state.setup, isA<ChoosingKey>());
      expect(cubit.state.stepIndex, 2);

      cubit.dispatch(const KeySubmitted(NoKey()));
      await pumpEventQueue();
      expect(cubit.state.setup, isA<Checking>());
      expect(cubit.state.stepIndex, 3);

      session.wizardCheck.respond(
        const CheckFailure(
          ProviderCheckFailure(
            kind: ProviderCheckFailureKind.unauthorized,
            message: 'x',
            statusCode: 401,
          ),
        ),
      );
      await pumpEventQueue();
      expect(cubit.state.setup, isA<CheckFailed>());
      expect(cubit.state.stepIndex, 3);

      cubit.dispatch(const Back());
      await pumpEventQueue();
      cubit.dispatch(const KeySubmitted(NoKey()));
      await pumpEventQueue();
      session.wizardCheck.respond(const CheckOk([RemoteModel('m1')]));
      await pumpEventQueue();
      expect(cubit.state.setup, isA<ChoosingModel>());
      expect(cubit.state.stepIndex, 4);

      cubit.dispatch(const ModelChosen('m1'));
      await pumpEventQueue();
      expect(cubit.state.setup, isA<EnteringModelDetails>());
      expect(cubit.state.stepIndex, 4);

      cubit.dispatch(const ModelDetailsSubmitted(contextWindow: 4096));
      await pumpEventQueue();
      expect(cubit.state.setup, isA<Reviewing>());
      expect(cubit.state.stepIndex, 5);
    });

    test('the summary lists the passed steps only', () async {
      final cubit = await open();
      expect(cubit.state.summary, isEmpty);

      cubit.dispatch(const PresetChosen('custom-openai'));
      await pumpEventQueue();
      expect(cubit.state.summary.map((r) => r.label), ['Type']);
      expect(cubit.state.summary.single.value, 'Custom OpenAI-compatible');

      cubit.dispatch(const BaseUrlSubmitted('https://llm.example/v1?x=1#f'));
      await pumpEventQueue();
      expect(cubit.state.summary.map((r) => r.label), ['Type', 'Base URL']);
      // Query и fragment в сводку не попадают (`displayBaseUrl`, D7).
      expect(cubit.state.summary.last.value, 'https://llm.example/v1');

      cubit.dispatch(KeySubmitted(StoreSecret(SecretValue(leakMarker))));
      await pumpEventQueue();
      expect(cubit.state.summary.map((r) => r.label), [
        'Type',
        'Base URL',
        'Key',
      ]);
      expect(
        cubit.state.summary.last.value,
        'Store in file as codelab/llm-example',
      );
      expect(
        cubit.state.summary.map((r) => r.value).join(),
        isNot(contains(leakMarker)),
      );
    });

    test('the title and the editing flag follow the mode', () async {
      final add = await open();
      expect(add.title, 'Add provider');
      expect(add.editing, isFalse);

      final edit = await open(editing: await entryOf('local'));
      expect(edit.title, 'Edit provider local');
      expect(edit.editing, isTrue);
      expect(edit.state.setup, isA<EnteringBaseUrl>());
    });
  });

  group('check failure texts (Q9 (a))', () {
    test('titles follow the Wizard artboard', () {
      expect(
        checkFailureTitle(
          _failed(ProviderCheckFailureKind.unauthorized, status: 401),
        ),
        'Key rejected (401)',
      );
      expect(
        checkFailureTitle(
          _failed(ProviderCheckFailureKind.unauthorized, status: 403),
        ),
        'Key rejected (403)',
      );
      expect(
        checkFailureTitle(_failed(ProviderCheckFailureKind.unreachable)),
        'Server unreachable',
      );
      expect(
        checkFailureTitle(_failed(ProviderCheckFailureKind.timeout)),
        'Timed out after 10 s',
      );
      expect(
        checkFailureTitle(_failed(ProviderCheckFailureKind.tlsError)),
        'TLS error',
      );
      expect(
        checkFailureTitle(
          _failed(ProviderCheckFailureKind.badResponse, status: 502),
        ),
        'Unexpected response (502)',
      );
      expect(
        checkFailureTitle(
          _failed(ProviderCheckFailureKind.notFound, status: 404),
        ),
        'Model list not found (404)',
      );
    });

    test('the request line has the status only when there is one', () {
      expect(
        checkRequestLine(
          _failed(ProviderCheckFailureKind.notFound, status: 404),
        ),
        'GET https://llm.internal.example/models → 404 · 212 ms',
      );
      expect(
        checkRequestLine(_failed(ProviderCheckFailureKind.unreachable)),
        'GET https://llm.internal.example/models · 212 ms',
      );
    });

    test('only notFound has the one-line explanation', () {
      expect(
        checkFailureNote(
          _failed(ProviderCheckFailureKind.notFound, status: 404),
        ),
        'The server answered, but GET /models does not exist. '
        'OpenAI-compatible servers usually live under /v1.',
      );
      expect(
        checkFailureNote(
          _failed(ProviderCheckFailureKind.unauthorized, status: 401),
        ),
        isNull,
      );
    });
  });

  group('key step', () {
    test('a read-only backend has no "Store in" option, only the reason, the '
        'variable and "No key"', () async {
      store.backend = const SecretBackendInfo(
        id: 'env',
        writable: false,
        unavailableReason: 'Secrets are read from the environment.',
      );
      session.readOnlyHint = 'Set CODELAB_SECRET_<NAME> instead.';
      final cubit = await open();
      cubit.dispatch(const PresetChosen('custom-openai'));
      await pumpEventQueue();
      cubit.dispatch(const BaseUrlSubmitted('https://llm.example/v1'));
      await pumpEventQueue();

      final key = cubit.state.setup as ChoosingKey;
      final options = wizardKeyOptions(key);
      expect(options.map((o) => o.kind), [
        WizardKeyKind.environment,
        WizardKeyKind.none,
      ]);
      expect(key.readOnlyHint, 'Set CODELAB_SECRET_<NAME> instead.');
    });

    test('a writable backend offers the stored key first; the labels are the '
        'CliSetup words', () async {
      final cubit = await open();
      cubit.dispatch(const PresetChosen('openai'));
      await pumpEventQueue();
      cubit.dispatch(const BaseUrlSubmitted('https://api.openai.com/v1'));
      await pumpEventQueue();

      final options = wizardKeyOptions(cubit.state.setup as ChoosingKey);
      expect(options.map((o) => o.label), [
        'Store in file as "codelab/openai"',
        'Read from environment variable (OPENAI_API_KEY)',
        'No key',
      ]);
    });

    test(
      'an existing secret offers "Use the stored key" and "Replace it"',
      () async {
        session.secrets['codelab/llm-example'] = 'old-value';
        final cubit = await open();
        cubit.dispatch(const PresetChosen('custom-openai'));
        await pumpEventQueue();
        cubit.dispatch(const BaseUrlSubmitted('https://llm.example/v1'));
        await pumpEventQueue();

        final key = cubit.state.setup as ChoosingKey;
        expect(key.existingSecret, 'codelab/llm-example');
        expect(wizardKeyOptions(key).map((o) => o.kind), [
          WizardKeyKind.keepStored,
          WizardKeyKind.replace,
          WizardKeyKind.environment,
          WizardKeyKind.none,
        ]);
        expect(wizardKeyOptions(key).first.label, 'Use the stored key');
        expect(wizardKeyOptions(key)[1].label, 'Replace it');
      },
    );
  });

  group('project target and editing', () {
    test(
      '"This project only" is offered only when targets hold projectLocal',
      () async {
        final withProject = await open();
        expect(withProject.projectOnlyAvailable, isTrue);

        final without = await open(
          access: const EditableSettings(ConfigPaths(codelabHome: _home)),
        );
        expect(without.projectOnlyAvailable, isFalse);
      },
    );

    test('"This project only" writes to the project-local layer', () async {
      store.projectLocal = {};
      final cubit = await open();
      await walkToReview(cubit);
      cubit.dispatch(ReviewEdited(target: cubit.projectTarget));
      await pumpEventQueue();
      cubit.dispatch(const ConfirmSave());
      await pumpEventQueue(times: 20);

      expect(cubit.state.setup, isA<Done>());
      expect(
        store.applied.single.base.path,
        FakeAgentConfigStore.projectLocalPath,
      );
    });

    test(
      'Edit writes to the layer of the provider and has no project option',
      () async {
        final cubit = await open(editing: await entryOf('local'));
        expect(cubit.projectOnlyAvailable, isFalse);

        cubit.dispatch(const BaseUrlSubmitted('http://localhost:11434/v1'));
        await pumpEventQueue();
        cubit.dispatch(const KeySubmitted(NoKey()));
        await pumpEventQueue();
        session.wizardCheck.respond(
          const CheckOk([RemoteModel('qwen', contextWindow: 8000)]),
        );
        await pumpEventQueue();
        cubit.dispatch(const ModelChosen('qwen'));
        await pumpEventQueue();
        cubit.dispatch(const ConfirmSave());
        await pumpEventQueue(times: 20);

        expect(cubit.state.setup, isA<Done>());
        expect(store.applied.single.base.path, FakeAgentConfigStore.userPath);
      },
    );

    test('forceDefault keeps "Make default" on and locked', () async {
      store.user = {};
      final cubit = await open(forceDefault: true);
      await walkToReview(cubit);

      final plan = (cubit.state.setup as Reviewing).plan;
      expect(plan.makeDefault, isTrue);
      expect(cubit.forceDefault, isTrue);
      cubit.dispatch(const ReviewEdited(makeDefault: false));
      await pumpEventQueue();
      expect((cubit.state.setup as Reviewing).plan.makeDefault, isTrue);
    });
  });

  group('saving', () {
    test('Cancel and a second Save are ignored while Saving; the result '
        'arrives once', () async {
      final gate = Completer<void>();
      store.onApply = () => gate.future;
      final cubit = await open();
      await walkToReview(cubit);

      cubit.dispatch(const ConfirmSave());
      await pumpEventQueue();
      expect(cubit.state.setup, isA<Saving>());
      expect(cubit.canDismiss, isFalse);

      cubit.cancel();
      cubit.dispatch(const ConfirmSave());
      cubit.dispatch(const Cancel());
      await pumpEventQueue();
      expect(cubit.state.setup, isA<Saving>());

      gate.complete();
      await pumpEventQueue(times: 20);
      expect(cubit.state.setup, isA<Done>());
      expect(store.applied, hasLength(1));
      expect(cubit.canDismiss, isTrue);
    });

    test(
      'the saved banner: replaced key says "applies after Restart agent"',
      () async {
        session.secrets['codelab/llm-example'] = 'old-value';
        final cubit = await open();
        await walkToReview(
          cubit,
          key: StoreSecret(SecretValue(leakMarker)),
          replaceExisting: true,
        );
        cubit.dispatch(const ConfirmSave());
        await pumpEventQueue(times: 20);

        final banner = cubit.savedBanner!;
        expect(banner.kind, ProviderBannerKind.saved);
        expect(
          banner.text,
          'Provider llm-example saved. The new key is used after Restart agent '
          '(Settings › Connection).',
        );
        expect(banner.action, isNull);
      },
    );

    test(
      'the saved banner: without a connected agent it offers Connect',
      () async {
        connected = false;
        final cubit = await open();
        await walkToReview(cubit);
        cubit.dispatch(const ConfirmSave());
        await pumpEventQueue(times: 20);

        final banner = cubit.savedBanner!;
        expect(
          banner.text,
          'Saved. Connect to start the agent with the new provider.',
        );
        expect(banner.action, ProviderBannerAction.connect);
      },
    );

    test('the saved banner: a plain save with a running agent', () async {
      final cubit = await open();
      await walkToReview(cubit, key: const NoKey());
      cubit.dispatch(const ConfirmSave());
      await pumpEventQueue(times: 20);

      expect(cubit.savedBanner!.text, 'Provider llm-example saved.');
      expect(cubit.savedBanner!.action, isNull);
    });

    test('a conflict returns to Review with the same plan and the banner; '
        'nothing is retried', () async {
      store.nextOutcome = const ConfigConflict(FakeAgentConfigStore.userPath);
      final cubit = await open();
      await walkToReview(cubit);
      final planned = (cubit.state.setup as Reviewing).plan.providerId;

      cubit.dispatch(const ConfirmSave());
      await pumpEventQueue(times: 20);

      final setup = cubit.state.setup;
      expect(setup, isA<Reviewing>());
      expect((setup as Reviewing).plan.providerId, planned);
      expect(
        cubit.state.reviewNotice,
        'Config changed on disk — review and save again',
      );
      expect(store.applied, hasLength(1));
    });

    test('Save again after a conflict writes over the fresh file; the '
        'external edit survives and the secret is written again', () async {
      store.firstOutcome = const ConfigConflict(FakeAgentConfigStore.userPath);
      final cubit = await open();
      await walkToReview(cubit);
      final snapshots = store.snapshots;
      cubit.dispatch(const ConfirmSave());
      await pumpEventQueue(times: 20);
      expect(cubit.state.reviewNotice, isNotNull);
      // Другой процесс правит файл между попытками.
      store.user['telemetry'] = {'enabled': false};

      cubit.dispatch(const ConfirmSave());
      await pumpEventQueue(times: 20);

      expect(cubit.state.setup, isA<Done>());
      expect(store.snapshots, greaterThan(snapshots));
      expect(store.applied, hasLength(2));
      expect(store.user['telemetry'], {'enabled': false});
      expect((store.user['providers']! as Map).keys, contains('llm-example'));
      expect(session.secrets['codelab/llm-example'], leakMarker);
      expect(cubit.state.reviewNotice, isNull);
    });

    test('a provider that appeared meanwhile is a typed refusal on Review, '
        'with no second write', () async {
      store.firstOutcome = const ConfigConflict(FakeAgentConfigStore.userPath);
      // Другой процесс добавил провайдера как раз во время первой записи:
      // автомат перечитывает снимок сразу после конфликта.
      store.onApply = () =>
          (store.user['providers']! as Map)['llm-example'] = providerMap();
      final cubit = await open();
      await walkToReview(cubit);
      cubit.dispatch(const ConfirmSave());
      await pumpEventQueue(times: 20);

      cubit.dispatch(const ConfirmSave());
      await pumpEventQueue(times: 20);

      final review = cubit.state.setup as Reviewing;
      expect(review.refusal, PlanRefusal.providerExists);
      expect(review.error, 'A provider with this id already exists.');
      expect(store.applied, hasLength(1));
    });

    test('the entry point reaches the session: app by default', () async {
      await open();
      expect(session.wizards.single.entry, ProviderWizardEntry.app);
      expect(
        session.wizardLog.entries.firstWhere(
          (e) => e['event'] == 'provider_wizard.started',
        )['entry'],
        'app',
      );
    });

    test(
      'another rejection is shown as SaveFailed without the secret text',
      () async {
        store.onApply = () => throw StateError('yaml near $leakMarker');
        final cubit = await open();
        await walkToReview(cubit);
        cubit.dispatch(const ConfirmSave());
        await pumpEventQueue(times: 20);

        final failed = cubit.state.setup as SaveFailed;
        expect(failed.failure.errorType, 'StateError');
        expect(cubit.state.reviewNotice, isNull);
        expect(wizardSaveFailureText(failed), isNot(contains(leakMarker)));
      },
    );
  });

  group('cancel and late results (D21)', () {
    test('Esc while checking: the request is cancelled, a late answer changes '
        'nothing, no file is written, check_discarded is logged', () async {
      final cubit = await open();
      cubit.dispatch(const PresetChosen('custom-openai'));
      await pumpEventQueue();
      cubit.dispatch(const BaseUrlSubmitted('https://llm.example/v1'));
      await pumpEventQueue();
      cubit.dispatch(KeySubmitted(StoreSecret(SecretValue(leakMarker))));
      await pumpEventQueue();
      expect(cubit.state.setup, isA<Checking>());
      final call = session.wizardCheck.calls.single;

      cubit.cancel();
      await pumpEventQueue();

      expect(cubit.state.setup, isA<Cancelled>());
      expect(call.cancel!.isCancelled, isTrue);
      session.wizardCheck.respond(const CheckOk([RemoteModel('m1')]));
      await pumpEventQueue();
      expect(cubit.state.setup, isA<Cancelled>());
      expect(store.applied, isEmpty);
      expect(
        session.lastKeys!.journal.where((e) => e.startsWith('write')),
        isEmpty,
      );
      // Все события `provider_wizard.*` пишет мост (D18); Cubit не дублирует.
      expect(
        session.wizardLog.entries.map((e) => e['event']),
        contains('provider_wizard.check_discarded'),
      );
      expect(log.entries, isEmpty);
      expect(
        session.wizardLog.entries.firstWhere(
          (e) => e['event'] == 'provider_wizard.cancelled',
        )['state'],
        'Checking',
      );
    });

    test('closing the Cubit while checking cancels the request once', () async {
      final cubit = await open();
      cubit.dispatch(const PresetChosen('custom-openai'));
      await pumpEventQueue();
      cubit.dispatch(const BaseUrlSubmitted('https://llm.example/v1'));
      await pumpEventQueue();
      cubit.dispatch(const KeySubmitted(NoKey()));
      await pumpEventQueue();
      final call = session.wizardCheck.calls.single;

      await cubit.close();
      session.wizardCheck.respond(const CheckOk([RemoteModel('m1')]));
      await pumpEventQueue();

      expect(call.cancel!.isCancelled, isTrue);
      expect(
        session.wizardLog.entries.where(
          (e) => e['event'] == 'provider_wizard.check_discarded',
        ),
        hasLength(1),
      );
      expect(log.entries, isEmpty);
    });
  });

  test('the secret marker does not leak: states, banner, logs and failure '
      'texts never contain it; it reaches the key store only', () async {
    final cubit = await open();
    final seen = <String>[];
    final subscription = cubit.stream.listen(
      (s) => seen.add('${s.setup}|${s.summary}|${s.reviewNotice}'),
    );
    await walkToReview(cubit);
    cubit.dispatch(const ConfirmSave());
    await pumpEventQueue(times: 20);

    expect(cubit.state.setup, isA<Done>());
    expect(session.secrets['codelab/llm-example'], leakMarker);
    expect(store.applied.single.edits.join(), isNot(contains(leakMarker)));
    final everything = [
      ...seen,
      '${cubit.state.setup}',
      '${cubit.savedBanner}',
      cubit.savedBanner!.text,
      '${log.entries}',
      '${session.wizardLog.entries}',
    ].join('\n');
    expect(everything, isNot(contains(leakMarker)));
    expect(everything, isNot(contains('sk-test-leak')));
    await subscription.cancel();
  });
}
