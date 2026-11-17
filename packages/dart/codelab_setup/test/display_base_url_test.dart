import 'package:codelab_setup/codelab_setup.dart';
import 'package:test/test.dart';

/// `displayBaseUrl` (client-agent-setup «Состав моста»; design.md change
/// `add-provider-setup-ui`, D6): адрес для экрана без userinfo, query и
/// fragment; одна реализация для мастера, списка и CLI.
void main() {
  test('схема, хост, порт и путь; userinfo, query и fragment убраны', () {
    expect(
      displayBaseUrl('https://u:sk-test-leak-0123456789@gw.test:8443/v1?k=v#f'),
      'https://gw.test:8443/v1',
    );
  });

  test('обычный адрес не меняется', () {
    expect(
      displayBaseUrl('http://localhost:11434/v1'),
      'http://localhost:11434/v1',
    );
  });

  test('null, пустая строка и адрес без хоста — null', () {
    expect(displayBaseUrl(null), isNull);
    expect(displayBaseUrl(''), isNull);
    expect(displayBaseUrl('not a url'), isNull);
  });
}
