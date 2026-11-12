// Решение «можно ли открыть адрес ссылки OSC 8» (задача 2.9 change
// `add-integrated-terminal`; spec `integrated-terminal` «Ссылки в выводе
// терминала»; D3 «Ссылки OSC 8»; Q14).
//
// Тест красный до задачи 2.10: файла
// `lib/features/terminal/application/terminal_link_decision.dart` и функции
// `terminalLinkDecision` ещё нет. Ожидаемый API: чистая функция
// `TerminalLinkDecision terminalLinkDecision(String uri)`; результат несёт
// `canOpen` и `scheme` (схема в нижнем регистре; `null`, если адрес не
// разобрался) — схема попадает в события `terminal.link_*`, адрес — никогда.

import 'package:codelab_desktop/features/terminal/application/terminal_link_decision.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('terminalLinkDecision', () {
    for (final uri in [
      'http://example.com',
      'https://example.com/docs?q=1',
      'HTTP://example.com',
      'HtTpS://Example.com/Path',
    ]) {
      test('$uri можно открыть', () {
        final decision = terminalLinkDecision(uri);

        expect(decision.canOpen, isTrue);
        expect(decision.scheme, anyOf('http', 'https'));
      });
    }

    test('схема в решении приведена к нижнему регистру', () {
      expect(terminalLinkDecision('HTTPS://example.com').scheme, 'https');
    });

    for (final (uri, scheme) in [
      ('file:///etc/passwd', 'file'),
      ('ssh://host/path', 'ssh'),
      ('javascript:alert(1)', 'javascript'),
      ('mailto:user@example.com', 'mailto'),
      ('custom-app://open?x=1', 'custom-app'),
    ]) {
      test('$uri нельзя открыть, схема $scheme', () {
        final decision = terminalLinkDecision(uri);

        expect(decision.canOpen, isFalse);
        expect(decision.scheme, scheme);
      });
    }

    test('пустой адрес и адрес без схемы нельзя открыть', () {
      expect(terminalLinkDecision('').canOpen, isFalse);
      expect(terminalLinkDecision('example.com/docs').canOpen, isFalse);
    });

    test('неразбираемый адрес нельзя открыть, схема неизвестна', () {
      final decision = terminalLinkDecision('http://[::1');

      expect(decision.canOpen, isFalse);
      expect(decision.scheme, isNull);
    });
  });
}
