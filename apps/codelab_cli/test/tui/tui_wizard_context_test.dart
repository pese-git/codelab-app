// Адаптер мастера и экрана настроек в `TuiCommandContext` (задача 4.15 change
// `add-provider-setup-ui`; design.md D17, D21): единственная подписка на
// `flow.states`, сообщения экрану, итог как у построчного мастера, запись
// настроек через `applySetting`.

import 'dart:async';

import 'package:codelab_cli/codelab_cli.dart';
import 'package:codelab_cli/src/setup/settings_screen.dart';
import 'package:codelab_setup/codelab_setup.dart';
import 'package:test/test.dart';

import '../support/fake_agent.dart';
import '../support/fake_terminal.dart' show eventually;
import '../support/setup_fakes.dart';

void main() {
  late FakeAgent agent;
  late List<TuiMsg> sent;
  late TuiCommandContext context;
  late FakeConfigStore store;
  late FakeProviderCheck check;
  late FakeProviderKeys keys;

  setUp(() async {
    agent = FakeAgent();
    sent = [];
    await agent.workspace.connect(FakeAgent.profile, projectDirectory: '/work');
    context = TuiCommandContext(
      workspace: agent.workspace,
      profile: FakeAgent.profile,
      cwd: '/work',
      send: sent.add,
      onExit: (_) {},
    );
    store = FakeConfigStore(snapshotValue: snapshotOf());
    check = FakeProviderCheck();
    keys = FakeProviderKeys();
  });
  tearDown(() async {
    await context.close();
    await agent.dispose();
  });

  /// Событие мастеру от оверлея с последним номером (id обязателен, D21).
  void ev(ProviderSetupEvent event) => context.wizardEvent(
    event,
    overlayId: sent.whereType<OpenWizardMsg>().last.id,
  );

  ProviderSetupFlow newFlow() => buildWizardFlow(
    check: check,
    keys: keys,
    config: store,
    entry: ProviderWizardEntry.cli,
  );

  group('runWizard', () {
    test('открывает оверлей и пересылает каждое состояние автомата', () async {
      final flow = newFlow();
      final result = context.runWizard(flow);
      await pumpEventQueue();

      expect(sent.first, isA<OpenWizardMsg>());
      final opened = sent.first as OpenWizardMsg;

      ev(const PresetChosen('custom-openai'));
      await pumpEventQueue();

      final states = sent.whereType<WizardStateMsg>().toList();
      expect(states, hasLength(1));
      expect(states.single.id, opened.id);
      expect(states.single.state, isA<EnteringBaseUrl>());

      ev(const Cancel());
      expect(await result, isA<ProviderWizardCancelled>());
    });

    test(
      'Cancelled завершает мастер, поздние события не пересылаются',
      () async {
        final flow = newFlow();
        final result = context.runWizard(flow);
        await pumpEventQueue();

        ev(const Cancel());
        await result;
        final count = sent.length;
        ev(const PresetChosen('openai'));
        await pumpEventQueue();

        expect(sent, hasLength(count), reason: 'подписка отменена');
      },
    );

    test('закрытие контекста при открытом мастере отменяет ожидание', () async {
      final flow = newFlow();
      final result = context.runWizard(flow);
      await pumpEventQueue();

      await context.close();

      expect(await result, isA<ProviderWizardCancelled>());
    });

    test('позиционный id применяется на «Review» один раз', () async {
      final flow = newFlow();
      final result = context.runWizard(flow, providerId: 'gw');
      await pumpEventQueue();
      ev(const PresetChosen('custom-openai'));
      ev(const BaseUrlSubmitted('https://gw.example/v1'));
      await eventually(() => flow.current is ChoosingKey);
      ev(const KeySubmitted(NoKey()));
      await eventually(() => check.calls.isNotEmpty);
      check.respond(modelsOk(['m1']));
      await eventually(() => flow.current is ChoosingModel);
      ev(const ModelChosen('m1'));
      await eventually(() => flow.current is Reviewing);
      await pumpEventQueue();

      ev(const ConfirmSave());
      final saved = await result;

      expect(saved, isA<ProviderWizardSaved>());
      expect((saved as ProviderWizardSaved).providerId, 'gw');
      expect(
        sent.whereType<WizardStateMsg>().where(
          (m) =>
              m.state is Reviewing &&
              (m.state as Reviewing).plan.providerId != 'gw',
        ),
        isEmpty,
        reason: 'экран не видит промежуточный Review до применения id',
      );
    });
  });

  group('ревью 4b: запись, id, снимок', () {
    test('close() во время Saving ждёт итог записи, а не отменяет', () async {
      store.applyGate = Completer<void>();
      final flow = newFlow();
      final result = context.runWizard(flow);
      await pumpEventQueue();
      ev(const PresetChosen('custom-openai'));
      ev(const BaseUrlSubmitted('https://gw.example/v1'));
      await eventually(() => flow.current is ChoosingKey);
      ev(const KeySubmitted(NoKey()));
      await eventually(() => check.calls.isNotEmpty);
      check.respond(modelsOk(['m1']));
      await eventually(() => flow.current is ChoosingModel);
      ev(const ModelChosen('m1'));
      await eventually(() => flow.current is Reviewing);
      ev(const ConfirmSave());
      await eventually(() => store.applied.isNotEmpty);

      var closed = false;
      final closing = context.close().then((_) => closed = true);
      await pumpEventQueue();
      expect(closed, isFalse, reason: 'запись ещё идёт');

      store.applyGate!.complete();
      await closing;
      expect(await result, isA<ProviderWizardSaved>());
    });

    test('событие чужого оверлея мастеру не отдаётся', () async {
      final flow = newFlow();
      final result = context.runWizard(flow);
      await pumpEventQueue();
      final id = (sent.first as OpenWizardMsg).id;

      context.wizardEvent(const PresetChosen('openai'), overlayId: id + 1);
      expect(flow.current, isA<ChoosingPreset>());

      context.wizardEvent(const Cancel(), overlayId: id);
      expect(await result, isA<ProviderWizardCancelled>());
    });

    const access = EditableSettings(
      ConfigPaths(codelabHome: '/h', projectDir: '/work'),
    );
    SettingsScreen screen() => SettingsScreen(
      access: access,
      scope: const SetupScope(access: access, cwd: '/work'),
      store: store,
      snapshot: snapshotOf(),
    );

    test('нет порта записи для текущего экрана: исход-отказ, экран не '
        'залипает в режиме записи', () async {
      context.showSettings(SettingsScreen(access: access));
      final id = sent.whereType<OpenSettingsMsg>().single.id;

      await context.applySettingFor(
        id,
        'agent.effort',
        'high',
        ConfigLayer.user,
      );

      final applied = sent.whereType<SettingsAppliedMsg>().single;
      expect(applied.id, id);
      expect(applied.line, isNotEmpty);
      expect(store.applied, isEmpty);
    });

    test('явный ctrl+u: ключ слоя local без цели пишется в user', () async {
      const noTarget = EditableSettings(ConfigPaths(codelabHome: '/h'));
      context.showSettings(
        SettingsScreen(
          access: noTarget,
          scope: const SetupScope(access: noTarget, cwd: '/work'),
          store: store,
          snapshot: snapshotOf(
            projectLocal: {
              'budget': {'max_steps': 7},
            },
            values: const {'budget.max_steps': 7},
          ),
        ),
      );
      final id = sent.whereType<OpenSettingsMsg>().single.id;

      await context.applySettingFor(
        id,
        'budget.max_steps',
        '3',
        ConfigLayer.user,
        explicitLayer: true,
      );

      expect(
        sent.whereType<SettingsAppliedMsg>().single.line,
        'Updated budget.max_steps in /h/config.yaml',
      );
    });

    test('запись чужого экрана игнорируется', () async {
      context.showSettings(screen());
      final id = sent.whereType<OpenSettingsMsg>().single.id;

      await context.applySettingFor(
        id + 1,
        'agent.effort',
        'high',
        ConfigLayer.user,
      );

      expect(store.applied, isEmpty);
      expect(sent.whereType<SettingsAppliedMsg>(), isEmpty);
    });

    test(
      'снимок не перечитался после записи: исход приходит без снимка',
      () async {
        context.showSettings(screen());
        final id = sent.whereType<OpenSettingsMsg>().single.id;
        store.snapshotError = StateError('gone');

        await context.applySettingFor(
          id,
          'agent.effort',
          'high',
          ConfigLayer.user,
        );

        final applied = sent.whereType<SettingsAppliedMsg>().single;
        expect(applied.snapshot, isNull);
        expect(applied.line, contains('Updated agent.effort'));
        expect(applied.line, contains('could not reload'));
      },
    );

    test(
      'сбой записи: строка исхода без текста исключения, экран не залипает',
      () async {
        context.showSettings(screen());
        final id = sent.whereType<OpenSettingsMsg>().single.id;
        store.applyError = StateError('boom $leakMarker');

        await context.applySettingFor(
          id,
          'agent.effort',
          'high',
          ConfigLayer.user,
        );

        final applied = sent.whereType<SettingsAppliedMsg>().single;
        expect(applied.line, isNot(contains(leakMarker)));
        expect(applied.line, contains('write failed'));
      },
    );
  });

  group('экран настроек', () {
    const access = EditableSettings(
      ConfigPaths(codelabHome: '/h', projectDir: '/work'),
    );

    test('showSettings открывает оверлей, applySettingFor пишет и отвечает '
        'исходом с новым снимком', () async {
      final snapshot = snapshotOf();
      context.showSettings(
        SettingsScreen(
          access: access,
          scope: const SetupScope(access: access, cwd: '/work'),
          store: store,
          snapshot: snapshot,
        ),
      );
      final open = sent.whereType<OpenSettingsMsg>().single;

      await context.applySettingFor(
        open.id,
        'agent.effort',
        'high',
        ConfigLayer.user,
      );

      final applied = sent.whereType<SettingsAppliedMsg>().single;
      expect(applied.id, open.id);
      expect(applied.line, 'Updated agent.effort in /h/config.yaml');
      expect(store.applied.single.edits, [
        const SetValue('agent.effort', 'high'),
      ]);
    });

    test('чужой агент: оверлей только для чтения, записи нет', () async {
      context.showSettings(SettingsScreen(access: NotManaged('python')));

      await context.applySettingFor(
        1,
        'agent.effort',
        'high',
        ConfigLayer.user,
      );

      expect(sent.whereType<OpenSettingsMsg>().single.snapshot, isNull);
      // Текущий экран получает отказ, а не молчание (иначе он залип бы в
      // режиме записи); запись не идёт.
      expect(sent.whereType<SettingsAppliedMsg>().single.line, isNotEmpty);
      expect(store.applied, isEmpty);
    });
  });
}
