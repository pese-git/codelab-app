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
import 'package:codelab_desktop/core/platform/path_opener.dart';
import 'package:codelab_desktop/features/settings/application/agents_modes_cubit.dart';
import 'package:codelab_desktop/features/settings/application/embedded_profile.dart';
import 'package:codelab_setup/codelab_setup.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../../support/fake_path_opener.dart';
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

const _own = ConnectionProfile.stdio(
  id: 'dev',
  label: 'Dev',
  command: '/opt/bin/codelab-agent',
  args: ['serve', '--stdio'],
  env: {'CODELAB_HOME': '/srv/codelab'},
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
    String? effort,
  }) async {
    final fx = await ModesFixture.open(
      userYaml: userYaml,
      trusted: trusted,
      localYaml: localYaml,
      projectYaml: projectYaml,
      effort: effort,
    );
    fixtures.add(fx);
    projectDir = () => fx.project;
    return fx;
  }

  AgentsModesCubit make(
    ModesFixture fx, {
    FakeDefinitionsLoader? loader,
    FakePathOpener? opener,
    Map<String, String>? environment,
  }) {
    final cubit = AgentsModesCubit(
      workspace: workspace,
      defaultProfile: () async => embeddedConnectionProfile,
      open: (access, env) async {
        opened.add(access);
        return ModesSession(fx.store);
      },
      environment: environment ?? {'HOME': fx.home},
      codelabHome: fx.home,
      projectDirectory: () => projectDir(),
      logger: logger,
      loadDefinitions: loader?.call,
      pathOpener: opener,
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

  /// Ждёт состояние [test] без опроса по таймеру: подписка до причины.
  Future<AgentsModesState> until(
    AgentsModesCubit cubit,
    bool Function(AgentsModesState state) test,
  ) => cubit.stream.firstWhere(test).timeout(const Duration(seconds: 10));

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
          userYaml: 'permissions:\n  mode: acceptEdits\n',
          effort: 'high',
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

  group('Цель без папки проекта', () {
    test('selecting the project target without a folder neither changes the '
        'target nor leaks into a later load; the write goes to user', () async {
      final fx = await fixture();
      final folder = fx.project;
      projectDir = () => null;
      final cubit = make(fx);
      await ready(cubit);

      cubit.selectTarget(ConfigLayer.projectLocal);

      expect(now(cubit).target, ConfigLayer.user);
      await cubit.selectMode('plan');
      expect(fx.store.applied.single.path, '${fx.home}/config.yaml');
      expect(fx.localConfig, isEmpty);

      // Папка появилась: отклонённый выбор не должен ожить после
      // перечитывания.
      projectDir = () => folder;
      await cubit.reload();
      expect(now(cubit).canTargetProject, isTrue);
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
      final token = cubit.beginBypass()!;

      await cubit.confirmBypass(token);

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

  group('Баннер по действующему значению после перечитывания', () {
    test('a write overridden by another layer: the warning banner names the '
        'source and the effective mode (Перекрытое значение)', () async {
      final fx = await fixture(localYaml: 'permissions:\n  mode: plan\n');
      connectEmbedded();
      final cubit = make(fx);
      await ready(cubit);
      cubit.selectTarget(ConfigLayer.user);

      await cubit.selectMode('accept-edits');

      expect(fx.userConfig, contains('mode: accept-edits'));
      final banner = now(cubit).banner!;
      expect(banner.kind, AgentsModesBannerKind.warning);
      expect(banner.text, contains('Saved to All projects;'));
      expect(banner.text, contains('overrides it: new sessions use plan'));
      expect(banner.text, endsWith('after Restart agent.'));
      expect(banner.text, isNot(contains('New sessions use accept-edits')));
    });

    test('the same without a connected agent ends with "when the agent '
        'starts."', () async {
      final fx = await fixture(localYaml: 'permissions:\n  mode: plan\n');
      final cubit = make(fx);
      await ready(cubit);
      cubit.selectTarget(ConfigLayer.user);

      await cubit.selectMode('accept-edits');

      expect(now(cubit).banner!.text, endsWith('when the agent starts.'));
    });

    test('a value narrowed by an untrusted project names the project as the '
        'source (Суженное значение)', () async {
      final fx = await fixture(
        trusted: false,
        localYaml: 'permissions:\n  mode: plan\n',
      );
      connectEmbedded();
      final cubit = make(fx);
      await ready(cubit);
      cubit.selectTarget(ConfigLayer.user);

      await cubit.selectMode('ask');

      expect(fx.userConfig, contains('mode: ask'));
      final state = now(cubit);
      expect(state.banner?.kind, AgentsModesBannerKind.warning);
      expect(
        state.banner?.text,
        contains(
          'the untrusted project overrides it: new sessions use '
          'ask (edits and commands blocked by plan)',
        ),
      );
      expect(state.narrowedNotice, isNotNull);
    });

    test('a softer mode for an untrusted project is refused by the writer: '
        'the error banner, nothing in the file', () async {
      final fx = await fixture(trusted: false);
      final cubit = make(fx);
      await ready(cubit);
      cubit.selectTarget(ConfigLayer.projectLocal);
      final token = cubit.beginBypass()!;

      await cubit.confirmBypass(token);

      expect(fx.localConfig, isEmpty);
      expect(now(cubit).banner?.kind, AgentsModesBannerKind.error);
      expect(events('agents_modes.save_failed').single['outcome'], 'rejected');
    });

    test('an effort overridden by another layer says so', () async {
      final fx = await fixture(localYaml: 'agent:\n  effort: low\n');
      final cubit = make(fx);
      await ready(cubit);
      cubit.selectTarget(ConfigLayer.user);

      await cubit.selectEffort('high');

      final banner = now(cubit).banner!;
      expect(banner.kind, AgentsModesBannerKind.warning);
      expect(banner.text, startsWith('Saved to All projects; '));
      expect(banner.text, contains('overrides it: new sessions use low'));
    });
  });

  group('Перечитывание после записи не удалось (D16)', () {
    for (final (layer, label) in [
      (ConfigLayer.user, 'All projects'),
      (ConfigLayer.projectLocal, 'This project only'),
    ]) {
      test(
        'the page is Unreadable but still says "Saved to $label."',
        () async {
          final fx = await fixture();
          connectEmbedded();
          final cubit = make(fx);
          await ready(cubit);
          cubit.selectTarget(layer);
          fx.store.onSnapshot = (call) async {
            throw StateError('cannot read');
          };

          await cubit.selectMode('plan');

          final state = cubit.state as AgentsModesUnreadable;
          expect(state.banner?.kind, AgentsModesBannerKind.saved);
          expect(state.banner?.text, 'Saved to $label.');
          expect(state.banner?.text, isNot(contains('New sessions')));
        },
      );
    }
  });

  group('Заметка о записи не переживает смену доступа', () {
    test('a write whose re-read was overtaken by an access change does not '
        'leak its banner into a later load', () async {
      final fx = await fixture();
      connectEmbedded();
      final cubit = make(fx);
      await ready(cubit);
      final reached = Completer<void>();
      final gate = Completer<void>();
      // Перечитывание после записи — второй снимок; удерживаем его.
      fx.store.onSnapshot = (call) {
        if (call != 2) {
          return null;
        }
        reached.complete();
        return gate.future;
      };

      final write = cubit.selectMode('plan');
      await reached.future;
      final readOnly = until(cubit, (s) => s is AgentsModesReadOnly);
      workspace.emit(WorkspaceState(connection: _connected, profile: _remote));
      await readOnly;
      gate.complete();
      await write;
      // Снова встроенный агент: баннер прежней записи показывать нельзя.
      fx.store.onSnapshot = null;
      final back = until(cubit, (s) => s is AgentsModesReady);
      connectEmbedded();
      await back;

      expect(now(cubit).banner, isNull);
    });
  });

  group('Заметка о записи привязана к загрузке самой записи', () {
    test('another reload that wins the race does not show the banner of '
        'the write', () async {
      final fx = await fixture();
      connectEmbedded();
      final cubit = make(fx);
      await ready(cubit);
      final reached = Completer<void>();
      final gate = Completer<void>();
      fx.store.onSnapshot = (call) {
        if (call != 2) {
          return null;
        }
        reached.complete();
        return gate.future;
      };

      final write = cubit.selectMode('plan');
      await reached.future;
      await cubit.reload();
      gate.complete();
      await write;

      expect(now(cubit).mode, 'plan');
      expect(now(cubit).banner, isNull);
    });
  });

  group('Доступ заметки фиксируется до записи', () {
    test('a change of the focus folder during the write: no "Saved" banner '
        'for the other folder', () async {
      final fx = await fixture();
      connectEmbedded();
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
      projectDir = () => null;
      workspace.emit(
        WorkspaceState(
          connection: _connected,
          profile: embeddedConnectionProfile,
        ),
      );
      release.complete();
      await write;

      expect(now(cubit).banner, isNull);
    });
  });

  group('Подтверждение bypass привязано к открытию диалога', () {
    test(
      'a change of access while the dialog is open: nothing is written',
      () async {
        final fx = await fixture();
        connectEmbedded();
        final cubit = make(fx);
        await ready(cubit);
        final token = cubit.beginBypass()!;

        final readOnly = until(cubit, (s) => s is AgentsModesReadOnly);
        workspace.emit(
          WorkspaceState(connection: _connected, profile: _remote),
        );
        await readOnly;
        await cubit.confirmBypass(token);

        expect(fx.store.applied, isEmpty);
        expect(cubit.state, isA<AgentsModesReadOnly>());
      },
    );

    test('a change of target while the dialog is open: nothing is written, '
        'the banner explains', () async {
      final fx = await fixture();
      final cubit = make(fx);
      await ready(cubit);
      final token = cubit.beginBypass()!;

      cubit.selectTarget(ConfigLayer.projectLocal);
      await cubit.confirmBypass(token);

      expect(fx.store.applied, isEmpty);
      expect(now(cubit).banner?.kind, AgentsModesBannerKind.warning);
      expect(
        now(cubit).banner?.text,
        'Settings changed while the dialog was open; bypass was not saved.',
      );
      expect(events('agents_modes.save_failed').single['outcome'], 'stale');
      expect(fx.localConfig, isEmpty);
    });

    test('a reload while the dialog is open invalidates the token', () async {
      final fx = await fixture();
      final cubit = make(fx);
      await ready(cubit);
      final token = cubit.beginBypass()!;

      await cubit.reload();
      await cubit.confirmBypass(token);

      expect(fx.store.applied, isEmpty);
    });

    test('a repeated confirmBypass with the same token writes once', () async {
      final fx = await fixture();
      final cubit = make(fx);
      await ready(cubit);
      final token = cubit.beginBypass()!;

      final first = cubit.confirmBypass(token);
      final second = cubit.confirmBypass(token);
      await Future.wait([first, second]);
      await cubit.confirmBypass(token);

      expect(fx.store.applied, hasLength(1));
      expect(
        events('agents_modes.save_failed').map((e) => e['outcome']),
        everyElement('stale'),
      );
    });

    test('no token while saving or before the page is ready', () async {
      final fx = await fixture();
      final cubit = make(fx);

      expect(cubit.beginBypass(), isNull);
    });

    test('no token while a write is in flight', () async {
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
      expect(cubit.beginBypass(), isNull);
      release.complete();
      await write;
    });

    test('dismissBypass logs "stale" only for an outdated token', () async {
      final fx = await fixture();
      connectEmbedded();
      final cubit = make(fx);
      await ready(cubit);
      final token = cubit.beginBypass()!;

      cubit.dismissBypass(token);
      expect(events('agents_modes.save_failed'), isEmpty);

      final readOnly = until(cubit, (s) => s is AgentsModesReadOnly);
      workspace.emit(WorkspaceState(connection: _connected, profile: _remote));
      await readOnly;
      cubit.dismissBypass(token);

      final failed = events('agents_modes.save_failed').single;
      expect(failed['key'], 'mode');
      expect(failed['outcome'], 'stale');
      expect(fx.store.applied, isEmpty);
    });

    test('while a load for another editable agent is running, bypass and '
        'plain writes do not go through the old session', () async {
      final fx = await fixture();
      connectEmbedded();
      final cubit = make(fx);
      await ready(cubit);
      final token = cubit.beginBypass()!;
      final reached = Completer<void>();
      final gate = Completer<void>();
      fx.store.onSnapshot = (call) {
        reached.complete();
        return gate.future;
      };

      workspace.emit(WorkspaceState(connection: _connected, profile: _own));
      await reached.future;
      // Состояние всё ещё старый Ready, но загрузка уже идёт.
      expect(cubit.state, isA<AgentsModesReady>());
      expect(cubit.isCurrent(token), isFalse);
      await cubit.confirmBypass(token);
      await cubit.selectMode('plan');
      await cubit.selectEffort('high');

      expect(fx.store.applied, isEmpty);
      expect(events('agents_modes.save_failed').single['outcome'], 'stale');
      gate.complete();
    });
  });

  group('Слой цели пропал из снимка', () {
    test(
      'the write is refused with the error banner, nothing is written',
      () async {
        final fx = await fixture();
        final cubit = make(fx);
        await ready(cubit);
        cubit.selectTarget(ConfigLayer.projectLocal);
        fx.store.transform = (snapshot) => AgentConfigSnapshot(
          cwd: snapshot.cwd,
          layers: {...snapshot.layers}..remove(ConfigLayer.projectLocal),
          loaded: snapshot.loaded,
          origins: snapshot.origins,
          secrets: snapshot.secrets,
        );
        await cubit.reload();
        cubit.selectTarget(ConfigLayer.projectLocal);

        await cubit.selectMode('plan');

        expect(fx.store.applied, isEmpty);
        expect(fx.userConfig, isNot(contains('mode: plan')));
        expect(now(cubit).banner?.kind, AgentsModesBannerKind.error);
        expect(now(cubit).saving, isFalse);
      },
    );
  });

  group('Смена папки фокуса без смены профиля (D2)', () {
    test('a change of the focus folder re-reads the access', () async {
      final fx = await fixture();
      connectEmbedded();
      final cubit = make(fx);
      await ready(cubit);
      expect(now(cubit).canTargetProject, isTrue);

      projectDir = () => null;
      final reread = until(
        cubit,
        (s) => s is AgentsModesReady && !s.canTargetProject,
      );
      workspace.emit(
        WorkspaceState(
          connection: _connected,
          profile: embeddedConnectionProfile,
        ),
      );
      await reread;

      expect(now(cubit).canTargetProject, isFalse);
      expect(opened.last.cwd, isNull);
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
      fx.store.extraRestartKeys = ['agent.effort'];

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
      final readOnly = until(cubit, (s) => s is AgentsModesReadOnly);
      workspace.emit(WorkspaceState(connection: _connected, profile: _remote));
      await readOnly;
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

  group('Таблица определений агентов (итерация 2)', () {
    // Пути вымышлены: загрузчик и порт — двойники, а HOME теста `/home/u`
    // даёт подпись `~/.codelab/agents/...`.
    const env = {'HOME': '/home/u'};
    const userDir = userAgentsDir;
    const migrator = '$userDir/migrator.md';

    AgentDefinitionRowView builtin(String name, {AgentRowStatus? status}) =>
        AgentDefinitionRowView(
          name: name,
          status: status ?? AgentRowStatus.available,
          availableIn: name == 'default'
              ? AgentRowScope.session
              : AgentRowScope.subagent,
          tools: const ['read'],
          model: 'session model',
        );

    final brokenRows = [
      builtin('default'),
      const AgentDefinitionRowView(
        name: 'reviewer',
        status: AgentRowStatus.available,
        description: 'Reviews diffs',
        path: '$userDir/reviewer.md',
        availableIn: AgentRowScope.both,
        tools: ['read', 'grep'],
        model: 'session model',
      ),
      const AgentDefinitionRowView(
        name: 'migrator',
        status: AgentRowStatus.error,
        path: migrator,
        errorLine: 4,
        errorMessage: 'tools must be a list',
      ),
    ];

    FakeDefinitionsLoader loaderOf(
      List<AgentDefinitionRowView> rows, {
      bool untrusted = false,
      bool timedOut = false,
      bool userExists = true,
      String? projectDir,
      bool projectExists = false,
    }) => FakeDefinitionsLoader(
      AgentDefinitionsLoad(
        rows: rows,
        projectTrusted: !untrusted,
        timedOut: timedOut,
        userDirectory: userDir,
        userDirectoryExists: userExists,
        projectDirectory: projectDir,
        projectDirectoryExists: projectExists,
      ),
    );

    AgentsDefinitionsView definitionsOf(AgentsModesCubit cubit) =>
        now(cubit).definitions!;

    test('a broken definition: the valid one is Available, the broken one is '
        '"Error · line 4"; the InfoBar names the file and not the value '
        '(Битое определение)', () async {
      final fx = await fixture();
      final cubit = make(fx, loader: loaderOf(brokenRows), environment: env);

      await ready(cubit);

      final view = definitionsOf(cubit);
      final byName = {for (final r in view.rows) r.name: r};
      expect(byName['reviewer']!.status, 'Available');
      expect(byName['reviewer']!.tone, AgentsStatusTone.success);
      expect(byName['reviewer']!.source, '~/.codelab/agents/reviewer.md');
      expect(byName['reviewer']!.availableIn, 'both');
      expect(byName['reviewer']!.tools, 'read, grep');
      expect(byName['migrator']!.status, 'Error · line 4');
      expect(byName['migrator']!.tone, AgentsStatusTone.danger);
      expect(byName['default']!.source, 'built-in');
      final error = view.errors.single;
      expect(error.index, 0);
      expect(error.pathLabel, '~/.codelab/agents/migrator.md');
      expect(error.path, migrator);
      expect(error.line, 4);
      expect(error.message, 'tools must be a list');
      expect(error.message, isNot(contains('read')));
    });

    test('rejected files show a dash in "Available in", "Tools" and "Model" '
        '(D7)', () async {
      final fx = await fixture();
      AgentDefinitionRowView rejected(String name, AgentRowStatus status) =>
          AgentDefinitionRowView(
            name: name,
            status: status,
            path: '$userDir/$name.md',
            availableIn: AgentRowScope.both,
            tools: const ['read'],
            model: 'openai/gpt-x',
          );
      final cubit = make(
        fx,
        loader: loaderOf([
          builtin('default'),
          rejected('a', AgentRowStatus.modelNotConfigured),
          rejected('b', AgentRowStatus.duplicate),
          rejected('c', AgentRowStatus.shadowed),
          rejected('d', AgentRowStatus.error),
        ]),
        environment: env,
      );

      await ready(cubit);

      for (final name in const ['a', 'b', 'c', 'd']) {
        final row = definitionsOf(cubit).rows.firstWhere((r) => r.name == name);
        expect(row.availableIn, '—', reason: name);
        expect(row.tools, '—', reason: name);
        expect(row.model, '—', reason: name);
      }
    });

    test('a working row without tools shows "all" and without a model '
        '"session model" (D7)', () async {
      final fx = await fixture();
      final cubit = make(
        fx,
        loader: loaderOf([
          const AgentDefinitionRowView(
            name: 'default',
            status: AgentRowStatus.available,
            availableIn: AgentRowScope.session,
          ),
          const AgentDefinitionRowView(
            name: 'plain',
            status: AgentRowStatus.available,
            path: '$userDir/plain.md',
            availableIn: AgentRowScope.subagent,
          ),
        ]),
        environment: env,
      );

      await ready(cubit);

      for (final row in definitionsOf(cubit).rows) {
        expect(row.tools, 'all', reason: row.name);
        expect(row.model, 'session model', reason: row.name);
      }
    });

    test('an overridden row without a path says just "Overridden"', () async {
      final fx = await fixture();
      final cubit = make(
        fx,
        loader: loaderOf([
          builtin('default'),
          const AgentDefinitionRowView(
            name: 'general',
            status: AgentRowStatus.overridden,
            availableIn: AgentRowScope.subagent,
          ),
        ]),
        environment: env,
      );

      await ready(cubit);

      expect(
        definitionsOf(cubit).rows.firstWhere((r) => r.name == 'general').status,
        'Overridden',
      );
    });

    test(
      'rows come in the order of the bridge: default, built-ins, files',
      () async {
        final fx = await fixture();
        final cubit = make(fx, loader: loaderOf(brokenRows), environment: env);

        await ready(cubit);

        expect(definitionsOf(cubit).rows.map((r) => r.name), [
          'default',
          'reviewer',
          'migrator',
        ]);
      },
    );

    test('an error without a line is "Error"', () async {
      final fx = await fixture();
      final cubit = make(
        fx,
        loader: loaderOf([
          builtin('default'),
          const AgentDefinitionRowView(
            name: 'x',
            status: AgentRowStatus.error,
            path: '$userDir/x.md',
            errorMessage: 'the file cannot be read',
          ),
        ]),
        environment: env,
      );

      await ready(cubit);

      expect(
        definitionsOf(cubit).rows.firstWhere((r) => r.name == 'x').status,
        'Error',
      );
      expect(definitionsOf(cubit).errors.single.line, isNull);
    });

    test('every status of the table has its text and tone (D7)', () async {
      final fx = await fixture();
      AgentDefinitionRowView row(String n, AgentRowStatus s, {String? by}) =>
          AgentDefinitionRowView(
            name: n,
            status: s,
            path: '$userDir/$n.md',
            overriddenBy: by,
          );
      final cubit = make(
        fx,
        loader: loaderOf([
          builtin('default'),
          row('docs-writer', AgentRowStatus.modelNotConfigured),
          row('dup', AgentRowStatus.duplicate),
          row('shadow', AgentRowStatus.shadowed),
          row('general', AgentRowStatus.overridden, by: '$userDir/general.md'),
        ]),
        environment: env,
      );

      await ready(cubit);

      final status = {
        for (final r in definitionsOf(cubit).rows) r.name: (r.status, r.tone),
      };
      expect(status['docs-writer'], (
        'Model not configured',
        AgentsStatusTone.warning,
      ));
      expect(status['dup'], (
        'Not loaded: duplicate name',
        AgentsStatusTone.danger,
      ));
      expect(status['shadow'], (
        'Shadowed by project',
        AgentsStatusTone.warning,
      ));
      expect(status['general'], (
        'Overridden by ~/.codelab/agents/general.md',
        AgentsStatusTone.warning,
      ));
    });

    test('a model outside the catalog also gets an error InfoBar with '
        '"Open file" (Модель вне каталога)', () async {
      final fx = await fixture();
      final cubit = make(
        fx,
        loader: loaderOf([
          builtin('default'),
          const AgentDefinitionRowView(
            name: 'docs-writer',
            status: AgentRowStatus.modelNotConfigured,
            path: '$userAgentsDir/docs-writer.md',
            errorMessage: 'the model is not in the config',
          ),
          ...brokenRows.skip(2),
        ]),
        environment: env,
      );

      await ready(cubit);

      final view = definitionsOf(cubit);
      expect(
        view.rows.firstWhere((r) => r.name == 'docs-writer').status,
        'Model not configured',
      );
      expect(view.errors.map((e) => e.index), [0, 1]);
      expect(view.errors.first.path, '$userAgentsDir/docs-writer.md');
      expect(view.errors.first.pathLabel, '~/.codelab/agents/docs-writer.md');
      expect(view.errors.first.message, 'the model is not in the config');
      expect(view.errors.first.line, isNull);
      expect(view.errors.last.path, migrator);
    });

    test(
      'a duplicate also gets an error InfoBar, a shadowed file does not',
      () async {
        final fx = await fixture();
        final cubit = make(
          fx,
          loader: loaderOf([
            builtin('default'),
            const AgentDefinitionRowView(
              name: 'dup',
              status: AgentRowStatus.duplicate,
              path: '$userAgentsDir/dup.md',
            ),
            const AgentDefinitionRowView(
              name: 'shadow',
              status: AgentRowStatus.shadowed,
              path: '$userAgentsDir/shadow.md',
            ),
          ]),
          environment: env,
        );

        await ready(cubit);

        final errors = definitionsOf(cubit).errors;
        expect(errors, hasLength(1));
        expect(errors.single.path, '$userAgentsDir/dup.md');
        expect(
          errors.single.message,
          'Not loaded: another definition has the same name.',
        );
        expect(errors.single.line, isNull);
      },
    );

    test('a model error without a message gets a fixed text', () async {
      final fx = await fixture();
      final cubit = make(
        fx,
        loader: loaderOf([
          builtin('default'),
          const AgentDefinitionRowView(
            name: 'docs-writer',
            status: AgentRowStatus.modelNotConfigured,
            path: '$userAgentsDir/docs-writer.md',
          ),
        ]),
        environment: env,
      );

      await ready(cubit);

      expect(definitionsOf(cubit).errors.single.message, isNotEmpty);
    });

    test('built-in types of a config with subagents.enabled false are '
        '"Subagents off" (Q12 (а))', () async {
      final fx = await fixture(userYaml: 'subagents:\n  enabled: false\n');
      final cubit = make(
        fx,
        loader: loaderOf([
          builtin('default'),
          for (final n in const ['general', 'explore', 'review', 'plan'])
            builtin(n, status: AgentRowStatus.subagentsOff),
        ]),
        environment: env,
      );

      await ready(cubit);

      final rows = {for (final r in definitionsOf(cubit).rows) r.name: r};
      for (final n in const ['general', 'explore', 'review', 'plan']) {
        expect(rows[n]!.status, 'Subagents off', reason: n);
        expect(rows[n]!.availableIn, 'subagent', reason: n);
      }
      expect(rows['default']!.status, 'Available');
    });

    test('definitions load together with the snapshot and get a cancel '
        'token (D11)', () async {
      final fx = await fixture();
      final loader = loaderOf(brokenRows);
      final cubit = make(fx, loader: loader, environment: env);

      await ready(cubit);

      expect(loader.tokens, hasLength(1));
      expect(loader.tokens.single, isNotNull);
      expect(loader.tokens.single!.isCancelled, isFalse);
    });

    test('a late result of an earlier load is discarded after a newer '
        'Reload (Поздний результат после Reload)', () async {
      final fx = await fixture();
      final loader = loaderOf([builtin('default'), brokenRows[1]]);
      final cubit = make(fx, loader: loader, environment: env);
      final reached = Completer<void>();
      final gate = Completer<AgentDefinitionsLoad>();
      final second = AgentDefinitionsLoad(
        rows: [builtin('default'), brokenRows[2]],
        userDirectory: userDir,
        userDirectoryExists: true,
      );
      loader.script = (call) {
        if (call == 1) {
          reached.complete();
          return gate.future;
        }
        return Future.value(second);
      };

      final first = cubit.reload();
      await reached.future;
      await cubit.reload();
      expect(
        definitionsOf(cubit).rows.map((r) => r.name),
        contains('migrator'),
      );
      gate.complete(loader.load);
      await first;

      expect(
        definitionsOf(cubit).rows.map((r) => r.name),
        contains('migrator'),
      );
      expect(
        definitionsOf(cubit).rows.map((r) => r.name),
        isNot(contains('reviewer')),
      );
      expect(events('agents_modes.load_discarded').single['reason'], 'reload');
      expect(loader.tokens.first!.isCancelled, isTrue);
    });

    test('closing the page cancels the load', () async {
      final fx = await fixture();
      final loader = loaderOf(brokenRows);
      final cubit = make(fx, loader: loader, environment: env);
      final reached = Completer<void>();
      final gate = Completer<AgentDefinitionsLoad>();
      loader.script = (call) {
        reached.complete();
        return gate.future;
      };

      final first = cubit.reload();
      await reached.future;
      await cubit.close();
      gate.complete(loader.load);
      await first;

      expect(loader.tokens.single!.isCancelled, isTrue);
    });

    test('the table is not loaded for a WebSocket agent', () async {
      final fx = await fixture();
      workspace.emit(WorkspaceState(connection: _connected, profile: _remote));
      final loader = loaderOf(brokenRows);
      final cubit = make(fx, loader: loader, environment: env);

      await cubit.reload();

      expect(cubit.state, isA<AgentsModesReadOnly>());
      expect(loader.tokens, isEmpty);
    });

    test(
      'a timeout shows the flag and logs the reason without a path',
      () async {
        final fx = await fixture();
        final cubit = make(
          fx,
          loader: loaderOf([builtin('default')], timedOut: true),
          environment: env,
        );

        await ready(cubit);

        expect(definitionsOf(cubit).timedOut, isTrue);
        final failed = events('agents_modes.definitions_failed').single;
        expect(failed['reason'], 'timeout');
        expect(failed['level'], 'warning');
      },
    );

    test(
      'an unexpected exception shows the failure and logs its type only',
      () async {
        final fx = await fixture();
        final loader = loaderOf(brokenRows)
          ..script = (call) async => throw const FileSystemException(
            'boom',
            '/Users/demo/.codelab/agents',
          );
        final cubit = make(fx, loader: loader, environment: env);

        await ready(cubit);

        final view = definitionsOf(cubit);
        expect(view.failed, isTrue);
        expect(view.rows, isEmpty);
        final failed = events('agents_modes.definitions_failed').single;
        expect(failed['reason'], 'error');
        expect(failed['error_type'], 'FileSystemException');
        expect(logger.entries.toString(), isNot(contains('/Users/demo')));
        expect(logger.entries.toString(), isNot(contains('boom')));
        // Режим и effort остаются доступными.
        expect(now(cubit).mode, 'standard');
      },
    );

    test(
      'an untrusted project is reported and has no project folder',
      () async {
        final fx = await fixture(trusted: false);
        final cubit = make(
          fx,
          loader: loaderOf(
            [builtin('default')],
            untrusted: true,
            projectDir: null,
          ),
          environment: env,
        );

        await ready(cubit);

        final view = definitionsOf(cubit);
        expect(view.untrustedProject, isTrue);
        expect(view.projectFolderAvailable, isFalse);
      },
    );

    test('a load without an explicit trust flag is fail-closed: the project '
        'is untrusted when its folder is known (3.3a)', () async {
      final fx = await fixture();
      final opener = FakePathOpener();
      final cubit = make(
        fx,
        loader: FakeDefinitionsLoader(
          const AgentDefinitionsLoad(
            rows: [],
            userDirectory: userAgentsDir,
            userDirectoryExists: true,
            projectDirectory: '/work/demo/.codelab/agents',
            projectDirectoryExists: true,
          ),
        ),
        opener: opener,
        environment: env,
      );

      await ready(cubit);

      final view = definitionsOf(cubit);
      expect(view.untrustedProject, isTrue);
      expect(view.projectFolderAvailable, isFalse);
      await cubit.openFolder(AgentsFolder.project);
      expect(opener.untouched, isTrue);
    });

    test('a stdio agent that does not run in the project folder has no '
        'untrusted project and no project item (review 3)', () async {
      final fx = await fixture();
      workspace.emit(
        const WorkspaceState(
          connection: _connected,
          profile: ConnectionProfile.stdio(
            id: 'dev',
            label: 'Dev',
            command: '/opt/bin/codelab-agent',
            args: ['serve', '--stdio'],
            runInProjectDirectory: false,
            env: {'CODELAB_HOME': '/srv/codelab'},
          ),
        ),
      );
      final opener = FakePathOpener();
      final cubit = make(
        fx,
        loader: FakeDefinitionsLoader(
          const AgentDefinitionsLoad(
            rows: [],
            userDirectory: userAgentsDir,
            userDirectoryExists: true,
            projectDirectory: '/work/demo/.codelab/agents',
            projectDirectoryExists: true,
          ),
        ),
        opener: opener,
        environment: env,
      );

      await ready(cubit);

      final view = definitionsOf(cubit);
      expect(opened.single.cwd, isNull);
      expect(view.untrustedProject, isFalse);
      expect(view.projectFolderAvailable, isFalse);
      await cubit.openFolder(AgentsFolder.project);
      expect(opener.untouched, isTrue);
    });

    test(
      'without a project folder there is no untrusted project (3.3a)',
      () async {
        final fx = await fixture();
        final cubit = make(
          fx,
          loader: FakeDefinitionsLoader(
            const AgentDefinitionsLoad(
              rows: [],
              userDirectory: userAgentsDir,
              userDirectoryExists: true,
            ),
          ),
          environment: env,
        );
        projectDir = () => null;

        await ready(cubit);

        expect(definitionsOf(cubit).untrustedProject, isFalse);
      },
    );

    test('the user folder label comes from the real folder, not a constant '
        '(3.1b)', () async {
      final fx = await fixture();
      final cubit = make(
        fx,
        loader: FakeDefinitionsLoader(
          const AgentDefinitionsLoad(
            rows: [],
            userDirectory: '/srv/codelab/agents',
            userDirectoryExists: true,
          ),
        ),
        environment: env,
      );

      await ready(cubit);

      expect(definitionsOf(cubit).userFolderLabel, '/srv/codelab/agents');
    });

    test('the user folder label shortens the home (3.1b)', () async {
      final fx = await fixture();
      final cubit = make(fx, loader: loaderOf(brokenRows), environment: env);

      await ready(cubit);

      expect(definitionsOf(cubit).userFolderLabel, '~/.codelab/agents');
    });

    test('the loaded event counts exactly the error InfoBars, duplicates '
        'included (3.1c)', () async {
      final fx = await fixture();
      final cubit = make(
        fx,
        loader: loaderOf([
          builtin('default'),
          const AgentDefinitionRowView(
            name: 'dup',
            status: AgentRowStatus.duplicate,
            path: '$userAgentsDir/dup.md',
          ),
          const AgentDefinitionRowView(
            name: 'm',
            status: AgentRowStatus.modelNotConfigured,
            path: '$userAgentsDir/m.md',
          ),
          const AgentDefinitionRowView(
            name: 'e',
            status: AgentRowStatus.error,
            path: '$userAgentsDir/e.md',
          ),
          const AgentDefinitionRowView(
            name: 's',
            status: AgentRowStatus.shadowed,
            path: '$userAgentsDir/s.md',
          ),
        ]),
        environment: env,
      );

      await ready(cubit);

      final loaded = events('agents_modes.loaded').single;
      expect(loaded['errors'], 3);
      expect(loaded['errors'], definitionsOf(cubit).errors.length);
      expect(loaded['definitions'], 4);
    });

    test(
      'the loaded event counts file rows and errors, without paths',
      () async {
        final fx = await fixture();
        final cubit = make(fx, loader: loaderOf(brokenRows), environment: env);

        await ready(cubit);

        final loaded = events('agents_modes.loaded').single;
        expect(loaded['definitions'], 2);
        expect(loaded['errors'], 1);
        expect(logger.entries.toString(), isNot(contains('migrator')));
      },
    );

    group('Open file и Open folder', () {
      test('"Open file" passes the path from the state and logs the kind '
          'and the outcome without the path', () async {
        final fx = await fixture();
        final opener = FakePathOpener();
        final cubit = make(
          fx,
          loader: loaderOf(brokenRows),
          opener: opener,
          environment: env,
        );
        await ready(cubit);

        await cubit.openDefinitionFile(migrator);

        expect(opener.files, [migrator]);
        final opened = events('agents_modes.open_path').single;
        expect(opened['kind'], 'file');
        expect(opened['outcome'], 'opened');
        expect(opened['level'], 'info');
        expect(logger.entries.toString(), isNot(contains('migrator')));
        expect(definitionsOf(cubit).openFailure, isNull);
      });

      test('a path that is not in the state is not_allowed and never reaches '
          'the port', () async {
        final fx = await fixture();
        final opener = FakePathOpener();
        final cubit = make(
          fx,
          loader: loaderOf(brokenRows),
          opener: opener,
          environment: env,
        );
        await ready(cubit);

        await cubit.openDefinitionFile('/etc/passwd');
        await cubit.openDefinitionFile('$userDir/../../.ssh/id_rsa');

        expect(opener.untouched, isTrue);
        final outcomes = events('agents_modes.open_path');
        expect(outcomes.map((e) => e['outcome']), everyElement('not_allowed'));
        expect(logger.entries.toString(), isNot(contains('passwd')));
      });

      test('a refusal of the port (a symlinked folder) shows the open-failed '
          'state too', () async {
        final fx = await fixture();
        final opener = FakePathOpener()
          ..directoryOutcome = PathOpenOutcome.notAllowed;
        final cubit = make(
          fx,
          loader: loaderOf([builtin('default')]),
          opener: opener,
          environment: env,
        );
        await ready(cubit);

        await cubit.openFolder(AgentsFolder.user);

        expect(definitionsOf(cubit).openFailure, '~/.codelab/agents');
        expect(
          events('agents_modes.open_path').single['outcome'],
          'not_allowed',
        );
      });

      test(
        'a refusal of the port for a file shows the open-failed state',
        () async {
          final fx = await fixture();
          final opener = FakePathOpener()
            ..fileOutcome = PathOpenOutcome.notAllowed;
          final cubit = make(
            fx,
            loader: loaderOf(brokenRows),
            opener: opener,
            environment: env,
          );
          await ready(cubit);

          await cubit.openDefinitionFile(migrator);

          expect(definitionsOf(cubit).openFailure, isNotNull);
        },
      );

      test('a failure of the platform shows the open-failed state', () async {
        final fx = await fixture();
        final opener = FakePathOpener()..fileOutcome = PathOpenOutcome.failed;
        final cubit = make(
          fx,
          loader: loaderOf(brokenRows),
          opener: opener,
          environment: env,
        );
        await ready(cubit);

        await cubit.openDefinitionFile(migrator);

        expect(definitionsOf(cubit).openFailure, isNotNull);
        expect(events('agents_modes.open_path').single['outcome'], 'failed');
      });

      test('"User definitions" asks the port to create the folder and logs '
          '"created" (Пользовательского каталога нет)', () async {
        final fx = await fixture();
        final opener = FakePathOpener();
        final cubit = make(
          fx,
          loader: loaderOf([builtin('default')], userExists: false),
          opener: opener,
          environment: env,
        );
        await ready(cubit);

        await cubit.openFolder(AgentsFolder.user);

        expect(opener.directories, [(path: userDir, create: true)]);
        final opened = events('agents_modes.open_path').single;
        expect(opened['kind'], 'user_dir');
        expect(opened['outcome'], 'created');
      });

      test('an existing user folder is opened with create too (the port '
          'creates only what is missing)', () async {
        final fx = await fixture();
        final opener = FakePathOpener()
          ..directoryOutcome = PathOpenOutcome.opened;
        final cubit = make(
          fx,
          loader: loaderOf([builtin('default')]),
          opener: opener,
          environment: env,
        );
        await ready(cubit);

        await cubit.openFolder(AgentsFolder.user);

        expect(events('agents_modes.open_path').single['outcome'], 'opened');
      });

      test('a failed creation shows the open-failed state', () async {
        final fx = await fixture();
        final opener = FakePathOpener()
          ..directoryOutcome = PathOpenOutcome.failed;
        final cubit = make(
          fx,
          loader: loaderOf([builtin('default')], userExists: false),
          opener: opener,
          environment: env,
        );
        await ready(cubit);

        await cubit.openFolder(AgentsFolder.user);

        expect(definitionsOf(cubit).openFailure, isNotNull);
      });

      test('the project folder of a trusted project is opened WITHOUT create '
          '(Q11)', () async {
        final fx = await fixture();
        const projectAgents = '/work/demo/.codelab/agents';
        final opener = FakePathOpener();
        final cubit = make(
          fx,
          loader: loaderOf(
            [builtin('default')],
            projectDir: projectAgents,
            projectExists: true,
          ),
          opener: opener,
          environment: env,
        );
        await ready(cubit);

        expect(definitionsOf(cubit).projectFolderAvailable, isTrue);
        expect(definitionsOf(cubit).projectFolderExists, isTrue);
        await cubit.openFolder(AgentsFolder.project);

        expect(opener.directories, [(path: projectAgents, create: false)]);
        expect(events('agents_modes.open_path').single['kind'], 'project_dir');
      });

      test('a missing project folder is never created by the app '
          '(Проектного каталога нет)', () async {
        final fx = await fixture();
        final opener = FakePathOpener();
        final cubit = make(
          fx,
          loader: loaderOf(
            [builtin('default')],
            projectDir: '/work/demo/.codelab/agents',
            projectExists: false,
          ),
          opener: opener,
          environment: env,
        );
        await ready(cubit);

        expect(definitionsOf(cubit).projectFolderAvailable, isTrue);
        expect(definitionsOf(cubit).projectFolderExists, isFalse);
        await cubit.openFolder(AgentsFolder.project);

        expect(opener.untouched, isTrue);
        expect(
          events('agents_modes.open_path').single['outcome'],
          'not_allowed',
        );
      });

      test('an untrusted project is not opened even if the loader names an '
          'existing project folder', () async {
        final fx = await fixture(trusted: false);
        final opener = FakePathOpener();
        final cubit = make(
          fx,
          loader: loaderOf(
            [builtin('default')],
            untrusted: true,
            projectDir: '/work/demo/.codelab/agents',
            projectExists: true,
          ),
          opener: opener,
          environment: env,
        );
        await ready(cubit);

        await cubit.openFolder(AgentsFolder.project);

        expect(opener.untouched, isTrue);
        final opened = events('agents_modes.open_path').single;
        expect(opened['kind'], 'project_dir');
        expect(opened['outcome'], 'not_allowed');
      });

      test('an untrusted project has no project folder to open '
          '(Проект без доверия)', () async {
        final fx = await fixture(trusted: false);
        final opener = FakePathOpener();
        final cubit = make(
          fx,
          loader: loaderOf([builtin('default')], untrusted: true),
          opener: opener,
          environment: env,
        );
        await ready(cubit);

        await cubit.openFolder(AgentsFolder.project);

        expect(opener.untouched, isTrue);
        expect(
          events('agents_modes.open_path').single['outcome'],
          'not_allowed',
        );
      });
    });
  });
}
