import 'package:codelab_setup/codelab_setup.dart';
import 'package:codelab_setup/src/config/config_values.dart';
import 'package:test/test.dart';

/// Удаление провайдера (client-agent-setup «Порядок записи провайдера»:
/// «Удаление провайдера SHALL удалять секрет только после `ConfigSaved`»;
/// SETUP-24; design.md change `add-provider-setup-ui`, D10).
///
/// Порты — фейки: порядок вызовов записывает один журнал, поэтому «секрет
/// после конфига» проверяется без таймеров.
void main() {
  const backend = SecretBackendInfo(id: 'file', writable: true);

  AgentConfigSnapshot snapshotOf({
    Map<String, Object?> user = const {},
    Map<String, Object?>? projectLocal,
    Map<String, Object?> loadedValues = const {},
    Map<String, ConfigSourceView> extra = const {},
  }) => AgentConfigSnapshot.fromLayers(
    cwd: '/work/project',
    layers: {
      ConfigLayer.user: ConfigSnapshot(
        target: const ConfigTarget.user(),
        path: '/h/config.yaml',
        fingerprint: 'fp-user',
        values: user,
      ),
      if (projectLocal != null)
        ConfigLayer.projectLocal: ConfigSnapshot(
          target: const ConfigTarget.projectLocal('/work/project'),
          path: '/work/project/.codelab/config.local.yaml',
          fingerprint: 'fp-local',
          values: projectLocal,
        ),
    },
    loaded: ConfigLoadResult(values: loadedValues),
    secrets: backend,
    externalOrigin: (key) => extra[key],
  );

  Map<String, Object?> provider(String secret) => {
    'kind': 'openai-compatible',
    'base_url': 'https://h/v1',
    'api_key_secret': secret,
    'models': {
      'm': {'context_window': 32000},
    },
  };

  Map<String, Object?> twoProviders({String? defaultModel = 'a/m'}) => {
    'agent': {'default_model': ?defaultModel},
    'providers': {'a': provider('codelab/a'), 'b': provider('codelab/b')},
  };

  late List<String> journal;
  late _FakeStore store;
  late ProviderRemover remover;
  late List<String> deleted;
  SecretDeletion Function(String name) deletion = (_) => SecretDeletion.deleted;

  setUp(() {
    journal = [];
    deleted = [];
    deletion = (_) => SecretDeletion.deleted;
    store = _FakeStore(journal);
    remover = ProviderRemover(
      config: store,
      deleteSecret: (name) async {
        journal.add('delete $name');
        deleted.add(name);
        return deletion(name);
      },
    );
  });

  group('правки одним apply', () {
    test('RemoveTable и новая модель по умолчанию — один вызов', () async {
      final snapshot = snapshotOf(user: twoProviders());

      final outcome = await remover.remove(
        snapshot,
        providerId: 'a',
        newDefaultModel: 'b/m',
      );

      expect(outcome, isA<ProviderRemoved>());
      expect(store.applied, hasLength(1));
      final call = store.applied.single;
      expect(call.base.target, const ConfigTarget.user());
      expect(call.base.fingerprint, 'fp-user');
      expect(call.edits, [
        const RemoveTable('providers.a'),
        const SetValue('agent.default_model', 'b/m'),
      ]);
    });

    test('не модель по умолчанию — только RemoveTable', () async {
      final snapshot = snapshotOf(user: twoProviders());

      await remover.remove(snapshot, providerId: 'b');

      expect(store.applied.single.edits, [const RemoveTable('providers.b')]);
    });

    test('провайдер слоя projectLocal пишется в projectLocal', () async {
      final snapshot = snapshotOf(
        projectLocal: twoProviders(defaultModel: null),
      );

      await remover.remove(snapshot, providerId: 'b');

      expect(
        store.applied.single.base.target,
        const ConfigTarget.projectLocal('/work/project'),
      );
    });
  });

  group('отказы без записи', () {
    test('последнего провайдера удалить нельзя', () async {
      final snapshot = snapshotOf(
        user: {
          'agent': {'default_model': 'a/m'},
          'providers': {'a': provider('codelab/a')},
        },
      );

      final outcome = await remover.remove(snapshot, providerId: 'a');

      expect(
        outcome,
        isA<ProviderRemovalRefused>().having(
          (o) => o.reason,
          'reason',
          ProviderRemovalRefusal.lastProvider,
        ),
      );
      expect(journal, isEmpty);
    });

    test('модель по умолчанию без замены — отказ', () async {
      final snapshot = snapshotOf(user: twoProviders());

      final missing = await remover.remove(snapshot, providerId: 'a');
      final same = await remover.remove(
        snapshot,
        providerId: 'a',
        newDefaultModel: 'a/m',
      );
      final unknown = await remover.remove(
        snapshot,
        providerId: 'a',
        newDefaultModel: 'zzz/m',
      );

      expect(
        [
          missing,
          same,
          unknown,
        ].map((o) => (o as ProviderRemovalRefused).reason),
        [
          ProviderRemovalRefusal.newDefaultRequired,
          ProviderRemovalRefusal.newDefaultInvalid,
          ProviderRemovalRefusal.newDefaultInvalid,
        ],
      );
      expect(journal, isEmpty);
    });

    test('неизвестный провайдер — отказ', () async {
      final snapshot = snapshotOf(user: twoProviders(defaultModel: null));

      final outcome = await remover.remove(snapshot, providerId: 'nope');

      expect(
        (outcome as ProviderRemovalRefused).reason,
        ProviderRemovalRefusal.unknownProvider,
      );
      expect(journal, isEmpty);
    });

    test('значение из чужого слоя делает провайдера нередактируемым', () async {
      // Итоговое значение `base_url` не совпадает со слоем user: его задало
      // окружение, и правка файла его не изменит.
      final snapshot = snapshotOf(
        user: twoProviders(defaultModel: null),
        loadedValues: {
          ...flattenConfigValues(twoProviders(defaultModel: null)),
          'providers.b.base_url': 'https://other.invalid/v1',
        },
        extra: {
          'providers.b.base_url': const ConfigSourceView(
            kind: ConfigSourceKind.environment,
            label: 'env',
          ),
        },
      );

      final outcome = await remover.remove(snapshot, providerId: 'b');

      expect(
        (outcome as ProviderRemovalRefused).reason,
        ProviderRemovalRefusal.notEditable,
      );
      expect(journal, isEmpty);
    });

    test('листья провайдера в двух слоях — отказ без записи', () async {
      // `base_url` переопределён в projectLocal: RemoveTable одного слоя
      // оставил бы в другом обрывок провайдера.
      final snapshot = snapshotOf(
        user: twoProviders(defaultModel: null),
        projectLocal: {
          'providers': {
            'b': {'base_url': 'https://local.invalid/v1'},
          },
        },
      );

      final outcome = await remover.remove(snapshot, providerId: 'b');

      expect(
        (outcome as ProviderRemovalRefused).reason,
        ProviderRemovalRefusal.multipleLayers,
      );
      expect(journal, isEmpty);
    });

    test('снимка слоя нет — отказ без записи', () async {
      // Итоговые значения известны, а файл слоя не читался (битый YAML):
      // основы для `apply` нет.
      final values = flattenConfigValues(twoProviders(defaultModel: null));
      final snapshot = AgentConfigSnapshot(
        cwd: '/work/project',
        layers: const {},
        loaded: ConfigLoadResult(values: values),
        origins: {
          for (final key in values.keys)
            key: const ConfigSourceView(
              kind: ConfigSourceKind.user,
              label: '/h/config.yaml',
            ),
        },
        secrets: backend,
      );

      final outcome = await remover.remove(snapshot, providerId: 'b');

      expect(
        (outcome as ProviderRemovalRefused).reason,
        ProviderRemovalRefusal.layerUnreadable,
      );
      expect(journal, isEmpty);
    });

    test('модель по умолчанию из более приоритетного слоя', () async {
      // Провайдер в user, а `agent.default_model` задан в projectLocal: правка
      // слоя user не сменит итоговую модель.
      final snapshot = snapshotOf(
        user: {
          'providers': {'a': provider('codelab/a'), 'b': provider('codelab/b')},
        },
        projectLocal: {
          'agent': {'default_model': 'a/m'},
        },
      );

      final outcome = await remover.remove(
        snapshot,
        providerId: 'a',
        newDefaultModel: 'b/m',
      );

      expect(
        (outcome as ProviderRemovalRefused).reason,
        ProviderRemovalRefusal.defaultOverridden,
      );
      expect(journal, isEmpty);
    });
  });

  group('секрет удаляется только после ConfigSaved (SETUP-24)', () {
    test('ConfigSaved — сначала apply, потом delete', () async {
      final snapshot = snapshotOf(user: twoProviders(defaultModel: null));

      final outcome = await remover.remove(
        snapshot,
        providerId: 'b',
        deleteStoredKey: true,
      );

      expect(journal, ['apply', 'delete codelab/b']);
      expect(outcome, isA<ProviderRemoved>());
      expect((outcome as ProviderRemoved).secret, SecretCleanup.deleted);
    });

    for (final unsaved in <ConfigSaveOutcome>[
      const ConfigConflict('/h/config.yaml'),
      const ConfigRejected([]),
      const ConfigInlineSecret(key: 'k', suggestedSecretName: 'codelab/k'),
    ]) {
      test('${unsaved.runtimeType} — секрет не тронут', () async {
        store.result = unsaved;
        final snapshot = snapshotOf(user: twoProviders(defaultModel: null));

        final outcome = await remover.remove(
          snapshot,
          providerId: 'b',
          deleteStoredKey: true,
        );

        expect(outcome, isA<ProviderRemovalNotSaved>());
        expect((outcome as ProviderRemovalNotSaved).outcome, same(unsaved));
        expect(deleted, isEmpty);
        // Конфликт не повторяется автоматически (SETUP-6).
        expect(store.applied, hasLength(1));
      });
    }

    test('без флажка секрет не удаляется', () async {
      final snapshot = snapshotOf(user: twoProviders(defaultModel: null));

      final outcome = await remover.remove(snapshot, providerId: 'b');

      expect((outcome as ProviderRemoved).secret, SecretCleanup.notRequested);
      expect(deleted, isEmpty);
    });

    test('чужой и общий секрет не удаляются', () async {
      final shared = snapshotOf(
        user: {
          'providers': {
            'a': provider('codelab/shared'),
            'b': provider('codelab/shared'),
          },
        },
      );
      final foreign = snapshotOf(
        user: {
          'providers': {'a': provider('team/key'), 'b': provider('codelab/b')},
        },
      );

      final sharedOutcome = await remover.remove(
        shared,
        providerId: 'a',
        deleteStoredKey: true,
      );
      final foreignOutcome = await remover.remove(
        foreign,
        providerId: 'a',
        deleteStoredKey: true,
      );

      expect(
        (sharedOutcome as ProviderRemoved).secret,
        SecretCleanup.notRequested,
      );
      expect(
        (foreignOutcome as ProviderRemoved).secret,
        SecretCleanup.notRequested,
      );
      expect(deleted, isEmpty);
    });

    test('ссылка на секрет из MCP-сервера: флажка нет, секрет цел', () async {
      Map<String, Object?> withMcp(String reference) => {
        ...twoProviders(defaultModel: null),
        'mcp': {
          'servers': [
            {
              'name': 'gh',
              'type': 'http',
              'url': 'https://mcp.invalid/',
              'headers': {'Authorization': 'Bearer $reference'},
            },
          ],
        },
      };
      final snapshot = snapshotOf(user: withMcp(r'${secret:codelab/b}'));

      final outcome = await remover.remove(
        snapshot,
        providerId: 'b',
        deleteStoredKey: true,
      );

      expect(ProviderRemover.ownedSecretName(snapshot, 'b'), isNull);
      expect((outcome as ProviderRemoved).secret, SecretCleanup.notRequested);
      expect(deleted, isEmpty);
    });

    test('ссылка появилась в другом слое после записи — секрет цел', () async {
      // Между снимком и удалением секрета другой процесс добавил ссылку.
      store.fresh = snapshotOf(
        user: {
          'providers': {'a': provider('codelab/a')},
        },
        projectLocal: {
          'mcp': {
            'servers': [
              {
                'name': 'gh',
                'type': 'http',
                'url': 'https://mcp.invalid/',
                'headers': {'X-Key': r'${secret:codelab/b}'},
              },
            ],
          },
        },
      );
      final snapshot = snapshotOf(user: twoProviders(defaultModel: null));

      final outcome = await remover.remove(
        snapshot,
        providerId: 'b',
        deleteStoredKey: true,
      );

      expect(
        (outcome as ProviderRemoved).secret,
        SecretCleanup.stillReferenced,
      );
      expect(deleted, isEmpty);
    });

    test('свежий снимок не получен — секрет не удаляется', () async {
      store.fresh = StateError('disk');
      final snapshot = snapshotOf(user: twoProviders(defaultModel: null));

      final outcome = await remover.remove(
        snapshot,
        providerId: 'b',
        deleteStoredKey: true,
      );

      expect((outcome as ProviderRemoved).secret, SecretCleanup.failed);
      expect(deleted, isEmpty);
    });

    test('отказ удаления секрета не отменяет удаление провайдера', () async {
      deletion = (_) => SecretDeletion.failed;
      final snapshot = snapshotOf(user: twoProviders(defaultModel: null));

      final outcome = await remover.remove(
        snapshot,
        providerId: 'b',
        deleteStoredKey: true,
      );

      expect(outcome, isA<ProviderRemoved>());
      expect((outcome as ProviderRemoved).secret, SecretCleanup.failed);
      expect(store.applied, hasLength(1));
    });

    test('секрета в хранилище уже нет', () async {
      deletion = (_) => SecretDeletion.notSet;
      final snapshot = snapshotOf(user: twoProviders(defaultModel: null));

      final outcome = await remover.remove(
        snapshot,
        providerId: 'b',
        deleteStoredKey: true,
      );

      expect((outcome as ProviderRemoved).secret, SecretCleanup.alreadyAbsent);
    });
  });

  test(
    'ownedSecretName: подсказка для флажка «Also delete the stored key»',
    () {
      final snapshot = snapshotOf(
        user: {
          'providers': {
            'a': provider('codelab/a'),
            'b': provider('team/key'),
            'c': provider('codelab/a'),
          },
        },
      );

      // `a` делит секрет с `c`, `b` ссылается на чужое имя.
      expect(ProviderRemover.ownedSecretName(snapshot, 'a'), isNull);
      expect(ProviderRemover.ownedSecretName(snapshot, 'b'), isNull);
      expect(
        ProviderRemover.ownedSecretName(snapshotOf(user: twoProviders()), 'b'),
        'codelab/b',
      );
    },
  );
}

typedef _Applied = ({ConfigSnapshot base, List<ConfigEdit> edits});

final class _FakeStore implements AgentConfigStore {
  _FakeStore(this._journal);

  final List<String> _journal;
  final applied = <_Applied>[];

  /// Снимок, который вернёт `snapshot` после записи (по умолчанию пустой);
  /// `Exception` — `snapshot` бросает его.
  Object? fresh;
  ConfigSaveOutcome result = const ConfigSaved(
    fingerprint: 'fp-new',
    warnings: [],
    restartRequiredKeys: [],
  );

  @override
  Future<ConfigSaveOutcome> apply(
    ConfigSnapshot base,
    List<ConfigEdit> edits,
  ) async {
    _journal.add('apply');
    applied.add((base: base, edits: edits));
    return result;
  }

  @override
  Future<AgentConfigSnapshot> snapshot({required String cwd}) async {
    final next = fresh;
    if (next != null && next is! AgentConfigSnapshot) {
      throw next;
    }
    return (next as AgentConfigSnapshot?) ??
        AgentConfigSnapshot(
          cwd: cwd,
          layers: const {},
          loaded: const ConfigLoadResult(),
          origins: const {},
          secrets: const SecretBackendInfo(id: 'file', writable: true),
        );
  }
}
