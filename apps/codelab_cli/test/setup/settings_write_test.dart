// `applySetting` и `settingWriteLayerOf` (задача 4.8b change
// `add-provider-setup-ui`; design.md D17, Q15, D24; SETUP-3, SETUP-6).
// Хранилище — фейк `FakeConfigStore`; значения выдуманные.

import 'package:codelab_cli/src/setup/settings_rows.dart';
import 'package:codelab_setup/codelab_setup.dart';
import 'package:test/test.dart';

import '../support/setup_fakes.dart';

void main() {
  late FakeConfigStore store;

  AgentConfigSnapshot snapshot({
    Map<String, Object?> user = const {},
    Map<String, Object?>? projectLocal,
    Map<String, Object?>? project,
    Map<String, Object?> values = const {},
    Map<String, ConfigSourceKind> external = const {},
  }) {
    final snap = snapshotOf(
      user: user,
      projectLocal: projectLocal,
      project: project,
      values: values,
      external: external,
    );
    store = FakeConfigStore(snapshotValue: snap);
    return snap;
  }

  Future<String> apply(
    AgentConfigSnapshot snap,
    String key, {
    String? raw,
    ConfigLayer layer = ConfigLayer.user,
  }) => applySetting(store, snap, key, raw: raw, layer: layer);

  group('applySetting: строки исходов D17', () {
    test('запись: Updated … in <path>', () async {
      final snap = snapshot();

      expect(
        await apply(snap, 'agent.effort', raw: 'high'),
        'Updated agent.effort in /h/config.yaml',
      );
      expect(store.applied.single.edits, [
        const SetValue('agent.effort', 'high'),
      ]);
      expect(store.applied.single.base.target, const ConfigTarget.user());
    });

    test('restartRequired: пометка в той же строке', () async {
      final snap = snapshot();

      expect(
        await apply(snap, 'permissions.mode', raw: 'ask'),
        'Updated permissions.mode in /h/config.yaml (applies after restart)',
      );
    });

    test('слой projectLocal пишется в свой файл', () async {
      final snap = snapshot(projectLocal: const {});

      expect(
        await apply(
          snap,
          'agent.effort',
          raw: 'low',
          layer: ConfigLayer.projectLocal,
        ),
        'Updated agent.effort in /work/.codelab/config.local.yaml',
      );
    });

    test('сброс: Removed … from <path> и is not set in <path>', () async {
      final set = snapshot(
        user: {
          'agent': {'effort': 'high'},
        },
      );
      expect(
        await apply(set, 'agent.effort'),
        'Removed agent.effort from /h/config.yaml',
      );
      expect(store.applied.single.edits, [const UnsetValue('agent.effort')]);

      final unset = snapshot();
      expect(
        await apply(unset, 'agent.effort'),
        'agent.effort is not set in /h/config.yaml',
      );
      expect(store.applied, isEmpty);
    });

    test('сброс restartRequired-ключа — с пометкой', () async {
      final snap = snapshot(
        user: {
          'permissions': {'mode': 'ask'},
        },
      );

      expect(
        await apply(snap, 'permissions.mode'),
        'Removed permissions.mode from /h/config.yaml (applies after restart)',
      );
    });

    test('ошибка разбора: «<key>: expected …» без значения', () async {
      final snap = snapshot();

      final line = await apply(
        snap,
        'budget.max_steps',
        raw: 'abc-$leakMarker',
      );

      expect(line, startsWith('budget.max_steps: expected '));
      expect(line, isNot(contains(leakMarker)));
      expect(store.applied, isEmpty);
    });

    test(
      'список правится строкой: stringList — JSON-массив по parseCliValue',
      () async {
        final snap = snapshot();

        await apply(snap, 'permissions.deny', raw: '["bash:rm*","bash:sudo*"]');

        final edit = store.applied.single.edits.single as SetValue;
        expect(edit.key, 'permissions.deny');
        expect(edit.value, isA<List<Object?>>());
      },
    );
  });

  group('applySetting: отказы без записи', () {
    test('неизвестный ключ и не shared', () async {
      final snap = snapshot();

      for (final key in ['nope.key', 'agent.fallback']) {
        expect(
          await apply(snap, key, raw: '1'),
          'Unknown setting $key. Run /settings to list them.',
        );
      }
      expect(store.applied, isEmpty);
    });

    test('trusted_projects: граница доверия, и запись, и сброс', () async {
      final snap = snapshot();

      expect(
        await apply(snap, 'trusted_projects', raw: '/x'),
        'trusted_projects is a trust boundary; it cannot be changed here.',
      );
      expect(
        await apply(snap, 'trusted_projects'),
        'trusted_projects is a trust boundary; it cannot be changed here.',
      );
      expect(store.applied, isEmpty);
    });

    test('секретный ключ', () async {
      final snap = snapshot();

      expect(
        await apply(snap, 'providers.openai.api_key_secret', raw: 'x'),
        'Use codelab secret set <name>',
      );
      expect(store.applied, isEmpty);
    });

    test('источники env и config', () async {
      final snap = snapshot(
        values: const {'budget.max_steps': 9, 'agent.effort': 'high'},
        external: const {
          'budget.max_steps': ConfigSourceKind.environment,
          'agent.effort': ConfigSourceKind.extraFile,
        },
      );

      expect(
        await apply(snap, 'budget.max_steps', raw: '5'),
        'budget.max_steps is set by env; it cannot be changed here.',
      );
      expect(
        await apply(snap, 'agent.effort'),
        'agent.effort is set by config; it cannot be changed here.',
      );
      expect(store.applied, isEmpty);
    });

    test('нечитаемый слой', () async {
      final snap = snapshot();

      expect(
        await apply(
          snap,
          'agent.effort',
          raw: 'high',
          layer: ConfigLayer.projectLocal,
        ),
        'Cannot read the local config file; run "codelab config check".',
      );
    });
  });

  group('applySetting: исходы apply', () {
    test('конфликт — без автоповтора', () async {
      final snap = snapshot();
      store.outcome = const ConfigConflict('/h/config.yaml');

      expect(
        await apply(snap, 'agent.effort', raw: 'high'),
        'The config file changed; run the command again.',
      );
      expect(store.applied, hasLength(1));
    });

    test('отклонён валидатором и литеральный секрет', () async {
      final snap = snapshot();
      store.outcome = const ConfigRejected([
        ConfigIssue(
          kind: ConfigIssueKind.value,
          key: 'budget.max_steps',
          source: '/h/config.yaml',
          message: 'must be at least 1',
        ),
      ]);
      expect(
        await apply(snap, 'budget.max_steps', raw: '5'),
        'codelab: budget.max_steps: must be at least 1',
      );

      store.outcome = const ConfigInlineSecret(
        key: 'agent.effort',
        suggestedSecretName: 'codelab/x',
      );
      expect(
        await apply(snap, 'agent.effort', raw: 'high'),
        'Use codelab secret set codelab/x',
      );
    });
  });

  group('settingWriteLayerOf: слой записи оверлея (D17, D24)', () {
    EditableSettings access({bool withLocal = true}) => EditableSettings(
      ConfigPaths(codelabHome: '/h', projectDir: withLocal ? '/work' : null),
    );

    SettingFieldView rowOf(AgentConfigSnapshot snap, String key) =>
        settingRowsOf(snap).singleWhere((r) => r.key == key);

    test('default и user → user', () {
      final snap = snapshot(
        user: {
          'agent': {'effort': 'high'},
        },
      );

      expect(
        settingWriteLayerOf(
          rowOf(snap, 'agent.effort'),
          access(),
          toUser: false,
        ),
        ConfigLayer.user,
      );
      expect(
        settingWriteLayerOf(
          rowOf(snap, 'budget.max_steps'),
          access(),
          toUser: false,
        ),
        ConfigLayer.user,
      );
    });

    test('local → projectLocal', () {
      final snap = snapshot(
        projectLocal: {
          'budget': {'max_steps': 7},
        },
      );

      expect(
        settingWriteLayerOf(
          rowOf(snap, 'budget.max_steps'),
          access(),
          toUser: false,
        ),
        ConfigLayer.projectLocal,
      );
    });

    test('project → projectLocal, хотя editable у строки false; без цели — '
        'user', () {
      final snap = snapshot(
        project: {
          'budget': {'max_steps': 9},
        },
      );
      final row = rowOf(snap, 'budget.max_steps');

      expect(row.editable, isFalse);
      expect(
        settingWriteLayerOf(row, access(), toUser: false),
        ConfigLayer.projectLocal,
      );
      expect(
        settingWriteLayerOf(row, access(withLocal: false), toUser: false),
        ConfigLayer.user,
      );
    });

    test('Ctrl+U (toUser) → user для любого источника, кроме внешнего', () {
      final snap = snapshot(
        projectLocal: {
          'budget': {'max_steps': 7},
        },
      );

      expect(
        settingWriteLayerOf(
          rowOf(snap, 'budget.max_steps'),
          access(),
          toUser: true,
        ),
        ConfigLayer.user,
      );
    });

    test('config и env → null', () {
      final snap = snapshot(
        values: const {'budget.max_steps': 9},
        external: const {'budget.max_steps': ConfigSourceKind.environment},
      );

      expect(
        settingWriteLayerOf(
          rowOf(snap, 'budget.max_steps'),
          access(),
          toUser: false,
        ),
        isNull,
      );
    });
  });
}
