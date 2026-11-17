import 'package:codelab_agent_core/codelab_agent_core.dart';
import 'package:test/test.dart';

/// Ссылки `${secret:<имя>}` в значении конфига (design.md change
/// `add-provider-setup-ui`, D11, Q22): одна функция ядра на мост и
/// подкоманды, вместо своих регулярных выражений. Разбор — тот же, что у
/// загрузки конфига (`expandEnvironment`): `$${secret:x}` — литерал, токен
/// вместо имени (`${ghp_…}`) — не ссылка.
void main() {
  group('secretReferencesIn', () {
    test('имена по порядку без повторов', () {
      expect(
        secretReferencesIn(
          r'Bearer ${secret:codelab/a} ${secret:codelab/b} ${secret:codelab/a}',
        ),
        ['codelab/a', 'codelab/b'],
      );
    });

    test('экранированный литерал, VAR в скобках и токен вместо имени — не '
        'ссылки', () {
      expect(secretReferencesIn(r'$${secret:codelab/a}'), isEmpty);
      expect(secretReferencesIn(r'${PG_URL}'), isEmpty);
      expect(
        secretReferencesIn(r'${ghp_abcdefghijklmnopqrstuvwxyz0123456789}'),
        isEmpty,
      );
      expect(secretReferencesIn('plain'), isEmpty);
    });
  });

  group('soleSecretReference', () {
    test('значение — ровно одна ссылка: возвращает имя', () {
      expect(soleSecretReference(r'${secret:codelab/a}'), 'codelab/a');
    });

    test('текст вокруг ссылки, две ссылки, переменная рядом — null', () {
      expect(soleSecretReference(r'Bearer ${secret:codelab/a}'), isNull);
      expect(
        soleSecretReference(r'${secret:codelab/a}${secret:codelab/b}'),
        isNull,
      );
      expect(soleSecretReference(r'${X}${secret:codelab/a}'), isNull);
      expect(soleSecretReference('plain'), isNull);
    });
  });
}
