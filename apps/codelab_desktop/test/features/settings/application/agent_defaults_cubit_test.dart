// `AgentDefaultsCubit` (задача 2.3 change `add-app-general-page`; spec
// app-settings «Умолчания агента на странице «General»: доступ и строки»,
// «…запись», «События журнала страницы «General»»; design.md D2, D4, D5, D7,
// D16).
//
// Красные тесты: Cubit — заглушка итерации 2, логика появится в задаче 2.4.
//
// Конфиг читает и пишет НАСТОЯЩЕЕ хранилище во временной папке
// (`ModesFixture`, образец — `agents_modes_cubit_test.dart`): итог значения,
// источник слоя, перекрытие проектным файлом, `restartRequiredKeys` и отказ
// писателя (`budget.max_cost` строго больше нуля) дают загрузчик и писатель
// ядра, а app не строит `CoreConfig` сам. Обёртка `ControlledConfigStore`
// удерживает снимок и запись и подменяет исход. Агенту Cubit ничего не
// отправляет: у `FakeWorkspace` любой вызов сессии бросает
// `UnimplementedError`.

import 'dart:async';
import 'dart:io';

import 'package:codelab_client_core/codelab_client_core.dart';
import 'package:codelab_desktop/features/settings/application/agent_defaults_cubit.dart';
import 'package:codelab_desktop/features/settings/application/embedded_profile.dart';
import 'package:codelab_setup/codelab_setup.dart';
import 'package:flutter_test/flutter_test.dart';

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

const _connected = ConnectionView.connected();

/// Ограничение ожидания: красный тест на заглушке падает быстро, а не по
/// таймауту теста.
const _wait = Duration(seconds: 2);

void main() {
  late FakeWorkspace workspace;
  late RecordingLogger logger;
  late List<AgentDefaultsCubit> cubits;
  late List<ModesFixture> fixtures;
  late List<EditableSettings> opened;
  String? Function() projectDir = () => null;

  Future<ModesFixture> fixture({
    String userYaml = '',
    bool trusted = true,
    String? localYaml,
  }) async {
    final fx = await ModesFixture.open(
      userYaml: userYaml,
      trusted: trusted,
      localYaml: localYaml,
    );
    fixtures.add(fx);
    projectDir = () => fx.project;
    return fx;
  }

  AgentDefaultsCubit make(ModesFixture fx) {
    final cubit = AgentDefaultsCubit(
      workspace: workspace,
      defaultProfile: () async => embeddedConnectionProfile,
      open: (access, env) async {
        opened.add(access);
        return ModesSession(fx.store);
      },
      environment: {'HOME': fx.home},
      codelabHome: fx.home,
      projectDirectory: () => projectDir(),
      logger: logger,
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

  AgentDefaultsReady now(AgentDefaultsCubit cubit) {
    expect(cubit.state, isA<AgentDefaultsReady>());
    return cubit.state as AgentDefaultsReady;
  }

  Future<AgentDefaultsReady> ready(AgentDefaultsCubit cubit) async {
    await cubit.reload();
    return now(cubit);
  }

  /// Строка ключа [key] готового состояния.
  AgentDefaultsRow row(AgentDefaultsCubit cubit, String key) {
    final rows = [
      for (final group in now(cubit).groups) ...group.rows,
    ].where((r) => r.field.key == key);
    expect(rows, hasLength(1), reason: 'строка $key');
    return rows.single;
  }

  Set<String> keys(AgentDefaultsReady state) => {
    for (final group in state.groups)
      for (final r in group.rows) r.field.key,
  };

  /// Ждёт состояние [test] без опроса по таймеру: подписка до причины.
  Future<AgentDefaultsState> until(
    AgentDefaultsCubit cubit,
    bool Function(AgentDefaultsState state) test,
  ) => cubit.stream
      .firstWhere(test)
      .timeout(_wait, onTimeout: () => fail('состояние не наступило'));

  Future<void> arrive(Completer<void> reached) => reached.future.timeout(
    _wait,
    onTimeout: () => fail('вызов хранилища не начался'),
  );

  Iterable<Map<String, Object?>> events(String name) =>
      logger.entries.where((e) => e['event'] == name);

  /// Удерживает снимок номер [call] до `gate`; `reached` — вызов начался.
  ({Completer<void> reached, Completer<void> gate}) holdSnapshot(
    ModesFixture fx,
    int call,
  ) {
    final reached = Completer<void>();
    final gate = Completer<void>();
    fx.store.onSnapshot = (n) {
      if (n != call) {
        return null;
      }
      reached.complete();
      return gate.future;
    };
    return (reached: reached, gate: gate);
  }

  group('Loading → Ready: строки из своего подмножества (D2)', () {
    test('starts in Loading', () async {
      final fx = await fixture();
      final cubit = make(fx);

      expect(cubit.state, isA<AgentDefaultsLoading>());
    });

    test('shows the rows of the general keys with their sources; the keys of '
        'other pages are absent', () async {
      final fx = await fixture(
        userYaml: 'budget:\n  max_steps: 80\npermissions:\n  mode: ask\n',
      );
      final cubit = make(fx);

      final state = await ready(cubit);

      final steps = row(cubit, 'budget.max_steps').field;
      expect(steps.displayValue, '80');
      expect(steps.sourceName, 'user');
      final compaction = row(cubit, 'compaction.enabled').field;
      expect(compaction.displayValue, 'true');
      expect(compaction.sourceName, 'default');
      for (final other in [
        'permissions.mode',
        'agent.effort',
        'agent.default_model',
        'trusted_projects',
        'mcp.servers',
      ]) {
        expect(keys(state), isNot(contains(other)), reason: other);
      }
      expect(
        [for (final g in state.groups) g.section],
        ['Budget', 'Agent', 'Subagents', 'Logging'],
      );
      expect(state.saving, isFalse);
      expect(state.banner, isNull);
      expect(state.fieldErrors, isEmpty);
      expect(opened.single.cwd, fx.project);
      final loaded = events('agent_defaults.loaded').single;
      expect(loaded['access'], 'editable');
      expect(loaded['rows'], 18);
    });

    test('a key with restart is marked and the others are not', () async {
      final fx = await fixture();
      final cubit = make(fx);
      await ready(cubit);

      expect(row(cubit, 'logging.level').field.restartRequired, isTrue);
      expect(row(cubit, 'budget.max_steps').field.restartRequired, isFalse);
    });

    test('a key set by the project layer stays editable and names the '
        'layer (D4)', () async {
      final fx = await fixture(localYaml: 'compaction:\n  enabled: false\n');
      final cubit = make(fx);
      await ready(cubit);

      final compaction = row(cubit, 'compaction.enabled');
      expect(compaction.field.sourceName, 'local');
      expect(compaction.refusal, isNull);
      expect(compaction.overriddenBy, 'local');
    });
  });

  group('Страница только для чтения (SETUP-2)', () {
    test('a WebSocket agent: the origin without the path, no rows, the local '
        'config is not read', () async {
      final fx = await fixture(userYaml: 'budget:\n  max_steps: 80\n');
      workspace.emit(WorkspaceState(connection: _connected, profile: _remote));
      final cubit = make(fx);

      await cubit.reload();

      expect(cubit.state, isA<AgentDefaultsReadOnly>());
      final state = cubit.state as AgentDefaultsReadOnly;
      expect(state.kind, AgentDefaultsReadOnlyKind.remote);
      expect(state.subject, 'wss://devbox:7420');
      expect(opened, isEmpty);
      expect(fx.store.snapshotCalls, 0);
      expect(events('agent_defaults.loaded').single['access'], 'remote');
    });

    test('a third-party stdio agent is managed by itself', () async {
      final fx = await fixture();
      workspace.emit(
        const WorkspaceState(connection: _connected, profile: _foreign),
      );
      final cubit = make(fx);

      await cubit.reload();

      expect(cubit.state, isA<AgentDefaultsReadOnly>());
      final state = cubit.state as AgentDefaultsReadOnly;
      expect(state.kind, AgentDefaultsReadOnlyKind.notManaged);
      expect(state.subject, 'python');
      expect(opened, isEmpty);
      expect(fx.store.snapshotCalls, 0);
    });

    test('a broken config.yaml: Unreadable with the problems, no editors, '
        'the file is untouched', () async {
      final fx = await fixture(userYaml: 'budget: [unclosed\n');
      final before = fx.userConfig;
      final cubit = make(fx);

      await cubit.reload();

      expect(cubit.state, isA<AgentDefaultsUnreadable>());
      final state = cubit.state as AgentDefaultsUnreadable;
      expect(state.problems, isNotEmpty);
      expect(events('agent_defaults.unreadable'), hasLength(1));
      // Любая правка в Unreadable ничего не пишет.
      await cubit.submit('budget.max_steps', '80');
      expect(fx.store.applied, isEmpty);
      expect(fx.userConfig, before);
    });
  });

  group('Запись одного ключа (D4, D5)', () {
    test('the step limit: one SetValue to the user layer, the row is re-read, '
        'the banner is plain "Saved", nothing goes to the agent', () async {
      final fx = await fixture();
      connectEmbedded();
      final cubit = make(fx);
      await ready(cubit);

      await cubit.submit('budget.max_steps', '80');

      expect(fx.store.applied.single.path, '${fx.home}/config.yaml');
      expect(fx.store.applied.single.edits, [
        const SetValue('budget.max_steps', 80),
      ]);
      expect(fx.userConfig, contains('max_steps: 80'));
      final steps = row(cubit, 'budget.max_steps').field;
      expect(steps.displayValue, '80');
      expect(steps.sourceName, 'user');
      final state = now(cubit);
      expect(state.saving, isFalse);
      expect(state.fieldErrors, isEmpty);
      expect(state.banner?.kind, AgentDefaultsBannerKind.saved);
      expect(state.banner?.key, 'budget.max_steps');
      expect(state.banner?.restart, AgentDefaultsRestart.none);
      expect(state.banner?.overriddenBy, isNull);
      expect(workspace.ensuredAgents, isEmpty);
    });

    test('a switch and a list pass through the same parser: true and an '
        'enum value', () async {
      final fx = await fixture();
      final cubit = make(fx);
      await ready(cubit);

      await cubit.submit('compaction.enabled', 'false');
      await cubit.submit('logging.level', 'warning');

      expect(fx.store.applied.map((a) => a.edits.single).toList(), [
        const SetValue('compaction.enabled', false),
        const SetValue('logging.level', 'warning'),
      ]);
    });

    test('a duration is written in the config form', () async {
      final fx = await fixture();
      final cubit = make(fx);
      await ready(cubit);

      await cubit.submit('budget.max_duration', '30s');

      expect(fx.store.applied.single.edits, [
        const SetValue('budget.max_duration', '30s'),
      ]);
    });

    test('a number that does not parse: a field error, no write, the value '
        'is not in the state or the events', () async {
      final fx = await fixture();
      final before = fx.userConfig;
      final cubit = make(fx);
      await ready(cubit);

      await cubit.submit('budget.max_steps', '0');
      expect(now(cubit).fieldErrors, {'budget.max_steps'});
      await cubit.submit('budget.max_steps', 'sk-test-leak-7351');

      expect(now(cubit).fieldErrors, {'budget.max_steps'});
      expect(now(cubit).banner, isNull);
      expect(fx.store.applied, isEmpty);
      expect(fx.userConfig, before);
      expect(logger.entries.toString(), isNot(contains('sk-test-leak-7351')));
    });

    test('a valid value after a wrong one clears the field error', () async {
      final fx = await fixture();
      final cubit = make(fx);
      await ready(cubit);
      await cubit.submit('budget.max_steps', '0');
      expect(now(cubit).fieldErrors, isNotEmpty);

      await cubit.submit('budget.max_steps', '12');

      expect(now(cubit).fieldErrors, isEmpty);
      expect(fx.store.applied, hasLength(1));
    });

    test('a key with restart: the banner tail depends on the connected '
        'agent', () async {
      final fx = await fixture();
      connectEmbedded();
      final cubit = make(fx);
      await ready(cubit);

      await cubit.submit('logging.level', 'debug');

      expect(fx.userConfig, contains('level: debug'));
      expect(now(cubit).banner?.kind, AgentDefaultsBannerKind.saved);
      expect(now(cubit).banner?.restart, AgentDefaultsRestart.afterRestart);
    });

    test('a key with restart without a connected agent: "when the agent '
        'starts"', () async {
      final fx = await fixture();
      final cubit = make(fx);
      await ready(cubit);

      await cubit.submit('logging.level', 'debug');

      expect(now(cubit).banner?.restart, AgentDefaultsRestart.whenStarts);
    });

    test('a project file overrides the write: the warning names the layer '
        'and the effective value, the project file is untouched', () async {
      final fx = await fixture(localYaml: 'compaction:\n  enabled: false\n');
      final localBefore = fx.localConfig;
      connectEmbedded();
      final cubit = make(fx);
      await ready(cubit);

      await cubit.submit('compaction.enabled', 'true');

      expect(fx.userConfig, contains('enabled: true'));
      expect(fx.localConfig, localBefore);
      final banner = now(cubit).banner!;
      expect(banner.kind, AgentDefaultsBannerKind.overridden);
      expect(banner.overriddenBy, 'local');
      expect(banner.effective, 'false');
      expect(banner.restart, AgentDefaultsRestart.none);
    });

    test(
      'the overridden banner of a key with restart carries the tail',
      () async {
        final fx = await fixture(localYaml: 'logging:\n  level: error\n');
        connectEmbedded();
        final cubit = make(fx);
        await ready(cubit);

        await cubit.submit('logging.level', 'debug');

        final banner = now(cubit).banner!;
        expect(banner.kind, AgentDefaultsBannerKind.overridden);
        expect(banner.effective, 'error');
        expect(banner.restart, AgentDefaultsRestart.afterRestart);
      },
    );
  });

  group('Отказ в правке (D5, D6)', () {
    test('a value set by the environment has no editor and is not '
        'written', () async {
      final fx = await fixture();
      fx.store.transform = (s) => AgentConfigSnapshot(
        cwd: s.cwd,
        layers: s.layers,
        loaded: s.loaded,
        origins: {
          ...s.origins,
          'budget.max_steps': const ConfigSourceView(
            kind: ConfigSourceKind.environment,
            label: 'env',
          ),
        },
        secrets: s.secrets,
      );
      final cubit = make(fx);
      await ready(cubit);

      final steps = row(cubit, 'budget.max_steps');
      expect(steps.refusal, isA<ExternalSourceSetting>());
      expect(steps.field.sourceName, 'env');
      await cubit.submit('budget.max_steps', '80');

      expect(fx.store.applied, isEmpty);
      expect(now(cubit).banner, isNull);
    });

    test('a key that the page does not show is not written', () async {
      final fx = await fixture();
      final cubit = make(fx);
      await ready(cubit);

      await cubit.submit('permissions.mode', 'bypass');
      await cubit.submit('trusted_projects', '/tmp');
      await cubit.submit('no.such.key', '1');

      expect(fx.store.applied, isEmpty);
    });
  });

  group('Сброс поля (D5)', () {
    test('an empty field of a key set in user removes it: UnsetValue, the row '
        'is "not set" with the source default', () async {
      final fx = await fixture(userYaml: 'budget:\n  max_tokens: 100000\n');
      final cubit = make(fx);
      await ready(cubit);
      expect(row(cubit, 'budget.max_tokens').field.displayValue, '100000');

      await cubit.submit('budget.max_tokens', '');

      expect(fx.store.applied.single.edits, [
        const UnsetValue('budget.max_tokens'),
      ]);
      expect(fx.userConfig, isNot(contains('max_tokens')));
      final tokens = row(cubit, 'budget.max_tokens').field;
      expect(tokens.displayValue, '(not set)');
      expect(tokens.sourceName, 'default');
      expect(now(cubit).banner?.kind, AgentDefaultsBannerKind.saved);
    });

    test('an empty field of a key not set in user writes nothing and '
        'reports no error', () async {
      final fx = await fixture(localYaml: 'budget:\n  max_steps: 7\n');
      final before = fx.userConfig;
      final cubit = make(fx);
      await ready(cubit);

      await cubit.submit('budget.max_steps', '');
      await cubit.submit('budget.max_tokens', '');

      expect(fx.store.applied, isEmpty);
      expect(fx.userConfig, before);
      expect(now(cubit).fieldErrors, isEmpty);
      expect(now(cubit).banner, isNull);
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

      await cubit.submit('compaction.enabled', 'false');

      expect(
        fx.store.applied,
        hasLength(1),
        reason: 'SETUP-6: без автоповтора',
      );
      expect(now(cubit).banner?.kind, AgentDefaultsBannerKind.conflict);
      expect(now(cubit).saving, isFalse);
      expect(fx.store.snapshotCalls, greaterThan(snapshotsBefore));
      final failed = events('agent_defaults.save_failed').single;
      expect(failed['key'], 'compaction.enabled');
      expect(failed['outcome'], 'conflict');
    });

    test('a real conflict: the file changed on disk after the snapshot is '
        'not overwritten', () async {
      final fx = await fixture();
      final cubit = make(fx);
      await ready(cubit);
      File(
        '${fx.home}/config.yaml',
      ).writeAsStringSync('${fx.userConfig}budget:\n  max_tokens: 5\n');

      await cubit.submit('compaction.enabled', 'false');

      expect(now(cubit).banner?.kind, AgentDefaultsBannerKind.conflict);
      expect(fx.userConfig, isNot(contains('compaction')));
      expect(fx.store.applied, hasLength(1));
    });

    test('the writer rejects a value: the error banner carries the problem '
        'of the writer, the file is untouched', () async {
      final fx = await fixture();
      final before = fx.userConfig;
      final cubit = make(fx);
      await ready(cubit);

      await cubit.submit('budget.max_cost', '0');

      final banner = now(cubit).banner!;
      expect(banner.kind, AgentDefaultsBannerKind.rejected);
      expect(banner.problems.single, contains('budget.max_cost'));
      expect(fx.userConfig, before);
      final failed = events('agent_defaults.save_failed').single;
      expect(failed['key'], 'budget.max_cost');
      expect(failed['outcome'], 'rejected');
    });

    test('a value that looks like a secret: the banner points to the secret '
        'command', () async {
      final fx = await fixture();
      final cubit = make(fx);
      await ready(cubit);
      fx.store.forcedOutcome = const ConfigInlineSecret(
        key: 'logging.level',
        suggestedSecretName: 'codelab_logging_level',
      );

      await cubit.submit('logging.level', 'debug');

      expect(now(cubit).banner?.kind, AgentDefaultsBannerKind.inlineSecret);
      expect(
        events('agent_defaults.save_failed').single['outcome'],
        'inline_secret',
      );
    });

    test('an exception is logged by type only: no path, no text', () async {
      final fx = await fixture();
      final cubit = make(fx);
      await ready(cubit);
      fx.store.applyError = const FileSystemException(
        'disk is full',
        '/Users/demo/.codelab/config.yaml',
      );

      await cubit.submit('budget.max_steps', '9');

      final state = now(cubit);
      expect(state.saving, isFalse);
      expect(state.banner?.kind, AgentDefaultsBannerKind.rejected);
      final failed = events('agent_defaults.save_failed').single;
      expect(failed['outcome'], 'error');
      expect(failed['error_type'], 'FileSystemException');
      expect(logger.entries.toString(), isNot(contains('/Users/demo')));
      expect(logger.entries.toString(), isNot(contains('disk is full')));
    });
  });

  group('Одна запись за раз и поздние результаты (D7)', () {
    test('a repeated edit while saving is ignored', () async {
      final fx = await fixture();
      final cubit = make(fx);
      await ready(cubit);
      final applying = Completer<void>();
      final release = Completer<void>();
      fx.store.onApply = () {
        applying.complete();
        return release.future;
      };

      final first = cubit.submit('budget.max_steps', '10');
      await arrive(applying);
      expect(now(cubit).saving, isTrue);
      await cubit.submit('budget.max_tokens', '5000');
      await cubit.submit('compaction.enabled', 'false');
      release.complete();
      await first;

      expect(fx.store.applied, hasLength(1));
      expect(fx.store.applied.single.edits, [
        const SetValue('budget.max_steps', 10),
      ]);
      expect(now(cubit).saving, isFalse);
    });

    test('a change of the connection during the write: the block is '
        'read-only, no banner of the write', () async {
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

      final write = cubit.submit('budget.max_steps', '80');
      await arrive(applying);
      final readOnly = until(cubit, (s) => s is AgentDefaultsReadOnly);
      workspace.emit(WorkspaceState(connection: _connected, profile: _remote));
      await readOnly;
      release.complete();
      await write;

      expect(cubit.state, isA<AgentDefaultsReadOnly>());
      expect(
        (cubit.state as AgentDefaultsReadOnly).kind,
        AgentDefaultsReadOnlyKind.remote,
      );
    });

    test('a late snapshot after a newer reload is discarded', () async {
      final fx = await fixture();
      final cubit = make(fx);
      final held = holdSnapshot(fx, 1);

      final first = cubit.reload();
      await arrive(held.reached);
      File(
        '${fx.home}/config.yaml',
      ).writeAsStringSync('${fx.userConfig}budget:\n  max_steps: 33\n');
      await cubit.reload();
      expect(row(cubit, 'budget.max_steps').field.displayValue, '33');
      held.gate.complete();
      await first;

      expect(row(cubit, 'budget.max_steps').field.displayValue, '33');
      expect(
        events('agent_defaults.load_discarded').single['reason'],
        'reload',
      );
    });

    test('a late snapshot after a change of the connection is '
        'discarded', () async {
      final fx = await fixture();
      final cubit = make(fx);
      final held = holdSnapshot(fx, 1);

      final first = cubit.reload();
      await arrive(held.reached);
      final readOnly = until(cubit, (s) => s is AgentDefaultsReadOnly);
      workspace.emit(WorkspaceState(connection: _connected, profile: _remote));
      await readOnly;
      held.gate.complete();
      await first;

      expect(cubit.state, isA<AgentDefaultsReadOnly>());
      expect(
        events('agent_defaults.load_discarded').single['reason'],
        'access_changed',
      );
    });

    test('a late snapshot after a change of the focus folder is '
        'discarded', () async {
      final fx = await fixture();
      final cubit = make(fx);
      final held = holdSnapshot(fx, 1);

      final first = cubit.reload();
      await arrive(held.reached);
      final reloaded = until(cubit, (s) => s is AgentDefaultsReady);
      projectDir = () => null;
      workspace.emit(const WorkspaceState());
      held.gate.complete();
      await first;
      await reloaded;

      expect(
        events('agent_defaults.load_discarded').single['reason'],
        'access_changed',
      );
      expect(opened.last.cwd, isNull);
    });

    test('a late snapshot after close() is discarded', () async {
      final fx = await fixture();
      final cubit = make(fx);
      final held = holdSnapshot(fx, 1);

      final first = cubit.reload();
      await arrive(held.reached);
      await cubit.close();
      held.gate.complete();
      await first;

      expect(cubit.state, isA<AgentDefaultsLoading>());
      expect(
        events('agent_defaults.load_discarded').single['reason'],
        'closed',
      );
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

      final write = cubit.submit('budget.max_steps', '10');
      await arrive(applying);
      await cubit.close();
      release.complete();
      await write;

      expect(events('agent_defaults.saved').single['key'], 'budget.max_steps');
    });

    test('an edit during a new load is not written: save_failed with '
        '"stale"', () async {
      final fx = await fixture();
      final cubit = make(fx);
      await ready(cubit);
      final held = holdSnapshot(fx, 2);

      final reloading = cubit.reload();
      await arrive(held.reached);
      await cubit.submit('budget.max_steps', '10');
      held.gate.complete();
      await reloading;

      expect(fx.store.applied, isEmpty);
      final failed = events('agent_defaults.save_failed').single;
      expect(failed['key'], 'budget.max_steps');
      expect(failed['outcome'], 'stale');
      expect(failed['level'], 'warning');
    });
  });

  group('События журнала без значений (CFG-10, D16)', () {
    test(
      'a write logs the key and the flags, not the value or a path',
      () async {
        final fx = await fixture();
        connectEmbedded();
        final cubit = make(fx);
        await ready(cubit);

        await cubit.submit('budget.max_steps', '7351');

        final saved = events('agent_defaults.saved').single;
        expect(saved['key'], 'budget.max_steps');
        expect(saved['restart_required'], false);
        expect(saved['overridden'], false);
        final text = logger.entries.toString();
        expect(text, isNot(contains('7351')));
        expect(text, isNot(contains(fx.rootPath)));
        expect(text, isNot(contains('config.yaml')));
      },
    );

    test('an overridden write and a restart key are flagged', () async {
      final fx = await fixture(localYaml: 'logging:\n  level: error\n');
      connectEmbedded();
      final cubit = make(fx);
      await ready(cubit);

      await cubit.submit('logging.level', 'debug');

      final saved = events('agent_defaults.saved').single;
      expect(saved['restart_required'], true);
      expect(saved['overridden'], true);
    });

    test('loading events carry no path', () async {
      final fx = await fixture(userYaml: 'budget: [unclosed\n');
      await make(fx).reload();
      final ok = await fixture();
      await make(ok).reload();

      expect(events('agent_defaults.unreadable'), isNotEmpty);
      expect(events('agent_defaults.loaded'), isNotEmpty);
      final text = logger.entries.toString();
      expect(text, isNot(contains(fx.rootPath)));
      expect(text, isNot(contains(ok.rootPath)));
      expect(text, isNot(contains('config.yaml')));
    });
  });
}
