import 'package:codelab_agent_core/codelab_agent_core.dart';
import 'package:test/test.dart';

import 'config_support.dart';

/// Раздел `subagents` конфигурации (agent-configuration «Ключи subagents в
/// схеме и реестре настроек», сценарии «Умолчания», «Диапазон глубины»,
/// «Проект не повышает глубину», «Дескрипторы в реестре»; design.md change
/// `add-subagents-and-tasks`, D17, D22; CFG-3, CFG-5).
///
/// Красные до задачи 2.2: раздел `subagents` — опаковый (`afterMvpSections`
/// и `_opaque('subagents')` в реестре), у `CoreConfig` нет поля `subagents`.
///
/// Фиксируемый API: `CoreConfig.subagents` типа `SubagentsConfig` с полями
/// `enabled`, `maxDepth`, `maxConcurrent`, `maxPerTurn`, `maxSteps`,
/// `maxTokens` (`int?`), `maxCost` (`double?`), `maxDuration`,
/// `reportMaxBytes`, `progressInterval`, `heartbeatInterval`, `cancelGrace`
/// (все длительности — `Duration`).
void main() {
  Map<String, Object?> subagents(Map<String, Object?> values) => {
    'subagents': values,
  };

  ConfigTree user(Map<String, Object?> values, {List<String>? trusted}) =>
      layer(
        withValues(baseValues(), {...values, 'trusted_projects': ?trusted}),
      );

  ConfigTree project(Map<String, Object?> values) =>
      layer(values, kind: ConfigLayerKind.project);

  group('сценарий «Умолчания»', () {
    test('пустой конфиг: enabled, глубина 3, три слота, десять запусков, '
        'тридцать шагов', () {
      final result = load([layer(baseValues())]);

      expect(result.issues, isEmpty, reason: result.issues.join('\n'));
      final s = result.config!.subagents;
      expect(s.enabled, isTrue);
      expect(s.maxDepth, 3);
      expect(s.maxConcurrent, 3);
      expect(s.maxPerTurn, 10);
      expect(s.maxSteps, 30);
      expect(s.maxTokens, isNull);
      expect(s.maxCost, isNull);
      expect(s.maxDuration, const Duration(minutes: 10));
      expect(s.reportMaxBytes, 16384);
      expect(s.progressInterval, const Duration(seconds: 2));
      expect(s.heartbeatInterval, const Duration(seconds: 15));
      expect(s.cancelGrace, const Duration(seconds: 10));
    });

    test('все ключи читаются из файла и не дают config.key.not_applied', () {
      final result = load([
        user(
          subagents({
            'enabled': false,
            'max_depth': 2,
            'max_concurrent': 5,
            'max_per_turn': 20,
            'max_steps': 100,
            'max_tokens': 50000,
            'max_cost': 1.5,
            'max_duration': '5m',
            'report_max_bytes': 4096,
            'progress_interval': '1s',
            'heartbeat_interval': '30s',
            'cancel_grace': '3s',
          }),
        ),
      ]);

      expect(result.issues, isEmpty, reason: result.issues.join('\n'));
      final s = result.config!.subagents;
      expect(s.enabled, isFalse);
      expect(s.maxDepth, 2);
      expect(s.maxConcurrent, 5);
      expect(s.maxPerTurn, 20);
      expect(s.maxSteps, 100);
      expect(s.maxTokens, 50000);
      expect(s.maxCost, 1.5);
      expect(s.maxDuration, const Duration(minutes: 5));
      expect(s.reportMaxBytes, 4096);
      expect(s.progressInterval, const Duration(seconds: 1));
      expect(s.heartbeatInterval, const Duration(seconds: 30));
      expect(s.cancelGrace, const Duration(seconds: 3));
      expect(warningsOf(result, 'config.key.not_applied'), isEmpty);
    });

    test('ключ другого этапа (background) не входит в схему (CFG-5)', () {
      final result = load([
        user(subagents({'background': true})),
      ]);

      final issue = issuesAt(result, 'subagents.background').single;
      expect(issue.kind, ConfigIssueKind.unknownKey);
      expect(result.config, isNull);
    });
  });

  group('диапазоны: значение вне диапазона — ConfigIssue, а не исключение', () {
    void expectBounds(
      String key,
      Object Function(int) build, {
      required int lower,
      required int upper,
    }) {
      for (final value in [lower, upper]) {
        final r = load([
          user(subagents({key: build(value)})),
        ]);
        expect(r.issues, isEmpty, reason: 'subagents.$key=$value ${r.issues}');
      }
      for (final value in [lower - 1, upper + 1]) {
        final r = load([
          user(subagents({key: build(value)})),
        ]);
        expect(
          issuesAt(r, 'subagents.$key'),
          hasLength(1),
          reason: 'subagents.$key=$value',
        );
        expect(r.config, isNull);
      }
    }

    test('max_depth 1..3', () {
      expectBounds('max_depth', (v) => v, lower: 1, upper: 3);
    });

    test('max_concurrent 1..8', () {
      expectBounds('max_concurrent', (v) => v, lower: 1, upper: 8);
    });

    test('max_per_turn 1..50', () {
      expectBounds('max_per_turn', (v) => v, lower: 1, upper: 50);
    });

    test('max_steps 1..500', () {
      expectBounds('max_steps', (v) => v, lower: 1, upper: 500);
    });

    test('report_max_bytes 1024..1048576', () {
      expectBounds('report_max_bytes', (v) => v, lower: 1024, upper: 1048576);
    });

    test('max_tokens не меньше 1', () {
      final ok = load([
        user(subagents({'max_tokens': 1})),
      ]);
      final bad = load([
        user(subagents({'max_tokens': 0})),
      ]);

      expect(ok.issues, isEmpty, reason: ok.issues.join('\n'));
      expect(issuesAt(bad, 'subagents.max_tokens'), hasLength(1));
    });

    test('max_cost больше нуля', () {
      final ok = load([
        user(subagents({'max_cost': 0.01})),
      ]);
      final bad = load([
        user(subagents({'max_cost': 0})),
      ]);

      expect(ok.issues, isEmpty, reason: ok.issues.join('\n'));
      expect(issuesAt(bad, 'subagents.max_cost'), hasLength(1));
    });

    test('длительности больше нуля', () {
      for (final key in [
        'max_duration',
        'progress_interval',
        'heartbeat_interval',
        'cancel_grace',
      ]) {
        final ok = load([
          user(subagents({key: '1s'})),
        ]);
        final bad = load([
          user(subagents({key: '0s'})),
        ]);

        expect(ok.issues, isEmpty, reason: '$key ${ok.issues}');
        expect(issuesAt(bad, 'subagents.$key'), hasLength(1), reason: key);
      }
    });

    test('неверный тип — проблема типа с путём ключа', () {
      final r = load([
        user(subagents({'max_depth': 'deep'})),
      ]);

      final issue = issuesAt(r, 'subagents.max_depth').single;
      expect(issue.kind, ConfigIssueKind.type);
    });
  });

  test('сценарий «Диапазон глубины»: 4 и 0 дают ConfigIssue с итогом 3, '
      '3 принимается', () {
    final tooDeep = load([
      user(subagents({'max_depth': 4})),
    ]);
    final zero = load([
      user(subagents({'max_depth': 0})),
    ]);
    final ok = load([
      user(subagents({'max_depth': 3})),
    ]);

    for (final r in [tooDeep, zero]) {
      // Проблема, а не исключение; путь ключа — в `ConfigIssue.key`.
      expect(issuesAt(r, 'subagents.max_depth'), hasLength(1));
    }
    expect(ok.issues, isEmpty, reason: ok.issues.join('\n'));
    expect(ok.config!.subagents.maxDepth, 3);
  });

  group('проектный слой только ужесточает (CFG-3)', () {
    test('сценарий «Проект не повышает глубину»: global 2, проект 3 → 2, '
        'config.project.untrusted_key', () {
      final r = load([
        user(subagents({'max_depth': 2})),
        project(subagents({'max_depth': 3})),
      ], projectRoot: '/proj');

      expect(r.config!.subagents.maxDepth, 2);
      final w = warningsOf(r, 'config.project.untrusted_key').single;
      expect(w.key, 'subagents.max_depth');
    });

    test('меньшие числа проекта применяются без предупреждения', () {
      final r = load([
        layer(baseValues()),
        project(
          subagents({
            'max_depth': 1,
            'max_concurrent': 2,
            'max_per_turn': 5,
            'max_steps': 10,
            'report_max_bytes': 2048,
          }),
        ),
      ], projectRoot: '/proj');

      final s = r.config!.subagents;
      expect(s.maxDepth, 1);
      expect(s.maxConcurrent, 2);
      expect(s.maxPerTurn, 5);
      expect(s.maxSteps, 10);
      expect(s.reportMaxBytes, 2048);
      expect(warningsOf(r, 'config.project.untrusted_key'), isEmpty);
    });

    test('смягчение отбрасывается по ключам: число больше глобального', () {
      final r = load([
        layer(baseValues()),
        project(
          subagents({
            'max_concurrent': 8,
            'max_per_turn': 50,
            'max_steps': 500,
          }),
        ),
      ], projectRoot: '/proj');

      final s = r.config!.subagents;
      expect(s.maxConcurrent, 3);
      expect(s.maxPerTurn, 10);
      expect(s.maxSteps, 30);
      expect(
        [for (final w in warningsOf(r, 'config.project.untrusted_key')) w.key],
        [
          'subagents.max_concurrent',
          'subagents.max_per_turn',
          'subagents.max_steps',
        ],
      );
    });

    test('enabled: false проекта применяется, enabled: true не отменяет '
        'false пользователя', () {
      final off = load([
        layer(baseValues()),
        project(subagents({'enabled': false})),
      ], projectRoot: '/proj');
      final back = load([
        user(subagents({'enabled': false})),
        project(subagents({'enabled': true})),
      ], projectRoot: '/proj');

      expect(off.config!.subagents.enabled, isFalse);
      expect(warningsOf(off, 'config.project.untrusted_key'), isEmpty);
      expect(back.config!.subagents.enabled, isFalse);
      expect(
        warningsOf(back, 'config.project.untrusted_key').single.key,
        'subagents.enabled',
      );
    });

    test('снимок без проекта хранит глобальные значения', () {
      final r = load([
        user(subagents({'max_depth': 3})),
        project(subagents({'max_depth': 1})),
      ], projectRoot: '/proj');

      expect(r.config!.subagents.maxDepth, 1);
      expect(r.config!.withoutProject!.subagents.maxDepth, 3);
    });
  });

  group('сценарий «Дескрипторы в реестре»', () {
    // (ключ, тип, умолчание или null, min, max)
    final table = <(String, SettingType, Object?, num?, num?)>[
      ('subagents.enabled', SettingType.bool, true, null, null),
      ('subagents.max_depth', SettingType.int, 3, 1, 3),
      ('subagents.max_concurrent', SettingType.int, 3, 1, 8),
      ('subagents.max_per_turn', SettingType.int, 10, 1, 50),
      ('subagents.max_steps', SettingType.int, 30, 1, 500),
      ('subagents.max_tokens', SettingType.int, null, 1, null),
      ('subagents.max_cost', SettingType.float, null, null, null),
      ('subagents.max_duration', SettingType.duration, null, null, null),
      ('subagents.report_max_bytes', SettingType.int, 16384, 1024, 1048576),
      ('subagents.progress_interval', SettingType.duration, null, null, null),
      ('subagents.heartbeat_interval', SettingType.duration, null, null, null),
      ('subagents.cancel_grace', SettingType.duration, null, null, null),
    ];

    test('каждый ключ таблицы — лист-дескриптор shared без перезапуска, '
        'с подписью и описанием', () {
      for (final (key, type, defaultValue, min, max) in table) {
        final d = SettingsRegistry.lookup(key);

        expect(d, isNotNull, reason: key);
        expect(d!.key, key, reason: 'лист, а не опаковый раздел subagents');
        expect(d.scope, SettingScope.shared, reason: key);
        expect(d.section, 'Subagents', reason: key);
        expect(d.type, type, reason: key);
        expect(d.restartRequired, isFalse, reason: key);
        expect(d.label, isNotEmpty, reason: key);
        expect(d.description, isNotEmpty, reason: key);
        if (type != SettingType.duration) {
          expect(d.defaultValue, defaultValue, reason: key);
        }
        expect(d.min, min, reason: key);
        expect(d.max, max, reason: key);
      }
    });

    test('опакового дескриптора subagents нет', () {
      final opaque = SettingsRegistry.all.where((d) => d.key == 'subagents');

      expect(opaque, isEmpty);
    });
  });
}
