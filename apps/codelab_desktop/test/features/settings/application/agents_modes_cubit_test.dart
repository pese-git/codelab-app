// `AgentsModesCubit` (задача 1.1 change `add-settings-agents-modes`; spec
// app-settings «Страница «Agents & modes» только для чтения», «Режим
// разрешений новой сессии…», «Уровень рассуждения…», «Цель записи…»,
// «События журнала…»; design.md D3, D4, D5, D11, D12).
//
// Красные тесты: Cubit — заглушка итерации 1, логика появится в задаче 1.3.
//
// Конфиг читает и пишет НАСТОЯЩЕЕ хранилище во временной папке
// (`ModesFixture`): итог режима, источник, предупреждение недоверенного
// проекта и `restartRequiredKeys` решают загрузчик и писатель ядра, а app не
// строит `CoreConfig` сам. Обёртка `ControlledConfigStore` удерживает снимок и
// запись и подменяет исход. Агенту Cubit ничего не отправляет: у
// `FakeWorkspace` любой вызов сессии бросает `UnimplementedError`.

import 'dart:async';
import 'dart:io';

import 'package:codelab_client_core/codelab_client_core.dart';
import 'package:codelab_desktop/features/settings/application/agents_modes_cubit.dart';
import 'package:codelab_desktop/features/settings/application/embedded_profile.dart';
import 'package:codelab_setup/codelab_setup.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../../support/fake_provider_settings.dart' show FakeWorkspace;
import '../../../support/modes_fixture.dart';
import '../../../support/recording_logger.dart';

final _remote = ConnectionProfile.webSocket(
  id: 'devbox',
  label: 'Devbox',
  uri: Uri.parse('wss://devbox:7420/acp'),
);

const _foreign = ConnectionProfile.stdio(
  id: 'other',
  label: 'Other',
  command: 'python',
  args: ['-m', 'other_agent'],
);

const _connected = ConnectionView.connected();

void main() {
  late FakeWorkspace workspace;
  late RecordingLogger logger;
  late List<AgentsModesCubit> cubits;
  late List<ModesFixture> fixtures;
  late List<EditableSettings> opened;
  String? Function() projectDir = () => null;

  Future<ModesFixture> fixture({
    String userYaml = '',
    bool trusted = true,
    String? localYaml,
    String? projectYaml,
  }) async {
    final fx = await ModesFixture.open(
      userYaml: userYaml,
      trusted: trusted,
      localYaml: localYaml,
      projectYaml: projectYaml,
    );
    fixtures.add(fx);
    projectDir = () => fx.project;
    return fx;
  }

  AgentsModesCubit make(ModesFixture fx) {
    final cubit = AgentsModesCubit(
      workspace: workspace,
      defaultProfile: () async => embeddedConnectionProfile,
      open: (access, env) async {
        opened.add(access);
        return ModesSession(fx.store);
      },
      environment: {'HOME': fx.home},
      codelabHome: fx.home,
      projectDirectory: () => projectDir(),
      logger: logger,
    );
    cubits.add(cubit);
    return cubit;
  }

  setUp(() {
    workspace = FakeWorkspace();
    logger = RecordingLogger();
    cubits = [];
    fixtures = [];
    opened = [];
    projectDir = () => null;
  });

  tearDown(() async {
    for (final cubit in cubits) {
      await cubit.close();
    }
    for (final fx in fixtures) {
      fx.dispose();
    }
  });

  void connectEmbedded() => workspace.emit(
    WorkspaceState(connection: _connected, profile: embeddedConnectionProfile),
  );

  Future<AgentsModesReady> ready(AgentsModesCubit cubit) async {
    await cubit.reload();
    return cubit.state as AgentsModesReady;
  }

  AgentsModesReady now(AgentsModesCubit cubit) =>
      cubit.state as AgentsModesReady;

  Iterable<Map<String, Object?>> events(String name) =>
      logger.entries.where((e) => e['event'] == name);

  group('Loading → Ready', () {
    test(
      'starts in Loading and shows the defaults of an empty config',
      () async {
        final fx = await fixture();
        final cubit = make(fx);

        expect(cubit.state, isA<AgentsModesLoading>());
        final state = await ready(cubit);

        expect(state.mode, 'standard');
        expect(state.modeLabel, 'standard');
        expect(state.modeSource, 'default');
        expect(state.effort, 'medium');
        expect(state.effortSource, 'default');
        expect(state.target, ConfigLayer.user);
        expect(state.canTargetProject, isTrue);
        expect(state.saving, isFalse);
        expect(state.banner, isNull);
        expect(state.narrowedNotice, isNull);
        expect(opened.single.cwd, fx.project);
        expect(events('agents_modes.loaded').single['access'], 'editable');
      },
    );

    test(
      'takes the mode and the effort with their sources from the files',
      () async {
        final fx = await fixture(
          userYaml:
              'permissions:\n  mode: acceptEdits\nagent:\n  effort: high\n',
        );

        final state = await ready(make(fx));

        expect(
          state.mode,
          'accept-edits',
          reason: 'псевдоним приведён к основному',
        );
        expect(state.modeSource, 'user');
        expect(state.effort, 'high');
        expect(state.effortSource, 'user');
      },
    );

    test('without a project folder there is no project target (D4)', () async {
      final fx = await fixture();
      projectDir = () => null;

      final state = await ready(make(fx));

      expect(opened.single.cwd, isNull);
      expect(state.canTargetProject, isFalse);
      expect(state.target, ConfigLayer.user);
    });

    test('selecting the project target without a folder is ignored', () async {
      final fx = await fixture();
      projectDir = () => null;
      final cubit = make(fx);
      await ready(cubit);

      cubit.selectTarget(ConfigLayer.projectLocal);

      expect(now(cubit).target, ConfigLayer.user);
    });
  });

  group('Страница только для чтения', () {
    test('a WebSocket agent: the notice without the path, the local config is '
        'not read', () async {
      final fx = await fixture();
      workspace.emit(WorkspaceState(connection: _connected, profile: _remote));
      final cubit = make(fx);

      await cubit.reload();

      final state = cubit.state as AgentsModesReadOnly;
      expect(
        state.notice,
        'Read-only: this agent runs on wss://devbox:7420. Change its modes '
        'and agents on that host: codelab config set, .codelab/agents.',
      );
      expect(opened, isEmpty);
      expect(fx.store.snapshotCalls, 0);
      expect(events('agents_modes.loaded').single['access'], 'remote');
    });

    test('a third-party stdio agent is managed by itself', () async {
      final fx = await fixture();
      workspace.emit(
        const WorkspaceState(connection: _connected, profile: _foreign),
      );
      final cubit = make(fx);

      await cubit.reload();

      final state = cubit.state as AgentsModesReadOnly;
      expect(state.notice, 'Agent settings are managed by python.');
      expect(opened, isEmpty);
      expect(fx.store.snapshotCalls, 0);
      expect(events('agents_modes.loaded').single['access'], 'not_managed');
    });

    test('autopilot in the file makes the page Unreadable and nothing is '
        'written', () async {
      final fx = await fixture(userYaml: 'permissions:\n  mode: autopilot\n');
      final before = fx.userConfig;
      final cubit = make(fx);

      await cubit.reload();

      final state = cubit.state as AgentsModesUnreadable;
      expect(state.problems.single, contains('permissions.mode'));
      expect(events('agents_modes.unreadable'), hasLength(1));
      expect(events('agents_modes.unreadable').single['level'], 'warning');
      expect(fx.store.applied, isEmpty);
      expect(fx.userConfig, before);
      // Любой выбор в Unreadable ничего не пишет.
      await cubit.selectMode('plan');
      expect(fx.store.applied, isEmpty);
    });
  });

  group('Режим новой сессии', () {
    test(
      'accept-edits is written to the user config with the Restart agent '
      'banner when the agent is connected; no request goes to the agent',
      () async {
        final fx = await fixture();
        connectEmbedded();
        final cubit = make(fx);
        await ready(cubit);

        await cubit.selectMode('accept-edits');

        expect(fx.store.applied.single.path, '${fx.home}/config.yaml');
        expect(fx.store.applied.single.edits, [
          const SetValue('permissions.mode', 'accept-edits'),
        ]);
        expect(fx.userConfig, contains('mode: accept-edits'));
        final state = now(cubit);
        expect(state.mode, 'accept-edits');
        expect(state.modeSource, 'user');
        expect(state.saving, isFalse);
        expect(state.banner?.kind, AgentsModesBannerKind.saved);
        expect(
          state.banner?.text,
          'Saved. New sessions use accept-edits after Restart agent.',
        );
        expect(workspace.ensuredAgents, isEmpty);
        final changed = events('agents_modes.mode_changed').single;
        expect(changed['mode'], 'accept-edits');
        expect(changed['target'], 'user');
        expect(changed['level'], 'info');
      },
    );

    test(
      'without a connected agent the banner says "when the agent starts"',
      () async {
        final fx = await fixture();
        final cubit = make(fx);
        await ready(cubit);

        await cubit.selectMode('plan');

        expect(
          now(cubit).banner?.text,
          'Saved. New sessions use plan when the agent starts.',
        );
      },
    );

    test('bypass is not written until it is confirmed', () async {
      final fx = await fixture();
      final cubit = make(fx);
      await ready(cubit);
      final before = fx.userConfig;

      await cubit.selectMode('bypass');

      expect(fx.store.applied, isEmpty);
      expect(fx.userConfig, before);
      expect(now(cubit).mode, 'standard');
      expect(events('agents_modes.mode_changed'), isEmpty);
    });

    test('Cancel keeps the mode and logs the cancellation', () async {
      final fx = await fixture(userYaml: 'permissions:\n  mode: ask\n');
      final cubit = make(fx);
      await ready(cubit);
      await cubit.selectMode('bypass');

      cubit.cancelBypass();

      expect(fx.store.applied, isEmpty);
      expect(now(cubit).mode, 'ask');
      final cancelled = events('agents_modes.bypass_cancelled').single;
      expect(cancelled['level'], 'info');
      expect(events('agents_modes.mode_changed'), isEmpty);
    });

    test('"Use bypass" writes permissions.mode: bypass', () async {
      final fx = await fixture();
      final cubit = make(fx);
      await ready(cubit);
      await cubit.selectMode('bypass');

      await cubit.confirmBypass();

      expect(fx.store.applied.single.edits, [
        const SetValue('permissions.mode', 'bypass'),
      ]);
      expect(fx.userConfig, contains('mode: bypass'));
      expect(now(cubit).mode, 'bypass');
      expect(events('agents_modes.mode_changed').single['mode'], 'bypass');
    });

    test('autopilot and unknown ids are never written', () async {
      final fx = await fixture();
      final cubit = make(fx);
      await ready(cubit);

      await cubit.selectMode('autopilot');
      await cubit.selectMode('acceptEdits');
      await cubit.selectMode('nonsense');

      expect(fx.store.applied, isEmpty);
    });

    test('an untrusted project cannot soften the mode: the user layer wins '
        'and the notice names the effective mode', () async {
      final fx = await fixture(
        userYaml: 'permissions:\n  mode: ask\n',
        trusted: false,
        localYaml: 'permissions:\n  mode: bypass\n',
      );

      final state = await ready(make(fx));

      expect(state.mode, 'ask');
      expect(state.modeLabel, 'ask');
      expect(state.modeSource, 'user');
      expect(
        state.narrowedNotice,
        'This project is not trusted, so its config can only make the mode '
        'stricter. New sessions here use ask.',
      );
    });

    test(
      'ask with plan is shown as ask with blocked edits and commands',
      () async {
        final fx = await fixture(
          userYaml: 'permissions:\n  mode: ask\n',
          trusted: false,
          localYaml: 'permissions:\n  mode: plan\n',
        );

        final state = await ready(make(fx));

        expect(state.mode, 'ask');
        expect(state.modeLabel, 'ask (edits and commands blocked by plan)');
      },
    );

    test('a trusted project does not show the narrowing notice', () async {
      final fx = await fixture(localYaml: 'permissions:\n  mode: plan\n');

      final state = await ready(make(fx));

      expect(state.mode, 'plan');
      expect(state.modeSource, 'local');
      expect(state.narrowedNotice, isNull);
    });
  });

  group('Уровень рассуждения', () {
    test(
      'high is written to agent.effort; the banner has no Restart agent',
      () async {
        final fx = await fixture();
        connectEmbedded();
        final cubit = make(fx);
        await ready(cubit);

        await cubit.selectEffort('high');

        expect(fx.store.applied.single.edits, [
          const SetValue('agent.effort', 'high'),
        ]);
        expect(fx.userConfig, contains('effort: high'));
        final state = now(cubit);
        expect(state.effort, 'high');
        expect(state.effortSource, 'user');
        expect(state.banner?.text, 'Saved. New sessions use high.');
        final changed = events('agents_modes.effort_changed').single;
        expect(changed['effort'], 'high');
        expect(changed['target'], 'user');
      },
    );

    test('with agent.effort among restartRequiredKeys the banner is the '
        'mode one', () async {
      final fx = await fixture();
      connectEmbedded();
      final cubit = make(fx);
      await ready(cubit);
      fx.store.forcedOutcome = const ConfigSaved(
        fingerprint: 'fp',
        warnings: [],
        restartRequiredKeys: ['agent.effort'],
      );

      await cubit.selectEffort('low');

      expect(
        now(cubit).banner?.text,
        'Saved. New sessions use low after Restart agent.',
      );
    });

    test('unknown effort values are never written', () async {
      final fx = await fixture();
      final cubit = make(fx);
      await ready(cubit);

      await cubit.selectEffort('extreme');

      expect(fx.store.applied, isEmpty);
    });
  });

  group('Цель записи', () {
    test(
      'the initial target is the editable layer of the mode source',
      () async {
        final fx = await fixture(localYaml: 'permissions:\n  mode: plan\n');

        final state = await ready(make(fx));

        expect(state.target, ConfigLayer.projectLocal);
      },
    );

    test('a mode defined in the project layer (read-only) starts with the '
        'user target', () async {
      final fx = await fixture(projectYaml: 'permissions:\n  mode: plan\n');

      final state = await ready(make(fx));

      expect(state.modeSource, 'project');
      expect(state.target, ConfigLayer.user);
    });

    test('"This project only" writes the mode to config.local.yaml and leaves '
        'the other files alone', () async {
      final fx = await fixture();
      final userBefore = fx.userConfig;
      final cubit = make(fx);
      await ready(cubit);

      cubit.selectTarget(ConfigLayer.projectLocal);
      await cubit.selectMode('plan');

      expect(
        fx.store.applied.single.path,
        '${fx.project}/.codelab/config.local.yaml',
      );
      expect(fx.localConfig, contains('mode: plan'));
      expect(fx.userConfig, userBefore);
      expect(fx.projectConfig, isEmpty);
      expect(events('agents_modes.mode_changed').single['target'], 'local');
    });

    test('one target for the mode and for the effort (Q10 (a))', () async {
      final fx = await fixture();
      final userBefore = fx.userConfig;
      final cubit = make(fx);
      await ready(cubit);

      cubit.selectTarget(ConfigLayer.projectLocal);
      await cubit.selectEffort('low');

      expect(
        fx.store.applied.single.path,
        '${fx.project}/.codelab/config.local.yaml',
      );
      expect(fx.localConfig, contains('effort: low'));
      expect(fx.userConfig, userBefore);
      expect(now(cubit).target, ConfigLayer.projectLocal);
      expect(events('agents_modes.effort_changed').single['target'], 'local');
    });
  });

  group('Конфликт, отказ и сбой записи', () {
    test('a conflict shows the banner, re-reads the snapshot and does not '
        'retry', () async {
      final fx = await fixture();
      final cubit = make(fx);
      await ready(cubit);
      final snapshotsBefore = fx.store.snapshotCalls;
      fx.store.forcedOutcome = ConfigConflict('${fx.home}/config.yaml');

      await cubit.selectMode('plan');

      expect(
        fx.store.applied,
        hasLength(1),
        reason: 'SETUP-6: без автоповтора',
      );
      expect(now(cubit).banner?.kind, AgentsModesBannerKind.conflict);
      expect(now(cubit).saving, isFalse);
      expect(fx.store.snapshotCalls, greaterThan(snapshotsBefore));
      final failed = events('agents_modes.save_failed').single;
      expect(failed['key'], 'mode');
      expect(failed['outcome'], 'conflict');
    });

    test(
      'a rejected edit is logged as rejected, the file is untouched',
      () async {
        final fx = await fixture();
        final before = fx.userConfig;
        final cubit = make(fx);
        await ready(cubit);
        fx.store.forcedOutcome = const ConfigRejected([]);

        await cubit.selectEffort('high');

        expect(now(cubit).banner?.kind, AgentsModesBannerKind.error);
        final failed = events('agents_modes.save_failed').single;
        expect(failed['key'], 'effort');
        expect(failed['outcome'], 'rejected');
        expect(fx.userConfig, before);
      },
    );

    test('an exception is logged by type only: no path, no text', () async {
      final fx = await fixture();
      final cubit = make(fx);
      await ready(cubit);
      fx.store.applyError = const FileSystemException(
        'disk is full',
        '/Users/demo/.codelab/config.yaml',
      );

      await cubit.selectMode('plan');

      final state = now(cubit);
      expect(state.banner?.kind, AgentsModesBannerKind.error);
      expect(state.saving, isFalse);
      final failed = events('agents_modes.save_failed').single;
      expect(failed['outcome'], 'error');
      expect(failed['error_type'], 'FileSystemException');
      expect(logger.entries.toString(), isNot(contains('/Users/demo')));
      expect(logger.entries.toString(), isNot(contains('disk is full')));
      expect(state.banner!.text, isNot(contains('/Users/demo')));
    });
  });

  group('Параллельные операции (D11)', () {
    test('a repeated choice while saving is ignored', () async {
      final fx = await fixture();
      final cubit = make(fx);
      await ready(cubit);
      final applying = Completer<void>();
      final release = Completer<void>();
      fx.store.onApply = () {
        applying.complete();
        return release.future;
      };

      final first = cubit.selectMode('plan');
      await applying.future;
      expect(now(cubit).saving, isTrue);
      await cubit.selectMode('ask');
      await cubit.selectEffort('high');
      release.complete();
      await first;

      expect(fx.store.applied, hasLength(1));
      expect(fx.store.applied.single.edits, [
        const SetValue('permissions.mode', 'plan'),
      ]);
      expect(now(cubit).saving, isFalse);
      expect(now(cubit).mode, 'plan');
    });

    test('a late snapshot after a newer reload is discarded', () async {
      final fx = await fixture();
      final cubit = make(fx);
      final reached = Completer<void>();
      final gate = Completer<void>();
      fx.store.onSnapshot = (call) {
        if (call != 1) {
          return null;
        }
        reached.complete();
        return gate.future;
      };

      final first = cubit.reload();
      await reached.future;
      File(
        '${fx.home}/config.yaml',
      ).writeAsStringSync('${fx.userConfig}permissions:\n  mode: plan\n');
      await cubit.reload();
      expect(now(cubit).mode, 'plan');
      gate.complete();
      await first;

      expect(now(cubit).mode, 'plan');
      expect(events('agents_modes.load_discarded').single['reason'], 'reload');
    });

    test('a late snapshot after a change of access is discarded', () async {
      final fx = await fixture();
      final cubit = make(fx);
      final reached = Completer<void>();
      final gate = Completer<void>();
      fx.store.onSnapshot = (call) {
        if (call != 1) {
          return null;
        }
        reached.complete();
        return gate.future;
      };

      final first = cubit.reload();
      await reached.future;
      workspace.emit(WorkspaceState(connection: _connected, profile: _remote));
      await pumpEventQueue();
      gate.complete();
      await first;

      expect(cubit.state, isA<AgentsModesReadOnly>());
      expect(
        events('agents_modes.load_discarded').single['reason'],
        'access_changed',
      );
    });

    test('a late snapshot after close() is discarded', () async {
      final fx = await fixture();
      final cubit = make(fx);
      final reached = Completer<void>();
      final gate = Completer<void>();
      fx.store.onSnapshot = (call) {
        reached.complete();
        return gate.future;
      };

      final first = cubit.reload();
      await reached.future;
      await cubit.close();
      gate.complete();
      await first;

      expect(cubit.state, isA<AgentsModesLoading>());
      expect(events('agents_modes.load_discarded').single['reason'], 'closed');
    });

    test('a write that ends after close() goes to the log only', () async {
      final fx = await fixture();
      final cubit = make(fx);
      await ready(cubit);
      final applying = Completer<void>();
      final release = Completer<void>();
      fx.store.onApply = () {
        applying.complete();
        return release.future;
      };

      final write = cubit.selectMode('plan');
      await applying.future;
      await cubit.close();
      release.complete();
      await write;

      expect(events('agents_modes.mode_changed').single['mode'], 'plan');
    });
  });

  group('Журнал без путей (D12)', () {
    test('no event carries a path or a file name', () async {
      final fx = await fixture(userYaml: 'permissions:\n  mode: autopilot\n');
      final broken = make(fx);
      await broken.reload();
      final ok = await fixture();
      final cubit = make(ok);
      await ready(cubit);
      await cubit.selectMode('accept-edits');
      await cubit.selectEffort('high');

      final text = logger.entries.toString();
      expect(text, isNot(contains(fx.rootPath)));
      expect(text, isNot(contains(ok.rootPath)));
      expect(text, isNot(contains('config.yaml')));
      expect(text, isNot(contains('config.local.yaml')));
    });
  });
}
