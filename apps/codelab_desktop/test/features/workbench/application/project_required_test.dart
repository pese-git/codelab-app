// Без выбранного проекта нет папки агента и сессий (задачи A1.1–A1.3 change
// `require-project-folder`; spec agent-workbench-ui «No project selected — no
// implicit directory», «Проект сменили во время проверки папки»; design.md
// D1, D2, D3).
//
// Тесты идут через настоящий граф cherrypick (`CodeLabTestBinding`), поэтому
// не зависят от конструкторов Cubit-ов. Подключение по кнопке Connect —
// предмет итерации A: в итерации B кнопки нет, и тест подключения без
// проекта переписывается (tasks B2.6).

import 'dart:async';
import 'dart:convert';

import 'package:codelab_acp_testing/codelab_acp_testing.dart';
import 'package:codelab_acp_transports/codelab_acp_transports.dart';
import 'package:codelab_client_core/codelab_client_core.dart'
    show ClientWorkspace, ConnectionProfile;
import 'package:codelab_desktop/features/settings/application/embedded_profile.dart';
import 'package:codelab_desktop/features/workbench/application/shell_cubit.dart';
import 'package:codelab_desktop/core/platform/project_folder_picker.dart';
import 'package:codelab_desktop/core/platform/shared_preferences_workspace_snapshot_store.dart'
    show kWorkspaceSnapshotPrefsKey;
import 'package:codelab_ui/codelab_ui.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:structured_log_flutter/structured_log_flutter.dart'
    show LogBuffer;

import '../../../support/test_app_scope.dart';

const _noProject =
    'Open a project before connecting: choose a folder with Open folder….';

const _stdioInProject = ConnectionProfile.stdio(
  id: 'dev',
  label: 'Dev',
  command: 'codelab-agent',
  args: ['serve', '--stdio'],
  runInProjectDirectory: true,
);

const _stdioAnywhere = ConnectionProfile.stdio(
  id: 'dev-free',
  label: 'Dev free',
  command: 'codelab-agent',
  args: ['serve', '--stdio'],
);

final _webSocket = ConnectionProfile.webSocket(
  id: 'remote',
  label: 'Remote',
  uri: Uri.parse('wss://agent.example.test/acp'),
);

Iterable<Object?> _events(CodeLabTestBinding binding) => binding.scope
    .resolve<LogBuffer>()
    .entries
    .value
    .map((entry) => entry['event']);

void main() {
  group('SettingsCubit.projectDirectory (A1.1, D1)', () {
    test('without a project and a snapshot the directory is null, not the '
        'process directory', () async {
      final binding = CodeLabTestBinding();
      final settings = binding.scope.resolve<CodeLabShellParts>().settings;
      await settings.projectRestored;

      expect(settings.projectDirectory, isNull);
    });

    test('selectProject sets the directory; a blank path is not a '
        'project', () async {
      final binding = CodeLabTestBinding();
      final settings = binding.scope.resolve<CodeLabShellParts>().settings;
      await settings.projectRestored;

      await settings.selectProject('/work/app');
      expect(settings.projectDirectory, '/work/app');

      final fresh = CodeLabTestBinding();
      final other = fresh.scope.resolve<CodeLabShellParts>().settings;
      await other.projectRestored;
      await other.selectProject('  ');
      expect(other.projectDirectory, isNull);
    });
  });

  group('connect without a project (A1.2, D2)', () {
    late List<StdioAcpTransportConfig> stdioStarted;
    var webSocketOpened = 0;
    var embeddedOpened = 0;
    late CodeLabTestBinding binding;
    late CodeLabShellCubit cubit;

    setUp(() async {
      stdioStarted = [];
      webSocketOpened = 0;
      embeddedOpened = 0;
      binding = CodeLabTestBinding(
        stdioTransportFactory: (config) {
          stdioStarted.add(config);
          return FakeAcpTransport();
        },
        webSocketTransportFactory: (_) {
          webSocketOpened++;
          return FakeAcpTransport();
        },
        embeddedOpener: ({required cwd, required hostProfile}) async {
          embeddedOpened++;
          throw StateError('the embedded agent must not be opened');
        },
      );
      cubit = binding.scope.resolve<CodeLabShellCubit>();
      await binding.scope.resolve<CodeLabShellParts>().settings.projectRestored;
    });

    void expectNothingStarted() {
      expect(stdioStarted, isEmpty);
      expect(webSocketOpened, 0);
      expect(embeddedOpened, 0);
      expect(
        binding.scope.resolve<ClientWorkspace>().current.projectDirectory,
        isNull,
      );
      expect(cubit.state.connectionStatus, CodeLabConnectionStatus.failed);
      expect(_events(binding), contains(_noProject));
    }

    for (final (name, profile) in [
      ('embedded', embeddedConnectionProfile),
      ('stdio in the project folder', _stdioInProject),
      ('stdio without the project folder', _stdioAnywhere),
      ('WebSocket', _webSocket),
    ]) {
      test('$name: connect() starts nothing and explains why', () async {
        await cubit.connect(profile);

        expectNothingStarted();
      });

      test('$name: reconnect() starts nothing and explains why', () async {
        // Отказанный `connect` делает профиль профилем окна, на нём и
        // работает `reconnect`.
        await cubit.connect(profile);
        await cubit.reconnect();

        expectNothingStarted();
      });
    }
  });

  group('the folder is read once per intent (A1.3, D3)', () {
    test('the project changed while the disk check hangs: the agent starts '
        'in the folder that was checked', () async {
      final check = Completer<bool>();
      var checks = 0;
      final started = <StdioAcpTransportConfig>[];
      final binding = CodeLabTestBinding(
        directoryExists: (path) {
          checks++;
          return check.future;
        },
        stdioTransportFactory: (config) {
          started.add(config);
          return FakeAcpTransport();
        },
      );
      final cubit = binding.scope.resolve<CodeLabShellCubit>();
      await binding.scope.resolve<CodeLabShellParts>().settings.projectRestored;
      await cubit.selectProject('/work/a');

      final connecting = cubit.connect(_stdioInProject);
      await pumpEventQueue();
      expect(checks, 1, reason: 'the disk check of /work/a is in flight');

      await cubit.selectProject('/work/b');
      check.complete(true);
      await connecting;

      expect(started.single.cwd, '/work/a');
    });
  });

  group('actions while the project is being restored (A1.14, D3)', () {
    final snapshot = jsonEncode({
      'version': 1,
      'windows': {
        'main': {'projectDirectory': '/work/app', 'openSessions': <Object?>[]},
      },
    });

    /// Восстановление проекта висит на проверке папки: первое обращение к
    /// `DirectoryExists` ждёт [gate], остальные отвечают сразу.
    ({
      CodeLabTestBinding binding,
      CodeLabShellCubit cubit,
      Completer<bool> gate,
      List<StdioAcpTransportConfig> started,
      List<String> picked,
    })
    restoring() {
      final gate = Completer<bool>();
      var first = true;
      final started = <StdioAcpTransportConfig>[];
      final picked = <String>[];
      final binding = CodeLabTestBinding(
        preferences: {kWorkspaceSnapshotPrefsKey: snapshot},
        directoryExists: (path) {
          if (first) {
            first = false;
            return gate.future;
          }
          return Future.value(true);
        },
        stdioTransportFactory: (config) {
          started.add(config);
          return FakeAcpTransport();
        },
        projectFolderPicker: _RecordingPicker(picked),
      );
      return (
        binding: binding,
        cubit: binding.scope.resolve<CodeLabShellCubit>(),
        gate: gate,
        started: started,
        picked: picked,
      );
    }

    test('Connect during the restore is connecting at once, then goes on '
        'with the restored folder', () async {
      final r = restoring();
      await pumpEventQueue();

      final connecting = r.cubit.connect(_stdioInProject);
      await pumpEventQueue();

      expect(
        r.cubit.state.connectionStatus,
        CodeLabConnectionStatus.connecting,
      );
      expect(r.started, isEmpty);

      r.gate.complete(true);
      await connecting;

      expect(r.started.single.cwd, '/work/app');
      expect(_events(r.binding), isNot(contains(_noProject)));
    });

    test(
      'a second press during the wait starts no second connection',
      () async {
        final r = restoring();
        await pumpEventQueue();

        final first = r.cubit.connect(_stdioInProject);
        final second = r.cubit.connect(_stdioInProject);
        await pumpEventQueue();
        r.gate.complete(true);
        await Future.wait([first, second]);

        expect(r.started, hasLength(1));
      },
    );

    testWidgets('a restore that hangs past the timeout rejects Connect '
        'before the workspace, with an event without a path', (tester) async {
      final r = restoring();
      await tester.pump();

      final connecting = r.cubit.connect(_stdioInProject);
      await tester.pump(const Duration(seconds: 3));

      expect(r.cubit.state.connectionStatus, CodeLabConnectionStatus.failed);
      expect(r.started, isEmpty);
      expect(
        r.binding.scope.resolve<ClientWorkspace>().current.projectDirectory,
        isNull,
      );
      expect(_events(r.binding), contains(_noProject));
      final rejected = r.binding.scope
          .resolve<LogBuffer>()
          .entries
          .value
          .singleWhere((e) => e['event'] == 'connection.connect_rejected');
      expect(rejected['reason'], 'no_project');
      expect(rejected['profile_id'], 'dev');
      expect(rejected.values.join(), isNot(contains('/work')));

      r.gate.complete(true);
      await connecting;
    });

    test('New session during the restore waits for it instead of opening '
        'the picker', () async {
      final r = restoring();
      await pumpEventQueue();

      final creating = r.cubit.createSession();
      await pumpEventQueue();
      expect(r.picked, isEmpty);

      r.gate.complete(true);
      await creating;

      // Проект восстановлен, поэтому выбор папки не нужен; соединения ещё
      // нет, и сессию создаёт повторное действие (D5).
      expect(r.picked, isEmpty);
      expect(r.cubit.state.selectedProjectPath, '/work/app');
    });

    testWidgets('New session after the timeout without a project opens the '
        'picker', (tester) async {
      final r = restoring();
      await tester.pump();

      final creating = r.cubit.createSession();
      await tester.pump(const Duration(seconds: 3));
      await creating;

      expect(r.picked, ['asked']);

      r.gate.complete(true);
      await tester.pump();
    });
  });
}

final class _RecordingPicker implements ProjectFolderPicker {
  _RecordingPicker(this.log);

  final List<String> log;

  @override
  Future<String?> pickFolder({String? initialDirectory}) async {
    log.add('asked');
    return null;
  }
}
