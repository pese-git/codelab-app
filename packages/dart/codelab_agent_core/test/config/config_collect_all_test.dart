import 'package:codelab_agent_core/codelab_agent_core.dart';
import 'package:codelab_agent_core/src/config/resolve.dart'
    show resolveCollectAllForTesting, withoutKeysForTesting;
import 'package:test/test.dart';

import 'config_support.dart';

/// Режим `collectAll` у `CoreConfig.fromLayers` (R3-1, решение пользователя
/// 2026-11-03; design.md change `add-config-writer-and-reload`, D5): полный
/// набор проблем без обрыва на ступени проверки слоёв.
void main() {
  Map<String, Object?> broken() => {
    'agent': {'default_model': 'lm/m'},
    'providers': {
      'lm': {
        'kind': 'openai-compatible',
        'colour':
            'red', // неизвестный ключ: ошибка слоя (литеральный api_key с R8-4 — предупреждение)
        'base_url': 'ftp://host/v1',
        'models': {
          'm': {'context_window': 8192},
        },
      },
    },
  };

  Set<String> keys(ConfigLoadResult r) => {for (final i in r.issues) i.key};

  test('обычный режим обрывается на ошибке проверки слоя', () {
    final result = load([layer(broken())]);

    expect(keys(result), {'providers.lm.colour'});
  });

  test('collectAll: ступени после ошибки слоя выполняются, каскад виден', () {
    final result = CoreConfig.fromLayers(
      [layer(broken())],
      environment: const {},
      collectAll: true,
    );

    expect(result.config, isNull);
    expect(keys(result), {
      'providers.lm.colour',
      'providers.lm.base_url',
      'agent.default_model',
    });
  });

  test('collectAll без проблем даёт ту же конфигурацию', () {
    final result = CoreConfig.fromLayers(
      [layer(baseValues())],
      environment: const {},
      collectAll: true,
    );

    expect(result.issues, isEmpty);
    expect(result.config, isNotNull);
  });

  // Ревью R3-3: несколько ошибочных элементов одного списка. Удаление по
  // номеру в порядке проблем сдвигало индексы и обрывало поздние ступени.
  group('элементы списков', () {
    Map<String, Object?> wrongModel() => {
      'providers': {
        'p': {
          'kind': 'openai-compatible',
          'base_url': 'https://x/v1',
          'models': {'m': <String, Object?>{}},
        },
      },
      'agent': {'default_model': 'p/nope'},
    };

    ConfigLoadResult all(Map<String, Object?> extra) => CoreConfig.fromLayers(
      [
        layer({...wrongModel(), ...extra}),
      ],
      environment: const {},
      collectAll: true,
    );

    test('два ошибочных trusted_projects: каскад виден', () {
      final result = all({
        'trusted_projects': ['a', 'b'],
      });

      expect(keys(result), {
        'trusted_projects[0]',
        'trusted_projects[1]',
        'agent.default_model',
      });
    });

    test('ошибочные элементы вокруг верного: лишних ключей нет', () {
      final result = all({
        'trusted_projects': ['a', '/b', 'c'],
      });

      expect(keys(result), {
        'trusted_projects[0]',
        'trusted_projects[2]',
        'agent.default_model',
      });
    });

    test('два безымянных сервера mcp: каскад виден', () {
      final result = all({
        'mcp': {
          'servers': [
            {'command': 'x'},
            {'command': 'y'},
          ],
        },
      });

      expect(keys(result), contains('agent.default_model'));
    });

    test('сервер с именем "0" и неизвестным ключом: вырезается он, а не '
        'элемент с индексом 0', () {
      final result = all({
        'mcp': {
          'servers': [
            {'name': 'ok', 'type': 'stdio', 'command': 'x'},
            {'name': '0', 'type': 'stdio', 'command': 'y', 'bogus': 1},
          ],
        },
      });

      expect(keys(result), {'mcp.servers[0].bogus', 'agent.default_model'});
    });
  });

  // Ревью R3-3, повторное: проблему, ключ которой не вырезается или которая
  // не снимается за лимит кругов, нельзя терять вместе с поздними ступенями
  // (иначе правила доверия не дают `untrusted_key`).
  group('проект недоверенный: правила доверия видны при любой порче слоя', () {
    final user = layer(baseValues());

    ConfigLoadResult withProject(Map<String, Object?> extra) =>
        CoreConfig.fromLayers(
          [
            user,
            layer({
              'permissions': {'mode': 'bypass'},
              ...extra,
            }, kind: ConfigLayerKind.project),
          ],
          environment: const {},
          projectRoot: '/proj',
          collectAll: true,
        );

    // Либо ступень доверия выполнена (предупреждение), либо проверка явно
    // названа неполной: третьего не дано (fail-closed).
    void expectClosed(ConfigLoadResult r) {
      final trustSeen = r.warnings.any(
        (w) => w.event == 'config.project.untrusted_key',
      );
      final incomplete = r.issues.any(
        (i) => i.event == validationIncompleteEvent,
      );
      expect(trustSeen || incomplete, isTrue, reason: '${r.issues}');
    }

    Map<String, Object?> servers(Object? list) => {
      'mcp': {'servers': list},
    };

    test('name не строка', () {
      final r = withProject(
        servers([
          {'name': 5, 'command': 'x'},
        ]),
      );
      expectClosed(r);
      expect(r.warnings.any((w) => w.key == 'permissions.mode'), isTrue);
    });

    test('ключ с кавычкой в элементе', () {
      final r = withProject(
        servers([
          {'name': 'q', 'type': 'stdio', 'command': 'x', 'a"b': 1},
        ]),
      );
      expectClosed(r);
      expect(r.warnings.any((w) => w.key == 'permissions.mode'), isTrue);
    });

    test('ключ с кавычкой на верхнем уровне', () {
      final r = withProject({'x"y': 1});
      expectClosed(r);
      expect(r.warnings.any((w) => w.key == 'permissions.mode'), isTrue);
    });

    bool trustSeen(ConfigLoadResult r) => r.warnings.any(
      (w) =>
          w.event == 'config.project.untrusted_key' &&
          w.key == 'permissions.mode',
    );

    // Третий проход ревью: неоднозначное сопоставление пути не должно
    // скрывать предупреждение доверия — оно считается по исходным слоям.
    test('ключ "mode.x" рядом с mode в permissions', () {
      final r = withProject({
        'permissions': {'mode': 'bypass', 'mode.x': 1},
      });
      expect(trustSeen(r), isTrue, reason: '${r.issues}');
    });

    test('верхнеуровневый "permissions.mode" рядом с permissions, оба '
        'порядка ключей', () {
      for (final extra in [
        {
          'permissions.mode': 'x',
          'permissions': {'mode': 'bypass'},
        },
        {
          'permissions': {'mode': 'bypass'},
          'permissions.mode': 'x',
        },
      ]) {
        final r = CoreConfig.fromLayers(
          [layer(baseValues()), layer(extra, kind: ConfigLayerKind.project)],
          environment: const {},
          projectRoot: '/proj',
          collectAll: true,
        );
        expect(trustSeen(r), isTrue, reason: '$extra ${r.issues}');
      }
    });

    test('"servers.x" рядом со списком servers', () {
      final r = withProject({
        'mcp': {
          'servers': [
            {'name': 's', 'type': 'stdio', 'command': 'x'},
          ],
          'servers.x': 1,
        },
      });
      expect(trustSeen(r), isTrue, reason: '${r.issues}');
      expect(
        r.issues.any((i) => i.event == validationIncompleteEvent) ||
            !r.issues.any((i) => i.key == 'mcp.servers[s]'),
        isTrue,
      );
    });

    test('имя сервера с "]" и неизвестный ключ', () {
      final r = withProject(
        servers([
          {'name': 'a]b', 'type': 'stdio', 'command': 'x', 'bogus': 1},
        ]),
      );
      expect(trustSeen(r), isTrue, reason: '${r.issues}');
      expect(
        r.issues.any((i) => i.event == validationIncompleteEvent),
        isFalse,
      );
    });

    test('запасное вырезание предка помечает проверку неполной', () {
      final tree = layer({
        'permissions': {'mode': 'ask'},
      });
      final cut = withoutKeysForTesting(tree, [
        ConfigIssue(
          kind: ConfigIssueKind.value,
          key: 'permissions.nothing.deeper',
          source: tree.source,
          message: 'x',
        ),
      ]);
      expect(cut.degraded, isTrue);
    });

    test('десять серверов с одним именем снимаются за один круг', () {
      final r = withProject(
        servers([
          for (var i = 0; i < 10; i++)
            {'name': 'd', 'type': 'stdio', 'command': 'x'},
        ]),
      );
      expectClosed(r);
      expect(r.warnings.any((w) => w.key == 'permissions.mode'), isTrue);
    });
  });

  // Ветка «проверка неполна» (fail-closed, R3-3): внутренние входы для
  // тестов, публичный API ядра не расширен.
  group('проверка неполна', () {
    test('лимит кругов исчерпан: служебная проблема, без молчаливого '
        'результата', () {
      final result = resolveCollectAllForTesting(
        [layer(broken())],
        environment: const {},
        rounds: 0,
      );

      expect(result.config, isNull);
      final marks = result.issues.where(
        (i) => i.event == validationIncompleteEvent,
      );
      expect(marks, hasLength(1));
      expect(marks.single.key, isEmpty);
      expect(marks.single.message, contains('could not be fully checked'));
      expect(keys(result), contains('providers.lm.colour'));
    });

    test('ключ проблемы не опознан: вырезается весь слой и это degraded', () {
      final tree = layer(baseValues());
      final cut = withoutKeysForTesting(tree, [
        ConfigIssue(
          kind: ConfigIssueKind.value,
          key: 'no.such.key',
          source: tree.source,
          message: 'x',
        ),
      ]);

      expect(cut.layer.values, isEmpty);
      expect(cut.removed, isTrue);
      expect(cut.degraded, isTrue);
    });

    test('вырезание предка ниже слоя не degraded, ключи вне поддерева '
        'остаются', () {
      final tree = layer({
        ...baseValues(),
        'mcp': {
          'servers': [
            {'name': 5, 'command': 'x'},
          ],
        },
      });
      final cut = withoutKeysForTesting(tree, [
        ConfigIssue(
          kind: ConfigIssueKind.value,
          key: 'mcp.servers[0]',
          source: tree.source,
          message: 'x',
        ),
      ]);

      expect(cut.degraded, isFalse);
      expect(cut.layer.values.keys, containsAll(['providers', 'agent']));
    });
  });
}
