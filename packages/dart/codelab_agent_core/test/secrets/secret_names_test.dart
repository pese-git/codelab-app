import 'package:codelab_agent_core/codelab_agent_core.dart';
import 'package:test/test.dart';

const _rule =
    'expected a secret name: lowercase letters, digits and . _ / -, '
    'up to 128 characters';

/// Имена секретов (agent-secrets «Имена секретов»; design.md change
/// `add-agent-secret-store`, D2; `agent-core-architecture` §17.5.2).
void main() {
  group('the rule', () {
    test('accepts lowercase names with . _ / - and up to 128 characters', () {
      for (final name in [
        'a',
        'codelab/openai',
        'codelab/mcp/github/authorization',
        'my.key_1-b',
        '0abc',
        'a' * 128,
      ]) {
        expect(SecretNames.problem(name), isNull, reason: name);
        expect(SecretNames.pattern.hasMatch(name), isTrue, reason: name);
      }
    });

    test('rejects other names with the rule text, never with the name', () {
      final bad = [
        'Codelab/OpenAI',
        'a/../b',
        'a..b',
        'codelab/',
        'my key',
        'a' * 129,
        '',
        '/abc',
        '-abc',
        '.abc',
        'tab\tname',
        'sk-Test Secret-0123456789',
        'ключ',
      ];
      for (final name in bad) {
        final problem = SecretNames.problem(name);
        expect(problem, _rule, reason: name);
        if (name.isNotEmpty) {
          expect(problem, isNot(contains(name)), reason: name);
        }
      }
    });
  });

  group('envOverride', () {
    test('uppercases and maps every character outside [A-Z0-9] to _', () {
      expect(
        SecretNames.envOverride('codelab/mcp/github/authorization'),
        'CODELAB_SECRET_CODELAB_MCP_GITHUB_AUTHORIZATION',
      );
      expect(
        SecretNames.envOverride('codelab/anthropic'),
        'CODELAB_SECRET_CODELAB_ANTHROPIC',
      );
    });

    test('is not reversible: two names may share one variable', () {
      expect(
        SecretNames.envOverride('codelab/a-b'),
        SecretNames.envOverride('codelab/a.b'),
      );
      expect(
        SecretNames.envOverride('codelab/a-b'),
        'CODELAB_SECRET_CODELAB_A_B',
      );
    });
  });

  group('suggestFor and forMcp', () {
    test('a provider key suggests codelab/<id>', () {
      expect(
        SecretNames.suggestFor('providers.openai.api_key'),
        'codelab/openai',
      );
      expect(
        SecretNames.suggestFor('providers.openai.headers.X-Key'),
        'codelab/openai',
      );
    });

    test('an MCP env or header suggests codelab/mcp/<server>/<key>', () {
      expect(
        SecretNames.suggestFor('mcp.servers[GitHub].headers.Authorization'),
        'codelab/mcp/github/authorization',
      );
      expect(
        SecretNames.suggestFor('mcp.servers[gh].env.GITHUB_TOKEN'),
        'codelab/mcp/gh/github_token',
      );
      expect(
        SecretNames.suggestFor('mcp.servers[github].token'),
        'codelab/mcp/github/token',
      );
      expect(
        SecretNames.forMcp('GitHub', 'Authorization'),
        'codelab/mcp/github/authorization',
      );
    });

    test('a path without a rule falls back to the codelab/ prefix', () {
      // agent-secrets «Предлагаемое имя ключа элемента MCP и запасной
      // вариант»: ключ элемента и запасной путь.
      expect(
        SecretNames.suggestFor('mcp.servers[GitHub].token'),
        'codelab/mcp/github/token',
      );
      final fallback = SecretNames.suggestFor('tools.exec.Api Token');
      expect(fallback, startsWith('codelab/'));
      expect(fallback, 'codelab/tools.exec.api-token');
      expect(SecretNames.problem(fallback), isNull);
    });

    test('a search backend suggests codelab/search-<b>', () {
      expect(
        SecretNames.suggestFor('tools.web.search.backends.brave.api_key'),
        'codelab/search-brave',
      );
    });

    test('the result always passes the rule', () {
      final paths = [
        'providers.My_Provider.api_key',
        'providers._x.api_key',
        'providers.-.api_key',
        'providers..api_key',
        'providers.${'p' * 300}.api_key',
        'mcp.servers[Ünï cödé].env.KEY',
        'mcp.servers[..].headers...',
        'mcp.servers[${'S' * 300}].headers.${'K' * 300}',
        'mcp.servers[a/b].env.C/D',
        'tools.web.search.backends._.api_key',
        'tools.web.search.backends.${'b' * 300}.api_key',
        'something.else.entirely',
        '',
      ];
      for (final path in paths) {
        expect(
          SecretNames.problem(SecretNames.suggestFor(path)),
          isNull,
          reason: path,
        );
      }
      for (final (server, key) in [
        ('', ''),
        ('..', '..'),
        ('A B', 'C/D'),
        ('S' * 300, 'K' * 300),
        ('_', '_'),
      ]) {
        expect(
          SecretNames.problem(SecretNames.forMcp(server, key)),
          isNull,
          reason: '$server/$key',
        );
      }
    });
  });
}
