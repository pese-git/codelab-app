import 'package:codelab_setup/codelab_setup.dart';
import 'package:test/test.dart';

import 'support/mcp_snapshots.dart';
import 'support/provider_setup_fakes.dart';

/// Порядок записи MCP-сервера (client-agent-setup «Порядок записи
/// провайдера» и «Черновик MCP-сервера»; design.md change
/// `add-provider-setup-ui`, D9, D11 «Сверка с кодом»; SETUP-5, SETUP-6):
/// секрет, затем конфиг, с откатом созданного секрета. Переключатель
/// `enabled` и правка пишут сырой элемент слоя целиком с изменённым полем:
/// `UpsertMcpServer` заменяет элемент по `name`, и `{name, enabled}` стёр бы
/// остальные ключи.
///
/// Ожидаемый API (задача 5.8): `McpServerCommitter({config, keys})` с
/// `commit(draft, base, {replaceSecrets})`, `setEnabled(snapshot, name,
/// enabled:)`, `disableHere(snapshot, name)`; исходы `McpServerCommitted`,
/// `McpSecretAppeared`, `McpSecretNotStored`, `McpServerNotSaved`,
/// `McpServerWritten`, `McpServerNotWritten`, `McpServerRefused`.
void main() {
  const leak = 'sk-test-leak-0123456789';
  const base = ConfigSnapshot(
    target: ConfigTarget.user(),
    path: '/h/config.yaml',
    fingerprint: 'fp',
    values: {},
  );
  const authorization = 'codelab/mcp/github/authorization';
  const cwd = '/work/project';

  late List<String> journal;
  late FakeProviderKeys keys;
  late FakeConfigStore config;
  late McpServerCommitter committer;

  McpServerDraft draft({
    Map<String, McpValueDraft>? headers,
    String name = 'github',
  }) => McpServerDraft(
    name: name,
    kind: McpTransportKind.http,
    url: 'https://mcp.test/mcp',
    headers:
        headers ?? {'Authorization': McpValueDraft.secret(SecretValue(leak))},
  );

  McpServerDraft twoSecrets() => McpServerDraft(
    name: 'github',
    kind: McpTransportKind.http,
    url: 'https://mcp.test/mcp',
    headers: {
      'Authorization': McpValueDraft.secret(SecretValue(leak)),
      'X-Token': McpValueDraft.secret(SecretValue(leak)),
    },
  );

  void rebuild() => committer = McpServerCommitter(config: config, keys: keys);

  setUp(() {
    journal = [];
    keys = FakeProviderKeys();
    config = FakeConfigStore(journal);
    rebuild();
  });

  group('секрет → конфиг → откат', () {
    test('успех: секрет записан раньше конфига, правка — одна '
        'UpsertMcpServer без значения', () async {
      final outcome = await committer.commit(draft(), base, cwd: cwd);

      expect(outcome, isA<McpServerCommitted>());
      expect((outcome as McpServerCommitted).replacedSecrets, isEmpty);
      expect(keys.written, {authorization: leak});
      expect(config.applied.single.base, base);
      expect(config.applied.single.edits, draft().toEdits());
      expect('${config.applied.single.edits}', isNot(contains(leak)));
      expect(keys.journal, ['stored $authorization', 'write $authorization']);
    });

    test('без секретов хранилище не трогается', () async {
      final outcome = await committer.commit(
        draft(headers: {'X-Team': McpValueDraft.text('core')}),
        base,
        cwd: cwd,
      );

      expect(outcome, isA<McpServerCommitted>());
      expect(keys.journal, isEmpty);
      expect(config.applied, hasLength(1));
    });

    test('откат созданного секрета при отказе валидатора', () async {
      config.outcome = const ConfigRejected([]);

      final outcome = await committer.commit(draft(), base, cwd: cwd);

      final failed = outcome as McpServerNotSaved;
      expect(failed.outcome, isA<ConfigRejected>());
      expect(failed.rollback, KeyRollback.deleted);
      expect(keys.journal, contains('delete $authorization'));
      expect(keys.written, isEmpty);
    });

    test(
      'конфликт файла: секрет откатывается, автоповтора нет (SETUP-6)',
      () async {
        config.outcome = const ConfigConflict('/h/config.yaml');

        final outcome = await committer.commit(draft(), base, cwd: cwd);

        expect((outcome as McpServerNotSaved).outcome, isA<ConfigConflict>());
        expect(outcome.rollback, KeyRollback.deleted);
        expect(config.applied, hasLength(1));
      },
    );

    test('ConfigInlineSecret пробрасывается как исход записи', () async {
      config.outcome = const ConfigInlineSecret(
        key: 'mcp.servers[github].headers.Authorization',
        suggestedSecretName: authorization,
      );

      final outcome = await committer.commit(draft(), base, cwd: cwd);

      expect((outcome as McpServerNotSaved).outcome, isA<ConfigInlineSecret>());
    });

    test('«Replace it»: имя в replaceSecrets — без перепроверки stored; '
        'заменённый секрет не откатывается', () async {
      keys = FakeProviderKeys(stored: {authorization});
      rebuild();
      config.outcome = const ConfigConflict('/h/config.yaml');

      final outcome = await committer.commit(
        draft(),
        base,
        replaceSecrets: {authorization},
        cwd: cwd,
      );

      final failed = outcome as McpServerNotSaved;
      expect(failed.replacedSecrets, [authorization]);
      expect(failed.rollback, KeyRollback.none);
      expect(keys.journal.where((j) => j.startsWith('stored')), isEmpty);
      expect(keys.journal.where((j) => j.startsWith('delete')), isEmpty);
    });

    test('успех с заменой сообщает, какие секреты заменены', () async {
      keys = FakeProviderKeys(stored: {authorization});
      rebuild();

      final outcome = await committer.commit(
        draft(),
        base,
        replaceSecrets: {authorization},
        cwd: cwd,
      );

      expect((outcome as McpServerCommitted).replacedSecrets, [authorization]);
    });

    test('секрет с таким именем уже есть: McpSecretAppeared, ни write, ни '
        'apply', () async {
      keys = FakeProviderKeys(stored: {authorization});
      rebuild();

      final outcome = await committer.commit(draft(), base, cwd: cwd);

      expect((outcome as McpSecretAppeared).names, [authorization]);
      expect(keys.journal.where((j) => j.startsWith('write')), isEmpty);
      expect(config.applied, isEmpty);
    });

    test('несколько секретов: имена проверяются до первой записи, частичной '
        'записи нет', () async {
      keys = FakeProviderKeys(stored: {'codelab/mcp/github/x-two'});
      rebuild();
      final two = draft(
        headers: {
          'Authorization': McpValueDraft.secret(SecretValue(leak)),
          'X-Two': McpValueDraft.secret(SecretValue('two')),
        },
      );

      final outcome = await committer.commit(two, base, cwd: cwd);

      expect(outcome, isA<McpSecretAppeared>());
      expect(keys.journal.where((j) => j.startsWith('write')), isEmpty);
    });

    test('отказ хранилища на втором секрете: созданный первый откатывается, '
        'apply не вызывался', () async {
      keys.onWrite = (name, value) => name.endsWith('x-two')
          ? const ProviderKeyRefused('store failed')
          : const ProviderKeyCreated();
      final two = draft(
        headers: {
          'Authorization': McpValueDraft.secret(SecretValue(leak)),
          'X-Two': McpValueDraft.secret(SecretValue('two')),
        },
      );

      final outcome = await committer.commit(two, base, cwd: cwd);

      expect((outcome as McpSecretNotStored).reason, 'store failed');
      expect(keys.journal, contains('delete $authorization'));
      expect(config.applied, isEmpty);
    });

    test('исключение apply: тип без текста, откат выполнен, маркер не в '
        'исходе', () async {
      config.throwOnApply = StateError('boom $leak');

      final outcome = await committer.commit(draft(), base, cwd: cwd);

      final failed = outcome as McpServerNotSaved;
      expect(failed.outcome, isNull);
      expect(failed.errorType, 'StateError');
      expect(failed.rollback, KeyRollback.deleted);
      expect('$failed', isNot(contains(leak)));
    });

    test('откат не удался: rollback=failed', () async {
      config.outcome = const ConfigRejected([]);
      keys.deletion = SecretDeletion.failed;

      final outcome = await committer.commit(draft(), base, cwd: cwd);

      expect((outcome as McpServerNotSaved).rollback, KeyRollback.failed);
    });

    test(
      'откат бросил исключение: rollback=failed, исход записи сохранён',
      () async {
        config.outcome = const ConfigConflict('/h/config.yaml');
        keys.throwOnDelete = StateError('boom $leak');

        final outcome = await committer.commit(draft(), base, cwd: cwd);

        final failed = outcome as McpServerNotSaved;
        expect(failed.outcome, isA<ConfigConflict>());
        expect(failed.rollback, KeyRollback.failed);
        expect('$failed', isNot(contains(leak)));
      },
    );

    test('недопустимый черновик не пишется (validate — до записи)', () async {
      final outcome = await committer.commit(
        draft(name: 'a b'),
        base,
        cwd: cwd,
      );

      expect(outcome, isA<McpServerInvalid>());
      expect(keys.journal, isEmpty);
      expect(config.applied, isEmpty);
    });
  });

  group('правка и переключатель пишут сырой элемент слоя', () {
    final raw = httpServer(
      'github',
      headers: {
        'Authorization': r'${secret:codelab/mcp/github/authorization}',
        'X-Team': 'core',
      },
      extra: {'call_timeout': '30s', 'enabled': true},
    );

    test('правка поля: ключи элемента не теряются, хранимый секрет не '
        'переписывается', () async {
      final edited = McpServerDraft.fromElement(
        raw,
      ).copyWith(url: 'https://mcp2.test/mcp');

      final outcome = await committer.commit(edited, base, cwd: cwd);

      expect(outcome, isA<McpServerCommitted>());
      final server =
          (config.applied.single.edits.single as UpsertMcpServer).server;
      expect(server['url'], 'https://mcp2.test/mcp');
      expect(server['call_timeout'], '30s');
      expect(
        (server['headers']! as Map)['Authorization'],
        r'${secret:codelab/mcp/github/authorization}',
      );
      expect(keys.journal, isEmpty);
    });

    test('setEnabled(false): сырой элемент слоя user с enabled: false, '
        'основа записи — снимок этого слоя', () async {
      final snapshot = mcpSnapshot(user: [raw]);

      final outcome = await committer.setEnabled(
        snapshot,
        'github',
        enabled: false,
      );

      expect(outcome, isA<McpServerWritten>());
      final applied = config.applied.single;
      expect(applied.base, snapshot.layers[ConfigLayer.user]);
      expect(applied.edits, [
        UpsertMcpServer({...raw, 'enabled': false}),
      ]);
      expect(keys.journal, isEmpty, reason: 'секреты не трогаются');
    });

    test(
      'setEnabled(true) для сервера projectLocal пишет в projectLocal',
      () async {
        final snapshot = mcpSnapshot(
          user: [httpServer('other')],
          projectLocal: [
            stdioServer(
              's',
              args: ['--a'],
              env: {'K': 'v'},
              extra: {'enabled': false},
            ),
          ],
        );

        await committer.setEnabled(snapshot, 's', enabled: true);

        final applied = config.applied.single;
        expect(applied.base, snapshot.layers[ConfigLayer.projectLocal]);
        expect((applied.edits.single as UpsertMcpServer).server, {
          'name': 's',
          'type': 'stdio',
          'command': '/usr/bin/server',
          'args': ['--a'],
          'env': {'K': 'v'},
          'enabled': true,
        });
      },
    );

    test('сервер слоя 3: переключатель отказывает, запись не идёт', () async {
      final outcome = await committer.setEnabled(
        mcpSnapshot(project: [stdioServer('playwright')]),
        'playwright',
        enabled: false,
      );

      expect(
        (outcome as McpServerRefused).reason,
        McpServerRefusal.notEditable,
      );
      expect(config.applied, isEmpty);
    });

    test('неизвестный сервер: отказ unknownServer', () async {
      final outcome = await committer.setEnabled(
        mcpSnapshot(),
        'nope',
        enabled: false,
      );

      expect(
        (outcome as McpServerRefused).reason,
        McpServerRefusal.unknownServer,
      );
    });

    test(
      'конфликт записи переключателя пробрасывается, автоповтора нет',
      () async {
        config.outcome = const ConfigConflict('/h/config.yaml');

        final outcome = await committer.setEnabled(
          mcpSnapshot(user: [raw]),
          'github',
          enabled: false,
        );

        expect((outcome as McpServerNotWritten).outcome, isA<ConfigConflict>());
        expect(config.applied, hasLength(1));
      },
    );

    test('исключение apply переключателя: тип без текста', () async {
      config.throwOnApply = StateError('boom $leak');

      final outcome = await committer.setEnabled(
        mcpSnapshot(user: [raw]),
        'github',
        enabled: false,
      );

      final failed = outcome as McpServerNotWritten;
      expect(failed.errorType, 'StateError');
      expect('$failed', isNot(contains(leak)));
    });
  });
  group('секреты, на которые элемент больше не ссылается (Q22, ревью 5b)', () {
    // После `ConfigSaved` секреты пространства страницы, исчезнувшие из
    // элемента (сняли «Secret», сменили тип, удалили строку), удаляются по
    // правилу `McpServerRemover` (одна реализация): только пространство
    // `codelab/mcp/<name>/`, только без ссылок в свежем снимке.
    const old = '\${secret:$authorization}';

    ConfigSnapshot layerWith(Map<String, Object?> element) => ConfigSnapshot(
      target: const ConfigTarget.user(),
      path: '/h/config.yaml',
      fingerprint: 'fp',
      values: {
        'mcp': {
          'servers': [element],
        },
      },
    );

    ConfigSnapshot withOld([String reference = old]) =>
        layerWith(httpServer('github', headers: {'Authorization': reference}));

    McpServerDraft plain({
      McpTransportKind kind = McpTransportKind.http,
      Map<String, McpValueDraft>? headers,
    }) => McpServerDraft.fromElement({
      'name': 'github',
      'type': 'http',
      'url': 'https://mcp.test/mcp',
    }).copyWith(kind: kind, headers: headers ?? {}, command: 'srv');

    setUp(() {
      keys = FakeProviderKeys(stored: {authorization, 'shared'});
      rebuild();
      config.snapshotValue = freshMcpSnapshot(user: [httpServer('github')]);
    });

    test('сняли «Secret»: секрет удалён после записи, итог в исходе', () async {
      final outcome = await committer.commit(
        plain(headers: {'Authorization': McpValueDraft.text('x')}),
        withOld(),
        cwd: cwd,
      );

      expect((outcome as McpServerCommitted).secrets, {
        authorization: SecretCleanup.deleted,
      });
      expect(keys.journal.where((j) => j.startsWith('delete')), [
        'delete $authorization',
      ]);
    });

    test('смена типа http → stdio: секреты прежней таблицы удалены', () async {
      final outcome = await committer.commit(
        plain(kind: McpTransportKind.stdio),
        withOld(),
        cwd: cwd,
      );

      expect((outcome as McpServerCommitted).secrets, {
        authorization: SecretCleanup.deleted,
      });
    });

    test('секрет остался в элементе: не трогается и не в итоге', () async {
      final outcome = await committer.commit(
        plain(headers: {'Authorization': McpValueDraft.stored(old)}),
        withOld(),
        cwd: cwd,
      );

      expect((outcome as McpServerCommitted).secrets, isEmpty);
      expect(keys.journal.where((j) => j.startsWith('delete')), isEmpty);
    });

    test('другой элемент ссылается на секрет: stillReferenced', () async {
      config.snapshotValue = freshMcpSnapshot(
        user: [
          httpServer('github'),
          httpServer('other', headers: {'X': old}),
        ],
      );

      final outcome = await committer.commit(
        plain(headers: {'Authorization': McpValueDraft.text('x')}),
        withOld(),
        cwd: cwd,
      );

      expect((outcome as McpServerCommitted).secrets, {
        authorization: SecretCleanup.stillReferenced,
      });
      expect(keys.journal.where((j) => j.startsWith('delete')), isEmpty);
    });

    test('сбой хранилища при удалении: failed', () async {
      keys.deletion = SecretDeletion.failed;

      final outcome = await committer.commit(
        plain(headers: {'Authorization': McpValueDraft.text('x')}),
        withOld(),
        cwd: cwd,
      );

      expect((outcome as McpServerCommitted).secrets, {
        authorization: SecretCleanup.failed,
      });
    });

    test('свежий снимок не получен: секрет не удаляется, failed', () async {
      config.snapshotValue = null;

      final outcome = await committer.commit(
        plain(headers: {'Authorization': McpValueDraft.text('x')}),
        withOld(),
        cwd: cwd,
      );

      expect((outcome as McpServerCommitted).secrets, {
        authorization: SecretCleanup.failed,
      });
      expect(keys.journal.where((j) => j.startsWith('delete')), isEmpty);
    });

    test('свежий снимок с синтаксической ошибкой или без пользовательского '
        'слоя: ссылки слоя не видны, ничего не удаляется (failed)', () async {
      final unreadable = AgentConfigSnapshot.fromLayers(
        cwd: cwd,
        layers: const {},
        loaded: const ConfigLoadResult(
          issues: [
            ConfigIssue(
              kind: ConfigIssueKind.syntax,
              key: '',
              source: '/h/config.yaml',
              message: 'bad yaml',
            ),
          ],
        ),
        secrets: const SecretBackendInfo(id: 'file', writable: true),
      );
      final syntaxOnly = mcpSnapshot(user: [httpServer('github')]);
      final withSyntax = AgentConfigSnapshot(
        cwd: cwd,
        layers: syntaxOnly.layers,
        loaded: unreadable.loaded,
        origins: syntaxOnly.origins,
        secrets: syntaxOnly.secrets,
      );
      for (final fresh in [unreadable, withSyntax]) {
        config.snapshotValue = fresh;

        final outcome = await committer.commit(
          plain(headers: {'Authorization': McpValueDraft.text('x')}),
          withOld(),
          cwd: cwd,
        );

        expect((outcome as McpServerCommitted).secrets, {
          authorization: SecretCleanup.failed,
        });
      }
      expect(keys.journal.where((j) => j.startsWith('delete')), isEmpty);
    });

    test('свежий снимок без слоя project или projectLocal (и без issue): '
        'failed, ничего не удаляется', () async {
      for (final missing in [ConfigLayer.project, ConfigLayer.projectLocal]) {
        final full = mcpSnapshot(
          user: [httpServer('github')],
          project: const [],
          projectLocal: const [],
        );
        config.snapshotValue = AgentConfigSnapshot(
          cwd: cwd,
          layers: {
            for (final e in full.layers.entries)
              if (e.key != missing) e.key: e.value,
          },
          loaded: const ConfigLoadResult(),
          origins: full.origins,
          secrets: full.secrets,
        );

        final outcome = await committer.commit(
          plain(headers: {'Authorization': McpValueDraft.text('x')}),
          withOld(),
          cwd: cwd,
        );

        expect((outcome as McpServerCommitted).secrets, {
          authorization: SecretCleanup.failed,
        }, reason: missing.name);
      }
      expect(keys.journal.where((j) => j.startsWith('delete')), isEmpty);
    });

    test('конфликт и отказ записи: ничего не удаляется', () async {
      for (final failure in <ConfigSaveOutcome>[
        const ConfigConflict('/h/config.yaml'),
        const ConfigRejected([]),
      ]) {
        config.outcome = failure;

        final outcome = await committer.commit(
          plain(headers: {'Authorization': McpValueDraft.text('x')}),
          withOld(),
          cwd: cwd,
        );

        expect(outcome, isA<McpServerNotSaved>());
      }
      expect(keys.journal.where((j) => j.startsWith('delete')), isEmpty);
    });

    test('ручной секрет вне пространства страницы не трогается', () async {
      final outcome = await committer.commit(
        plain(headers: {'Authorization': McpValueDraft.text('x')}),
        withOld('\${secret:shared}'),
        cwd: cwd,
      );

      expect((outcome as McpServerCommitted).secrets, isEmpty);
      expect(keys.journal.where((j) => j.startsWith('delete')), isEmpty);
    });

    test(
      'создание нового сервера: прежнего элемента нет, чистить нечего',
      () async {
        final outcome = await committer.commit(
          plain(headers: {'Authorization': McpValueDraft.text('x')}),
          base,
          cwd: cwd,
        );

        expect((outcome as McpServerCommitted).secrets, isEmpty);
        expect(keys.journal, isEmpty);
      },
    );
  });

  group('отказ хранилища на втором секрете (откат первого)', () {
    test('McpSecretNotStored несёт итог отката: неоткаченный первый секрет '
        'в notRolledBack', () async {
      keys.onWrite = (name, value) {
        if (name != authorization) {
          return const ProviderKeyRefused('store failed');
        }
        keys.storedNames.add(name);
        return const ProviderKeyCreated();
      };
      keys.deletion = SecretDeletion.failed;

      final outcome = await committer.commit(twoSecrets(), base, cwd: cwd);

      final refused = outcome as McpSecretNotStored;
      expect(refused.reason, 'store failed');
      expect(refused.rollback, KeyRollback.failed);
      expect(refused.notRolledBack, [authorization]);
    });

    test('откат удался: deleted, список пуст', () async {
      keys.onWrite = (name, value) {
        if (name != authorization) {
          return const ProviderKeyRefused('store failed');
        }
        keys.storedNames.add(name);
        return const ProviderKeyCreated();
      };

      final outcome = await committer.commit(twoSecrets(), base, cwd: cwd);

      final refused = outcome as McpSecretNotStored;
      expect(refused.rollback, KeyRollback.deleted);
      expect(refused.notRolledBack, isEmpty);
    });
  });

  group('исключение хранилища до записи (HIGH-1, ревью 5b)', () {
    test('stored бросает: исход с типом, текст с маркером не утекает, '
        'конфиг не писался', () async {
      final throwing = _ThrowingStored(keys, StateError('boom $leak'));
      committer = McpServerCommitter(config: config, keys: throwing);

      final outcome = await committer.commit(draft(), base, cwd: cwd);

      final failed = outcome as McpServerNotSaved;
      expect(failed.errorType, 'StateError');
      expect(failed.outcome, isNull);
      expect('$failed', isNot(contains(leak)));
      expect(config.applied, isEmpty);
    });

    test('второй write бросает: первый секрет откачен, в исходе только '
        'реально оставшиеся (ничего), текст исключения не утекает', () async {
      var calls = 0;
      keys.onWrite = (name, value) {
        if (++calls == 2) {
          throw StateError('boom $leak');
        }
        keys.storedNames.add(name);
        return const ProviderKeyCreated();
      };

      final outcome = await committer.commit(twoSecrets(), base, cwd: cwd);

      final failed = outcome as McpServerNotSaved;
      expect(failed.errorType, 'StateError');
      expect(failed.rollback, KeyRollback.deleted);
      expect(failed.notRolledBack, isEmpty);
      expect(keys.storedNames, isEmpty);
      expect(config.applied, isEmpty);
      expect('$failed', isNot(contains(leak)));
    });

    test('откат не удался: в исходе имена секретов, оставшихся в '
        'хранилище', () async {
      var calls = 0;
      keys.onWrite = (name, value) {
        if (++calls == 2) {
          throw StateError('boom');
        }
        keys.storedNames.add(name);
        return const ProviderKeyCreated();
      };
      keys.deletion = SecretDeletion.failed;

      final outcome = await committer.commit(twoSecrets(), base, cwd: cwd);

      final failed = outcome as McpServerNotSaved;
      expect(failed.rollback, KeyRollback.failed);
      expect(failed.notRolledBack, ['codelab/mcp/github/authorization']);
    });

    test('отказ валидатора конфига при неудавшемся откате: notRolledBack '
        'тот же', () async {
      config.outcome = const ConfigRejected([]);
      keys.deletion = SecretDeletion.failed;

      final outcome = await committer.commit(draft(), base, cwd: cwd);

      expect((outcome as McpServerNotSaved).notRolledBack, [authorization]);
    });
  });

  group('occupiedSecrets: тот же вопрос, что у commit (LOW-3, ревью 5b)', () {
    test('занятые имена — теми же stored; replaceSecrets исключены', () async {
      keys = FakeProviderKeys(stored: {authorization});
      rebuild();

      final check = await committer.occupiedSecrets(draft());
      final replaced = await committer.occupiedSecrets(
        draft(),
        replaceSecrets: {authorization},
      );

      expect(check.names, [authorization]);
      expect(check.errorType, isNull);
      expect(replaced.names, isEmpty);
      expect(keys.journal, ['stored $authorization']);
    });

    test('commit при занятом имени возвращает McpSecretAppeared с теми же '
        'именами', () async {
      keys = FakeProviderKeys(stored: {authorization});
      rebuild();

      final check = await committer.occupiedSecrets(draft());
      final outcome = await committer.commit(draft(), base, cwd: cwd);

      expect((outcome as McpSecretAppeared).names, check.names);
    });

    test('stored бросает: тип в ответе, не бросок', () async {
      committer = McpServerCommitter(
        config: config,
        keys: _ThrowingStored(keys, StateError('boom $leak')),
      );

      final check = await committer.occupiedSecrets(draft());

      expect(check.errorType, 'StateError');
      expect(check.names, isEmpty);
      expect('$check', isNot(contains(leak)));
    });
  });
}

/// Порт ключей, у которого `stored` бросает [error] (текст с маркером).
final class _ThrowingStored implements ProviderKeys {
  _ThrowingStored(this._inner, this.error);

  final FakeProviderKeys _inner;
  final Object error;

  @override
  SecretBackendInfo get backend => _inner.backend;

  @override
  String? get readOnlyHint => _inner.readOnlyHint;

  @override
  Future<bool> stored(String name) => throw error;

  @override
  Future<SecretValue?> read(String name) => _inner.read(name);

  @override
  Future<ProviderKeyWrite> write(String name, SecretValue value) =>
      _inner.write(name, value);

  @override
  Future<SecretDeletion> delete(String name) => _inner.delete(name);
}
