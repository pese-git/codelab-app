import 'package:codelab_agent_core/codelab_agent_core.dart';
import 'package:test/test.dart';

import 'config_support.dart';

// Заведомо фиктивные значения в формате шаблонов §12.4.
const _skProj = 'sk-proj-AbCdEfGhIjKlMnOpQrStUvWx';
const _github = 'ghp_abcdefghijklmnopqrstuvwxyz0123456789';

/// Литеральные секреты в файлах конфига (agent-configuration «Секреты только
/// ссылками» и «Литеральные секреты в файле конфига»; пункты 1–3 CFG-9;
/// design.md change `add-config-literal-secrets-and-migrate`, D4, R8-4, R8-6;
/// задача 1.2).
void main() {
  const event = 'config.secret.in_file';

  Map<String, Object?> mcp(Map<String, Object?> server) =>
      withValues(baseValues(), {
        'mcp': {
          'servers': [
            {
              'name': 'gh',
              'type': 'http',
              'url': 'https://gh.test/mcp',
              ...server,
            },
          ],
        },
      });

  String text(ConfigIssue w) => '${w.key}: ${w.message}';

  group('warning text and layers', () {
    test('user layer: codelab secret migrate; project: --project; '
        'projectLocal: --local', () {
      final user = Map<String, Object?>.from(baseValues())
        ..['trusted_projects'] = ['/proj'];
      for (final (kind, command) in [
        (ConfigLayerKind.user, 'codelab secret migrate'),
        (ConfigLayerKind.project, 'codelab secret migrate --project'),
        (ConfigLayerKind.projectLocal, 'codelab secret migrate --local'),
      ]) {
        final values = {
          'providers': {
            'p': {'api_key': _skProj},
          },
        };
        final result = load(
          kind == ConfigLayerKind.user
              ? [layer(withValues(baseValues(), values))]
              : [layer(user), layer(values, kind: kind)],
          projectRoot: kind == ConfigLayerKind.user ? null : '/proj',
        );

        final warning = warningsOf(result, event).single;
        expect(
          text(warning),
          'providers.p.api_key: a secret is stored in the config file; move '
          'it to the secret store: $command',
          reason: '$kind',
        );
        expect(warning.source, contains('config'), reason: '$kind');
      }
    });

    test(
      'CODELAB_CONFIG: secret set with the suggested name, no --project',
      () {
        final result = load([
          layer(baseValues()),
          layer({
            'providers': {
              'p': {'api_key': _skProj},
            },
          }, kind: ConfigLayerKind.extra),
        ]);

        expect(
          text(warningsOf(result, event).single),
          'providers.p.api_key: a secret is stored in the config file; move it '
          'to the secret store: codelab secret set codelab/p',
        );
      },
    );

    test('the warning carries file, line and column of the key', () {
      final result = load([
        layer(
          withValues(baseValues(), {
            'providers': {
              'p': {'api_key': _skProj},
            },
          }),
          positions: {'providers.p.api_key': const ConfigPosition(7, 5)},
        ),
      ]);

      final warning = warningsOf(result, event).single;
      expect(warning.line, 7);
      expect(warning.column, 5);
      expect(
        '$warning',
        '/home/u/.codelab/config.yaml:7:5: providers.p.api_key: a secret is '
            'stored in the config file; move it to the secret store: codelab '
            'secret migrate',
      );
    });
  });

  group('what is applied', () {
    test('a mixed header Bearer <token> \${X} is warned about and applied '
        '(R1-1)', () {
      final result = load(
        [
          layer(
            mcp({
              'headers': {'Authorization': 'Bearer $_github \${X}'},
            }),
          ),
        ],
        environment: {'X': 'tail'},
      );

      expect(result.issues, isEmpty, reason: result.issues.join('\n'));
      final warning = warningsOf(result, event).single;
      expect(warning.key, 'mcp.servers[gh].headers.Authorization');
      final server = result.config!.mcpServers.single as McpHttpServerConfig;
      expect(server.headers, [('Authorization', 'Bearer $_github tail')]);
      expect(result.warnings.join('\n'), isNot(contains(_github)));
    });

    test('a pure reference next to a scheme prefix is not a finding', () {
      final result = load([
        layer(
          mcp({
            'headers': {
              'Authorization': r'Bearer ${secret:codelab/mcp/gh/authorization}',
            },
          }),
        ),
      ]);

      expect(warningsOf(result, event), isEmpty);
    });

    test('a DSN cut by a substitution is a finding; one substitution is '
        'not (L5)', () {
      final result = load(
        [
          layer(
            withValues(baseValues(), {
              'mcp': {
                'servers': [
                  {
                    'name': 'db',
                    'type': 'stdio',
                    'command': 'db-mcp',
                    'env': {
                      'DATABASE_URL':
                          r'postgres://app:pw-lit${SUFFIX}@localhost/db',
                    },
                  },
                  {
                    'name': 'db2',
                    'type': 'stdio',
                    'command': 'db-mcp',
                    'env': {
                      'DATABASE_URL': r'postgres://app:${PW}@localhost/db',
                    },
                  },
                ],
              },
            }),
          ),
        ],
        environment: {'SUFFIX': 'x', 'PW': 'y'},
      );

      expect(warningsOf(result, event).map((w) => w.key), [
        'mcp.servers[db].env.DATABASE_URL',
      ]);
      expect(result.warnings.join('\n'), isNot(contains('pw-lit')));
    });

    test('a disabled server still warns: warnings are per layer (D4)', () {
      final result = load([
        layer(
          mcp({
            'enabled': false,
            'headers': {'Authorization': 'Bearer $_github'},
          }),
        ),
      ]);

      expect(warningsOf(result, event).map((w) => w.key), [
        'mcp.servers[gh].headers.Authorization',
      ]);
    });
  });

  group('reference instead of a name (CFG-9 p.3)', () {
    test('api_key_env: a key that does not match a pattern is a format '
        'problem; one that matches is a warning and an UnusableKeyRef', () {
      final result = load([
        layer(
          withValues(baseValues(), {
            'providers': {
              'a': {
                'kind': 'openai-compatible',
                'base_url': 'https://llm.test/v1',
                'api_key_env': 'sk-test-secret-123',
              },
              'b': {
                'kind': 'openai-compatible',
                'base_url': 'https://llm.test/v1',
                'api_key_env': _skProj,
              },
            },
          }),
        ),
      ]);

      // `a`: проблема формата без значения, конфиг не построен.
      expect(result.config, isNull);
      expect(
        issuesAt(result, 'providers.a.api_key_env').single.message,
        'expected an environment variable name',
      );
      expect(issuesAt(result, 'providers.b.api_key_env'), isEmpty);
      expect(result.issues.join('\n'), isNot(contains('sk-test-secret-123')));
      expect(result.issues.join('\n'), isNot(contains(_skProj)));

      // `b` отдельно: ссылка-значение не даёт проблемы формата.
      final onlyB = load([
        layer(
          withValues(baseValues(), {
            'providers': {
              'b': {
                'kind': 'openai-compatible',
                'base_url': 'https://llm.test/v1',
                'api_key_env': _skProj,
              },
            },
          }),
        ),
      ]);
      expect(onlyB.issues, isEmpty, reason: onlyB.issues.join('\n'));
      expect(warningsOf(onlyB, event).map((w) => w.key), [
        'providers.b.api_key_env',
      ]);
      final provider = onlyB.config!.providers.firstWhere(
        (p) => p.config.name == 'b',
      );
      expect(provider.key, isA<UnusableKeyRef>());
      expect(
        (provider.key! as UnusableKeyRef).keyPath,
        'providers.b.api_key_env',
      );
      expect(provider.config.apiKey, isNull);
      expect(onlyB.config!.providerProblems, isEmpty);
      expect(warningsOf(onlyB, 'config.provider.key_missing'), isEmpty);
      expect(onlyB.warnings.join('\n'), isNot(contains(_skProj)));
    });

    test('api_key_secret: "sk-Test Secret" is a name problem; a GitHub token '
        'is a warning and a marker', () {
      final a = load([
        layer(
          withValues(baseValues(), {
            'providers': {
              'a': {
                'kind': 'openai-compatible',
                'base_url': 'https://llm.test/v1',
                'api_key_secret': 'sk-Test Secret',
              },
            },
          }),
        ),
      ]);
      expect(a.config, isNull);
      expect(
        issuesAt(a, 'providers.a.api_key_secret').single.message,
        contains('expected a secret name'),
      );
      expect(a.issues.join('\n'), isNot(contains('sk-Test Secret')));

      final b = load([
        layer(
          withValues(baseValues(), {
            'providers': {
              'b': {
                'kind': 'openai-compatible',
                'base_url': 'https://llm.test/v1',
                'api_key_secret': _github,
              },
            },
          }),
        ),
      ]);
      expect(b.issues, isEmpty, reason: b.issues.join('\n'));
      expect(warningsOf(b, event).map((w) => w.key), [
        'providers.b.api_key_secret',
      ]);
      expect(
        b.config!.providers.firstWhere((p) => p.config.name == 'b').key,
        isA<UnusableKeyRef>(),
      );
      expect(b.warnings.join('\n'), isNot(contains(_github)));
    });

    test('\${secret:<token>} in a server header: a warning and a marker in '
        'the template that names no secret', () {
      final result = load([
        layer(
          mcp({
            'headers': {'Authorization': 'Bearer \${secret:$_github}'},
          }),
        ),
      ]);

      expect(result.issues, isEmpty, reason: result.issues.join('\n'));
      expect(warningsOf(result, event).map((w) => w.key), [
        'mcp.servers[gh].headers.Authorization',
      ]);
      final server = result.config!.mcpServers.single;
      final template = server.secretValues['headers.Authorization']!;
      expect(template.parts.whereType<UnusableSecretReference>(), hasLength(1));
      expect(template.names, isEmpty, reason: 'the store is never asked');
      expect(result.warnings.join('\n'), isNot(contains(_github)));
    });
  });

  group('sources of the provider key (R8-6)', () {
    test('api_key with api_key_secret in one layer: a problem without the '
        'value', () {
      final result = load([
        layer(
          withValues(baseValues(), {
            'providers': {
              'openai': {
                'kind': 'openai-compatible',
                'base_url': 'https://llm.test/v1',
                'api_key': _skProj,
                'api_key_secret': 'codelab/openai',
              },
            },
          }),
        ),
      ]);

      expect(result.config, isNull);
      final issue = issuesAt(result, 'providers.openai.api_key').single;
      expect(issue.kind, ConfigIssueKind.value);
      expect(
        issue.message,
        'api_key, api_key_env and api_key_secret are mutually exclusive',
      );
      expect(result.issues.join('\n'), isNot(contains(_skProj)));
    });

    // Проектный слой сюда больше не годится: группа провайдера берётся из
    // него целиком и `api_key` пользователя к нему не наследуется (D23,
    // правило 2; config_provider_key_binding_test.dart). Два источника ключа
    // в слитом дереве остаются у глобальных слоёв.
    test('api_key in the user layer and api_key_secret in the --config '
        'layer: the merged tree has two sources', () {
      final result = load([
        layer({
          ...withValues(baseValues(), {
            'providers': {
              'openai': {
                'kind': 'openai-compatible',
                'base_url': 'https://llm.test/v1',
                'api_key': _skProj,
              },
            },
          }),
          'trusted_projects': ['/proj'],
        }),
        layer({
          'providers': {
            'openai': {'api_key_secret': 'codelab/openai'},
          },
        }, kind: ConfigLayerKind.extra),
      ], projectRoot: '/proj');

      expect(result.config, isNull);
      expect(
        issuesAt(result, 'providers.openai.api_key').single.message,
        'api_key, api_key_env and api_key_secret are mutually exclusive',
      );
    });

    // Сценарий agent-configuration «Ключ проектного слоя не образует пары с
    // ключом пользователя» (D23 правило 2, Q21 (a), D25).
    test('api_key in the user layer and api_key_secret in config.local.yaml '
        'of a trusted project: no pair, the project reference is the key', () {
      final result = load([
        layer({
          ...withValues(baseValues(), {
            'providers': {
              'openai': {
                'kind': 'openai-compatible',
                'base_url': 'https://llm.test/v1',
                'api_key': _skProj,
                'models': <String, Object?>{'m': <String, Object?>{}},
              },
            },
          }),
          'trusted_projects': ['/proj'],
        }),
        layer(<String, Object?>{
          'providers': <String, Object?>{
            'openai': <String, Object?>{'api_key_secret': 'codelab/openai'},
          },
        }, kind: ConfigLayerKind.projectLocal),
      ], projectRoot: '/proj');

      expect(result.issues, isEmpty, reason: result.issues.join('\n'));
      final provider = result.config!.providers.singleWhere(
        (p) => p.config.name == 'openai',
      );
      expect((provider.key as SecretKeyRef).name, 'codelab/openai');
      expect(provider.config.apiKey, isNull);
      expect(provider.config.baseUrl.host, 'llm.test');
    });

    test('api_key_env with api_key_secret keeps its own problem', () {
      final result = load([
        layer(
          withValues(baseValues(), {
            'providers': {
              'openai': {
                'kind': 'openai-compatible',
                'base_url': 'https://llm.test/v1',
                'api_key_env': 'OPENAI_API_KEY',
                'api_key_secret': 'codelab/openai',
              },
            },
          }),
        ),
      ]);

      expect(
        issuesAt(result, 'providers.openai.api_key_secret').single.message,
        'api_key_env and api_key_secret are mutually exclusive',
      );
    });
  });

  group('untrusted project', () {
    test('keys dropped by trust give untrusted_key and no in_file', () {
      final result = load([
        layer(baseValues()),
        layer({
          'providers': {
            'evil': {
              'kind': 'openai-compatible',
              'base_url': 'https://evil.test/v1',
              'api_key': _skProj,
            },
          },
          'mcp': {
            'servers': [
              {
                'name': 'gh',
                'type': 'http',
                'url': 'https://gh.test/mcp',
                'headers': {'Authorization': 'Bearer $_github'},
              },
            ],
          },
        }, kind: ConfigLayerKind.project),
      ], projectRoot: '/proj');

      expect(result.issues, isEmpty, reason: result.issues.join('\n'));
      expect(warningsOf(result, event), isEmpty);
      expect(
        warningsOf(result, 'config.project.untrusted_key').map((w) => w.key),
        containsAll(['providers', 'mcp.servers']),
      );
      expect(result.warnings.join('\n'), isNot(contains(_skProj)));
    });
  });

  group('settings registry (CFG-19)', () {
    test('providers.*.api_key is a secret fileOnly leaf', () {
      final descriptor = SettingsRegistry.lookup('providers.openai.api_key')!;
      expect(descriptor.scope, SettingScope.fileOnly);
      expect(descriptor.secret, isTrue);
      expect(descriptor.restartRequired, isFalse);
    });
  });

  // R8-8 (решение пользователя 2026-11-04): ссылка в api_key — не литерал.
  group('api_key as a reference (R8-8)', () {
    Map<String, Object?> withKey(Object? extra) => withValues(baseValues(), {
      'providers': {
        'p': {'api_key': extra},
      },
    });

    test(r'${VAR} set: the value is the key, no in_file warning', () {
      final result = load(
        [layer(withKey(r'${P_KEY}'))],
        environment: {'P_KEY': 'sk-from-env-0123456789'},
      );

      expect(result.issues, isEmpty, reason: result.issues.join('\n'));
      expect(warningsOf(result, event), isEmpty);
      final p = result.config!.providers.firstWhere(
        (p) => p.config.name == 'p',
      );
      expect(p.config.apiKey, 'sk-from-env-0123456789');
    });

    test(r'${VAR} unset: a problem naming the variable, never a value', () {
      final result = load([layer(withKey(r'${P_KEY}'))]);

      final issue = issuesAt(result, 'providers.p.api_key').single;
      expect(issue.message, 'variable P_KEY is not set');
    });

    test(r'${secret:x}: a SecretKeyRef, no warning, no literal key', () {
      final result = load([layer(withKey(r'${secret:codelab/p}'))]);

      expect(result.issues, isEmpty, reason: result.issues.join('\n'));
      expect(warningsOf(result, event), isEmpty);
      final p = result.config!.providers.firstWhere(
        (p) => p.config.name == 'p',
      );
      expect(p.key, isA<SecretKeyRef>());
      expect((p.key! as SecretKeyRef).name, 'codelab/p');
      expect(p.config.apiKey, isNull);
    });

    test(r'${secret:<token>}: a warning and a marker', () {
      final result = load([layer(withKey('\${secret:$_github}'))]);

      expect(result.issues, isEmpty, reason: result.issues.join('\n'));
      expect(warningsOf(result, event).map((w) => w.key), [
        'providers.p.api_key',
      ]);
      final p = result.config!.providers.firstWhere(
        (p) => p.config.name == 'p',
      );
      expect(p.key, isA<UnusableKeyRef>());
      expect(result.warnings.join('\n'), isNot(contains(_github)));
    });

    test('a reference together with api_key_secret is the R8-6 problem', () {
      final result = load(
        [
          layer(
            withValues(baseValues(), {
              'providers': {
                'p': {'api_key': r'${P_KEY}', 'api_key_secret': 'codelab/p'},
              },
            }),
          ),
        ],
        environment: {'P_KEY': 'abc'},
      );

      expect(
        issuesAt(result, 'providers.p.api_key').single.message,
        'api_key, api_key_env and api_key_secret are mutually exclusive',
      );
    });
  });

  group('characters that cannot be sent in a header (5)', () {
    for (final (name, bad) in [
      ('newline', 'sk-proj-AbCdEfGhIj\nKlMnOpQrStUvWx'),
      ('carriage return', 'sk-proj-AbCdEfGhIj\rKlMnOpQrStUvWx'),
      ('NBSP', 'sk-proj-AbCdEfGhIj\u00a0KlMnOpQrStUvWx'),
      ('zero-width space', 'sk-proj-AbCdEfGhIj\u200bKlMnOpQrStUvWx'),
    ]) {
      test('a literal api_key with $name: a problem without the value', () {
        final result = load([
          layer(
            withValues(baseValues(), {
              'providers': {
                'p': {'api_key': bad},
              },
            }),
          ),
        ]);

        expect(result.config, isNull);
        final issue = issuesAt(result, 'providers.p.api_key').single;
        expect(issue.message, 'api_key must be printable ASCII');
        expect('${result.issues}', isNot(contains('KlMnOp')));
        expect('${result.issues}', isNot(contains('AbCdEf')));
      });
    }

    test('a secret-named provider header with a bad character, too', () {
      final result = load([
        layer(
          withValues(baseValues(), {
            'providers': {
              'p': {
                'headers': {'X-Api-Key': 'abc\u00a0def'},
              },
            },
          }),
        ),
      ]);

      expect(
        issuesAt(result, 'providers.p.headers.X-Api-Key').single.message,
        'X-Api-Key must be printable ASCII',
      );
      expect('${result.issues}', isNot(contains('abc')));
    });
  });

  group(r'a token written as a variable name ${ghp_…} (6)', () {
    // Как `${secret:<токен>}`: маркер, окружение не читается, проблемы
    // загрузки нет, только предупреждение.
    for (final environment in [
      const <String, String>{},
      {_github: 'would-be-value'},
    ]) {
      test('environment ${environment.isEmpty ? 'empty' : 'has the name'}: '
          'a warning and a marker, no problem, the variable is not read', () {
        final result = load([
          layer(
            mcp({
              'headers': {'Authorization': 'Bearer \${$_github}'},
            }),
          ),
        ], environment: environment);

        expect(result.issues, isEmpty, reason: result.issues.join('\n'));
        expect(warningsOf(result, event).map((w) => w.key), [
          'mcp.servers[gh].headers.Authorization',
        ]);
        final template = result
            .config!
            .mcpServers
            .single
            .secretValues['headers.Authorization']!;
        expect(
          template.parts.whereType<UnusableSecretReference>(),
          hasLength(1),
        );
        expect(template.names, isEmpty);
        expect('${result.warnings}', isNot(contains(_github)));
        expect(
          result.warnings.map((w) => w.fields.toString()).join(),
          isNot(contains(_github)),
        );
      });
    }
  });

  test('api_key mixing a literal and a reference: only-as-a-whole problem', () {
    final result = load([
      layer(
        withValues(baseValues(), {
          'providers': {
            'p': {'api_key': r'Bearer ${secret:codelab/p}'},
          },
        }),
      ),
    ]);

    expect(
      issuesAt(result, 'providers.p.api_key').single.message,
      r'api_key may use ${secret:…} only as the whole value',
    );
  });

  group('secret names that contain sk- (L3)', () {
    test('api_key_secret with sk- inside is an ordinary reference', () {
      final result = load([
        layer(
          withValues(baseValues(), {
            'providers': {
              'p': {'api_key_secret': 'codelab/sk-anthropic-production-key'},
            },
          }),
        ),
      ]);

      expect(result.issues, isEmpty, reason: result.issues.join('\n'));
      expect(warningsOf(result, event), isEmpty);
      final p = result.config!.providers.firstWhere(
        (p) => p.config.name == 'p',
      );
      expect(p.key, isA<SecretKeyRef>());
    });
  });
}
