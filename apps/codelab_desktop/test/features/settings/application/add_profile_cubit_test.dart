// `AddProfileCubit` — форма «Add connection profile» (задача 3.4 change
// `add-app-settings-shell`; spec app-settings «Диалог «Add connection
// profile»» и «События журнала настроек без секретов»; design.md D11–D14,
// D17).
//
// Проверяется то, что видит пользователь и что остаётся на диске: состояния
// формы, записанный профиль, ключ `shared_preferences`, события журнала.
// Проверка подключения идёт через настоящий `ProfileProbe` на
// `FakeAcpTransport`: порядок событий задаётся явно, без таймеров.

import 'dart:async';

import 'package:codelab_acp_protocol/codelab_acp_protocol.dart'
    show Implementation;
import 'package:codelab_acp_testing/codelab_acp_testing.dart';
import 'package:codelab_acp_transports/codelab_acp_transports.dart';
import 'package:codelab_client_core/codelab_client_core.dart';
import 'package:codelab_desktop/core/platform/connection_preferences.dart';
import 'package:codelab_desktop/features/settings/application/add_profile_cubit.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../support/fake_profile_secrets.dart';
import '../../../support/recording_logger.dart';

const _defaultKey = 'codelab.connection.default_profile';

/// Значение, которого не должно быть ни в событиях, ни в текстах (3.4).
const _leak = 'sk-test-leak-0123456789';

const _dev = ConnectionProfile.stdio(
  id: 'dev',
  label: 'Dev',
  command: 'codelab-agent',
);

/// Хранилище в памяти с управляемым сбоем записи.
final class _Store implements ProfileStore {
  _Store([Iterable<ConnectionProfile> profiles = const []])
    : profiles = [...profiles];

  final List<ConnectionProfile> profiles;

  /// Если задано, `save` бросает это.
  Object? failSave;
  var saves = 0;

  /// Если задано, `load` ждёт его: так тест держит `save()` посреди чтения id.
  Completer<void>? loadGate;

  @override
  Future<List<ConnectionProfile>> load() async {
    final gate = loadGate;
    if (gate != null) {
      await gate.future;
    }
    return List.of(profiles);
  }

  @override
  Future<void> save(ConnectionProfile profile) async {
    saves++;
    if (failSave case final error?) {
      throw error;
    }
    profiles.removeWhere((p) => p.id == profile.id);
    profiles.add(profile);
  }

  @override
  Future<bool> remove(String id) async {
    final before = profiles.length;
    profiles.removeWhere((p) => p.id == id);
    return profiles.length != before;
  }
}

/// Исключение, чей `toString()` несёт секрет: в журнал должно попасть только
/// имя типа (D17).
final class _LeakyException implements Exception {
  @override
  String toString() => '_LeakyException: $_leak';
}

/// Настройки, у которых запись ключа умолчания падает (D14, D17: этап
/// `default`); остальное — как в настоящих.
final class _FailingDefaultPreferences implements ConnectionPreferences {
  const _FailingDefaultPreferences();

  static const _real = SharedPreferencesConnectionPreferences();

  @override
  Future<String?> loadDefaultProfileId() => _real.loadDefaultProfileId();

  @override
  Future<void> saveDefaultProfileId(String? id) async =>
      throw _LeakyException();
}

void main() {
  late _Store store;
  late FakeProfileSecrets secrets;
  late RecordingLogger logger;
  late List<FakeAcpTransport> stdioTransports;
  late List<StdioAcpTransportConfig> stdioConfigs;
  late FakeAcpTransport Function() nextStdio;
  late FakeAcpTransport wsTransport;
  ProbeFailureClassifier? classifier;
  var wsFactoryFails = false;

  /// Сколько раз probe открыл WebSocket-транспорт: до подтверждения токен не
  /// должен уйти, то есть транспорт не открывается.
  var wsOpened = 0;

  /// Токены, с которыми probe открывал WebSocket (в памяти теста).
  late List<String?> wsTokens;

  /// Папка проекта окна; `null` — проект не выбран (D7).
  String? projectFolder = '/work';

  AddProfileCubit build({
    Map<String, String> environment = const {},
    List<ProfileKind> kinds = const [ProfileKind.stdio, ProfileKind.webSocket],
    ConnectionPreferences preferences =
        const SharedPreferencesConnectionPreferences(),
  }) {
    final probe = ProfileProbe(
      resolvers: [
        ConfigTransportResolver(
          stdio: (config) {
            stdioConfigs.add(config);
            final transport = nextStdio();
            stdioTransports.add(transport);
            return transport;
          },
          webSocket: (config) {
            wsOpened++;
            wsTokens.add(config.token);
            return wsFactoryFails ? throw StateError('ws failed') : wsTransport;
          },
          secrets: ProfileSecretSource(environment, stored: secrets),
        ),
      ],
      classifier: classifier,
    );
    final cubit = AddProfileCubit(
      store: store,
      openSecrets: () async => secrets,
      preferences: preferences,
      probe: probe,
      kinds: kinds,
      environment: environment,
      projectDirectory: () => projectFolder,
      logger: logger,
    );
    addTearDown(cubit.close);
    return cubit;
  }

  /// Открытая форма с загруженными id профилей.
  Future<AddProfileCubit> started({
    Map<String, String> environment = const {},
    List<ProfileKind> kinds = const [ProfileKind.stdio, ProfileKind.webSocket],
    ConnectionPreferences preferences =
        const SharedPreferencesConnectionPreferences(),
  }) async {
    final cubit = build(
      environment: environment,
      kinds: kinds,
      preferences: preferences,
    );
    await cubit.start();
    return cubit;
  }

  /// Состояния по мере появления (без начального).
  List<AddProfileState> record(AddProfileCubit cubit) {
    final seen = <AddProfileState>[];
    final subscription = cubit.stream.listen(seen.add);
    addTearDown(subscription.cancel);
    return seen;
  }

  List<String> events(String name) => [
    for (final entry in logger.entries)
      if (entry['event'] == name) entry['level']! as String,
  ];

  Map<String, Object?> eventOf(String name) =>
      logger.entries.firstWhere((entry) => entry['event'] == name);

  AddProfileForm formOf(AddProfileCubit cubit) => switch (cubit.state) {
    AddProfileInProgress(:final form) => form,
    OpeningSecrets() => throw StateError('the store is still opening'),
    Saved() => throw StateError('the form is already saved'),
  };

  void fillStdio(AddProfileCubit cubit, {String label = 'Build box'}) {
    cubit
      ..selectKind(ProfileKind.stdio)
      ..setLabel(label);
  }

  void fillWebSocket(
    AddProfileCubit cubit, {
    String label = 'Devbox 2',
    String url = 'wss://devbox:7420',
  }) {
    cubit
      ..selectKind(ProfileKind.webSocket)
      ..setLabel(label)
      ..setUrl(url);
  }

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    store = _Store([_dev]);
    secrets = FakeProfileSecrets();
    logger = RecordingLogger();
    stdioTransports = [];
    stdioConfigs = [];
    nextStdio = FakeAcpTransport.new;
    classifier = null;
    wsFactoryFails = false;
    wsOpened = 0;
    projectFolder = '/work';
    wsTokens = [];
    wsTransport = FakeAcpTransport();
  });

  group('probe text (3.8b, D12)', () {
    test('Command not found names the Command field, never the arguments '
        'or env', () async {
      classifier = (_) => const CommandNotFound();
      nextStdio = () => throw StateError('no such file $_leak');
      final cubit = await started();
      fillStdio(cubit);
      cubit
        ..setCommand('missing-agent')
        ..setArgs('--token $_leak')
        ..setEnv('API_URL=$_leak');

      await cubit.testConnection();

      expect(formOf(cubit).probeText, 'Command not found: missing-agent');
      expect(logger.entries.toString(), isNot(contains(_leak)));
    });

    test('Unreachable shows the text of its reason; the transport message '
        'with the marker stays out of the form and the log', () async {
      classifier = (_) => Unreachable(
        'refused wss://u:p@devbox:7420/acp?t=$_leak',
        reason: UnreachableReason.connectionRefused,
      );
      wsFactoryFails = true;
      final cubit = await started();
      fillWebSocket(cubit);

      await cubit.testConnection();

      expect(formOf(cubit).probeText, 'Unreachable: connection refused');
      expect(logger.entries.toString(), isNot(contains(_leak)));
    });

    test('HTTP status reaches the text', () async {
      classifier = (_) => const Unreachable(
        'x',
        reason: UnreachableReason.httpStatus,
        statusCode: 503,
      );
      wsFactoryFails = true;
      final cubit = await started();
      fillWebSocket(cubit);

      await cubit.testConnection();

      expect(formOf(cubit).probeText, 'Unreachable: HTTP 503');
    });

    test('Unauthorized with a token from a set variable says the token was '
        'rejected', () async {
      classifier = (_) => const Unauthorized();
      wsFactoryFails = true;
      final cubit = await started(
        environment: const {'CODELAB_AGENT_TOKEN': _leak},
      );
      fillWebSocket(cubit);
      cubit.selectTokenEnv();

      await cubit.testConnection();

      expect(
        formOf(cubit).probeText,
        'Unauthorized: the agent rejected the token',
      );
      expect(formOf(cubit).probeText, isNot(contains(_leak)));
    });

    test('Unauthorized with "No token" says the agent requires one', () async {
      classifier = (_) => const Unauthorized();
      wsFactoryFails = true;
      final cubit = await started();
      fillWebSocket(cubit);

      await cubit.testConnection();

      expect(
        formOf(cubit).probeText,
        'Unauthorized: the agent requires a token',
      );
    });

    test('Unauthorized with a variable that is not set was sent without a '
        'token: the agent requires one', () async {
      classifier = (_) => const Unauthorized();
      wsFactoryFails = true;
      final cubit = await started();
      fillWebSocket(cubit);
      cubit.selectTokenEnv();

      await cubit.testConnection();

      expect(
        formOf(cubit).probeText,
        'Unauthorized: the agent requires a token',
      );
    });

    test('Reachable shows latency and the agent', () async {
      final cubit = await started();
      fillStdio(cubit);

      await cubit.testConnection();

      expect(formOf(cubit).probeText, startsWith('Reachable · '));
      expect(formOf(cubit).probeText, contains(' ms'));
    });

    test('any edit clears the text with the outcome', () async {
      final cubit = await started();
      fillStdio(cubit);
      await cubit.testConnection();
      expect(formOf(cubit).probeText, isNotNull);

      cubit.setCommand('other');

      expect(formOf(cubit).probeText, isNull);
    });
  });

  group('profiles file in the subtitle (D20)', () {
    AddProfileCubit withPath(String? path, Map<String, String> env) {
      final cubit = AddProfileCubit(
        store: store,
        openSecrets: () async => secrets,
        preferences: const SharedPreferencesConnectionPreferences(),
        probe: ProfileProbe(resolvers: const []),
        kinds: const [ProfileKind.stdio],
        environment: env,
        projectDirectory: () => '/work',
        profilesPath: path,
      );
      addTearDown(cubit.close);
      return cubit;
    }

    test('under HOME the path starts with ~', () {
      final cubit = withPath('/Users/u/.codelab/profiles.json', {
        'HOME': '/Users/u',
      });
      expect(cubit.profilesPathLabel, '~/.codelab/profiles.json');
    });

    test('CODELAB_HOME outside HOME shows the absolute path', () {
      final cubit = withPath('/private/tmp/ch/profiles.json', {
        'HOME': '/Users/u',
      });
      expect(cubit.profilesPathLabel, '/private/tmp/ch/profiles.json');
    });

    test('a path that only shares the prefix of HOME is not shortened', () {
      final cubit = withPath('/Users/uu/profiles.json', {'HOME': '/Users/u'});
      expect(cubit.profilesPathLabel, '/Users/uu/profiles.json');
    });

    test('without a path the default location is named', () {
      expect(
        withPath(null, const {}).profilesPathLabel,
        '~/.codelab/profiles.json',
      );
    });
  });

  group('form', () {
    test('opens on stdio with the agent defaults when the host supports it; '
        'on WebSocket when it does not (SETUP-22)', () async {
      final both = await started();
      expect(formOf(both).draft.kind, ProfileKind.stdio);
      expect(formOf(both).draft.command, 'codelab-agent');
      expect(formOf(both).draft.args, 'serve --stdio');
      expect(formOf(both).draft.runInProjectDirectory, isTrue);
      expect(formOf(both).kinds, [ProfileKind.stdio, ProfileKind.webSocket]);

      final onlyWs = await started(kinds: const [ProfileKind.webSocket]);
      expect(formOf(onlyWs).draft.kind, ProfileKind.webSocket);
      expect(formOf(onlyWs).kinds, [ProfileKind.webSocket]);
    });

    test('the id follows the name until the user edits the id', () async {
      final cubit = await started();

      cubit.setLabel('Build Box #2');
      expect(formOf(cubit).draft.id, 'build-box-2');

      cubit.setId('mine');
      cubit.setLabel('Another');
      expect(formOf(cubit).draft.id, 'mine');

      // Пустой id возвращает автоподстановку.
      cubit.setId('');
      expect(formOf(cubit).draft.id, 'another');
    });

    test('shows no errors before the first edit, then the id errors one by '
        'one with the texts of the spec', () async {
      final cubit = await started();
      expect(formOf(cubit).errors, isEmpty);
      expect(formOf(cubit).canSave, isFalse);

      cubit.setLabel('Embedded');
      expect(
        formOf(cubit).errors[ProfileDraftField.id],
        '"embedded" is reserved for the built-in agent.',
      );
      cubit.setLabel('Default');
      expect(
        formOf(cubit).errors[ProfileDraftField.id],
        '"default" is reserved for the built-in agent.',
      );
      cubit.setLabel('Dev');
      expect(
        formOf(cubit).errors[ProfileDraftField.id],
        'A profile with id "dev" already exists.',
      );
      cubit.setId('a:b');
      expect(formOf(cubit).errors[ProfileDraftField.id], isNotNull);
      expect(formOf(cubit).canSave, isFalse);
      expect(formOf(cubit).errors.values.join(), isNot(contains('a:b')));

      cubit.setId('');
      cubit.setLabel('');
      expect(formOf(cubit).errors[ProfileDraftField.label], 'Enter a name.');
      expect(formOf(cubit).errors.containsKey(ProfileDraftField.id), isFalse);
    });

    group('errors appear only for fields the user touched', () {
      test('switching to WebSocket shows no error, yet Save and Test stay '
          'blocked by validation', () async {
        final cubit = await started();

        cubit.selectKind(ProfileKind.webSocket);

        expect(formOf(cubit).errors, isEmpty);
        expect(formOf(cubit).canSave, isFalse);
        expect(formOf(cubit).canTest, isFalse);
      });

      test('typing in one field shows only its own error', () async {
        final cubit = await started();
        cubit
          ..selectKind(ProfileKind.webSocket)
          ..setUrl('nope');

        expect(formOf(cubit).errors.keys, [ProfileDraftField.url]);
      });

      test(
        'leaving a field (touchField) shows its error without typing',
        () async {
          final cubit = await started();
          cubit.selectKind(ProfileKind.webSocket);

          cubit.touchField(ProfileDraftField.label);

          expect(formOf(cubit).errors, {
            ProfileDraftField.label: 'Enter a name.',
          });
        },
      );

      test('Save on an incomplete form shows every error', () async {
        final cubit = await started();
        cubit.selectKind(ProfileKind.webSocket);

        await cubit.save();

        expect(
          formOf(cubit).errors.keys,
          containsAll([ProfileDraftField.label, ProfileDraftField.url]),
        );
        expect(store.saves, 0);
      });

      test(
        'touching a field keeps a running probe and a confirmation',
        () async {
          final cubit = await started();
          fillStdio(cubit);
          await cubit.testConnection();
          final probe = formOf(cubit).probe;

          cubit.touchField(ProfileDraftField.command);

          expect(formOf(cubit).probe, probe);
        },
      );
    });

    test('a secret-like env key blocks saving; the value is never shown or '
        'logged', () async {
      final cubit = await started();
      fillStdio(cubit);

      cubit.setEnv('OPENAI_API_KEY=sk-x');

      expect(
        formOf(cubit).errors[ProfileDraftField.env],
        'OPENAI_API_KEY looks like a secret. Set it in the system '
        r'environment or reference it from the agent config as ${secret:…}.',
      );
      expect(formOf(cubit).canSave, isFalse);
      await cubit.save();
      expect(store.saves, 0);
      expect(formOf(cubit).errors.values.join(), isNot(contains('sk-x')));
      expect(logger.entries.toString(), isNot(contains('sk-x')));
    });

    test(
      'an unclosed quote in arguments is an error at the arguments',
      () async {
        final cubit = await started();
        fillStdio(cubit);

        cubit.setArgs('serve "--stdio');

        expect(formOf(cubit).errors[ProfileDraftField.args], isNotNull);
        expect(formOf(cubit).canSave, isFalse);
      },
    );

    test('a WebSocket URL error uses the text of the mockup', () async {
      final cubit = await started();
      fillWebSocket(cubit, url: 'http://nope');

      expect(
        formOf(cubit).errors[ProfileDraftField.url],
        'Use ws:// or wss:// with a host.',
      );
      expect(formOf(cubit).canTest, isFalse);
    });

    test('ws:// to another machine gives the warning but does not block '
        'saving', () async {
      final cubit = await started();
      fillWebSocket(cubit, url: 'ws://devbox:7420');

      // Без токена подсказка не обещает токен (решение 2026-11-05, D20).
      expect(
        formOf(cubit).warning,
        'ws:// to another machine: traffic is sent unencrypted.',
      );
      expect(formOf(cubit).canSave, isTrue);

      cubit.selectTokenEnv();
      expect(
        formOf(cubit).warning,
        'ws:// to another machine: the token is sent unencrypted.',
      );

      cubit.setUrl('ws://localhost:7420');
      expect(formOf(cubit).warning, isNull);
    });

    test('the token has two choices; the variable defaults to '
        'CODELAB_AGENT_TOKEN and the name survives switching', () async {
      final cubit = await started(
        environment: const {'CODELAB_AGENT_TOKEN': 'x'},
      );
      fillWebSocket(cubit);
      expect(formOf(cubit).draft.token, const NoToken());

      cubit.selectTokenEnv();
      expect(formOf(cubit).draft.token, const EnvToken('CODELAB_AGENT_TOKEN'));

      cubit.setTokenEnvName('DEVBOX_TOKEN');
      cubit.selectTokenNone();
      expect(formOf(cubit).draft.token, const NoToken());
      cubit.selectTokenEnv();
      expect(formOf(cubit).draft.token, const EnvToken('DEVBOX_TOKEN'));
    });

    test('an unset variable gives "<NAME> is not set in CodeLab\'s '
        'environment." and keeps saving available; the value is never in '
        'the state', () async {
      final cubit = await started(environment: const {'SET_ONE': _leak});
      fillWebSocket(cubit);
      cubit.selectTokenEnv();

      cubit.setTokenEnvName('MISSING_TOKEN');
      expect(
        formOf(cubit).tokenNotice,
        "MISSING_TOKEN is not set in CodeLab's environment.",
      );
      expect(formOf(cubit).canSave, isTrue);

      cubit.setTokenEnvName('SET_ONE');
      expect(formOf(cubit).tokenNotice, isNull);
      expect(formOf(cubit).toString(), isNot(contains(_leak)));
      expect(formOf(cubit).draft.toString(), isNot(contains(_leak)));
    });

    test('an invalid variable name is an error at the token field', () async {
      final cubit = await started();
      fillWebSocket(cubit);
      cubit.selectTokenEnv();

      cubit.setTokenEnvName('1BAD');

      expect(formOf(cubit).errors[ProfileDraftField.token], isNotNull);
      expect(formOf(cubit).canSave, isFalse);
    });
  });

  group('test connection', () {
    test('Editing → Probing → Editing with the outcome; the label of the '
        'save button follows the result', () async {
      wsTransport = FakeAcpTransport()
        ..initializeAgentInfo = const Implementation(
          name: 'scripted',
          version: '1.2.3',
        );
      final cubit = await started();
      fillWebSocket(cubit);
      expect(formOf(cubit).saveLabel, 'Save without test');
      final seen = record(cubit);

      await cubit.testConnection();
      // Подписчик потока получает состояния асинхронно.
      await pumpEventQueue();

      expect(seen.map((s) => s.runtimeType), [Probing, Editing]);
      expect((seen.first as Probing).probeId, 1);
      expect(formOf(cubit).probe, isA<Reachable>());
      expect(formOf(cubit).saveLabel, 'Save');
      expect(events('connection_profile.probe_started'), ['info']);
      expect(events('connection_profile.probe_finished'), ['info']);
      expect(eventOf('connection_profile.probe_started')['type'], 'websocket');
      expect(
        eventOf('connection_profile.probe_finished')['outcome'],
        isNotNull,
      );
    });

    test('editing a field drops the previous result: Save becomes '
        '"Save without test" again', () async {
      final cubit = await started();
      fillWebSocket(cubit);
      await cubit.testConnection();
      expect(formOf(cubit).saveLabel, 'Save');

      cubit.setUrl('wss://other:1');

      expect(formOf(cubit).probe, isNull);
      expect(formOf(cubit).saveLabel, 'Save without test');
    });

    test('is not started for an invalid address or command', () async {
      final cubit = await started();
      fillWebSocket(cubit, url: 'nope');

      await cubit.testConnection();

      expect(cubit.state, isA<Editing>());
      expect(events('connection_profile.probe_started'), isEmpty);
    });

    test('works while the name is still empty: only the fields the agent '
        'needs are checked', () async {
      final cubit = await started();
      cubit.setUrl('wss://devbox:7420');
      cubit.selectKind(ProfileKind.webSocket);
      expect(formOf(cubit).canTest, isTrue);

      await cubit.testConnection();

      expect(formOf(cubit).probe, isA<Reachable>());
    });

    test('a stdio probe starts in the project folder and sends only '
        'initialize', () async {
      final cubit = await started();
      fillStdio(cubit);

      await cubit.testConnection();

      expect(stdioConfigs.single.cwd, '/work');
      expect(stdioConfigs.single.command, 'codelab-agent');
      final methods = [
        for (final message in stdioTransports.single.sentMessages)
          message.toString(),
      ];
      expect(methods, hasLength(1));
    });

    test('without a project a stdio probe starts without the project folder '
        'and still sends only initialize (D7)', () async {
      projectFolder = null;
      final cubit = await started();
      fillStdio(cubit);
      expect(formOf(cubit).draft.runInProjectDirectory, isTrue);

      await cubit.testConnection();

      expect(stdioConfigs.single.cwd, isNull);
      expect(stdioTransports.single.sentMessages, hasLength(1));
      // Флажок профиля формы не меняется: подмена касается только проверки.
      expect(formOf(cubit).draft.runInProjectDirectory, isTrue);
    });

    test('without a project a WebSocket probe is not changed (D7)', () async {
      projectFolder = null;
      final cubit = await started();
      fillWebSocket(cubit);

      await cubit.testConnection();

      expect(formOf(cubit).probe, isA<Reachable>());
      expect(wsOpened, 1);
    });

    test('a new edit during a probe discards its outcome with '
        'probe_discarded and closes the transport', () async {
      nextStdio = () => FakeAcpTransport()..autoRespondToInitialize = false;
      final cubit = await started();
      fillStdio(cubit);
      unawaited(cubit.testConnection());
      await pumpEventQueue();
      expect(cubit.state, isA<Probing>());

      cubit.setCommand('other-agent');
      await pumpEventQueue();

      expect(cubit.state, isA<Editing>());
      expect(formOf(cubit).probe, isNull);
      expect(stdioTransports.single.state, AcpTransportState.closed);
      expect(events('connection_profile.probe_discarded'), ['debug']);
      expect(eventOf('connection_profile.probe_discarded')['operation_id'], 1);
      expect(events('connection_profile.probe_finished'), isEmpty);
    });

    test('a repeated probe gets the next number; the outcome of the first '
        'does not change the form', () async {
      var attempt = 0;
      nextStdio = () => attempt++ == 0
          ? (FakeAcpTransport()..autoRespondToInitialize = false)
          : FakeAcpTransport();
      final cubit = await started();
      fillStdio(cubit);
      unawaited(cubit.testConnection());
      await pumpEventQueue();
      final first = (cubit.state as Probing).probeId;

      await cubit.testConnection();
      await pumpEventQueue();

      expect(first, 1);
      expect(cubit.state, isA<Editing>());
      expect(formOf(cubit).probe, isA<Reachable>());
      expect(events('connection_profile.probe_discarded'), ['debug']);
      expect(eventOf('connection_profile.probe_discarded')['operation_id'], 1);
      expect(
        logger.entries
            .where((e) => e['event'] == 'connection_profile.probe_finished')
            .map((e) => e['operation_id']),
        [2],
      );
    });

    test('closing the dialog cancels the probe: the transport is closed and '
        'the outcome is discarded', () async {
      nextStdio = () => FakeAcpTransport()..autoRespondToInitialize = false;
      final cubit = await started();
      fillStdio(cubit);
      unawaited(cubit.testConnection());
      await pumpEventQueue();
      expect(cubit.state, isA<Probing>());

      await cubit.close();
      await pumpEventQueue();

      expect(stdioTransports.single.state, AcpTransportState.closed);
      expect(events('connection_profile.probe_discarded'), ['debug']);
      expect(events('connection_profile.probe_finished'), isEmpty);
    });
  });

  group('plaintext confirmation before Test connection (user decision '
      '2026-11-05)', () {
    const env = {'CODELAB_AGENT_TOKEN': _leak};

    test('ws:// to another machine with a token asks first; the token does '
        'not leave until "Test anyway"', () async {
      final cubit = await started(environment: env);
      fillWebSocket(cubit, url: 'ws://devbox:7420/acp?t=1');
      cubit.selectTokenEnv();

      await cubit.testConnection();

      expect(cubit.state, isA<ConfirmingPlaintextProbe>());
      expect(wsOpened, 0);
      final message = (cubit.state as ConfirmingPlaintextProbe).message;
      expect(
        message,
        'The token for ws://devbox:7420 will travel in clear text. Use '
        'wss:// if the host supports it.',
      );
      for (final secret in const ['u:p', '/acp', 't=', _leak]) {
        expect(message, isNot(contains(secret)), reason: secret);
      }

      await cubit.confirmPlaintextProbe();

      expect(wsOpened, 1);
      expect(cubit.state, isA<Editing>());
      expect(formOf(cubit).probe, isA<Reachable>());
    });

    test(
      'without a token or to a local host the probe starts at once',
      () async {
        final cubit = await started(environment: env);
        fillWebSocket(cubit, url: 'ws://devbox:7420');
        await cubit.testConnection();
        expect(wsOpened, 1);
        expect(cubit.state, isA<Editing>());

        cubit
          ..setUrl('ws://localhost:7420')
          ..selectTokenEnv();
        await cubit.testConnection();
        expect(wsOpened, 2);
      },
    );

    test(
      'a new URL or token asks again; an edit cancels the question',
      () async {
        final cubit = await started(environment: env);
        fillWebSocket(cubit, url: 'ws://devbox:7420');
        cubit.selectTokenEnv();
        await cubit.testConnection();
        await cubit.confirmPlaintextProbe();
        expect(wsOpened, 1);

        // Те же URL и токен: повторная проверка не спрашивает.
        await cubit.testConnection();
        expect(wsOpened, 2);

        cubit.setUrl('ws://other:7420');
        await cubit.testConnection();
        expect(cubit.state, isA<ConfirmingPlaintextProbe>());
        cubit.setTokenEnvName('OTHER_TOKEN');
        expect(cubit.state, isA<Editing>());
        await cubit.confirmPlaintextProbe();
        expect(wsOpened, 2);

        await cubit.testConnection();
        expect(cubit.state, isA<ConfirmingPlaintextProbe>());
      },
    );

    test('a confirmed Test also covers Save of the same URL and token, and '
        'the other way round', () async {
      final cubit = await started(environment: env);
      fillWebSocket(cubit, url: 'ws://devbox:7420');
      cubit.selectTokenEnv();
      await cubit.testConnection();
      await cubit.confirmPlaintextProbe();

      await cubit.save();

      expect(cubit.state, isA<Saved>());
      expect(store.saves, 1);

      final other = await started(environment: env);
      fillWebSocket(other, label: 'Other', url: 'ws://devbox:7420');
      other.selectTokenEnv();
      await other.save();
      expect(other.state, isA<ConfirmingPlaintext>());
      await other.confirmPlaintext();
      expect(other.state, isA<Saved>());

      // «Add another» начинает новый профиль: прежнее подтверждение не
      // переносится, даже при том же URL и токене.
      other
        ..addAnother()
        ..setLabel('Third')
        ..setUrl('ws://devbox:7420')
        ..selectTokenEnv();
      await other.testConnection();
      expect(other.state, isA<ConfirmingPlaintextProbe>());
      expect(wsOpened, 1);
    });

    test('A -> B -> A asks again: any edit of the URL or the token drops the '
        'confirmation', () async {
      final cubit = await started(environment: env);
      fillWebSocket(cubit, url: 'ws://devbox:7420');
      cubit.selectTokenEnv();
      await cubit.testConnection();
      await cubit.confirmPlaintextProbe();

      cubit
        ..setUrl('ws://other:7420')
        ..setUrl('ws://devbox:7420');
      await cubit.testConnection();
      expect(cubit.state, isA<ConfirmingPlaintextProbe>());
      await cubit.confirmPlaintextProbe();

      cubit
        ..selectTokenNone()
        ..selectTokenEnv();
      await cubit.save();
      expect(cubit.state, isA<ConfirmingPlaintext>());
    });

    test(
      'a Save confirmed without a token does not cover a probe with one',
      () async {
        final cubit = await started(environment: env);
        fillWebSocket(cubit, url: 'ws://devbox:7420');
        await cubit.save();
        await cubit.confirmPlaintext();
        cubit
          ..addAnother()
          ..setLabel('Again')
          ..setUrl('ws://devbox:7420')
          ..selectTokenEnv();

        await cubit.testConnection();

        expect(cubit.state, isA<ConfirmingPlaintextProbe>());
        expect(wsOpened, 0);
      },
    );
  });

  group('save', () {
    test('Save without test writes the profile; the row will say "Not '
        'tested"; the default stays untouched', () async {
      final cubit = await started();
      fillStdio(cubit);
      final seen = record(cubit);

      await cubit.save();
      // Подписчик потока получает состояния асинхронно.
      await pumpEventQueue();

      expect(seen.map((s) => s.runtimeType), [Saving, Saved]);
      final saved = cubit.state as Saved;
      expect(saved.profileId, 'build-box');
      expect(saved.label, 'Build box');
      expect(saved.tested, isFalse);
      expect(saved.probe, isNull);
      expect(saved.useByDefault, isFalse);
      expect(store.profiles.map((p) => p.id), ['dev', 'build-box']);
      final profile = store.profiles.last as StdioProfile;
      expect(profile.args, ['serve', '--stdio']);
      expect(profile.runInProjectDirectory, isTrue);
      expect(
        (await SharedPreferences.getInstance()).getString(_defaultKey),
        isNull,
      );
      final event = eventOf('connection_profile.saved');
      expect(event['profile_id'], 'build-box');
      expect(event['type'], 'stdio');
      expect(event['token'], 'none');
      expect(event['tested'], false);
    });

    test('Save after a successful test marks the profile as tested', () async {
      final cubit = await started();
      fillWebSocket(cubit);
      cubit.selectTokenEnv();
      await cubit.testConnection();

      await cubit.save();

      final saved = cubit.state as Saved;
      expect(saved.tested, isTrue);
      expect(saved.probe, isA<Reachable>());
      final profile = store.profiles.last as WebSocketProfile;
      expect(profile.tokenRef, 'env:CODELAB_AGENT_TOKEN');
      final event = eventOf('connection_profile.saved');
      expect(event['type'], 'websocket');
      expect(event['token'], 'env');
      expect(event['tested'], true);
    });

    test('"Use by default" writes codelab.connection.default_profile; '
        'nothing connects', () async {
      final cubit = await started();
      fillStdio(cubit);
      cubit.setUseByDefault(true);

      await cubit.save();

      expect((cubit.state as Saved).useByDefault, isTrue);
      expect(
        (await SharedPreferences.getInstance()).getString(_defaultKey),
        'build-box',
      );
      expect(
        eventOf('connection_profile.default_changed')['profile_id'],
        'build-box',
      );
      // Подключение окна — дело страницы: у Cubit-а диалога нет ни
      // workspace, ни команд подключения.
      expect(stdioTransports, isEmpty);
    });

    test('ws:// to another machine asks for confirmation first; nothing '
        'is written until "Save anyway"', () async {
      final cubit = await started();
      fillWebSocket(cubit, url: 'ws://devbox:7420/acp?t=1');
      final seen = record(cubit);

      await cubit.save();

      expect(cubit.state, isA<ConfirmingPlaintext>());
      expect(store.saves, 0);
      final confirming = cubit.state as ConfirmingPlaintext;
      expect(confirming.message, contains('ws://devbox:7420'));
      for (final secret in const ['u:p', '/acp', 't=']) {
        expect(confirming.message, isNot(contains(secret)), reason: secret);
      }

      await cubit.confirmPlaintext();
      // Подписчик потока получает состояния асинхронно.
      await pumpEventQueue();

      expect(seen.map((s) => s.runtimeType), [
        Saving,
        ConfirmingPlaintext,
        Saving,
        Saved,
      ]);
      expect(store.saves, 1);
    });

    test('the confirmation without a token speaks about prompts and files, '
        'with a token about the token; only scheme://host:port', () async {
      final cubit = await started(
        environment: const {'CODELAB_AGENT_TOKEN': _leak},
      );
      fillWebSocket(cubit, url: 'ws://devbox:7420/acp?t=1');

      await cubit.save();
      expect(
        (cubit.state as ConfirmingPlaintext).message,
        'Prompts and files sent to ws://devbox:7420 will travel in clear '
        'text. Use wss:// if the host supports it.',
      );

      cubit.selectTokenEnv();
      await cubit.save();
      final message = (cubit.state as ConfirmingPlaintext).message;
      expect(
        message,
        'The token for ws://devbox:7420 will travel in clear text. Use '
        'wss:// if the host supports it.',
      );
      for (final secret in const ['u:p', '/acp', 't=', _leak]) {
        expect(message, isNot(contains(secret)), reason: secret);
      }
      expect(store.saves, 0);
    });

    test('editing during the confirmation cancels it', () async {
      final cubit = await started();
      fillWebSocket(cubit, url: 'ws://devbox:7420');
      await cubit.save();
      expect(cubit.state, isA<ConfirmingPlaintext>());

      cubit.setUrl('wss://devbox:7420');

      expect(cubit.state, isA<Editing>());
      await cubit.confirmPlaintext();
      expect(store.saves, 0);
    });

    test('ws://localhost needs no confirmation', () async {
      final cubit = await started();
      fillWebSocket(cubit, url: 'ws://localhost:7420');

      await cubit.save();

      expect(cubit.state, isA<Saved>());
    });

    test('a write failure gives SaveFailed with a generic text, keeps the '
        'draft and logs only the exception type', () async {
      store.failSave = _LeakyException();
      final cubit = await started(environment: const {'DEVBOX_TOKEN': _leak});
      fillStdio(cubit);
      final draft = formOf(cubit).draft;
      final seen = record(cubit);

      await cubit.save();
      // Подписчик потока получает состояния асинхронно.
      await pumpEventQueue();

      expect(seen.map((s) => s.runtimeType), [Saving, SaveFailed]);
      final failed = cubit.state as SaveFailed;
      expect(failed.message, 'Could not save the profile. Try again.');
      expect(failed.form.draft, draft);
      final event = eventOf('connection_profile.save_failed');
      expect(event['level'], 'warning');
      expect(event['profile_id'], 'build-box');
      expect(event['error_type'], '_LeakyException');
      expect(event['stage'], 'profile');
      expect(logger.entries.toString(), isNot(contains(_leak)));
      expect(
        (await SharedPreferences.getInstance()).getString(_defaultKey),
        isNull,
      );

      // Повторная попытка после починки хранилища проходит.
      store.failSave = null;
      await cubit.save();
      expect(cubit.state, isA<Saved>());
    });

    test('a failed "Use by default" key after a written profile logs '
        'save_failed with stage default and still shows "Profile saved" '
        'without the default', () async {
      final cubit = await started(
        preferences: const _FailingDefaultPreferences(),
      );
      fillStdio(cubit);
      cubit.setUseByDefault(true);

      await cubit.save();

      expect(store.saves, 1);
      final saved = cubit.state as Saved;
      expect(saved.useByDefault, isFalse);
      final event = eventOf('connection_profile.save_failed');
      expect(event['level'], 'warning');
      expect(event['profile_id'], 'build-box');
      expect(event['error_type'], '_LeakyException');
      expect(event['stage'], 'default');
      expect(logger.entries.toString(), isNot(contains(_leak)));
    });

    test('a taken id is checked again at save time against the file', () async {
      final cubit = await started();
      fillStdio(cubit, label: 'Late');
      // Другой процесс (CLI) успел создать профиль с таким id.
      store.profiles.add(
        const ConnectionProfile.stdio(id: 'late', label: 'x', command: 'c'),
      );

      await cubit.save();

      expect(store.saves, 0);
      expect(cubit.state, isA<Editing>());
      expect(
        formOf(cubit).errors[ProfileDraftField.id],
        'A profile with id "late" already exists.',
      );
    });

    test('a second Save while the ids are being read writes one profile and '
        'logs one saved event; edits are ignored meanwhile (M2)', () async {
      final cubit = await started();
      fillStdio(cubit);
      final gate = store.loadGate = Completer<void>();

      final first = cubit.save();
      // Синхронно после первого нажатия форма уже в Saving.
      expect(cubit.state, isA<Saving>());
      final second = cubit.save();
      cubit.setLabel('Changed');
      expect(formOf(cubit).draft.label, 'Build box');
      gate.complete();
      await Future.wait([first, second]);

      expect(store.saves, 1);
      expect(store.profiles.map((p) => p.id), ['dev', 'build-box']);
      expect(events('connection_profile.saved'), hasLength(1));
      expect(cubit.state, isA<Saved>());
    });

    test('"Save anyway" reads the ids again: an id taken in between is not '
        'overwritten (safety)', () async {
      final cubit = await started();
      fillWebSocket(cubit, label: 'Devbox 2', url: 'ws://devbox:7420');
      await cubit.save();
      expect(cubit.state, isA<ConfirmingPlaintext>());
      // Другой процесс (CLI) занял id, пока висело подтверждение.
      const taken = ConnectionProfile.stdio(
        id: 'devbox-2',
        label: 'Other',
        command: 'c',
      );
      store.profiles.add(taken);

      await cubit.confirmPlaintext();

      expect(store.saves, 0);
      expect(store.profiles.last, taken);
      expect(cubit.state, isA<Editing>());
      expect(
        formOf(cubit).errors[ProfileDraftField.id],
        'A profile with id "devbox-2" already exists.',
      );
    });

    test('probe events carry the draft id, fixed at the start (N2)', () async {
      final cubit = await started();
      fillStdio(cubit, label: 'First');
      await cubit.testConnection();
      for (final name in const ['started', 'finished']) {
        expect(
          eventOf('connection_profile.probe_$name')['profile_id'],
          'first',
        );
      }

      // Проверка с отброшенным исходом тоже называет id, взятый на старте.
      nextStdio = () => FakeAcpTransport()..autoRespondToInitialize = false;
      final pending = cubit.testConnection();
      await pumpEventQueue();
      cubit.setLabel('Renamed');
      await pending;
      expect(
        eventOf('connection_profile.probe_discarded')['profile_id'],
        'first',
      );
    });

    test('every profile saved over the life of the dialog is kept with its '
        'own probe outcome (M1)', () async {
      final cubit = await started();
      fillStdio(cubit, label: 'First');
      await cubit.testConnection();
      await cubit.save();
      cubit.addAnother();
      cubit.setLabel('Second');
      await cubit.save();

      final saved = cubit.savedProfiles;
      expect(saved.map((s) => s.profileId), ['first', 'second']);
      expect(saved[0].probe, isA<Reachable>());
      expect(saved[1].probe, isNull);
    });

    test('Add another returns to an empty form of the same type', () async {
      final cubit = await started();
      fillWebSocket(cubit);
      cubit.setUseByDefault(true);
      await cubit.save();
      expect(cubit.state, isA<Saved>());

      cubit.addAnother();
      await pumpEventQueue();

      expect(cubit.state, isA<Editing>());
      expect(formOf(cubit).draft.kind, ProfileKind.webSocket);
      expect(formOf(cubit).draft.label, '');
      expect(formOf(cubit).draft.url, '');
      expect(formOf(cubit).useByDefault, isFalse);
      expect(formOf(cubit).probe, isNull);

      // Новый id уже видит только что сохранённый профиль.
      fillWebSocket(cubit, label: 'Devbox 2');
      expect(
        formOf(cubit).errors[ProfileDraftField.id],
        'A profile with id "devbox-2" already exists.',
      );
    });

    test('closing without saving writes nothing (Esc)', () async {
      final cubit = await started();
      fillStdio(cubit);
      cubit.setUseByDefault(true);

      await cubit.close();

      expect(store.saves, 0);
      expect(
        (await SharedPreferences.getInstance()).getString(_defaultKey),
        isNull,
      );
    });
  });

  group('token in the secret store (1.6, D13, D14)', () {
    const ownName = 'codelab/profiles/devbox/token';
    const readOnlyHint =
        "Secret store env is read-only. Add 'secrets.backend: file' to "
        '/home/u/.codelab/config.yaml to store secrets in '
        '/home/u/.codelab/secrets.yaml (plaintext, 0600), or set '
        'CODELAB_SECRET_X in the environment.';

    /// WebSocket-черновик `devbox` с токеном «Store a new token».
    Future<AddProfileCubit> newTokenForm({
      String url = 'wss://devbox:7420',
      String value = _leak,
      Map<String, String> environment = const {},
    }) async {
      final cubit = await started(environment: environment);
      fillWebSocket(cubit, label: 'devbox', url: url);
      cubit
        ..selectTokenNew()
        ..setNewToken(value);
      return cubit;
    }

    test('four variants: the stored secrets and the target of a new token '
        'come from the store', () async {
      secrets = FakeProfileSecrets(values: {'codelab/profiles/ci/token': 'x'});
      final cubit = await started();
      fillWebSocket(cubit, label: 'devbox');

      final form = formOf(cubit);
      expect(form.secretNames, ['codelab/profiles/ci/token']);
      expect(form.storedSecretsHint, isNull);
      expect(form.newTokenAvailable, isTrue);
      expect(
        form.newTokenHint,
        'Saved as codelab/profiles/devbox/token in file. The value is never '
        'shown again or written to profiles.json.',
      );
      expect(form.tokenKind, AddProfileTokenKind.none);
    });

    test('a read-only store disables "Store a new token" and says why; '
        '"From environment variable" stays', () async {
      secrets = FakeProfileSecrets(
        backend: const ProfileSecretBackend(
          id: 'env',
          writable: false,
          unavailableReason: readOnlyHint,
        ),
      );
      final cubit = await started();
      fillWebSocket(cubit);

      final form = formOf(cubit);
      expect(form.newTokenAvailable, isFalse);
      expect(form.newTokenHint, readOnlyHint);
      cubit.selectTokenNew();
      expect(formOf(cubit).tokenKind, AddProfileTokenKind.none);
      cubit.selectTokenEnv();
      expect(formOf(cubit).tokenKind, AddProfileTokenKind.env);
    });

    test('no stored secrets, or an unreadable store, disables "Use stored '
        'secret" with the reason', () async {
      final cubit = await started();
      fillWebSocket(cubit);
      expect(formOf(cubit).storedSecretsHint, 'No stored secrets in file.');
      cubit.selectTokenStored();
      expect(formOf(cubit).tokenKind, AddProfileTokenKind.none);

      secrets = FakeProfileSecrets()..namesFailure = StateError(_leak);
      final failing = await started();
      fillWebSocket(failing);
      expect(formOf(failing).storedSecretsHint, 'No stored secrets in file.');
      expect(logger.entries.toString(), isNot(contains(_leak)));
    });

    test('"Store a new token" is written before the profile; the profile '
        'holds only the reference', () async {
      final cubit = await newTokenForm();
      await cubit.testConnection();
      // Проверка не пишет в хранилище: токен идёт транспорту из памяти.
      expect(secrets.values, isEmpty);
      expect(store.saves, 0);
      expect(wsTokens, [_leak]);

      await cubit.save();

      expect(cubit.state, isA<Saved>());
      expect(secrets.values, {ownName: _leak});
      expect(
        (store.profiles.firstWhere((p) => p.id == 'devbox') as WebSocketProfile)
            .tokenRef,
        'secret:$ownName',
      );
      expect(
        eventOf('connection_profile.token_stored'),
        containsPair('backend', 'file'),
      );
      expect(
        eventOf('connection_profile.token_stored'),
        containsPair('profile_id', 'devbox'),
      );
      expect(
        eventOf('connection_profile.saved'),
        containsPair('token', 'secret'),
      );
      expect(logger.entries.toString(), isNot(contains(_leak)));
      expect(store.profiles.toString(), isNot(contains(_leak)));
    });

    test('the form never prints the new token', () async {
      final cubit = await newTokenForm();

      expect(cubit.state.toString(), isNot(contains(_leak)));
      expect(formOf(cubit).draft.token.toString(), isNot(contains(_leak)));
      expect(formOf(cubit).tokenKind, AddProfileTokenKind.newToken);
    });

    test('"Use stored secret" writes only the profile; the probe reads the '
        'secret the same way a connection does', () async {
      secrets = FakeProfileSecrets(
        values: {'codelab/profiles/ci/token': _leak},
      );
      classifier = (_) => const Unauthorized();
      wsFactoryFails = true;
      final cubit = await started();
      fillWebSocket(cubit, label: 'ci');
      cubit
        ..selectTokenStored()
        ..setStoredSecret('codelab/profiles/ci/token');

      await cubit.testConnection();
      expect(
        formOf(cubit).probeText,
        'Unauthorized: the agent rejected the token',
      );
      secrets.calls.clear();

      await cubit.save();

      expect(cubit.state, isA<Saved>());
      expect(
        (store.profiles.firstWhere((p) => p.id == 'ci') as WebSocketProfile)
            .tokenRef,
        'secret:codelab/profiles/ci/token',
      );
      expect(secrets.calls.where((c) => c.startsWith('store:')), isEmpty);
      expect(secrets.calls.where((c) => c.startsWith('delete:')), isEmpty);
      expect(secrets.values, {'codelab/profiles/ci/token': _leak});
      expect(
        eventOf('connection_profile.saved'),
        containsPair('token', 'secret'),
      );
      expect(events('connection_profile.token_stored'), isEmpty);
      expect(logger.entries.toString(), isNot(contains(_leak)));
    });

    test('a secret that vanished from the store sends no token: the agent '
        'requires one', () async {
      secrets = FakeProfileSecrets(
        values: {'codelab/profiles/ci/token': _leak},
      );
      classifier = (_) => const Unauthorized();
      wsFactoryFails = true;
      final cubit = await started();
      fillWebSocket(cubit, label: 'ci');
      cubit
        ..selectTokenStored()
        ..setStoredSecret('codelab/profiles/ci/token');
      // Другой процесс удалил секрет, пока диалог был открыт.
      secrets.values.remove('codelab/profiles/ci/token');

      await cubit.testConnection();

      expect(
        formOf(cubit).probeText,
        'Unauthorized: the agent requires a token',
      );
    });

    test('an empty new token blocks saving; a name that cannot name a secret '
        'is rejected at the id field', () async {
      final cubit = await newTokenForm(value: '');
      expect(formOf(cubit).canSave, isFalse);
      cubit.setNewToken(_leak);
      expect(formOf(cubit).canSave, isTrue);
      cubit.setId('a..b');
      expect(formOf(cubit).canSave, isFalse);
      expect(formOf(cubit).errors, contains(ProfileDraftField.id));
    });

    test('an existing secret of the same name stops the save: nothing is '
        'written and the field says what to do', () async {
      secrets = FakeProfileSecrets(values: {ownName: 'older-value'});
      final cubit = await newTokenForm();

      await cubit.save();

      expect(cubit.state, isA<Editing>());
      expect(
        formOf(cubit).errors[ProfileDraftField.token],
        'A stored token codelab/profiles/devbox/token already exists in '
        'file. Choose it with "Use stored secret" or remove it with codelab '
        'secret delete.',
      );
      expect(secrets.values, {ownName: 'older-value'});
      expect(store.saves, 0);
      expect(logger.entries.toString(), isNot(contains(_leak)));

      // Любая правка снимает ошибку.
      cubit.selectTokenNone();
      expect(formOf(cubit).errors[ProfileDraftField.token], isNull);
    });

    test(
      'a refused profile write rolls the new secret back and logs it',
      () async {
        store.failSave = _LeakyException();
        final cubit = await newTokenForm();

        await cubit.save();

        expect(cubit.state, isA<SaveFailed>());
        expect(
          (cubit.state as SaveFailed).message,
          'Could not save the profile. Try again.',
        );
        expect(secrets.values, isEmpty);
        expect(
          eventOf('connection_profile.token_rollback'),
          containsPair('profile_id', 'devbox'),
        );
        expect(events('connection_profile.token_stored'), isEmpty);
        expect(events('connection_profile.save_failed'), ['warning']);
        expect(logger.entries.toString(), isNot(contains(_leak)));
        expect((cubit.state as SaveFailed).message, isNot(contains(_leak)));
      },
    );

    test('a failed rollback tells where the token stays', () async {
      store.failSave = _LeakyException();
      secrets.nextDelete = const Failed('cannot delete');
      final cubit = await newTokenForm();

      await cubit.save();

      expect(
        (cubit.state as SaveFailed).message,
        'The profile was not saved; the token stays in file as $ownName. '
        'Remove it with codelab secret delete $ownName.',
      );
      expect(
        eventOf('connection_profile.token_rollback_failed'),
        allOf(
          containsPair('profile_id', 'devbox'),
          containsPair('backend', 'file'),
        ),
      );
      expect(events('connection_profile.token_rollback'), isEmpty);
      expect(logger.entries.toString(), isNot(contains(_leak)));
    });

    test(
      'a store that refuses the write is reported without the value',
      () async {
        secrets.nextWrite = const ReadOnly('Secret store env is read-only.');
        final cubit = await newTokenForm();

        await cubit.save();

        expect(cubit.state, isA<SaveFailed>());
        expect(
          (cubit.state as SaveFailed).message,
          'Secret store env is read-only.',
        );
        expect(store.saves, 0);
        expect(logger.entries.toString(), isNot(contains(_leak)));
      },
    );

    test(
      'Saving holds the form: no second write, no edit of the token',
      () async {
        secrets.storeGate = Completer<void>();
        final cubit = await newTokenForm();

        final first = cubit.save();
        await pumpEventQueue();
        expect(cubit.state, isA<Saving>());
        final second = cubit.save();
        cubit.setNewToken('another');
        secrets.storeGate!.complete();
        await Future.wait([first, second]);

        expect(cubit.state, isA<Saved>());
        expect(
          secrets.calls.where((c) => c.startsWith('store:')),
          hasLength(1),
        );
        expect(secrets.values, {ownName: _leak});
      },
    );

    group('ws:// to another machine', () {
      const remote = 'ws://10.0.0.5:8765/acp?t=x';

      test('a new token and a stored secret are confirmed before the probe '
          'and before the save, like a variable', () async {
        secrets = FakeProfileSecrets(
          values: {'codelab/profiles/ci/token': 'x'},
        );
        final cubit = await newTokenForm(url: remote);
        expect(
          formOf(cubit).warning,
          'ws:// to another machine: the token is sent unencrypted.',
        );

        await cubit.testConnection();
        expect(cubit.state, isA<ConfirmingPlaintextProbe>());
        expect(wsOpened, 0);
        expect(
          (cubit.state as ConfirmingPlaintextProbe).message,
          'The token for ws://10.0.0.5:8765 will travel in clear text. Use '
          'wss:// if the host supports it.',
        );
        await cubit.confirmPlaintextProbe();
        expect(wsOpened, 1);

        // Одно подтверждение на пару «URL, токен»: «Save» не спрашивает.
        await cubit.save();
        expect(cubit.state, isA<Saved>());

        cubit.addAnother();
        fillWebSocket(cubit, label: 'ci', url: remote);
        cubit
          ..selectTokenStored()
          ..setStoredSecret('codelab/profiles/ci/token');
        await cubit.testConnection();
        expect(cubit.state, isA<ConfirmingPlaintextProbe>());
        expect(wsOpened, 1);
      });

      test(
        'a new secret name or a new token value resets the confirmation',
        () async {
          secrets = FakeProfileSecrets(
            values: {
              'codelab/profiles/ci/token': 'x',
              'codelab/profiles/dev/token': 'y',
            },
          );
          final cubit = await started();
          fillWebSocket(cubit, label: 'ci', url: remote);
          cubit
            ..selectTokenStored()
            ..setStoredSecret('codelab/profiles/ci/token');
          await cubit.testConnection();
          await cubit.confirmPlaintextProbe();
          expect(wsOpened, 1);

          cubit.setStoredSecret('codelab/profiles/dev/token');
          await cubit.testConnection();
          expect(cubit.state, isA<ConfirmingPlaintextProbe>());
          await cubit.confirmPlaintextProbe();
          expect(wsOpened, 2);

          cubit
            ..selectTokenNew()
            ..setNewToken('first');
          await cubit.testConnection();
          expect(cubit.state, isA<ConfirmingPlaintextProbe>());
          await cubit.confirmPlaintextProbe();
          expect(wsOpened, 3);

          cubit
            ..setNewToken('second')
            ..setNewToken('first');
          await cubit.testConnection();
          // Возврат к прежнему значению подтверждение не восстанавливает.
          expect(cubit.state, isA<ConfirmingPlaintextProbe>());
        },
      );

      test('"Save anyway" for a new token writes the secret after the '
          'confirmation only', () async {
        final cubit = await newTokenForm(url: remote);

        await cubit.save();

        expect(cubit.state, isA<ConfirmingPlaintext>());
        expect(secrets.values, isEmpty);
        expect(store.saves, 0);
        expect(
          (cubit.state as ConfirmingPlaintext).message,
          'The token for ws://10.0.0.5:8765 will travel in clear text. Use '
          'wss:// if the host supports it.',
        );

        await cubit.confirmPlaintext();

        expect(cubit.state, isA<Saved>());
        expect(secrets.values, {ownName: _leak});
      });
    });

    test('the store is opened by the dialog itself: OpeningSecrets first, a '
        'late open after close is dropped', () async {
      final gate = Completer<void>();
      final cubit = AddProfileCubit(
        store: store,
        openSecrets: () async {
          await gate.future;
          return secrets;
        },
        preferences: const SharedPreferencesConnectionPreferences(),
        probe: ProfileProbe(resolvers: const []),
        kinds: const [ProfileKind.webSocket],
        environment: const {},
        projectDirectory: () => '/work',
      );
      expect(cubit.state, isA<OpeningSecrets>());

      final started = cubit.start();
      await pumpEventQueue();
      expect(cubit.state, isA<OpeningSecrets>());
      await cubit.close();
      gate.complete();
      await started;

      expect(cubit.state, isA<OpeningSecrets>());
    });

    test('every dialog reopens the store: a config edited from env to file '
        'makes "Store a new token" available at the next opening', () async {
      var edited = false;
      Future<ProfileSecrets> reopen() async => FakeProfileSecrets(
        backend: edited
            ? const ProfileSecretBackend(id: 'file', writable: true)
            : const ProfileSecretBackend(
                id: 'env',
                writable: false,
                unavailableReason: 'Secret store env is read-only.',
              ),
      );
      AddProfileCubit dialog() {
        final cubit = AddProfileCubit(
          store: store,
          openSecrets: reopen,
          preferences: const SharedPreferencesConnectionPreferences(),
          probe: ProfileProbe(resolvers: const []),
          kinds: const [ProfileKind.webSocket],
          environment: const {},
          projectDirectory: () => '/work',
        );
        addTearDown(cubit.close);
        return cubit;
      }

      final first = dialog();
      await first.start();
      expect(formOf(first).newTokenAvailable, isFalse);

      edited = true;
      final second = dialog();
      await second.start();
      expect(formOf(second).newTokenAvailable, isTrue);
    });

    test('"Use stored secret" offers only codelab/profiles/*: a provider key '
        'and an MCP secret are not listed', () async {
      secrets = FakeProfileSecrets(
        values: {
          'codelab/openai': 'a',
          'codelab/mcp/git/token': 'b',
          'codelab/ws-ci': 'c',
          'codelab/profiles/ci/token': 'd',
        },
      );
      final cubit = await started();
      fillWebSocket(cubit);

      expect(formOf(cubit).secretNames, ['codelab/profiles/ci/token']);
      cubit.setStoredSecret('codelab/openai');
      expect(formOf(cubit).tokenKind, AddProfileTokenKind.none);
    });

    test('switching to stdio drops the new token from the draft and no '
        'token_stored is logged for the saved stdio profile', () async {
      final cubit = await newTokenForm();

      cubit.selectKind(ProfileKind.stdio);
      expect(formOf(cubit).draft.token, isA<NoToken>());
      cubit.setLabel('Build box');
      await cubit.save();

      expect(cubit.state, isA<Saved>());
      expect(events('connection_profile.token_stored'), isEmpty);
      expect(
        eventOf('connection_profile.saved'),
        containsPair('token', 'none'),
      );
      expect(secrets.values, isEmpty);
    });

    test(
      'closing during the write forgets the new token in Saving too',
      () async {
        secrets.storeGate = Completer<void>();
        final cubit = await newTokenForm();

        final saving = cubit.save();
        await pumpEventQueue();
        expect(cubit.state, isA<Saving>());
        await cubit.close();

        final token = formOf(cubit).draft.token;
        expect(token, isA<NewSecretToken>());
        expect((token as NewSecretToken).value.reveal(), isEmpty);
        secrets.storeGate!.complete();
        await saving;
      },
    );

    test('closing the dialog forgets the new token', () async {
      final cubit = await newTokenForm();

      await cubit.close();

      final token = formOf(cubit).draft.token;
      expect(token, isA<NewSecretToken>());
      expect((token as NewSecretToken).value.reveal(), isEmpty);
    });

    test('the marker stays out of every text of a whole session with a new '
        'token', () async {
      store.failSave = _LeakyException();
      final cubit = await started();
      final texts = <String>[];
      final subscription = cubit.stream.listen((state) {
        texts.add(state.toString());
        if (state case AddProfileInProgress(:final form)) {
          texts
            ..addAll(form.errors.values)
            ..add(form.warning ?? '')
            ..add(form.newTokenHint)
            ..add(form.probeText ?? '');
        }
        if (state case SaveFailed(:final message)) {
          texts.add(message);
        }
      });
      addTearDown(subscription.cancel);
      fillWebSocket(cubit, label: 'devbox', url: 'wss://host:1/acp?t=$_leak');
      cubit
        ..selectTokenNew()
        ..setNewToken(_leak);
      await cubit.testConnection();
      await cubit.save();
      await pumpEventQueue();

      final everything = '${texts.join('\n')}\n${logger.entries}';
      expect(everything, isNot(contains(_leak)));
      expect(everything, isNot(contains('/acp')));
    });
  });

  test('the marker does not leak into events or texts through a whole '
      'session of the dialog (3.4)', () async {
    store.failSave = _LeakyException();
    const url = 'wss://host:1/acp?t=$_leak';
    final cubit = await started(environment: const {'DEVBOX_TOKEN': _leak});
    final texts = <String>[];
    void collect(AddProfileState state) {
      switch (state) {
        case AddProfileInProgress(:final form):
          texts
            ..addAll(form.errors.values)
            ..add(form.warning ?? '')
            ..add(form.tokenNotice ?? '')
            ..add(form.saveLabel);
          texts.add(form.probeText ?? '');
        case Saved() || OpeningSecrets():
          break;
      }
      switch (state) {
        case SaveFailed(:final message) ||
            ConfirmingPlaintext(:final message) ||
            ConfirmingPlaintextProbe(:final message):
          texts.add(message);
        default:
          break;
      }
    }

    final subscription = cubit.stream.listen(collect);
    addTearDown(subscription.cancel);

    cubit
      ..selectKind(ProfileKind.webSocket)
      ..setLabel('Devbox')
      ..setUrl(url)
      ..selectTokenEnv()
      ..setTokenEnvName('DEVBOX_TOKEN');
    await cubit.testConnection();
    await cubit.save();
    await pumpEventQueue();

    expect(cubit.state, isA<SaveFailed>());
    final everything = '${texts.join('\n')}\n${logger.entries}';
    for (final secret in const [_leak, 'u:p', '/acp', 't=']) {
      expect(everything, isNot(contains(secret)), reason: secret);
    }
    // Имя переменной в журнал тоже не пишется (D17).
    expect(logger.entries.toString(), isNot(contains('DEVBOX_TOKEN')));
  });
}
