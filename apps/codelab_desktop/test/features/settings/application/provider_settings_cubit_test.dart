// `ProviderSettingsCubit` (задача 2.6 change `add-provider-setup-ui`; spec
// app-settings «Страница «Providers»», «Доступ к настройкам агента на
// страницах Providers и MCP servers»; design.md D5, D10, D18, D21).
//
// Конфиг, секреты и проверка — двойники (`fake_provider_settings.dart`):
// запись файла и порядок «конфиг → секрет» проверяет мост, здесь — что
// страница показывает и вызывает. Маркер `sk-test-leak-…` лежит только в
// «хранилище» двойника: Cubit, состояние и журнал его видеть не должны
// (SETUP-1).

import 'dart:async';
import 'dart:io';

import 'package:codelab_acp_protocol/codelab_acp_protocol.dart' show SessionId;
import 'package:codelab_client_core/codelab_client_core.dart';
import 'package:codelab_desktop/features/settings/application/embedded_profile.dart';
import 'package:codelab_desktop/features/settings/application/provider_settings_cubit.dart';
import 'package:codelab_setup/codelab_setup.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../../support/fake_provider_settings.dart';
import '../../../support/real_config_session.dart';
import '../../../support/recording_logger.dart';

const _home = '/home/u/.codelab';

final _remote = ConnectionProfile.webSocket(
  id: 'devbox',
  label: 'Devbox',
  uri: Uri.parse('wss://devbox:7420/acp?t=$leakMarker'),
);

const _foreign = ConnectionProfile.stdio(
  id: 'other',
  label: 'Other',
  command: 'python',
  args: ['-m', 'other_agent'],
);

const _ownAgent = ConnectionProfile.stdio(
  id: 'dev',
  label: 'Dev',
  command: '/opt/bin/codelab-agent',
  args: ['serve', '--stdio'],
  env: {'CODELAB_HOME': '/srv/codelab'},
);

Map<String, Object?> _two({String? defaultModel = 'anthropic/m'}) => {
  'agent': {'default_model': ?defaultModel},
  'providers': {
    'anthropic': providerMap(
      kind: 'anthropic',
      baseUrl: null,
      secret: 'codelab/anthropic',
    ),
    'local': providerMap(
      baseUrl: 'http://localhost:11434/v1',
      models: ['qwen'],
    ),
  },
};

void main() {
  late FakeAgentConfigStore store;
  late FakeProviderSettingsSession session;
  late FakeWorkspace workspace;
  late RecordingLogger logger;
  late ConnectionProfile defaultProfile;
  late List<({EditableSettings access, Map<String, String> env})> opened;
  late List<ProviderSettingsCubit> cubits;
  String? projectDir = '/work/app';

  ProviderSettingsCubit make({
    Map<String, String> environment = const {'HOME': '/home/u'},
    String? home = _home,
  }) {
    final cubit = ProviderSettingsCubit(
      workspace: workspace,
      defaultProfile: () async => defaultProfile,
      open: (access, env) async {
        opened.add((access: access, env: env));
        return session;
      },
      environment: environment,
      codelabHome: home,
      projectDirectory: () => projectDir,
      logger: logger,
      now: () => DateTime(2026, 11, 6, 14, 1),
    );
    cubits.add(cubit);
    return cubit;
  }

  setUp(() {
    store = FakeAgentConfigStore(user: _two());
    session = FakeProviderSettingsSession(
      store,
      secrets: {'codelab/anthropic': leakMarker},
    );
    workspace = FakeWorkspace();
    logger = RecordingLogger();
    defaultProfile = embeddedConnectionProfile;
    opened = [];
    cubits = [];
    projectDir = '/work/app';
  });

  tearDown(() async {
    for (final cubit in cubits) {
      await cubit.close();
    }
  });

  Future<ProviderSettingsReady> ready(ProviderSettingsCubit cubit) async {
    await cubit.reload();
    return cubit.state as ProviderSettingsReady;
  }

  ProviderRow row(ProviderSettingsReady state, String id) =>
      state.rows.firstWhere((r) => r.id == id);

  group('rows', () {
    test(
      'shows the rows of the user layer with the section 12.4.9 texts',
      () async {
        final state = await ready(make());

        expect(state.rows.map((r) => r.id), ['anthropic', 'local']);
        final anthropic = row(state, 'anthropic');
        expect(anthropic.isDefault, isTrue);
        expect(
          anthropic.subtitle,
          'anthropic · Anthropic · Key: in file · 1 model',
        );
        expect(anthropic.editable, isTrue);
        expect(
          row(state, 'local').subtitle,
          'local · OpenAI-compatible · http://localhost:11434/v1 · No key · '
          '1 model',
        );
        expect(state.defaultModel, 'anthropic/m');
        expect(state.models, ['anthropic/m', 'local/qwen']);
        expect(state.configPath, '~/.codelab/config.yaml');
        expect(state.keyStorage.openFilePath, '~/.codelab/secrets.yaml');
        expect(state.keyStorage.backendId, 'file');
        expect(state.keyStorage.writable, isTrue);
      },
    );

    test(
      'the key status is computed without reading a value (SETUP-1)',
      () async {
        store.user = {
          'providers': {
            'anthropic': providerMap(secret: 'codelab/anthropic'),
            'openai': providerMap(env: 'OPENAI_API_KEY'),
            'team': providerMap(secret: 'codelab/team'),
          },
        };

        final state = await ready(
          make(environment: {'OPENAI_API_KEY': leakMarker}),
        );

        expect(row(state, 'anthropic').keyLabel, 'Key: in file');
        expect(row(state, 'openai').keyLabel, 'Key: env OPENAI_API_KEY (set)');
        expect(row(state, 'team').keyLabel, 'Key: missing in file');
        expect(
          session.isSetCalls,
          containsAll(['codelab/anthropic', 'codelab/team']),
        );
        expect(state.toString(), isNot(contains(leakMarker)));
        expect(logger.entries.toString(), isNot(contains(leakMarker)));
      },
    );

    test('a project-layer provider is shown as defined in the file and is not '
        'editable', () async {
      store.project = {
        'providers': {
          'team': providerMap(models: ['big']),
        },
      };

      final state = await ready(make());

      final team = row(state, 'team');
      expect(team.editable, isFalse);
      expect(team.canRemove, isFalse);
      expect(
        team.subtitle,
        endsWith('· defined in ${FakeAgentConfigStore.projectPath}'),
      );
      expect(row(state, 'anthropic').editable, isTrue);
    });

    test('a provider of the local project layer is editable', () async {
      store.projectLocal = {
        'providers': {'mine': providerMap()},
      };

      final state = await ready(make());

      expect(row(state, 'mine').editable, isTrue);
    });

    test('an empty config gives no rows and no failure', () async {
      store.user = {};

      final state = await ready(make());

      expect(state.rows, isEmpty);
      expect(state.defaultModel, isNull);
    });

    test(
      'start problems (missing keys) do not make the page Unreadable',
      () async {
        store.user = {};
        store.issues = [
          const ConfigIssue(
            kind: ConfigIssueKind.value,
            key: 'agent.default_model',
            source: 'config',
            message: 'required',
          ),
        ];

        final cubit = make();
        await cubit.reload();

        final state = cubit.state as ProviderSettingsReady;
        expect(state.rows, isEmpty);
      },
    );

    test('a user layer that cannot be read is Unreadable', () async {
      store.omitUserLayer = true;
      final cubit = make();
      await cubit.reload();

      expect(cubit.state, isA<ProviderSettingsUnreadable>());
    });

    test('a broken config.yaml is Unreadable with the loader problems and '
        'is never written', () async {
      store.issues = [
        const ConfigIssue(
          kind: ConfigIssueKind.value,
          key: 'providers.anthropic.kind',
          source: FakeAgentConfigStore.userPath,
          message: 'must be one of openai-compatible',
        ),
      ];

      final cubit = make();
      await cubit.reload();

      final state = cubit.state as ProviderSettingsUnreadable;
      expect(state.problems.single, contains('providers.anthropic.kind'));
      expect(
        logger.entries.map((e) => e['event']),
        contains('provider_settings.unreadable'),
      );
      expect(store.applied, isEmpty);
    });
  });

  group('whose settings', () {
    test('the embedded profile is editable with the app home and the project '
        'folder', () async {
      await make().reload();

      final access = opened.single.access;
      expect(access.paths.codelabHome, _home);
      expect(access.cwd, '/work/app');
      expect(logger.entries.last['event'], 'provider_settings.loaded');
    });

    test('without a project and an agent there is no folder: the settings are '
        'editable, with no project layer among the targets (D8)', () async {
      projectDir = null;

      await make().reload();

      final access = opened.single.access;
      expect(access.cwd, isNull);
      expect(access.targets, [const ConfigTarget.user()]);
    });

    test(
      'a WebSocket agent is read-only and the local file is not read',
      () async {
        workspace.emit(
          WorkspaceState(
            connection: const ConnectionView.connected(),
            profile: _remote,
          ),
        );

        final cubit = make();
        await cubit.reload();

        final state = cubit.state as ProviderSettingsReadOnly;
        expect(
          state.notice,
          'Read-only: this agent runs on wss://devbox:7420.',
        );
        expect(state.hint, contains('codelab provider add'));
        expect(opened, isEmpty);
        expect(store.snapshots, 0);
        expect(state.toString(), isNot(contains(leakMarker)));
      },
    );

    test('a third-party stdio agent is managed by itself', () async {
      workspace.emit(
        const WorkspaceState(
          connection: ConnectionView.connected(),
          profile: _foreign,
        ),
      );

      final cubit = make();
      await cubit.reload();

      final state = cubit.state as ProviderSettingsReadOnly;
      expect(state.notice, 'Provider settings are managed by python.');
      expect(opened, isEmpty);
    });

    test('codelab-agent with CODELAB_HOME in its env uses that home and '
        'no project layer without runInProjectDirectory', () async {
      workspace.emit(
        const WorkspaceState(
          connection: ConnectionView.connected(),
          profile: _ownAgent,
        ),
      );

      await make().reload();

      final access = opened.single.access;
      expect(access.paths.codelabHome, '/srv/codelab');
      expect(access.cwd, isNull);
      expect(access.targets, hasLength(1));
      expect(opened.single.env['CODELAB_HOME'], '/srv/codelab');
    });

    test('without a connection the default profile decides', () async {
      defaultProfile = _remote;

      final cubit = make();
      await cubit.reload();

      expect(cubit.state, isA<ProviderSettingsReadOnly>());
    });

    test('a connection change re-reads the access', () async {
      final cubit = make();
      await cubit.reload();
      expect(cubit.state, isA<ProviderSettingsReady>());

      final readOnly = cubit.stream.firstWhere(
        (state) => state is ProviderSettingsReadOnly,
      );
      workspace.emit(
        WorkspaceState(
          connection: const ConnectionView.connected(),
          profile: _remote,
        ),
      );
      await readOnly;

      expect(cubit.state, isA<ProviderSettingsReadOnly>());
    });

    test('an invalid CODELAB_HOME is Unreadable', () async {
      final cubit = make(home: null);
      await cubit.reload();

      expect(cubit.state, isA<ProviderSettingsUnreadable>());
      expect(opened, isEmpty);
    });
  });

  group('active model of the session', () {
    ConfigOptionView modelOption(String value) => ConfigOptionView(
      id: 'model',
      name: 'Model',
      currentValue: value,
      values: [ConfigOptionValueView(value: value, name: value)],
    );

    test(
      'shows the model option of the active session and follows it',
      () async {
        const id = SessionId('s1');
        final handle = FakeSessionHandle(
          SessionView(
            revision: 1,
            status: SessionStatusView.idle,
            configOptions: [modelOption('local/qwen')],
          ),
        );
        workspace.handles[id] = handle;
        workspace.emit(
          const WorkspaceState(
            connection: ConnectionView.connected(),
            profile: embeddedConnectionProfile,
            activeSessionId: id,
          ),
        );

        final cubit = make();
        final state = await ready(cubit);
        expect(state.activeModel, 'local/qwen');

        handle.emit(
          SessionView(
            revision: 2,
            status: SessionStatusView.idle,
            configOptions: [modelOption('anthropic/m')],
          ),
        );
        expect(
          (cubit.state as ProviderSettingsReady).activeModel,
          'anthropic/m',
        );
      },
    );

    test('no session or no model option: no active model', () async {
      final state = await ready(make());

      expect(state.activeModel, isNull);
    });
  });

  group('Default model', () {
    test('writes agent.default_model to the layer that defines it', () async {
      store.user = {'providers': _two()['providers']};
      store.projectLocal = {
        'agent': {'default_model': 'anthropic/m'},
      };
      final cubit = make();
      await cubit.reload();

      await cubit.setDefaultModel('local/qwen');

      final call = store.applied.single;
      expect(call.base.target, isA<ConfigTarget>());
      expect(call.base.path, FakeAgentConfigStore.projectLocalPath);
      expect(call.edits, [const SetValue('agent.default_model', 'local/qwen')]);
      expect(
        logger.entries.any(
          (e) =>
              e['event'] == 'provider_settings.default_model_changed' &&
              e['provider_id'] == 'local',
        ),
        isTrue,
      );
    });

    test('writes to the user layer when the key is defined in a read-only '
        'one', () async {
      store.project = {
        'agent': {'default_model': 'anthropic/m'},
      };
      final cubit = make();
      await cubit.reload();

      await cubit.setDefaultModel('local/qwen');

      expect(store.applied.single.base.path, FakeAgentConfigStore.userPath);
    });

    test('a model that no provider offers is ignored', () async {
      final cubit = make();
      await cubit.reload();

      await cubit.setDefaultModel('ghost/none');

      expect(store.applied, isEmpty);
    });

    test('a conflict shows the banner, re-reads the snapshot and writes '
        'nothing more', () async {
      final cubit = make();
      await cubit.reload();
      final before = store.snapshots;
      store.nextOutcome = const ConfigConflict(FakeAgentConfigStore.userPath);

      await cubit.setDefaultModel('local/qwen');

      expect(store.applied, hasLength(1));
      expect(store.snapshots, greaterThan(before));
      final state = cubit.state as ProviderSettingsReady;
      expect(state.banner?.kind, ProviderBannerKind.conflict);
      expect(state.saving, isFalse);
    });

    test('a rejected config shows an error banner', () async {
      final cubit = make();
      await cubit.reload();
      store.nextOutcome = const ConfigRejected([
        ConfigIssue(
          kind: ConfigIssueKind.value,
          key: 'agent.default_model',
          source: 'x',
          message: 'unknown model',
        ),
      ]);

      await cubit.setDefaultModel('local/qwen');

      final state = cubit.state as ProviderSettingsReady;
      expect(state.banner?.kind, ProviderBannerKind.error);
      expect(state.banner?.text, contains('agent.default_model'));
    });
  });

  group('Check', () {
    test('a wrong key: unauthorized, and no value in state or log', () async {
      session.checkResult = () async => const CheckFailure(
        ProviderCheckFailure(
          kind: ProviderCheckFailureKind.unauthorized,
          statusCode: 401,
          message: 'the server rejected the key',
        ),
      );
      final cubit = make();
      await cubit.reload();

      await cubit.check('anthropic');

      final state = cubit.state as ProviderSettingsReady;
      expect(row(state, 'anthropic').check.label, 'unauthorized');
      expect(session.checks.single.key, isA<KeyInSecretStore>());
      expect(
        session.checks.single.baseUrl.toString(),
        'https://api.anthropic.com',
      );
      expect(
        state.toString() + row(state, 'anthropic').toString(),
        isNot(contains(leakMarker)),
      );
      expect(logger.entries.toString(), isNot(contains(leakMarker)));
      final finished = logger.entries.firstWhere(
        (e) => e['event'] == 'provider_settings.check_finished',
      );
      expect(finished['provider_id'], 'anthropic');
      expect(finished['outcome'], 'unauthorized');
      expect(finished['operation_id'], isNotNull);
    });

    test('a successful check shows models, time and duration', () async {
      session.checkResult = () async =>
          const CheckOk([RemoteModel('a'), RemoteModel('b'), RemoteModel('c')]);
      final cubit = make();
      await cubit.reload();

      await cubit.check('local');

      final check = row(cubit.state as ProviderSettingsReady, 'local').check;
      expect(check.label, 'ok, 3 models');
      expect(check.detail, startsWith('14:01 · 3 models · '));
    });

    test('every refusal kind has its tag', () async {
      const labels = {
        ProviderCheckFailureKind.unauthorized: 'unauthorized',
        ProviderCheckFailureKind.notFound: 'not found',
        ProviderCheckFailureKind.unreachable: 'unreachable',
        ProviderCheckFailureKind.timeout: 'timeout',
        ProviderCheckFailureKind.tlsError: 'TLS error',
        ProviderCheckFailureKind.badResponse: 'bad response',
      };
      final cubit = make();
      await cubit.reload();
      for (final MapEntry(:key, :value) in labels.entries) {
        session.checkResult = () async =>
            CheckFailure(ProviderCheckFailure(kind: key, message: 'x'));
        await cubit.check('local');
        expect(
          row(cubit.state as ProviderSettingsReady, 'local').check.label,
          value,
        );
      }
    });

    test('a missing key is Key: missing without a request', () async {
      store.user = {
        'providers': {'team': providerMap(secret: 'codelab/team')},
      };
      final cubit = make();
      await cubit.reload();

      await cubit.check('team');

      expect(session.checks, isEmpty);
      expect(
        row(cubit.state as ProviderSettingsReady, 'team').check.label,
        'Key: missing',
      );
    });

    test('a repeated Check discards the earlier result', () async {
      final first = Completer<ProviderCheckResult>();
      final second = Completer<ProviderCheckResult>();
      final results = [first, second];
      session.checkResult = () => results.removeAt(0).future;
      final cubit = make();
      await cubit.reload();

      final a = cubit.check('local');
      final b = cubit.check('local');
      second.complete(const CheckOk([RemoteModel('new')]));
      await b;
      first.complete(
        const CheckFailure(
          ProviderCheckFailure(
            kind: ProviderCheckFailureKind.timeout,
            message: 'late',
          ),
        ),
      );
      await a;

      final check = row(cubit.state as ProviderSettingsReady, 'local').check;
      expect(check.label, 'ok, 1 model');
      expect(
        logger.entries.map((e) => e['event']),
        contains('provider_settings.check_discarded'),
      );
    });

    test(
      'a repeated Check cancels the previous token, the new one stays live',
      () async {
        final gates = [
          Completer<ProviderCheckResult>(),
          Completer<ProviderCheckResult>(),
        ];
        session.checkResult = () => gates.removeAt(0).future;
        final cubit = make();
        await cubit.reload();

        final a = cubit.check('local');
        final b = cubit.check('local');

        expect(session.cancels, hasLength(2));
        expect(session.cancels[0]!.isCancelled, isTrue);
        expect(session.cancels[1]!.isCancelled, isFalse);
        await cubit.close();
        unawaited(a);
        unawaited(b);
      },
    );

    test('CheckCancelled is dropped: the row is not marked and the discard is '
        'logged', () async {
      final first = Completer<ProviderCheckResult>();
      final second = Completer<ProviderCheckResult>();
      final gates = [first, second];
      session.checkResult = () => gates.removeAt(0).future;
      final cubit = make();
      await cubit.reload();

      final a = cubit.check('local');
      final b = cubit.check('local');
      first.complete(const CheckCancelled());
      await a;
      expect(
        row(cubit.state as ProviderSettingsReady, 'local').check.kind,
        ProviderCheckKind.running,
      );
      second.complete(const CheckOk([RemoteModel('x')]));
      await b;

      expect(
        row(cubit.state as ProviderSettingsReady, 'local').check.label,
        'ok, 1 model',
      );
      expect(
        logger.entries.map((e) => e['event']),
        contains('provider_settings.check_discarded'),
      );
    });

    test('a CheckCancelled for a live check frees the row: not running, Check '
        'available again', () async {
      session.checkResult = () async => const CheckCancelled();
      final cubit = make();
      await cubit.reload();

      await cubit.check('local');

      final local = row(cubit.state as ProviderSettingsReady, 'local');
      expect(local.check.kind, ProviderCheckKind.notChecked);
      expect(local.canCheck, isTrue);
      session.checkResult = () async => const CheckOk([RemoteModel('a')]);
      await cubit.check('local');
      expect(
        row(cubit.state as ProviderSettingsReady, 'local').check.label,
        'ok, 1 model',
      );
    });

    test('closing the page cancels the running Check token', () async {
      final gate = Completer<ProviderCheckResult>();
      session.checkResult = () => gate.future;
      final cubit = make();
      await cubit.reload();

      final pending = cubit.check('local');
      expect(session.cancels.single!.isCancelled, isFalse);
      await cubit.close();

      expect(session.cancels.single!.isCancelled, isTrue);
      gate.complete(const CheckCancelled());
      await pending;
    });

    test(
      'a connection change cancels every Check and clears the results',
      () async {
        final gate = Completer<ProviderCheckResult>();
        session.checkResult = () => gate.future;
        final cubit = make();
        await cubit.reload();

        final pending = cubit.check('local');
        final reloaded = cubit.stream.firstWhere(
          (state) => state is ProviderSettingsReadOnly,
        );
        workspace.emit(
          WorkspaceState(
            connection: const ConnectionView.connected(),
            profile: _remote,
          ),
        );
        await reloaded;
        expect(session.cancels.single!.isCancelled, isTrue);
        gate.complete(const CheckOk([RemoteModel('late')]));
        await pending;

        expect(cubit.state, isA<ProviderSettingsReadOnly>());
        workspace.emit(const WorkspaceState());
        final back = cubit.stream.firstWhere(
          (state) => state is ProviderSettingsReady,
        );
        await back;
        expect(
          row(cubit.state as ProviderSettingsReady, 'local').check.label,
          'not checked',
        );
        expect(
          logger.entries.where(
            (e) =>
                e['event'] == 'provider_settings.check_discarded' &&
                e['outcome'] == 'superseded',
          ),
          hasLength(1),
        );
      },
    );

    test(
      'a provider that disappears on reload loses its running Check',
      () async {
        final gate = Completer<ProviderCheckResult>();
        session.checkResult = () => gate.future;
        final cubit = make();
        await cubit.reload();

        final pending = cubit.check('local');
        store.user = {
          'providers': {'anthropic': providerMap(secret: 'codelab/anthropic')},
        };
        await cubit.reload();

        expect(session.cancels.single!.isCancelled, isTrue);
        gate.complete(const CheckOk([RemoteModel('late')]));
        await pending;
        expect((cubit.state as ProviderSettingsReady).rows.map((r) => r.id), [
          'anthropic',
        ]);
      },
    );

    test('an unencrypted http provider to a remote host gets a warning with '
        'the host only; local hosts and keyless providers do not', () async {
      store.user = {
        'providers': {
          'remote': providerMap(
            baseUrl: 'http://api.example.com:8080/v1?t=$leakMarker',
            env: 'REMOTE_KEY',
          ),
          'secure': providerMap(
            baseUrl: 'https://api.example.com/v1',
            env: 'K',
          ),
          'local': providerMap(baseUrl: 'http://localhost:11434/v1', env: 'K'),
          'loop': providerMap(baseUrl: 'http://127.0.0.1:1/v1', env: 'K'),
          'nokey': providerMap(baseUrl: 'http://api.example.com/v1'),
        },
      };
      final state = await ready(make(environment: {'REMOTE_KEY': 'x'}));

      expect(row(state, 'remote').unencryptedHost, 'api.example.com');
      for (final id in ['secure', 'local', 'loop', 'nokey']) {
        expect(row(state, id).unencryptedHost, isNull, reason: id);
      }
      expect(row(state, 'remote').canCheck, isTrue);
      expect(
        state.toString() + row(state, 'remote').toString(),
        isNot(contains(leakMarker)),
      );
    });

    test(
      'a kind without a model-list check has Check off and says why',
      () async {
        store.user = {
          'providers': {
            'g': providerMap(kind: 'gemini', baseUrl: null, env: 'G'),
            'local': providerMap(),
          },
        };
        final cubit = make(environment: {'G': 'x'});
        final state = await ready(cubit);

        expect(row(state, 'g').canCheck, isFalse);
        expect(
          row(state, 'g').checkHint,
          'Check is not available for gemini providers yet.',
        );
        await cubit.check('g');
        expect(session.checks, isEmpty);
        expect(row(state, 'local').canCheck, isTrue);
        expect(row(state, 'local').checkHint, isNull);
      },
    );

    test('the subtitle shows the address without userinfo and query', () async {
      store.user = {
        'providers': {
          'p': providerMap(
            baseUrl: 'https://user:pw@h.example/v1?t=$leakMarker#frag',
          ),
        },
      };
      final state = await ready(make());

      final subtitle = row(state, 'p').subtitle;
      expect(subtitle, contains('https://h.example/v1'));
      expect(subtitle, isNot(contains(leakMarker)));
      expect(subtitle, isNot(contains('pw')));
      expect(subtitle, isNot(contains('user')));
      expect(
        state.toString() + row(state, 'p').toString(),
        isNot(contains(leakMarker)),
      );
    });

    test('a literal key in config.yaml: Check is off, the hint names the '
        'migration, and the value is never read', () async {
      store.user = {
        'providers': {
          'lit': {...providerMap(), 'api_key': leakMarker},
          'local': providerMap(),
        },
      };
      final cubit = make();
      final state = await ready(cubit);

      final lit = row(state, 'lit');
      expect(lit.canCheck, isFalse);
      expect(
        lit.keyHint,
        'The key is written in config.yaml. Move it to the secret store: '
        'codelab secret migrate.',
      );
      await cubit.check('lit');
      expect(session.checks, isEmpty);
      expect(state.toString() + lit.toString(), isNot(contains(leakMarker)));
      expect(logger.entries.toString(), isNot(contains(leakMarker)));
      expect(row(state, 'local').canCheck, isTrue);
      expect(row(state, 'local').keyHint, isNull);
    });

    test(
      'closing the page during Check discards the result and logs it',
      () async {
        final gate = Completer<ProviderCheckResult>();
        session.checkResult = () => gate.future;
        final cubit = make();
        await cubit.reload();

        final pending = cubit.check('local');
        await cubit.close();
        gate.complete(const CheckOk([RemoteModel('late')]));
        await pending;

        expect(
          logger.entries.map((e) => e['event']),
          contains('provider_settings.check_discarded'),
        );
        expect(
          logger.entries.map((e) => e['event']),
          isNot(contains('provider_settings.check_finished')),
        );
      },
    );
  });

  group('Remove', () {
    test('the plan of a default provider asks for a new default model and '
        'offers the owned key', () async {
      final cubit = make();
      await cubit.reload();

      final plan = cubit.removalPlan('anthropic')!;

      expect(plan.needsNewDefault, isTrue);
      expect(plan.newDefaultChoices, ['local/qwen']);
      expect(plan.offersKeyDeletion, isTrue);
      expect(cubit.removalPlan('local')!.offersKeyDeletion, isFalse);
      expect(cubit.removalPlan('local')!.needsNewDefault, isFalse);
    });

    test('removes the default provider, sets the new default in one apply '
        'and deletes the key only after the config is saved', () async {
      final journal = <String>[];
      store.onApply = () => journal.add('apply');
      session.onDelete = (name) => journal.add('delete $name');
      final cubit = make();
      await cubit.reload();

      final done = await cubit.remove(
        'anthropic',
        newDefaultModel: 'local/qwen',
        deleteStoredKey: true,
      );

      expect(done, isTrue);
      expect(store.applied, hasLength(1));
      expect(store.applied.single.edits, [
        const RemoveTable('providers.anthropic'),
        const SetValue('agent.default_model', 'local/qwen'),
      ]);
      expect(journal, ['apply', 'delete codelab/anthropic']);
      expect(
        logger.entries.any(
          (e) =>
              e['event'] == 'provider_settings.removed' &&
              e['provider_id'] == 'anthropic' &&
              e['key_deleted'] == true,
        ),
        isTrue,
      );
      expect(logger.entries.toString(), isNot(contains('codelab/anthropic')));
    });

    test('a key that other settings still use is kept and the banner says '
        'so', () async {
      store.onApply = () {
        store.user['mcp'] = {'x': r'${secret:codelab/anthropic}'};
      };
      final cubit = make();
      await cubit.reload();

      await cubit.remove(
        'anthropic',
        newDefaultModel: 'local/qwen',
        deleteStoredKey: true,
      );

      expect(session.deleted, isEmpty);
      final banner = (cubit.state as ProviderSettingsReady).banner!;
      expect(
        banner.text,
        'Provider anthropic removed. The stored key codelab/anthropic is '
        'kept because other settings still use it.',
      );
    });

    test('a refused save keeps the secret', () async {
      store.nextOutcome = const ConfigConflict(FakeAgentConfigStore.userPath);
      final cubit = make();
      await cubit.reload();

      final done = await cubit.remove(
        'anthropic',
        newDefaultModel: 'local/qwen',
        deleteStoredKey: true,
      );

      expect(done, isFalse);
      expect(session.deleted, isEmpty);
      expect(
        (cubit.state as ProviderSettingsReady).banner?.kind,
        ProviderBannerKind.conflict,
      );
    });

    test('Edit follows the Remove refusals: several layers make it inactive '
        'with the same hint (task 3.4)', () async {
      store.projectLocal = {
        'providers': {
          'local': {'base_url': 'http://localhost:9999/v1'},
        },
      };
      final state = await ready(make());

      final local = row(state, 'local');
      expect(local.canEdit, isFalse);
      expect(
        local.editHint,
        'This provider is defined in several config files. Change it there.',
      );
      expect(row(state, 'anthropic').canEdit, isTrue);
      expect(row(state, 'anthropic').editHint, isNull);
    });

    test(
      'Edit is absent for a project-layer provider (not editable)',
      () async {
        store.project = {
          'providers': {
            'team': providerMap(models: ['big']),
          },
        };
        final state = await ready(make());

        expect(row(state, 'team').editable, isFalse);
        expect(row(state, 'team').canEdit, isFalse);
      },
    );

    test('the wizard opens on the session of the page with the row as the '
        'entry; the Cubit never touches the key port (SETUP-1)', () async {
      final cubit = make();
      await ready(cubit);

      final wizard = await cubit.openWizard(editId: 'anthropic');

      expect(wizard, isNotNull);
      expect(session.wizards.single.editing!.id, 'anthropic');
      expect(wizard!.editing, isTrue);
      expect(session.lastKeys!.journal, isEmpty);
      await wizard.close();
    });

    test('the wizard is not opened without a writable session', () async {
      defaultProfile = _remote;
      final cubit = make();
      await cubit.reload();

      expect(await cubit.openWizard(), isNull);
      expect(session.wizards, isEmpty);
    });

    test('the last provider cannot be removed', () async {
      store.user = {
        'providers': {'only': providerMap()},
      };
      final cubit = make();
      final state = await ready(cubit);

      final only = row(state, 'only');
      expect(only.canRemove, isFalse);
      expect(
        only.removeHint,
        'The agent needs at least one provider. Add another provider first.',
      );
      expect(await cubit.remove('only'), isFalse);
      expect(store.applied, isEmpty);
    });

    test('a repeated Remove while saving is ignored', () async {
      final gate = Completer<void>();
      store.onApply = () => gate.future;
      final cubit = make();
      await cubit.reload();

      final first = cubit.remove('local');
      expect((cubit.state as ProviderSettingsReady).saving, isTrue);
      final second = await cubit.remove('local');
      gate.complete();
      await first;

      expect(second, isFalse);
      expect(store.applied, hasLength(1));
    });

    test('Remove cancels the running Check of that provider', () async {
      final gate = Completer<ProviderCheckResult>();
      session.checkResult = () => gate.future;
      final cubit = make();
      await cubit.reload();

      final pending = cubit.check('local');
      await cubit.remove('local');
      expect(session.cancels.single!.isCancelled, isTrue);
      gate.complete(const CheckOk([RemoteModel('late')]));
      await pending;

      expect(
        (cubit.state as ProviderSettingsReady).rows.map((r) => r.id),
        isNot(contains('local-checked')),
      );
      expect(
        logger.entries.map((e) => e['event']),
        isNot(contains('provider_settings.check_finished')),
      );
    });

    test(
      'a reload during apply keeps saving and still allows one write only',
      () async {
        final gate = Completer<void>();
        store.onApply = () => gate.future;
        final cubit = make();
        await cubit.reload();

        final first = cubit.remove('local');
        await cubit.reload();
        expect((cubit.state as ProviderSettingsReady).saving, isTrue);
        expect(
          await cubit.remove('anthropic', newDefaultModel: 'local/qwen'),
          isFalse,
        );
        gate.complete();
        await first;

        expect(store.applied, hasLength(1));
        expect((cubit.state as ProviderSettingsReady).saving, isFalse);
      },
    );

    test(
      'an unsuccessful write logs save_failed with the outcome kind only',
      () async {
        final cubit = make();
        await cubit.reload();
        final outcomes = <ConfigSaveOutcome, String>{
          const ConfigConflict(FakeAgentConfigStore.userPath): 'conflict',
          const ConfigRejected([
            ConfigIssue(
              kind: ConfigIssueKind.value,
              key: 'agent.default_model',
              source: 'x',
              message: 'bad $leakMarker',
            ),
          ]): 'rejected',
          const ConfigInlineSecret(
            key: 'providers.x.api_key',
            suggestedSecretName: 'codelab/x',
          ): 'inline_secret',
        };
        for (final MapEntry(:key, :value) in outcomes.entries) {
          store.nextOutcome = key;
          await cubit.setDefaultModel('local/qwen');
          final event = logger.entries.lastWhere(
            (e) => e['event'] == 'provider_settings.save_failed',
          );
          expect(event['outcome'], value);
          expect(event['level'], 'warning');
        }
        expect(logger.entries.toString(), isNot(contains(leakMarker)));
      },
    );

    test('a read-only provider is not removed', () async {
      store.project = {
        'providers': {'team': providerMap()},
      };
      final cubit = make();
      await cubit.reload();

      expect(await cubit.remove('team'), isFalse);
      expect(store.applied, isEmpty);
    });
  });

  // Ревью 6a, Q35: мастер, открытый со страницы «Providers», берёт снимок
  // «до» у Cubit страницы и после записи называет провайдера, который агент
  // применит только после «Restart agent». Настоящее хранилище во временном
  // `CODELAB_HOME`, правило даёт мост.
  test('a wizard opened from the page points to Restart agent after a new '
      'provider with a key', () async {
    final root = Directory.systemTemp.createTempSync('codelab_providers_hint_');
    addTearDown(() => root.deleteSync(recursive: true));
    Directory('${root.path}/home').createSync();
    Directory('${root.path}/project').createSync();
    final real = await RealConfigSession.open(
      home: '${root.path}/home',
      project: '${root.path}/project',
    );
    real.environment = const {'LLM_KEY': 'value-from-env'};
    workspace.emit(
      WorkspaceState(
        connection: const ConnectionView.connected(),
        profile: embeddedConnectionProfile,
      ),
    );
    final page = ProviderSettingsCubit(
      workspace: workspace,
      defaultProfile: () async => embeddedConnectionProfile,
      open: (access, env) async => real,
      environment: const {'HOME': '/home/u'},
      codelabHome: '${root.path}/home',
      projectDirectory: () => '${root.path}/project',
    );
    cubits.add(page);
    await page.reload();

    final wizard = (await page.openWizard())!;
    wizard.dispatch(const PresetChosen('custom-openai'));
    await pumpEventQueue();
    wizard.dispatch(const BaseUrlSubmitted('https://llm.example/v1'));
    await pumpEventQueue();
    wizard.dispatch(const KeySubmitted(UseEnvVar('LLM_KEY')));
    await pumpEventQueue();
    real.wizardCheck.respond(
      const CheckOk([RemoteModel('m1', contextWindow: 8000)]),
    );
    await pumpEventQueue();
    wizard.dispatch(const ModelChosen('m1'));
    await pumpEventQueue();
    wizard.dispatch(const ConfirmSave());
    await pumpEventQueue(times: 40);

    expect(wizard.state.setup, isA<Done>());
    expect(
      wizard.savedBanner!.text,
      'Provider llm-example saved. Its models are available after Restart '
      'agent (Settings › Connection).',
    );
    await wizard.close();
  });
}
