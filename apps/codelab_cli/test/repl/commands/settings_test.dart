// `/settings` в REPL (задача 4.3 change `add-provider-setup-ui`; spec
// codelab-cli «Команды /provider и /settings в REPL и TUI», сценарии
// «Изменение настройки», «Секретный ключ не редактируется», «Удалённый
// агент»; design.md D17, решение Q15).
//
// Строки берутся из `settingFieldsOf(AgentConfigSnapshot)` моста (задача
// 4.0a, `SettingFieldView`: `key`, `descriptor`, `value`, `source`,
// `sourceName`, `displayValue`, `restartRequired`, `editable`); запись — через
// `AgentConfigStore` порта `SetupCommands.configStore`. Порт и хранилище —
// фейки (`test/support/setup_repl_harness.dart`, `setup_fakes.dart`).
// Значения настроек выдуманные, настоящий `~/.codelab` не читается.

import 'package:codelab_cli/codelab_cli.dart';
import 'package:codelab_client_core/codelab_client_core.dart'
    show ConnectionProfile, StdioProfile;
import 'package:codelab_setup/codelab_setup.dart';
import 'package:test/test.dart';

import '../../support/setup_fakes.dart';
import '../../support/setup_repl_harness.dart';

/// Ожидаемый формат ошибки разбора — из самого реестра, как у
/// `codelab config set`.
String expectedFormat(String key, String raw) {
  try {
    SettingsRegistry.parseCliValue(SettingsRegistry.lookup(key)!, raw);
  } on ConfigValueException catch (error) {
    return error.expected;
  }
  throw StateError('значение "$raw" ключа $key разобрано');
}

void main() {
  group('доступ', accessTests);
  late SetupReplHarness repl;
  var opened = false;

  Future<void> open({
    AgentConfigSnapshot? snapshot,
    ConnectionProfile profile = editableProfile,
  }) async {
    repl = SetupReplHarness(profile: profile, snapshot: snapshot);
    opened = true;
    await repl.start();
  }

  tearDown(() async {
    if (opened) {
      await repl.dispose();
    }
    opened = false;
  });

  /// Выполняет команду и ждёт [text] в её выводе.
  Future<void> run(String line, String text) async {
    repl.line(line);
    await repl.waitText(text);
  }

  group('/settings без аргументов: строки key value source', () {
    test('источники default, user, local, project, config и env', () async {
      await open(
        snapshot: snapshotOf(
          user: {
            'agent': {'effort': 'high'},
          },
          projectLocal: {
            'budget': {'max_steps': 7},
          },
          project: {
            'compaction': {'enabled': true},
          },
          values: {
            'agent.effort': 'high',
            'budget.max_steps': 7,
            'compaction.enabled': true,
            'logging.level': 'debug',
            'permissions.mode': 'ask',
          },
          external: {
            'logging.level': ConfigSourceKind.environment,
            'permissions.mode': ConfigSourceKind.extraFile,
          },
        ),
      );

      repl.line('/settings');
      await repl.waitText('agent.effort');

      final out = repl.lastOutput;
      expect(out, contains(RegExp(r'agent\.effort\s+high\s+user')));
      expect(out, contains(RegExp(r'budget\.max_steps\s+7\s+local')));
      expect(out, contains(RegExp(r'compaction\.enabled\s+true\s+project')));
      expect(out, contains(RegExp(r'logging\.level\s+debug\s+env')));
      expect(out, contains(RegExp(r'permissions\.mode\s+ask\s+config')));
      expect(
        out,
        contains(RegExp(r'agent\.default_model\s+\(not set\)\s+default')),
      );
    });

    test('PickerSpec: по строке на ключ scope shared, пункт запускает '
        '/settings <key>', () async {
      final snapshot = snapshotOf(
        user: {
          'agent': {'effort': 'high'},
        },
      );
      final context = _Context(
        profile: editableProfile,
        setup: FakeSetupCommands(
          configStore: FakeConfigStore(snapshotValue: snapshot),
          check: FakeProviderCheck(),
          keys: FakeProviderKeys(),
        ),
      );

      await _command('settings').run(context, const []);

      final spec = context.picked.single;
      final rows = settingFieldsOf(snapshot);
      expect(
        [for (final i in spec.items) i.line],
        [for (final r in rows) '/settings ${r.key}'],
      );
      final effort = spec.items.singleWhere(
        (i) => i.line == '/settings agent.effort',
      );
      expect(effort.label, contains(RegExp(r'agent\.effort\s+high\s+user')));
      expect(spec.action, PickerAction.run);
      expect(
        spec.items.any((i) => i.line == '/settings trusted_projects'),
        isTrue,
        reason: 'trusted_projects показывается',
      );
      expect(
        spec.items.any((i) => i.label.contains('agent.fallback')),
        isFalse,
        reason: 'fileOnly-ключи строк не имеют',
      );
    });
  });

  group('/settings <key>: пикер значений или подсказка формата', () {
    test('enumeration: значения реестра, текущее отмечено', () async {
      final snapshot = snapshotOf(
        user: {
          'agent': {'effort': 'high'},
        },
      );
      final context = _Context(
        profile: editableProfile,
        setup: FakeSetupCommands(
          configStore: FakeConfigStore(snapshotValue: snapshot),
          check: FakeProviderCheck(),
          keys: FakeProviderKeys(),
        ),
      );

      await _command('settings').run(context, const ['agent.effort']);

      final spec = context.picked.single;
      expect(
        [for (final i in spec.items) i.line],
        [
          '/settings agent.effort low',
          '/settings agent.effort medium',
          '/settings agent.effort high',
        ],
      );
      expect(spec.current, 2);
      expect(spec.action, PickerAction.run);
    });

    test('bool: true и false', () async {
      final snapshot = snapshotOf();
      final context = _Context(
        profile: editableProfile,
        setup: FakeSetupCommands(
          configStore: FakeConfigStore(snapshotValue: snapshot),
          check: FakeProviderCheck(),
          keys: FakeProviderKeys(),
        ),
      );

      await _command('settings').run(context, const ['compaction.enabled']);

      expect(
        [for (final i in context.picked.single.items) i.line],
        [
          '/settings compaction.enabled true',
          '/settings compaction.enabled false',
        ],
      );
    });

    test('число: подсказка формата, пикера нет, запись не идёт', () async {
      await open();

      await run('/settings budget.max_steps', 'budget.max_steps');

      expect(
        repl.lastOutput,
        contains(expectedFormat('budget.max_steps', 'x')),
      );
      expect(repl.store.applied, isEmpty);
    });
  });

  group('запись: Updated / Removed и слой', () {
    test(
      '/settings agent.effort high → слой user, «Updated … in <path>»',
      () async {
        await open();

        await run(
          '/settings agent.effort high',
          'Updated agent.effort in /h/config.yaml',
        );

        final applied = repl.store.applied.single;
        expect(applied.base.target, const ConfigTarget.user());
        expect(applied.edits, [const SetValue('agent.effort', 'high')]);
        expect(repl.lastOutput, isNot(contains('applies after restart')));
      },
    );

    test('после записи список показывает «agent.effort high user»', () async {
      await open();
      await run('/settings agent.effort high', 'Updated agent.effort');
      // Хранилище отдаёт новый снимок, как файловое после записи.
      repl.store.snapshotValue = snapshotOf(
        user: {
          'agent': {'effort': 'high'},
        },
      );

      repl.line('/settings');

      await repl.waitText('agent.effort');
      expect(repl.lastOutput, contains(RegExp(r'agent\.effort\s+high\s+user')));
    });

    test('число разбирается типом ключа', () async {
      await open();

      await run('/settings budget.max_steps 5', 'Updated budget.max_steps');

      expect(repl.store.applied.single.edits, [
        const SetValue('budget.max_steps', 5),
      ]);
    });

    test('--local пишет в projectLocal текущей папки', () async {
      await open(snapshot: snapshotOf(projectLocal: const {}));

      await run(
        '/settings agent.effort high --local',
        'Updated agent.effort in /work/.codelab/config.local.yaml',
      );

      final applied = repl.store.applied.single;
      expect(applied.base.target, const ConfigTarget.projectLocal('/work'));
      expect(applied.edits, [const SetValue('agent.effort', 'high')]);
    });

    test('restartRequired: пометка «(applies after restart)» в той же '
        'строке', () async {
      await open();

      await run(
        '/settings permissions.mode ask',
        'Updated permissions.mode in /h/config.yaml (applies after restart)',
      );
    });

    test(
      '--reset: «Removed <key> from <path>», UnsetValue в слое user',
      () async {
        await open(
          snapshot: snapshotOf(
            user: {
              'agent': {'effort': 'high'},
            },
          ),
        );

        await run(
          '/settings agent.effort --reset',
          'Removed agent.effort from /h/config.yaml',
        );

        final applied = repl.store.applied.single;
        expect(applied.base.target, const ConfigTarget.user());
        expect(applied.edits, [const UnsetValue('agent.effort')]);
      },
    );

    test('--reset restartRequired-ключа — с пометкой', () async {
      await open(
        snapshot: snapshotOf(
          user: {
            'permissions': {'mode': 'ask'},
          },
        ),
      );

      await run(
        '/settings permissions.mode --reset',
        'Removed permissions.mode from /h/config.yaml (applies after restart)',
      );
    });

    test('--reset ключа, которого нет в слое: «<key> is not set in <path>», '
        'записи нет', () async {
      await open();

      await run(
        '/settings agent.effort --reset',
        'agent.effort is not set in /h/config.yaml',
      );

      expect(repl.store.applied, isEmpty);
    });

    test('--reset --local работает по слою projectLocal', () async {
      await open(
        snapshot: snapshotOf(
          projectLocal: {
            'agent': {'effort': 'low'},
          },
        ),
      );

      await run(
        '/settings agent.effort --reset --local',
        'Removed agent.effort from /work/.codelab/config.local.yaml',
      );

      expect(
        repl.store.applied.single.base.target,
        const ConfigTarget.projectLocal('/work'),
      );
    });
  });

  group('слой 3 (проектный config.yaml) не пишется (SETUP-3)', () {
    test('ключ из проектного слоя пишется в user, не в project', () async {
      await open(
        snapshot: snapshotOf(
          project: {
            'budget': {'max_steps': 9},
          },
        ),
      );

      await run(
        '/settings budget.max_steps 3',
        'Updated budget.max_steps in /h/config.yaml',
      );

      expect(repl.store.applied.single.base.target, const ConfigTarget.user());
      for (final call in repl.store.applied) {
        expect(call.base.target.layer, isNot(ConfigLayer.project));
      }
    });

    test('--reset ключа проектного слоя не трогает слой 3', () async {
      await open(
        snapshot: snapshotOf(
          project: {
            'budget': {'max_steps': 9},
          },
        ),
      );

      await run(
        '/settings budget.max_steps --reset',
        'budget.max_steps is not set in /h/config.yaml',
      );

      expect(repl.store.applied, isEmpty);
    });
  });

  group('отказы без записи', () {
    final external = snapshotOf(
      values: const {'budget.max_steps': 9, 'agent.effort': 'high'},
      external: const {
        'budget.max_steps': ConfigSourceKind.environment,
        'agent.effort': ConfigSourceKind.extraFile,
      },
    );

    test(
      'источник env: «<key> is set by env; it cannot be changed here.»',
      () async {
        await open(snapshot: external);

        await run(
          '/settings budget.max_steps 5',
          'budget.max_steps is set by env; it cannot be changed here.',
        );
        await run(
          '/settings budget.max_steps --reset',
          'budget.max_steps is set by env; it cannot be changed here.',
        );

        expect(repl.store.applied, isEmpty);
      },
    );

    test('источник config: «<key> is set by config; …»', () async {
      await open(snapshot: external);

      await run(
        '/settings agent.effort low',
        'agent.effort is set by config; it cannot be changed here.',
      );
      await run(
        '/settings agent.effort --reset --local',
        'agent.effort is set by config; it cannot be changed here.',
      );

      expect(repl.store.applied, isEmpty);
    });

    test('ошибка разбора: «<key>: expected <expected>», значение не '
        'цитируется', () async {
      await open();

      repl.line('/settings budget.max_steps abc-$leakMarker');
      await repl.waitText('budget.max_steps: expected');

      expect(
        repl.lastOutput,
        contains(
          'budget.max_steps: expected '
          '${expectedFormat('budget.max_steps', 'x')}',
        ),
      );
      // Эхо введённой строки — вывод самого REPL; ошибка значения не цитирует.
      expect(
        _errorLine(repl.lastOutput, 'expected'),
        isNot(contains(leakMarker)),
      );
      expect(repl.store.applied, isEmpty);
    });

    test('значение вне enumeration: ожидаемые значения реестра', () async {
      await open();

      await run(
        '/settings agent.effort turbo',
        'agent.effort: expected ${expectedFormat('agent.effort', 'turbo')}',
      );

      expect(_errorLine(repl.lastOutput, 'expected'), isNot(contains('turbo')));
      expect(repl.store.applied, isEmpty);
    });

    test('неизвестный ключ и ключ не shared: Unknown setting', () async {
      await open();
      const unknown = 'Unknown setting nope.key. Run /settings to list them.';

      await run('/settings nope.key 1', unknown);
      await run('/settings nope.key', unknown);
      await run('/settings nope.key --reset', unknown);
      // `agent.fallback` — fileOnly, редактора нет.
      await run(
        '/settings agent.fallback x',
        'Unknown setting agent.fallback. Run /settings to list them.',
      );

      expect(repl.store.applied, isEmpty);
    });

    test(
      'секретный ключ не редактируется: Use codelab secret set <name>',
      () async {
        await open();

        await run(
          '/settings providers.openai.api_key_secret x',
          'Use codelab secret set <name>',
        );
        await run(
          '/settings providers.openai.api_key_secret --reset',
          'Use codelab secret set <name>',
        );

        expect(repl.store.applied, isEmpty);
      },
    );
  });

  group('исходы записи', () {
    test('ConfigConflict → «The config file changed; run the command '
        'again.»', () async {
      await open();
      repl.store.outcome = const ConfigConflict('/h/config.yaml');

      await run(
        '/settings agent.effort high',
        'The config file changed; run the command again.',
      );

      expect(repl.lastOutput, isNot(contains('Updated')));
    });

    test('ConfigRejected → «codelab: <key>: <текст проблемы>»', () async {
      await open();
      repl.store.outcome = const ConfigRejected([
        ConfigIssue(
          kind: ConfigIssueKind.value,
          key: 'budget.max_steps',
          source: '/h/config.yaml',
          message: 'must be at least 1',
        ),
      ]);

      await run(
        '/settings budget.max_steps 5',
        'codelab: budget.max_steps: must be at least 1',
      );
    });

    test('ConfigInlineSecret → Use codelab secret set …', () async {
      await open();
      repl.store.outcome = const ConfigInlineSecret(
        key: 'agent.effort',
        suggestedSecretName: 'codelab/x',
      );

      await run('/settings agent.effort high', 'Use codelab secret set');
    });
  });

  group('чьи настройки: resolveSettingsAccess профиля подключения '
      '(SETUP-2)', () {
    test('удалённый агент: запись и сброс — строка только для чтения, '
        'конфиг не пишется', () async {
      await open(profile: remoteProfile);

      await run('/settings agent.effort high', remoteReadOnlyText);
      await run('/settings agent.effort --reset', remoteReadOnlyText);

      expect(repl.store.applied, isEmpty);
    });

    test('чужой stdio-агент: «managed by <имя>»', () async {
      await open(profile: foreignProfile);

      await run(
        '/settings agent.effort high',
        'Provider settings are managed by agent.',
      );

      expect(repl.store.applied, isEmpty);
    });
  });
}

void accessTests() {
  late SetupReplHarness repl;
  var opened = false;

  Future<void> open(ConnectionProfile profile) async {
    repl = SetupReplHarness(profile: profile);
    opened = true;
    await repl.start();
  }

  tearDown(() async {
    if (opened) {
      await repl.dispose();
    }
    opened = false;
  });

  group('trusted_projects: граница доверия', () {
    test('показывается в списке, но запись и сброс отказываются', () async {
      await open(editableProfile);
      const refusal =
          'trusted_projects is a trust boundary; it cannot be changed here.';

      repl.line('/settings trusted_projects');
      await repl.waitText(refusal);
      expect(repl.lastOutput, isNot(contains('Set it with')));
      repl.line('/settings trusted_projects /x');
      await repl.waitText(refusal);
      repl.line('/settings trusted_projects --reset');
      await repl.waitText(refusal);
      repl.line('/settings trusted_projects /x --local');
      await repl.waitText(refusal);

      expect(repl.store.applied, isEmpty);
    });
  });

  group('чьи настройки: пути из EditableSettings профиля (D5, SETUP-2)', () {
    test('CODELAB_HOME из env профиля и --config из его аргументов идут в '
        'порт', () async {
      await open(
        const StdioProfile(
          id: 'p',
          label: 'P',
          command: '/opt/bin/codelab-agent',
          args: ['serve', '--stdio', '--config', '/x/extra.yaml'],
          env: {'CODELAB_HOME': '/other', 'GW_KEY': 'value'},
        ),
      );

      repl.line('/settings agent.effort high');
      await repl.waitText('Updated agent.effort');

      final access = repl.setup.accessSeen.first;
      expect(access.paths.codelabHome, '/other');
      // Весь `env` профиля идёт в порт (api_key_env, источник env).
      expect(repl.setup.scopeSeen.first.env['GW_KEY'], 'value');
      expect(repl.setup.scopeSeen.first.cwd, '/work');
      expect(access.paths.extraConfig, '/x/extra.yaml');
      expect(
        access.paths.projectDir,
        isNull,
        reason: 'нет runInProjectDirectory',
      );
    });

    test('runInProjectDirectory даёт папку проекта', () async {
      await open(editableProfile);

      repl.line('/settings agent.effort high');
      await repl.waitText('Updated agent.effort');

      expect(repl.setup.accessSeen.first.paths.projectDir, '/work');
    });

    test(
      '--local без цели projectLocal: строка отказа, запись не идёт',
      () async {
        await open(editableNoProjectProfile);
        const line =
            'This agent has no project-local config; run without --local.';

        repl.line('/settings agent.effort high --local');
        await repl.waitText(line);
        repl.line('/settings agent.effort --reset --local');
        await repl.waitText(line);

        expect(repl.store.applied, isEmpty);
      },
    );
  });
}

/// Строка вывода с [needle], без эха введённой команды.
String _errorLine(String output, String needle) => output
    .split('\n')
    .firstWhere((l) => l.contains(needle) && !l.contains('> /settings'));

ReplCommand _command(String name) =>
    replCommands.singleWhere((c) => c.name == name);

/// Контекст без терминала: записывает, что команда попросила (как в
/// `narrow_context_test.dart`).
final class _Context implements ReplContext {
  _Context({required this.profile, required this.setup});

  @override
  final ConnectionProfile profile;

  @override
  final SetupCommands setup;

  final said = <String>[];
  final picked = <PickerSpec>[];

  @override
  String get cwd => '/work';

  @override
  void say(String text) => said.add(text);

  @override
  void pick(PickerSpec spec) => picked.add(spec);

  @override
  Object? noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
