// Markdown в ответе агента (итерация 2, задача 2.1 change
// `add-desktop-markdown`; spec agent-workbench-ui «Markdown в ответе агента»,
// «Блок кода в ответе агента», «Стриминг markdown без перестройки закрытых
// блоков»; design.md D1–D4, D7–D9, D13; invariant DSK-3, DSK-6).
//
// Красная фаза: тесты обращаются к API, которого ещё нет, — `CodeLabMarkdown`,
// `CodeLabMarkdownStats` и новая форма `CodeLabAgentTextRow(id, text,
// streaming)` из `package:codelab_ui/codelab_ui.dart`. Имена тестов — ровно
// как в tasks.md и `12-3-desktop-display.md` §12.3.7: это критерии матрицы
// D-06.
//
// Сеть перехвачена `HttpOverrides` (R3): любой запрос из отрисовки — провал
// теста. Тесты идут без Material-предка: хостом служит `FluentApp`.
//
// Ожидаемые сигнатуры (для реализации 2.2/2.3):
//  * `CodeLabMarkdown({Key? key, required String id, required String text,
//    bool streaming = false, CodeLabMarkdownConfig? config})` — `id` — id
//    строки ленты, из него строятся ключи `code-copy-<id>-<n>`;
//  * `CodeLabMarkdownStats` — debug-счётчики, считаются только в `assert`:
//    `Map<String, int> codeBlockBuilds` (построения ЗАКРЫТЫХ блоков кода,
//    ключ `<id>-<n>`), `Map<String, int> codeBlockMounts` (initState блока,
//    тот же ключ), `Map<String, int> headingBuilds` (ключ — текст заголовка),
//    `int highlightRuns`, `int highlightSyncRuns`, `void reset()`;
//  * `CodeLabAgentTextRow({required id, required text, bool streaming = false})`.

import 'dart:io';

import 'package:codelab_ui/codelab_ui.dart';
import 'package:fluent_ui/fluent_ui.dart';
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

Widget _host(
  Widget child, {
  Brightness brightness = Brightness.light,
  double width = 600,
}) => FluentApp(
  debugShowCheckedModeBanner: false,
  themeMode: brightness == Brightness.dark ? ThemeMode.dark : ThemeMode.light,
  theme: FluentThemeData(brightness: Brightness.light),
  darkTheme: FluentThemeData(brightness: Brightness.dark),
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
}) => FluentApp(
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
  final step = (doc.length / n).ceil();
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
    await tester.pump();
    expect(clipboard, [code]);

    // Выделение всего ответа не содержит подписи `dart` (D4, факт 7).
    clipboard.clear();
    final region = tester.state<SelectableRegionState>(
      find.byType(SelectableRegion),
    );
    region.selectAll();
    await tester.pump();
    // ignore: deprecated_member_use — публичного способа получить выделенный
    // текст без меню нет; метод кладёт в буфер то же, что Cmd/Ctrl+C.
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

    final paragraphBuilds = Map.of(CodeLabMarkdownStats.headingBuilds);

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
    expect(CodeLabMarkdownStats.headingBuilds, paragraphBuilds);
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
}
