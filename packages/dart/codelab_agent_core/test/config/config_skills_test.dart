import 'package:codelab_agent_core/codelab_agent_core.dart';
import 'package:test/test.dart';

import 'config_support.dart';

/// Раздел `skills` конфигурации (agent-configuration «Схема и строгая
/// проверка», сценарии «Ключ без потребителя», «Раздел skills применяется»;
/// agent-skills «Конфигурация навыков», все сценарии; design.md change
/// `add-agent-skills`, D11; CFG-3).
///
/// Фиксируемый API: `CoreConfig.skills` типа `SkillsConfig` с полями
/// `enabled`, `extraRoots`, `disabled`, `maxSkills`, `catalogMaxChars`,
/// `reattachPerSkillTokens`, `reattachTotalTokens`; `HostCapability.skills`.
void main() {
  Map<String, Object?> skills(Map<String, Object?> values) => {
    'skills': values,
  };

  ConfigTree user(Map<String, Object?> values, {List<String>? trusted}) =>
      layer(
        withValues(baseValues(), {...values, 'trusted_projects': ?trusted}),
      );

  ConfigTree project(
    Map<String, Object?> values, {
    ConfigLayerKind kind = ConfigLayerKind.project,
  }) => layer(values, kind: kind);

  group('defaults', () {
    test('the section is absent: documented defaults, capability on', () {
      final result = load([layer(baseValues())]);

      expect(result.issues, isEmpty, reason: result.issues.join('\n'));
      final s = result.config!.skills;
      expect(s.enabled, isTrue);
      expect(s.extraRoots, isEmpty);
      expect(s.disabled, isEmpty);
      expect(s.maxSkills, 200);
      expect(s.catalogMaxChars, 8000);
      expect(s.reattachPerSkillTokens, 5000);
      expect(s.reattachTotalTokens, 25000);
    });
  });

  group('keys with a consumer', () {
    test('are read from the config without config.key.not_applied', () {
      final result = load([
        user(
          skills({
            'enabled': false,
            'extra_roots': ['/opt/skills', '.claude/skills'],
            'disabled': ['pdf', 'notes'],
            'max_skills': 100,
            'catalog_max_chars': 4000,
            'reattach': {'per_skill_tokens': 3000, 'total_tokens': 10000},
          }),
        ),
      ]);

      expect(result.issues, isEmpty, reason: result.issues.join('\n'));
      final s = result.config!.skills;
      expect(s.enabled, isFalse);
      expect(s.extraRoots, ['/opt/skills', '.claude/skills']);
      expect(s.disabled, ['pdf', 'notes']);
      expect(s.maxSkills, 100);
      expect(s.catalogMaxChars, 4000);
      expect(s.reattachPerSkillTokens, 3000);
      expect(s.reattachTotalTokens, 10000);
      expect(warningsOf(result, 'config.key.not_applied'), isEmpty);
    });

    test('scenario "Раздел skills применяется": max_skills applied, '
        'catalog_max_chars 500 is a problem, profile narrowing accepted', () {
      final ok = load([
        user({
          ...skills({'max_skills': 100}),
          'profile': {
            'agent-serve': {'skills': 'off'},
          },
        }),
      ]);
      final bad = load([
        user(skills({'catalog_max_chars': 500})),
      ]);

      expect(ok.issues, isEmpty, reason: ok.issues.join('\n'));
      expect(ok.config!.skills.maxSkills, 100);
      expect(warningsOf(ok, 'config.key.not_applied'), isEmpty);
      expect(
        ok.host!.profileNarrowing['agent-serve']![HostCapability.skills],
        isA<CapabilityOff>(),
      );
      expect(issuesAt(bad, 'skills.catalog_max_chars'), hasLength(1));
      expect(bad.config, isNull);
    });
  });

  group('bounds', () {
    void expectBounds(
      String key,
      Map<String, Object?> Function(int) build, {
      required int lower,
      required int upper,
    }) {
      for (final value in [lower, upper]) {
        final r = load([user(skills(build(value)))]);
        expect(r.issues, isEmpty, reason: '$key=$value ${r.issues}');
      }
      for (final value in [lower - 1, upper + 1]) {
        final r = load([user(skills(build(value)))]);
        expect(issuesAt(r, key), hasLength(1), reason: '$key=$value');
        expect(r.config, isNull);
      }
    }

    test('max_skills is 1..1000', () {
      expectBounds(
        'skills.max_skills',
        (v) => {'max_skills': v},
        lower: 1,
        upper: 1000,
      );
    });

    test('catalog_max_chars is 1000..64000', () {
      expectBounds(
        'skills.catalog_max_chars',
        (v) => {'catalog_max_chars': v},
        lower: 1000,
        upper: 64000,
      );
    });

    test('reattach.per_skill_tokens is 0..16384; 0 switches reattach off', () {
      expectBounds(
        'skills.reattach.per_skill_tokens',
        (v) => {
          'reattach': {'per_skill_tokens': v},
        },
        lower: 0,
        upper: 16384,
      );
    });

    test('reattach.total_tokens is 0..200000; 0 switches reattach off', () {
      expectBounds(
        'skills.reattach.total_tokens',
        (v) => {
          'reattach': {'total_tokens': v},
        },
        lower: 0,
        upper: 200000,
      );
    });

    test('a wrong type is a type problem with the path of the key', () {
      final r = load([
        user(skills({'max_skills': 'many'})),
      ]);

      final issue = issuesAt(r, 'skills.max_skills').single;
      expect(issue.kind, ConfigIssueKind.type);
    });
  });

  group('skills.extra_roots', () {
    test('an element with a URI scheme is a value problem with the index '
        '(scenario "Схема зарезервирована")', () {
      final r = load([
        user(
          skills({
            'extra_roots': ['builtin://pdf'],
          }),
        ),
      ]);

      final issue = issuesAt(r, 'skills.extra_roots[0]').single;
      expect(issue.kind, ConfigIssueKind.value);
      expect(issue.message, contains('URI schemes are not supported'));
      expect(r.config, isNull);
    });

    test('the index names the offending element, not the first', () {
      final r = load([
        user(
          skills({
            'extra_roots': ['/ok', 'file:///etc'],
          }),
        ),
      ]);

      expect(issuesAt(r, 'skills.extra_roots[1]'), hasLength(1));
      expect(issuesAt(r, 'skills.extra_roots[0]'), isEmpty);
    });

    test('Q41: ~ and ~/dir are valid elements (expanded by the loader)', () {
      final r = load([
        user(
          skills({
            'extra_roots': ['~', '~/shared/skills'],
          }),
        ),
      ]);

      expect(r.issues, isEmpty, reason: r.issues.join('\n'));
      // Значение хранится как записано: раскрывает загрузчик (D16).
      expect(r.config!.skills.extraRoots, ['~', '~/shared/skills']);
    });

    test('Q41: ~user/dir is a value problem with the index', () {
      final r = load([
        user(
          skills({
            'extra_roots': ['/ok', '~bob/skills'],
          }),
        ),
      ]);

      final issue = issuesAt(r, 'skills.extra_roots[1]').single;
      expect(issue.kind, ConfigIssueKind.value);
      expect(
        issue.message,
        '~user is not supported in skills.extra_roots; use an absolute path '
        'or ~/',
      );
      expect(r.config, isNull);
    });

    test('a Windows drive path is not a scheme', () {
      final r = load([
        user(
          skills({
            'extra_roots': [r'C:\skills'],
          }),
        ),
      ]);

      expect(r.issues, isEmpty, reason: r.issues.join('\n'));
    });
  });

  group('skills.operative stays without a consumer', () {
    test('each explicit leaf gives one config.key.not_applied; max_skills '
        'is applied silently (scenario "operative без потребителя")', () {
      final r = load([
        user(
          skills({
            'operative': {
              'lines': ['Run tests.'],
            },
            'max_skills': 50,
          }),
        ),
      ]);

      expect(r.issues, isEmpty, reason: r.issues.join('\n'));
      final warnings = warningsOf(r, 'config.key.not_applied');
      expect([for (final w in warnings) w.key], ['skills.operative.lines']);
      expect(r.config!.skills.maxSkills, 50);
    });

    test('scenario "Ключ без потребителя": operative.max_tokens warns', () {
      final r = load([
        user({
          'loop': {'empty_response_retries': 3},
          ...skills({
            'operative': {'max_tokens': 1024},
          }),
        }),
      ]);

      expect(
        [for (final w in warningsOf(r, 'config.key.not_applied')) w.key],
        ['loop.empty_response_retries', 'skills.operative.max_tokens'],
      );
    });
  });

  group('profile.<name>.skills', () {
    test('is a known capability: off narrows, no not_applied', () {
      final r = load([
        user({
          'profile': {
            'embedded-cli': {'skills': 'off'},
          },
        }),
      ]);

      expect(r.issues, isEmpty, reason: r.issues.join('\n'));
      expect(warningsOf(r, 'config.key.not_applied'), isEmpty);
      expect(
        r.host!.profileNarrowing['embedded-cli']![HostCapability.skills],
        isA<CapabilityOff>(),
      );
    });
  });

  group('trust of the project layers (CFG-3)', () {
    test('skills.enabled: false and skills.disabled apply from any project '
        'layer, without a warning', () {
      final r = load([
        layer(baseValues()),
        project(
          skills({
            'enabled': false,
            'disabled': ['pdf'],
          }),
        ),
      ], projectRoot: '/proj');

      expect(r.config!.skills.enabled, isFalse);
      expect(r.config!.skills.disabled, ['pdf']);
      expect(warningsOf(r, 'config.project.untrusted_key'), isEmpty);
    });

    test('a decrease of numeric keys applies from the project layer', () {
      final r = load([
        layer(baseValues()),
        project(
          skills({
            'max_skills': 10,
            'catalog_max_chars': 2000,
            'reattach': {'per_skill_tokens': 100, 'total_tokens': 500},
          }),
        ),
      ], projectRoot: '/proj');

      final s = r.config!.skills;
      expect(s.maxSkills, 10);
      expect(s.catalogMaxChars, 2000);
      expect(s.reattachPerSkillTokens, 100);
      expect(s.reattachTotalTokens, 500);
      expect(warningsOf(r, 'config.project.untrusted_key'), isEmpty);
    });

    test('an increase from an untrusted project is dropped with '
        'config.project.untrusted_key, key by key', () {
      final r = load([
        layer(baseValues()),
        project(
          skills({
            'max_skills': 500,
            'catalog_max_chars': 20000,
            'reattach': {'per_skill_tokens': 9000, 'total_tokens': 100000},
          }),
        ),
      ], projectRoot: '/proj');

      final s = r.config!.skills;
      expect(s.maxSkills, 200);
      expect(s.catalogMaxChars, 8000);
      expect(s.reattachPerSkillTokens, 5000);
      expect(s.reattachTotalTokens, 25000);
      expect(
        [for (final w in warningsOf(r, 'config.project.untrusted_key')) w.key],
        [
          'skills.max_skills',
          'skills.catalog_max_chars',
          'skills.reattach.per_skill_tokens',
          'skills.reattach.total_tokens',
        ],
      );
    });

    test('Q40: a trusted project may raise the numeric keys, also from '
        '.codelab/config.yaml, without a warning', () {
      for (final kind in [
        ConfigLayerKind.project,
        ConfigLayerKind.projectLocal,
      ]) {
        final r = load([
          user(const {}, trusted: ['/proj']),
          project(
            skills({
              'max_skills': 500,
              'catalog_max_chars': 20000,
              'reattach': {'per_skill_tokens': 9000, 'total_tokens': 100000},
            }),
            kind: kind,
          ),
        ], projectRoot: '/proj');

        expect(r.issues, isEmpty, reason: r.issues.join('\n'));
        final s = r.config!.skills;
        expect(s.maxSkills, 500, reason: '$kind');
        expect(s.catalogMaxChars, 20000);
        expect(s.reattachPerSkillTokens, 9000);
        expect(s.reattachTotalTokens, 100000);
        expect(warningsOf(r, 'config.project.untrusted_key'), isEmpty);
      }
    });

    test('Q40: the bounds of the schema hold for a trusted project too', () {
      final r = load([
        user(const {}, trusted: ['/proj']),
        project(skills({'max_skills': 5000})),
      ], projectRoot: '/proj');

      expect(issuesAt(r, 'skills.max_skills'), hasLength(1));
    });

    test('an increase is compared with the global value, not the default', () {
      final r = load([
        user(skills({'max_skills': 50})),
        project(skills({'max_skills': 80})),
      ], projectRoot: '/proj');

      expect(r.config!.skills.maxSkills, 50);
      expect(warningsOf(r, 'config.project.untrusted_key'), hasLength(1));
    });

    test('extra_roots in .codelab/config.yaml is always dropped, even for a '
        'trusted project (scenario "Проект не даёт согласия")', () {
      final r = load([
        user(const {}, trusted: ['/proj']),
        project(
          skills({
            'extra_roots': ['~/.claude/skills'],
          }),
        ),
      ], projectRoot: '/proj');

      expect(r.config!.skills.extraRoots, isEmpty);
      final w = warningsOf(r, 'config.project.untrusted_key').single;
      expect(w.key, 'skills.extra_roots');
      expect(w.source, '/proj/.codelab/config.yaml');
    });

    test('extra_roots in config.local.yaml: applied for a trusted project', () {
      final r = load([
        user(const {}, trusted: ['/proj']),
        project(
          skills({
            'extra_roots': ['.claude/skills'],
          }),
          kind: ConfigLayerKind.projectLocal,
        ),
      ], projectRoot: '/proj');

      expect(r.config!.skills.extraRoots, ['.claude/skills']);
      expect(warningsOf(r, 'config.project.untrusted_key'), isEmpty);
    });

    test('extra_roots in config.local.yaml: dropped for an untrusted project '
        'with a warning', () {
      final r = load([
        layer(baseValues()),
        project(
          skills({
            'extra_roots': ['.claude/skills'],
          }),
          kind: ConfigLayerKind.projectLocal,
        ),
      ], projectRoot: '/proj');

      expect(r.config!.skills.extraRoots, isEmpty);
      final w = warningsOf(r, 'config.project.untrusted_key').single;
      expect(w.key, 'skills.extra_roots');
      expect(w.source, '/proj/.codelab/config.local.yaml');
    });

    test('the snapshot without the project keeps the global values', () {
      final r = load([
        user(skills({'max_skills': 100, 'disabled': <String>[]})),
        project(
          skills({
            'max_skills': 10,
            'disabled': ['pdf'],
          }),
        ),
      ], projectRoot: '/proj');

      expect(r.config!.skills.maxSkills, 10);
      final bare = r.config!.withoutProject!.skills;
      expect(bare.maxSkills, 100);
      expect(bare.disabled, isEmpty);
    });
  });

  group('settings registry', () {
    test('every skills.* key is fileOnly with a reason', () {
      const keys = [
        'skills.enabled',
        'skills.extra_roots',
        'skills.disabled',
        'skills.max_skills',
        'skills.catalog_max_chars',
        'skills.reattach.per_skill_tokens',
        'skills.reattach.total_tokens',
      ];
      for (final key in keys) {
        final d = SettingsRegistry.lookup(key);

        expect(d, isNotNull, reason: key);
        expect(
          d!.key,
          key,
          reason: 'a leaf descriptor, not the opaque section',
        );
        expect(d.scope, SettingScope.fileOnly, reason: key);
        expect(d.fileOnlyReason, isNotEmpty, reason: key);
      }
    });
  });
}
