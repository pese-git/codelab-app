// Composition root app и профили подключения (задача 2.6 change
// `add-app-settings-shell`; spec app-settings «Список профилей на странице
// «Connection»», «События журнала настроек без секретов»; design.md D7, D15,
// D17).
//
// Файл профилей настоящий: путь выводится из окружения шва
// `createCodeLabRootScope(environment:)`, тесты идут в обычной зоне (`test`),
// без fake-async — файловый ввод-вывод в ней зависал бы.

import 'dart:io';

import 'package:cherrypick/cherrypick.dart' show Scope;
import 'package:codelab_acp_testing/codelab_acp_testing.dart';
import 'package:codelab_acp_transports/codelab_acp_transports.dart';
import 'package:codelab_client_core/codelab_client_core.dart'
    show ConnectionProfile;
import 'package:codelab_desktop/app/app_scope.dart';
import 'package:codelab_desktop/app/codelab_app_widget.dart';
import 'package:codelab_desktop/app/navigation/navigation_cubit.dart';
import 'package:codelab_desktop/app/navigation/settings_page.dart';
import 'package:codelab_desktop/features/settings/application/connection_settings_cubit.dart';
import 'package:codelab_desktop/features/workbench/application/shell_cubit.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:structured_log_flutter/structured_log_flutter.dart'
    show LogBuffer;

import '../support/test_app_scope.dart';

const _marker = 'sk-test-leak-0123456789';

const _file = '''
{"version":1,"profiles":[
 {"type":"stdio","id":"dev","label":"Dev","command":"codelab-agent",
  "args":["serve","--stdio"],"env":{},"runInProjectDirectory":true}
]}
''';

void main() {
  late Directory home;
  late File profiles;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    home = await Directory.systemTemp.createTemp('codelab_scope_profiles_');
    profiles = File('${home.path}/profiles.json');
    addTearDown(() => home.delete(recursive: true));
  });

  Scope scopeWith({
    required Map<String, String> environment,
    CodeLabWebSocketTransportFactory? webSocketTransportFactory,
  }) {
    final scope = createCodeLabRootScope(
      transportFactory: FakeAcpTransport.new,
      webSocketTransportFactory: webSocketTransportFactory,
      environment: environment,
      directoryExists: (_) async => true,
      logDirectoryPath: home.path,
      settingsPages: const SettingsPages(available: {SettingsPage.connection}),
    );
    addTearDown(closeCodeLabRootScopeInTest);
    return scope;
  }

  List<Map<String, Object?>> events(Scope scope) => [
    for (final entry in scope.resolve<LogBuffer>().entries.value)
      Map<String, Object?>.from(entry),
  ];

  test(
    'profiles.json is read from the CODELAB_HOME of the environment seam',
    () async {
      await profiles.writeAsString(_file);
      final scope = scopeWith(environment: {'CODELAB_HOME': home.path});

      final cubit = scope.resolve<ConnectionSettingsCubit>();
      await cubit.reload();

      final state = cubit.state as ConnectionSettingsReady;
      expect([for (final row in state.rows) row.id], ['embedded', 'dev']);
    },
  );

  test('an empty CODELAB_HOME falls back to \$HOME/.codelab', () async {
    await Directory('${home.path}/.codelab').create();
    await File('${home.path}/.codelab/profiles.json').writeAsString(_file);
    final scope = scopeWith(
      environment: {'CODELAB_HOME': '', 'HOME': home.path},
    );

    final cubit = scope.resolve<ConnectionSettingsCubit>();
    await cubit.reload();

    expect(
      [for (final row in (cubit.state as ConnectionSettingsReady).rows) row.id],
      ['embedded', 'dev'],
    );
  });

  group('invalid CODELAB_HOME (D7, 2.16.4)', () {
    for (final environment in <Map<String, String>>[
      {'CODELAB_HOME': '~bob/cl', 'HOME': '/Users/me'},
      // Нет ни CODELAB_HOME, ни домашней папки.
      <String, String>{},
    ]) {
      test('$environment: Unreadable with the reason, no file created, '
          'Behavior works', () async {
        final scope = scopeWith(environment: environment);
        final cubit = scope.resolve<ConnectionSettingsCubit>();

        await cubit.reload();
        await cubit.setConnectOnStart(true);

        final state = cubit.state as ConnectionSettingsUnreadable;
        expect([for (final row in state.rows) row.id], ['embedded']);
        expect(state.reason, isNotEmpty);
        expect(state.connectOnStart, isTrue);
        expect(state.canRestart, isFalse);
        expect(await cubit.removeIgnoredDefault(), isFalse);
        expect(Directory('${home.path}/cl').existsSync(), isFalse);
        expect(Directory('${home.path}/.codelab').existsSync(), isFalse);
        expect(
          events(scope).singleWhere(
            (e) => e['event'] == 'connection_profile.unreadable',
          )['error_type'],
          'ProfilesUnavailableException',
        );
      });
    }
  });

  group('ProfileSecretSource instead of InMemorySecretSource (D15)', () {
    final profile = ConnectionProfile.webSocket(
      id: 'devbox',
      label: 'Devbox',
      uri: Uri.parse('wss://devbox:7420/acp'),
      tokenRef: 'env:DEVBOX_TOKEN',
    );

    test('the token of env:NAME is read from the environment of the app '
        'when the transport opens', () async {
      final configs = <WebSocketAcpTransportConfig>[];
      final scope = scopeWith(
        environment: {'CODELAB_HOME': home.path, 'DEVBOX_TOKEN': _marker},
        webSocketTransportFactory: (config) {
          configs.add(config);
          return FakeAcpTransport();
        },
      );

      await scope.resolve<CodeLabShellCubit>().connect(profile);

      expect(configs.single.token, _marker);
    });

    test(
      'a variable that is not set means a connection without a token',
      () async {
        final configs = <WebSocketAcpTransportConfig>[];
        final scope = scopeWith(
          environment: {'CODELAB_HOME': home.path},
          webSocketTransportFactory: (config) {
            configs.add(config);
            return FakeAcpTransport();
          },
        );

        await scope.resolve<CodeLabShellCubit>().connect(profile);

        expect(configs.single.token, isNull);
      },
    );
  });

  group('events without values (D17)', () {
    test('an unreadable file is logged by the error type; the content, '
        'the path and the marker are not in the log', () async {
      await profiles.writeAsString(
        '{"version":2,"profiles":[{"token":"$_marker"}]}',
      );
      final scope = scopeWith(environment: {'CODELAB_HOME': home.path});

      await scope.resolve<ConnectionSettingsCubit>().reload();

      final log = events(scope);
      final event = log.singleWhere(
        (e) => e['event'] == 'connection_profile.unreadable',
      );
      expect('$event', contains('FormatException'));
      expect('$log', isNot(contains(_marker)));
      expect('$log', isNot(contains(home.path)));
    });

    test('opening settings logs the page and the source only', () async {
      final scope = scopeWith(environment: {'CODELAB_HOME': home.path});

      await scope.resolve<NavigationCubit>().openSettings(
        source: SettingsOpenSource.shortcut,
      );

      final opened = events(
        scope,
      ).singleWhere((e) => e['event'] == 'settings.opened');
      expect('$opened', contains('connection'));
      expect('$opened', contains('shortcut'));
    });
  });

  testWidgets('Connect on start connects the default profile once after the '
      'first frame (D8)', (tester) async {
    var starts = 0;
    final binding = CodeLabTestBinding(
      preferences: const {'codelab.connection.connect_on_start': true},
      stdioTransportFactory: (_) {
        starts++;
        return FakeAcpTransport();
      },
    );
    final shell = binding.scope.resolve<CodeLabShellCubit>();

    await tester.pumpWidget(binding.bootstrap(child: const CodeLabApp()));
    await tester.pump();
    await tester.pump();
    await tester.pump();

    expect(starts, 1);
    expect(shell.state.profileLabel, 'Codelab Agent');
    // Ещё кадры не создают второго подключения.
    await tester.pump(const Duration(seconds: 1));
    expect(starts, 1);
    await tester.pumpWidget(const SizedBox.shrink());
    await closeCodeLabRootScope();
  });
}
