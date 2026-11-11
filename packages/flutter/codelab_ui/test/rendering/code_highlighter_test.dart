// Подсветка кода: пороги, кеш, язык, сбой и палитра (итерация 3, задача 3.1
// change `add-desktop-markdown`; design.md D4; §12.3 A4; DSK-5, DSK-19;
// spec agent-workbench-ui «Блок кода в ответе агента»).
//
// Красная фаза: тесты обращаются к ещё не существующим `CodeLabCodeHighlighter`,
// `CodeLabCodeToken`, `CodeLabTokenClass`, `CodeLabCodeTheme` из
// `package:codelab_ui/codelab_ui.dart`.

import 'dart:ui' show Color;

import 'package:codelab_ui/codelab_ui.dart';
import 'package:fluent_ui/fluent_ui.dart';
import 'package:flutter_test/flutter_test.dart';

final _lightTheme = FluentThemeData(brightness: Brightness.light);
final _darkTheme = FluentThemeData(brightness: Brightness.dark);

/// Код из [lines] строк по одному символу.
String _lines(int lines) => List.filled(lines, 'a').join('\n');

/// Токенайзер-заглушка со счётчиком вызовов.
class _CountingTokenizer {
  final calls = <String>[];

  List<CodeLabCodeToken> call(String language, String code) {
    calls.add('$language:$code');
    return [CodeLabCodeToken(0, code.length, CodeLabTokenClass.keyword)];
  }
}

double _contrast(Color a, Color b) {
  final l1 = a.computeLuminance();
  final l2 = b.computeLuminance();
  final hi = l1 > l2 ? l1 : l2;
  final lo = l1 > l2 ? l2 : l1;
  return (hi + 0.05) / (lo + 0.05);
}

void main() {
  setUp(CodeLabMarkdownStats.reset);

  group('thresholds (A4, DSK-5)', () {
    final highlighter = CodeLabCodeHighlighter();

    test('up to 300 lines and 16 KiB is tokenized synchronously', () {
      expect(
        highlighter.modeFor('dart', _lines(300)),
        CodeLabHighlightMode.sync,
      );
      expect(
        highlighter.modeFor('dart', 'a' * (16 * 1024)),
        CodeLabHighlightMode.sync,
      );
    });

    test('over 300 lines or 16 KiB goes to the background', () {
      expect(
        highlighter.modeFor('dart', _lines(301)),
        CodeLabHighlightMode.background,
      );
      expect(
        highlighter.modeFor('dart', 'a' * (16 * 1024 + 1)),
        CodeLabHighlightMode.background,
      );
    });

    test('up to 5000 lines and 256 KiB still goes to the background', () {
      expect(
        highlighter.modeFor('dart', _lines(5000)),
        CodeLabHighlightMode.background,
      );
      expect(
        highlighter.modeFor('dart', 'a' * (256 * 1024)),
        CodeLabHighlightMode.background,
      );
    });

    test('over 5000 lines or 256 KiB is not highlighted at all', () {
      expect(
        highlighter.modeFor('dart', _lines(5001)),
        CodeLabHighlightMode.none,
      );
      expect(
        highlighter.modeFor('dart', 'a' * (256 * 1024 + 1)),
        CodeLabHighlightMode.none,
      );
    });
  });

  group('language (no auto-detection)', () {
    test('known languages and aliases are supported, case-insensitively', () {
      final highlighter = CodeLabCodeHighlighter();
      for (final name in ['dart', 'Dart', 'sh', 'js', 'yml', 'python']) {
        expect(highlighter.supports(name), isTrue, reason: name);
      }
    });

    test('unknown, empty and text languages give no tokens and no engine '
        'call', () {
      final tokenizer = _CountingTokenizer();
      final highlighter = CodeLabCodeHighlighter(tokenizer: tokenizer.call);
      const code = 'final a = 1; // looks like Dart';
      for (final name in ['foolang', '', 'text', 'plaintext']) {
        expect(highlighter.supports(name), isFalse, reason: name);
        expect(highlighter.modeFor(name, code), CodeLabHighlightMode.none);
        expect(highlighter.highlightSync(name, code), isEmpty, reason: name);
      }
      expect(tokenizer.calls, isEmpty);
      expect(CodeLabMarkdownStats.highlightRuns, 0);
    });
  });

  group('real engine (val_highlight)', () {
    const code = "// note\nfinal a = 'x' + 1;\nclass A {}\n";

    test('classifies Dart tokens by offsets into the code', () {
      final tokens = CodeLabCodeHighlighter().highlightSync('dart', code);

      CodeLabTokenClass? classAt(int offset) {
        for (final t in tokens) {
          if (offset >= t.start && offset < t.end) return t.tokenClass;
        }
        return null;
      }

      expect(classAt(code.indexOf('note')), CodeLabTokenClass.comment);
      expect(classAt(code.indexOf('final')), CodeLabTokenClass.keyword);
      expect(classAt(code.indexOf("'x'")), CodeLabTokenClass.string);
      expect(classAt(code.indexOf('1;')), CodeLabTokenClass.number);
      // Токены упорядочены, не пересекаются и лежат внутри кода.
      var last = 0;
      for (final t in tokens) {
        expect(t.start, greaterThanOrEqualTo(last));
        expect(t.end, greaterThan(t.start));
        expect(t.end, lessThanOrEqualTo(code.length));
        last = t.end;
      }
    });

    test(
      'the background run returns the same tokens as the sync run',
      () async {
        final highlighter = CodeLabCodeHighlighter();
        final sync = highlighter.highlightSync('dart', code);
        final background = await CodeLabCodeHighlighter().highlightInBackground(
          'dart',
          code,
        );
        expect(
          background.map((t) => (t.start, t.end, t.tokenClass)).toList(),
          sync.map((t) => (t.start, t.end, t.tokenClass)).toList(),
        );
      },
    );

    test('counters: sync runs are counted separately', () {
      CodeLabCodeHighlighter().highlightSync('dart', code);
      expect(CodeLabMarkdownStats.highlightRuns, 1);
      expect(CodeLabMarkdownStats.highlightSyncRuns, 1);
    });
  });

  group('cache (LRU 256 by language and code)', () {
    test('a repeated request does not tokenize again', () {
      final tokenizer = _CountingTokenizer();
      final highlighter = CodeLabCodeHighlighter(tokenizer: tokenizer.call);
      highlighter.highlightSync('dart', 'final a = 1;');
      highlighter.highlightSync('dart', 'final a = 1;');
      expect(tokenizer.calls, hasLength(1));
      expect(highlighter.cached('dart', 'final a = 1;'), isNotNull);
      // Другой язык — другой ключ.
      highlighter.highlightSync('python', 'final a = 1;');
      expect(tokenizer.calls, hasLength(2));
    });

    test('the 257th distinct block evicts the least recently used one', () {
      final tokenizer = _CountingTokenizer();
      final highlighter = CodeLabCodeHighlighter(tokenizer: tokenizer.call);
      for (var i = 0; i < 256; i++) {
        highlighter.highlightSync('dart', 'var v$i;');
      }
      expect(tokenizer.calls, hasLength(256));
      // Обращение к первому делает его «свежим»; вытесняется второй.
      highlighter.highlightSync('dart', 'var v0;');
      expect(tokenizer.calls, hasLength(256));
      highlighter.highlightSync('dart', 'var v256;');
      expect(tokenizer.calls, hasLength(257));
      highlighter.highlightSync('dart', 'var v0;');
      expect(tokenizer.calls, hasLength(257), reason: 'v0 stays cached');
      highlighter.highlightSync('dart', 'var v1;');
      expect(tokenizer.calls, hasLength(258), reason: 'v1 was evicted');
    });
  });

  group('engine failure', () {
    test('gives no tokens and reports without the code text', () {
      final reports = <FlutterErrorDetails>[];
      final previous = FlutterError.onError;
      FlutterError.onError = reports.add;
      addTearDown(() => FlutterError.onError = previous);

      final highlighter = CodeLabCodeHighlighter(
        tokenizer: (language, code) => throw StateError('engine failed'),
      );
      const secret = 'final topSecretValue = 42;';
      expect(highlighter.highlightSync('dart', secret), isEmpty);

      expect(reports, hasLength(1));
      final text = reports.single.toDiagnosticsNode().toStringDeep();
      expect(text, isNot(contains('topSecretValue')));
      expect(reports.single.exceptionAsString(), isNot(contains(secret)));
      // Сбой не кешируется как успех: повтор снова пробует движок.
      expect(highlighter.cached('dart', secret), isNull);
    });
  });

  group('palette (DSK-19)', () {
    test('every token class has contrast of at least 4.5:1 on the block '
        'background in both themes', () {
      for (final theme in [_lightTheme, _darkTheme]) {
        final palette = CodeLabCodeTheme.of(theme);
        for (final tokenClass in CodeLabTokenClass.values) {
          expect(
            _contrast(palette.colorOf(tokenClass), palette.background),
            greaterThanOrEqualTo(4.5),
            reason: '${tokenClass.name} in ${theme.brightness.name}',
          );
        }
        expect(
          _contrast(palette.plain, palette.background),
          greaterThanOrEqualTo(4.5),
        );
      }
    });

    test('the dark palette differs from the light one', () {
      final light = CodeLabCodeTheme.of(_lightTheme);
      final dark = CodeLabCodeTheme.of(_darkTheme);
      expect(dark.background, isNot(light.background));
      expect(dark.background.computeLuminance(), lessThan(0.2));
      expect(light.background.computeLuminance(), greaterThan(0.5));
      for (final tokenClass in CodeLabTokenClass.values) {
        expect(
          dark.colorOf(tokenClass),
          isNot(light.colorOf(tokenClass)),
          reason: tokenClass.name,
        );
      }
    });

    test('a palette registered in FluentThemeData.extensions wins', () {
      final custom = CodeLabCodeTheme.of(
        _lightTheme,
      ).copyWith(background: const Color(0xFFFFFFFF));
      final theme = FluentThemeData(
        brightness: Brightness.light,
        extensions: [custom],
      );
      expect(CodeLabCodeTheme.of(theme).background, const Color(0xFFFFFFFF));
    });
  });
}
