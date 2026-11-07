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
      final outcome = await committer.commit(draft(), base);

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
      );

      expect(outcome, isA<McpServerCommitted>());
      expect(keys.journal, isEmpty);
      expect(config.applied, hasLength(1));
    });

    test('откат созданного секрета при отказе валидатора', () async {
      config.outcome = const ConfigRejected([]);

      final outcome = await committer.commit(draft(), base);

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

        final outcome = await committer.commit(draft(), base);

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

      final outcome = await committer.commit(draft(), base);

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
      );

      expect((outcome as McpServerCommitted).replacedSecrets, [authorization]);
    });

    test('секрет с таким именем уже есть: McpSecretAppeared, ни write, ни '
        'apply', () async {
      keys = FakeProviderKeys(stored: {authorization});
      rebuild();

      final outcome = await committer.commit(draft(), base);

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

      final outcome = await committer.commit(two, base);

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

      final outcome = await committer.commit(two, base);

      expect((outcome as McpSecretNotStored).reason, 'store failed');
      expect(keys.journal, contains('delete $authorization'));
      expect(config.applied, isEmpty);
    });

    test('исключение apply: тип без текста, откат выполнен, маркер не в '
        'исходе', () async {
      config.throwOnApply = StateError('boom $leak');

      final outcome = await committer.commit(draft(), base);

      final failed = outcome as McpServerNotSaved;
      expect(failed.outcome, isNull);
      expect(failed.errorType, 'StateError');
      expect(failed.rollback, KeyRollback.deleted);
      expect('$failed', isNot(contains(leak)));
    });

    test('откат не удался: rollback=failed', () async {
      config.outcome = const ConfigRejected([]);
      keys.deletion = SecretDeletion.failed;

      final outcome = await committer.commit(draft(), base);

      expect((outcome as McpServerNotSaved).rollback, KeyRollback.failed);
    });

    test(
      'откат бросил исключение: rollback=failed, исход записи сохранён',
      () async {
        config.outcome = const ConfigConflict('/h/config.yaml');
        keys.throwOnDelete = StateError('boom $leak');

        final outcome = await committer.commit(draft(), base);

        final failed = outcome as McpServerNotSaved;
        expect(failed.outcome, isA<ConfigConflict>());
        expect(failed.rollback, KeyRollback.failed);
        expect('$failed', isNot(contains(leak)));
      },
    );

    test('недопустимый черновик не пишется (validate — до записи)', () async {
      final outcome = await committer.commit(draft(name: 'a b'), base);

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

      final outcome = await committer.commit(edited, base);

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
}
