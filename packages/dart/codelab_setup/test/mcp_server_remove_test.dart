import 'package:codelab_setup/codelab_setup.dart';
import 'package:test/test.dart';

import 'support/mcp_snapshots.dart';
import 'support/provider_setup_fakes.dart';

/// Удаление MCP-сервера и «Disable here» / «Enable here» (client-agent-setup
/// «Порядок записи провайдера»; design.md change `add-provider-setup-ui`, D11,
/// решения Q21, Q22; SETUP-24): секрет удаляется только после `ConfigSaved` и
/// только если на него не осталось ссылок `${secret:…}`; кандидаты — только
/// секреты, на которые ссылался удалённый элемент. Префикс
/// `codelab/mcp/<name>/` не используется: `SecretNames.forMcp` приводит имя к
/// нижнему регистру, и у `GitHub` и `github` он общий.
///
/// Ожидаемый API (задача 5.8): `McpServerRemover({config, keys})` с
/// `remove(snapshot, name:)` и `enableHere(snapshot, name:)`;
/// `McpServerCommitter.disableHere`; исходы `McpServerRemoved`,
/// `McpServerRemovalNotSaved`, `McpServerRemovalRefused`.
void main() {
  const authorization = 'codelab/mcp/github/authorization';
  const token = 'codelab/mcp/github/token';

  late List<String> journal;
  late FakeProviderKeys keys;
  late FakeConfigStore config;
  late McpServerRemover remover;
  late McpServerCommitter committer;

  AgentConfigSnapshot twoServers({
    String authorizationRef = '\${secret:$authorization}',
  }) => mcpSnapshot(
    user: [
      httpServer('github', headers: {'Authorization': authorizationRef}),
      httpServer('GitHub', headers: {'X-Token': '\${secret:$token}'}),
    ],
  );

  void rebuild() {
    remover = McpServerRemover(config: config, keys: keys);
    committer = McpServerCommitter(config: config, keys: keys);
  }

  setUp(() {
    journal = [];
    keys = FakeProviderKeys(stored: {authorization, token});
    config = FakeConfigStore(journal);
    config.snapshotValue = mcpSnapshot();
    rebuild();
    // Свежий снимок после записи: оба сервера, `github` уже без заголовка.
    config.snapshotValue = mcpSnapshot(
      user: [
        httpServer('GitHub', headers: {'X-Token': '\${secret:$token}'}),
      ],
    );
  });

  group('удаление с секретами (Q22; сценарий «Удаление с секретами»)', () {
    test('RemoveMcpServer пишется в слой сервера; удаляется только секрет '
        'удалённого элемента, секрет сервера GitHub остаётся', () async {
      final snapshot = twoServers();

      final outcome = await remover.remove(snapshot, name: 'github');

      expect(outcome, isA<McpServerRemoved>());
      final applied = config.applied.single;
      expect(applied.base, snapshot.layers[ConfigLayer.user]);
      expect(applied.edits, [const RemoveMcpServer('github')]);
      expect(keys.journal.where((j) => j.startsWith('delete')), [
        'delete $authorization',
      ]);
      expect(keys.storedNames, contains(token));
      expect((outcome as McpServerRemoved).secrets, {
        authorization: SecretCleanup.deleted,
      });
    });

    test('секрет удаляется только после ConfigSaved: apply раньше delete в '
        'общем журнале', () async {
      remover = McpServerRemover(
        config: config,
        keys: _OrderedKeys(keys, journal),
      );

      await remover.remove(twoServers(), name: 'github');

      expect(journal, ['apply', 'delete $authorization']);
    });

    test('отказ записи: оба секрета на месте, удаления не было', () async {
      config.outcome = const ConfigConflict('/h/config.yaml');

      final outcome = await remover.remove(twoServers(), name: 'github');

      expect(outcome, isA<McpServerRemovalNotSaved>());
      expect(keys.journal.where((j) => j.startsWith('delete')), isEmpty);
      expect(keys.storedNames, containsAll([authorization, token]));
    });

    test('исключение apply: тип без текста, секреты на месте', () async {
      config.throwOnApply = StateError('boom');

      final outcome = await remover.remove(twoServers(), name: 'github');

      expect(outcome, isA<McpServerRemovalNotSaved>());
      expect((outcome as McpServerRemovalNotSaved).errorType, 'StateError');
      expect(keys.journal.where((j) => j.startsWith('delete')), isEmpty);
    });

    test('секрет, на который ссылается другой сервер, не удаляется', () async {
      // Свежий снимок после записи: другой сервер ссылается на тот же секрет.
      config.snapshotValue = mcpSnapshot(
        user: [
          httpServer('other', headers: {'X': '\${secret:$authorization}'}),
        ],
      );

      final outcome = await remover.remove(twoServers(), name: 'github');

      expect((outcome as McpServerRemoved).secrets, {
        authorization: SecretCleanup.stillReferenced,
      });
      expect(keys.journal.where((j) => j.startsWith('delete')), isEmpty);
    });

    test('ссылку на секрет нашёл свежий снимок, а не исходный: перечитывание '
        'после записи (SETUP-24)', () async {
      final fresh = mcpSnapshot(
        projectLocal: [
          httpServer('late', headers: {'X': '\${secret:$authorization}'}),
        ],
      );
      config.snapshotValue = fresh;

      final outcome = await remover.remove(twoServers(), name: 'github');

      expect(
        (outcome as McpServerRemoved).secrets[authorization],
        SecretCleanup.stillReferenced,
      );
    });

    test(
      'свежий снимок не получен: секрет не удаляется, исход failed',
      () async {
        config.snapshotValue = null;

        final outcome = await remover.remove(twoServers(), name: 'github');

        expect((outcome as McpServerRemoved).secrets, {
          authorization: SecretCleanup.failed,
        });
        expect(keys.journal.where((j) => j.startsWith('delete')), isEmpty);
      },
    );

    test(
      'хранилище отказало в удалении: сервер удалён, исход failed',
      () async {
        keys.deletion = SecretDeletion.failed;

        final outcome = await remover.remove(twoServers(), name: 'github');

        expect(outcome, isA<McpServerRemoved>());
        expect((outcome as McpServerRemoved).secrets, {
          authorization: SecretCleanup.failed,
        });
      },
    );

    test('секрета уже нет: alreadyAbsent', () async {
      keys.deletion = SecretDeletion.notSet;

      final outcome = await remover.remove(twoServers(), name: 'github');

      expect(
        (outcome as McpServerRemoved).secrets[authorization],
        SecretCleanup.alreadyAbsent,
      );
    });

    test(
      'в кандидаты попадают ссылки env и headers, но не литералы и не '
      r'${VAR}; ссылка внутри текста (Bearer ${secret:…}) тоже кандидат',
      () async {
        final snapshot = mcpSnapshot(
          user: [
            stdioServer(
              'gh',
              env: {
                'A': '\${secret:codelab/mcp/gh/a}',
                'B': '\${PG_URL}',
                'C': 'plain',
              },
            ),
            httpServer(
              'gh2',
              headers: {
                'Authorization': 'Bearer \${secret:codelab/mcp/gh2/auth}',
              },
            ),
          ],
        );
        keys = FakeProviderKeys(
          stored: {'codelab/mcp/gh/a', 'codelab/mcp/gh2/auth'},
        );
        config.snapshotValue = mcpSnapshot();
        rebuild();

        final first = await remover.remove(snapshot, name: 'gh');
        final second = await remover.remove(snapshot, name: 'gh2');

        expect((first as McpServerRemoved).secrets.keys, ['codelab/mcp/gh/a']);
        expect((second as McpServerRemoved).secrets.keys, [
          'codelab/mcp/gh2/auth',
        ]);
      },
    );

    test('Remove трогает только секреты пространства codelab/mcp/<name>/: '
        'ручной \${secret:shared} остаётся (kept), хранилище не '
        'трогается', () async {
      keys = FakeProviderKeys(stored: {authorization, 'shared'});
      rebuild();
      config.snapshotValue = mcpSnapshot();
      final snapshot = mcpSnapshot(
        user: [
          httpServer(
            'github',
            headers: {
              'Authorization': '\${secret:$authorization}',
              'X-Shared': '\${secret:shared}',
            },
          ),
        ],
      );

      final outcome = await remover.remove(snapshot, name: 'github');

      expect((outcome as McpServerRemoved).secrets, {
        authorization: SecretCleanup.deleted,
        'shared': SecretCleanup.kept,
      });
      expect(keys.journal.where((j) => j.startsWith('delete')), [
        'delete $authorization',
      ]);
      expect(keys.storedNames, contains('shared'));
    });

    test(
      'чужое пространство того же вида (codelab/mcp/other/x) тоже kept',
      () async {
        keys = FakeProviderKeys(stored: {'codelab/mcp/other/x'});
        rebuild();
        config.snapshotValue = mcpSnapshot();
        final snapshot = mcpSnapshot(
          user: [
            httpServer(
              'github',
              headers: {'X': '\${secret:codelab/mcp/other/x}'},
            ),
          ],
        );

        final outcome = await remover.remove(snapshot, name: 'github');

        expect((outcome as McpServerRemoved).secrets, {
          'codelab/mcp/other/x': SecretCleanup.kept,
        });
        expect(keys.journal.where((j) => j.startsWith('delete')), isEmpty);
      },
    );

    test('сервер без секретов: ни одного обращения к хранилищу', () async {
      final outcome = await remover.remove(
        mcpSnapshot(user: [httpServer('plain')]),
        name: 'plain',
      );

      expect((outcome as McpServerRemoved).secrets, isEmpty);
      expect(keys.journal, isEmpty);
    });

    test('сервер слоя 3 удалить нельзя; неизвестный — отказ', () async {
      final project = await remover.remove(
        mcpSnapshot(project: [stdioServer('playwright')]),
        name: 'playwright',
      );
      final unknown = await remover.remove(mcpSnapshot(), name: 'nope');

      expect(
        (project as McpServerRemovalRefused).reason,
        McpServerRefusal.notEditable,
      );
      expect(
        (unknown as McpServerRemovalRefused).reason,
        McpServerRefusal.unknownServer,
      );
      expect(config.applied, isEmpty);
    });
  });

  group('«Disable here» / «Enable here» для сервера слоя 3 (Q21)', () {
    // Файл `config.local.yaml` читается (пока пуст): слой в снимке есть.
    final project = mcpSnapshot(
      project: [stdioServer('playwright', command: 'pw')],
      projectLocal: const [],
    );
    const access = EditableSettings(
      ConfigPaths(codelabHome: '/h', projectDir: mcpCwd),
    );

    test('disableHere пишет {name, enabled: false} в projectLocal, проектный '
        'файл не затрагивается', () async {
      final outcome = await committer.disableHere(
        project,
        'playwright',
        access: access,
      );

      expect(outcome, isA<McpServerWritten>());
      final applied = config.applied.single;
      expect(applied.edits, [
        const UpsertMcpServer({'name': 'playwright', 'enabled': false}),
      ]);
      expect(applied.base.target, const ConfigTarget.projectLocal(mcpCwd));
    });

    test('нечитаемый config.local.yaml (слоя нет в снимке) — отказ '
        'layerUnreadable, а не ConfigConflict', () async {
      final unreadable = mcpSnapshot(
        project: [stdioServer('playwright', command: 'pw')],
      );

      final outcome = await committer.disableHere(
        unreadable,
        'playwright',
        access: access,
      );

      expect(
        (outcome as McpServerRefused).reason,
        McpServerRefusal.layerUnreadable,
      );
      expect(config.applied, isEmpty);
    });

    test('профиль без цели projectLocal (папка проекта неизвестна) — отказ '
        'noProjectTarget, запись не идёт (D5, SETUP-3)', () async {
      final outcome = await committer.disableHere(
        project,
        'playwright',
        access: const EditableSettings(ConfigPaths(codelabHome: '/h')),
      );

      expect(
        (outcome as McpServerRefused).reason,
        McpServerRefusal.noProjectTarget,
      );
      expect(config.applied, isEmpty);
    });

    test('disableHere только для сервера слоя 3: user-сервер и неизвестный — '
        'отказ', () async {
      final user = await committer.disableHere(
        mcpSnapshot(user: [httpServer('u')]),
        'u',
        access: access,
      );
      final unknown = await committer.disableHere(
        project,
        'nope',
        access: access,
      );

      expect((user as McpServerRefused).reason, McpServerRefusal.notProject);
      expect(
        (unknown as McpServerRefused).reason,
        McpServerRefusal.unknownServer,
      );
      expect(config.applied, isEmpty);
    });

    test('enableHere удаляет переопределение: RemoveMcpServer из '
        'projectLocal', () async {
      final disabled = mcpSnapshot(
        project: [stdioServer('playwright', command: 'pw')],
        projectLocal: [
          {'name': 'playwright', 'enabled': false},
        ],
      );

      final outcome = await remover.enableHere(disabled, name: 'playwright');

      expect(outcome, isA<McpServerWritten>());
      final applied = config.applied.single;
      expect(applied.edits, [const RemoveMcpServer('playwright')]);
      expect(applied.base, disabled.layers[ConfigLayer.projectLocal]);
    });

    test('enableHere без переопределения «disabled here» — отказ, запись не '
        'идёт', () async {
      final outcome = await remover.enableHere(project, name: 'playwright');

      expect(
        (outcome as McpServerRefused).reason,
        McpServerRefusal.notDisabledHere,
      );
      expect(config.applied, isEmpty);
    });

    test('enableHere не трогает полное переопределение пользователя', () async {
      final full = mcpSnapshot(
        project: [stdioServer('playwright')],
        projectLocal: [stdioServer('playwright', command: 'mine')],
      );

      final outcome = await remover.enableHere(full, name: 'playwright');

      expect(outcome, isA<McpServerRefused>());
      expect(config.applied, isEmpty);
    });

    test('конфликт записи пробрасывается без автоповтора (SETUP-6)', () async {
      config.outcome = const ConfigConflict('/w/.codelab/config.local.yaml');

      final outcome = await committer.disableHere(
        project,
        'playwright',
        access: access,
      );

      expect((outcome as McpServerNotWritten).outcome, isA<ConfigConflict>());
      expect(config.applied, hasLength(1));
    });
  });
}

/// Порт ключей, который пишет `delete` в общий журнал вместе с `apply`
/// хранилища конфига: порядок «конфиг → секрет» (SETUP-24) виден одним
/// списком.
final class _OrderedKeys implements ProviderKeys {
  _OrderedKeys(this._inner, this._journal);

  final FakeProviderKeys _inner;
  final List<String> _journal;

  @override
  SecretBackendInfo get backend => _inner.backend;

  @override
  String? get readOnlyHint => _inner.readOnlyHint;

  @override
  Future<bool> stored(String name) => _inner.stored(name);

  @override
  Future<SecretValue?> read(String name) => _inner.read(name);

  @override
  Future<ProviderKeyWrite> write(String name, SecretValue value) =>
      _inner.write(name, value);

  @override
  Future<SecretDeletion> delete(String name) {
    _journal.add('delete $name');
    return _inner.delete(name);
  }
}
