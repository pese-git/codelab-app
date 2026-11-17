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

    // Q21: адрес с невидимыми или управляющими символами может выглядеть в
    // диалоге иначе, чем уйдёт в браузер, поэтому не открывается вовсе.
    final dangerous = <String, List<int>>{
      'bidi': [
        0x202A, 0x202B, 0x202C, 0x202D, 0x202E, //
        0x2066, 0x2067, 0x2068, 0x2069, 0x200E, 0x200F,
      ],
      'нулевой ширины': [0x200B, 0x200C, 0x200D, 0xFEFF, 0x2060],
      'управляющий C0': [0x00, 0x07, 0x0A, 0x1F, 0x7F],
      'управляющий C1': [0x80, 0x85, 0x9F],
    };
    for (final MapEntry(key: kind, value: codes) in dangerous.entries) {
      for (final code in codes) {
        final hex = code.toRadixString(16);
        test('http-адрес с символом $kind U+$hex нельзя открыть', () {
          final decision = terminalLinkDecision(
            'https://example.com/a${String.fromCharCode(code)}b',
          );

          expect(decision.canOpen, isFalse);
          // Схема остаётся для события `terminal.link_refused` (D9).
          expect(decision.scheme, 'https');
        });
      }
    }

    test('символ в хосте тоже отклоняется', () {
      expect(
        terminalLinkDecision('https://ex\u202Eample.com/').canOpen,
        isFalse,
      );
    });

    test('обычный юникод без запрещённых символов открывается', () {
      expect(terminalLinkDecision('https://example.com/é/日本').canOpen, isTrue);
    });

    test('address — то, что уйдёт в порт: Uri.parse(uri).toString()', () {
      final decision = terminalLinkDecision('https://example.com/a b/é');

      expect(decision.address, 'https://example.com/a%20b/%C3%A9');
      expect(
        Uri.parse(decision.address),
        Uri.parse('https://example.com/a b/é'),
      );
    });

    test(
      'address отклонённого адреса не содержит сырых невидимых символов',
      () {
        final decision = terminalLinkDecision('https://example.com/\u202Epath');

        expect(decision.address, 'https://example.com/%E2%80%AEpath');
      },
    );

    test('address неразбираемого адреса экранирует запрещённые символы', () {
      final decision = terminalLinkDecision('http://[::1\u202E');

      expect(decision.canOpen, isFalse);
      expect(decision.address, isNot(contains('\u202E')));
      expect(decision.address, contains(r'\u{202e}'));
    });
  });
}
