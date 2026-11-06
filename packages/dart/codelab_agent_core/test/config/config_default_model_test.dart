import 'package:codelab_agent_core/codelab_agent_core.dart';
import 'package:test/test.dart';

import 'config_support.dart';

/// Модель по умолчанию без `agent.default_model` (agent-configuration
/// «Модель по умолчанию без agent.default_model»; design.md change
/// `optional-default-model`, D1–D4). Красные тесты задачи 1.1: пока ключ
/// обязателен, любой слой без него даёт проблему `required`.
void main() {
  /// Провайдер `kind: openai-compatible` с моделями [models] (в порядке).
  Map<String, Object?> provider(
    List<String> models, {
    Map<String, Object?> extra = const {},
  }) => {
    'kind': 'openai-compatible',
    'base_url': 'https://llm.test/v1',
    'models': {for (final m in models) m: <String, Object?>{}},
    ...extra,
  };

  Map<String, Object?> providersOnly(Map<String, Map<String, Object?>> byId) =>
      {'providers': byId};

  String refOf(CoreConfig config) =>
      '${config.defaultModel.provider}/${config.defaultModel.id}';

  group('first available provider (D2)', () {
    test('first model of the first provider, no problems '
        '(scenario "Первая модель первого провайдера")', () {
      final result = load([
        layer(
          providersOnly({
            'a': provider(['x1', 'x2']),
            'b': provider(['y']),
          }),
        ),
      ]);

      expect(result.issues, isEmpty, reason: result.issues.join('\n'));
      expect(refOf(result.config!), 'a/x1');
      expect(
        result.config!.defaultModelSource,
        DefaultModelSource.firstProvider,
      );
    });

    test('a provider with an unset api_key_env is skipped; its warning '
        'stays (scenario "Первый провайдер без ключа")', () {
      final result = load(
        [
          layer(
            providersOnly({
              'a': provider(['x'], extra: {'api_key_env': 'A_KEY'}),
              'b': provider(['y'], extra: {'api_key_env': 'B_KEY'}),
            }),
          ),
        ],
        environment: {'B_KEY': 'sk-test-leak-0123456789'},
      );

      expect(result.issues, isEmpty, reason: result.issues.join('\n'));
      expect(refOf(result.config!), 'b/y');
      expect(
        result.config!.defaultModelSource,
        DefaultModelSource.firstProvider,
      );
      expect(warningsOf(result, 'config.provider.key_missing'), hasLength(1));
    });

    test('a secret reference counts as available and the store is not '
        'touched (scenario "Ссылка на секрет не читается при выборе")', () {
      // Загрузка чистая и хранилища не получает вовсе (CFG-10, D4
      // `add-agent-secret-store`); счётчик обращений проверяется в тесте
      // `codelab_agent_io` (`config check` с подставленным хранилищем).
      final result = load([
        layer(
          providersOnly({
            'gw': provider(['m'], extra: {'api_key_secret': 'codelab/gw'}),
          }),
        ),
      ]);

      expect(result.issues, isEmpty, reason: result.issues.join('\n'));
      expect(refOf(result.config!), 'gw/m');
      expect(result.config!.providers.single.key, isA<SecretKeyRef>());
      expect(
        result.config!.defaultModelSource,
        DefaultModelSource.firstProvider,
      );
    });

    test('a provider with a secret reference before an env one wins by '
        'order, not by the store', () {
      final result = load([
        layer(
          providersOnly({
            'a': provider(['x'], extra: {'api_key_secret': 'codelab/a'}),
            'b': provider(['y']),
          }),
        ),
      ]);

      expect(refOf(result.config!), 'a/x');
    });

    test(
      'no available providers: the first model of the first provider '
      'with models, load succeeds (scenario "Нет доступных провайдеров")',
      () {
        final result = load([
          layer(
            providersOnly({
              'a': provider(['x'], extra: {'api_key_env': 'A_KEY'}),
              'b': provider(['y'], extra: {'api_key_env': 'B_KEY'}),
            }),
          ),
        ]);

        expect(result.issues, isEmpty, reason: result.issues.join('\n'));
        expect(refOf(result.config!), 'a/x');
        expect(
          result.config!.defaultModelSource,
          DefaultModelSource.firstProvider,
        );
        expect(warningsOf(result, 'config.provider.key_missing'), hasLength(2));
      },
    );

    test('a provider without models is skipped when choosing', () {
      final result = load([
        layer(
          providersOnly({
            'a': {'kind': 'openai-compatible', 'base_url': 'https://a.test/v1'},
            'b': provider(['y']),
          }),
        ),
      ]);

      expect(result.issues, isEmpty, reason: result.issues.join('\n'));
      expect(refOf(result.config!), 'b/y');
    });
  });

  group('no model at all (D4)', () {
    void expectNone(ConfigLoadResult result) {
      final issue = issuesAt(result, 'agent.default_model').single;
      expect(result.issues, hasLength(1));
      expect(issue.key, 'agent.default_model');
      expect(issue.kind, ConfigIssueKind.value);
      expect(issue.event, 'config.model.none');
      expect(
        issue.message,
        'no model is configured; add a provider with at least one model',
      );
      expect(result.config, isNull);
    }

    test('no providers at all (scenario "Нет ни одного провайдера")', () {
      expectNone(load([layer(const {})]));
    });

    test('a provider without models gives the same problem', () {
      expectNone(
        load([
          layer(
            providersOnly({
              'gw': {'kind': 'openai-compatible', 'base_url': 'https://x/v1'},
            }),
          ),
        ]),
      );
    });
  });

  group('explicit model (D1)', () {
    test('a key in a layer wins and has the source config', () {
      final result = load([
        layer(
          withValues(
            providersOnly({
              'a': provider(['x']),
              'b': provider(['y']),
            }),
            {
              'agent': {'default_model': 'b/y'},
            },
          ),
        ),
      ]);

      expect(refOf(result.config!), 'b/y');
      expect(result.config!.defaultModelSource, DefaultModelSource.config);
    });

    test('an explicit model outside the catalog is a problem, no fallback '
        '(scenario "Явная модель на несуществующую модель")', () {
      final result = load([
        layer(
          withValues(
            providersOnly({
              'gw': provider(['m']),
            }),
            {
              'agent': {'default_model': 'gw/zzz'},
            },
          ),
        ),
      ]);

      final issue = issuesAt(result, 'agent.default_model').single;
      expect(issue.message, contains('gw/zzz is not in the model catalog'));
      expect(issue.event, isNot('config.model.none'));
      expect(result.config, isNull);
    });

    test('CODELAB_MODEL is an explicit model of the environment layer '
        '(scenario "CODELAB_MODEL — явная модель", layer part)', () {
      final result = load([
        layer(
          providersOnly({
            'a': provider(['x']),
            'b': provider(['y']),
          }),
        ),
        layer(const {
          'agent': {'default_model': 'b/y'},
        }, kind: ConfigLayerKind.environment),
      ]);

      expect(refOf(result.config!), 'b/y');
      expect(result.config!.defaultModelSource, DefaultModelSource.config);
    });
  });

  group('snapshot without the project (D1, D9 add-agent-configuration)', () {
    ConfigTree project(Map<String, Object?> values) =>
        layer(values, kind: ConfigLayerKind.project);

    test('the bare snapshot takes the model and the source of the full '
        'one when the key is explicit only in the project', () {
      final result = load([
        layer(
          providersOnly({
            'p': provider(['m']),
          }),
        ),
        project({
          'agent': {'default_model': 'p/m'},
        }),
      ], projectRoot: '/proj');

      expect(result.issues, isEmpty, reason: result.issues.join('\n'));
      final full = result.config!;
      expect(full.defaultModelSource, DefaultModelSource.config);
      final bare = full.withoutProject!;
      expect(refOf(bare), 'p/m');
      expect(bare.defaultModelSource, DefaultModelSource.config);
    });

    test('an implicit model keeps firstProvider in both snapshots', () {
      final result = load([
        layer(
          providersOnly({
            'p': provider(['m']),
          }),
        ),
        project({
          'budget': {'max_steps': 5},
        }),
      ], projectRoot: '/proj');

      expect(result.issues, isEmpty, reason: result.issues.join('\n'));
      final full = result.config!;
      expect(full.defaultModelSource, DefaultModelSource.firstProvider);
      expect(
        full.withoutProject!.defaultModelSource,
        DefaultModelSource.firstProvider,
      );
    });

    test('a trusted project layer adds a provider after the user ones: both '
        'snapshots start on the first provider of the user', () {
      final result = load([
        layer(
          withValues(
            providersOnly({
              'u': provider(['um']),
            }),
            {
              'trusted_projects': ['/proj'],
            },
          ),
        ),
        project({
          'providers': {
            'a': provider(['pm']),
          },
        }),
      ], projectRoot: '/proj');

      expect(result.issues, isEmpty, reason: result.issues.join('\n'));
      final full = result.config!;
      final bare = full.withoutProject!;
      expect(refOf(bare), 'u/um');
      expect(bare.defaultModelSource, DefaultModelSource.firstProvider);
      expect(full.defaultModelSource, DefaultModelSource.firstProvider);
      // Порядок провайдеров — порядок слияния слоёв: ключи пользователя идут
      // раньше ключей проекта, поэтому провайдер проекта не становится первым.
      expect(refOf(full), 'u/um');
    });

    test('the only provider comes from the trusted project: the bare snapshot '
        'has no model of its own and takes the model of the full one', () {
      final result = load([
        layer(const {
          'trusted_projects': ['/proj'],
        }),
        project({
          'providers': {
            'a': provider(['pm']),
          },
        }),
      ], projectRoot: '/proj');

      expect(result.issues, isEmpty, reason: result.issues.join('\n'));
      final full = result.config!;
      expect(refOf(full), 'a/pm');
      expect(refOf(full.withoutProject!), 'a/pm');
      expect(
        full.withoutProject!.defaultModelSource,
        DefaultModelSource.firstProvider,
      );
    });

    test('only the project provider is available: the full snapshot starts on '
        'it (D2), the bare one on the user provider without a key (D3) '
        '(scenario "Доступен только провайдер проекта")', () {
      final result = load([
        layer(
          withValues(
            providersOnly({
              'u': provider(['x'], extra: {'api_key_env': 'U_KEY'}),
            }),
            {
              'trusted_projects': ['/proj'],
            },
          ),
        ),
        project({
          'providers': {
            'p': provider(['y']),
          },
        }),
      ], projectRoot: '/proj');

      expect(result.issues, isEmpty, reason: result.issues.join('\n'));
      final full = result.config!;
      expect(refOf(full), 'p/y');
      expect(full.defaultModelSource, DefaultModelSource.firstProvider);
      final bare = full.withoutProject!;
      expect(refOf(bare), 'u/x');
      expect(bare.defaultModelSource, DefaultModelSource.firstProvider);
    });
  });
}
