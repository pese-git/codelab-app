import 'package:codelab_agent_core/codelab_agent_core.dart';
import 'package:test/test.dart';

import 'config_support.dart';

const _secret = 'sk-test-0123456789abcdef';

/// Ключ значением в файле конфига (agent-configuration «Секреты только
/// ссылками», сценарии «Ключ значением» и «Токен значением у MCP-сервера»;
/// `core/config-warns-inline-api-key`, заменяет
/// `core/config-rejects-inline-api-key`; пункт 1 CFG-9; design.md change
/// `add-config-literal-secrets-and-migrate`, D4, R8-4).
///
/// До R8-4 литерал давал проблему загрузки `inlineSecret`; теперь файловый
/// слой даёт предупреждение `config.secret.in_file`, а загрузка идёт дальше.
void main() {
  Map<String, Object?> openai(Map<String, Object?> extra) =>
      withValues(baseValues(), {
        'providers': {
          'openai': {
            'kind': 'openai-compatible',
            'base_url': 'https://llm.test/v1',
            ...extra,
          },
        },
      });

  group('providers.*', () {
    test('api_key: a warning with the migrate command, and it is the '
        'provider key', () {
      final result = load([
        layer(openai({'api_key': _secret})),
      ]);

      expect(result.issues, isEmpty, reason: result.issues.join('\n'));
      final warning = warningsOf(result, 'config.secret.in_file').single;
      expect(warning.key, 'providers.openai.api_key');
      expect(
        '${warning.key}: ${warning.message}',
        'providers.openai.api_key: a secret is stored in the config file; '
            'move it to the secret store: codelab secret migrate',
      );
      expect(warning.source, '/home/u/.codelab/config.yaml');
      expect(warning.fields, {
        'key': 'providers.openai.api_key',
        'source': '/home/u/.codelab/config.yaml',
      });
      final provider = result.config!.providers.firstWhere(
        (p) => p.config.name == 'openai',
      );
      expect(provider.config.apiKey, _secret);
      expect(provider.key, isNull, reason: 'the value needs no resolver');
      expect(result.config!.providerProblems, isEmpty);
      expect(warningsOf(result, 'config.provider.key_missing'), isEmpty);
    });

    test('no value is in any warning, in toString, or in the problems', () {
      final result = load([
        layer(openai({'api_key': _secret})),
      ]);

      expect(result.warnings.join('\n'), isNot(contains(_secret)));
      expect(
        result.warnings.map((w) => w.fields.toString()).join(),
        isNot(contains(_secret)),
      );
      expect(result.issues.join('\n'), isNot(contains(_secret)));
    });

    test('orThrow does not throw for a file literal: it is a warning', () {
      final result = load([
        layer(openai({'api_key': _secret})),
      ]);

      expect(result.orThrow, returnsNormally);
    });

    for (final key in ['apiKey', 'token', 'secret', 'password']) {
      test('$key: a warning, the key is not applied', () {
        final result = load([
          layer(openai({key: _secret})),
        ]);

        expect(result.issues, isEmpty, reason: result.issues.join('\n'));
        expect(warningsOf(result, 'config.secret.in_file').map((w) => w.key), [
          'providers.openai.$key',
        ]);
        final provider = result.config!.providers.firstWhere(
          (p) => p.config.name == 'openai',
        );
        expect(provider.config.apiKey, isNull);
        expect(provider.key, isNull);
        expect(result.warnings.join('\n'), isNot(contains(_secret)));
      });
    }

    test('a provider id outside the name alphabet keeps a valid '
        'suggestion in the command of CODELAB_CONFIG', () {
      final result = load([
        layer(baseValues()),
        layer({
          'providers': {
            'my_provider': {
              'kind': 'openai-compatible',
              'base_url': 'https://llm.test/v1',
              'api_key': _secret,
            },
          },
        }, kind: ConfigLayerKind.extra),
      ]);

      final warning = warningsOf(result, 'config.secret.in_file').single;
      expect(
        warning.message,
        endsWith('codelab secret set codelab/my_provider'),
      );
    });
  });

  group('mcp.servers', () {
    test('a token value: a warning, the server loads, the field is not '
        'applied', () {
      final result = load([
        layer(
          withValues(baseValues(), {
            'mcp': {
              'servers': [
                {
                  'name': 'github',
                  'type': 'http',
                  'url': 'https://gh.test/mcp',
                  'token': 'ghp-test-secret',
                },
              ],
            },
          }),
        ),
      ]);

      expect(result.issues, isEmpty, reason: result.issues.join('\n'));
      final warning = warningsOf(result, 'config.secret.in_file').single;
      expect(
        '${warning.key}: ${warning.message}',
        'mcp.servers[github].token: a secret is stored in the config file; '
            'move it to the secret store: codelab secret migrate',
      );
      expect(result.config!.mcpServers.map((s) => s.name), ['github']);
      expect(result.warnings.join('\n'), isNot(contains('ghp-test-secret')));
    });
  });
}
