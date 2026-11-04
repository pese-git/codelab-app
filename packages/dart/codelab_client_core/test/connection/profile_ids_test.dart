// Правила id профиля и записи с зарезервированным id (tasks 2.13 change
// `add-app-settings-shell`; spec acp-client-kit «Записи профилей с
// зарезервированным id»; design.md, D11, D21).

import 'package:codelab_client_core/codelab_client_core.dart';
import 'package:test/test.dart';

StdioProfile _stdio(String id) =>
    StdioProfile(id: id, label: id, command: '/opt/$id');

void main() {
  group('isValidProfileId', () {
    test('accepts lowercase ids up to 64 characters', () {
      for (final id in ['dev', 'a', '0x', 'my-agent_1.test', 'a' * 64]) {
        expect(isValidProfileId(id), isTrue, reason: id);
      }
    });

    test('rejects capitals, bad first characters, separators and length', () {
      for (final id in [
        '',
        'Dev',
        '-dev',
        '.dev',
        'bad id',
        'a:b',
        'a/b',
        'a' * 65,
      ]) {
        expect(isValidProfileId(id), isFalse, reason: id);
      }
    });
  });

  group('reserved ids', () {
    test('embedded and default are the names of the built-in agent', () {
      expect(reservedProfileIds, {'embedded', 'default'});
      expect(isReservedProfileId('embedded'), isTrue);
      expect(isReservedProfileId('default'), isTrue);
      expect(isReservedProfileId('dev'), isFalse);
    });
  });

  group('usableStoredProfiles', () {
    test('separates the old default entry and keeps the file order', () {
      final result = usableStoredProfiles([
        _stdio('default'),
        _stdio('dev'),
        _stdio('Old'),
      ]);

      expect(result.usable.map((p) => p.id), ['dev', 'Old']);
      expect(result.ignoredDefault, isTrue);
    });

    test('without default nothing is ignored', () {
      final result = usableStoredProfiles([_stdio('dev')]);

      expect(result.usable.map((p) => p.id), ['dev']);
      expect(result.ignoredDefault, isFalse);
    });

    test('an empty list gives an empty result', () {
      final result = usableStoredProfiles(const []);

      expect(result.usable, isEmpty);
      expect(result.ignoredDefault, isFalse);
    });
  });
}
