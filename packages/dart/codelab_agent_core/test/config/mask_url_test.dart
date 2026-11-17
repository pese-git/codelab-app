import 'package:codelab_agent_core/codelab_agent_core.dart';
import 'package:test/test.dart';

/// Показ адресов и листьев конфига (design.md changes
/// `add-config-writer-and-reload`, D6, и `add-provider-setup-ui`, D17; R0-2,
/// R4-5): одно правило для `config get`, `provider list` и строк `/settings`.
void main() {
  const leak = 'sk-test-leak-0123456789';

  group('maskUrl', () {
    test('адрес без секретов возвращается байт в байт', () {
      const url = 'https://gw.test:8443/v1/models?api-version=2024-02-01&x=1';

      expect(maskUrl(url), url);
    });

    test('userinfo удаляется', () {
      expect(maskUrl('https://u:p@gw.test/v1'), 'https://gw.test/v1');
    });

    test('%40 и / в пароле не оставляют части секрета', () {
      final shown = maskUrl('https://u:p%40ss/x@gw.test/v1');

      expect(shown, isNot(contains('ss')));
      expect(shown, anyOf('https://gw.test/v1', redactedMask));
    });

    test('user:pass@host без авторитета — fail closed', () {
      expect(maskUrl('user:pass@gw.test'), redactedMask);
    });

    test('значение секретного параметра query и fragment скрыто', () {
      expect(
        maskUrl('https://gw.test/v1?token=$leak&x=1#key=$leak'),
        'https://gw.test/v1?token=$redactedMask&x=1#key=$redactedMask',
      );
    });

    test('секретный matrix-параметр пути скрыт', () {
      final shown = maskUrl('https://gw.test/v1;api_key=$leak/m');

      expect(shown, isNot(contains(leak)));
      expect(shown, contains('api_key=$redactedMask'));
    });

    test('ссылки \${…} остаются как есть', () {
      const url = r'https://${HOST}/v1?token=${TOKEN}';

      expect(maskUrl(url), url);
      expect(maskUrl(r'https://${U}:${P}@h/v1'), r'https://h/v1');
    });

    test('неразбираемый адрес скрыт', () {
      expect(maskUrl('http://[::1'), redactedMask);
    });
  });

  group('displaySafeConfigValue', () {
    test('токен в пути с percent-кодированием скрыт', () {
      // `%2D` — дефис: без декодирования шаблон `sk-` путь не найдёт.
      final shown = displaySafeConfigValue(
        'providers.gw.base_url',
        'https://gw.test/sk%2Dtest%2Dleak%2D0123456789/v1',
      );

      expect(shown, redactedMask);
    });

    test('токен в параметре query под несекретным именем скрыт', () {
      expect(
        displaySafeConfigValue('providers.gw.base_url', 'https://h/v1?x=$leak'),
        redactedMask,
      );
    });

    test('query вида a=1&b=2 ложно не срабатывает', () {
      const url = 'https://gw.test/v1?a=1&b=2';

      expect(displaySafeConfigValue('providers.gw.base_url', url), url);
    });

    test('строка по шаблону секрета скрыта, обычная — нет', () {
      expect(
        displaySafeConfigValue('providers.gw.models.m.name', leak),
        redactedMask,
      );
      expect(displaySafeConfigValue('agent.effort', 'high'), 'high');
    });

    test('api_key_secret проверяется как имя: sk- внутри слова не секрет', () {
      const name = 'codelab/sk-anthropic-production-key';

      expect(displaySafeConfigValue('providers.gw.api_key_secret', name), name);
      expect(
        displaySafeConfigValue('providers.gw.api_key_secret', leak),
        redactedMask,
      );
    });

    test('числа, null и ссылки не меняются', () {
      expect(displaySafeConfigValue('budget.max_steps', 7), 7);
      expect(displaySafeConfigValue('agent.effort', null), isNull);
      expect(
        displaySafeConfigValue('providers.gw.base_url', r'${GW_URL}'),
        r'${GW_URL}',
      );
    });
  });

  group('maskMcpArgs (R4-6)', () {
    test('значение после секретного флага и --флаг=значение скрыты', () {
      expect(
        maskMcpArgs(['--token', 'hunter2', '--verbose', '--api-key=abc', '-y']),
        ['--token', redactedMask, '--verbose', '--api-key=$redactedMask', '-y'],
      );
    });

    test('литерал по шаблону скрыт, ссылки и несекретное — как есть', () {
      expect(maskMcpArgs(['x', leak, r'--token', r'${secret:codelab/t}']), [
        'x',
        redactedMask,
        '--token',
        r'${secret:codelab/t}',
      ]);
    });

    test('вложенный список или карта — opaqueMask', () {
      expect(
        maskMcpArgs([
          ['a'],
          {'k': 'v'},
        ]),
        [opaqueMask, opaqueMask],
      );
    });
  });

  group('isSecretScalarName', () {
    test('счётчики токенов не секретны, а token и keys — секретны', () {
      expect(isSecretScalarName('max_tokens'), isFalse);
      expect(isSecretScalarName('token'), isTrue);
      expect(isSecretScalarName('keys'), isTrue);
    });
  });
}
