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

import 'dart:io';

import 'package:codelab_ui/codelab_ui.dart';
import 'package:codelab_ui/src/rendering/codelab_markdown_row.dart';
import 'package:codelab_ui/src/rendering/escape_for_display.dart';
import 'package:fluent_ui/fluent_ui.dart';
import 'package:flutter/foundation.dart' show defaultTargetPlatform;
import 'package:flutter/gestures.dart';
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

void main() {
  late HttpOverrides? previousOverrides;

  setUp(() {
    previousOverrides = HttpOverrides.current;
    _networkRequests.clear();
    HttpOverrides.global = _ForbiddenNetwork();
    CodeLabMarkdownStats.reset();
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
}
