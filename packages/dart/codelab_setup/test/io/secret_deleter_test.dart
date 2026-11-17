import 'dart:io';

import 'package:codelab_agent_core/testing.dart';
import 'package:codelab_setup/codelab_setup.dart';
import 'package:codelab_setup/io.dart';
import 'package:test/test.dart';

/// `secretDeleterOf`: удаление секрета провайдера через `ClientSecretAccess`
/// (SETUP-24; design.md change `add-provider-setup-ui`, D10). Временный
/// `CODELAB_HOME`, фиктивные значения.
void main() {
  late Directory root;
  late String home;

  setUp(() {
    root = Directory.systemTemp.createTempSync('secret_deleter_test');
    home = '${root.path}/home';
    Directory(home).createSync();
    Process.runSync('/bin/chmod', ['700', home]);
  });

  tearDown(() => root.deleteSync(recursive: true));

  Future<ClientSecretAccess> open({bool file = true}) {
    if (file) {
      File(
        '$home/config.yaml',
      ).writeAsStringSync('secrets:\n  backend: file\n');
    }
    return ClientSecretAccess.open(
      codelabHome: home,
      environment: const {},
      logger: RecordingLogger(),
    );
  }

  test('удалён, затем «уже нет»', () async {
    final access = await open();
    await access.admin.store('codelab/p', 'sk-test-leak-0123456789');
    final delete = secretDeleterOf(access);

    final first = await delete('codelab/p');
    final second = await delete('codelab/p');

    expect(first, SecretDeletion.deleted);
    expect(second, SecretDeletion.notSet);
    expect(await access.isSet('codelab/p'), isFalse);
  });

  test('бэкенд только для чтения — failed', () async {
    final access = await open(file: false);

    expect(await secretDeleterOf(access)('codelab/p'), SecretDeletion.failed);
  });

  test(
    'ProviderRemover удаляет секрет настоящим хранилищем после apply',
    () async {
      final access = await open();
      await access.admin.store('codelab/b', 'sk-test-leak-0123456789');
      final journal = <String>[];
      final remover = ProviderRemover(
        config: _SavingStore(journal),
        deleteSecret: (name) async {
          journal.add('delete');
          return secretDeleterOf(access)(name);
        },
      );
      final snapshot = AgentConfigSnapshot.fromLayers(
        cwd: '/w',
        layers: {
          ConfigLayer.user: ConfigSnapshot(
            target: const ConfigTarget.user(),
            path: '$home/config.yaml',
            fingerprint: 'f',
            values: {
              'providers': {
                'a': {'kind': 'openai-compatible'},
                'b': {
                  'kind': 'openai-compatible',
                  'api_key_secret': 'codelab/b',
                },
              },
            },
          ),
        },
        loaded: const ConfigLoadResult(),
        secrets: access.backend,
      );

      final outcome = await remover.remove(
        snapshot,
        providerId: 'b',
        deleteStoredKey: true,
      );

      expect((outcome as ProviderRemoved).secret, SecretCleanup.deleted);
      expect(journal, ['apply', 'delete']);
      expect(await access.isSet('codelab/b'), isFalse);
    },
  );
}

final class _SavingStore implements AgentConfigStore {
  _SavingStore(this._journal);

  final List<String> _journal;

  @override
  Future<ConfigSaveOutcome> apply(
    ConfigSnapshot base,
    List<ConfigEdit> edits,
  ) async {
    _journal.add('apply');
    return const ConfigSaved(
      fingerprint: 'n',
      warnings: [],
      restartRequiredKeys: [],
    );
  }

  @override
  Future<AgentConfigSnapshot> snapshot({required String cwd}) async =>
      // Свежий снимок после записи: провайдера и ссылок на секрет в нём нет.
      AgentConfigSnapshot(
        cwd: cwd,
        layers: const {},
        loaded: const ConfigLoadResult(),
        origins: const {},
        secrets: const SecretBackendInfo(id: 'file', writable: true),
      );
}
