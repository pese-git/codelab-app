import 'package:codelab_setup/codelab_setup.dart';
import 'package:test/test.dart';

import 'support/provider_setup_fakes.dart';

/// Порядок записи провайдера (client-agent-setup «Порядок записи провайдера»;
/// design.md change `add-provider-setup-ui`, D9; SETUP-5): секрет, потом
/// конфиг; откат только созданного секрета; исключение `apply` не уносит
/// текст.
void main() {
  const leak = 'sk-test-leak-0123456789';
  const base = ConfigSnapshot(
    target: ConfigTarget.user(),
    path: '/h/config.yaml',
    fingerprint: 'fp',
    values: {},
  );

  late List<String> journal;
  late FakeProviderKeys keys;
  late FakeConfigStore config;
  late ProviderSetupCommitter committer;

  ProviderSetupPlan plan({
    KeyChoice? key,
    bool replace = false,
    String? secretName = 'codelab/openai',
  }) => ProviderSetupPlan(
    providerId: 'openai',
    kind: 'openai-compatible',
    baseUrl: 'https://api.openai.com/v1',
    key: key ?? StoreSecret(SecretValue(leak)),
    secretName: secretName,
    replaceSecret: replace,
    model: const PlannedModel(id: 'm', contextWindow: 8000),
    makeDefault: true,
    target: const ConfigTarget.user(),
  );

  setUp(() {
    journal = [];
    keys = FakeProviderKeys();
    config = FakeConfigStore(journal);
    committer = ProviderSetupCommitter(config: config, keys: keys);
  });

  test('успех: секрет раньше конфига', () async {
    final outcome = await committer.commit(plan(), base);

    expect(outcome, isA<ProviderCommitted>());
    expect((outcome as ProviderCommitted).keyReplaced, isFalse);
    expect(keys.written, {'codelab/openai': leak});
    expect(config.applied.single.base, base);
    expect(config.applied.single.edits, plan().toEdits());
    expect(keys.journal, ['stored codelab/openai', 'write codelab/openai']);
  });

  test('UseEnvVar и KeepStoredSecret не трогают хранилище', () async {
    await committer.commit(
      plan(key: const UseEnvVar('K'), secretName: null),
      base,
    );
    await committer.commit(plan(key: const NoKey(), secretName: null), base);

    expect(keys.journal, isEmpty);
    expect(config.applied, hasLength(2));
  });

  test('откат созданного секрета', () async {
    config.outcome = const ConfigRejected([]);

    final outcome = await committer.commit(plan(), base);

    final failed = outcome as ProviderConfigNotSaved;
    expect(failed.outcome, isA<ConfigRejected>());
    expect(failed.rollback, KeyRollback.deleted);
    expect(failed.keyReplaced, isFalse);
    expect(keys.journal, contains('delete codelab/openai'));
    expect(keys.written, isEmpty);
  });

  test('ранее существовавший секрет сохраняется (keyReplaced)', () async {
    keys = FakeProviderKeys(stored: {'codelab/openai'});
    committer = ProviderSetupCommitter(config: config, keys: keys);
    config.outcome = const ConfigConflict('/h/config.yaml');

    final outcome = await committer.commit(plan(replace: true), base);

    final failed = outcome as ProviderConfigNotSaved;
    expect(failed.outcome, isA<ConfigConflict>());
    expect(failed.keyReplaced, isTrue);
    expect(failed.rollback, KeyRollback.none);
    expect(keys.journal.where((j) => j.startsWith('delete')), isEmpty);
    // «Replace it» выбран явно: повторной проверки имени нет.
    expect(keys.journal.where((j) => j.startsWith('stored')), isEmpty);
  });

  test(
    'гонка в окне: ProviderKeyReplaced при replaceSecret=false — без отката',
    () async {
      keys.onWrite = (_, _) => const ProviderKeyReplaced();
      config.outcome = const ConfigRejected([]);

      final outcome = await committer.commit(plan(), base);

      final failed = outcome as ProviderConfigNotSaved;
      expect(failed.keyReplaced, isTrue);
      expect(failed.rollback, KeyRollback.none);
      expect(keys.journal.where((j) => j.startsWith('delete')), isEmpty);
    },
  );

  test('хранилище отказало: apply не вызывался', () async {
    keys.onWrite = (_, _) => const ProviderKeyRefused('store failed');

    final outcome = await committer.commit(plan(), base);

    expect((outcome as ProviderKeyNotStored).reason, 'store failed');
    expect(config.applied, isEmpty);
  });

  test('секрет появился до записи: ни write, ни apply', () async {
    keys = FakeProviderKeys(stored: {'codelab/openai'});
    committer = ProviderSetupCommitter(config: config, keys: keys);

    final outcome = await committer.commit(plan(), base);

    expect(outcome, isA<ProviderKeyAppeared>());
    expect(keys.journal.where((j) => j.startsWith('write')), isEmpty);
    expect(config.applied, isEmpty);
  });

  test(
    'исключение записи конфига: откат, errorType, маркер не в исходе',
    () async {
      config.throwOnApply = StateError('boom $leak');

      final outcome = await committer.commit(plan(), base);

      final failed = outcome as ProviderConfigNotSaved;
      expect(failed.outcome, isNull);
      expect(failed.errorType, 'StateError');
      expect(failed.rollback, KeyRollback.deleted);
      expect(failed.toString(), isNot(contains(leak)));
      expect(keys.journal, contains('delete codelab/openai'));
    },
  );

  test('откат не удался: rollback=failed', () async {
    config.outcome = const ConfigRejected([]);
    keys.deletion = SecretDeletion.failed;

    final outcome = await committer.commit(plan(), base);

    expect((outcome as ProviderConfigNotSaved).rollback, KeyRollback.failed);
  });

  test(
    'откат бросил исключение: rollback=failed, исход конфликта сохранён',
    () async {
      config.outcome = const ConfigConflict('/h/config.yaml');
      keys.throwOnDelete = StateError('boom $leak');

      final outcome = await committer.commit(plan(), base);

      final failed = outcome as ProviderConfigNotSaved;
      expect(failed.outcome, isA<ConfigConflict>());
      expect(failed.rollback, KeyRollback.failed);
      expect(failed.toString(), isNot(contains(leak)));
    },
  );
}
