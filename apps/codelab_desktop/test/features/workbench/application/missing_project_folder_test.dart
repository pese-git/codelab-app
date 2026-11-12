// Исчезнувшая папка проекта: восстановление после перезапуска и подключение
// не падают непонятной ошибкой процесса или `session/new`, а говорят, что
// папки нет, и предлагают выбрать другую.

import 'dart:convert';

import 'package:codelab_acp_testing/codelab_acp_testing.dart';
import 'package:codelab_acp_transports/codelab_acp_transports.dart';
import 'package:codelab_client_core/codelab_client_core.dart'
    show ConnectionProfile;
import 'package:codelab_desktop/core/platform/shared_preferences_workspace_snapshot_store.dart';
import 'package:codelab_desktop/features/workbench/application/shell_cubit.dart';
import 'package:codelab_ui/codelab_ui.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:structured_log_flutter/structured_log_flutter.dart'
    show LogBuffer;

import '../../../support/test_app_scope.dart';

String _snapshot(String project) => jsonEncode({
  'version': 1,
  'windows': {
    'main': {'projectDirectory': project, 'openSessions': <Object?>[]},
  },
});

/// Папки, которых «нет на диске»; остальные считаются существующими.
Future<bool> Function(String) _missing(Set<String> gone) =>
    (path) async => !gone.contains(path);

Iterable<Object?> _events(CodeLabTestBinding binding) => binding.scope
    .resolve<LogBuffer>()
    .entries
    .value
    .map((entry) => entry['event']);

void main() {
  group('restore', () {
    test('a project whose folder is gone is not selected and is reported '
        'as a warning', () async {
      final binding = CodeLabTestBinding(
        preferences: {kWorkspaceSnapshotPrefsKey: _snapshot('/work/gone')},
        directoryExists: _missing({'/work/gone'}),
      );
      final cubit = binding.scope.resolve<CodeLabShellCubit>();

      await pumpEventQueue();

      expect(cubit.state.selectedProjectPath, isNull);
      expect(
        _events(binding),
        contains(
          'Project folder from the last run no longer exists: /work/gone. '
          'Choose a folder with Open folder….',
        ),
      );
    });

    test('a project whose folder exists is selected as before', () async {
      final binding = CodeLabTestBinding(
        preferences: {kWorkspaceSnapshotPrefsKey: _snapshot('/work/app')},
        directoryExists: _missing({'/work/gone'}),
      );
      final cubit = binding.scope.resolve<CodeLabShellCubit>();

      await pumpEventQueue();

      expect(cubit.state.selectedProjectPath, '/work/app');
    });
  });

  // Ручного Connect нет (B2.6, D13): старт агента — триггер выбора проекта.
  // Текст — без «and connect again» (D2): повторять нечего, пользователь
  // выбирает папку заново.
  group('start of the agent', () {
    const message =
        'Project folder not found: /work/gone. '
        'Choose an existing folder with Open folder….';

    late List<StdioAcpTransportConfig> started;
    late CodeLabTestBinding binding;
    late CodeLabShellCubit cubit;

    setUp(() async {
      started = [];
      binding = CodeLabTestBinding(
        directoryExists: _missing({'/work/gone'}),
        stdioTransportFactory: (config) {
          started.add(config);
          return FakeAcpTransport();
        },
        webSocketTransportFactory: (_) => FakeAcpTransport(),
      );
      cubit = binding.scope.resolve<CodeLabShellCubit>();
      await pumpEventQueue();
      // Выбор проекта — триггер старта: папки нет, агент не стартует.
      await cubit.selectProject('/work/gone');
      await pumpEventQueue();
    });

    test(
      'selecting the project stops before starting the agent and explains why',
      () async {
        expect(started, isEmpty);
        expect(cubit.state.connectionStatus, CodeLabConnectionStatus.failed);
        expect(cubit.state.connectionMessage, message);
        expect(_events(binding), contains(message));
      },
    );

    test('Restart agent stops the same way', () async {
      await cubit.restartAgent();

      expect(started, isEmpty);
      expect(cubit.state.connectionStatus, CodeLabConnectionStatus.failed);
      expect(cubit.state.connectionMessage, message);
    });

    test('choosing an existing folder starts the agent', () async {
      await cubit.selectProject('/work/app');
      await pumpEventQueue();

      expect(started.single.cwd, '/work/app');
      expect(cubit.state.connectionMessage, isNull);
    });

    test(
      'WebSocket is not checked: the folder belongs to the remote agent',
      () async {
        await cubit.useProfile(
          ConnectionProfile.webSocket(
            id: 'remote',
            label: 'Remote',
            uri: Uri.parse('wss://agent.example.test/acp'),
          ),
        );
        await cubit.retryStart();

        expect(cubit.state.connectionMessage, isNot(message));
        // Единственная запись — от первой попытки stdio при выборе проекта;
        // WebSocket-старт новой не добавил.
        expect(_events(binding).where((e) => e == message), hasLength(1));
      },
    );
  });
}
