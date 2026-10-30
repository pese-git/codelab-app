import 'package:codelab_agent_core/codelab_agent_core.dart';
import 'package:test/test.dart';

import 'config_support.dart';

/// Ключи без потребителя (agent-configuration, сценарий «Ключ без
/// потребителя»; design.md change `add-agent-configuration`, D6, OQ4 (а)).
void main() {
  test('an explicit key without a consumer gives one warning with key and '
      'source', () {
    final result = load([
      layer(
        withValues(baseValues(), {
          'loop': {'empty_response_retries': 3},
          'skills': {'max_skills': 100},
          'redact': {'enabled': true},
        }),
        source: '/h/config.yaml',
        positions: {'loop.empty_response_retries': const ConfigPosition(4, 3)},
      ),
    ]);

    expect(result.issues, isEmpty, reason: result.issues.join('\n'));
    expect(result.config, isNotNull);
    final warnings = warningsOf(result, 'config.key.not_applied');
    expect(
      [for (final w in warnings) w.key],
      ['loop.empty_response_retries', 'skills.max_skills', 'redact.enabled'],
    );
    expect(warnings.first.source, '/h/config.yaml');
    expect(warnings.first.fields, {
      'key': 'loop.empty_response_retries',
      'source': '/h/config.yaml',
    });
    expect(warnings.first.line, 4);
  });

  test('a key set by two layers gives one warning, from the later layer', () {
    final result = load([
      layer(
        withValues(baseValues(), {
          'loop': {'empty_response_retries': 3},
        }),
        source: '/a.yaml',
      ),
      layer(
        {
          'loop': {'empty_response_retries': 1},
        },
        kind: ConfigLayerKind.projectLocal,
        source: '/b.yaml',
      ),
    ], projectRoot: '/proj');

    final warnings = warningsOf(result, 'config.key.not_applied');
    expect(warnings, hasLength(1));
    expect(warnings.single.source, '/b.yaml');
  });

  test('a built-in default of a key without a consumer gives no warning', () {
    final result = load([
      layer(
        {
          'loop': {'empty_response_retries': 2},
        },
        kind: ConfigLayerKind.defaults,
        source: 'defaults',
      ),
      layer(baseValues()),
    ]);

    expect(result.warnings, isEmpty);
  });

  test('keys with a consumer give no warning', () {
    final result = load([
      layer(
        withValues(baseValues(), {
          'budget': {'max_steps': 5},
          'compaction': {'enabled': true},
        }),
      ),
    ]);

    expect(result.warnings, isEmpty);
  });

  test('nested keys of an after-MVP provider key are named by leaf', () {
    final result = load([
      layer(
        withValues(baseValues(), {
          'providers': {
            'p': {'key_cooldown': '60s', 'list_models': false},
          },
        }),
      ),
    ]);

    expect(
      [for (final w in warningsOf(result, 'config.key.not_applied')) w.key],
      ['providers.p.key_cooldown', 'providers.p.list_models'],
    );
  });
}
