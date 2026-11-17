// Порт хранилища секретов профилей и SecretText (task 1.3 change
// `add-provider-setup-ui`; spec acp-client-kit «Порт хранилища секретов
// профилей»; design.md, D13).

import 'dart:convert';

import 'package:codelab_client_core/codelab_client_core.dart';
import 'package:test/test.dart';

const _leak = 'sk-test-leak-0123456789';

void main() {
  group('SecretText', () {
    test('never prints the value: toString, json, interpolation, '
        'exceptions', () {
      const secret = SecretText(_leak);
      final draft = const ProfileDraft(
        kind: ProfileKind.webSocket,
        id: 'devbox',
        label: 'Devbox',
        url: 'wss://devbox:7420',
      ).copyWith(token: const NewSecretToken(SecretText(_leak)));

      expect(secret.toString(), '***');
      expect('$secret', isNot(contains(_leak)));
      expect(jsonEncode(secret), '"***"');
      expect(jsonEncode({'token': secret}), isNot(contains(_leak)));
      expect(draft.toString(), isNot(contains(_leak)));
      expect('${draft.token}', isNot(contains(_leak)));
      expect(
        StateError('failed with $secret').toString(),
        isNot(contains(_leak)),
      );
    });

    test('reveal returns the value; equality is by value', () {
      expect(const SecretText('a').reveal(), 'a');
      expect(const SecretText('a'), const SecretText('a'));
      expect(const SecretText('a'), isNot(const SecretText('b')));
      expect(const SecretText('').isEmpty, isTrue);
    });
  });

  group('results carry no value', () {
    test('store and delete outcomes are closed hierarchies', () {
      const writes = <ProfileSecretWrite>[
        Stored(),
        Exists(),
        ReadOnly('read-only backend'),
        Failed('boom'),
      ];
      const deletes = <ProfileSecretDelete>[
        Deleted(),
        NotSet(),
        ReadOnly('read-only backend'),
        Failed('boom'),
      ];

      for (final write in writes) {
        // Исчерпывающий switch: новый исход без обработки не скомпилируется.
        final text = switch (write) {
          Stored() => 'stored',
          Exists() => 'exists',
          ReadOnly(:final reason) => 'ro $reason',
          Failed(:final message) => 'failed $message',
        };
        expect(text, isNot(contains(_leak)));
      }
      for (final delete in deletes) {
        final text = switch (delete) {
          Deleted() => 'deleted',
          NotSet() => 'not set',
          ReadOnly(:final reason) => 'ro $reason',
          Failed(:final message) => 'failed $message',
        };
        expect(text, isNot(contains(_leak)));
      }
    });

    test('the backend description keeps id, writable and the reason', () {
      const backend = ProfileSecretBackend(
        id: 'env',
        writable: false,
        unavailableReason: 'read-only',
      );

      expect(backend.id, 'env');
      expect(backend.writable, isFalse);
      expect(backend.unavailableReason, 'read-only');
    });
  });
}
