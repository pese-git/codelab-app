import 'package:codelab_agent_core/codelab_agent_core.dart';
import 'package:test/test.dart';

import 'config_support.dart';

const _secret = 'sk-test-0123456789abcdef';

/// Ключ значением в конфиге (agent-configuration «Секреты только ссылками»,
/// сценарии «Ключ значением» и «Токен значением у MCP-сервера»;
/// `core/config-rejects-inline-api-key`, пункт 1 CFG-9; design.md change
/// `add-agent-secret-store`, D2).
void main() {
  group('providers.*', () {
    for (final key in ['api_key', 'apiKey', 'token', 'secret', 'password']) {
      test('$key: the problem names the command and the reference, never the '
          'value', () {
        final result = load([
          layer(
            withValues(baseValues(), {
              'providers': {
                'openai': {
                  'kind': 'openai-compatible',
                  'base_url': 'https://llm.test/v1',
                  key: _secret,
                },
              },
            }),
          ),
        ]);

        final issue = issuesAt(result, 'providers.openai.$key').single;
        expect(issue.kind, ConfigIssueKind.inlineSecret);
        expect(issue.message, contains('codelab secret set codelab/openai'));
        expect(issue.message, contains('api_key_secret: codelab/openai'));
        expect(result.issues.join('\n'), isNot(contains(_secret)));

        try {
          result.orThrow();
          fail('must throw');
        } on ConfigInlineSecretException catch (error) {
          expect(error.key, 'providers.openai.$key');
          expect(error.suggestedSecretName, 'codelab/openai');
          expect('$error', isNot(contains(_secret)));
        }
      });
    }

    test('a provider id outside the name alphabet still gives a valid '
        'suggestion', () {
      final result = load([
        layer(
          withValues(baseValues(), {
            'providers': {
              'my_provider': {'api_key': _secret},
            },
          }),
        ),
      ]);

      final issue = issuesAt(result, 'providers.my_provider.api_key').single;
      expect(issue.message, contains('codelab secret set codelab/my_provider'));
      expect(SecretNames.problem((result.orThrowSuggestion())), isNull);
    });
  });

  group('mcp.servers', () {
    test('a token value names the command and the \${secret:…} form', () {
      final result = load([
        layer(
          withValues(baseValues(), {
            'mcp': {
              'servers': [
                {
                  'name': 'github',
                  'type': 'http',
                  'url': 'https://gh.test/mcp',
                  'token': _secret,
                },
              ],
            },
          }),
        ),
      ]);

      final issue = issuesAt(result, 'mcp.servers[github].token').single;
      expect(issue.kind, ConfigIssueKind.inlineSecret);
      expect(
        issue.message,
        contains('codelab secret set codelab/mcp/github/token'),
      );
      expect(issue.message, contains(r'${secret:codelab/mcp/github/token}'));
      expect(result.issues.join('\n'), isNot(contains(_secret)));
      expect(result.orThrowSuggestion(), 'codelab/mcp/github/token');
    });
  });
}

extension on ConfigLoadResult {
  /// `suggestedSecretName` исключения, которое бросает `orThrow`.
  String orThrowSuggestion() {
    try {
      orThrow();
    } on ConfigInlineSecretException catch (error) {
      return error.suggestedSecretName;
    }
    throw StateError('orThrow must throw ConfigInlineSecretException');
  }
}
