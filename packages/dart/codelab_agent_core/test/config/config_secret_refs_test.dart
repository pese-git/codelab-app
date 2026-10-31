import 'package:codelab_agent_core/codelab_agent_core.dart';
import 'package:test/test.dart';

import 'config_support.dart';

const _rule =
    'expected a secret name: lowercase letters, digits and . _ / -, '
    'up to 128 characters';

Map<String, Object?> _withProvider(Map<String, Object?> provider) =>
    withValues(baseValues(), {
      'providers': {'p': provider},
    });

Map<String, Object?> _withServers(List<Map<String, Object?>> servers) =>
    withValues(baseValues(), {
      'mcp': {'servers': servers},
    });

/// Ссылки на секреты в конфиге (agent-configuration «Секреты только
/// ссылками»; agent-secrets «Выбор бэкенда secrets.backend»; design.md change
/// `add-agent-secret-store`, D2, D4, D7).
void main() {
  group('names', () {
    test('api_key_secret follows the strict rule, the name is not echoed', () {
      for (final bad in ['Codelab/OpenAI', 'a/../b', 'my key', 'codelab/']) {
        final result = load([
          layer(_withProvider({'api_key_secret': bad})),
        ]);

        final issue = issuesAt(result, 'providers.p.api_key_secret').single;
        expect(issue.kind, ConfigIssueKind.value, reason: bad);
        expect(issue.message, _rule, reason: bad);
        expect(result.config, isNull);
        expect(issue.message, isNot(contains(bad)), reason: bad);
      }
    });

    test(r'${secret:<name>} follows the same rule in headers and env', () {
      final result = load([
        layer(
          withValues(
            _withProvider({
              'headers': {'X-Key': r'${secret:Bad Name}'},
            }),
            {
              'mcp': {
                'servers': [
                  {
                    'name': 'gh',
                    'type': 'stdio',
                    'command': 'gh-mcp',
                    'env': {'T': r'${secret:UPPER}'},
                  },
                ],
              },
            },
          ),
        ),
      ]);

      expect(
        issuesAt(result, 'providers.p.headers.X-Key').single.message,
        _rule,
      );
      expect(issuesAt(result, 'mcp.servers[gh].env.T').single.message, _rule);
      expect(result.issues.join('\n'), isNot(contains('Bad Name')));
    });

    test('a valid name passes', () {
      final result = load([
        layer(_withProvider({'api_key_secret': 'codelab/anthropic'})),
      ]);

      expect(result.issues, isEmpty);
    });
  });

  group('forbidden positions', () {
    const text =
        r'secret references ${secret:…} are allowed only in env and headers '
        'values';

    test('providers.*.base_url with a reference is a value problem', () {
      final result = load([
        layer(
          _withProvider({'base_url': r'https://${secret:codelab/host}/v1'}),
        ),
      ]);

      final issue = issuesAt(result, 'providers.p.base_url').single;
      expect(issue.kind, ConfigIssueKind.value);
      expect(issue.message, text);
      expect(result.config, isNull);
    });
  });

  group('provider key', () {
    test(
      'api_key_secret becomes a SecretKeyRef, no problem and no warning',
      () {
        final result = load([
          layer(_withProvider({'api_key_secret': 'codelab/anthropic'})),
        ]);

        final provider = result.config!.providers.single;
        expect(provider.key, isA<SecretKeyRef>());
        expect((provider.key as SecretKeyRef).name, 'codelab/anthropic');
        expect(provider.config.apiKey, isNull);
        expect(result.config!.providerProblems, isEmpty);
        expect(result.warnings, isEmpty);
      },
    );

    test('api_key_env becomes an EnvKeyRef; the value is not read at load', () {
      final result = load(
        [
          layer(_withProvider({'api_key_env': 'OPENAI_API_KEY'})),
        ],
        environment: {'OPENAI_API_KEY': 'sk-test-0123456789abcdef'},
      );

      final provider = result.config!.providers.single;
      expect(provider.key, isA<EnvKeyRef>());
      expect((provider.key as EnvKeyRef).variable, 'OPENAI_API_KEY');
      expect(provider.config.apiKey, isNull);
      expect(result.config!.providerProblems, isEmpty);
      expect(result.warnings, isEmpty);
    });

    test('an unset api_key_env keeps the reference, the warning and the '
        'problem', () {
      final result = load([
        layer(_withProvider({'api_key_env': 'OPENAI_API_KEY'})),
      ]);

      expect(
        (result.config!.providers.single.key as EnvKeyRef).variable,
        'OPENAI_API_KEY',
      );
      expect(warningsOf(result, 'config.provider.key_missing'), hasLength(1));
      expect(
        result.config!.providerProblems['p'],
        'API key variable OPENAI_API_KEY is not set',
      );
    });

    test('a provider without a key has no reference', () {
      final result = load([layer(baseValues())]);

      expect(result.config!.providers.single.key, isNull);
    });
  });

  // Сценарий agent-configuration «Ссылки на секреты не читаются при
  // загрузке». Загрузка — чистая функция без параметра хранилища: «хранилище
  // не вызывалось» обеспечено её сигнатурой, проверяется результат.
  test('references are not read at load: no warnings, gh is in mcpServers, '
      'anthropic is not a provider problem', () {
    final result = load([
      layer(
        withValues(baseValues(), {
          'providers': {
            'anthropic': {
              'kind': 'anthropic',
              'api_key_secret': 'codelab/anthropic',
            },
          },
          'mcp': {
            'servers': [
              {
                'name': 'gh',
                'type': 'http',
                'url': 'https://gh.test/mcp',
                'headers': {
                  'Authorization': r'${secret:codelab/mcp/gh/authorization}',
                },
              },
            ],
          },
        }),
      ),
    ]);

    final config = result.config!;
    expect(result.warnings, isEmpty);
    expect(config.mcpServers.map((s) => s.name), contains('gh'));
    expect(config.providerProblems.containsKey('anthropic'), isFalse);
  });

  group('provider headers', () {
    test('a header with a reference becomes a template, the rest stay '
        'strings', () {
      final result = load(
        [
          layer(
            _withProvider({
              'headers': {
                'X-Plain': 'v',
                'X-Key': r'Bearer ${secret:codelab/p/key}',
                'X-Mixed': r'${ORG}:${secret:codelab/a}:${secret:codelab/b}',
              },
            }),
          ),
        ],
        environment: {'ORG': 'acme'},
      );

      final provider = result.config!.providers.single;
      expect(provider.config.headers, {'X-Plain': 'v'});
      expect(provider.headerTemplates.keys, ['X-Key', 'X-Mixed']);
      expect(provider.headerTemplates['X-Key']!.parts, [
        const SecretLiteral('Bearer '),
        const SecretReference('codelab/p/key'),
      ]);
      expect(provider.headerTemplates['X-Mixed']!.parts, [
        const SecretLiteral('acme:'),
        const SecretReference('codelab/a'),
        const SecretLiteral(':'),
        const SecretReference('codelab/b'),
      ]);
      expect(provider.headerTemplates['X-Mixed']!.names, [
        'codelab/a',
        'codelab/b',
      ]);
      expect(result.config!.providerProblems, isEmpty);
      expect(warningsOf(result, 'config.secret.unavailable'), isEmpty);
    });

    test(r'a literal $${secret:x} stays a plain header', () {
      final result = load([
        layer(
          _withProvider({
            'headers': {'X-Lit': r'$${secret:x}'},
          }),
        ),
      ]);

      final provider = result.config!.providers.single;
      expect(provider.config.headers, {'X-Lit': r'${secret:x}'});
      expect(provider.headerTemplates, isEmpty);
    });
  });

  group('MCP servers', () {
    test('an http header with a reference keeps the server, the value is a '
        'template', () {
      final result = load([
        layer(
          _withServers([
            {
              'name': 'gh',
              'type': 'http',
              'url': 'https://gh.test/mcp',
              'headers': {
                'Authorization':
                    r'Bearer ${secret:codelab/mcp/gh/authorization}',
                'X-Plain': 'v',
              },
            },
            {'name': 'ok', 'type': 'stdio', 'command': 'ok-mcp'},
          ]),
        ),
      ]);

      expect(result.issues, isEmpty, reason: result.issues.join('\n'));
      expect([for (final s in result.config!.mcpServers) s.name], ['gh', 'ok']);
      final gh = result.config!.mcpServers.first as McpHttpServerConfig;
      expect(gh.headers, [('X-Plain', 'v')]);
      expect(gh.secretValues.keys, ['headers.Authorization']);
      expect(gh.secretValues['headers.Authorization']!.parts, [
        const SecretLiteral('Bearer '),
        const SecretReference('codelab/mcp/gh/authorization'),
      ]);
      expect(warningsOf(result, 'config.secret.unavailable'), isEmpty);
      expect(gh.toString(), isNot(contains('codelab/mcp')));
    });

    test('withSecrets keeps the header order of the config file and every '
        'other field', () {
      final result = load([
        layer(
          _withServers([
            {
              'name': 'gh',
              'type': 'http',
              'url': 'https://gh.test/mcp',
              'connect_timeout': '3s',
              'call_timeout': '40s',
              'headers': {
                'X-A': 'a',
                'Authorization': r'Bearer ${secret:codelab/gh}',
                'X-B': 'b',
                'X-C': r'${secret:codelab/c}',
              },
            },
            {
              'name': 'fs',
              'type': 'stdio',
              'command': 'fs-mcp',
              'args': ['--x'],
              'env': {'K': 'v', 'TOKEN': r'${secret:codelab/fs}'},
            },
          ]),
        ),
      ]);

      final gh = result.config!.mcpServers.first as McpHttpServerConfig;
      final ready = gh.withSecrets({
        'headers.Authorization': 'Bearer t',
        'headers.X-C': 'c',
      });

      expect(ready.headers, [
        ('X-A', 'a'),
        ('Authorization', 'Bearer t'),
        ('X-B', 'b'),
        ('X-C', 'c'),
      ]);
      expect(ready.name, 'gh');
      expect(ready.url, Uri.parse('https://gh.test/mcp'));
      expect(ready.origin, McpServerOrigin.config);
      expect(ready.connectTimeout, const Duration(seconds: 3));
      expect(ready.callTimeout, const Duration(seconds: 40));
      expect(ready.secretValues, isEmpty);

      final fs = result.config!.mcpServers.last as McpStdioServerConfig;
      final fsReady = fs.withSecrets({'env.TOKEN': 't'});
      expect(fsReady.env, {'K': 'v', 'TOKEN': 't'});
      expect(fsReady.command, 'fs-mcp');
      expect(fsReady.args, ['--x']);
      expect(fsReady.origin, McpServerOrigin.config);
      expect(fsReady.secretValues, isEmpty);
    });

    test('a stdio env value with a reference is a template', () {
      final result = load([
        layer(
          _withServers([
            {
              'name': 'fs',
              'type': 'stdio',
              'command': 'fs-mcp',
              'env': {'TOKEN': r'${secret:codelab/mcp/fs/token}', 'K': 'v'},
            },
          ]),
        ),
      ]);

      final fs = result.config!.mcpServers.single as McpStdioServerConfig;
      expect(fs.env, {'K': 'v'});
      expect(fs.secretValues.keys, ['env.TOKEN']);
      expect(fs.secretValues['env.TOKEN']!.names, ['codelab/mcp/fs/token']);
    });

    test(r'a literal $${secret:x} is a plain value without a template', () {
      final result = load([
        layer(
          _withServers([
            {
              'name': 'fs',
              'type': 'stdio',
              'command': 'fs-mcp',
              'env': {'K': r'$${secret:x}'},
            },
          ]),
        ),
      ]);

      final fs = result.config!.mcpServers.single as McpStdioServerConfig;
      expect(fs.env, {'K': r'${secret:x}'});
      expect(fs.secretValues, isEmpty);
    });

    test('a reference outside env and headers is a problem', () {
      final result = load([
        layer(
          _withServers([
            {
              'name': 'a',
              'type': 'stdio',
              'command': 'x',
              'args': [r'--token=${secret:codelab/a}'],
            },
            {
              'name': 'b',
              'type': 'http',
              'url': r'https://b.test/${secret:codelab/b}',
            },
          ]),
        ),
      ]);

      expect(issuesAt(result, 'mcp.servers[a].args[0]'), hasLength(1));
      expect(issuesAt(result, 'mcp.servers[b].url'), hasLength(1));
      expect(
        issuesAt(result, 'mcp.servers[b].url').single.message,
        contains('env and headers'),
      );
    });

    test('sameConnection compares the templates', () {
      const a = McpHttpServerConfigFixture();
      expect(
        a.withRef('codelab/x').sameConnection(a.withRef('codelab/x')),
        isTrue,
      );
      expect(
        a.withRef('codelab/x').sameConnection(a.withRef('codelab/y')),
        isFalse,
      );
    });
  });

  group('untrusted project', () {
    test(
      r'a ${secret:…} server of an untrusted project gives no reference',
      () {
        final result = load([
          layer(baseValues()),
          layer(
            _withServers([
              {
                'name': 'gh',
                'type': 'http',
                'url': 'https://gh.test/mcp',
                'headers': {'Authorization': r'${secret:codelab/openai}'},
              },
            ]),
            kind: ConfigLayerKind.project,
          ),
        ], projectRoot: '/proj');

        expect(result.config!.mcpServers, isEmpty);
        expect(warningsOf(result, 'config.project.untrusted_key'), isNotEmpty);
      },
    );
  });

  group('secrets.backend', () {
    HostSettings? backendOf(String? value, {ConfigLayerKind? kind}) {
      final result = load([
        layer(baseValues()),
        layer({
          'secrets': {'backend': ?value},
        }, kind: kind ?? ConfigLayerKind.extra),
      ]);
      expect(result.issues, isEmpty, reason: result.issues.join('\n'));
      expect(warningsOf(result, 'config.key.not_applied'), isEmpty);
      return result.host;
    }

    test('auto, env and file are accepted without not_applied', () {
      expect(backendOf('auto')!.secretsBackend, 'auto');
      expect(backendOf('env')!.secretsBackend, 'env');
      expect(backendOf('file')!.secretsBackend, 'file');
    });

    test('an unset key is null', () {
      expect(load([layer(baseValues())]).host!.secretsBackend, isNull);
    });

    test('it is read from the user layer too', () {
      final result = load([
        layer(
          withValues(baseValues(), {
            'secrets': {'backend': 'file'},
          }),
        ),
      ]);

      expect(result.host!.secretsBackend, 'file');
    });

    test('keychain is a problem: not supported yet', () {
      final result = load([
        layer(
          withValues(baseValues(), {
            'secrets': {'backend': 'keychain'},
          }),
        ),
      ]);

      final issue = issuesAt(result, 'secrets.backend').single;
      expect(issue.kind, ConfigIssueKind.value);
      expect(
        issue.message,
        'keychain is not supported yet (supported: auto, env, file)',
      );
      expect(result.config, isNull);
    });

    test('another value is a problem with the list of values', () {
      final result = load([
        layer(
          withValues(baseValues(), {
            'secrets': {'backend': 'vault'},
          }),
        ),
      ]);

      final issue = issuesAt(result, 'secrets.backend').single;
      expect(issue.kind, ConfigIssueKind.value);
      expect(issue.message, 'expected one of: auto, keychain, env, file');
      expect(result.issues.join('\n'), isNot(contains('vault')));
    });

    test('a project layer cannot set it, even with trust', () {
      for (final kind in [
        ConfigLayerKind.project,
        ConfigLayerKind.projectLocal,
      ]) {
        final result = load([
          layer(
            withValues(baseValues(), {
              'trusted_projects': ['/proj'],
            }),
          ),
          layer({
            'secrets': {'backend': 'file'},
          }, kind: kind),
        ], projectRoot: '/proj');

        expect(result.host!.secretsBackend, isNull, reason: kind.name);
        expect(
          [
            for (final w in warningsOf(result, 'config.project.untrusted_key'))
              w.key,
          ],
          ['secrets'],
          reason: kind.name,
        );
      }
    });
  });
}

/// Сервер с одним шаблоном для проверки `sameConnection`.
final class McpHttpServerConfigFixture {
  const McpHttpServerConfigFixture();

  McpHttpServerConfig withRef(String name) => McpHttpServerConfig(
    name: 'gh',
    url: Uri.parse('https://gh.test/mcp'),
    secretValues: {
      'headers.Authorization': SecretTemplate([SecretReference(name)]),
    },
  );
}
