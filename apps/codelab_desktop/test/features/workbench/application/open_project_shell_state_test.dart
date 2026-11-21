// Состояние рабочего места без проекта (задача 3.7 change
// `add-empty-project-screen`; design.md D5, D8; spec agent-workbench-ui
// «Экран без выбранного проекта», сценарий «Badge after a folder is chosen»):
// `CodeLabShellState.awaitingProject`, `transportKind`, `dropRejection` и
// методы фасада `openDroppedPaths`, `clearDropRejection`.
//
// Красный до задачи 3.8: этих полей и методов ещё нет, тест не компилируется.
// Тест идёт через граф app (`CodeLabTestBinding`); брошенная папка —
// настоящий временный каталог, потому что `ioLocalPathKind` — реализация
// порта по умолчанию (D4).

import 'dart:io';

import 'package:codelab_acp_testing/codelab_acp_testing.dart';
import 'package:codelab_client_core/codelab_client_core.dart'
    show ConnectionProfile;
import 'package:codelab_desktop/features/settings/application/embedded_profile.dart';
import 'package:codelab_desktop/features/workbench/application/settings_cubit.dart';
import 'package:codelab_desktop/features/workbench/application/shell_cubit.dart';
import 'package:codelab_ui/codelab_ui.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../../support/test_app_scope.dart';

const _stdio = ConnectionProfile.stdio(
  id: 'dev',
  label: 'Dev',
  command: '/usr/local/bin/codelab-agent',
  args: ['serve', '--stdio', '--token', 'abc'],
  runInProjectDirectory: true,
);

final _webSocket = ConnectionProfile.webSocket(
  id: 'remote',
  label: 'Remote',
  uri: Uri.parse('ws://user:pw@127.0.0.1:8765/acp?t=1'),
);

void main() {
  late CodeLabTestBinding binding;
  late CodeLabShellCubit cubit;

  setUp(() async {
    binding = CodeLabTestBinding(
      stdioTransportFactory: (_) => FakeAcpTransport(),
    );
    cubit = binding.scope.resolve<CodeLabShellCubit>();
    await binding.scope.resolve<CodeLabShellParts>().settings.projectRestored;
  });

  group('awaitingProject', () {
    test('истинно без проекта при disconnected', () {
      expect(cubit.state.selectedProjectPath, isNull);
      expect(
        cubit.state.connectionStatus,
        CodeLabConnectionStatus.disconnected,
      );
      expect(cubit.state.awaitingProject, isTrue);
    });

    test('истинно только при idle и disconnected без проекта', () {
      final state = cubit.state;
      for (final (status, expected) in [
        (CodeLabConnectionStatus.idle, true),
        (CodeLabConnectionStatus.disconnected, true),
        (CodeLabConnectionStatus.connecting, false),
        (CodeLabConnectionStatus.connected, false),
        (CodeLabConnectionStatus.reconnecting, false),
        (CodeLabConnectionStatus.lost, false),
        (CodeLabConnectionStatus.failed, false),
      ]) {
        expect(
          state.copyWith(connectionStatus: status).awaitingProject,
          expected,
          reason: '$status',
        );
      }
    });

    test('с выбранным проектом ложно даже при disconnected', () {
      final withProject = cubit.state.copyWith(
        selectedProjectPath: '/work/app',
        connectionStatus: CodeLabConnectionStatus.disconnected,
      );

      expect(withProject.awaitingProject, isFalse);
    });

    test('Badge after a folder is chosen: после выбора папки ложно', () async {
      await cubit.selectProject('/work/app');

      expect(cubit.state.selectedProjectPath, '/work/app');
      expect(cubit.state.awaitingProject, isFalse);
    });
  });

  group('transportKind', () {
    for (final (name, profile, kind) in [
      (
        'встроенный агент',
        embeddedConnectionProfile,
        ProfileTransportKind.embedded,
      ),
      ('stdio', _stdio, ProfileTransportKind.stdio),
      ('WebSocket', _webSocket, ProfileTransportKind.webSocket),
    ]) {
      test(name, () async {
        await cubit.useProfile(profile);

        expect(cubit.state.transportKind, kind);
      });
    }
  });

  group('перетаскивание через фасад', () {
    late Directory tmp;

    setUp(() => tmp = Directory.systemTemp.createTempSync('drop_shell_'));
    tearDown(() => tmp.deleteSync(recursive: true));

    test('dropRejection проходит из SettingsState; clearDropRejection '
        'снимает его', () async {
      await cubit.openDroppedPaths(['/work/a', '/work/b']);

      expect(cubit.state.dropRejection, isA<DropMultiple>());
      expect(cubit.state.selectedProjectPath, isNull);

      cubit.clearDropRejection();

      expect(cubit.state.dropRejection, isNull);
    });

    test(
      'брошенная папка выбирает проект, и бейдж больше не ждёт проект',
      () async {
        await cubit.openDroppedPaths([tmp.path]);

        expect(cubit.state.selectedProjectPath, tmp.path);
        expect(cubit.state.dropRejection, isNull);
        expect(cubit.state.awaitingProject, isFalse);
      },
    );

    test('брошенный файл — отказ DropNotAFolder, проект не выбран', () async {
      final file = File('${tmp.path}/README.md')..writeAsStringSync('x');

      await cubit.openDroppedPaths([file.path]);

      expect(cubit.state.dropRejection, isA<DropNotAFolder>());
      expect(cubit.state.selectedProjectPath, isNull);
      expect(cubit.state.awaitingProject, isTrue);
    });
  });
}
