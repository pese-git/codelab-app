import 'package:codelab_agent_core/codelab_agent_core.dart';
import 'package:test/test.dart';

import 'config_support.dart';

const _secret = 'sk-test-secret';

/// Секреты только ссылками (agent-configuration «Секреты только
/// ссылками»; CFG-2; `core/config-rejects-inline-api-key`; design.md change
/// `add-agent-configuration`, D8).
void main() {
  group('an inline secret', () {
    for (final key in ['api_key', 'apiKey', 'token', 'secret', 'password']) {
      test('$key in providers.* is rejected without the value', () {
        final result = load([
          layer(
            withValues(baseValues(), {
              'providers': {
                'p': {key: _secret},
              },
            }),
          ),
        ]);

        final issue = issuesAt(result, 'providers.p.$key').single;
        expect(issue.kind, ConfigIssueKind.inlineSecret);
        expect(issue.message, contains('api_key_env'));
        expect(result.issues.join('\n'), isNot(contains(_secret)));
        expect(result.config, isNull);
      });
    }

    test('in an mcp.servers item is rejected too', () {
      final result = load([
        layer(
          withValues(baseValues(), {
            'mcp': {
              'servers': [
                {
                  'name': 'gh',
                  'type': 'http',
                  'url': 'https://gh.test/mcp',
                  'token': _secret,
                },
              ],
            },
          }),
        ),
      ]);

      final issue = issuesAt(result, 'mcp.servers[gh].token').single;
      expect(issue.kind, ConfigIssueKind.inlineSecret);
      expect(result.issues.join('\n'), isNot(contains(_secret)));
    });

    test('orThrow throws ConfigInlineSecretException with the key path', () {
      final result = load([
        layer(
          withValues(baseValues(), {
            'providers': {
              'p': {'api_key': _secret},
            },
          }),
        ),
      ]);

      try {
        result.orThrow();
        fail('must throw');
      } on ConfigInlineSecretException catch (error) {
        expect(error.key, 'providers.p.api_key');
        expect(error.toString(), isNot(contains(_secret)));
      }
    });
  });

  group('api_key_env', () {
    Map<String, Object?> withKeyEnv() => withValues(baseValues(), {
      'providers': {
        'p': {'api_key_env': 'OPENAI_API_KEY'},
      },
    });

    test('is not read at load time: the provider keeps a reference', () {
      final result = load(
        [layer(withKeyEnv())],
        environment: {'OPENAI_API_KEY': _secret},
      );

      final config = result.config!;
      expect(config.providers.single.config.apiKey, isNull);
      expect(config.providers.single.key, isA<EnvKeyRef>());
      expect(config.providerProblems, isEmpty);
      expect(result.warnings, isEmpty);
      expect(result.warnings.join(), isNot(contains(_secret)));
    });

    test('an unset variable is a warning and a provider problem, not an '
        'error', () {
      final result = load([layer(withKeyEnv())]);

      expect(result.issues, isEmpty);
      final warning = warningsOf(result, 'config.provider.key_missing').single;
      expect(warning.fields, {'provider': 'p', 'variable': 'OPENAI_API_KEY'});
      expect(
        result.config!.providerProblems['p'],
        'API key variable OPENAI_API_KEY is not set',
      );
      expect(result.config!.providers.single.config.apiKey, isNull);
    });

    test('an empty variable counts as unset', () {
      final result = load(
        [layer(withKeyEnv())],
        environment: {'OPENAI_API_KEY': ''},
      );

      expect(result.config!.providerProblems, contains('p'));
    });

    test('together with api_key_secret is a problem', () {
      final result = load([
        layer(
          withValues(baseValues(), {
            'providers': {
              'p': {'api_key_env': 'K', 'api_key_secret': 'codelab/p'},
            },
          }),
        ),
      ]);

      final issue = issuesAt(result, 'providers.p.api_key_secret').single;
      expect(issue.kind, ConfigIssueKind.value);
      expect(issue.message, contains('mutually exclusive'));
    });
  });

  test('no value of a key variable appears in any message', () {
    final result = load(
      [
        layer(
          withValues(baseValues(), {
            'providers': {
              'p': {'api_key_env': 'K'},
            },
            'budget': {'max_steps': 0},
          }),
        ),
      ],
      environment: {'K': _secret},
    );

    expect(result.issues, isNotEmpty);
    expect(result.issues.join('\n'), isNot(contains(_secret)));
    expect(result.warnings.join('\n'), isNot(contains(_secret)));
  });

  group('names of references', () {
    test('api_key_env that is not a variable name is a problem without the '
        'value anywhere', () {
      for (final bad in [_secret, 'has space', '1ABC', '']) {
        final result = load(
          [
            layer(
              withValues(baseValues(), {
                'providers': {
                  'p': {'api_key_env': bad},
                },
              }),
            ),
          ],
          environment: {bad: 'value'},
        );

        final issue = issuesAt(result, 'providers.p.api_key_env').single;
        expect(issue.kind, ConfigIssueKind.value, reason: bad);
        expect(issue.message, 'expected an environment variable name');
        expect(result.config, isNull);
        expect(
          [...result.issues, ...result.warnings].join('\n'),
          isNot(contains(_secret)),
        );
      }
    });

    test(r'api_key_secret and ${secret:...} follow the secret name rule', () {
      final result = load([
        layer(
          withValues(baseValues(), {
            'providers': {
              'p': {'api_key_secret': 'Bad Name'},
            },
            'mcp': {
              'servers': [
                {
                  'name': 'gh',
                  'type': 'http',
                  'url': 'https://gh.test/mcp',
                  'headers': {'A': r'${secret:Bad Name}'},
                },
              ],
            },
          }),
        ),
      ]);

      expect(issuesAt(result, 'providers.p.api_key_secret'), hasLength(1));
      expect(issuesAt(result, 'mcp.servers[gh].headers.A'), hasLength(1));
      expect(result.issues.join('\n'), isNot(contains('Bad Name')));
    });

    test('a valid secret name passes', () {
      final result = load([
        layer(
          withValues(baseValues(), {
            'providers': {
              'p': {'api_key_secret': 'codelab/anthropic'},
            },
          }),
        ),
      ]);

      expect(result.issues, isEmpty);
    });
  });
}
