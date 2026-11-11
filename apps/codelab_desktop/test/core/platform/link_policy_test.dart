// Политика ссылок и изображений ответа агента (задача 4.1 change
// `add-desktop-markdown`; spec agent-workbench-ui «Ссылки в ответе агента»,
// «Изображения в ответе агента»; design.md D2, D5, D6; DSK-7).
//
// Решение «опасно ли открыть ссылку или загрузить изображение» принимает app
// (кит только рисует), и принимает его чистая функция — её таблица и есть
// спецификация. Красный: `link_policy.dart` ещё нет.

import 'package:codelab_desktop/core/platform/link_policy.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('isOpenableLink', () {
    const openable = [
      'https://example.com',
      'https://example.com/a?token=abc#frag',
      'http://example.com/docs',
      'https://example.com:8443/x',
      'HTTPS://EXAMPLE.COM/x',
      'mailto:dev@example.com',
      'mailto:dev@example.com?subject=hi',
      'mailto:a@b.com,c@d.org',
      // Параметры mailto политику не меняют: лишнее отбрасывает
      // `externalLinkTarget` (ревью итерации 4).
      'mailto:a@b.com?cc=x&bcc=y&body=z&attach=/etc/passwd&subject=hi',
      // Числовой IPv4 и локальная сеть — принятый риск R4 (решение
      // пользователя 2026-11-11): политику не меняем.
      'https://127.0.0.1/x',
      'http://192.168.0.1/admin',
      // Обратная косая: Dart читает хост `good.com`, путь `/@evil.com/` —
      // открывается ровно то, что разобрано, подсказка покажет полный адрес.
      r'https://good.com\@evil.com/',
    ];
    const notOpenable = [
      'file:///etc/passwd',
      'javascript:alert(1)',
      'data:text/html,hi',
      'vscode://open',
      'xmpp:a@b',
      'ftp://example.com/x',
      'tel:+123',
      'ssh://host',
      'about:blank',
      // protocol-relative, относительные пути и пустые значения
      '//evil.example/a',
      '/a/b',
      'a/b',
      'docs/readme.md',
      '',
      // схема без хоста или адреса
      'https://',
      'https:///path',
      'http:/x',
      'mailto:',
      'mailto:?subject=x',
      // Адресат со спрятанными параметрами (решение ревью итерации 4): после
      // раскодирования это не простой адрес `local@domain`.
      'mailto:a@b%3Fbcc=evil@x.com',
      'mailto:a@b%0D%0Abcc:x@y',
      'mailto:%3Fattach=/etc/passwd@x',
      'mailto:a@b.com,%3Fbcc=x@y',
      'mailto:a b@c.com',
      // Управляющие и bidi-символы после раскодирования (набор
      // `escapeForDisplay`): адрес выглядел бы иначе, чем он есть.
      'mailto:a@b%00c',
      'mailto:a@b%07',
      'mailto:a@b%E2%80%AE.com',
      'mailto:a@b%EF%BB%BF.com',
      'mailto:a@b%E2%80%8B.com',
      'mailto:%ZZ@x.com',
      // userinfo: `good.com` в начале адреса — не хост, а приманка
      // (решение пользователя 2026-11-11).
      'https://good.com@evil.com',
      'https://a:b@evil.com',
      'http://user@example.com/x',
      // Раньше `https://user@example.com/x` считался открываемым; после
      // решения пользователя 2026-11-11 userinfo отклоняется целиком.
      'https://user@example.com/x',
    ];

    for (final value in openable) {
      test('opens "$value"', () {
        expect(isOpenableLink(Uri.parse(value)), isTrue);
      });
    }
    for (final value in notOpenable) {
      test('does not open "$value"', () {
        expect(isOpenableLink(Uri.parse(value)), isFalse);
      });
    }
  });

  group('isLoadableImage', () {
    const loadable = [
      'https://x.example/y.png',
      'https://x.example:8443/y.png?v=1',
      'HTTPS://X.EXAMPLE/y.png',
    ];
    const notLoadable = [
      'http://x.example/y.png',
      'data:image/png;base64,AAAA',
      'file:///tmp/y.png',
      'mailto:a@b.c',
      '//x.example/y.png',
      '/y.png',
      'y.png',
      '',
      'https://',
      'https:///y.png',
      'javascript:alert(1)',
      'https://good.com@evil.com/y.png',
      'https://a:b@evil.com/y.png',
    ];

    for (final value in loadable) {
      test('loads "$value" after a click', () {
        expect(isLoadableImage(Uri.parse(value)), isTrue);
      });
    }
    for (final value in notLoadable) {
      test('never loads "$value"', () {
        expect(isLoadableImage(Uri.parse(value)), isFalse);
      });
    }
  });

  test('the backslash trick resolves to the host Dart really parsed', () {
    final uri = Uri.parse(r'https://good.com\@evil.com/');
    expect(uri.host, 'good.com');
    expect(uri.userInfo, isEmpty);
    expect(isOpenableLink(uri), isTrue);
  });

  group('externalLinkTarget', () {
    test('mailto keeps recipients and subject, drops the other parameters', () {
      final target = externalLinkTarget(
        Uri.parse(
          'mailto:a@b.com?cc=x&bcc=y&body=z&attach=/etc/passwd&subject=hi',
        ),
      );
      expect(target.toString(), 'mailto:a@b.com?subject=hi');
    });

    test('mailto without a subject has no query at all', () {
      expect(
        externalLinkTarget(Uri.parse('mailto:a@b.com?cc=x')).toString(),
        'mailto:a@b.com',
      );
    });

    test('a subject with spaces stays a valid mailto', () {
      expect(
        externalLinkTarget(
          Uri.parse('mailto:a@b.com?subject=hello%20world&body=x'),
        ).toString(),
        'mailto:a@b.com?subject=hello%20world',
      );
    });

    test('a broken percent escape in the subject drops the subject', () {
      expect(
        externalLinkTarget(Uri.parse('mailto:a@b?subject=%E0%A4')).toString(),
        'mailto:a@b',
      );
    });

    test('several recipients stay', () {
      expect(
        externalLinkTarget(
          Uri.parse('mailto:a@b.com,c@d.org?bcc=x'),
        ).toString(),
        'mailto:a@b.com,c@d.org',
      );
    });

    test('http and https are unchanged', () {
      final uri = Uri.parse('https://example.com/a?token=abc#frag');
      expect(externalLinkTarget(uri), uri);
    });
  });
}
