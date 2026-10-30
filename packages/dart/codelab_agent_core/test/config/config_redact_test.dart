import 'package:codelab_agent_core/codelab_agent_core.dart';
import 'package:test/test.dart';

import 'config_support.dart';

/// Ключи редакции секретов (agent-configuration «Ключи редакции
/// секретов»; `agent-core-architecture` §12.4.3, §15.3).
void main() {
  test('defaults: enabled, six layers without entropy, git_sha and uuid', () {
    final result = load([layer(baseValues())]);

    final redact = result.config!.redact;
    expect(redact.enabled, isTrue);
    expect(redact.layers, [
      'exact',
      'credential_files',
      'formats',
      'pem',
      'connection_strings',
      'key_values',
    ]);
    expect(redact.allowlistBuiltin, ['git_sha', 'uuid']);
    expect(redact.allowlistPatterns, isEmpty);
    expect(redact.exemptTools, isEmpty);
  });

  test('checked values reach CoreConfig.redact; keys are not applied yet', () {
    final result = load([
      layer(
        withValues(baseValues(), {
          'redact': {
            'layers': ['exact', 'entropy'],
            'allowlist': {
              'builtin': ['uuid'],
              'patterns': [r'^corp-\d+$'],
            },
            'exempt_tools': ['search'],
          },
        }),
      ),
    ]);

    expect(result.issues, isEmpty, reason: result.issues.join('\n'));
    final redact = result.config!.redact;
    expect(redact.layers, ['exact', 'entropy']);
    expect(redact.allowlistBuiltin, ['uuid']);
    expect(redact.allowlistPatterns, [r'^corp-\d+$']);
    expect(redact.exemptTools, ['search']);
    expect([
      for (final w in warningsOf(result, 'config.key.not_applied')) w.key,
    ], isNotEmpty);
  });

  test('an unknown layer name is a problem with its index', () {
    final result = load([
      layer(
        withValues(baseValues(), {
          'redact': {
            'layers': ['exact', 'bogus'],
          },
        }),
      ),
    ]);

    expect(issuesAt(result, 'redact.layers[1]'), hasLength(1));
    expect(result.config, isNull);
  });

  test('an unknown builtin allowlist entry is a problem', () {
    final result = load([
      layer(
        withValues(baseValues(), {
          'redact': {
            'allowlist': {
              'builtin': ['md5'],
            },
          },
        }),
      ),
    ]);

    expect(issuesAt(result, 'redact.allowlist.builtin[0]'), hasLength(1));
  });

  test('an uncompilable pattern names the key path with the index', () {
    final result = load([
      layer(
        withValues(baseValues(), {
          'redact': {
            'allowlist': {
              'patterns': ['[a-'],
            },
          },
        }),
        positions: {'redact.allowlist.patterns[0]': const ConfigPosition(9, 7)},
      ),
    ]);

    final issue = issuesAt(result, 'redact.allowlist.patterns[0]').single;
    expect(issue.kind, ConfigIssueKind.value);
    expect((issue.line, issue.column), (9, 7));
    expect(result.config, isNull);
  });

  group('rules of an untrusted project (§15.3, §12.4.3)', () {
    ConfigLoadResult withProject(
      Map<String, Object?> project, {
      Map<String, Object?> user = const {},
      bool trusted = false,
    }) => load([
      layer(
        withValues(withValues(baseValues(), user), {
          if (trusted) 'trusted_projects': ['/proj'],
        }),
      ),
      layer(project, kind: ConfigLayerKind.project),
    ], projectRoot: '/proj');

    test('enabled: false and new patterns are dropped with two warnings', () {
      final result = withProject({
        'redact': {
          'enabled': false,
          'allowlist': {
            'patterns': ['x+'],
          },
        },
      });

      expect(result.config!.redact.enabled, isTrue);
      expect(result.config!.redact.allowlistPatterns, isEmpty);
      expect(
        [
          for (final w in warningsOf(result, 'config.project.untrusted_key'))
            w.key,
        ],
        ['redact.enabled', 'redact.allowlist.patterns'],
      );
    });

    test('enabled: true, added layers and removed allowlist entries pass', () {
      final result = withProject({
        'redact': {
          'enabled': true,
          'layers': [
            'exact',
            'credential_files',
            'formats',
            'pem',
            'connection_strings',
            'key_values',
            'entropy',
          ],
          'allowlist': {
            'builtin': ['uuid'],
          },
        },
      });

      expect(warningsOf(result, 'config.project.untrusted_key'), isEmpty);
      expect(result.config!.redact.layers, contains('entropy'));
      expect(result.config!.redact.allowlistBuiltin, ['uuid']);
    });

    test('removed layers and new exempt tools are dropped', () {
      final result = withProject({
        'redact': {
          'layers': ['exact'],
          'exempt_tools': ['exec'],
        },
      });

      expect(result.config!.redact.layers, hasLength(6));
      expect(result.config!.redact.exemptTools, isEmpty);
      expect(
        [
          for (final w in warningsOf(result, 'config.project.untrusted_key'))
            w.key,
        ],
        ['redact.layers', 'redact.exempt_tools'],
      );
    });

    test('a project that repeats the global patterns is not a widening', () {
      final result = withProject(
        {
          'redact': {
            'allowlist': {
              'patterns': ['a+'],
            },
          },
        },
        user: {
          'redact': {
            'allowlist': {
              'patterns': ['a+', 'b+'],
            },
          },
        },
      );

      expect(warningsOf(result, 'config.project.untrusted_key'), isEmpty);
      expect(result.config!.redact.allowlistPatterns, ['a+']);
    });

    test('a trusted project applies all redact keys', () {
      final result = withProject({
        'redact': {
          'enabled': false,
          'allowlist': {
            'patterns': ['x+'],
          },
          'exempt_tools': ['exec'],
        },
      }, trusted: true);

      expect(result.config!.redact.enabled, isFalse);
      expect(result.config!.redact.allowlistPatterns, ['x+']);
      expect(result.config!.redact.exemptTools, ['exec']);
      expect(warningsOf(result, 'config.project.untrusted_key'), isEmpty);
    });
  });
}
