// `ConnectionCubit`: тип подключения «Встроенный агент» (задача 4.1 change
// `add-embedded-agent-mode`; agent-workbench-ui «Тип подключения «Встроенный
// агент»», сценарии «Выбор встроенного агента», «Нет конфигурации встроенного
// агента»; design.md D9).
//
// Cubit собирается из настоящих частей рабочего места поверх
// `ClientWorkspace` с записывающим резолвером: проверяется профиль, который
// форма отдаёт рабочему пространству, и состояние формы, а не транспорт.

import 'package:codelab_acp_testing/codelab_acp_testing.dart';
import 'package:codelab_acp_transports/codelab_acp_transports.dart';
import 'package:codelab_client_acp/codelab_client_acp.dart';
import 'package:codelab_client_core/codelab_client_core.dart';
import 'package:codelab_client_io/codelab_client_io.dart'
    show DirectoryExists, WorkingDirectoryProvider;
import 'package:codelab_desktop/app/embedded_transport_resolver.dart';
import 'package:codelab_desktop/core/platform/project_folder_picker.dart';
import 'package:codelab_embedded/codelab_embedded.dart'
    show EmbeddedAgentConfigException;
import 'package:codelab_desktop/features/workbench/application/shell_cubit.dart';
import 'package:codelab_ui/codelab_ui.dart';
import 'package:flutter_test/flutter_test.dart';

/// Резолвер, который запоминает профили и отдаёт фейковый транспорт.
final class _RecordingResolver implements TransportResolver {
  final profiles = <ConnectionProfile>[];

  @override
  bool supports(ConnectionProfile profile) => profile is EmbeddedProfile;

  @override
  Future<AcpTransport> open(
    ConnectionProfile profile, {
    required String projectDirectory,
  }) async {
    profiles.add(profile);
    return FakeAcpTransport();
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

void main() {
  late CodeLabShellParts parts;
  late _RecordingResolver resolver;

  CodeLabShellParts build({
    TransportResolver? realResolver,
    DirectoryExists? directoryExists,
  }) {
    resolver = _RecordingResolver();
    final application = AcpClientApplication(transport: FakeAcpTransport());
    final workspace = ClientWorkspace(
      backend: AcpClientBackend(application),
      resolvers: [realResolver ?? resolver],
    );
    parts = CodeLabShellParts.build(
      profile: codelabAgentStdioProfile,
      application: application,
      workspace: workspace,
      secrets: InMemorySecretSource(),
      workingDirectoryProvider: _FixedDirectory(),
      projectFolderPicker: _NoPicker(),
      recentProjectsStore: _NoRecentProjects(),
      directoryExists: directoryExists ?? (_) async => true,
    );
    addTearDown(parts.close);
    return parts;
  }

  test('the connection type of the form is stdio by default (D9)', () {
    build();

    expect(parts.connection.state.transportType, CodeLabTransportType.stdio);
  });

  test('the embedded type has the label and the detail of D9', () {
    build();

    parts.connection.selectTransport(CodeLabTransportType.embedded);

    final form = parts.connection.state;
    expect(form.transportType.label, 'Embedded agent');
    expect(form.selectedProfileLabel, 'Embedded agent');
    expect(
      form.selectedConnectionDetail,
      'codelab_embedded (embedded-app-desktop)',
    );
  });

  test('connect() with the embedded type builds EmbeddedProfile('
      'embedded-app-desktop) and hands it to the workspace', () async {
    build();
    parts.connection.selectTransport(CodeLabTransportType.embedded);

    await parts.connection.connect();

    expect(resolver.profiles, [
      const ConnectionProfile.embedded(
        id: 'embedded',
        label: 'Embedded agent',
        hostProfile: 'embedded-app-desktop',
      ),
    ]);
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
      parts.connection.selectTransport(CodeLabTransportType.embedded);

      await parts.connection.connect();

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
    parts.connection.selectTransport(CodeLabTransportType.embedded);

    await parts.connection.connect();

    expect(
      parts.connection.state.connectionStatus,
      CodeLabConnectionStatus.failed,
    );
    expect(parts.connection.state.connectionMessage, contains('/work/app'));
    expect(resolver.profiles, isEmpty);
  });
}
