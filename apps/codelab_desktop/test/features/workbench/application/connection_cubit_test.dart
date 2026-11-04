// `ConnectionCubit`: подключение по профилю (задачи 2.3 и 2.4 change
// `add-app-settings-shell`; agent-workbench-ui «Тип подключения «Встроенный
// агент»», app-settings «Блок «Behavior»»; design.md D5, D6, D8, D13, D17).
//
// Cubit собирается из настоящих частей рабочего места поверх
// `ClientWorkspace` с записывающим резолвером: проверяется профиль, который
// Cubit отдаёт рабочему пространству, состояние и события, а не транспорт.
// Прежний тест формы встроенного агента (задача 4.1 change
// `add-embedded-agent-mode`) переписан под выбор профиля: исходы прежние.

import 'dart:async';

import 'package:codelab_acp_testing/codelab_acp_testing.dart';
import 'package:codelab_client_acp/codelab_client_acp.dart';
import 'package:codelab_client_core/codelab_client_core.dart';
import 'package:codelab_client_io/codelab_client_io.dart'
    show DirectoryExists, WorkingDirectoryProvider;
import 'package:codelab_desktop/app/embedded_transport_resolver.dart';
import 'package:codelab_desktop/core/platform/connection_preferences.dart';
import 'package:codelab_desktop/core/platform/project_folder_picker.dart';
import 'package:codelab_desktop/features/settings/application/connection_commands.dart';
import 'package:codelab_desktop/features/settings/application/default_profile_resolver.dart';
import 'package:codelab_desktop/features/settings/application/embedded_profile.dart';
import 'package:codelab_desktop/features/workbench/application/shell_cubit.dart';
import 'package:codelab_embedded/codelab_embedded.dart'
    show EmbeddedAgentConfigException;
import 'package:codelab_ui/codelab_ui.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../support/in_memory_profile_store.dart';
import '../../../support/recording_logger.dart';

/// Резолвер, который запоминает профили и отдаёт фейковый транспорт.
final class _RecordingResolver implements TransportResolver {
  final profiles = <ConnectionProfile>[];

  /// Id профилей, открытие которых падает (недоступный агент).
  final failFor = <String>{};

  /// Открытые транспорты по порядку: тест обрывает соединение первого.
  final transports = <FakeAcpTransport>[];

  /// Открытие этих профилей висит, пока не завершится future (рукопожатие).
  final holds = <String, Future<void>>{};

  @override
  bool supports(ConnectionProfile profile) => true;

  @override
  Future<AcpTransport> open(
    ConnectionProfile profile, {
    required String projectDirectory,
  }) async {
    profiles.add(profile);
    await holds[profile.id];
    if (failFor.contains(profile.id)) {
      throw StateError('agent ${profile.id} is unavailable');
    }
    final transport = FakeAcpTransport();
    transports.add(transport);
    return transport;
  }
}

final class _FixedDirectory implements WorkingDirectoryProvider {
  @override
  String get currentPath => '/work/app';
}

final class _NoPicker implements ProjectFolderPicker {
  @override
  Future<String?> pickFolder({String? initialDirectory}) async => null;
}

final class _NoRecentProjects implements RecentProjectsStore {
  @override
  Future<List<RecentProject>> load() async => const [];

  @override
  Future<void> record(String path) async {}
}

const _stdio = ConnectionProfile.stdio(
  id: 'dev',
  label: 'Dev',
  command: 'codelab-agent',
  args: ['serve', '--stdio'],
  runInProjectDirectory: true,
);

void main() {
  late CodeLabShellParts parts;
  late _RecordingResolver resolver;
  late RecordingLogger shellLog;
  late RecordingLogger eventLog;
  late ClientWorkspace workspace;

  CodeLabShellParts build({
    TransportResolver? realResolver,
    DirectoryExists? directoryExists,
    List<ConnectionProfile> stored = const [],
    SecretSource? secrets,
  }) {
    resolver = _RecordingResolver();
    shellLog = RecordingLogger();
    eventLog = RecordingLogger();
    final application = AcpClientApplication(transport: FakeAcpTransport());
    workspace = ClientWorkspace(
      backend: AcpClientBackend(application),
      resolvers: [realResolver ?? resolver],
    );
    const preferences = SharedPreferencesConnectionPreferences();
    parts = CodeLabShellParts.build(
      initialProfile: embeddedConnectionProfile,
      application: application,
      workspace: workspace,
      workingDirectoryProvider: _FixedDirectory(),
      projectFolderPicker: _NoPicker(),
      recentProjectsStore: _NoRecentProjects(),
      directoryExists: directoryExists ?? (_) async => true,
      defaultProfiles: DefaultProfileResolver(
        store: InMemoryProfileStore(stored),
        preferences: preferences,
      ),
      preferences: preferences,
      logger: shellLog,
      eventLogger: eventLog,
    );
    addTearDown(parts.close);
    return parts;
  }

  setUp(() => SharedPreferences.setMockInitialValues({}));

  test('a new install: the profile of the window is the embedded agent with '
      'the label and the detail of D9', () async {
    build();
    await pumpEventQueue();

    final connection = parts.connection.state;
    expect(connection.profile, embeddedConnectionProfile);
    expect(connection.selectedProfileLabel, 'Embedded agent');
    expect(
      connection.selectedConnectionDetail,
      'codelab_embedded (embedded-app-desktop)',
    );
    expect(parts.connection, isA<ConnectionCommands>());
  });

  test('connect() without a profile connects the default one: the embedded '
      'agent without a saved choice (D5)', () async {
    build(stored: [_stdio]);

    await parts.connection.connect();

    expect(resolver.profiles, [
      const ConnectionProfile.embedded(
        id: 'embedded',
        label: 'Embedded agent',
        hostProfile: 'embedded-app-desktop',
      ),
    ]);
  });

  test('connect() without a profile connects the saved default and shows '
      'it before the first connect', () async {
    SharedPreferences.setMockInitialValues({
      'codelab.connection.default_profile': 'dev',
    });
    build(stored: [_stdio]);
    await pumpEventQueue();

    expect(parts.connection.state.profile.id, 'dev');
    expect(parts.connection.state.selectedProfileLabel, 'Dev');

    await parts.connection.connect();

    expect(resolver.profiles.single.id, 'dev');
  });

  test('connect(profile) makes it the profile of the window and a later '
      'reconnect() uses the same profile', () async {
    build(stored: [_stdio]);

    await parts.connection.connect(_stdio);
    await parts.connection.reconnect();

    expect(parts.connection.state.profile, _stdio);
    expect(resolver.profiles, [_stdio, _stdio]);
    expect(
      parts.connection.state.connectionStatus,
      CodeLabConnectionStatus.connected,
    );
  });

  test('connect(embedded) hands EmbeddedProfile(embedded-app-desktop) to '
      'the workspace', () async {
    build();

    await parts.connection.connect(embeddedConnectionProfile);

    expect(resolver.profiles, [embeddedConnectionProfile]);
  });

  test(
    'invalid or missing config of the embedded agent is ConnectionFailed '
    'and the banner is the bare problem text, without the class name',
    () async {
      build(
        realResolver: EmbeddedTransportResolver(
          ({required cwd, required hostProfile}) async =>
              throw EmbeddedAgentConfigException(
                const [],
                home: '/home/u/.codelab',
              ),
        ),
      );

      await parts.connection.connect(embeddedConnectionProfile);

      expect(
        parts.connection.state.connectionStatus,
        CodeLabConnectionStatus.failed,
      );
      final message = parts.connection.state.connectionMessage!;
      expect(
        message,
        startsWith(
          'Configure the embedded agent in /home/u/.codelab/config.yaml',
        ),
      );
      expect(message, contains('check it with: codelab config check'));
      expect(message, isNot(contains('EmbeddedAgentConfigException')));
    },
  );

  test('a missing project folder stops the embedded connection before the '
      'resolver is asked: the agent is local, like stdio', () async {
    build(directoryExists: (_) async => false);

    await parts.connection.connect(embeddedConnectionProfile);

    expect(
      parts.connection.state.connectionStatus,
      CodeLabConnectionStatus.failed,
    );
    expect(parts.connection.state.connectionMessage, contains('/work/app'));
    expect(resolver.profiles, isEmpty);
  });

  group('token reference (D13)', () {
    test('an unsupported reference connects without a token; the warning '
        'names the profile and never the reference (M2)', () async {
      build();
      final profile = ConnectionProfile.webSocket(
        id: 'devbox',
        label: 'Devbox',
        uri: Uri.parse('wss://devbox:7420/acp'),
        tokenRef: 'sk-test-leak-0123456789',
      );

      await parts.connection.connect(profile);

      expect(resolver.profiles, [profile]);
      expect(
        parts.connection.state.connectionStatus,
        CodeLabConnectionStatus.connected,
      );
      final warning = shellLog.entries.singleWhere(
        (e) => '${e['event']}'.contains('not supported in this version'),
      );
      // Формулировка не попадает под `SecretRedactor` (`\bToken\s+…`).
      expect(
        warning['event'],
        'The token-reference format of profile devbox is not supported in '
        'this version; connecting without a token.',
      );
      expect(warning['level'], 'warning');
      expect(
        '${shellLog.entries}${eventLog.entries}',
        isNot(contains('sk-test-leak-0123456789')),
      );
    });

    test('an env reference raises no warning', () async {
      build();

      await parts.connection.connect(
        ConnectionProfile.webSocket(
          id: 'devbox',
          label: 'Devbox',
          uri: Uri.parse('wss://devbox:7420/acp'),
          tokenRef: 'env:DEVBOX_TOKEN',
        ),
      );

      expect(
        shellLog.entries.where(
          (e) => '${e['event']}'.contains('not supported in this version'),
        ),
        isEmpty,
      );
    });
  });

  group('Connect on start (D8)', () {
    const enabled = {
      'codelab.connection.connect_on_start': true,
      'codelab.connection.default_profile': 'dev',
    };

    test('on: connects the default profile once, logs the event with the '
        'profile id and type only', () async {
      SharedPreferences.setMockInitialValues(enabled);
      build(stored: [_stdio]);

      await parts.connection.connectOnStart();
      await parts.connection.connectOnStart();

      expect(resolver.profiles, [_stdio]);
      final event = eventLog.entries.singleWhere(
        (e) => e['event'] == 'connection.connect_on_start',
      );
      expect(event['profile_id'], 'dev');
      expect(event['type'], 'stdio');
      expect(event.keys.toSet(), {'event', 'level', 'profile_id', 'type'});
    });

    test('off (the default): no connection at all', () async {
      build(stored: [_stdio]);

      await parts.connection.connectOnStart();

      expect(resolver.profiles, isEmpty);
      expect(
        parts.connection.state.connectionStatus,
        CodeLabConnectionStatus.disconnected,
      );
    });

    test('a manual Connect pressed first wins: the start connection does '
        'not race with it', () async {
      SharedPreferences.setMockInitialValues(enabled);
      build(stored: [_stdio]);

      final start = parts.connection.connectOnStart();
      await parts.connection.connect(embeddedConnectionProfile);
      await start;

      expect(resolver.profiles, [embeddedConnectionProfile]);
    });

    test(
      'a failure is an ordinary ConnectionFailed, without retries',
      () async {
        SharedPreferences.setMockInitialValues({
          'codelab.connection.connect_on_start': true,
        });
        build(
          realResolver: EmbeddedTransportResolver(
            ({required cwd, required hostProfile}) async =>
                throw EmbeddedAgentConfigException(const [], home: '/h'),
          ),
        );

        await parts.connection.connectOnStart();

        expect(
          parts.connection.state.connectionStatus,
          CodeLabConnectionStatus.failed,
        );
      },
    );
  });

  group('details in the diagnostics (L1)', () {
    test('stdio shows the command only, without arguments', () async {
      build();

      await parts.connection.connect(
        const ConnectionProfile.stdio(
          id: 'dev',
          label: 'Dev',
          command: 'codelab-agent',
          args: ['serve', '--token-arg-leak'],
        ),
      );

      final texts = [for (final e in shellLog.entries) '${e['event']}'];
      expect(texts, contains('Starting stdio ACP agent: codelab-agent.'));
      expect(texts.join(), isNot(contains('leak')));
      expect(parts.connection.state.selectedConnectionDetail, 'codelab-agent');
    });

    test('WebSocket shows scheme://host:port only: no userinfo, path or '
        'query', () async {
      build();

      await parts.connection.connect(
        ConnectionProfile.webSocket(
          id: 'devbox',
          label: 'Devbox',
          uri: Uri.parse('wss://u:p@devbox:7420/acp?t=sk-leak-0123'),
        ),
      );

      final texts = [for (final e in shellLog.entries) '${e['event']}'];
      expect(
        texts,
        contains('Connecting WebSocket ACP agent: wss://devbox:7420.'),
      );
      for (final hidden in const ['u:p', '/acp', 'sk-leak']) {
        expect(texts.join(), isNot(contains(hidden)));
      }
      expect(
        parts.connection.state.selectedConnectionDetail,
        'wss://devbox:7420',
      );
    });
  });

  group('attempt number after every await (M1, AGENTS.md §9)', () {
    final remote = ConnectionProfile.webSocket(
      id: 'remote',
      label: 'Remote',
      uri: Uri.parse('wss://remote:1/acp'),
    );

    test('a slow folder check of attempt A does not connect over B', () async {
      final gate = Completer<bool>();
      build(directoryExists: (_) => gate.future);

      final a = parts.connection.connect(_stdio);
      await pumpEventQueue();
      await parts.connection.connect(remote);
      gate.complete(true);
      await a;

      expect(resolver.profiles, [remote]);
      expect(workspace.current.profile?.id, 'remote');
      expect(
        parts.connection.state.connectionStatus,
        CodeLabConnectionStatus.connected,
      );
    });

    test('a missing folder found by the stale attempt A does not set '
        'failed', () async {
      final gate = Completer<bool>();
      build(directoryExists: (_) => gate.future);

      final a = parts.connection.connect(_stdio);
      await pumpEventQueue();
      await parts.connection.connect(remote);
      gate.complete(false);
      await a;

      expect(
        parts.connection.state.connectionStatus,
        CodeLabConnectionStatus.connected,
      );
      expect(parts.connection.state.connectionMessage, isNull);
    });

    test('the same for reconnect(): a stale reconnect does not replace '
        'the newer connection', () async {
      final gate = Completer<bool>();
      var calls = 0;
      build(
        directoryExists: (_) => ++calls == 1 ? Future.value(true) : gate.future,
      );
      await parts.connection.connect(_stdio);
      resolver.profiles.clear();

      final stale = parts.connection.reconnect();
      await pumpEventQueue();
      await parts.connection.connect(remote);
      gate.complete(true);
      await stale;

      expect(resolver.profiles, [remote]);
      expect(workspace.current.profile?.id, 'remote');
      expect(
        parts.connection.state.connectionStatus,
        CodeLabConnectionStatus.connected,
      );
    });
  });

  group('the window profile changes only after an accepted connect (L5)', () {
    test('Restart agent after a failed Connect reconnects the profile the '
        'workspace held, not the failed one', () async {
      build(stored: [_stdio]);
      await parts.connection.connect(embeddedConnectionProfile);
      resolver.failFor.add('dev');

      await parts.connection.connect(_stdio);
      expect(
        parts.connection.state.connectionStatus,
        CodeLabConnectionStatus.failed,
      );
      resolver.profiles.clear();
      await parts.connection.reconnect();

      expect(resolver.profiles.map((p) => p.id), ['embedded']);
      expect(parts.connection.state.profile, embeddedConnectionProfile);
    });

    test('the profile is replaced on success', () async {
      build(stored: [_stdio]);
      await parts.connection.connect(embeddedConnectionProfile);

      await parts.connection.connect(_stdio);

      expect(parts.connection.state.profile, _stdio);
    });
  });

  group('rejection before the workspace is asked (safety LOW)', () {
    test('a missing folder for B while A is connected keeps the status '
        'connected, the reason goes to connectionMessage, and losing A '
        'is still noticed', () async {
      var calls = 0;
      build(directoryExists: (_) async => ++calls == 1);
      await parts.connection.connect(_stdio);
      expect(
        parts.connection.state.connectionStatus,
        CodeLabConnectionStatus.connected,
      );

      await parts.connection.connect(
        const ConnectionProfile.stdio(id: 'b', label: 'B', command: 'b'),
      );

      expect(
        parts.connection.state.connectionStatus,
        CodeLabConnectionStatus.connected,
      );
      // Нит: при живом соединении причина — только в диагностике, баннер
      // ошибки не ложится поверх рабочего соединения.
      expect(parts.connection.state.connectionMessage, isNull);
      expect(
        [for (final e in shellLog.entries) '${e['event']}'].join('\n'),
        contains('Project folder not found: /work/app'),
      );
      expect(parts.connection.state.profile, _stdio);

      resolver.transports.first.fail(
        const AcpTransportException(
          code: AcpTransportErrorCode.disconnected,
          message: 'agent exited',
        ),
      );
      await pumpEventQueue();

      expect(
        parts.connection.state.connectionStatus,
        CodeLabConnectionStatus.lost,
      );
    });

    test(
      'an empty command for B while A is connected keeps connected',
      () async {
        build();
        await parts.connection.connect(_stdio);

        await parts.connection.connect(
          const ConnectionProfile.stdio(id: 'b', label: 'B', command: ' '),
        );

        expect(
          parts.connection.state.connectionStatus,
          CodeLabConnectionStatus.connected,
        );
      },
    );

    test(
      'without a live connection the rejection is failed, as before',
      () async {
        build(directoryExists: (_) async => false);

        await parts.connection.connect(_stdio);

        expect(
          parts.connection.state.connectionStatus,
          CodeLabConnectionStatus.failed,
        );
      },
    );
  });

  group('restart target (MEDIUM-A, MEDIUM-B)', () {
    test('before the first accepted connect it is the last selected '
        'profile; Restart retries it', () async {
      build(stored: [_stdio]);
      expect(parts.connection.restartTarget, isNull);
      resolver.failFor.add('dev');

      await parts.connection.connect(_stdio);

      expect(parts.connection.restartTarget, _stdio);
      resolver.failFor.clear();
      resolver.profiles.clear();
      await parts.connection.reconnect();
      expect(resolver.profiles, [_stdio]);
    });

    test('after an accepted connect it stays on it when a later Connect '
        'fails, and the stream announces changes', () async {
      build(stored: [_stdio]);
      final seen = <String?>[];
      final sub = parts.connection.restartTargets.listen(
        (profile) => seen.add(profile?.id),
      );
      addTearDown(sub.cancel);
      await parts.connection.connect(embeddedConnectionProfile);
      resolver.failFor.add('dev');

      await parts.connection.connect(_stdio);
      await pumpEventQueue();

      expect(parts.connection.restartTarget, embeddedConnectionProfile);
      expect(seen, contains('embedded'));
      expect(seen.last, 'embedded');
    });
  });

  group('title of a CLI profile with a long label (LOW)', () {
    const cli = ConnectionProfile.stdio(
      id: 'py',
      label: 'stdio:python -m "codelab agent" --stdio',
      command: 'python',
      args: ['-m', 'codelab agent', '--stdio'],
    );

    test('the label of the window is the id, not the command line', () async {
      build(stored: [cli]);

      await parts.connection.connect(cli);

      expect(parts.connection.state.selectedProfileLabel, 'py');
      expect(parts.connection.state.selectedConnectionDetail, 'python');
    });
  });

  group('a rejected intent does not preempt an attempt already in the kit '
      '(safety MEDIUM)', () {
    final remote = ConnectionProfile.webSocket(
      id: 'remote',
      label: 'Remote',
      uri: Uri.parse('wss://remote:1/acp'),
    );

    test('A (WebSocket handshake pending) → Connect B without a folder → A '
        'completes: connected, the target is A, losing A gives lost', () async {
      build(directoryExists: (_) async => false);
      final handshake = Completer<void>();
      resolver.holds['remote'] = handshake.future;

      final a = parts.connection.connect(remote);
      await pumpEventQueue();
      await parts.connection.connect(_stdio); // нет папки: отказ
      expect(
        parts.connection.state.connectionStatus,
        isNot(CodeLabConnectionStatus.failed),
        reason: 'A is still connecting; B must not show failed over it',
      );
      handshake.complete();
      await a;

      expect(
        parts.connection.state.connectionStatus,
        CodeLabConnectionStatus.connected,
      );
      expect(parts.connection.restartTarget, remote);
      expect(workspace.current.profile?.id, 'remote');

      resolver.transports.first.fail(
        const AcpTransportException(
          code: AcpTransportErrorCode.disconnected,
          message: 'agent exited',
        ),
      );
      await pumpEventQueue();
      expect(
        parts.connection.state.connectionStatus,
        CodeLabConnectionStatus.lost,
      );
    });

    test('an empty command of B does not preempt A either', () async {
      build();
      final handshake = Completer<void>();
      resolver.holds['remote'] = handshake.future;

      final a = parts.connection.connect(remote);
      await pumpEventQueue();
      await parts.connection.connect(
        const ConnectionProfile.stdio(id: 'b', label: 'B', command: ' '),
      );
      handshake.complete();
      await a;

      expect(
        parts.connection.state.connectionStatus,
        CodeLabConnectionStatus.connected,
      );
      expect(parts.connection.restartTarget, remote);
    });
  });
}
