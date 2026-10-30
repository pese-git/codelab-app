import 'package:codelab_agent_core/codelab_agent_core.dart';
import 'package:codelab_agent_core/src/config/interpolate.dart';
import 'package:test/test.dart';

import 'config_support.dart';

/// Подстановка переменных окружения (agent-configuration «Подстановка
/// переменных окружения»; `agent-core-architecture` §15.5).
void main() {
  group('expandEnvironment', () {
    test(r'expands ${NAME}', () {
      final result = expandEnvironment(r'Bearer ${TOKEN}!', {'TOKEN': 'abc'});

      expect(result.text, 'Bearer abc!');
      expect(result.missing, isEmpty);
    });

    test(r'$${ is a literal ${ and $NAME is a literal', () {
      final result = expandEnvironment(r'$${HOME} $HOME', {'HOME': '/h'});

      expect(result.text, r'${HOME} $HOME');
    });

    test('the result is not expanded again', () {
      final result = expandEnvironment(r'${A}', {'A': r'${B}', 'B': 'x'});

      expect(result.text, r'${B}');
    });

    test('a missing variable is reported by name, not replaced by empty', () {
      final result = expandEnvironment(r'${MISSING}-${OK}', {'OK': '1'});

      expect(result.missing, ['MISSING']);
    });

    test('a bad name and an unclosed brace stay literal', () {
      final result = expandEnvironment(r'${1X} ${OPEN', {});

      expect(result.text, r'${1X} ${OPEN');
      expect(result.missing, isEmpty);
    });

    test(r'${secret:name} is recognized separately', () {
      final result = expandEnvironment(r'Bearer ${secret:codelab/gh}', {});

      expect(result.secretRefs, ['codelab/gh']);
      expect(result.missing, isEmpty);
    });
  });

  group('allowed keys', () {
    ConfigLoadResult withServer(
      Map<String, Object?> server, {
      Map<String, String> environment = const {},
      Map<String, Object?> extra = const {},
    }) => load([
      layer(
        withValues(withValues(baseValues(), extra), {
          'mcp': {
            'servers': [server],
          },
        }),
      ),
    ], environment: environment);

    test('substitution in headers, args, env and url; literals elsewhere', () {
      final result = withServer(
        {
          'name': 'github',
          'type': 'http',
          'url': r'https://${HOST}/mcp',
          'headers': {'Authorization': r'Bearer ${GITHUB_TOKEN}'},
        },
        environment: {'GITHUB_TOKEN': 'tok-test-secret', 'HOST': 'gh.test'},
      );
      final stdio = withServer(
        {
          'name': 'local',
          'type': 'stdio',
          'command': 'srv',
          'args': [r'$${HOME}', r'$HOME', r'--key=${KEY}'],
          'env': {'K': r'${KEY}'},
        },
        environment: {'KEY': 'k1'},
      );

      final http = result.config!.mcpServers.single as McpHttpServerConfig;
      expect(http.url.toString(), 'https://gh.test/mcp');
      expect(http.headers, [('Authorization', 'Bearer tok-test-secret')]);
      final proc = stdio.config!.mcpServers.single as McpStdioServerConfig;
      expect(proc.args, [r'${HOME}', r'$HOME', '--key=k1']);
      expect(proc.env, {'K': 'k1'});
    });

    test(r'${X} in agent.default_model is not expanded', () {
      final result = load(
        [
          layer({
            'providers': {
              'p': {
                'kind': 'openai-compatible',
                'base_url': 'https://llm.test/v1',
                'models': {r'${X}': <String, Object?>{}},
              },
            },
            'agent': {'default_model': r'p/${X}'},
          }),
        ],
        environment: {'X': 'zzz'},
      );

      expect(result.issues, isEmpty, reason: result.issues.join('\n'));
      expect(result.config!.defaultModel.id, r'${X}');
    });

    test('provider base_url and headers are expanded', () {
      final result = load(
        [
          layer(
            withValues(baseValues(), {
              'providers': {
                'p': {
                  'base_url': r'https://${HOST}/v1',
                  'headers': {'X-Org': r'${ORG}'},
                },
              },
            }),
          ),
        ],
        environment: {'HOST': 'llm.example', 'ORG': 'acme'},
      );

      final provider = result.config!.providers.single.config;
      expect(provider.baseUrl.toString(), 'https://llm.example/v1');
      expect(provider.headers, {'X-Org': 'acme'});
    });

    test('an unset variable is a problem with the key path and the name', () {
      final result = withServer({
        'name': 'github',
        'type': 'http',
        'url': 'https://gh.test/mcp',
        'headers': {'Authorization': r'Bearer ${GITHUB_TOKEN}'},
      });

      final issue = issuesAt(
        result,
        'mcp.servers[github].headers.Authorization',
      ).single;
      expect(issue.kind, ConfigIssueKind.value);
      expect(issue.message, 'variable GITHUB_TOKEN is not set');
      expect(result.config, isNull);
    });

    test('values of variables never reach messages', () {
      final result = withServer(
        {
          'name': 'github',
          'type': 'http',
          'url': 'https://gh.test/mcp',
          'headers': {
            'Authorization': r'Bearer ${GITHUB_TOKEN}',
            'X-Other': r'${MISSING}',
          },
        },
        environment: {'GITHUB_TOKEN': 'tok-test-secret'},
      );

      expect(result.issues, isNotEmpty);
      expect(result.issues.join('\n'), isNot(contains('tok-test-secret')));
    });
  });
}
