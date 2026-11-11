// Подсветка кода: пороги, кеш, язык, сбой и палитра (итерация 3, задача 3.1
// change `add-desktop-markdown`; design.md D4; §12.3 A4; DSK-5, DSK-19;
// spec agent-workbench-ui «Блок кода в ответе агента»).
//
// Красная фаза: тесты обращаются к ещё не существующим `CodeLabCodeHighlighter`,
// `CodeLabCodeToken`, `CodeLabTokenClass`, `CodeLabCodeTheme` из
// `package:codelab_ui/codelab_ui.dart`.

import 'dart:async';

import 'package:codelab_ui/codelab_ui.dart';
import 'package:codelab_ui/src/rendering/codelab_code_highlighter.dart'
    show snapToCodePoint, tokenizeWithEngine;
import 'package:fluent_ui/fluent_ui.dart';
import 'package:flutter_test/flutter_test.dart';

final _lightTheme = FluentThemeData(brightness: Brightness.light);
final _darkTheme = FluentThemeData(brightness: Brightness.dark);

/// Код из [lines] строк по одному символу.
String _lines(int lines) => List.filled(lines, 'a').join('\n');

/// Код ровно из [chars] символов со строками по [lineLength] (порог по
/// длине строки: A4 + ревью итерации 3, квадратичность `RegExp` движка).
String _chars(int chars, {int lineLength = 100}) {
  final b = StringBuffer();
  for (var i = 0; i < chars; i++) {
    b.write((i + 1) % lineLength == 0 && i != chars - 1 ? '\n' : 'a');
  }
  return b.toString();
}

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
        highlighter.modeFor('dart', _chars(16 * 1024)),
        CodeLabHighlightMode.sync,
      );
    });

    test('over 300 lines or 16 KiB goes to the background', () {
      expect(
        highlighter.modeFor('dart', _lines(301)),
        CodeLabHighlightMode.background,
      );
      expect(
        highlighter.modeFor('dart', _chars(16 * 1024 + 1)),
        CodeLabHighlightMode.background,
      );
    });

    test('up to 5000 lines and 256 KiB still goes to the background', () {
      expect(
        highlighter.modeFor('dart', _lines(5000)),
        CodeLabHighlightMode.background,
      );
      expect(
        highlighter.modeFor('dart', _chars(256 * 1024, lineLength: 1000)),
        CodeLabHighlightMode.background,
      );
    });

    test('over 5000 lines or 256 KiB is not highlighted at all', () {
      expect(
        highlighter.modeFor('dart', _lines(5001)),
        CodeLabHighlightMode.none,
      );
      expect(
        highlighter.modeFor('dart', _chars(256 * 1024 + 1, lineLength: 1000)),
        CodeLabHighlightMode.none,
      );
    });
  });

  group('line length (quadratic regexps of the engine)', () {
    final highlighter = CodeLabCodeHighlighter();

    test('synchronous only while every line is at most 150 chars', () {
      expect(highlighter.modeFor('dart', 'a' * 150), CodeLabHighlightMode.sync);
      expect(
        highlighter.modeFor('dart', 'a' * 151),
        CodeLabHighlightMode.background,
      );
    });

    test('background only while every line is at most 1000 chars', () {
      expect(
        highlighter.modeFor('dart', 'a' * 1000),
        CodeLabHighlightMode.background,
      );
      expect(
        highlighter.modeFor('dart', 'a' * 1001),
        CodeLabHighlightMode.none,
      );
      // Длинная строка среди коротких тоже отключает подсветку.
      expect(
        highlighter.modeFor('dart', 'a\n${'a' * 1001}\nb'),
        CodeLabHighlightMode.none,
      );
    });

    test('a 16000-char swift line is not tokenized at all', () {
      final tokenizer = _CountingTokenizer();
      final guarded = CodeLabCodeHighlighter(tokenizer: tokenizer.call);
      final code = '#' * 16000;
      final watch = Stopwatch()..start();
      expect(guarded.modeFor('swift', code), CodeLabHighlightMode.none);
      expect(watch.elapsedMilliseconds, lessThan(100));
      expect(tokenizer.calls, isEmpty);
    });
  });

  group('background runs', () {
    test('two requests for the same code share one run', () async {
      final result = Completer<List<CodeLabCodeToken>>();
      var calls = 0;
      final highlighter = CodeLabCodeHighlighter(
        background: (language, code) {
          calls++;
          return result.future;
        },
      );
      final code = _lines(400);
      final first = highlighter.highlightInBackground('dart', code);
      final second = highlighter.highlightInBackground('dart', code);
      expect(calls, 1);
      expect(CodeLabMarkdownStats.highlightRuns, 1);
      result.complete([
        const CodeLabCodeToken(0, 1, CodeLabTokenClass.keyword),
      ]);
      expect(await first, hasLength(1));
      expect(await second, hasLength(1));
      // После результата — кеш, новый запуск не нужен.
      await highlighter.highlightInBackground('dart', code);
      expect(calls, 1);
    });

    testWidgets('a run that never ends is dropped after the timeout', (
      tester,
    ) async {
      // Время тестовое (`tester.pump`): ждать реальные секунды не нужно.
      final reports = <FlutterErrorDetails>[];
      final previous = FlutterError.onError;
      FlutterError.onError = reports.add;
      addTearDown(() => FlutterError.onError = previous);
      var calls = 0;
      final highlighter = CodeLabCodeHighlighter(
        background: (language, code) {
          calls++;
          return Completer<List<CodeLabCodeToken>>().future;
        },
      );
      final code = '${_lines(400)}\nsecret_code_line';
      List<CodeLabCodeToken>? result;
      unawaited(
        highlighter
            .highlightInBackground('dart', code)
            .then((tokens) => result = tokens),
      );
      await tester.pump(
        highlighter.backgroundTimeout - const Duration(seconds: 1),
      );
      expect(result, isNull, reason: 'still waiting');
      await tester.pump(const Duration(seconds: 2));
      expect(result, isEmpty);

      expect(reports, hasLength(1));
      final text = reports.single.toDiagnosticsNode().toStringDeep();
      expect(text, contains('dart'));
      expect(text, contains('Timeout'));
      expect(text, isNot(contains('secret_code_line')));

      // Решение оркестратора: тот же код даст тот же исход, поэтому таймаут
      // запоминается как «без подсветки»: повтор не запускает фон и не шлёт
      // новый отчёт (повторный монтаж и прокрутка не плодят isolate).
      List<CodeLabCodeToken>? again;
      unawaited(
        highlighter
            .highlightInBackground('dart', code)
            .then((tokens) => again = tokens),
      );
      await tester.pump();
      expect(again, isEmpty);
      expect(calls, 1);
      expect(reports, hasLength(1));
      expect(highlighter.cached('dart', code), isEmpty);
    });
  });

  group('cache budget', () {
    test('old entries are evicted when the total size exceeds the budget', () {
      final tokenizer = _CountingTokenizer();
      final highlighter = CodeLabCodeHighlighter(tokenizer: tokenizer.call);
      // 40 блоков по 250 000 символов — 10 млн единиц при бюджете 8 Mi.
      String block(int i) => '${i.toString().padLeft(4, '0')}${'a' * 249996}';
      for (var i = 0; i < 40; i++) {
        highlighter.highlightSync('dart', block(i));
      }
      expect(tokenizer.calls, hasLength(40));
      expect(highlighter.cached('dart', block(39)), isNotNull);
      expect(highlighter.cached('dart', block(0)), isNull);
    });
  });

  group('cache budget by tokens', () {
    test('a token weighs 20 units, so many tokens evict old entries', () {
      final highlighter = CodeLabCodeHighlighter(
        tokenizer: (language, code) => [
          for (var i = 0; i < 10000; i++)
            CodeLabCodeToken(0, 1, CodeLabTokenClass.keyword),
        ],
      );
      // Код короткий, но по 10 000 токенов (200 000 единиц) на запись: при
      // бюджете 8 Mi помещается около 40 записей; с весом токена 1 вытеснения
      // не было бы вовсе.
      for (var i = 0; i < 60; i++) {
        highlighter.highlightSync('dart', 'var v$i;');
      }
      expect(highlighter.cached('dart', 'var v59;'), isNotNull);
      expect(highlighter.cached('dart', 'var v0;'), isNull);
    });
  });

  group('surrogate pairs', () {
    void expectWholePairs(String language, String code) {
      final tokens = CodeLabCodeHighlighter().highlightSync(language, code);
      expect(tokens, isNotEmpty);
      bool splits(int pos) =>
          pos > 0 &&
          pos < code.length &&
          code.codeUnitAt(pos - 1) >= 0xD800 &&
          code.codeUnitAt(pos - 1) <= 0xDBFF &&
          code.codeUnitAt(pos) >= 0xDC00 &&
          code.codeUnitAt(pos) <= 0xDFFF;
      for (final t in tokens) {
        expect(splits(t.start), isFalse, reason: 'start ${t.start}');
        expect(splits(t.end), isFalse, reason: 'end ${t.end}');
      }
    }

    test('the engine output itself has no bound inside a pair', () {
      // Прямая проверка `tokenizeWithEngine`, без страховки `_codeSpan`.
      // Подобрано перебором языков: разрез попадает на НАЧАЛО токена
      // (c и clojure, строка `"\\😀`) и на КОНЕЦ (batch `^😀`, c `"\\😀`).
      const emoji = '\u{1F600}';
      final inputs = <String, List<String>>{
        'c': ['"\\$emoji', '"\\$emoji x', '"\\$emoji"'],
        'clojure': ['"\\$emoji', '(str \\$emoji)'],
        'batch': ['^$emoji', '^$emoji x'],
        'latex': ['\\$emoji x'],
      };
      inputs.forEach((language, codes) {
        for (final code in codes) {
          final tokens = tokenizeWithEngine(language, code);
          expect(tokens, isNotEmpty, reason: '$language $code');
          for (final t in tokens) {
            expect(
              snapToCodePoint(code, t.start),
              t.start,
              reason: 'start of $language $code',
            );
            expect(
              snapToCodePoint(code, t.end),
              t.end,
              reason: 'end of $language $code',
            );
          }
        }
      });
    });

    test('token bounds never fall between the halves of a pair', () {
      expectWholePairs('latex', '\\\u{1F600} x');
      expectWholePairs('clojure', '(str \\\u{1F600})');
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

      // Движок может положить фрагмент кода в сообщение своего исключения:
      // в отчёт оно попадать не должно (§12, §16 `AGENTS.md`).
      final highlighter = CodeLabCodeHighlighter(
        tokenizer: (language, code) =>
            throw StateError('boom: secret_code_line in $code'),
      );
      const secret = 'final topSecretValue = 42; // secret_code_line';
      expect(highlighter.highlightSync('dart', secret), isEmpty);

      expect(reports, hasLength(1));
      final details = reports.single;
      final text = details.toDiagnosticsNode().toStringDeep();
      for (final fragment in ['topSecretValue', 'secret_code_line', 'boom']) {
        expect(text, isNot(contains(fragment)), reason: 'report: $fragment');
        expect(
          details.exception.toString(),
          isNot(contains(fragment)),
          reason: 'exception: $fragment',
        );
        expect(
          details.exceptionAsString(),
          isNot(contains(fragment)),
          reason: 'exceptionAsString: $fragment',
        );
      }
      // Решение оркестратора: тот же код даст тот же исход, поэтому сбой
      // запоминается как «без подсветки» — повтор не вызывает движок и не
      // шлёт второй отчёт.
      expect(highlighter.cached('dart', secret), isEmpty);
      expect(highlighter.highlightSync('dart', secret), isEmpty);
      expect(reports, hasLength(1));
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
