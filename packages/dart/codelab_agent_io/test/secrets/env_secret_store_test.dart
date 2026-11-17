import 'package:codelab_agent_core/codelab_agent_core.dart';
import 'package:codelab_agent_io/codelab_agent_io.dart';
import 'package:test/test.dart';

/// Бэкенд `env` (agent-secrets «Бэкенды env и file», сценарий «env только для
/// чтения»; design.md change `add-agent-secret-store`, D5).
void main() {
  test('reads CODELAB_SECRET_* and refuses write and delete', () async {
    final store = EnvSecretStore(
      environment: {'CODELAB_SECRET_CODELAB_A': 'v'},
    );

    expect(await store.read('codelab/a'), 'v');
    for (final action in [
      () => store.write('codelab/a', 'x-secret-value'),
      () => store.delete('codelab/a'),
    ]) {
      await expectLater(
        action(),
        throwsA(
          isA<SecretStoreUnavailableException>()
              .having((e) => e.backend, 'backend', 'env')
              .having((e) => e.reason, 'reason', 'env backend is read-only')
              .having(
                (e) => e.toString(),
                'text',
                isNot(contains('x-secret-value')),
              ),
        ),
      );
    }
  });

  test('an unset or empty variable and an invalid name read as null', () async {
    final store = EnvSecretStore(
      environment: {'CODELAB_SECRET_CODELAB_E': '', 'OTHER': 'v'},
    );

    expect(await store.read('codelab/missing'), isNull);
    expect(await store.read('codelab/e'), isNull);
    expect(await store.read('Bad Name'), isNull);
  });

  test('has no secret names and describes itself as read-only env', () async {
    final store = EnvSecretStore(
      environment: {'CODELAB_SECRET_CODELAB_A': 'v'},
    );

    expect(await store.names(), isEmpty);
    expect(store.backend.id, 'env');
    expect(store.backend.writable, isFalse);
    expect(store.backend.unavailableReason, isNull);
  });

  test('carries the reason given by openSecretStore', () {
    final store = EnvSecretStore(
      environment: const {},
      unavailableReason: 'because',
    );

    expect(store.backend.unavailableReason, 'because');
  });
}
