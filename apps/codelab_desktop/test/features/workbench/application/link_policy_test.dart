// Политика ссылок и изображений ответа агента (задача 4.1 change
// `add-desktop-markdown`; spec agent-workbench-ui «Ссылки в ответе агента»,
// «Изображения в ответе агента»; design.md D2, D5, D6; DSK-7).
//
// Решение «опасно ли открыть ссылку или загрузить изображение» принимает app
// (кит только рисует), и принимает его чистая функция — её таблица и есть
// спецификация. Красный: `link_policy.dart` ещё нет.

import 'package:codelab_desktop/features/workbench/application/link_policy.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('isOpenableLink', () {
    const openable = [
      'https://example.com',
      'https://example.com/a?token=abc#frag',
      'http://example.com/docs',
      'https://example.com:8443/x',
      'HTTPS://EXAMPLE.COM/x',
      'https://user@example.com/x',
      'mailto:dev@example.com',
      'mailto:dev@example.com?subject=hi',
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
}
