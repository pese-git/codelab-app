// Экран `/settings` как модальный экран ядра TUI (задача 4.12 change
// `add-provider-setup-ui`; codelab-cli «Экран настроек в TUI», «Ключ
// проектного слоя в TUI»; design.md D17, D24, решение Q16 (а)).
//
// Ожидаемый API реализации (задача 4.14), см. отчёт:
//   tui_msg.dart — OpenSettingsMsg(int id, {required SettingsAccess access,
//     AgentConfigSnapshot? snapshot}); SettingsAppliedMsg(int id,
//     {required String line, required AgentConfigSnapshot snapshot});
//   tui_cmd.dart — ApplySettingCmd(int overlayId, String key,
//     {String? raw, required ConfigLayer layer});
//   settings_rows.dart — settingRowsOf, settingWriteLayerOf (4.8b).
// Разделы — секции реестра в порядке первого появления; в разделе — строки
// в порядке `settingFieldsOf`. Строка таблицы: «<key> · <value> · <source>»
// (разделитель — любые пробелы и «·»), выбранная строка помечена «›».
// Подсказка о выбранной строке и исход записи — в строке-подсказке над
// полосой клавиш. Ctrl+U в поле правки и в выборе ←→ сохраняет в `user`.
// Ядро чистое: запись делает адаптер по `ApplySettingCmd`.

import 'package:codelab_cli/codelab_cli.dart';
import 'package:codelab_setup/codelab_setup.dart';
import 'package:test/test.dart';

import '../../support/setup_fakes.dart' show leakMarker, snapshotOf;
import '../../support/tui_overlay_fixtures.dart';

const _access = EditableSettings(
  ConfigPaths(codelabHome: '/h', projectDir: '/work'),
);
const _accessNoProject = EditableSettings(ConfigPaths(codelabHome: '/h'));

TuiModel _open(
  AgentConfigSnapshot snapshot, {
  EditableSettings access = _access,
  TuiModel? model,
}) => reduce(
  model ?? newModel(),
  OpenSettingsMsg(7, access: access, snapshot: snapshot),
).$1;

/// Клавиши Tab и ↓ до строки [key] в порядке `settingFieldsOf`.
(int, int) _path(AgentConfigSnapshot snapshot, String key) {
  final rows = settingFieldsOf(snapshot);
  final sections = <String>[];
  for (final row in rows) {
    if (!sections.contains(row.descriptor.section)) {
      sections.add(row.descriptor.section);
    }
  }
  final row = rows.singleWhere((r) => r.key == key);
  final inSection = [
    for (final r in rows)
      if (r.descriptor.section == row.descriptor.section) r.key,
  ];
  return (sections.indexOf(row.descriptor.section), inSection.indexOf(key));
}

/// Открывает экран и встаёт на строку [key].
TuiModel _at(
  AgentConfigSnapshot snapshot,
  String key, {
  EditableSettings access = _access,
}) {
  final (tabs, downs) = _path(snapshot, key);
  var model = _open(snapshot, access: access);
  for (var i = 0; i < tabs; i++) {
    model = reduce(model, key_(Key.tab)).$1;
  }
  for (var i = 0; i < downs; i++) {
    model = reduce(model, key_(Key.down)).$1;
  }
  return model;
}

KeyMsg key_(Key k) => key(k);

ApplySettingCmd _apply(List<TuiCmd> cmds) =>
    cmds.whereType<ApplySettingCmd>().single;

String _hint(TuiModel model) => screenOf(model);

void main() {
  group('разметка CliSettings', () {
    final snapshot = snapshotOf(
      user: {
        'agent': {'effort': 'high'},
      },
      projectLocal: const {},
      values: const {'agent.effort': 'high'},
    );

    test('шапка с путями слоёв и полоса клавиш', () {
      final frame = frameOf(_open(snapshot));

      expect(
        frame.any(
          (l) => l.contains('Settings · /settings · user /h/config.yaml'),
        ),
        isTrue,
        reason: frame.join('\n'),
      );
      expect(
        frame.any(
          (l) => l.contains('project /work/.codelab/config.local.yaml'),
        ),
        isTrue,
      );
      expect(
        frame,
        contains(
          '↑↓ move · enter edit · ←→ choose · tab section · r reset · esc close',
        ),
      );
      expect(frame.last, 'default');
    });

    test(
      'разделы реестра, текущий помечен «›»; Display, Input, Updates нет',
      () {
        final screen = screenOf(_open(snapshot));

        for (final section in [
          'Models',
          'Agent',
          'Providers',
          'Permissions',
          'Budget',
          'MCP',
          'Logging',
        ]) {
          expect(screen, contains(section));
        }
        expect(screen, contains('› Models'));
        for (final absent in ['Display', 'Input', 'Updates']) {
          expect(screen, isNot(contains(absent)));
        }
      },
    );

    test('таблица текущего раздела: ключ, значение, источник', () {
      var model = _open(snapshot);
      expect(
        frameOf(model).any(
          (l) =>
              RegExp(r'agent\.default_model.*\(not set\).*default').hasMatch(l),
        ),
        isTrue,
      );

      model = reduce(model, key(Key.tab)).$1;
      final frame = frameOf(model);
      expect(frame.any((l) => l.contains('› Agent')), isTrue);
      expect(
        frame.any((l) => RegExp(r'agent\.effort.*high.*user').hasMatch(l)),
        isTrue,
        reason: frame.join('\n'),
      );
      expect(
        frame.any(
          (l) => RegExp(r'compaction\.enabled.*true.*default').hasMatch(l),
        ),
        isTrue,
      );
    });

    test('↑↓ двигает выбранную строку', () {
      var model = reduce(_open(snapshot), key(Key.tab)).$1;
      expect(frameOf(model).any((l) => l.contains('› agent.effort')), isTrue);

      model = reduce(model, key(Key.down)).$1;
      expect(
        frameOf(model).any((l) => l.contains('› compaction.enabled')),
        isTrue,
      );

      model = reduce(model, key(Key.up)).$1;
      expect(frameOf(model).any((l) => l.contains('› agent.effort')), isTrue);
    });

    test('Esc закрывает экран без команд', () {
      final (model, cmds) = reduce(_open(snapshot), key(Key.escape));

      expect(model.overlay, isNull);
      expect(cmds, isEmpty);
    });
  });

  group('правка значения', () {
    final snapshot = snapshotOf(
      user: {
        'agent': {'effort': 'high'},
      },
      values: const {'agent.effort': 'high'},
    );

    test('enumeration: Enter → ←→ выбирают → Enter пишет в user', () {
      var model = _at(snapshot, 'agent.effort');

      model = reduce(model, key(Key.enter)).$1;
      model = reduce(model, key(Key.left)).$1;
      final (_, cmds) = reduce(model, key(Key.enter));

      final apply = _apply(cmds);
      expect(apply.overlayId, 7);
      expect(apply.key, 'agent.effort');
      expect(apply.raw, 'medium');
      expect(apply.layer, ConfigLayer.user);
    });

    test('bool: ← → переключает true/false', () {
      var model = _at(snapshot, 'compaction.enabled');

      model = reduce(model, key(Key.enter)).$1;
      model = reduce(model, key(Key.right)).$1;

      expect(_apply(reduce(model, key(Key.enter)).$2).raw, 'false');
    });

    test('Esc в выборе возвращает к таблице, второй Esc закрывает', () {
      var model = _at(snapshot, 'agent.effort');
      model = reduce(model, key(Key.enter)).$1;

      model = reduce(model, key(Key.escape)).$1;
      expect(model.overlay, isA<SettingsOverlay>());

      model = reduce(model, key(Key.escape)).$1;
      expect(model.overlay, isNull);
    });

    test('число: поле с текущим значением, ввод и Enter', () {
      var model = _at(snapshot, 'budget.max_steps');

      model = reduce(model, key(Key.enter)).$1;
      expect(_hint(model), contains('50'), reason: 'значение по умолчанию');
      model = reduce(model, key(Key.backspace)).$1;
      model = reduce(model, key(Key.backspace)).$1;
      model = reduce(model, text('7')).$1;
      final (_, cmds) = reduce(model, key(Key.enter));

      final apply = _apply(cmds);
      expect(apply.key, 'budget.max_steps');
      expect(apply.raw, '7');
      expect(apply.layer, ConfigLayer.user);
    });

    test('список: поле с JSON значения; ввод разбирает parseCliValue при '
        'записи', () {
      final withList = snapshotOf(
        user: {
          'permissions': {
            'deny': ['bash:rm*'],
          },
        },
        values: const {
          'permissions.deny': ['bash:rm*'],
        },
      );
      var model = _at(withList, 'permissions.deny');

      model = reduce(model, key(Key.enter)).$1;
      expect(_hint(model), contains('["bash:rm*"]'));
      model = reduce(model, text(',')).$1;
      final (_, cmds) = reduce(model, key(Key.enter));

      expect(_apply(cmds).raw, '["bash:rm*"],');
    });

    test('исход записи — в строке-подсказке, таблица берёт новый снимок', () {
      final model = _at(snapshot, 'agent.effort');
      final next = snapshotOf(
        user: {
          'agent': {'effort': 'low'},
        },
        values: const {'agent.effort': 'low'},
      );

      final (updated, cmds) = reduce(
        model,
        SettingsAppliedMsg(
          7,
          line: 'Updated agent.effort in /h/config.yaml',
          snapshot: next,
        ),
      );

      expect(cmds, isEmpty);
      expect(
        _hint(updated),
        contains('Updated agent.effort in /h/config.yaml'),
      );
      expect(
        frameOf(
          updated,
        ).any((l) => RegExp(r'agent\.effort.*low.*user').hasMatch(l)),
        isTrue,
      );
    });

    test('исход с чужим номером экрана игнорируется', () {
      final model = _at(snapshot, 'agent.effort');

      final (same, _) = reduce(
        model,
        SettingsAppliedMsg(9, line: 'Updated x', snapshot: snapshotOf()),
      );

      expect(_hint(same), isNot(contains('Updated x')));
    });

    test('`r` сбрасывает ключ в слое, где он определён', () {
      final model = _at(snapshot, 'agent.effort');

      final (_, cmds) = reduce(model, text('r'));

      final apply = _apply(cmds);
      expect(apply.key, 'agent.effort');
      expect(apply.raw, isNull);
      expect(apply.layer, ConfigLayer.user);
    });
  });

  group('слой записи (D17, D24)', () {
    final project = snapshotOf(
      project: {
        'budget': {'max_steps': 9},
      },
      projectLocal: const {},
      values: const {'budget.max_steps': 9},
    );

    test('ключ проектного слоя: подсказка и запись в projectLocal', () {
      var model = _at(project, 'budget.max_steps');

      expect(
        _hint(model),
        contains(
          'budget.max_steps is set by the project file; your choice is saved '
          'to .codelab/config.local.yaml. ctrl+u saves to user instead.',
        ),
      );

      model = reduce(model, key(Key.enter)).$1;
      model = reduce(model, key(Key.backspace)).$1;
      model = reduce(model, text('3')).$1;
      final apply = _apply(reduce(model, key(Key.enter)).$2);

      expect(apply.layer, ConfigLayer.projectLocal);
      expect(apply.raw, '3');
    });

    test('ctrl+u сохраняет значение в user', () {
      var model = _at(project, 'budget.max_steps');
      model = reduce(model, key(Key.enter)).$1;
      model = reduce(model, key(Key.backspace)).$1;
      model = reduce(model, text('3')).$1;

      final (_, cmds) = reduce(model, key(Key.ctrlU));

      expect(_apply(cmds).layer, ConfigLayer.user);
      expect(_apply(cmds).raw, '3');
    });

    test('без цели projectLocal ключ проектного слоя пишется в user', () {
      var model = _at(project, 'budget.max_steps', access: _accessNoProject);
      model = reduce(model, key(Key.enter)).$1;
      model = reduce(model, key(Key.backspace)).$1;
      model = reduce(model, text('3')).$1;

      expect(_apply(reduce(model, key(Key.enter)).$2).layer, ConfigLayer.user);
    });

    test('источники config и env не редактируются', () {
      final external = snapshotOf(
        values: const {'budget.max_steps': 9},
        external: const {'budget.max_steps': ConfigSourceKind.environment},
      );
      var model = _at(external, 'budget.max_steps');

      model = reduce(model, key(Key.enter)).$1;
      final (_, cmds) = reduce(model, text('r'));

      expect(
        _hint(model),
        contains('budget.max_steps is set by env; it cannot be changed here.'),
      );
      expect(cmds.whereType<ApplySettingCmd>(), isEmpty);
    });
  });

  group('только для чтения: секреты, карты, замаскированные значения', () {
    final snapshot = snapshotOf(
      user: {
        'providers': {
          'gw': {
            'kind': 'openai-compatible',
            'base_url': 'https://gw.test/v1?token=$leakMarker',
            'models': {
              'm': {'context_window': 8000},
            },
          },
        },
        'permissions': {
          'tools': {'bash': 'deny'},
        },
      },
      values: {
        'providers.gw.kind': 'openai-compatible',
        'providers.gw.base_url': 'https://gw.test/v1?token=$leakMarker',
        'providers.gw.models.m.context_window': 8000,
        'permissions.tools.bash': 'deny',
      },
    );

    test('secretName: Use codelab secret set <name>, поля нет', () {
      final model = _at(snapshot, 'providers.gw.api_key_secret');

      final (next, cmds) = reduce(model, key(Key.enter));

      expect(_hint(next), contains('Use codelab secret set <name>'));
      expect(cmds, isEmpty);
    });

    test(
      'замаскированный литерал: значения нет в кадре, поле не открывается',
      () {
        final model = _at(snapshot, 'providers.gw.base_url');
        expect(screenOf(model), isNot(contains(leakMarker)));

        final (next, cmds) = reduce(model, key(Key.enter));

        expect(screenOf(next), isNot(contains(leakMarker)));
        expect(_hint(next), contains('Use codelab secret set <name>'));
        expect(cmds, isEmpty);
      },
    );

    test('mapList: Enter — Edit with codelab mcp add', () {
      final (next, cmds) = reduce(_at(snapshot, 'mcp.servers'), key(Key.enter));

      expect(_hint(next), contains('Edit with codelab mcp add'));
      expect(cmds, isEmpty);
    });

    test('map: Enter — подсказка про файл и codelab config set; r удаляет '
        'ключ из слоя', () {
      final model = _at(snapshot, 'permissions.tools');

      final (next, cmds) = reduce(model, key(Key.enter));
      expect(
        _hint(next),
        contains(
          'Edit permissions.tools in the config file or with codelab config '
          'set',
        ),
      );
      expect(cmds, isEmpty);

      final apply = _apply(reduce(model, text('r')).$2);
      expect(apply.key, 'permissions.tools');
      expect(apply.raw, isNull);
      expect(apply.layer, ConfigLayer.user);
    });

    test('trusted_projects: граница доверия — подсказка, команд нет', () {
      final (next, cmds) = reduce(
        _at(snapshot, 'trusted_projects'),
        key(Key.enter),
      );

      expect(
        _hint(next),
        contains(
          'trusted_projects is a trust boundary; it cannot be changed here.',
        ),
      );
      expect(cmds, isEmpty);
    });
  });

  group('удалённый и сторонний агент: только чтение', () {
    test('удалённый: строка §12.4.8, строк настроек нет, клавиши — без '
        'команд', () {
      var model = reduce(
        newModel(),
        OpenSettingsMsg(
          7,
          access: RemoteReadOnly(Uri.parse('ws://127.0.0.1:9/acp')),
        ),
      ).$1;
      final screen = screenOf(model);

      expect(
        screen,
        contains(
          'Provider settings are read-only for a remote agent. Run "codelab '
          'provider add" on the agent host.',
        ),
      );
      expect(screen, isNot(contains('agent.effort')));
      expect(screen, isNot(contains('r reset')));

      final all = <TuiCmd>[];
      for (final msg in [
        key(Key.enter),
        text('r'),
        key(Key.down),
        key(Key.tab),
      ]) {
        final (next, cmds) = reduce(model, msg);
        model = next;
        all.addAll(cmds);
      }
      expect(all, isEmpty);
      expect(reduce(model, key(Key.escape)).$1.overlay, isNull);
    });

    test('сторонний агент: «managed by <имя>»', () {
      final model = reduce(
        newModel(),
        const OpenSettingsMsg(7, access: NotManaged('python')),
      ).$1;

      expect(
        screenOf(model),
        contains('Provider settings are managed by python.'),
      );
    });
  });
}
