// Красные тесты задачи 3.3 change `redesign-protocol-pane`: организм
// `CodeLabProtocolPane` по готовым данным (design.md D1, D12, D13; spec
// agent-workbench-ui «Панель Protocol: виды Frames и Log», «Таблица кадров»,
// «Выбранный кадр», «Вид Log панели Protocol»; testing-quality «Рендерится
// панель Protocol»).
//
// Красный до задачи 3.4: файла `organisms/codelab_protocol_pane.dart` и
// классов данных ещё нет (ошибка компиляции — допустимый красный).
//
// Границы (`codelab_ui/AGENTS.md` §2, design.md D12): кит не знает ACP,
// кадров и записей журнала. Подписи, тоны, теги и сегменты JSON приходят
// готовыми от маппера app; здесь проверяется только отображение и
// взаимодействие. Имена классов данных, параметров и ключей, кроме названных
// в D12 (`CodeLabProtocolPane`, `CodeLabProtocolTableRow`,
// `CodeLabProtocolDetail`, `CodeLabMaskedSegment(text, masked)`), выбраны
// этим тестом и фиксируют предложение для задачи 3.4: design.md их не задаёт.

import 'package:codelab_ui/codelab_ui.dart';
import 'package:fluent_ui/fluent_ui.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter_test/flutter_test.dart';

const _tableKey = ValueKey('protocol-table');
const _detailKey = ValueKey('protocol-detail');

Widget _host(Widget pane, {double height = 700}) => FluentApp(
  home: Center(
    child: SizedBox(width: 640, height: height, child: pane),
  ),
);

const _rows = [
  CodeLabProtocolTableRow(
    id: 'f1',
    cells: ['→', 'session/new', '1', '12:00:01'],
  ),
  CodeLabProtocolTableRow(
    id: 'f2',
    cells: ['←', 'session/update · tool_call', '—', '12:00:02'],
  ),
  CodeLabProtocolTableRow(
    id: 'f3',
    cells: ['←', 'error -32603 · Internal error', '5', '12:00:03'],
    tone: CodeLabTone.danger,
  ),
  CodeLabProtocolTableRow(
    id: 'f4',
    cells: ['→', 'initialize', '0', '12:00:00'],
    tag: 'connection',
    selected: true,
  ),
];

CodeLabProtocolPane _pane({
  CodeLabProtocolView view = CodeLabProtocolView.frames,
  int framesCount = 412,
  int logCount = 1284,
  ValueChanged<CodeLabProtocolView>? onViewChanged,
  List<CodeLabProtocolTableRow> rows = _rows,
  ValueChanged<String>? onRowSelected,
  String? emptyRowsText,
  CodeLabProtocolDetail? detail,
  List<String> columns = const ['', 'Method', 'Id', 'Time'],
  int toneColumn = 1,
  int tagColumn = 1,
  List<CodeLabProtocolInfo> notices = const [],
  double? splitFraction,
  ValueChanged<double>? onSplitChanged,
  String footer = 'Panes follow the focused session · ⇧⌘I',
}) => CodeLabProtocolPane(
  view: view,
  onViewChanged: onViewChanged ?? (_) {},
  framesCount: framesCount,
  logCount: logCount,
  viewHint: 'Alt+← / Alt+→ previous / next frame',
  filters: const Text('filters-slot'),
  columns: columns,
  toneColumn: toneColumn,
  tagColumn: tagColumn,
  notices: notices,
  splitFraction: splitFraction,
  onSplitChanged: onSplitChanged,
  rows: rows,
  onRowSelected: onRowSelected ?? (_) {},
  emptyRowsText: emptyRowsText,
  detail: detail,
  footer: footer,
);

CodeLabProtocolDetail _detail({
  List<CodeLabMaskedSegment>? segments,
  List<CodeLabProtocolField>? fields,
  CodeLabProtocolInfo? info,
  String? note,
  VoidCallback? onCopy,
  bool copy = true,
}) => CodeLabProtocolDetail(
  title: '→ session/new · id 1',
  tags: const [
    CodeLabProtocolTag(label: 'client → agent'),
    CodeLabProtocolTag(label: '2.0 KB', tone: CodeLabTone.accent),
  ],
  info:
      info ??
      const CodeLabProtocolInfo(
        title: 'Debug build: full payloads.',
        message:
            'Release builds keep metadata only. Secrets are masked before a '
            'frame is stored.',
        tone: CodeLabTone.warning,
      ),
  segments: segments,
  fields: fields,
  note: note,
  onCopy: copy ? (onCopy ?? () {}) : null,
);

Color? _textColor(WidgetTester tester, String text) =>
    tester.widget<Text>(find.text(text)).style?.color;

InfoBarSeverity _severityOf(WidgetTester tester) =>
    tester.widget<InfoBar>(find.byType(InfoBar)).severity;

void main() {
  group('переключатель видов', () {
    testWidgets('показывает Frames и Log со счётчиками и подсказку вида', (
      tester,
    ) async {
      await tester.pumpWidget(_host(_pane()));

      expect(find.textContaining('Frames'), findsWidgets);
      expect(find.textContaining('412'), findsOneWidget);
      expect(find.textContaining('Log'), findsOneWidget);
      expect(find.textContaining('1284'), findsOneWidget);
      expect(find.text('Alt+← / Alt+→ previous / next frame'), findsOneWidget);
    });

    testWidgets('нажатие на Log сообщает о смене вида', (tester) async {
      final changes = <CodeLabProtocolView>[];
      await tester.pumpWidget(_host(_pane(onViewChanged: changes.add)));

      await tester.tap(find.textContaining('Log'));
      await tester.pump();

      expect(changes, [CodeLabProtocolView.log]);
    });

    testWidgets('слот фильтров и подвал показаны', (tester) async {
      await tester.pumpWidget(_host(_pane()));

      expect(find.text('filters-slot'), findsOneWidget);
      expect(
        find.text('Panes follow the focused session · ⇧⌘I'),
        findsOneWidget,
      );
    });
  });

  group('таблица', () {
    testWidgets('показывает заголовки колонок и подписи строк', (tester) async {
      await tester.pumpWidget(_host(_pane()));

      for (final text in ['Method', 'Id', 'Time']) {
        expect(find.text(text), findsOneWidget);
      }
      expect(find.text('session/new'), findsOneWidget);
      expect(find.text('session/update · tool_call'), findsOneWidget);
      expect(find.text('error -32603 · Internal error'), findsOneWidget);
      expect(find.text('—'), findsOneWidget);
    });

    testWidgets('строка с тоном опасности отличается цветом от обычной', (
      tester,
    ) async {
      await tester.pumpWidget(_host(_pane()));
      final theme = FluentTheme.of(tester.element(find.byType(FluentApp)));
      final danger = CodeLabPalette.of(theme).danger;

      expect(_textColor(tester, 'error -32603 · Internal error'), danger);
      expect(_textColor(tester, 'session/new'), isNot(danger));
    });

    testWidgets('строка с тегом показывает его рядом с подписью', (
      tester,
    ) async {
      await tester.pumpWidget(_host(_pane()));

      expect(find.text('connection'), findsOneWidget);
    });

    testWidgets('выбранная строка помечена для семантики', (tester) async {
      await tester.pumpWidget(_host(_pane()));

      final selected = tester.getSemantics(
        find.byKey(const ValueKey('protocol-row-f4')),
      );
      // ignore: deprecated_member_use
      expect(selected.hasFlag(SemanticsFlag.isSelected), isTrue);
      final other = tester.getSemantics(
        find.byKey(const ValueKey('protocol-row-f1')),
      );
      // ignore: deprecated_member_use
      expect(other.hasFlag(SemanticsFlag.isSelected), isFalse);
    });

    testWidgets('нажатие на строку сообщает её id', (tester) async {
      final selected = <String>[];
      await tester.pumpWidget(_host(_pane(onRowSelected: selected.add)));

      await tester.tap(find.text('session/update · tool_call'));
      await tester.pump();

      expect(selected, ['f2']);
    });

    testWidgets('пустая таблица показывает подсказку вместо строк', (
      tester,
    ) async {
      await tester.pumpWidget(
        _host(_pane(rows: const [], emptyRowsText: 'No frames yet.')),
      );

      expect(find.text('No frames yet.'), findsOneWidget);
      expect(find.text('session/new'), findsNothing);
    });

    testWidgets('при 2000 строках строятся только видимые', (tester) async {
      final rows = [
        for (var i = 0; i < 2000; i++)
          CodeLabProtocolTableRow(
            id: 'r$i',
            cells: ['→', 'session/update · $i', '$i', '12:00:00'],
          ),
      ];
      await tester.pumpWidget(_host(_pane(rows: rows)));

      final built = find.byWidgetPredicate((widget) {
        final key = widget.key;
        return key is ValueKey<String> && key.value.startsWith('protocol-row-');
      });
      expect(built, findsWidgets);
      expect(built.evaluate().length, lessThan(60));
      expect(find.text('session/update · 1999'), findsNothing);
    });
  });

  group('панель выбранного', () {
    testWidgets('без выбора показывает подсказку вида Frames', (tester) async {
      await tester.pumpWidget(_host(_pane()));

      expect(find.text('Select a frame to see its details.'), findsOneWidget);
    });

    testWidgets('без выбора показывает подсказку вида Log', (tester) async {
      await tester.pumpWidget(_host(_pane(view: CodeLabProtocolView.log)));

      expect(find.text('Select a record to see its fields.'), findsOneWidget);
      expect(find.text('Select a frame to see its details.'), findsNothing);
    });

    testWidgets('показывает заголовок, теги и кнопку Copy', (tester) async {
      var copied = 0;
      await tester.pumpWidget(
        _host(
          _pane(
            detail: _detail(
              segments: const [CodeLabMaskedSegment('{}', masked: false)],
              onCopy: () => copied++,
            ),
          ),
        ),
      );

      expect(find.text('→ session/new · id 1'), findsOneWidget);
      expect(find.text('client → agent'), findsOneWidget);
      expect(find.text('2.0 KB'), findsOneWidget);
      expect(find.text('Select a frame to see its details.'), findsNothing);

      await tester.tap(find.text('Copy'));
      await tester.pump();
      expect(copied, 1);
    });

    testWidgets('InfoBar-предупреждение: заголовок, текст, серьёзность', (
      tester,
    ) async {
      await tester.pumpWidget(
        _host(
          _pane(
            detail: _detail(
              segments: const [CodeLabMaskedSegment('{}', masked: false)],
            ),
          ),
        ),
      );

      expect(find.text('Debug build: full payloads.'), findsOneWidget);
      expect(
        find.textContaining('Release builds keep metadata only.'),
        findsOneWidget,
      );
      expect(_severityOf(tester), InfoBarSeverity.warning);
    });

    testWidgets('информационный InfoBar: серьёзность info', (tester) async {
      await tester.pumpWidget(
        _host(
          _pane(
            detail: _detail(
              info: const CodeLabProtocolInfo(
                title: 'Release build: metadata only.',
                message:
                    'Payloads are not stored. Secrets are masked before a '
                    'frame is stored.',
                tone: CodeLabTone.neutral,
              ),
              fields: const [
                CodeLabProtocolField(label: 'direction', value: 'outgoing'),
              ],
            ),
          ),
        ),
      );

      expect(find.text('Release build: metadata only.'), findsOneWidget);
      expect(_severityOf(tester), InfoBarSeverity.info);
    });

    testWidgets('замаскированный сегмент показан как «••••••• (masked)»', (
      tester,
    ) async {
      await tester.pumpWidget(
        _host(
          _pane(
            detail: _detail(
              segments: const [
                CodeLabMaskedSegment('{"value": "', masked: false),
                CodeLabMaskedSegment('<redacted>', masked: true),
                CodeLabMaskedSegment('"}', masked: false),
              ],
            ),
          ),
        ),
      );

      expect(
        find.textContaining('••••••• (masked)', findRichText: true),
        findsOneWidget,
      );
      // Исходный маркер сегмента не показывается: кит рисует вместо него
      // собственную подпись (D12).
      expect(
        find.textContaining('<redacted>', findRichText: true),
        findsNothing,
      );
      expect(
        find.textContaining('"value": "', findRichText: true),
        findsOneWidget,
      );
    });

    testWidgets('поля ключ — значение и заметка вместо JSON', (tester) async {
      await tester.pumpWidget(
        _host(
          _pane(
            detail: _detail(
              fields: const [
                CodeLabProtocolField(label: 'direction', value: 'outgoing'),
                CodeLabProtocolField(label: 'method', value: 'session/new'),
              ],
              note: 'Recorded before Trace was turned on: metadata only.',
            ),
          ),
        ),
      );

      expect(find.text('direction'), findsOneWidget);
      expect(find.text('outgoing'), findsOneWidget);
      expect(find.text('method'), findsOneWidget);
      expect(
        find.text('Recorded before Trace was turned on: metadata only.'),
        findsOneWidget,
      );
    });

    testWidgets('ссылка у поля вызывает колбэк', (tester) async {
      var shown = 0;
      await tester.pumpWidget(
        _host(
          _pane(
            view: CodeLabProtocolView.log,
            detail: _detail(
              fields: [
                CodeLabProtocolField(
                  label: 'request_id',
                  value: '5',
                  linkLabel: 'Show frame in Frames',
                  onLink: () => shown++,
                ),
              ],
            ),
          ),
        ),
      );

      await tester.tap(find.text('Show frame in Frames'));
      await tester.pump();

      expect(shown, 1);
    });

    testWidgets('недоступная ссылка не нажимается и несёт подсказку', (
      tester,
    ) async {
      await tester.pumpWidget(
        _host(
          _pane(
            view: CodeLabProtocolView.log,
            detail: _detail(
              fields: const [
                CodeLabProtocolField(
                  label: 'request_id',
                  value: '5',
                  linkLabel: 'Show frame in Frames',
                  linkUnavailableHint: 'The frame is no longer in the buffer.',
                ),
              ],
            ),
          ),
        ),
      );

      expect(find.text('Show frame in Frames'), findsOneWidget);
      expect(
        find.byWidgetPredicate(
          (widget) =>
              widget is Tooltip &&
              widget.message == 'The frame is no longer in the buffer.',
        ),
        findsOneWidget,
      );
      // Нажатие по недоступной ссылке не бросает и ничего не меняет.
      await tester.tap(find.text('Show frame in Frames'));
      await tester.pump();
      expect(tester.takeException(), isNull);
    });
  });

  group('разделитель таблицы и панели выбранного', () {
    CodeLabProtocolPane withDetail() => _pane(
      detail: _detail(
        segments: const [CodeLabMaskedSegment('{}', masked: false)],
      ),
    );

    testWidgets('по умолчанию таблица занимает около 52 % в Frames', (
      tester,
    ) async {
      await tester.pumpWidget(_host(withDetail()));

      final table = tester.getSize(find.byKey(_tableKey)).height;
      final detail = tester.getSize(find.byKey(_detailKey)).height;
      final share = table / (table + detail);
      expect(share, closeTo(0.52, 0.03));
    });

    testWidgets('по умолчанию таблица занимает около 56 % в Log', (
      tester,
    ) async {
      await tester.pumpWidget(
        _host(
          _pane(
            view: CodeLabProtocolView.log,
            detail: _detail(
              fields: const [
                CodeLabProtocolField(label: 'time', value: '2026-11-22'),
              ],
            ),
          ),
        ),
      );

      final table = tester.getSize(find.byKey(_tableKey)).height;
      final detail = tester.getSize(find.byKey(_detailKey)).height;
      expect(table / (table + detail), closeTo(0.56, 0.03));
    });

    testWidgets('горизонтальная ось: тяга вниз до края оставляет ≥ 96 px', (
      tester,
    ) async {
      await tester.pumpWidget(_host(withDetail()));
      final handle = find.byType(CodeLabResizeHandle);
      expect(tester.widget<CodeLabResizeHandle>(handle).axis, Axis.horizontal);

      await tester.drag(handle, const Offset(0, 2000));
      await tester.pump();

      expect(
        tester.getSize(find.byKey(_detailKey)).height,
        greaterThanOrEqualTo(96),
      );
      expect(
        tester.getSize(find.byKey(_tableKey)).height,
        greaterThanOrEqualTo(96),
      );
    });

    testWidgets('тяга вверх до края оставляет таблице ≥ 96 px', (tester) async {
      await tester.pumpWidget(_host(withDetail()));

      await tester.drag(
        find.byType(CodeLabResizeHandle),
        const Offset(0, -2000),
      );
      await tester.pump();

      expect(
        tester.getSize(find.byKey(_tableKey)).height,
        greaterThanOrEqualTo(96),
      );
      expect(
        tester.getSize(find.byKey(_detailKey)).height,
        greaterThanOrEqualTo(96),
      );
    });

    testWidgets('тяга меняет долю: таблица растёт при движении вниз', (
      tester,
    ) async {
      await tester.pumpWidget(_host(withDetail()));
      final before = tester.getSize(find.byKey(_tableKey)).height;

      await tester.drag(find.byType(CodeLabResizeHandle), const Offset(0, 40));
      await tester.pump();

      expect(tester.getSize(find.byKey(_tableKey)).height, greaterThan(before));
    });
  });

  // Дополнение D12 (решение архитектора 2026-11-22): `notices`, пары
  // `toneColumn`/`tagColumn`, контролируемая доля `splitFraction` и
  // `onSplitChanged`, кнопка `Copy` только при `onCopy`.
  group('notices', () {
    testWidgets('danger — InfoBarSeverity.error, neutral — info', (
      tester,
    ) async {
      await tester.pumpWidget(
        _host(
          _pane(
            notices: const [
              CodeLabProtocolInfo(
                title: 'No session in focus. Showing connection frames only.',
                message: '',
                tone: CodeLabTone.neutral,
              ),
              CodeLabProtocolInfo(
                title: "Couldn't save the file.",
                message: '',
                tone: CodeLabTone.danger,
              ),
            ],
          ),
        ),
      );

      final bars = tester.widgetList<InfoBar>(find.byType(InfoBar)).toList();
      expect(bars, hasLength(2));
      expect(bars[0].severity, InfoBarSeverity.info);
      expect(bars[1].severity, InfoBarSeverity.error);
      expect(
        find.text('No session in focus. Showing connection frames only.'),
        findsOneWidget,
      );
      expect(find.text("Couldn't save the file."), findsOneWidget);
    });

    testWidgets('warning — InfoBarSeverity.warning, заметки над таблицей', (
      tester,
    ) async {
      await tester.pumpWidget(
        _host(
          _pane(
            notices: const [
              CodeLabProtocolInfo(
                title: 'Heads up',
                message: '',
                tone: CodeLabTone.warning,
              ),
            ],
          ),
        ),
      );

      expect(_severityOf(tester), InfoBarSeverity.warning);
      expect(
        tester.getRect(find.text('Heads up')).bottom,
        lessThanOrEqualTo(tester.getRect(find.byKey(_tableKey)).top + 1),
      );
    });

    testWidgets('без notices InfoBar-ов нет', (tester) async {
      await tester.pumpWidget(_host(_pane()));

      expect(find.byType(InfoBar), findsNothing);
    });
  });

  group('toneColumn и tagColumn в виде Log', () {
    const logRows = [
      CodeLabProtocolTableRow(
        id: 'l1',
        cells: ['12:00:01.000', 'ERROR', 'session', 'prompt failed'],
        tone: CodeLabTone.danger,
        tag: 'connection',
      ),
    ];

    testWidgets('тон красит колонку 1, тег стоит у колонки 3', (tester) async {
      await tester.pumpWidget(
        _host(
          _pane(
            view: CodeLabProtocolView.log,
            columns: const ['Time', 'Level', 'Category', 'Event'],
            toneColumn: 1,
            tagColumn: 3,
            rows: logRows,
          ),
        ),
      );
      final theme = FluentTheme.of(tester.element(find.byType(FluentApp)));
      final danger = CodeLabPalette.of(theme).danger;

      expect(_textColor(tester, 'ERROR'), danger);
      expect(_textColor(tester, 'prompt failed'), isNot(danger));
      expect(_textColor(tester, 'session'), isNot(danger));

      final event = tester.getRect(find.text('prompt failed'));
      final tag = tester.getRect(find.text('connection'));
      final level = tester.getRect(find.text('ERROR'));
      // Тег — в колонке Event, правее Level и на одной строке с событием.
      expect(tag.left, greaterThanOrEqualTo(event.left));
      expect(tag.left, greaterThan(level.right));
      expect((tag.center.dy - event.center.dy).abs(), lessThan(8));
    });

    testWidgets('без индексов тон и тег — в колонке 1 (Method)', (
      tester,
    ) async {
      await tester.pumpWidget(_host(_pane()));
      final theme = FluentTheme.of(tester.element(find.byType(FluentApp)));

      expect(
        _textColor(tester, 'error -32603 · Internal error'),
        CodeLabPalette.of(theme).danger,
      );
      final method = tester.getRect(find.text('initialize'));
      final tag = tester.getRect(find.text('connection'));
      expect(tag.left, greaterThanOrEqualTo(method.right));
    });
  });

  group('контролируемая доля разделителя', () {
    CodeLabProtocolPane controlled({
      required double fraction,
      ValueChanged<double>? onChanged,
    }) => _pane(
      splitFraction: fraction,
      onSplitChanged: onChanged,
      detail: _detail(
        segments: const [CodeLabMaskedSegment('{}', masked: false)],
      ),
    );

    double tableShare(WidgetTester tester) {
      final table = tester.getSize(find.byKey(_tableKey)).height;
      final detail = tester.getSize(find.byKey(_detailKey)).height;
      return table / (table + detail);
    }

    testWidgets('рисует переданную долю и перерисовывается при смене', (
      tester,
    ) async {
      await tester.pumpWidget(_host(controlled(fraction: 0.3)));
      expect(tableShare(tester), closeTo(0.3, 0.04));

      await tester.pumpWidget(_host(controlled(fraction: 0.7)));
      expect(tableShare(tester), closeTo(0.7, 0.04));
    });

    testWidgets('перетаскивание сообщает долю через onSplitChanged', (
      tester,
    ) async {
      final reported = <double>[];
      await tester.pumpWidget(
        _host(controlled(fraction: 0.3, onChanged: reported.add)),
      );

      await tester.drag(find.byType(CodeLabResizeHandle), const Offset(0, 60));
      await tester.pump();

      expect(reported, isNotEmpty);
      expect(reported.last, greaterThan(0.3));
      expect(reported.last, lessThan(1));
    });

    testWidgets('хост не принял долю — организм её не меняет', (tester) async {
      await tester.pumpWidget(
        _host(controlled(fraction: 0.3, onChanged: (_) {})),
      );

      await tester.drag(find.byType(CodeLabResizeHandle), const Offset(0, 60));
      await tester.pump();

      expect(tableShare(tester), closeTo(0.3, 0.04));
    });

    testWidgets('доля у края всё равно оставляет обеим частям ≥ 96 px', (
      tester,
    ) async {
      await tester.pumpWidget(_host(controlled(fraction: 0.99)));

      expect(
        tester.getSize(find.byKey(_detailKey)).height,
        greaterThanOrEqualTo(96),
      );
      await tester.pumpWidget(_host(controlled(fraction: 0.01)));
      expect(
        tester.getSize(find.byKey(_tableKey)).height,
        greaterThanOrEqualTo(96),
      );
    });
  });

  group('Copy только при onCopy', () {
    testWidgets('без onCopy кнопки Copy нет', (tester) async {
      await tester.pumpWidget(
        _host(
          _pane(
            detail: _detail(
              copy: false,
              segments: const [CodeLabMaskedSegment('{}', masked: false)],
            ),
          ),
        ),
      );

      expect(find.text('→ session/new · id 1'), findsOneWidget);
      expect(find.text('Copy'), findsNothing);
    });

    testWidgets('с onCopy кнопка Copy есть', (tester) async {
      await tester.pumpWidget(
        _host(
          _pane(
            detail: _detail(
              segments: const [CodeLabMaskedSegment('{}', masked: false)],
            ),
          ),
        ),
      );

      expect(find.text('Copy'), findsOneWidget);
    });
  });
}
