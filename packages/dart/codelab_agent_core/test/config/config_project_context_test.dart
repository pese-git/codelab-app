import 'package:codelab_agent_core/codelab_agent_core.dart';
import 'package:test/test.dart';

import 'config_support.dart';

/// Ключ `tools.project_context.max_bytes` и `CoreConfig.trustedProjects`
/// (agent-configuration «Ключ tools.project_context.max_bytes», «Доверенные
/// проекты в CoreConfig»; design.md change `add-agent-project-files`, D4, D5;
/// CFG-3).
void main() {
  const key = 'tools.project_context.max_bytes';

  ConfigTree user(Map<String, Object?> extra, {List<String>? trusted}) =>
      layer(withValues(baseValues(), {...extra, 'trusted_projects': ?trusted}));

  ConfigTree project(int bytes) => layer({
    'tools': {
      'project_context': {'max_bytes': bytes},
    },
  }, kind: ConfigLayerKind.project);

  Map<String, Object?> setting(int bytes) => {
    'tools': {
      'project_context': {'max_bytes': bytes},
    },
  };

  group('the value', () {
    test('is 32 KiB by default', () {
      final result = load([layer(baseValues())]);

      expect(result.config!.projectContextMaxBytes, 32768);
    });

    test('is read from the config; 0 and the upper bound are valid', () {
      for (final value in [0, 1, 4096, 262144]) {
        final result = load([user(setting(value))]);

        expect(result.issues, isEmpty, reason: '$value');
        expect(result.config!.projectContextMaxBytes, value);
      }
    });

    test('outside 0..262144 is a problem with the path of the key', () {
      for (final value in [-1, 262145]) {
        final result = load([user(setting(value))]);

        expect(issuesAt(result, key), hasLength(1), reason: '$value');
        expect(result.config, isNull);
      }
    });

    test('is applied: no config.key.not_applied', () {
      final result = load([user(setting(4096))]);

      expect(warningsOf(result, 'config.key.not_applied'), isEmpty);
    });
  });

  group('an untrusted project can only lower it', () {
    test('an increase over the default is dropped with a warning', () {
      final result = load([
        layer(baseValues()),
        project(200000),
      ], projectRoot: '/proj');

      expect(result.config!.projectContextMaxBytes, 32768);
      final warnings = warningsOf(result, 'config.project.untrusted_key');
      expect([for (final w in warnings) w.key], [key]);
    });

    test('a decrease is accepted without a warning', () {
      final result = load([
        layer(baseValues()),
        project(4096),
      ], projectRoot: '/proj');

      expect(result.config!.projectContextMaxBytes, 4096);
      expect(warningsOf(result, 'config.project.untrusted_key'), isEmpty);
    });

    test('is compared with the global value, not with the default', () {
      final raised = load([
        user(setting(8192)),
        project(16384),
      ], projectRoot: '/proj');
      final lowered = load([
        user(setting(8192)),
        project(2048),
      ], projectRoot: '/proj');

      expect(raised.config!.projectContextMaxBytes, 8192);
      expect(warningsOf(raised, 'config.project.untrusted_key'), hasLength(1));
      expect(lowered.config!.projectContextMaxBytes, 2048);
    });

    test('a trusted project may raise it', () {
      final result = load([
        user(const {}, trusted: ['/proj']),
        project(200000),
      ], projectRoot: '/proj');

      expect(result.config!.projectContextMaxBytes, 200000);
      expect(warningsOf(result, 'config.project.untrusted_key'), isEmpty);
    });

    test('the snapshot without the project keeps the global value', () {
      final result = load([
        user(setting(8192), trusted: ['/proj']),
        project(100),
      ], projectRoot: '/proj');

      expect(result.config!.projectContextMaxBytes, 100);
      expect(result.config!.withoutProject!.projectContextMaxBytes, 8192);
    });
  });

  group('trustedProjects', () {
    test('lists the roots of the global config in the full snapshot and in '
        'withoutProject', () {
      final result = load([
        user(const {}, trusted: ['/work/a', '/work/b']),
        project(4096),
      ], projectRoot: '/work/a');

      final config = result.config!;
      expect(config.trustedProjects, ['/work/a', '/work/b']);
      expect(config.withoutProject!.trustedProjects, ['/work/a', '/work/b']);
    });

    test('are empty by default', () {
      final result = load([layer(baseValues())]);

      expect(result.config!.trustedProjects, isEmpty);
    });

    test('a project layer does not change the list (CFG-3)', () {
      final result = load([
        user(const {}, trusted: ['/work/a']),
        layer({
          'trusted_projects': ['/evil'],
        }, kind: ConfigLayerKind.project),
      ], projectRoot: '/work/a');

      expect(result.config!.trustedProjects, ['/work/a']);
    });
  });
}
