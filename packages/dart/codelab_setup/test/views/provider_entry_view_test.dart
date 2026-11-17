import 'package:codelab_setup/codelab_setup.dart';
import 'package:codelab_setup/src/config/config_values.dart';
import 'package:test/test.dart';

/// Модели представления страницы Providers (client-agent-setup «Модели
/// представления настроек»; design.md change `add-provider-setup-ui`, D6,
/// D10; SETUP-1): статус ключа строится по именам, значение не читается, а
/// слой 3, `--config` и окружение не редактируются.
void main() {
  const leak = 'sk-test-leak-0123456789';
  const backend = SecretBackendInfo(id: 'file', writable: true);

  const userSource = ConfigSourceView(
    kind: ConfigSourceKind.user,
    label: '/h/config.yaml',
  );

  Map<String, Object?> openai(Map<String, Object?> extra) => {
    'kind': 'openai-compatible',
    'base_url': 'https://api.example.invalid/v1',
    'models': {
      'gpt-b': {'context_window': 32000},
      'gpt-a': {'context_window': 16000},
    },
    ...extra,
  };

  AgentConfigSnapshot snapshotOf(
    Map<String, Object?> user, {
    Map<String, Object?> project = const {},
    Map<String, Object?> loadedValues = const {},
    ConfigSourceView? Function(String key)? external,
  }) => AgentConfigSnapshot.fromLayers(
    cwd: '/work/project',
    layers: {
      ConfigLayer.user: ConfigSnapshot(
        target: const ConfigTarget.user(),
        path: '/h/config.yaml',
        fingerprint: 'f',
        values: user,
      ),
      if (project.isNotEmpty)
        ConfigLayer.project: ConfigSnapshot(
          target: const ConfigTarget.project('/work/project'),
          path: '/work/project/.codelab/config.yaml',
          fingerprint: 'g',
          values: project,
        ),
    },
    loaded: ConfigLoadResult(values: loadedValues),
    secrets: backend,
    externalOrigin: external,
  );

  Future<List<ProviderEntryView>> entries(
    AgentConfigSnapshot snapshot, {
    Map<String, String> environment = const {},
    Set<String> stored = const {},
    List<String>? asked,
  }) => providerEntriesOf(
    snapshot,
    environment: environment,
    isSecretSet: (name) async {
      asked?.add(name);
      return stored.contains(name);
    },
  );

  group('статус ключа без чтения значения', () {
    test('секрет в хранилище и секрет отсутствует', () async {
      final snapshot = snapshotOf({
        'providers': {
          'a': openai({'api_key_secret': 'codelab/a'}),
          'b': openai({'api_key_secret': 'codelab/b'}),
        },
      });
      final asked = <String>[];

      final list = await entries(snapshot, stored: {'codelab/a'}, asked: asked);

      expect(
        list[0].key,
        const KeyInSecretStore(name: 'codelab/a', backendId: 'file'),
      );
      expect(
        list[1].key,
        const KeySecretMissing(name: 'codelab/b', backendId: 'file'),
      );
      expect(list[0].key.label, 'Key: in file');
      expect(list[1].key.label, 'Key: missing in file');
      // Спрашиваются только имена: у порта проверки нет метода чтения.
      expect(asked, ['codelab/a', 'codelab/b']);
    });

    test('переменная переопределения секрета побеждает хранилище', () async {
      final snapshot = snapshotOf({
        'providers': {
          'a': openai({'api_key_secret': 'codelab/a'}),
        },
      });

      final list = await entries(
        snapshot,
        environment: {'CODELAB_SECRET_CODELAB_A': leak},
      );

      expect(
        list.single.key,
        const KeyInSecretStore(name: 'codelab/a', backendId: 'env'),
      );
    });

    test('переменная api_key_env: задана и не задана', () async {
      final snapshot = snapshotOf({
        'providers': {
          'a': openai({'api_key_env': 'A_KEY'}),
          'b': openai({'api_key_env': 'B_KEY'}),
        },
      });

      final list = await entries(
        snapshot,
        environment: {'A_KEY': leak, 'B_KEY': ''},
      );

      expect(list[0].key, const KeyFromEnv(name: 'A_KEY', isSet: true));
      expect(list[1].key, const KeyFromEnv(name: 'B_KEY', isSet: false));
      expect(list[0].key.label, 'Key: env A_KEY (set)');
      expect(list[1].key.label, 'Key: env B_KEY (not set)');
    });

    test('без ключа и с литералом в файле', () async {
      final snapshot = snapshotOf({
        'providers': {
          'local': openai({}),
          'lit': openai({'api_key': leak}),
        },
      });

      final list = await entries(snapshot);

      expect(list.firstWhere((e) => e.id == 'local').key, const KeyNone());
      expect(list.firstWhere((e) => e.id == 'local').key.label, 'No key');
      expect(
        list.firstWhere((e) => e.id == 'lit').key,
        const KeyLiteralInConfig(),
      );
    });

    test(
      'значение ключа не попадает ни в представление, ни в подпись',
      () async {
        final snapshot = snapshotOf({
          'providers': {
            'a': openai({'api_key_env': 'A_KEY'}),
            'lit': openai({'api_key': leak}),
          },
        });

        final list = await entries(snapshot, environment: {'A_KEY': leak});

        for (final entry in list) {
          expect(
            '$entry ${entry.key} ${entry.key.label}',
            isNot(contains(leak)),
          );
        }
      },
    );
  });

  group('содержимое строки', () {
    test(
      'поля, модели «<id>/<модель>» и признак модели по умолчанию',
      () async {
        final snapshot = snapshotOf({
          'agent': {'default_model': 'a/gpt-a'},
          'providers': {'b': openai({}), 'a': openai({})},
        });

        final list = await entries(snapshot);

        expect(list.map((e) => e.id), ['a', 'b']);
        final a = list.first;
        expect(a.kind, 'openai-compatible');
        expect(a.baseUrl, 'https://api.example.invalid/v1');
        expect(a.models, ['a/gpt-a', 'a/gpt-b']);
        expect(a.isDefault, isTrue);
        expect(list.last.isDefault, isFalse);
        expect(a.source, userSource);
      },
    );

    test('модель с точкой и двоеточием в имени', () async {
      final snapshot = snapshotOf({
        'providers': {
          'ollama': {
            'kind': 'openai-compatible',
            'models': {
              'llama3.1:70b': {'context_window': 8000},
              'qwen2.5-coder': {'context_window': 8000},
            },
          },
        },
      });

      final list = await entries(snapshot);

      expect(list.single.models, [
        'ollama/llama3.1:70b',
        'ollama/qwen2.5-coder',
      ]);
    });

    test(
      'displayBaseUrl: без userinfo, query и fragment, путь остаётся',
      () async {
        final snapshot = snapshotOf({
          'providers': {
            'a': openai({
              'base_url':
                  'https://user:pw@h.example:8443/v1?api-key=$leak#frag',
            }),
            'b': openai({'base_url': 'http://localhost:11434/v1'}),
            'c': {'kind': 'anthropic'},
          },
        });

        final list = await entries(snapshot);

        expect(list[0].displayBaseUrl, 'https://h.example:8443/v1');
        expect(list[1].displayBaseUrl, 'http://localhost:11434/v1');
        expect(list[2].displayBaseUrl, isNull);
        for (final entry in list) {
          expect('${entry.displayBaseUrl} $entry', isNot(contains(leak)));
          expect(entry.displayBaseUrl ?? '', isNot(contains('pw')));
        }
      },
    );

    test('пустой конфиг — пустой список', () async {
      expect(await entries(snapshotOf({})), isEmpty);
    });
  });

  group('editable', () {
    test('слои user и projectLocal редактируются', () async {
      final snapshot = AgentConfigSnapshot.fromLayers(
        cwd: '/w',
        layers: {
          ConfigLayer.user: ConfigSnapshot(
            target: const ConfigTarget.user(),
            path: '/h/config.yaml',
            fingerprint: null,
            values: {
              'providers': {'a': openai({})},
            },
          ),
          ConfigLayer.projectLocal: ConfigSnapshot(
            target: const ConfigTarget.projectLocal('/w'),
            path: '/w/.codelab/config.local.yaml',
            fingerprint: 'x',
            values: {
              'providers': {'b': openai({})},
            },
          ),
        },
        loaded: const ConfigLoadResult(),
        secrets: backend,
      );

      final list = await entries(snapshot);

      expect(list.map((e) => (e.id, e.editable)), [('a', true), ('b', true)]);
      expect(list.last.source.kind, ConfigSourceKind.projectLocal);
      expect(list.last.source.label, '/w/.codelab/config.local.yaml');
    });

    test('слой 3 (project) — только чтение', () async {
      final snapshot = snapshotOf(
        {},
        project: {
          'providers': {'team': openai({})},
        },
      );

      final list = await entries(snapshot);

      expect(list.single.source.kind, ConfigSourceKind.project);
      expect(list.single.editable, isFalse);
    });

    test('--config и переменные окружения — только чтение', () async {
      const values = {
        'providers.x.kind': 'openai-compatible',
        'providers.x.base_url': 'https://x.invalid/v1',
        'providers.e.kind': 'openai-compatible',
      };
      final snapshot = snapshotOf(
        {},
        loadedValues: values,
        external: (key) => key.startsWith('providers.x.')
            ? const ConfigSourceView(
                kind: ConfigSourceKind.extraFile,
                label: '/etc/team.yaml',
              )
            : const ConfigSourceView(
                kind: ConfigSourceKind.environment,
                label: 'env',
              ),
      );

      final list = await entries(snapshot);

      expect(list.map((e) => (e.id, e.editable, e.source.kind)), [
        ('e', false, ConfigSourceKind.environment),
        ('x', false, ConfigSourceKind.extraFile),
      ]);
    });

    test('лист из чужого слоя делает всю запись нередактируемой', () async {
      final user = {
        'providers': {'a': openai({})},
      };
      final snapshot = snapshotOf(
        user,
        loadedValues: {
          ...flattenConfigValues(user),
          'providers.a.base_url': 'https://env.invalid/v1',
        },
        external: (key) => const ConfigSourceView(
          kind: ConfigSourceKind.environment,
          label: 'env',
        ),
      );

      final list = await entries(snapshot);

      expect(list.single.editable, isFalse);
      expect(list.single.source.kind, ConfigSourceKind.environment);
    });
  });
}
