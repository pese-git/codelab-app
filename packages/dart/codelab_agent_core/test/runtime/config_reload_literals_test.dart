// Тест проверяет чистый план перезагрузки: это шов тестов, а не публичный API
// (PKG-5); рантайм только применяет его результат (design.md change
// `add-config-writer-and-reload`, D8).
import 'package:codelab_agent_core/codelab_agent_core.dart';
import 'package:test/test.dart';

import '../config/config_support.dart' show baseValues, layer, withValues;

// Заведомо фиктивные значения в формате шаблонов §12.4.
const _github = 'ghp_abcdefghijklmnopqrstuvwxyz0123456789';
// Переменная для смешанного значения `Bearer <токен> ${X}`.
const _env = {'X': 'x'};
const _skProj = 'sk-proj-AbCdEfGhIjKlMnOpQrStUvWx';

/// Литералы и живая перезагрузка (agent-runtime «Живая перезагрузка
/// конфигурации», сценарии с литералами; design.md change
/// `add-config-literal-secrets-and-migrate`, D12, R0-4; задача 1.5).
///
/// Литерал может увести секрет на новый адрес так же, как подстановка `${…}`:
/// смена `url` HTTP-сервера с литеральным `Authorization` или `base_url`
/// провайдера с литеральным `api_key`. Поэтому такие правки ждут перезапуска.
void main() {
  Map<String, Object?> http(
    String name, {
    String? url,
    Map<String, String>? headers,
    Map<String, Object?> extra = const {},
  }) => {
    'name': name,
    'type': 'http',
    'url': url ?? 'https://$name.test/mcp',
    'headers': ?headers,
    ...extra,
  };

  Map<String, Object?> config({
    List<Map<String, Object?>> servers = const [],
    Map<String, Map<String, Object?>> providers = const {},
  }) => withValues(baseValues(), {
    if (servers.isNotEmpty) 'mcp': {'servers': servers},
    if (providers.isNotEmpty) 'providers': providers,
  });

  Map<String, Object?> provider(
    String base, {
    Map<String, Object?> extra = const {},
    bool model2 = false,
  }) => {
    'kind': 'openai-compatible',
    'base_url': base,
    'models': {
      'lm': <String, Object?>{},
      if (model2) 'lm2': <String, Object?>{},
    },
    ...extra,
  };

  ConfigReloadPlan plan(
    Map<String, Object?> before,
    Map<String, Object?> after,
  ) {
    final a = CoreConfig.fromLayers([layer(before)], environment: _env);
    final b = CoreConfig.fromLayers([layer(after)], environment: _env);
    expect(a.issues, isEmpty, reason: a.issues.join('\n'));
    expect(b.issues, isEmpty, reason: b.issues.join('\n'));
    return planConfigReload(
      previousValues: a.values,
      previous: a.config!,
      nextValues: b.values,
      next: b.config!,
    );
  }

  group('an http server with a literal secret', () {
    test('a url change waits for a restart; the old url stays applied', () {
      final result = plan(
        config(
          servers: [
            http('gh', headers: {'Authorization': 'Bearer $_github'}),
          ],
        ),
        config(
          servers: [
            http(
              'gh',
              url: 'https://other.test/mcp',
              headers: {'Authorization': 'Bearer $_github'},
            ),
          ],
        ),
      );

      expect(result.restartRequiredKeys, ['mcp.servers[gh]']);
      expect(result.changedKeys, isEmpty);
      final applied =
          result.appliedValues['mcp.servers[gh]']! as Map<String, Object?>;
      expect(applied['url'], 'https://gh.test/mcp');
    });

    test('a mixed value "Bearer <token> \${X}" counts too (R1-1)', () {
      final result = plan(
        config(
          servers: [
            http('gh', headers: {'Authorization': 'Bearer $_github \${X}'}),
          ],
        ),
        config(
          servers: [
            http(
              'gh',
              url: 'https://other.test/mcp',
              headers: {'Authorization': 'Bearer $_github \${X}'},
            ),
          ],
        ),
      );

      expect(result.restartRequiredKeys, ['mcp.servers[gh]']);
    });

    test('an ignored token key counts as a finding too', () {
      final result = plan(
        config(
          servers: [
            http('gh', extra: {'token': 'ghp-test-secret'}),
          ],
        ),
        config(
          servers: [
            http(
              'gh',
              url: 'https://other.test/mcp',
              extra: {'token': 'ghp-test-secret'},
            ),
          ],
        ),
      );

      expect(result.restartRequiredKeys, ['mcp.servers[gh]']);
    });

    test('control: the same edit without a literal is applied live', () {
      final result = plan(
        config(
          servers: [
            http('gh', headers: {'X-Team': 'blue'}),
          ],
        ),
        config(
          servers: [
            http(
              'gh',
              url: 'https://other.test/mcp',
              headers: {'X-Team': 'blue'},
            ),
          ],
        ),
      );

      expect(result.restartRequiredKeys, isEmpty);
      expect(result.changedKeys, ['mcp.servers[gh]']);
    });

    test('a new server with a literal waits; one without connects', () {
      final result = plan(
        config(),
        config(
          servers: [
            http('lit', headers: {'Authorization': 'Bearer $_github'}),
            http('plain'),
          ],
        ),
      );

      expect(result.restartRequiredKeys, ['mcp.servers[lit]']);
      expect(result.changedKeys, ['mcp.servers[plain]']);
      expect(result.appliedValues, isNot(contains('mcp.servers[lit]')));
    });
  });

  group('a provider with a literal api_key', () {
    test('a base_url change waits as a group; the literal key stays', () {
      final result = plan(
        config(
          providers: {
            'lit': provider('https://a.test/v1', extra: {'api_key': _skProj}),
          },
        ),
        config(
          providers: {
            'lit': provider('https://b.test/v1', extra: {'api_key': _skProj}),
          },
        ),
      );

      expect(result.restartRequiredKeys, ['providers.lit']);
      expect(result.changedKeys, isEmpty);
      expect(
        result.appliedValues['providers.lit.base_url'],
        'https://a.test/v1',
      );
    });

    test('rotating the literal key itself waits too (api_key is in the '
        'group)', () {
      final result = plan(
        config(
          providers: {
            'lit': provider('https://a.test/v1', extra: {'api_key': _skProj}),
          },
        ),
        config(
          providers: {
            'lit': provider(
              'https://a.test/v1',
              extra: {'api_key': '${_skProj}x'},
            ),
          },
        ),
      );

      expect(result.restartRequiredKeys, ['providers.lit']);
      expect(result.appliedValues['providers.lit.api_key'], _skProj);
    });

    test('new models of such a provider apply live', () {
      final result = plan(
        config(
          providers: {
            'lit': provider('https://a.test/v1', extra: {'api_key': _skProj}),
          },
        ),
        config(
          providers: {
            'lit': provider(
              'https://a.test/v1',
              extra: {'api_key': _skProj},
              model2: true,
            ),
          },
        ),
      );

      expect(result.restartRequiredKeys, isEmpty);
      expect(result.changedKeys, ['providers.lit.models.lm2']);
    });

    test('a literal in a header or an ignored key makes a provider "with a '
        'key" (any finding)', () {
      for (final extra in [
        {
          'headers': {'X-Foo': 'Bearer $_github'},
        },
        {'token': 'ghp-test-secret'},
        {'api_key_env': _skProj},
      ]) {
        final result = plan(
          config(
            providers: {
              'lit': provider('https://a.test/v1', extra: {...extra}),
            },
          ),
          config(
            providers: {
              'lit': provider('https://b.test/v1', extra: {...extra}),
            },
          ),
        );

        expect(result.restartRequiredKeys, ['providers.lit'], reason: '$extra');
      }
    });

    test('control: a provider without any key applies the address live', () {
      final result = plan(
        config(providers: {'free': provider('https://a.test/v1')}),
        config(providers: {'free': provider('https://b.test/v1')}),
      );

      expect(result.restartRequiredKeys, isEmpty);
      expect(result.changedKeys, ['providers.free.base_url']);
    });

    test(
      'a new provider with a literal key waits, its model reference too',
      () {
        final before = config();
        final after = withValues(
          config(
            providers: {
              'n': provider('https://n.test/v1', extra: {'api_key': _skProj}),
            },
          ),
          {
            'agent': {'default_model': 'n/lm'},
          },
        );

        final result = plan(before, after);

        expect(result.restartRequiredKeys, [
          'agent.default_model',
          'providers.n',
        ]);
      },
    );
  });

  group('review fixes (R0-4)', () {
    test('a literal in a provider header whose name has a dot (3)', () {
      final result = plan(
        config(
          providers: {
            'lit': provider(
              'https://a.test/v1',
              extra: {
                'headers': {'X.Custom': 'Bearer $_github'},
              },
            ),
          },
        ),
        config(
          providers: {
            'lit': provider(
              'https://b.test/v1',
              extra: {
                'headers': {'X.Custom': 'Bearer $_github'},
              },
            ),
          },
        ),
      );

      expect(result.restartRequiredKeys, ['providers.lit']);
    });

    test('a secret-named http header is a key even without a pattern (3)', () {
      final header = {'X-Api-Key': '0123456789abcdef0123456789abcdef'};
      final result = plan(
        config(servers: [http('gh', headers: header)]),
        config(
          servers: [http('gh', url: 'https://other.test/mcp', headers: header)],
        ),
      );

      expect(result.restartRequiredKeys, ['mcp.servers[gh]']);
    });

    test(r'api_key: ${VAR} counts as a key (R8-8)', () {
      final result = plan(
        config(
          providers: {
            'r': provider('https://a.test/v1', extra: {'api_key': r'${X}'}),
          },
        ),
        config(
          providers: {
            'r': provider('https://b.test/v1', extra: {'api_key': r'${X}'}),
          },
        ),
      );

      expect(result.restartRequiredKeys, ['providers.r']);
    });
  });
}
