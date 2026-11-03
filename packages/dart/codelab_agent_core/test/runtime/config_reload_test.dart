import 'dart:async';

import 'package:codelab_agent_core/codelab_agent_core.dart';
// Тест проверяет применённый снимок рантайма (`config`, `appliedValues`,
// `appliedHost`): это шов тестов, а не публичный API (PKG-5).
import 'package:codelab_agent_core/src/runtime/agent_runtime.dart'
    show AgentRuntimeImpl;
import 'package:codelab_agent_core/testing.dart';
import 'package:test/test.dart';

import '../config/config_support.dart' show baseValues, layer, withValues;
import '../host/core_harness.dart'
    show callStep, inMemoryJournal, noExec, textStep;
import '../support/fake_secret_store.dart';
import '../support/manual_stream.dart';

/// Живая перезагрузка конфигурации в `AgentRuntime` (agent-runtime «Живая
/// перезагрузка конфигурации», «Серверы конфигурации при перезагрузке» — в
/// части снимка; design.md change `add-config-writer-and-reload`, D8, D14;
/// CFG-15, CFG-16, R0-1, R0-4).
///
/// Тест проверяет снимок, `restartRequiredKeys` и `pendingRestartKeys`;
/// применение серверов к живым сессиям — `mcp_apply_config_test.dart`
/// (задача 6.3).
void main() {
  // ---- перезагрузка: итог и ключи ------------------------------------------

  group('outcome and keys', () {
    test('a restart key stays old, the rest is applied (scenario "Ключ '
        'перезапуска")', () async {
      final rig = await _Rig.create(
        user: withValues(_user(), {
          'logging': {'file': '/var/a.log'},
        }),
      );
      _put(rig.user, 'logging.file', '/var/b.log');
      _put(rig.user, 'budget.max_steps', 20);

      final report = await rig.runtime.reloadConfig();

      expect(report.outcome, ConfigReloadOutcome.applied);
      expect(report.changedKeys, ['budget.max_steps']);
      expect(report.restartRequiredKeys, ['logging.file']);
      expect(rig.runtime.configStatus().pendingRestartKeys, ['logging.file']);
      expect(rig.runtime.config.budget.maxSteps, 20);
      // Прежние HostSettings и values: ключ хоста действует после
      // перезапуска (D8, «ConfigLoadResult.values и прежние HostSettings»).
      expect(rig.runtime.appliedHost!.logFile, '/var/a.log');
      expect(rig.runtime.appliedValues['logging.file'], '/var/a.log');
      expect(rig.runtime.appliedValues['budget.max_steps'], 20);
      final applied = rig.logger.eventsOf('config.reload.applied').single;
      expect(applied.fields['keys'], ['budget.max_steps']);
      expect(applied.fields['restart_required'], ['logging.file']);
      expect(
        rig.logger.eventsOf('config.reload.restart_required').single.fields,
        {
          'keys': ['logging.file'],
        },
      );
    });

    test('without a difference the outcome is unchanged and the log is '
        'config.reload.noop', () async {
      final rig = await _Rig.create();

      final report = await rig.runtime.reloadConfig();

      expect(report.outcome, ConfigReloadOutcome.unchanged);
      expect(report.changedKeys, isEmpty);
      expect(report.restartRequiredKeys, isEmpty);
      expect(rig.logger.eventsOf('config.reload.noop'), hasLength(1));
      expect(rig.logger.eventsOf('config.reload.applied'), isEmpty);
    });

    test('the model by default applies only to new sessions (scenario '
        '"Модель по умолчанию")', () async {
      final rig = await _Rig.create();
      final old = await rig.session();
      _put(rig.user, 'agent.default_model', 'a/m2');

      final report = await rig.runtime.reloadConfig();

      expect(report.changedKeys, ['agent.default_model']);
      expect(old.model.id, 'm1');
      expect((await rig.session()).model.id, 'm2');
    });

    test('an invalid edit keeps the snapshot and says nothing to sessions '
        '(CFG-15, scenario "Невалидная правка")', () async {
      final rig = await _Rig.create();
      final session = await rig.session();
      final seen = <AgentEvent>[];
      session.events.listen(seen.add);
      _put(rig.user, 'budget.max_steps', 0);

      final report = await rig.runtime.reloadConfig();

      expect(report.outcome, ConfigReloadOutcome.failed);
      expect(report.issues.map((i) => i.key), ['budget.max_steps']);
      expect(rig.runtime.config.budget.maxSteps, 10);
      expect(seen, isEmpty);
      final status = rig.runtime.configStatus();
      expect(status.lastIssues.map((i) => i.key), ['budget.max_steps']);
      expect(status.lastFailureAt, rig.clock.now());
      expect(rig.modelsForCalls, isEmpty, reason: 'nothing is built');
      expect(rig.logger.eventsOf('config.reload.applied'), isEmpty);
    });

    test('the log of a failure has keys and positions, never values '
        '(CFG-2)', () async {
      final rig = await _Rig.create();
      _put(rig.user, 'logging.level', 'hunter2-not-a-level');

      final report = await rig.runtime.reloadConfig();

      expect(report.outcome, ConfigReloadOutcome.failed);
      final record = rig.logger.eventsOf('config.reload.failed').single;
      expect(record.level, LogLevel.error);
      expect(record.fields['sources'], isA<List<Object?>>());
      final issues = (record.fields['issues']! as List<Object?>)
          .cast<Map<String, Object?>>();
      expect(issues.single.keys, {'source', 'line', 'column', 'key', 'kind'});
      expect(issues.single['key'], 'logging.level');
      expect(record.fields.toString(), isNot(contains('hunter2')));
    });

    test('an error of load() by a signal is config.reload.failed with '
        'error_class, not an exception in the zone', () async {
      final zoneErrors = await _inZone(() async {
        final rig = await _Rig.create();
        rig.source.failure = StateError('boom hunter2');

        rig.source.signal();
        await pumpEventQueue();

        final record = rig.logger.eventsOf('config.reload.failed').single;
        expect(record.fields['error_class'], 'StateError');
        expect(record.fields.toString(), isNot(contains('hunter2')));
        expect(rig.runtime.configStatus().lastFailureAt, isNotNull);
        // Явный вызов тоже не бросает: итог — failed.
        final report = await rig.runtime.reloadConfig();
        expect(report.outcome, ConfigReloadOutcome.failed);
      });
      expect(zoneErrors, isEmpty);
    });

    test('a success after a failure clears lastIssues', () async {
      final rig = await _Rig.create();
      _put(rig.user, 'budget.max_steps', 0);
      await rig.runtime.reloadConfig();
      _put(rig.user, 'budget.max_steps', 12);

      final report = await rig.runtime.reloadConfig();

      expect(report.outcome, ConfigReloadOutcome.applied);
      final status = rig.runtime.configStatus();
      expect(status.lastIssues, isEmpty);
      expect(status.lastFailureAt, isNotNull, reason: 'history is kept');
    });

    test(
      'keys of diff: a list is one leaf, mcp.servers goes by name',
      () async {
        final rig = await _Rig.create(
          user: withValues(_user(), {
            'permissions': {
              'deny': ['exec:rm *'],
            },
            'mcp': {
              'servers': [
                {'name': 'h', 'type': 'http', 'url': 'https://h.test/mcp'},
              ],
            },
          }),
        );
        _put(rig.user, 'permissions.deny', ['exec:rm *', 'exec:dd *']);
        _put(rig.user, 'mcp.servers', [
          {'name': 'h', 'type': 'http', 'url': 'https://h2.test/mcp'},
        ]);

        final report = await rig.runtime.reloadConfig();

        expect(report.restartRequiredKeys, ['permissions.deny']);
        expect(report.changedKeys, ['mcp.servers[h]']);
      },
    );

    test('a key outside the registry waits for a restart (fail closed, '
        'scenario "Ключ вне реестра")', () async {
      final rig = await _Rig.create(
        patchValues: (values) => {...values, 'x.unknown': 1},
      );
      rig.source.patch = (values) => {...values, 'x.unknown': 2};

      final report = await rig.runtime.reloadConfig();

      expect(report.restartRequiredKeys, ['x.unknown']);
      expect(rig.runtime.configStatus().pendingRestartKeys, ['x.unknown']);
      expect(rig.runtime.appliedValues['x.unknown'], 1);
    });

    test('keys without a consumer are not restart keys: tools.disabled, '
        'exec.*, redact.* (D8, "Ключи без потребителя")', () async {
      final rig = await _Rig.create();
      _put(rig.user, 'tools.disabled', ['exec']);
      _put(rig.user, 'exec.default_timeout', '30s');
      _put(rig.user, 'redact.enabled', false);

      final report = await rig.runtime.reloadConfig();

      expect(report.restartRequiredKeys, isEmpty);
      expect(rig.runtime.configStatus().pendingRestartKeys, isEmpty);
    });

    test('checkConfig does not move the watcher base, reload does (D7, '
        'scenario "/config check during the debounce")', () async {
      final rig = await _Rig.create();

      await rig.runtime.checkConfig();
      await rig.runtime.reloadConfig();

      expect(rig.source.rebaseFlags, [false, true]);
    });

    test(
      'budget applies from the next turn of a live session (CFG-16)',
      () async {
        final rig = await _Rig.create(
          user: withValues(_user(), {
            'budget': {'max_steps': 1},
          }),
          steps: [
            callStep('c1', 'read', {'path': '/proj/a.txt'}),
            callStep('c2', 'read', {'path': '/proj/a.txt'}),
            textStep('done'),
          ],
        );
        final session = await rig.session();
        final first = await session.prompt(const [TextContent('go')]);
        _put(rig.user, 'budget.max_steps', 5);
        await rig.runtime.reloadConfig();

        final second = await session.prompt(const [TextContent('again')]);

        expect(first.budgetExceeded, isNotNull);
        expect(second.budgetExceeded, isNull);
      },
    );

    test(
      'pendingRestartKeys are the keys that still differ from the applied '
      'snapshot: sorted, and a key returned in the file disappears',
      () async {
        final rig = await _Rig.create(
          user: withValues(_user(), {
            'logging': {'file': '/var/a.log'},
            'sessions': {'fsync': 'never'},
          }),
        );
        _put(rig.user, 'sessions.fsync', 'always');
        await rig.runtime.reloadConfig();
        _put(rig.user, 'logging.file', '/var/b.log');
        await rig.runtime.reloadConfig();

        expect(rig.runtime.configStatus().pendingRestartKeys, [
          'logging.file',
          'sessions.fsync',
        ]);

        _put(rig.user, 'logging.file', '/var/a.log');
        await rig.runtime.reloadConfig();

        expect(rig.runtime.configStatus().pendingRestartKeys, [
          'sessions.fsync',
        ]);
      },
    );
  });

  // ---- модели: функция, каталог, события -----------------------------------

  group('model function and catalog', () {
    test('modelsFor is not called at assembly; the first turn runs on '
        'streamFunction, the next after a reload on modelsFor (scenario '
        '"modelsFor не вызывается при сборке")', () async {
      final rig = await _Rig.create();
      final session = await rig.session();
      expect(rig.modelsForCalls, isEmpty);

      await session.prompt(const [TextContent('one')]);
      final report = await rig.runtime.reloadConfig();
      await session.prompt(const [TextContent('two')]);

      expect(report.outcome, ConfigReloadOutcome.unchanged);
      expect(rig.modelsForCalls, hasLength(1));
      expect(rig.streamTags, ['init', 'm1']);
    });

    test('without a ConfigSource modelsFor is neither required nor called '
        'and nothing is subscribed (scenario "Хост без источника")', () async {
      final rig = await _Rig.create(withSource: false);
      final session = await rig.session();
      await session.prompt(const [TextContent('one')]);

      expect(rig.modelsForCalls, isEmpty);
      expect(rig.streamTags, ['init']);
      expect(rig.source.listened, isFalse);
      expect(rig.runtime.reloadConfig, throwsStateError);
      expect(rig.runtime.checkConfig, throwsStateError);
      expect(rig.runtime.configStatus().sources, isEmpty);
    });

    test('a ConfigSource without modelsFor is HostWiringException', () async {
      await expectLater(
        _Rig.create(withModelsFor: false),
        throwsA(isA<HostWiringException>()),
      );
    });

    test('a changed model list gives each live session one '
        'ModelOptionsChanged; the next step runs on the new function '
        '(scenario "Смена списка моделей")', () async {
      final rig = await _Rig.create();
      final one = await rig.session();
      final two = await rig.session();
      final closed = await rig.session();
      final seenOne = <AgentEvent>[], seenTwo = <AgentEvent>[];
      final seenClosed = <AgentEvent>[];
      one.events.listen(seenOne.add);
      two.events.listen(seenTwo.add);
      closed.events.listen(seenClosed.add);
      await closed.close();
      _put(rig.user, 'providers.a.models.m3', <String, Object?>{});

      await rig.runtime.reloadConfig();
      await one.prompt(const [TextContent('go')]);

      expect(seenOne.whereType<ModelOptionsChanged>(), hasLength(1));
      expect(seenOne.whereType<ModelOptionsChanged>().single.sessionId, one.id);
      expect(seenTwo.whereType<ModelOptionsChanged>(), hasLength(1));
      expect(seenClosed, isEmpty);
      expect(rig.streamTags, ['m1']);
      expect(
        [for (final m in rig.runtime.models.models) m.id.value],
        ['a/m1', 'a/m2', 'a/m3', 'k/km'],
      );
    });

    test('a model added as an empty node is a changed key and a changed '
        'catalog: applied, one event (empty nodes have no leaves)', () async {
      final rig = await _Rig.create();
      final session = await rig.session();
      final seen = <AgentEvent>[];
      session.events.listen(seen.add);
      _put(rig.user, 'providers.a.models.m3', <String, Object?>{});

      final report = await rig.runtime.reloadConfig();
      await pumpEventQueue();

      expect(report.outcome, ConfigReloadOutcome.applied);
      expect(report.changedKeys, ['providers.a.models.m3']);
      expect(report.restartRequiredKeys, isEmpty);
      expect(seen.whereType<ModelOptionsChanged>(), hasLength(1));

      _drop(rig.user, 'providers.a.models.m3');
      final removed = await rig.runtime.reloadConfig();
      await pumpEventQueue();

      expect(removed.outcome, ConfigReloadOutcome.applied);
      expect(removed.changedKeys, ['providers.a.models.m3']);
      expect(seen.whereType<ModelOptionsChanged>(), hasLength(2));
    });

    test(
      'an empty section is not a restart key: no descriptor, no value',
      () async {
        final rig = await _Rig.create();
        _put(rig.user, 'permissions', <String, Object?>{});

        final report = await rig.runtime.reloadConfig();

        expect(report.restartRequiredKeys, isEmpty);
      },
    );

    test(
      'a new provider with a key and an empty model node waits whole',
      () async {
        final rig = await _Rig.create();
        _put(rig.user, 'providers.n', {
          'kind': 'openai-compatible',
          'base_url': 'https://n.test/v1',
          'api_key_secret': 'codelab/n',
          'models': {'m': <String, Object?>{}},
        });

        final report = await rig.runtime.reloadConfig();

        expect(report.restartRequiredKeys, ['providers.n']);
        expect(rig.runtime.models.resolve(const ModelId('n/m')), isNull);
      },
    );

    test(
      'only deferred keys changed: applied, nothing in changedKeys',
      () async {
        final rig = await _Rig.create(
          user: withValues(_user(), {
            'logging': {'file': '/var/a.log'},
          }),
        );
        _put(rig.user, 'logging.file', '/var/b.log');

        final report = await rig.runtime.reloadConfig();

        expect(report.outcome, ConfigReloadOutcome.applied);
        expect(report.restartRequiredKeys, ['logging.file']);
        expect(report.changedKeys, isEmpty);
      },
    );

    test('ModelOptionsChanged goes out during a running turn, at once and '
        'outside the journal; a closed session gets none', () async {
      final rig = await _Rig.create(hold: true);
      final session = await rig.session();
      final other = await rig.session();
      final seen = <AgentEvent>[];
      session.events.listen(seen.add);
      final turn = session.prompt(const [TextContent('go')]);
      await pumpEventQueue();
      expect(rig.manual!.calls, 1, reason: 'the turn is running');
      final before = rig.journalOf(session);
      _put(rig.user, 'providers.a.models.m3', <String, Object?>{});

      await rig.runtime.reloadConfig();
      await pumpEventQueue();

      expect(seen.whereType<ModelOptionsChanged>(), hasLength(1));
      expect(rig.journalOf(session), before);
      await session.close();
      _put(rig.user, 'providers.a.models.m4', <String, Object?>{});
      await rig.runtime.reloadConfig();
      expect(seen.whereType<ModelOptionsChanged>(), hasLength(1));
      expect(rig.journalOf(other), isNot(contains('ModelOptionsChanged')));
      await turn;
    });

    test('an unchanged model list gives no event', () async {
      final rig = await _Rig.create();
      final session = await rig.session();
      final seen = <AgentEvent>[];
      session.events.listen(seen.add);
      _put(rig.user, 'budget.max_steps', 15);

      await rig.runtime.reloadConfig();

      expect(seen.whereType<ModelOptionsChanged>(), isEmpty);
    });

    test('a model removed from the catalog: the session keeps its model and '
        'the old function; one model_orphaned per session and model '
        '(scenarios "удалённая модель сессии")', () async {
      final rig = await _Rig.create();
      final orphan = await rig.session();
      _put(rig.user, 'agent.default_model', 'a/m2');
      _drop(rig.user, 'providers.a.models.m1');

      await rig.runtime.reloadConfig();
      _put(rig.user, 'budget.max_steps', 11);
      await rig.runtime.reloadConfig();
      await orphan.prompt(const [TextContent('on the old function')]);
      final fresh = await rig.session();
      await fresh.prompt(const [TextContent('on the new one')]);

      expect(orphan.model.id, 'm1');
      expect(rig.streamTags, ['init', 'm2']);
      final record = rig.logger.eventsOf('config.reload.model_orphaned').single;
      expect(record.level, LogLevel.info);
      expect(record.fields, {'session_id': orphan.id.value, 'model': 'a/m1'});
    });

    test('after setModel to a model of the catalog the orphan session '
        'returns to the current function', () async {
      final rig = await _Rig.create();
      final orphan = await rig.session();
      _put(rig.user, 'agent.default_model', 'a/m2');
      _drop(rig.user, 'providers.a.models.m1');
      await rig.runtime.reloadConfig();

      await orphan.setModel(const ModelId('a/m2'));
      await orphan.prompt(const [TextContent('go')]);

      expect(rig.streamTags, ['m1']);
    });

    test('a session created during the replacement gets the snapshot of '
        'its start and no notification (scenario "Сессия, создаваемая во '
        'время замены")', () async {
      final port = _GatedPort();
      final rig = await _Rig.create(projectFiles: port);
      port.gate = Completer<ProjectFiles>();
      final creating = rig.session();
      await pumpEventQueue();
      _put(rig.user, 'agent.default_model', 'a/m2');
      _put(rig.user, 'providers.a.models.m3', <String, Object?>{});

      await rig.runtime.reloadConfig();
      port.gate!.complete(ProjectFiles.empty);
      final session = await creating;
      final seen = <AgentEvent>[];
      session.events.listen(seen.add);
      await session.prompt(const [TextContent('go')]);

      expect(session.model.id, 'm1', reason: 'the snapshot of the start');
      expect(seen.whereType<ModelOptionsChanged>(), isEmpty);
      expect(rig.streamTags, ['m1'], reason: 'the first turn: new function');
    });
  });

  // ---- коалесценция, dispose, подписка -------------------------------------

  group('coalescence and lifecycle', () {
    test('three signals during a load make one more load; every caller '
        'gets the result of that load (scenario "Коалесценция")', () async {
      final rig = await _Rig.create();
      rig.source.gate = Completer<void>();
      _put(rig.user, 'budget.max_steps', 21);

      final first = rig.runtime.reloadConfig();
      await pumpEventQueue();
      rig.source
        ..signal()
        ..signal()
        ..signal();
      final second = rig.runtime.reloadConfig();
      final third = rig.runtime.reloadConfig();
      await pumpEventQueue();
      rig.source.gate!.complete();
      final reports = await Future.wait([first, second, third]);

      expect(rig.source.loads, 2);
      expect(identical(reports[1], reports[2]), isTrue);
      expect(reports[0].outcome, ConfigReloadOutcome.applied);
      expect(reports[1].outcome, ConfigReloadOutcome.unchanged);
    });

    test('dispose during a load: nothing is applied, no events, no zone '
        'errors (scenario "dispose во время загрузки")', () async {
      final zoneErrors = await _inZone(() async {
        final rig = await _Rig.create();
        final session = await rig.session();
        final seen = <AgentEvent>[];
        session.events.listen(seen.add);
        rig.source.gate = Completer<void>();
        _put(rig.user, 'budget.max_steps', 33);
        _put(rig.user, 'providers.a.models.m3', <String, Object?>{});

        final pending = rig.runtime.reloadConfig();
        await pumpEventQueue();
        await rig.runtime.dispose();
        rig.source.gate!.complete();
        await pending;
        rig.source.signal();
        await pumpEventQueue();

        expect(rig.runtime.config.budget.maxSteps, 10);
        expect(rig.modelsForCalls, isEmpty);
        expect(seen.whereType<ModelOptionsChanged>(), isEmpty);
        expect(rig.logger.eventsOf('config.reload.applied'), isEmpty);
        expect(rig.logger.eventsOf('config.reload.failed'), isEmpty);
        expect(rig.source.loads, 1, reason: 'no signal after dispose');
      });
      expect(zoneErrors, isEmpty);
    });

    test('the subscription to changes is owned by the runtime and is '
        'cancelled by dispose', () async {
      final rig = await _Rig.create();
      expect(rig.source.listened, isTrue);

      rig.source.signal();
      await pumpEventQueue();
      expect(rig.source.loads, 1);

      await rig.runtime.dispose();
      expect(rig.source.listened, isFalse);
    });

    test('a replaced secret is seen after an unchanged reload (scenario '
        '"Замена ключа в хранилище секретов")', () async {
      final rig = await _Rig.create();
      rig.secretsStore.values['codelab/k'] = 'v1';
      expect(
        ((await rig.secrets.secret('codelab/k', purpose: 'p')) as SecretFound)
            .value,
        'v1',
      );
      rig.secretsStore.values['codelab/k'] = 'v2';

      final report = await rig.runtime.reloadConfig();
      final lookup = await rig.secrets.secret('codelab/k', purpose: 'p');

      expect(report.outcome, ConfigReloadOutcome.unchanged);
      expect((lookup as SecretFound).value, 'v2');
      expect(lookup.source, 'fake');
    });
    test('the secret cache is kept when the snapshot could not be built '
        '(the model function failed)', () async {
      final rig = await _Rig.create(failModels: true);
      rig.secretsStore.values['codelab/k'] = 'v1';
      await rig.secrets.secret('codelab/k', purpose: 'p');
      rig.secretsStore.values['codelab/k'] = 'v2';

      final report = await rig.runtime.reloadConfig();
      final lookup = await rig.secrets.secret('codelab/k', purpose: 'p');

      expect(report.outcome, ConfigReloadOutcome.failed);
      expect((lookup as SecretFound).value, 'v1');
    });
  });

  // ---- R0-1: права и stdio-серверы -----------------------------------------

  group('keys that widen permissions wait for a restart (R0-1)', () {
    test('permissions and trusted_projects keep the old rules (scenario '
        '"Права не меняются на лету")', () async {
      final rig = await _Rig.create(
        user: withValues(_user(), {
          'permissions': {
            'mode': 'standard',
            'tools': {'exec': 'ask'},
            'deny': ['exec:rm *'],
          },
        }),
      );
      _put(rig.user, 'permissions.tools.exec', 'allow');
      _put(rig.user, 'permissions.mode', 'bypass');
      _put(rig.user, 'permissions.deny', <String>[]);
      _put(rig.user, 'trusted_projects', ['/w/other']);

      final report = await rig.runtime.reloadConfig();

      expect(
        report.restartRequiredKeys,
        containsAll([
          'permissions.tools.exec',
          'permissions.mode',
          'permissions.deny',
          'trusted_projects',
        ]),
      );
      expect(
        rig.runtime.configStatus().pendingRestartKeys,
        containsAll(report.restartRequiredKeys),
      );
      final permissions = rig.runtime.config.permissions;
      expect(permissions.mode, ModeId.standard);
      expect(permissions.rules.toolPolicies['exec'], ToolPolicy.ask);
      expect(permissions.rules.denyPatterns, {
        const PermissionKey('exec', 'rm *'),
      });
      expect(rig.runtime.config.trustedProjects, isEmpty);
      expect(
        rig.logger
            .eventsOf('config.reload.restart_required')
            .single
            .fields['keys'],
        containsAll(['permissions.mode', 'trusted_projects']),
      );
      // Новая сессия получает прежние правила.
      final session = await rig.session();
      expect(session.mode, ModeId.standard);
    });

    test(
      'a new stdio server waits; an http server connects and a removed '
      'one is dropped (scenario "Новый stdio-сервер ждёт перезапуска")',
      () async {
        final rig = await _Rig.create(
          user: withValues(_user(), {
            'mcp': {
              'servers': [_http('old')],
            },
          }),
        );
        _put(rig.user, 'mcp.servers', [_stdio('x'), _http('h')]);

        final report = await rig.runtime.reloadConfig();

        expect(rig.serverNames(), ['h']);
        expect(report.restartRequiredKeys, ['mcp.servers[x]']);
        expect(
          report.changedKeys,
          containsAll(['mcp.servers[h]', 'mcp.servers[old]']),
        );
        expect(report.changedKeys, isNot(contains('mcp.servers[x]')));
        expect(rig.runtime.configStatus().pendingRestartKeys, [
          'mcp.servers[x]',
        ]);
      },
    );

    test('http to stdio and a changed secret reference in stdio env keep '
        'the old servers (scenario "Смена типа на stdio")', () async {
      final rig = await _Rig.create(
        user: withValues(_user(), {
          'mcp': {
            'servers': [
              _http('s'),
              _stdio('t', env: {'TOKEN': r'${secret:a}'}),
            ],
          },
        }),
      );
      _put(rig.user, 'mcp.servers', [
        _stdio('s'),
        _stdio('t', env: {'TOKEN': r'${secret:b}'}),
      ]);

      final report = await rig.runtime.reloadConfig();

      expect(report.restartRequiredKeys, ['mcp.servers[s]', 'mcp.servers[t]']);
      final s = rig.server('s');
      final t = rig.server('t');
      expect(s, isA<McpHttpServerConfig>());
      expect(t, isA<McpStdioServerConfig>());
      expect(t.secretValues.keys, ['env.TOKEN']);
      expect(t.secretValues['env.TOKEN']!.names, ['a'], reason: 'old one');
      expect(
        rig.runtime.appliedValues['mcp.servers[s]'],
        containsPair('type', 'http'),
      );
    });

    test('enabling a stdio server from enabled: false waits (scenario '
        '"Включение stdio-сервера из enabled: false")', () async {
      final rig = await _Rig.create(
        user: withValues(_user(), {
          'mcp': {
            'servers': [_stdio('d', enabled: false)],
          },
        }),
      );
      expect(rig.serverNames(), isEmpty);
      _put(rig.user, 'mcp.servers', [_stdio('d')]);

      final report = await rig.runtime.reloadConfig();

      expect(report.restartRequiredKeys, ['mcp.servers[d]']);
      expect(rig.serverNames(), isEmpty);
    });

    test('a changed command, args or env of a stdio server waits; a changed '
        'call_timeout alone applies', () async {
      final rig = await _Rig.create(
        user: withValues(_user(), {
          'mcp': {
            'servers': [
              _stdio('a'),
              _stdio('b', args: ['--x']),
              _stdio('c', env: {'K': '1'}),
              {..._stdio('d'), 'call_timeout': '10s'},
            ],
          },
        }),
      );
      _put(rig.user, 'mcp.servers', [
        _stdio('a', command: 'other-mcp'),
        _stdio('b', args: ['--y']),
        _stdio('c', env: {'K': '2'}),
        {..._stdio('d'), 'call_timeout': '20s'},
      ]);

      final report = await rig.runtime.reloadConfig();

      expect(report.restartRequiredKeys, [
        'mcp.servers[a]',
        'mcp.servers[b]',
        'mcp.servers[c]',
      ]);
      expect(report.changedKeys, ['mcp.servers[d]']);
      expect((rig.server('a') as McpStdioServerConfig).command, 'fake-mcp');
      expect((rig.server('b') as McpStdioServerConfig).args, ['--x']);
      expect((rig.server('c') as McpStdioServerConfig).env, {'K': '1'});
      expect(rig.server('d').callTimeout, const Duration(seconds: 20));
    });

    test('removing and disabling a stdio server are applied', () async {
      final rig = await _Rig.create(
        user: withValues(_user(), {
          'mcp': {
            'servers': [_stdio('a'), _stdio('b')],
          },
        }),
      );
      _put(rig.user, 'mcp.servers', [_stdio('b', enabled: false)]);

      final report = await rig.runtime.reloadConfig();

      expect(report.restartRequiredKeys, isEmpty);
      expect(report.changedKeys, containsAll(['mcp.servers[a]']));
      expect(rig.serverNames(), isEmpty);
    });
  });

  // ---- R0-4: секрет не уходит на другой адрес ------------------------------

  group('edits that can send a secret elsewhere wait for a restart (R0-4)', () {
    test('a provider with a key: new models apply, the address waits; an '
        'http server with a secret reference waits, one without connects '
        '(scenario "Секрет на новый адрес")', () async {
      final rig = await _Rig.create();
      _put(rig.user, 'providers.k.base_url', 'https://other.test/v1');
      _put(rig.user, 'providers.k.models.km2', <String, Object?>{});
      _put(rig.user, 'mcp.servers', [
        _http(
          'h',
          headers: {
            'Authorization': r'Bearer ${secret:codelab/mcp/h/authorization}',
          },
        ),
        _http('h2'),
      ]);

      final report = await rig.runtime.reloadConfig();

      expect(report.restartRequiredKeys, ['mcp.servers[h]', 'providers.k']);
      expect(rig.runtime.models.resolve(const ModelId('k/km2')), isNotNull);
      expect(rig.provider('k').config.baseUrl.toString(), 'https://k.test/v1');
      expect(rig.serverNames(), ['h2']);
    });

    test(
      'substitution by value, not by name: a secret reference, \${VAR} in '
      'a header, \${VAR} in auth_header (scenario "Подстановка по значению")',
      () async {
        final rig = await _Rig.create(
          environment: {'GITHUB_TOKEN': 'ghp-fake', 'Q_KEY': 'q-fake'},
          user: withValues(_user(), {
            'providers': {
              'q': {
                'kind': 'openai-compatible',
                'base_url': 'https://q.test/v1',
                'auth_header': r'Bearer ${Q_KEY}',
                'models': {'qm': <String, Object?>{}},
              },
            },
          }),
        );
        _put(rig.user, 'providers.q.base_url', 'https://q2.test/v1');
        _put(rig.user, 'mcp.servers', [
          _http('a', headers: {'X-Gw': r'${secret:gw}'}),
          _http('b', headers: {'Authorization': r'Bearer ${GITHUB_TOKEN}'}),
        ]);

        final report = await rig.runtime.reloadConfig();

        expect(report.restartRequiredKeys, [
          'mcp.servers[a]',
          'mcp.servers[b]',
          'providers.q',
        ]);
        expect(rig.serverNames(), isEmpty);
        expect(
          rig.provider('q').config.baseUrl.toString(),
          'https://q.test/v1',
        );
      },
    );

    test('a \${VAR} in base_url makes a provider "with a key" (scenario '
        '"Подстановка в base_url")', () async {
      final rig = await _Rig.create(
        environment: {'GW_HOST': 'gw.test'},
        user: withValues(_user(), {
          'providers': {
            'g': {
              'kind': 'openai-compatible',
              'base_url': r'https://${GW_HOST}/v1',
              'headers': {'X-Team': 'one'},
              'models': {'gm': <String, Object?>{}},
            },
          },
        }),
      );
      _put(rig.user, 'providers.g.headers.X-Team', 'two');

      final report = await rig.runtime.reloadConfig();

      expect(report.restartRequiredKeys, ['providers.g']);
      expect(rig.provider('g').config.headers, containsPair('X-Team', 'one'));
    });

    test('a literal secret header by the name rule makes a provider "with a '
        'key"', () async {
      final rig = await _Rig.create(
        user: withValues(_user(), {
          'providers': {
            'l': {
              'kind': 'openai-compatible',
              'base_url': 'https://l.test/v1',
              'headers': {'X-Api-Key': 'fake-literal-key'},
              'models': {'lm': <String, Object?>{}},
            },
          },
        }),
      );
      _put(rig.user, 'providers.l.base_url', 'https://l2.test/v1');

      final report = await rig.runtime.reloadConfig();

      expect(report.restartRequiredKeys, ['providers.l']);
    });

    test('a provider without a key applies fully, a new one too', () async {
      final rig = await _Rig.create();
      _put(rig.user, 'providers.a.base_url', 'https://a2.test/v1');
      _put(rig.user, 'providers.local', {
        'kind': 'openai-compatible',
        'base_url': 'http://localhost:11434/v1',
        'models': {'lm': <String, Object?>{}},
      });

      final report = await rig.runtime.reloadConfig();

      expect(report.restartRequiredKeys, isEmpty);
      expect(rig.provider('a').config.baseUrl.toString(), 'https://a2.test/v1');
      expect(rig.provider('local'), isNotNull);
    });

    test('a new provider with a key and default_model on its model: applied, '
        'not failed; the reference waits (scenario "Новый провайдер с '
        'ключом и ссылки на его модели")', () async {
      final rig = await _Rig.create();
      _put(rig.user, 'providers.n', {
        'kind': 'openai-compatible',
        'base_url': 'https://n.test/v1',
        'api_key_secret': 'codelab/n',
        'models': {'m': <String, Object?>{}},
      });
      _put(rig.user, 'agent.default_model', 'n/m');
      _put(rig.user, 'budget.max_steps', 17);

      final report = await rig.runtime.reloadConfig();

      expect(report.outcome, ConfigReloadOutcome.applied);
      expect(report.issues, isEmpty);
      expect(report.restartRequiredKeys, [
        'agent.default_model',
        'providers.n',
      ]);
      expect(report.changedKeys, ['budget.max_steps']);
      expect(rig.runtime.config.budget.maxSteps, 17);
      expect(
        rig.runtime.config.providers.map((p) => p.config.name),
        isNot(contains('n')),
      );
      expect(rig.runtime.config.defaultModel.id, 'm1');
      expect(rig.runtime.config.defaultModel.provider, 'a');
    });

    test('the group of provider fields is atomic (scenario "Атомарность '
        'группы полей провайдера")', () async {
      final rig = await _Rig.create();
      _put(rig.user, 'providers.k.base_url', 'https://other.test/v1');
      _put(rig.user, 'providers.k.models.km2', <String, Object?>{});

      final first = await rig.runtime.reloadConfig();

      expect(first.restartRequiredKeys, ['providers.k']);
      expect(rig.provider('k').config.baseUrl.toString(), 'https://k.test/v1');
      expect(rig.provider('k').models.keys, ['km', 'km2']);

      // Вторая правка — относительно исходного файла: меняются только
      // заголовки.
      _put(rig.user, 'providers.k.base_url', 'https://k.test/v1');
      _drop(rig.user, 'providers.k.models.km2');
      _put(rig.user, 'providers.k.headers', {'X-Team': 'new'});

      final second = await rig.runtime.reloadConfig();

      expect(second.restartRequiredKeys, ['providers.k']);
      expect(rig.provider('k').config.baseUrl.toString(), 'https://k.test/v1');
      expect(rig.provider('k').config.headers, isEmpty);
      expect(rig.provider('k').models.keys, ['km']);
      expect(rig.runtime.configStatus().pendingRestartKeys, ['providers.k']);
    });
  });

  // ---- доверие --------------------------------------------------------------

  group('trust is pinned to the initial snapshot', () {
    Map<String, Object?> project() => {
      'providers': {
        'pp': {
          'kind': 'openai-compatible',
          'base_url': 'https://pp.test/v1',
          'models': {'ppm': <String, Object?>{}},
        },
      },
      'mcp': {
        'servers': [_http('ph')],
      },
    };

    test('a project added to trusted_projects stays untrusted (scenario '
        '"Проект добавлен в trusted_projects")', () async {
      final port = _GatedPort();
      final rig = await _Rig.create(
        root: '/w/p',
        project: project(),
        projectFiles: port,
      );
      expect(rig.serverNames(), isEmpty);
      _put(rig.user, 'trusted_projects', ['/w/p']);

      final report = await rig.runtime.reloadConfig();
      await rig.session(cwd: '/w/p');

      expect(report.restartRequiredKeys, ['trusted_projects']);
      expect(rig.serverNames(), isEmpty);
      expect(
        rig.runtime.config.providers.map((p) => p.config.name),
        isNot(contains('pp')),
      );
      expect(rig.runtime.config.trustedProjects, isEmpty);
      expect(rig.runtime.config.withoutProject!.trustedProjects, isEmpty);
      expect(port.queries.single.projectTrusted, isFalse);
      expect(rig.runtime.configStatus().pendingRestartKeys, [
        'trusted_projects',
      ]);
    });

    test('a project removed from trusted_projects stays trusted (scenario '
        '"Доверие снято")', () async {
      final port = _GatedPort();
      final rig = await _Rig.create(
        root: '/w/p',
        user: withValues(_user(), {
          'trusted_projects': ['/w/p'],
        }),
        project: {
          ...project(),
          'permissions': {
            'tools': {'exec': 'allow'},
          },
        },
        projectFiles: port,
      );
      expect(rig.serverNames(), ['ph']);
      _drop(rig.user, 'trusted_projects');

      final report = await rig.runtime.reloadConfig();
      await rig.session(cwd: '/w/p');

      expect(report.restartRequiredKeys, ['trusted_projects']);
      expect(rig.serverNames(), ['ph']);
      expect(rig.runtime.config.trustedProjects, ['/w/p']);
      expect(rig.runtime.config.withoutProject!.trustedProjects, ['/w/p']);
      expect(
        rig.runtime.config.permissions.rules.toolPolicies['exec'],
        ToolPolicy.allow,
      );
      expect(port.queries.single.projectTrusted, isTrue);
    });

    test('checkConfig loads without applying, by the pinned trust, and '
        'names the deferred keys as Restart required (scenario '
        '"checkConfig")', () async {
      final rig = await _Rig.create(root: '/w/p', project: project());
      _put(rig.user, 'trusted_projects', ['/w/p']);
      _put(rig.user, 'budget.max_steps', 44);

      final result = await rig.runtime.checkConfig();

      expect(result.issues, isEmpty);
      expect(result.config!.trustedProjects, isEmpty);
      expect(
        [
          for (final w in result.warnings)
            if (w.event == 'config.reload.restart_required') w.key,
        ],
        ['trusted_projects'],
      );
      expect(rig.runtime.config.budget.maxSteps, 10, reason: 'not applied');
      expect(rig.modelsForCalls, isEmpty);
      expect(rig.runtime.configStatus().pendingRestartKeys, isEmpty);
    });

    test(
      'checkConfig reports load problems as the issues of the result',
      () async {
        final rig = await _Rig.create();
        _put(rig.user, 'budget.max_steps', 0);

        final result = await rig.runtime.checkConfig();

        expect(result.config, isNull);
        expect(result.issues.map((i) => i.key), ['budget.max_steps']);
        expect(rig.runtime.config.budget.maxSteps, 10);
        expect(
          rig.runtime.configStatus().lastIssues,
          isEmpty,
          reason: 'check does not touch the status',
        );
      },
    );
  });

  // ---- снимок без проекта (R0-1, ревью итерации 5) -------------------------

  group('the snapshot without the project is compared too (R0-1)', () {
    Map<String, Object?> project() => {
      'permissions': {'mode': 'standard'},
      'mcp': {
        'servers': [
          {'name': 's', 'enabled': false},
        ],
      },
    };

    test(
      'a user-layer edit hidden by the project layer is a restart key; '
      'a session outside the root keeps the old mode and has no server',
      () async {
        final rig = await _Rig.create(
          user: withValues(_user(), {
            'trusted_projects': ['/proj'],
            'permissions': {'mode': 'standard'},
          }),
          project: project(),
        );
        _put(rig.user, 'permissions.mode', 'bypass');
        _put(rig.user, 'mcp.servers', [_stdio('s', command: 'evil')]);

        final report = await rig.runtime.reloadConfig();

        expect(report.outcome, ConfigReloadOutcome.applied);
        expect(
          report.restartRequiredKeys,
          containsAll(['permissions.mode', 'mcp.servers[s]']),
        );
        final outside = rig.runtime.config.forSessionCwd('/elsewhere');
        expect(outside.permissions.mode, ModeId.standard);
        expect(outside.mcpServers.map((s) => s.name), isEmpty);
        expect(
          rig.runtime.config.permissions.mode,
          ModeId.standard,
          reason: 'the full snapshot is unchanged',
        );
        expect(
          rig.runtime.configStatus().pendingRestartKeys,
          containsAll(['permissions.mode', 'mcp.servers[s]']),
        );
      },
    );

    test('a harmless edit of the user layer under the project layer is '
        'applied to both snapshots', () async {
      final rig = await _Rig.create(
        user: withValues(_user(), {
          'trusted_projects': ['/proj'],
        }),
        project: project(),
      );
      _put(rig.user, 'budget.max_steps', 33);

      final report = await rig.runtime.reloadConfig();

      expect(report.restartRequiredKeys, isEmpty);
      expect(rig.runtime.config.budget.maxSteps, 33);
      expect(
        rig.runtime.config.forSessionCwd('/elsewhere').budget.maxSteps,
        33,
      );
    });
  });

  // ---- имена серверов со скобками и кавычками -------------------------------

  group('a server name that the key path cannot split stays deferred', () {
    for (final name in ['x]y', 'a[b]', 'q"r', 'a.b']) {
      test('stdio server "$name" is not in the snapshot', () async {
        final rig = await _Rig.create();
        _put(rig.user, 'mcp.servers', [_stdio(name, command: 'evil')]);

        final report = await rig.runtime.reloadConfig();

        expect(report.restartRequiredKeys, isNotEmpty);
        expect(rig.serverNames(), isNot(contains(name)));
        expect(
          rig.runtime.config.forSessionCwd('/elsewhere').mcpServers,
          isEmpty,
        );
      });
    }
  });

  // ---- checkConfig и validateSnapshot (ревью итерации 5) ---------------------

  group('checkConfig sees what reload would reject', () {
    test('a deferred reference to a vanished model is an issue of check, '
        'and reload says failed', () async {
      final rig = await _Rig.create();
      // Новый провайдер с ключом откладывается вместе со ссылкой на его
      // модель, а прежняя модель по умолчанию исчезла из каталога `a`:
      // перезагрузка отказывает, и `check` обязан сказать то же.
      _put(rig.user, 'providers.n', {
        'kind': 'openai-compatible',
        'base_url': 'https://n.test/v1',
        'api_key_secret': 'codelab/n',
        'models': {'m': <String, Object?>{}},
      });
      _put(rig.user, 'agent.default_model', 'n/m');
      _put(rig.user, 'providers.a.models', {'m2': <String, Object?>{}});

      final check = await rig.runtime.checkConfig();
      final report = await rig.runtime.reloadConfig();

      expect(report.outcome, ConfigReloadOutcome.failed);
      expect(check.issues.map((i) => i.key), contains('agent.default_model'));
    });
  });

  // ---- ModelOptionsChanged не буферизуется ------------------------------------

  group('ModelOptionsChanged is live only', () {
    test('a late subscriber does not get an old ModelOptionsChanged', () async {
      final rig = await _Rig.create();
      final session = await rig.session();
      final first = <AgentEvent>[];
      session.events.listen(first.add);
      _put(rig.user, 'providers.a.models', {
        'm1': <String, Object?>{},
        'm2': <String, Object?>{},
        'm3': <String, Object?>{},
      });

      await rig.runtime.reloadConfig();
      await pumpEventQueue();
      final late = <AgentEvent>[];
      session.events.listen(late.add);
      await pumpEventQueue();

      expect(first.whereType<ModelOptionsChanged>(), hasLength(1));
      expect(late.whereType<ModelOptionsChanged>(), isEmpty);
    });
  });

  // ---- withDeferred и validateSnapshot -------------------------------------

  group('CoreConfig.withDeferred and validateSnapshot', () {
    CoreConfig config(Map<String, Object?> user, {String root = '/proj'}) =>
        CoreConfig.fromLayers(
          [layer(user)],
          environment: const {},
          projectRoot: root,
        ).config!;

    test('only deferred parts come from the previous snapshot; the model '
        'list of a provider is new', () {
      final previous = config(_user());
      final next = config(
        withValues(_user(), {
          'providers': {
            'k': {
              'base_url': 'https://other.test/v1',
              'models': {'km2': <String, Object?>{}},
            },
          },
          'budget': {'max_steps': 99},
          'permissions': {'mode': 'bypass'},
        }),
      );

      final merged = CoreConfig.withDeferred(
        previous,
        next,
        const DeferredConfigParts(providers: {'k'}, permissions: true),
      );

      expect(merged.budget.maxSteps, 99);
      expect(merged.permissions, same(previous.permissions));
      final k = merged.providers.firstWhere((p) => p.config.name == 'k');
      final oldK = previous.providers.firstWhere((p) => p.config.name == 'k');
      expect(k.config, same(oldK.config));
      expect(k.key, same(oldK.key));
      expect(k.models.keys, ['km', 'km2']);
      expect(merged.trustedProjects, previous.trustedProjects);
    });

    test('a new provider and a reference to its model are excluded; a new '
        'stdio server is dropped, a changed one is the old one', () {
      final previous = config(
        withValues(_user(), {
          'mcp': {
            'servers': [
              _stdio('t', args: ['--a']),
            ],
          },
        }),
      );
      final next = config(
        withValues(_user(), {
          'providers': {
            'n': {
              'kind': 'openai-compatible',
              'base_url': 'https://n.test/v1',
              'api_key_secret': 'codelab/n',
              'models': {'m': <String, Object?>{}},
            },
          },
          'agent': {'default_model': 'n/m'},
          'mcp': {
            'servers': [
              _stdio('t', args: ['--b']),
              _stdio('x'),
            ],
          },
        }),
      );

      final merged = CoreConfig.withDeferred(
        previous,
        next,
        const DeferredConfigParts(
          providers: {'n'},
          defaultModel: true,
          servers: {'t', 'x'},
        ),
      );

      expect(merged.providers.map((p) => p.config.name), ['a', 'k']);
      expect(merged.defaultModel.id, previous.defaultModel.id);
      expect(merged.mcpServers.map((s) => s.name), ['t']);
      expect((merged.mcpServers.single as McpStdioServerConfig).args, ['--a']);
    });

    test('withoutProject gets the same treatment', () {
      CoreConfig withProject(Map<String, Object?> user, String budget) =>
          CoreConfig.fromLayers(
            [
              layer(user),
              layer({
                'budget': {'max_steps': int.parse(budget)},
              }, kind: ConfigLayerKind.project),
            ],
            environment: const {},
            projectRoot: '/proj',
          ).config!;
      final previous = withProject(_user(), '5');
      final next = withProject(
        withValues(_user(), {
          'permissions': {'mode': 'bypass'},
        }),
        '6',
      );

      final merged = CoreConfig.withDeferred(
        previous,
        next,
        const DeferredConfigParts(permissions: true),
      );

      expect(merged.permissions, same(previous.permissions));
      expect(
        merged.withoutProject!.permissions,
        same(previous.withoutProject!.permissions),
      );
    });

    test('validateSnapshot: the model by default must be in the catalog', () {
      final good = config(_user());
      final missing = CoreConfig(
        defaultModel: ModelRef(
          provider: 'zz',
          id: 'none',
          api: ProviderApi.openaiChat,
          baseUrl: Uri.parse('https://zz.test/v1'),
          contextWindow: 1000,
          maxOutputTokens: 100,
        ),
        providers: good.providers,
      );

      expect(good.validateSnapshot(), isEmpty);
      final issues = missing.validateSnapshot();
      expect(issues.map((i) => i.key), ['agent.default_model']);
      expect(issues.single.kind, ConfigIssueKind.value);
      expect(issues.single.message, isNot(contains('zz.test')));
    });

    test('a failed re-check makes the outcome failed: the deferred model '
        'by default is gone from the catalog', () async {
      final rig = await _Rig.create();
      // Модель по умолчанию переходит на отложенного провайдера, а прежняя
      // `a/m1` в том же файле удалена: после подстановки прежней ссылки её
      // нет в каталоге.
      _put(rig.user, 'providers.n', {
        'kind': 'openai-compatible',
        'base_url': 'https://n.test/v1',
        'api_key_secret': 'codelab/n',
        'models': {'m': <String, Object?>{}},
      });
      _put(rig.user, 'agent.default_model', 'n/m');
      _drop(rig.user, 'providers.a.models.m1');

      final report = await rig.runtime.reloadConfig();

      expect(report.outcome, ConfigReloadOutcome.failed);
      expect(report.issues.map((i) => i.key), ['agent.default_model']);
      expect(rig.runtime.config.defaultModel.id, 'm1');
      expect(rig.logger.eventsOf('config.reload.failed'), hasLength(1));
    });
  });
}

// ---- данные --------------------------------------------------------------

/// Пользовательский слой: провайдер без ключа `a` с моделями `m1`, `m2` и
/// провайдер с ключом `k`; модель по умолчанию `a/m1`, `budget.max_steps: 10`.
Map<String, Object?> _user() => {
  ...baseValues(),
  'providers': {
    'a': {
      'kind': 'openai-compatible',
      'base_url': 'https://a.test/v1',
      'models': {'m1': <String, Object?>{}, 'm2': <String, Object?>{}},
    },
    'k': {
      'kind': 'openai-compatible',
      'base_url': 'https://k.test/v1',
      'api_key_secret': 'codelab/k',
      'models': {'km': <String, Object?>{}},
    },
  },
  'agent': {'default_model': 'a/m1'},
  'budget': {'max_steps': 10},
};

Map<String, Object?> _http(String name, {Map<String, String>? headers}) => {
  'name': name,
  'type': 'http',
  'url': 'https://$name.test/mcp',
  'headers': ?headers,
};

Map<String, Object?> _stdio(
  String name, {
  String command = 'fake-mcp',
  bool enabled = true,
  List<String> args = const [],
  Map<String, String>? env,
}) => {
  'name': name,
  'type': 'stdio',
  'command': command,
  if (args.isNotEmpty) 'args': args,
  'env': ?env,
  if (!enabled) 'enabled': false,
};

/// Выполняет [body] в зоне, которая собирает необработанные ошибки (асинхронные
/// ошибки «в зоне хоста»). Сбой самого [body] (например, `expect`) пробрасывается
/// как обычно: иначе тест молча завис бы, ожидая завершения зоны.
Future<List<Object>> _inZone(Future<void> Function() body) {
  final errors = <Object>[];
  final done = Completer<List<Object>>();
  runZonedGuarded(() async {
    try {
      await body();
      done.complete(errors);
    } on Object catch (error, stack) {
      done.completeError(error, stack);
    }
  }, (error, stack) => errors.add(error));
  return done.future;
}

/// Копия дерева с типами `Map<String, Object?>` и `List<Object?>` на всех
/// уровнях: литералы теста выводят узкие типы, и правка по месту падала бы на
/// приведении.
Object? _deep(Object? node) => switch (node) {
  final Map<Object?, Object?> map => <String, Object?>{
    for (final entry in map.entries) entry.key! as String: _deep(entry.value),
  },
  final List<Object?> list => <Object?>[for (final item in list) _deep(item)],
  _ => node,
};

/// Кладёт [value] по пути из имён через точку (имена без точек и кавычек).
void _put(Map<String, Object?> root, String path, Object? value) {
  final names = path.split('.');
  var node = root;
  for (final name in names.take(names.length - 1)) {
    node =
        node.putIfAbsent(name, () => <String, Object?>{})!
            as Map<String, Object?>;
  }
  node[names.last] = value;
}

void _drop(Map<String, Object?> root, String path) {
  final names = path.split('.');
  var node = root;
  for (final name in names.take(names.length - 1)) {
    node = node[name]! as Map<String, Object?>;
  }
  node.remove(names.last);
}

// ---- стенд ---------------------------------------------------------------

/// Подставной [ConfigSource]: слои — изменяемые карты теста, `load()` —
/// настоящий `CoreConfig.fromLayers` с закреплённым доверием, как у
/// `FileConfigSource` (D7, D8).
///
/// Проблемы загрузки возвращает как есть (результат с `issues`), чтобы
/// `reloadConfig` их увидел; `patch` подменяет `values` (ключ вне реестра).
final class _FakeSource implements ConfigSource {
  _FakeSource(this._build);

  final ConfigLoadResult Function(List<String>? pinned) _build;
  late ConfigLoadResult _initial;
  final _changes = StreamController<void>.broadcast();

  /// Сколько раз вызван `load()`.
  var loads = 0;

  /// Пока не завершён, `load()` ждёт.
  Completer<void>? gate;

  /// Если задан, `load()` бросает его после ожидания.
  Object? failure;

  /// Подмена `values` результата.
  Map<String, Object?> Function(Map<String, Object?> values)? patch;

  void start() {
    _initial = _patched(_build(null));
    expect(_initial.issues, isEmpty, reason: _initial.issues.join('\n'));
  }

  ConfigLoadResult _patched(ConfigLoadResult result) {
    final patch = this.patch;
    if (patch == null || result.config == null) {
      return result;
    }
    return ConfigLoadResult(
      config: result.config,
      host: result.host,
      warnings: result.warnings,
      sources: result.sources,
      values: patch(result.values),
    );
  }

  /// Значения `rebase` каждого вызова `load` — по ним тест проверяет, что
  /// `checkConfig` не сдвигает базу наблюдателя (D7, D8).
  final List<bool> rebaseFlags = [];

  @override
  ConfigLoadResult get initial => _initial;

  @override
  Future<ConfigLoadResult> load({bool rebase = true}) async {
    loads++;
    rebaseFlags.add(rebase);
    if (gate case final gate?) {
      await gate.future;
    }
    if (failure case final error?) {
      throw error;
    }
    return _patched(_build(_initial.config!.trustedProjects));
  }

  @override
  Stream<void> get changes => _changes.stream;

  bool get listened => _changes.hasListener;

  void signal() => _changes.add(null);
}

/// Порт файлов проекта, который запоминает запросы и умеет ждать.
final class _GatedPort implements ProjectFilesSource {
  final queries = <ProjectFilesQuery>[];
  Completer<ProjectFiles>? gate;

  @override
  Future<ProjectFiles> load(ProjectFilesQuery query) async {
    queries.add(query);
    return gate?.future ?? ProjectFiles.empty;
  }
}

/// Память, раскрывающая любой путь в себя: сессии в `/w/p` получают
/// раскрытый `realpath` и могут быть доверенными.
final class _ResolvingEnv implements ExecutionEnv, PathResolver {
  final _inner = MemoryExecutionEnv(cwd: '/proj');

  @override
  String get cwd => _inner.cwd;

  @override
  Future<Result<String, FileError>> realpath(String path) async => Ok(path);

  @override
  Future<Result<String, FileError>> readText(
    String path, {
    int? line,
    int? limit,
  }) => _inner.readText(path, line: line, limit: limit);

  @override
  Future<Result<void, FileError>> writeText(String path, String content) =>
      _inner.writeText(path, content);

  @override
  Future<Result<FileStat, FileError>> stat(String path) => _inner.stat(path);

  @override
  Future<Result<ExecResult, ExecError>> exec(
    String command,
    ExecOptions options,
  ) => _inner.exec(command, options);
}

final class _Rig {
  _Rig._({
    required this.user,
    required this.source,
    required this.built,
    required this.logger,
    required this.clock,
    required this.modelsForCalls,
    required this.streamTags,
    required this.secrets,
    required this.secretsStore,
    required this.root,
    required this.store,
    required this.manual,
  });

  static Future<_Rig> create({
    Map<String, Object?>? user,
    Map<String, Object?>? project,
    String root = '/proj',
    Map<String, String> environment = const {},
    bool withSource = true,
    bool withModelsFor = true,
    bool failModels = false,
    ProjectFilesSource? projectFiles,
    List<Map<String, Object?>>? steps,
    bool hold = false,
    Map<String, Object?> Function(Map<String, Object?> values)? patchValues,
  }) async {
    final userValues = _deep(user ?? _user())! as Map<String, Object?>;
    final clock = FakeClock();
    final logger = RecordingLogger(clock: clock);
    final manual = hold ? ManualStream(clock) : null;
    final modelsForCalls = <CoreConfig>[];
    final streamTags = <String>[];
    final scripted = ScriptedStreamFunction.fromJson({
      'steps': steps ?? [for (var i = 0; i < 40; i++) textStep('ok')],
    }, clock: clock);
    StreamFunction tagged(String tag) => (ref, context, {cancel}) {
      streamTags.add(tag);
      if (tag == 'init' && manual != null) {
        return manual.call(ref, context, cancel: cancel);
      }
      return scripted.call(ref, context, cancel: cancel);
    };
    final secretsStore = FakeSecretStore();
    final store = MemorySessionStore();
    final secrets = SecretResolver(
      store: secretsStore,
      environment: const {},
      logger: logger,
    );

    final source =
        _FakeSource(
            (pinned) => CoreConfig.fromLayers(
              [
                layer(userValues),
                if (project != null)
                  layer(
                    _deep(project)! as Map<String, Object?>,
                    kind: ConfigLayerKind.project,
                    source: '$root/.codelab/config.yaml',
                  ),
              ],
              environment: environment,
              projectRoot: root,
              pinnedTrustedProjects: pinned,
            ),
          )
          ..patch = patchValues
          ..start();

    ModelCatalog catalogOf(CoreConfig config) =>
        StaticModelCatalog(config.providers, logger: logger);

    ConfiguredModels makeModels(CoreConfig config) {
      if (failModels) {
        throw StateError('models are not built');
      }
      modelsForCalls.add(config);
      return (
        stream: tagged('m${modelsForCalls.length}'),
        catalog: catalogOf(config),
      );
    }

    final initial = source.initial.config!;
    final built = buildAgentCore(
      profile: HostProfile.of(
        'agent-serve',
      ).narrowed({...inMemoryJournal, ...noExec}),
      services: AgentCoreServices(
        baseEnv: _ResolvingEnv(),
        logger: logger,
        clock: clock,
        ids: SequentialIdGenerator(),
        sessions: store,
        models: catalogOf(initial),
        projectFiles: projectFiles,
        secrets: secrets,
        config: withSource ? source : null,
      ),
      config: initial,
      streamFunction: tagged('init'),
      modelsFor: withModelsFor ? makeModels : null,
    );
    return _Rig._(
      user: userValues,
      source: source,
      built: built,
      logger: logger,
      clock: clock,
      modelsForCalls: modelsForCalls,
      streamTags: streamTags,
      secrets: secrets,
      secretsStore: secretsStore,
      root: root,
      store: store,
      manual: manual,
    );
  }

  final Map<String, Object?> user;
  final _FakeSource source;
  final BuiltAgentCore built;
  final RecordingLogger logger;
  final FakeClock clock;
  final List<CoreConfig> modelsForCalls;
  final List<String> streamTags;
  final SecretResolver secrets;
  final FakeSecretStore secretsStore;
  final String root;
  final MemorySessionStore store;
  final ManualStream? manual;

  /// Текст журнала сессии.
  String journalOf(AgentSession session) => store.textOf(session.id) ?? '';

  AgentRuntimeImpl get runtime => built.runtime as AgentRuntimeImpl;

  Future<AgentSession> session({String? cwd}) =>
      runtime.createSession(SessionSpec(cwd: cwd ?? root));

  CatalogProvider provider(String id) =>
      runtime.config.providers.firstWhere((p) => p.config.name == id);

  List<String> serverNames() => [
    for (final s in runtime.config.mcpServers) s.name,
  ];

  McpServerConfig server(String name) =>
      runtime.config.mcpServers.firstWhere((s) => s.name == name);
}
