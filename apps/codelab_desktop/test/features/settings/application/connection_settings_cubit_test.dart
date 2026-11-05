// `ConnectionSettingsCubit` на временном `profiles.json` (задачи 2.2, 2.3 и
// 2.15 change `add-app-settings-shell`; spec app-settings «Список профилей на
// странице «Connection»», «Блок «Behavior»»; design.md D4, D5, D8–D10, D17,
// D21).
//
// Файл профилей настоящий (`JsonFileProfileStore` во временной папке), а
// `shared_preferences` — подменные значения: проверяется то, что видит
// пользователь и что остаётся на диске, а не внутренности Cubit.

import 'dart:async';
import 'dart:io';

import 'package:codelab_acp_testing/codelab_acp_testing.dart';
import 'package:codelab_client_acp/codelab_client_acp.dart';
import 'package:codelab_client_core/codelab_client_core.dart';
import 'package:codelab_client_io/codelab_client_io.dart'
    show JsonFileProfileStore;
import 'package:codelab_desktop/core/platform/connection_preferences.dart';
import 'package:codelab_desktop/features/settings/application/connection_commands.dart';
import 'package:codelab_desktop/features/settings/application/embedded_profile.dart';
import 'package:codelab_desktop/features/settings/application/connection_settings_cubit.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../support/fake_profile_secrets.dart';
import '../../../support/recording_logger.dart';

const _defaultKey = 'codelab.connection.default_profile';
const _connectOnStartKey = 'codelab.connection.connect_on_start';

/// Резолвер всех профилей: открывает фейковый транспорт; [gate] держит
/// открытие, чтобы тест видел состояние `connecting`.
final class _Resolver implements TransportResolver {
  Future<void>? gate;

  /// Если задано, открытие после [gate] падает этой ошибкой.
  Object? failWith;

  /// Id профилей, открытие которых падает (остальные открываются).
  final failIds = <String>{};

  @override
  bool supports(ConnectionProfile profile) => true;

  @override
  Future<AcpTransport> open(
    ConnectionProfile profile, {
    required String projectDirectory,
  }) async {
    await gate;
    if (failIds.contains(profile.id)) {
      throw StateError('agent ${profile.id} is unavailable');
    }
    if (failWith case final error?) {
      throw error;
    }
    return FakeAcpTransport();
  }
}

/// Команды подключения, которые запоминают вызовы.
final class _Commands implements ConnectionCommands {
  final connected = <ConnectionProfile>[];
  var reconnects = 0;

  /// Что делает «Restart agent» в workspace (по умолчанию ничего).
  Future<void> Function()? reconnectHook;

  /// Цель перезапуска: профиль последнего принятого подключения (MEDIUM-A).
  ConnectionProfile? target;
  final _targets = StreamController<ConnectionProfile?>.broadcast();

  /// Окно приняло подключение к [profile].
  void accept(ConnectionProfile profile) {
    target = profile;
    _targets.add(profile);
  }

  @override
  ConnectionProfile? get restartTarget => target;

  @override
  Stream<ConnectionProfile?> get restartTargets => _targets.stream;

  @override
  Future<void> connect(ConnectionProfile profile) async =>
      connected.add(profile);

  @override
  Future<void> reconnect() async {
    reconnects++;
    await reconnectHook?.call();
  }
}

/// Настройки, чтение id по умолчанию которых завершается по сигналу, но
/// значение берётся в момент вызова: моделирует `reload` в полёте, который
/// читает старый выбор (nit ревью: поздний reload не возвращает старое).
final class _GatedPreferences implements ConnectionPreferences {
  _GatedPreferences(this._inner);

  final ConnectionPreferences _inner;
  Completer<void>? gate;

  @override
  Future<String?> loadDefaultProfileId() async {
    final value = await _inner.loadDefaultProfileId();
    // Задерживается только первое чтение: повторное чтение после записи
    // проходит сразу.
    final pending = gate;
    gate = null;
    await pending?.future;
    return value;
  }

  @override
  Future<void> saveDefaultProfileId(String? id) =>
      _inner.saveDefaultProfileId(id);

  @override
  Future<bool> loadConnectOnStart() => _inner.loadConnectOnStart();

  @override
  Future<void> saveConnectOnStart(bool value) =>
      _inner.saveConnectOnStart(value);
}

const _titles = '''
{"version":1,"profiles":[
 {"type":"stdio","id":"py","label":"stdio:python -m \\"codelab agent\\" --stdio",
  "command":"python","args":["-m","codelab agent","--stdio"],"env":{},
  "runInProjectDirectory":true},
 {"type":"webSocket","id":"ws","label":"","uri":"ws://ws:1/acp"},
 {"type":"webSocket","id":"url","label":"wss://u:p@h:2/acp?t=1","uri":"wss://h:2/acp"},
 {"type":"stdio","id":"dev","label":"A very long label that does not fit the row title",
  "command":"codelab-agent","args":[],"env":{},"runInProjectDirectory":true}
]}
''';

const _file = '''
{"version":1,"profiles":[
 {"type":"stdio","id":"dev","label":"Dev","command":"codelab-agent",
  "args":["serve","--stdio","--secret-arg"],"env":{"K":"secret-env"},
  "runInProjectDirectory":true},
 {"type":"webSocket","id":"devbox","label":"Devbox",
  "uri":"wss://u:p@devbox:7420/acp?t=1","tokenRef":"env:DEVBOX_TOKEN"},
 {"type":"webSocket","id":"plain","label":"Plain","uri":"ws://plain:1/acp"},
 {"type":"webSocket","id":"named","label":"Named","uri":"ws://named:2/acp",
  "tokenRef":"codelab/ws-devbox"}
]}
''';

const _legacyDefault = '''
{"version":1,"profiles":[
 {"type":"stdio","id":"default","label":"Old","command":"/opt/secret-agent",
  "args":["--token","leak-arg"],"env":{"T":"leak-env"},
  "runInProjectDirectory":true},
 {"type":"stdio","id":"dev","label":"Dev","command":"codelab-agent",
  "args":[],"env":{},"runInProjectDirectory":false}
]}
''';

/// Хранилище поверх файла, у которого запись можно сломать (D14, D17).
final class _BreakableStore implements ProfileStore {
  _BreakableStore(this._inner);

  final ProfileStore _inner;
  bool failWrites = false;

  @override
  Future<List<ConnectionProfile>> load() => _inner.load();

  @override
  Future<void> save(ConnectionProfile profile) async {
    if (failWrites) {
      throw StateError('disk full sk-test-leak-0123456789');
    }
    await _inner.save(profile);
  }

  @override
  Future<bool> remove(String id) async {
    if (failWrites) {
      throw StateError('disk full sk-test-leak-0123456789');
    }
    return _inner.remove(id);
  }
}

void main() {
  late Directory home;
  late File profilesFile;
  late _Resolver resolver;
  late ClientWorkspace workspace;
  late _Commands commands;
  late RecordingLogger logger;
  late AcpClientApplication application;
  late FakeProfileSecrets secrets;

  ConnectionSettingsCubit build({
    Map<String, String> environment = const {},
    ProfileProbe? probe,
    ProfileStore? store,
  }) {
    final cubit = ConnectionSettingsCubit(
      store: store ?? JsonFileProfileStore(profilesFile.path),
      openSecrets: () async => secrets,
      preferences: const SharedPreferencesConnectionPreferences(),
      workspace: workspace,
      commands: commands,
      environment: environment,
      profilesPath: profilesFile.path,
      probe: probe ?? ProfileProbe(resolvers: [resolver]),
      projectDirectory: () => '/work',
      logger: logger,
    );
    addTearDown(cubit.close);
    return cubit;
  }

  /// Окно принимает подключение к [profile]: и workspace, и цель перезапуска.
  Future<void> connectedTo(ConnectionProfile profile) async {
    commands.accept(profile);
    await workspace.connect(profile, projectDirectory: '/work');
  }

  Future<ConnectionSettingsReady> ready(ConnectionSettingsCubit cubit) async {
    await cubit.reload();
    return cubit.state as ConnectionSettingsReady;
  }

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    home = await Directory.systemTemp.createTemp('codelab_settings_cubit_');
    profilesFile = File('${home.path}/profiles.json');
    resolver = _Resolver();
    application = AcpClientApplication(transport: FakeAcpTransport());
    workspace = ClientWorkspace(
      backend: AcpClientBackend(application),
      resolvers: [resolver],
    );
    commands = _Commands();
    logger = RecordingLogger();
    secrets = FakeProfileSecrets();
    addTearDown(() async {
      await workspace.dispose();
      await application.dispose();
      await home.delete(recursive: true);
    });
  });

  group('rows', () {
    test('the embedded agent goes first, then the file order; a missing '
        'file is just the embedded agent', () async {
      final cubit = build();
      expect(cubit.state, isA<ConnectionSettingsLoading>());

      final empty = await ready(cubit);
      expect([for (final row in empty.rows) row.id], ['embedded']);

      await profilesFile.writeAsString(_file);
      final state = await ready(cubit);

      expect(
        [for (final row in state.rows) row.id],
        ['embedded', 'dev', 'devbox', 'plain', 'named'],
      );
      expect(state.rows.first.isBuiltIn, isTrue);
      expect(state.rows.last.isBuiltIn, isFalse);
    });

    test('the row summary is the command or scheme://host:port, without '
        'arguments, env, userinfo, path and query', () async {
      await profilesFile.writeAsString(_file);

      final state = await ready(build());

      final summaries = {for (final r in state.rows) r.id: r.summary};
      expect(summaries['dev'], 'codelab-agent');
      expect(summaries['devbox'], 'wss://devbox:7420');
      for (final summary in summaries.values) {
        expect(summary, isNot(contains('secret')));
        expect(summary, isNot(contains('u:p')));
        expect(summary, isNot(contains('/acp')));
      }
    });
  });

  group('default profile', () {
    test('without a saved choice the embedded agent is the default '
        '(Q1, D5)', () async {
      await profilesFile.writeAsString(_file);

      final state = await ready(build());

      expect(state.defaultProfileId, 'embedded');
      expect(
        [
          for (final row in state.rows)
            if (row.isDefault) row.id,
        ],
        ['embedded'],
      );
    });

    test('a saved id selects that profile', () async {
      SharedPreferences.setMockInitialValues({_defaultKey: 'dev'});
      await profilesFile.writeAsString(_file);

      final state = await ready(build());

      expect(state.defaultProfileId, 'dev');
    });

    test('a saved id that is no longer in the file falls back to the '
        'embedded agent and the key is dropped', () async {
      SharedPreferences.setMockInitialValues({_defaultKey: 'gone'});
      await profilesFile.writeAsString(_file);

      final state = await ready(build());

      expect(state.defaultProfileId, 'embedded');
      expect(
        (await SharedPreferences.getInstance()).containsKey(_defaultKey),
        isFalse,
      );
    });

    test('selecting a default saves its id; selecting the embedded agent '
        'removes the key; both are logged with the profile id only', () async {
      await profilesFile.writeAsString(_file);
      final cubit = build();
      await cubit.reload();

      await cubit.selectDefault('dev');
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getString(_defaultKey), 'dev');
      expect((cubit.state as ConnectionSettingsReady).defaultProfileId, 'dev');

      await cubit.selectDefault('embedded');
      expect(prefs.containsKey(_defaultKey), isFalse);
      expect(
        (cubit.state as ConnectionSettingsReady).defaultProfileId,
        'embedded',
      );

      final events = logger.entries
          .where((e) => e['event'] == 'connection_profile.default_changed')
          .toList();
      expect([for (final e in events) e['profile_id']], ['dev', 'embedded']);
    });

    test('an unknown id cannot become the default', () async {
      await profilesFile.writeAsString(_file);
      final cubit = build();
      await cubit.reload();

      await cubit.selectDefault('nope');

      final prefs = await SharedPreferences.getInstance();
      expect(prefs.containsKey(_defaultKey), isFalse);
    });

    test('Connect passes the profile to the connection and does not touch '
        'the default (D5)', () async {
      await profilesFile.writeAsString(_file);
      final cubit = build();
      await cubit.reload();

      await cubit.connect('dev');

      expect(commands.connected.single.id, 'dev');
      expect(
        (cubit.state as ConnectionSettingsReady).defaultProfileId,
        'embedded',
      );
      expect(
        (await SharedPreferences.getInstance()).containsKey(_defaultKey),
        isFalse,
      );
    });
  });

  group('current connection', () {
    test('the profile of the window is marked Current by id', () async {
      await profilesFile.writeAsString(_file);
      final cubit = build();
      await cubit.reload();

      await connectedTo(
        (await JsonFileProfileStore(profilesFile.path).load()).first,
      );
      await pumpEventQueue();

      final state = cubit.state as ConnectionSettingsReady;
      expect(state.currentProfileId, 'dev');
      expect(
        [
          for (final row in state.rows)
            if (row.isCurrent) row.id,
        ],
        ['dev'],
      );
    });

    test('a current profile that is not in the file is shown as a separate '
        '"Current connection (not saved)" row', () async {
      await profilesFile.writeAsString(_file);
      final cubit = build();
      await cubit.reload();

      await connectedTo(
        const ConnectionProfile.stdio(
          id: 'adhoc',
          label: 'Ad hoc',
          command: 'x',
        ),
      );
      await pumpEventQueue();

      final state = cubit.state as ConnectionSettingsReady;
      final unsaved = state.rows.last;
      expect(unsaved.id, 'adhoc');
      expect(unsaved.isUnsaved, isTrue);
      expect(unsaved.isCurrent, isTrue);
      expect(unsaved.canRemove, isFalse);
      expect(state.rows.where((row) => row.isUnsaved), hasLength(1));
    });
  });

  group('token source in the row', () {
    test('No token / From env / not set / not supported', () async {
      await profilesFile.writeAsString(_file);

      final set = await ready(build(environment: {'DEVBOX_TOKEN': 'v'}));
      final unset = await ready(build());

      ProfileTokenView? token(ConnectionSettingsReady s, String id) =>
          s.rows.firstWhere((row) => row.id == id).token;
      expect(token(set, 'plain'), isA<NoTokenView>());
      expect(
        token(set, 'devbox'),
        const EnvTokenView('DEVBOX_TOKEN', isSet: true),
      );
      expect(
        token(unset, 'devbox'),
        const EnvTokenView('DEVBOX_TOKEN', isSet: false),
      );
      expect(token(set, 'named'), const UnsupportedTokenView());
      expect(token(set, 'dev'), isNull);
    });

    test('the token value never reaches the state or the log', () async {
      await profilesFile.writeAsString(_file);
      final cubit = build(environment: {'DEVBOX_TOKEN': 'sk-leak-0123456789'});

      await cubit.reload();

      expect(
        '${cubit.state.runtimeType}${logger.entries}',
        isNot(contains('sk-leak-0123456789')),
      );
      final state = cubit.state as ConnectionSettingsReady;
      expect(
        state.rows.map((row) => '${row.token}').join(),
        isNot(contains('sk-leak-0123456789')),
      );
    });

    test('an unsupported reference is logged once per profile without the '
        'reference', () async {
      await profilesFile.writeAsString(_file);
      final cubit = build();

      await cubit.reload();
      await cubit.reload();

      final events = logger.entries
          .where(
            (e) => e['event'] == 'connection_profile.token_ref_unsupported',
          )
          .toList();
      expect(events, hasLength(1));
      expect(events.single['profile_id'], 'named');
      expect('${logger.entries}', isNot(contains('codelab/ws-devbox')));
    });
  });

  group('unreadable profiles.json (data integrity)', () {
    const broken = '{"version": 2, "profiles": []}';

    test('version 2 is Unreadable, shows the embedded row and the file is '
        'not touched', () async {
      await profilesFile.writeAsString(broken);
      final cubit = build();

      await cubit.reload();

      final state = cubit.state as ConnectionSettingsUnreadable;
      expect([for (final row in state.rows) row.id], ['embedded']);
      expect(state.path, profilesFile.path);
      expect(state.reason, isNotEmpty);
      expect(await profilesFile.readAsString(), broken);
    });

    test(
      'the event carries only the error type, not the path or the text',
      () async {
        await profilesFile.writeAsString(broken);

        await build().reload();

        final event = logger.entries.singleWhere(
          (e) => e['event'] == 'connection_profile.unreadable',
        );
        expect(event['level'], 'warning');
        expect(event['error_type'], 'FormatException');
        expect('$event', isNot(contains(home.path)));
      },
    );

    test('Remove and removing the ignored default do nothing', () async {
      await profilesFile.writeAsString(broken);
      final cubit = build();
      await cubit.reload();

      expect(await cubit.removeProfile('dev'), isFalse);
      expect(await cubit.removeIgnoredDefault(), isFalse);

      expect(await profilesFile.readAsString(), broken);
    });

    test('a corrupt file (not JSON) is Unreadable too', () async {
      await profilesFile.writeAsString('{not json');
      final cubit = build();

      await cubit.reload();

      expect(cubit.state, isA<ConnectionSettingsUnreadable>());
      expect(await profilesFile.readAsString(), '{not json');
    });
  });

  group('Remove', () {
    test(
      'the built-in agent cannot be removed, also by a direct call',
      () async {
        await profilesFile.writeAsString(_file);
        final cubit = build();
        await cubit.reload();

        expect(await cubit.removeProfile('embedded'), isFalse);

        expect(await profilesFile.readAsString(), _file);
      },
    );

    test('the current profile cannot be removed, also by a direct call; '
        'the row is not removable ("Disconnect first")', () async {
      await profilesFile.writeAsString(_file);
      final cubit = build();
      await cubit.reload();
      await connectedTo(
        (await JsonFileProfileStore(profilesFile.path).load()).first,
      );
      await pumpEventQueue();

      final state = cubit.state as ConnectionSettingsReady;
      expect(state.rows.firstWhere((r) => r.id == 'dev').canRemove, isFalse);
      expect(await cubit.removeProfile('dev'), isFalse);

      expect(await profilesFile.readAsString(), _file);
    });

    test('another profile is removed from the file only; removing the '
        'default resets the choice to the embedded agent', () async {
      SharedPreferences.setMockInitialValues({_defaultKey: 'devbox'});
      await profilesFile.writeAsString(_file);
      final cubit = build();
      await cubit.reload();

      expect(await cubit.removeProfile('devbox'), isTrue);

      final stored = await JsonFileProfileStore(profilesFile.path).load();
      expect([for (final p in stored) p.id], ['dev', 'plain', 'named']);
      expect(
        (await SharedPreferences.getInstance()).containsKey(_defaultKey),
        isFalse,
      );
      final state = cubit.state as ConnectionSettingsReady;
      expect(state.defaultProfileId, 'embedded');
      expect(
        [for (final r in state.rows) r.id],
        ['embedded', 'dev', 'plain', 'named'],
      );
      expect(
        logger.entries.where((e) => e['event'] == 'connection_profile.removed'),
        [containsPair('profile_id', 'devbox')],
      );
    });
  });

  group('token secret in the row and Remove (1.7, D13, D14, D18)', () {
    const ownName = 'codelab/profiles/devbox/token';
    const leak = 'sk-test-leak-0123456789';
    const withSecrets = """
{"version":1,"profiles":[
 {"type":"webSocket","id":"devbox","label":"Devbox","uri":"wss://devbox:7420",
  "tokenRef":"secret:codelab/profiles/devbox/token"},
 {"type":"webSocket","id":"ci","label":"CI","uri":"wss://ci:7420",
  "tokenRef":"secret:codelab/ws-ci"}
]}
""";
    // `twin` ссылается на секрет `devbox`: общий секрет не удаляется.
    const withTwin = """
{"version":1,"profiles":[
 {"type":"webSocket","id":"devbox","label":"Devbox","uri":"wss://devbox:7420",
  "tokenRef":"secret:codelab/profiles/devbox/token"},
 {"type":"webSocket","id":"twin","label":"Twin","uri":"wss://twin:7420",
  "tokenRef":"secret:codelab/profiles/devbox/token"}
]}
""";

    SecretTokenView? token(ConnectionSettingsReady state, String id) =>
        state.rows.firstWhere((row) => row.id == id).token as SecretTokenView?;

    test('the row knows the name, the backend and whether the secret is '
        'set, without reading the value', () async {
      secrets = FakeProfileSecrets(values: {ownName: leak});
      await profilesFile.writeAsString(withSecrets);

      final state = await ready(build());

      expect(
        token(state, 'devbox'),
        const SecretTokenView(ownName, backend: 'file', isSet: true),
      );
      expect(
        token(state, 'ci'),
        const SecretTokenView('codelab/ws-ci', backend: 'file', isSet: false),
      );
      expect(secrets.calls.where((c) => c.startsWith('read:')), isEmpty);
      expect(
        state.rows.map((row) => '${row.token}').join(),
        isNot(contains(leak)),
      );
    });

    test('an unreadable store means "missing", not a failed page', () async {
      secrets = FakeProfileSecrets(values: {ownName: leak})
        ..isSetFailure = StateError(leak);
      await profilesFile.writeAsString(withSecrets);

      final state = await ready(build());

      expect(token(state, 'devbox')!.isSet, isFalse);
      expect(token(state, 'ci')!.isSet, isFalse);
      expect(logger.entries.toString(), isNot(contains(leak)));
    });

    test('only the secret named after the profile is deletable together '
        'with it', () async {
      await profilesFile.writeAsString(withTwin);

      final state = await ready(build());

      ConnectionProfileRow row(String id) =>
          state.rows.firstWhere((r) => r.id == id);
      expect(row('devbox').ownTokenSecret, ownName);
      // Профиль, ссылающийся на чужое имя `codelab/profiles/devbox/token`,
      // собственным секретом его не считает.
      expect(row('twin').ownTokenSecret, isNull);
    });

    test('Remove with the flag: the profile first, then the secret; both '
        'are logged with the profile id and the backend only', () async {
      secrets = FakeProfileSecrets(values: {ownName: leak});
      await profilesFile.writeAsString(withSecrets);
      final cubit = build();
      await cubit.reload();

      expect(
        await cubit.removeProfile('devbox', deleteOwnSecret: true),
        isTrue,
      );

      final stored = await JsonFileProfileStore(profilesFile.path).load();
      expect([for (final p in stored) p.id], ['ci']);
      expect(secrets.values, isEmpty);
      expect(
        logger.entries.where((e) => e['event'] == 'connection_profile.removed'),
        [containsPair('profile_id', 'devbox')],
      );
      expect(
        logger.entries.singleWhere(
          (e) => e['event'] == 'connection_profile.token_deleted',
        ),
        allOf(
          containsPair('profile_id', 'devbox'),
          containsPair('backend', 'file'),
        ),
      );
      expect(logger.entries.toString(), isNot(contains(leak)));
    });

    test('the page opens the store itself: Loading until it is open, a '
        'late open after close is dropped', () async {
      final gate = Completer<void>();
      await profilesFile.writeAsString(withSecrets);
      final cubit = ConnectionSettingsCubit(
        store: JsonFileProfileStore(profilesFile.path),
        openSecrets: () async {
          await gate.future;
          return secrets;
        },
        preferences: const SharedPreferencesConnectionPreferences(),
        workspace: workspace,
        commands: commands,
        environment: const {},
        profilesPath: profilesFile.path,
        probe: ProfileProbe(resolvers: [resolver]),
        projectDirectory: () => '/work',
        logger: logger,
      );
      final loading = cubit.reload();
      await pumpEventQueue();
      expect(cubit.state, isA<ConnectionSettingsLoading>());

      await cubit.close();
      gate.complete();
      await loading;

      expect(cubit.state, isA<ConnectionSettingsLoading>());
    });

    test('every opening of the page reopens the store', () async {
      await profilesFile.writeAsString(withSecrets);
      var opened = 0;
      ConnectionSettingsCubit page() {
        final cubit = ConnectionSettingsCubit(
          store: JsonFileProfileStore(profilesFile.path),
          openSecrets: () async {
            opened++;
            return secrets;
          },
          preferences: const SharedPreferencesConnectionPreferences(),
          workspace: workspace,
          commands: commands,
          environment: const {},
          profilesPath: profilesFile.path,
          probe: ProfileProbe(resolvers: [resolver]),
          projectDirectory: () => '/work',
          logger: logger,
        );
        addTearDown(cubit.close);
        return cubit;
      }

      final first = page();
      await first.reload();
      await first.reload();
      expect(opened, 1);
      await page().reload();
      expect(opened, 2);
    });

    test('Remove without the flag keeps the secret', () async {
      secrets = FakeProfileSecrets(values: {ownName: leak});
      await profilesFile.writeAsString(withSecrets);
      final cubit = build();
      await cubit.reload();

      expect(await cubit.removeProfile('devbox'), isTrue);

      expect(secrets.values, {ownName: leak});
      expect(
        logger.entries.where(
          (e) => e['event'] == 'connection_profile.token_deleted',
        ),
        isEmpty,
      );
    });

    test('a foreign secret is not deleted even with the flag', () async {
      secrets = FakeProfileSecrets(values: {'codelab/ws-ci': leak});
      await profilesFile.writeAsString(withSecrets);
      final cubit = build();
      await cubit.reload();

      expect(await cubit.removeProfile('ci', deleteOwnSecret: true), isTrue);

      expect(secrets.values, {'codelab/ws-ci': leak});
      expect(secrets.calls.where((c) => c.startsWith('delete:')), isEmpty);
    });

    test('a secret another profile still points at is not deleted', () async {
      secrets = FakeProfileSecrets(values: {ownName: leak});
      await profilesFile.writeAsString(withTwin);
      final cubit = build();
      await cubit.reload();

      await cubit.removeProfile('devbox', deleteOwnSecret: true);

      expect(secrets.values, {ownName: leak});
    });

    test('a refused secret deletion does not bring the profile back; the '
        'page says how to remove it', () async {
      secrets = FakeProfileSecrets(values: {ownName: leak})
        ..nextDelete = const Failed('cannot delete');
      await profilesFile.writeAsString(withSecrets);
      final cubit = build();
      await cubit.reload();

      expect(
        await cubit.removeProfile('devbox', deleteOwnSecret: true),
        isTrue,
      );

      final stored = await JsonFileProfileStore(profilesFile.path).load();
      expect(stored.any((p) => p.id == 'devbox'), isFalse);
      expect(
        (cubit.state as ConnectionSettingsReady).failure,
        'The profile was removed, but the stored token $ownName was not '
        'deleted. Remove it with codelab secret delete $ownName.',
      );
      expect(
        logger.entries.singleWhere(
          (e) => e['event'] == 'connection_profile.token_delete_failed',
        ),
        allOf(
          containsPair('profile_id', 'devbox'),
          containsPair('backend', 'file'),
        ),
      );
      expect(logger.entries.toString(), isNot(contains(leak)));
    });

    test('a failed profile write leaves the secret alone (SETUP-24)', () async {
      secrets = FakeProfileSecrets(values: {ownName: leak});
      await profilesFile.writeAsString(withSecrets);
      final store = _BreakableStore(JsonFileProfileStore(profilesFile.path))
        ..failWrites = true;
      final cubit = build(store: store);
      await cubit.reload();

      expect(
        await cubit.removeProfile('devbox', deleteOwnSecret: true),
        isFalse,
      );

      expect(secrets.values, {ownName: leak});
      expect(
        logger.entries.where((e) => e['event'] == 'connection_profile.removed'),
        isEmpty,
      );
      expect(logger.entries.toString(), isNot(contains(leak)));
    });
  });

  group('legacy "default" entry (D5, D21, task 2.15)', () {
    test('the entry is not a row, the flag is set, the file is unchanged '
        'and the log has only the fact', () async {
      await profilesFile.writeAsString(_legacyDefault);
      final cubit = build();

      final state = await ready(cubit);

      expect([for (final row in state.rows) row.id], ['embedded', 'dev']);
      expect(state.ignoredDefaultEntry, isTrue);
      expect(await profilesFile.readAsString(), _legacyDefault);
      final event = logger.entries.singleWhere(
        (e) => e['event'] == 'connection_profile.default_ignored',
      );
      expect(event['level'], 'warning');
      expect(event.keys.toSet(), {'event', 'level'});
      expect('${logger.entries}', isNot(contains('secret-agent')));
      expect('${logger.entries}', isNot(contains('leak')));
    });

    test('the state never exposes the command, arguments or env of the '
        'entry', () async {
      await profilesFile.writeAsString(_legacyDefault);

      final state = await ready(build());

      final text = state.rows
          .map((r) => '${r.id}${r.label}${r.summary}')
          .join();
      expect(text, isNot(contains('secret-agent')));
      expect(text, isNot(contains('leak')));
    });

    test('a saved default id "default" is not used: the embedded agent '
        'is the default', () async {
      SharedPreferences.setMockInitialValues({_defaultKey: 'default'});
      await profilesFile.writeAsString(_legacyDefault);

      final state = await ready(build());

      expect(state.defaultProfileId, 'embedded');
    });

    test('removeIgnoredDefault deletes only that entry and clears the '
        'flag', () async {
      await profilesFile.writeAsString(_legacyDefault);
      final cubit = build();
      await cubit.reload();

      expect(await cubit.removeIgnoredDefault(), isTrue);

      final stored = await JsonFileProfileStore(profilesFile.path).load();
      expect([for (final p in stored) p.id], ['dev']);
      expect(
        (cubit.state as ConnectionSettingsReady).ignoredDefaultEntry,
        isFalse,
      );
      expect(
        logger.entries.where(
          (e) => e['event'] == 'connection_profile.default_removed',
        ),
        hasLength(1),
      );
    });

    test('no flag without the entry', () async {
      await profilesFile.writeAsString(_file);

      final state = await ready(build());

      expect(state.ignoredDefaultEntry, isFalse);
    });
  });

  group('Behavior', () {
    test('Connect on start is off by default and persists a change', () async {
      await profilesFile.writeAsString(_file);
      final cubit = build();

      expect((await ready(cubit)).connectOnStart, isFalse);
      await cubit.setConnectOnStart(true);

      expect((cubit.state as ConnectionSettingsReady).connectOnStart, isTrue);
      expect(
        (await SharedPreferences.getInstance()).getBool(_connectOnStartKey),
        isTrue,
      );
    });

    test('Restart agent reconnects with the current profile', () async {
      await profilesFile.writeAsString(_file);
      final cubit = build();
      await cubit.reload();
      await connectedTo(
        (await JsonFileProfileStore(profilesFile.path).load()).first,
      );
      await pumpEventQueue();

      expect((cubit.state as ConnectionSettingsReady).canRestart, isTrue);
      await cubit.restartAgent();

      expect(commands.reconnects, 1);
    });

    test('Restart agent is unavailable without a profile and does nothing '
        'when called directly', () async {
      await profilesFile.writeAsString(_file);
      final cubit = build();
      await cubit.reload();

      expect((cubit.state as ConnectionSettingsReady).canRestart, isFalse);
      await cubit.restartAgent();

      expect(commands.reconnects, 0);
    });

    test('Restart agent is unavailable while connecting', () async {
      await profilesFile.writeAsString(_file);
      final cubit = build();
      await cubit.reload();
      final open = Completer<void>();
      resolver.gate = open.future;
      final profile = (await JsonFileProfileStore(
        profilesFile.path,
      ).load()).first;
      commands.accept(profile);
      final connecting = workspace.connect(profile, projectDirectory: '/work');
      await pumpEventQueue();

      final state = cubit.state as ConnectionSettingsReady;
      expect(state.restartTarget?.id, 'dev');
      expect(state.canRestart, isFalse);
      await cubit.restartAgent();
      expect(commands.reconnects, 0);

      open.complete();
      await connecting;
    });
  });

  group('row title and status badge (manual run, D4)', () {
    test('the title is the label, or the id for an empty label and for a '
        'label made from --agent (stdio:, ws://, wss://)', () async {
      await profilesFile.writeAsString(_titles);

      final state = await ready(build());

      final titles = {for (final r in state.rows) r.id: r.title};
      expect(titles['py'], 'py');
      expect(titles['ws'], 'ws');
      expect(titles['url'], 'url');
      expect(
        titles['dev'],
        'A very long label that does not fit the row title',
      );
      expect(state.rows.firstWhere((r) => r.id == 'py').summary, 'python');
    });

    test('only the current row has the status; it follows Connecting then '
        'Failed, without the error text', () async {
      await profilesFile.writeAsString(_file);
      final cubit = build();
      await cubit.reload();
      final open = Completer<void>();
      resolver
        ..gate = open.future
        ..failWith = StateError('boom: sk-test-leak-0123456789');
      final dev = (await JsonFileProfileStore(profilesFile.path).load()).first;
      commands.accept(dev);

      final connecting = workspace
          .connect(dev, projectDirectory: '/work')
          .then<void>((_) {}, onError: (Object _) {});
      await pumpEventQueue();
      ConnectionRowStatus? status(String id) =>
          (cubit.state as ConnectionSettingsReady).rows
              .firstWhere((r) => r.id == id)
              .status;
      expect(status('dev'), ConnectionRowStatus.connecting);
      expect(status('devbox'), isNull);
      expect(status('embedded'), isNull);

      open.complete();
      await connecting;
      await pumpEventQueue();

      expect(status('dev'), ConnectionRowStatus.failed);
      expect('${cubit.state.runtimeType}', isNot(contains('leak')));
    });
  });

  group('Behavior in Unreadable (D4)', () {
    const broken = '{"version": 2, "profiles": []}';

    test('Connect on start is shown and persists while the file is '
        'unreadable', () async {
      await profilesFile.writeAsString(broken);
      final cubit = build();
      await cubit.reload();

      await cubit.setConnectOnStart(true);

      final state = cubit.state as ConnectionSettingsUnreadable;
      expect(state.connectOnStart, isTrue);
      expect(
        (await SharedPreferences.getInstance()).getBool(_connectOnStartKey),
        isTrue,
      );
      expect(await profilesFile.readAsString(), broken);
    });

    test('Restart agent works for the current profile of the window', () async {
      await profilesFile.writeAsString(broken);
      final cubit = build();
      await cubit.reload();
      await connectedTo(embeddedConnectionProfile);
      await pumpEventQueue();

      expect((cubit.state as ConnectionSettingsUnreadable).canRestart, isTrue);
      await cubit.restartAgent();

      expect(commands.reconnects, 1);
    });
  });

  group('state getters instead of logic in build() (§15)', () {
    test(
      'remote origin, read-only notice and Restart/Reconnect wording',
      () async {
        await profilesFile.writeAsString(_file);
        final cubit = build();
        await cubit.reload();
        var state = cubit.state as ConnectionSettingsReady;
        expect(state.restartTitle, 'Restart agent');
        expect(state.restartButtonLabel, 'Restart');
        expect(state.showsReadOnlyNotice, isFalse);

        await connectedTo(
          (await JsonFileProfileStore(profilesFile.path).load())[1],
        );
        await pumpEventQueue();

        state = cubit.state as ConnectionSettingsReady;
        expect(state.isRemote, isTrue);
        expect(state.remoteOrigin, 'wss://devbox:7420');
        expect(state.showsReadOnlyNotice, isTrue);
        expect(state.restartTitle, 'Reconnect');
        expect(state.restartButtonLabel, 'Reconnect');
      },
    );

    test('the file actions and the "Not tested" badge belong to saved rows '
        'only', () async {
      await profilesFile.writeAsString(_file);

      final state = await ready(build());

      final embedded = state.rows.first;
      final dev = state.rows.firstWhere((r) => r.id == 'dev');
      expect(embedded.hasFileActions, isFalse);
      expect(embedded.showNotTested, isFalse);
      expect(dev.hasFileActions, isTrue);
      expect(dev.showNotTested, isTrue);
    });
  });

  group('a late reload and the nits of the review', () {
    test('a reload in flight does not bring back the old default after '
        'selectDefault', () async {
      await profilesFile.writeAsString(_file);
      final preferences = _GatedPreferences(
        const SharedPreferencesConnectionPreferences(),
      );
      final cubit = ConnectionSettingsCubit(
        store: JsonFileProfileStore(profilesFile.path),
        openSecrets: () async => secrets,
        preferences: preferences,
        workspace: workspace,
        commands: commands,
        environment: const {},
        profilesPath: profilesFile.path,
        probe: ProfileProbe(resolvers: [resolver]),
        projectDirectory: () => '/work',
        logger: logger,
      );
      addTearDown(cubit.close);
      await cubit.reload();

      final gate = preferences.gate = Completer<void>();
      final late = cubit.reload();
      await pumpEventQueue();
      await cubit.selectDefault('dev');
      gate.complete();
      await late;

      expect((cubit.state as ConnectionSettingsReady).defaultProfileId, 'dev');
    });

    test(
      'default_ignored is written once per page, not on every reload',
      () async {
        await profilesFile.writeAsString(_legacyDefault);
        final cubit = build();

        await cubit.reload();
        await cubit.reload();

        expect(
          logger.entries.where(
            (e) => e['event'] == 'connection_profile.default_ignored',
          ),
          hasLength(1),
        );
      },
    );
  });

  group('one source of the restart target (MEDIUM-A)', () {
    test(
      'embedded connected, Connect to dev failed: nobody is Current, the '
      'badge is on the failed attempt, and Restart makes the embedded '
      'agent Current and Connected again (user decision 2026-11-05)',
      () async {
        await profilesFile.writeAsString(_file);
        final cubit = build();
        await cubit.reload();
        await connectedTo(embeddedConnectionProfile);
        await pumpEventQueue();
        // Встроенный агент «Current» в `Connected` — без «Connect» (spec
        // app-settings: правило касается и его), у остальных он есть.
        final live = cubit.state as ConnectionSettingsReady;
        expect(
          live.rows.firstWhere((r) => r.id == 'embedded').canConnect,
          isFalse,
        );
        expect(live.rows.firstWhere((r) => r.id == 'dev').canConnect, isTrue);
        resolver.failIds.add('dev');
        final dev = (await JsonFileProfileStore(
          profilesFile.path,
        ).load()).first;
        await workspace
            .connect(dev, projectDirectory: '/work')
            .then<void>((_) {}, onError: (Object _) {});
        await pumpEventQueue();

        var state = cubit.state as ConnectionSettingsReady;
        ConnectionProfileRow row(String id) =>
            state.rows.firstWhere((r) => r.id == id);
        expect(state.rows.where((r) => r.isCurrent), isEmpty);
        // Current нет ни у кого: «Connect» есть во всех строках.
        expect(state.rows.every((r) => r.canConnect), isTrue);
        expect(row('embedded').status, isNull);
        expect(row('dev').status, ConnectionRowStatus.failed);
        expect(state.currentProfileId, isNull);
        // Цель перезапуска — по-прежнему встроенный агент.
        expect(state.restartTarget?.id, 'embedded');
        expect(state.restartTitle, 'Restart agent');
        expect(
          state.restartDescription,
          startsWith('Reconnects Embedded agent'),
        );
        expect(state.canRestart, isTrue);
        expect(state.showsReadOnlyNotice, isFalse);

        commands.reconnectHook = () => workspace.reconnect(
          profile: embeddedConnectionProfile,
          projectDirectory: '/work',
        );
        await cubit.restartAgent();
        await pumpEventQueue();

        state = cubit.state as ConnectionSettingsReady;
        expect(commands.reconnects, 1);
        expect(row('embedded').isCurrent, isTrue);
        expect(row('embedded').status, ConnectionRowStatus.connected);
        expect(row('dev').status, isNull);
      },
    );

    test('the first connect: the attempt shows Connecting then Failed on '
        'its row, and nobody is Current', () async {
      await profilesFile.writeAsString(_file);
      final cubit = build();
      await cubit.reload();
      final open = Completer<void>();
      resolver
        ..gate = open.future
        ..failIds.add('dev');
      final dev = (await JsonFileProfileStore(profilesFile.path).load()).first;
      commands.target = dev; // выбран, но не принят
      final connecting = workspace
          .connect(dev, projectDirectory: '/work')
          .then<void>((_) {}, onError: (Object _) {});
      await pumpEventQueue();

      var state = cubit.state as ConnectionSettingsReady;
      expect(
        state.rows.firstWhere((r) => r.id == 'dev').status,
        ConnectionRowStatus.connecting,
      );
      expect(state.rows.where((r) => r.isCurrent), isEmpty);
      // `Connecting…`: «Connect» во всех строках, и у строки попытки тоже.
      expect(state.rows.every((r) => r.canConnect), isTrue);

      open.complete();
      await connecting;
      await pumpEventQueue();

      state = cubit.state as ConnectionSettingsReady;
      expect(
        state.rows.firstWhere((r) => r.id == 'dev').status,
        ConnectionRowStatus.failed,
      );
      expect(state.rows.where((r) => r.isCurrent), isEmpty);
      expect(state.restartTarget?.id, 'dev');
    });

    test('Connect refused before the workspace is reached leaves the live '
        'profile Current without Connect and the other one with it', () async {
      await profilesFile.writeAsString(_file);
      final cubit = build();
      await cubit.reload();
      final dev = (await JsonFileProfileStore(profilesFile.path).load()).first;
      await connectedTo(dev);
      await pumpEventQueue();

      // `_Commands.connect` не трогает workspace — как отказ `ConnectionCubit`
      // до обращения к нему (D5): состояние окна не меняется.
      await cubit.connect('devbox');
      await pumpEventQueue();

      final state = cubit.state as ConnectionSettingsReady;
      ConnectionProfileRow row(String id) =>
          state.rows.firstWhere((r) => r.id == id);
      expect(commands.connected.map((p) => p.id), ['devbox']);
      expect(row('dev').isCurrent, isTrue);
      expect(row('dev').canConnect, isFalse);
      expect(row('devbox').canConnect, isTrue);
    });

    test('Connect is hidden while Reconnecting (the connection is accepted) '
        'and shown after Failed', () async {
      await profilesFile.writeAsString(_file);
      final cubit = build();
      await cubit.reload();
      final dev = (await JsonFileProfileStore(profilesFile.path).load()).first;
      await connectedTo(dev);
      await pumpEventQueue();

      var state = cubit.state as ConnectionSettingsReady;
      ConnectionProfileRow row(String id) =>
          state.rows.firstWhere((r) => r.id == id);
      expect(row('dev').isCurrent, isTrue);
      expect(row('dev').canConnect, isFalse);

      // Переподключение держим на открытии транспорта: `Reconnecting`.
      final open = Completer<void>();
      resolver.gate = open.future;
      final reconnecting = workspace.reconnect().then<void>(
        (_) {},
        onError: (Object _) {},
      );
      await pumpEventQueue();

      state = cubit.state as ConnectionSettingsReady;
      expect(workspace.current.connection, isA<Reconnecting>());
      expect(row('dev').isCurrent, isTrue);
      expect(row('dev').canConnect, isFalse);
      expect(row('plain').canConnect, isTrue);

      // Неудачное переподключение: «Current» нет, «Connect» возвращается.
      resolver.failIds.add('dev');
      open.complete();
      await reconnecting;
      await pumpEventQueue();

      state = cubit.state as ConnectionSettingsReady;
      expect(row('dev').isCurrent, isFalse);
      expect(row('dev').status, ConnectionRowStatus.failed);
      expect(row('dev').canConnect, isTrue);
    });

    test('a new accepted connection moves Current', () async {
      await profilesFile.writeAsString(_file);
      final cubit = build();
      await cubit.reload();
      await connectedTo(embeddedConnectionProfile);
      await pumpEventQueue();

      await connectedTo(
        (await JsonFileProfileStore(profilesFile.path).load()).first,
      );
      await pumpEventQueue();

      expect((cubit.state as ConnectionSettingsReady).currentProfileId, 'dev');
    });
  });

  group('re-reading after a write (nit)', () {
    test('setConnectOnStart re-reads, so a late reload cannot bring the old '
        'value back', () async {
      await profilesFile.writeAsString(_file);
      final cubit = build();
      await cubit.reload();

      await cubit.setConnectOnStart(true);
      await cubit.reload();

      expect((cubit.state as ConnectionSettingsReady).connectOnStart, isTrue);
    });
  });

  group('Rename (iteration 3)', () {
    test('changes only the label of the stored profile; id, command, '
        'arguments and env stay; the event has no label', () async {
      await profilesFile.writeAsString(_file);
      final cubit = build();
      await cubit.reload();

      final renamed = await cubit.renameProfile('dev', '  Build box  ');

      expect(renamed, isTrue);
      final saved = await JsonFileProfileStore(profilesFile.path).load();
      final dev = saved.first as StdioProfile;
      expect(dev.id, 'dev');
      expect(dev.label, 'Build box');
      expect(dev.command, 'codelab-agent');
      expect(dev.args, ['serve', '--stdio', '--secret-arg']);
      expect(dev.env, {'K': 'secret-env'});
      expect(saved.map((p) => p.id), ['dev', 'devbox', 'plain', 'named']);
      final state = cubit.state as ConnectionSettingsReady;
      expect(state.rows.firstWhere((r) => r.id == 'dev').title, 'Build box');
      final event = logger.entries.singleWhere(
        (e) => e['event'] == 'connection_profile.renamed',
      );
      expect(event['profile_id'], 'dev');
      expect(logger.entries.toString(), isNot(contains('Build box')));
    });

    test('uses the file as it is now, not the copy the page loaded: a '
        'field changed by the CLI is not lost', () async {
      await profilesFile.writeAsString(_file);
      final cubit = build();
      await cubit.reload();
      final store = JsonFileProfileStore(profilesFile.path);
      await store.save(
        const ConnectionProfile.stdio(
          id: 'dev',
          label: 'Dev',
          command: 'changed-by-cli',
        ),
      );

      await cubit.renameProfile('dev', 'Renamed');

      final dev = (await store.load()).first as StdioProfile;
      expect(dev.command, 'changed-by-cli');
      expect(dev.label, 'Renamed');
    });

    test('is refused for the built-in agent, an unknown id, an empty name '
        'and an unreadable file', () async {
      await profilesFile.writeAsString(_file);
      final cubit = build();
      await cubit.reload();

      expect(await cubit.renameProfile('embedded', 'X'), isFalse);
      expect(await cubit.renameProfile('nope', 'X'), isFalse);
      expect(await cubit.renameProfile('dev', '   '), isFalse);
      expect(
        (await JsonFileProfileStore(profilesFile.path).load()).first.label,
        'Dev',
      );

      await profilesFile.writeAsString('{ not json');
      await cubit.reload();
      expect(cubit.state, isA<ConnectionSettingsUnreadable>());
      expect(await cubit.renameProfile('dev', 'X'), isFalse);
      expect(await profilesFile.readAsString(), '{ not json');
    });
  });

  group('connection_profile.save_failed has stage profile (D14, D17)', () {
    test('Rename and Remove: a write failure logs stage profile and the '
        'type only', () async {
      await profilesFile.writeAsString(_file);
      final store = _BreakableStore(JsonFileProfileStore(profilesFile.path));
      final cubit = build(store: store);
      await cubit.reload();
      store.failWrites = true;

      expect(await cubit.renameProfile('dev', 'Renamed'), isFalse);
      expect(await cubit.removeProfile('plain'), isFalse);

      final events = logger.entries
          .where((e) => e['event'] == 'connection_profile.save_failed')
          .toList();
      expect(events, hasLength(2));
      for (final event in events) {
        expect(event['level'], 'warning');
        expect(event['stage'], 'profile');
        expect(event['error_type'], 'StateError');
      }
      expect(logger.entries.toString(), isNot(contains('sk-test-leak')));
    });
  });

  group('Test connection of a row (iteration 3, D14)', () {
    ProfileProbe probeOver(AcpTransport Function() next) => ProfileProbe(
      resolvers: [
        ConfigTransportResolver(stdio: (_) => next(), webSocket: (_) => next()),
      ],
    );

    test('records the outcome by id for the life of the page and the row '
        'stops being "Not tested"', () async {
      await profilesFile.writeAsString(_file);
      final cubit = build(probe: probeOver(FakeAcpTransport.new));
      var state = await ready(cubit);
      expect(state.lastProbes, isEmpty);
      expect(state.rows.firstWhere((r) => r.id == 'dev').showNotTested, isTrue);

      await cubit.testProfile('dev');

      state = cubit.state as ConnectionSettingsReady;
      expect(state.lastProbes['dev'], isA<Reachable>());
      final dev = state.rows.firstWhere((r) => r.id == 'dev');
      expect(dev.probe, isA<Reachable>());
      expect(dev.showNotTested, isFalse);
      expect(dev.isProbing, isFalse);
      final started = logger.entries.singleWhere(
        (e) => e['event'] == 'connection_profile.probe_started',
      );
      expect(started['profile_id'], 'dev');
      expect(started['type'], 'stdio');
      final finished = logger.entries.singleWhere(
        (e) => e['event'] == 'connection_profile.probe_finished',
      );
      expect(finished['operation_id'], started['operation_id']);
      // Все события проверки несут profile_id (D17).
      expect(finished['profile_id'], 'dev');
    });

    test('is refused for the built-in agent and unknown ids', () async {
      await profilesFile.writeAsString(_file);
      final cubit = build(probe: probeOver(FakeAcpTransport.new));
      await cubit.reload();

      await cubit.testProfile('embedded');
      await cubit.testProfile('nope');

      expect((cubit.state as ConnectionSettingsReady).lastProbes, isEmpty);
      expect(
        logger.entries.where(
          (e) => e['event'] == 'connection_profile.probe_started',
        ),
        isEmpty,
      );
    });

    test('closing the page cancels the probe: the transport is closed and '
        'the outcome is discarded', () async {
      await profilesFile.writeAsString(_file);
      final transports = <FakeAcpTransport>[];
      final cubit = build(
        probe: probeOver(() {
          final transport = FakeAcpTransport()..autoRespondToInitialize = false;
          transports.add(transport);
          return transport;
        }),
      );
      await cubit.reload();
      unawaited(cubit.testProfile('dev'));
      await pumpEventQueue();
      expect(
        (cubit.state as ConnectionSettingsReady).rows
            .firstWhere((r) => r.id == 'dev')
            .isProbing,
        isTrue,
      );

      await cubit.close();
      await pumpEventQueue();

      expect(transports.single.state, AcpTransportState.closed);
      expect(
        logger.entries.where(
          (e) => e['event'] == 'connection_profile.probe_discarded',
        ),
        hasLength(1),
      );
      expect(
        logger.entries.singleWhere(
          (e) => e['event'] == 'connection_profile.probe_discarded',
        )['profile_id'],
        'dev',
      );
    });

    test('the outcome is dropped when a reload finds the profile changed '
        '(another URL, command or token); an unchanged one keeps it', () async {
      await profilesFile.writeAsString(_file);
      final cubit = build(probe: probeOver(FakeAcpTransport.new));
      await cubit.reload();
      await cubit.testProfile('dev');
      await cubit.testProfile('plain');
      expect(
        (cubit.state as ConnectionSettingsReady).lastProbes.keys,
        containsAll(['dev', 'plain']),
      );

      // CLI переписал команду dev и адрес plain; остальное осталось.
      await profilesFile.writeAsString(
        _file
            .replaceFirst('"command":"codelab-agent"', '"command":"other"')
            .replaceFirst('ws://plain:1/acp', 'ws://plain:9/acp'),
      );
      final state = await ready(cubit);

      expect(state.lastProbes, isEmpty);
      expect(state.rows.firstWhere((r) => r.id == 'dev').showNotTested, isTrue);

      // Профиль без правок исход сохраняет.
      await cubit.testProfile('devbox');
      await cubit.reload();
      expect((cubit.state as ConnectionSettingsReady).lastProbes.keys, [
        'devbox',
      ]);
    });

    test('Rename keeps the outcome; a changed URL drops it (N1)', () async {
      await profilesFile.writeAsString(_file);
      final cubit = build(probe: probeOver(FakeAcpTransport.new));
      await cubit.reload();
      await cubit.testProfile('plain');

      expect(await cubit.renameProfile('plain', 'Renamed'), isTrue);
      expect(
        (cubit.state as ConnectionSettingsReady).lastProbes['plain'],
        isA<Reachable>(),
      );

      await profilesFile.writeAsString(
        (await profilesFile.readAsString()).replaceFirst(
          'ws://plain:1/acp',
          'ws://plain:9/acp',
        ),
      );
      await cubit.reload();
      expect(
        (cubit.state as ConnectionSettingsReady).lastProbes,
        isNot(contains('plain')),
      );
    });

    test('an outcome of a profile changed during the probe is discarded '
        '(safety)', () async {
      await profilesFile.writeAsString(_file);
      final cubit = build();
      await cubit.reload();
      final gate = Completer<void>();
      resolver.gate = gate.future;
      final pending = cubit.testProfile('plain');
      await pumpEventQueue();

      // За время проверки CLI сменил адрес, страница перечитала файл.
      await profilesFile.writeAsString(
        (await profilesFile.readAsString()).replaceFirst(
          'ws://plain:1/acp',
          'ws://plain:9/acp',
        ),
      );
      await cubit.reload();
      gate.complete();
      await pending;

      expect(
        (cubit.state as ConnectionSettingsReady).lastProbes,
        isNot(contains('plain')),
      );
      expect(
        logger.entries.where(
          (e) =>
              e['event'] == 'connection_profile.probe_discarded' &&
              e['profile_id'] == 'plain',
        ),
        hasLength(1),
      );
    });

    test(
      'profileAdded stores the outcome of the dialog under the new id',
      () async {
        await profilesFile.writeAsString(_file);
        final cubit = build();
        await cubit.reload();

        await cubit.profileAdded(
          'dev',
          const Reachable(latency: Duration(milliseconds: 5)),
        );

        final state = cubit.state as ConnectionSettingsReady;
        expect(state.lastProbes['dev'], isA<Reachable>());
      },
    );
  });
}
