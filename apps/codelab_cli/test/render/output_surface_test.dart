// Выбор поверхности вывода и UTF-8 локали (tasks 5.3; spec codelab-cli
// «Поверхности вывода»; §12.2.1; design.md change `add-codelab-cli`, D6).

import 'package:codelab_cli/codelab_cli.dart';
import 'package:test/test.dart';

void main() {
  group('selectOutputSurface', () {
    test('stdout that is not a terminal is raw even with colors on', () {
      expect(
        selectOutputSurface(
          stdoutIsTerminal: false,
          environment: const {'TERM': 'xterm-256color'},
        ),
        OutputSurface.raw,
      );
    });

    test('raw wins over TERM=dumb and NO_COLOR', () {
      expect(
        selectOutputSurface(
          stdoutIsTerminal: false,
          environment: const {'TERM': 'dumb', 'NO_COLOR': '1'},
          noColor: true,
        ),
        OutputSurface.raw,
      );
    });

    test('TERM=dumb is plain', () {
      expect(
        selectOutputSurface(
          stdoutIsTerminal: true,
          environment: const {'TERM': 'dumb'},
        ),
        OutputSurface.plain,
      );
    });

    test('a non-empty NO_COLOR is plain, an empty one is not', () {
      expect(
        selectOutputSurface(
          stdoutIsTerminal: true,
          environment: const {'NO_COLOR': '1'},
        ),
        OutputSurface.plain,
      );
      expect(
        selectOutputSurface(
          stdoutIsTerminal: true,
          environment: const {'NO_COLOR': ''},
        ),
        OutputSurface.ansi,
      );
    });

    test('--no-color is plain', () {
      expect(
        selectOutputSurface(
          stdoutIsTerminal: true,
          environment: const {},
          noColor: true,
        ),
        OutputSurface.plain,
      );
    });

    test('otherwise a terminal is ansi', () {
      expect(
        selectOutputSurface(
          stdoutIsTerminal: true,
          environment: const {'TERM': 'xterm-256color'},
        ),
        OutputSurface.ansi,
      );
    });
  });

  group('supportsUnicode', () {
    test('the first set of LC_ALL, LC_CTYPE, LANG decides', () {
      expect(supportsUnicode(const {'LANG': 'en_US.UTF-8'}), isTrue);
      expect(supportsUnicode(const {'LC_ALL': 'ru_RU.utf8'}), isTrue);
      expect(
        supportsUnicode(const {'LC_ALL': 'C', 'LANG': 'en_US.UTF-8'}),
        isFalse,
      );
      expect(supportsUnicode(const {'LC_CTYPE': 'UTF-8', 'LANG': 'C'}), isTrue);
    });

    test('without a locale the terminal is treated as ASCII', () {
      expect(supportsUnicode(const {}), isFalse);
      expect(supportsUnicode(const {'LANG': ''}), isFalse);
    });
  });
}
