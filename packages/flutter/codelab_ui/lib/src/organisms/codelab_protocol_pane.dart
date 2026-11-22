import 'dart:math' as math;

import 'package:fluent_ui/fluent_ui.dart';

import '../atomics/atomics.dart';
import '../atomics/codelab_pressable.dart';
import '../l10n/strings.dart';
import '../molecules/codelab_selector_bar.dart';

/// Вид панели Protocol: кадры ACP или записи журнала.
enum CodeLabProtocolView { frames, log }

/// Тег рядом с заголовком выбранного элемента (`client → agent`, `2.0 KB`).
class CodeLabProtocolTag {
  const CodeLabProtocolTag({
    required this.label,
    this.tone = CodeLabTone.neutral,
  });

  final String label;
  final CodeLabTone tone;
}

/// Заметка-InfoBar: политика payload, заметки сбоя и области панели.
///
/// Тон выбирает серьёзность: `warning` — предупреждение, `danger` — ошибка,
/// остальное — информация (design.md change `redesign-protocol-pane`, D12).
/// Пустой [message] не рисуется.
class CodeLabProtocolInfo {
  const CodeLabProtocolInfo({
    required this.title,
    required this.message,
    this.tone = CodeLabTone.neutral,
  });

  final String title;
  final String message;
  final CodeLabTone tone;
}

/// Фрагмент отформатированного JSON: [masked] — значение скрыто маскированием.
///
/// Маппер app делит JSON по `"<redacted>"`; кит рисует замаскированный
/// фрагмент подписью `••••••• (masked)` тоном предупреждения, а [text]
/// замаскированного фрагмента не показывает (D12).
class CodeLabMaskedSegment {
  const CodeLabMaskedSegment(this.text, {required this.masked});

  final String text;
  final bool masked;
}

/// Поле «ключ — значение» панели выбранного; у одного поля может быть ссылка.
///
/// Ссылка есть при [linkLabel]. При [onLink] `== null` она недоступна, а
/// [linkUnavailableHint] показывается подсказкой (`The frame is no longer in
/// the buffer.`).
class CodeLabProtocolField {
  const CodeLabProtocolField({
    required this.label,
    required this.value,
    this.linkLabel,
    this.onLink,
    this.linkUnavailableHint,
  });

  final String label;
  final String value;
  final String? linkLabel;
  final VoidCallback? onLink;
  final String? linkUnavailableHint;
}

/// Строка таблицы панели Protocol: готовые ячейки, тон и тег.
///
/// [tone] красит текст ячейки `toneColumn` (не фон строки), [tag] стоит рядом
/// с текстом ячейки `tagColumn`, [selected] помечает строку для семантики.
class CodeLabProtocolTableRow {
  const CodeLabProtocolTableRow({
    required this.id,
    required this.cells,
    this.tone,
    this.selected = false,
    this.tag,
  });

  final String id;
  final List<String> cells;
  final CodeLabTone? tone;
  final bool selected;
  final String? tag;
}

/// Панель выбранного элемента: заголовок, теги, InfoBar и тело.
///
/// Тело — [segments] (JSON) или [fields] (ключ — значение); [note] идёт под
/// телом. Без [onCopy] кнопки `Copy` нет.
class CodeLabProtocolDetail {
  const CodeLabProtocolDetail({
    required this.title,
    this.tags = const [],
    this.info,
    this.segments,
    this.fields,
    this.note,
    this.onCopy,
  });

  final String title;
  final List<CodeLabProtocolTag> tags;
  final CodeLabProtocolInfo? info;
  final List<CodeLabMaskedSegment>? segments;
  final List<CodeLabProtocolField>? fields;
  final String? note;
  final VoidCallback? onCopy;
}

/// Панель Protocol дока: переключатель видов, фильтры, таблица, разделитель,
/// панель выбранного и подвал.
///
/// Почему: макет `Inspector.dc.html` / `InspectorLog.dc.html` показывает один
/// вид за раз, а таблице и деталям нужна высота (change
/// `redesign-protocol-pane`, D1, D12).
///
/// Для чего: только отображение готовых данных. Кит не знает ACP, кадров и
/// журнала: подписи, тоны, теги и сегменты JSON строит маппер app
/// (`codelab_ui/AGENTS.md` §2). Тексты кита — `Frames`/`Log`, подсказки
/// пустого выбора, `Copy`, `••••••• (masked)`; остальное передаёт хост.
/// Действия шапки (`Pause`, `Clear`, …) сюда не входят — они в
/// `CodeLabDockTab.actions`.
///
/// Как использовать: хост передаёт данные и колбэки. Доля таблицы в сумме
/// «таблица + панель выбранного» либо внутренняя (`splitFraction == null`,
/// по умолчанию 0.52 в Frames и 0.56 в Log), либо контролируемая хостом
/// ([splitFraction] и [onSplitChanged]). Обе части не меньше 96 px. Таблица —
/// `ListView.builder` с фиксированной высотой строки: строятся только видимые.
/// Ключи: `protocol-table`, `protocol-detail`, `protocol-row-<id>`.
class CodeLabProtocolPane extends StatefulWidget {
  const CodeLabProtocolPane({
    required this.view,
    required this.onViewChanged,
    required this.framesCount,
    required this.logCount,
    required this.columns,
    required this.rows,
    required this.onRowSelected,
    required this.footer,
    this.viewHint,
    this.filters,
    this.toneColumn = 1,
    this.tagColumn = 1,
    this.columnWidths,
    this.emptyRowsText,
    this.notices = const [],
    this.detail,
    this.splitFraction,
    this.onSplitChanged,
    this.followTail = true,
    this.tailScope,
    super.key,
  });

  final CodeLabProtocolView view;
  final ValueChanged<CodeLabProtocolView> onViewChanged;
  final int framesCount;
  final int logCount;

  /// Подсказка сочетаний активного вида справа от переключателя.
  final String? viewHint;

  /// Слот строки фильтров (поиск, переключатели, `Expand` строит app).
  final Widget? filters;

  /// Заголовки колонок; пустой заголовок — узкая колонка (направление).
  final List<String> columns;

  /// Колонка, чей текст красит тон строки.
  final int toneColumn;

  /// Колонка, рядом с текстом которой стоит тег строки; она же растягивается.
  final int tagColumn;

  /// Ширины колонок: число — фиксированная ширина, `null` — гибкая колонка.
  /// Без параметра: колонка тега гибкая, колонка с пустым заголовком (стрелка
  /// направления) 28 px, остальные 72 px. Узкие фиксированные колонки нужны,
  /// чтобы в доке 360 px гибкой колонке (метод, событие) оставалось место.
  final List<double?>? columnWidths;
  final List<CodeLabProtocolTableRow> rows;
  final ValueChanged<String> onRowSelected;

  /// Текст вместо строк при пустом [rows].
  final String? emptyRowsText;

  /// Заметки над таблицей.
  final List<CodeLabProtocolInfo> notices;

  /// Выбранный элемент; `null` — подсказка пустого выбора.
  final CodeLabProtocolDetail? detail;

  /// Доля высоты таблицы; `null` — состояние внутри организма.
  final double? splitFraction;

  /// «Вид не на паузе» (D12 «Хвост таблицы»): пока `true` и пользователь не
  /// оторвался от низа, таблица после обновления строк прыгает к последней.
  /// Знает пауза app; отрыв знает только организм.
  final bool followTail;

  /// Ключ области (id сессии в фокусе, `null` без фокуса): его смена, как и
  /// смена [view], снимает отрыв и прыгает к последней строке.
  final Object? tailScope;
  final ValueChanged<double>? onSplitChanged;
  final String footer;

  /// Минимальная высота таблицы и панели выбранного (D1).
  static const double minPartHeight = 96;

  /// Высота строки таблицы: `.ptbl td` — 16 + 2 × 6 padding.
  static const double rowExtent = 28;

  @override
  State<CodeLabProtocolPane> createState() => _CodeLabProtocolPaneState();
}

class _CodeLabProtocolPaneState extends State<CodeLabProtocolPane> {
  double? _local;
  double? _dragFraction;

  double get _effective =>
      widget.splitFraction ??
      _local ??
      (widget.view == CodeLabProtocolView.frames ? 0.52 : 0.56);

  /// Доля, при которой обе части не меньше [CodeLabProtocolPane.minPartHeight].
  static double _clamp(double fraction, double total) {
    const min = CodeLabProtocolPane.minPartHeight;
    if (total <= 2 * min) return 0.5;
    return fraction.clamp(min / total, 1 - min / total);
  }

  void _onDelta(double delta, double total) {
    final next = _clamp((_dragFraction ?? _effective) + delta / total, total);
    _dragFraction = next;
    if (widget.splitFraction == null) {
      setState(() => _local = next);
    }
    widget.onSplitChanged?.call(next);
  }

  @override
  Widget build(BuildContext context) {
    final strings = codeLabStringsOf(context);
    final resources = FluentTheme.of(context).resources;
    final frames = widget.view == CodeLabProtocolView.frames;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            CodeLabSelectorBar<CodeLabProtocolView>(
              items: [
                CodeLabSelectorItem(
                  value: CodeLabProtocolView.frames,
                  label:
                      '${strings.codeLabProtocolViewFrames} ${widget.framesCount}',
                ),
                CodeLabSelectorItem(
                  value: CodeLabProtocolView.log,
                  label: '${strings.codeLabProtocolViewLog} ${widget.logCount}',
                ),
              ],
              value: widget.view,
              onChanged: widget.onViewChanged,
            ),
            if (widget.viewHint != null)
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 10),
                  child: CodeLabText(
                    widget.viewHint!,
                    role: CodeLabTextRole.caption,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    color: resources.textFillColorSecondary,
                  ),
                ),
              ),
          ],
        ),
        if (widget.filters != null)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            child: widget.filters,
          ),
        for (final notice in widget.notices)
          Padding(
            padding: const EdgeInsets.fromLTRB(10, 0, 10, 6),
            child: _InfoBar(info: notice),
          ),
        Expanded(
          child: LayoutBuilder(
            builder: (context, constraints) {
              const handle = 7.0;
              final total = math.max(1.0, constraints.maxHeight - handle);
              final tableHeight = (total * _clamp(_effective, total))
                  .roundToDouble();
              return Column(
                children: [
                  SizedBox(
                    key: const ValueKey('protocol-table'),
                    height: tableHeight,
                    child: _Table(pane: widget),
                  ),
                  CodeLabResizeHandle(
                    axis: Axis.horizontal,
                    width: handle,
                    onDelta: (delta) => _onDelta(delta, total),
                    onDragEnd: () => _dragFraction = null,
                  ),
                  SizedBox(
                    key: const ValueKey('protocol-detail'),
                    height: total - tableHeight,
                    child: widget.detail == null
                        ? Center(
                            child: CodeLabText(
                              frames
                                  ? strings.codeLabProtocolSelectFrame
                                  : strings.codeLabProtocolSelectRecord,
                              color: resources.textFillColorSecondary,
                            ),
                          )
                        : _Detail(detail: widget.detail!),
                  ),
                ],
              );
            },
          ),
        ),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
          decoration: BoxDecoration(
            border: Border(
              top: BorderSide(color: resources.dividerStrokeColorDefault),
            ),
          ),
          child: CodeLabText(
            widget.footer,
            role: CodeLabTextRole.caption,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            color: resources.textFillColorSecondary,
          ),
        ),
      ],
    );
  }
}

class _InfoBar extends StatelessWidget {
  const _InfoBar({required this.info});

  final CodeLabProtocolInfo info;

  @override
  Widget build(BuildContext context) => InfoBar(
    title: Text(info.title),
    content: info.message.isEmpty ? null : Text(info.message),
    severity: switch (info.tone) {
      CodeLabTone.warning => InfoBarSeverity.warning,
      CodeLabTone.danger => InfoBarSeverity.error,
      _ => InfoBarSeverity.info,
    },
  );
}

/// Таблица панели Protocol.
///
/// Прокруткой управляет сама таблица (design.md change
/// `redesign-protocol-pane`, D11, D12 «Хвост таблицы»): позиция прокрутки —
/// состояние отрисовки, и контроллер наружу не отдаётся. Высота строки
/// фиксирована (`itemExtent`), поэтому смещения считаются без
/// `ensureVisible`. Правила:
/// - **Выбранная строка.** После смены выбранной строки (и при первой
///   раскладке) таблица минимально прокручивается к ней; видимую строку не
///   двигает. Это приоритетнее хвоста: в таком обновлении прыжка к хвосту нет.
/// - **Хвост.** Пока `followTail` и нет отрыва пользователя от низа, после
///   обновления строк таблица прыгает к последней строке. «У низа» —
///   `pixels >= maxScrollExtent - rowExtent / 2`; признак отрыва
///   пересчитывается по положению после любой прокрутки, кроме собственного
///   прыжка к хвосту (колесо, перетаскивание, прокрутка к выбранной).
/// - **Смена `view` или `tailScope`** снимает отрыв и прыгает к последней
///   строке, в том числе на паузе (`followTail == false`).
/// Прыжок к хвосту выбор не меняет: выбор — состояние app.
class _Table extends StatefulWidget {
  const _Table({required this.pane});

  final CodeLabProtocolPane pane;

  @override
  State<_Table> createState() => _TableState();
}

class _TableState extends State<_Table> {
  final _controller = ScrollController();

  /// Пользователь оторвался от низа: поток новых строк его не уводит.
  bool _detached = false;

  /// Идёт собственный прыжок к хвосту: слушатель не считает его отрывом.
  bool _jumping = false;

  bool _scheduled = false;
  bool _selectionChanged = false;
  bool _scopeChanged = false;

  @override
  void initState() {
    super.initState();
    _controller.addListener(_onScroll);
    _selectionChanged = true;
    _schedule(initial: true);
  }

  @override
  void didUpdateWidget(_Table oldWidget) {
    super.didUpdateWidget(oldWidget);
    final pane = widget.pane;
    final old = oldWidget.pane;
    if (_selectedId(pane) != _selectedId(old)) _selectionChanged = true;
    if (pane.view != old.view || pane.tailScope != old.tailScope) {
      _scopeChanged = true;
    }
    _schedule();
  }

  @override
  void dispose() {
    _controller
      ..removeListener(_onScroll)
      ..dispose();
    super.dispose();
  }

  static String? _selectedId(CodeLabProtocolPane pane) {
    for (final row in pane.rows) {
      if (row.selected) return row.id;
    }
    return null;
  }

  bool get _atBottom {
    final position = _controller.position;
    return position.pixels >=
        position.maxScrollExtent - CodeLabProtocolPane.rowExtent / 2;
  }

  void _onScroll() {
    if (_jumping || !_controller.hasClients) return;
    _detached = !_atBottom;
  }

  /// Размеры области прокрутки известны только после раскладки, поэтому
  /// смещение применяется после кадра.
  void _schedule({bool initial = false}) {
    if (_scheduled) return;
    _scheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _scheduled = false;
      if (!mounted || !_controller.hasClients) {
        // Таблица пуста и списка ещё нет: ждём следующего обновления.
        return;
      }
      final selectionChanged = _selectionChanged;
      final scopeChanged = _scopeChanged;
      _selectionChanged = false;
      _scopeChanged = false;
      if (scopeChanged) {
        _detached = false;
        _jumpToTail();
      } else if (selectionChanged && _revealSelected()) {
        // Приоритет у выбранной строки: прыжка к хвосту в этом обновлении нет.
        if (initial) _detached = !_atBottom;
      } else if (initial && widget.pane.rows.isNotEmpty && !selectionChanged) {
        _jumpToTail();
      } else if (widget.pane.followTail && !_detached) {
        _jumpToTail();
      }
    });
  }

  /// Минимально прокручивает к выбранной строке. Возвращает `false`, если
  /// выбранной строки нет.
  bool _revealSelected() {
    final index = widget.pane.rows.indexWhere((row) => row.selected);
    if (index < 0) return false;
    final position = _controller.position;
    const extent = CodeLabProtocolPane.rowExtent;
    final top = index * extent;
    final bottom = top + extent;
    final double? target = top < position.pixels
        ? top
        : bottom > position.pixels + position.viewportDimension
        ? bottom - position.viewportDimension
        : null;
    if (target != null) {
      _controller.jumpTo(
        target.clamp(position.minScrollExtent, position.maxScrollExtent),
      );
    }
    return true;
  }

  void _jumpToTail() {
    final position = _controller.position;
    if ((position.pixels - position.maxScrollExtent).abs() < 0.5) return;
    _jumping = true;
    try {
      _controller.jumpTo(position.maxScrollExtent);
    } finally {
      _jumping = false;
    }
  }

  CodeLabProtocolPane get pane => widget.pane;

  /// Ширина колонки: `null` — гибкая (по умолчанию колонка тега), иначе
  /// фиксированная.
  double? _width(int column) {
    final base = _baseWidth(column);
    return base == null ? null : base * _scale;
  }

  double? _baseWidth(int column) {
    final widths = pane.columnWidths;
    if (widths != null) return column < widths.length ? widths[column] : 72;
    if (column == pane.tagColumn) return null;
    return pane.columns[column].isEmpty ? 28 : 72;
  }

  /// Во сколько раз ужаты фиксированные колонки, чтобы гибкой осталось не
  /// меньше [_minFlexible] (крупный шрифт, узкий док).
  double _scale = 1;
  static const double _minFlexible = 88;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      var fixed = 0.0;
      for (var c = 0; c < pane.columns.length; c++) {
        fixed += _baseWidth(c) ?? 0;
      }
      final room = constraints.maxWidth - _minFlexible;
      _scale = fixed > room && fixed > 0 ? math.max(0.0, room) / fixed : 1;
      return _buildTable(context);
    },
  );

  Widget _buildTable(BuildContext context) {
    final theme = FluentTheme.of(context);
    final resources = theme.resources;
    final palette = CodeLabPalette.of(theme);
    final secondary = resources.textFillColorSecondary;

    Widget cell(int column, Widget child) {
      final width = _width(column);
      // У ужатой колонки отступы тоже уменьшаются, иначе они одни шире её.
      final padded = Padding(
        padding: EdgeInsets.symmetric(
          horizontal: width == null ? 10 : math.min(10, width / 4),
        ),
        child: child,
      );
      return width == null
          ? Expanded(child: padded)
          : SizedBox(width: width, child: padded);
    }

    final header = Container(
      height: CodeLabProtocolPane.rowExtent,
      color: resources.cardBackgroundFillColorSecondary,
      child: Row(
        children: [
          for (var c = 0; c < pane.columns.length; c++)
            cell(
              c,
              CodeLabText(
                pane.columns[c],
                role: CodeLabTextRole.strong,
                maxLines: 1,
                color: secondary,
              ),
            ),
        ],
      ),
    );

    final Widget body;
    if (pane.rows.isEmpty) {
      body = Center(
        child: pane.emptyRowsText == null
            ? null
            : CodeLabText(pane.emptyRowsText!, color: secondary),
      );
    } else {
      body = ListView.builder(
        controller: _controller,
        itemExtent: CodeLabProtocolPane.rowExtent,
        itemCount: pane.rows.length,
        itemBuilder: (context, index) {
          final row = pane.rows[index];
          final tone = row.tone == null
              ? null
              : palette.toneColor(row.tone!, theme);
          return Semantics(
            key: ValueKey('protocol-row-${row.id}'),
            container: true,
            button: true,
            selected: row.selected,
            child: CodeLabPressable(
              onPressed: () => pane.onRowSelected(row.id),
              builder: (context, hovered, focused) => DecoratedBox(
                decoration: BoxDecoration(
                  color: row.selected
                      ? palette.selection
                      : hovered
                      ? resources.subtleFillColorSecondary
                      : null,
                  border: Border(
                    top: BorderSide(color: resources.dividerStrokeColorDefault),
                  ),
                ),
                child: Row(
                  children: [
                    for (var c = 0; c < pane.columns.length; c++)
                      cell(
                        c,
                        LayoutBuilder(
                          builder: (context, cell) => Row(
                            children: [
                              Flexible(
                                child: CodeLabText(
                                  c < row.cells.length ? row.cells[c] : '',
                                  role: CodeLabTextRole.caption,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  color: c == pane.toneColumn ? tone : null,
                                ),
                              ),
                              if (c == pane.tagColumn && row.tag != null) ...[
                                const SizedBox(width: 6),
                                // Тег сжимается с многоточием: не больше 60 %
                                // ширины ячейки, чтобы тексту остался
                                // видимый кусок (док 360 px, русский тег).
                                ConstrainedBox(
                                  constraints: BoxConstraints(
                                    maxWidth: cell.maxWidth * 0.6,
                                  ),
                                  child: DefaultTextStyle.merge(
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    softWrap: false,
                                    child: CodeLabBadge(label: row.tag!),
                                  ),
                                ),
                              ],
                            ],
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ),
          );
        },
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        header,
        Expanded(child: body),
      ],
    );
  }
}

class _Detail extends StatelessWidget {
  const _Detail({required this.detail});

  final CodeLabProtocolDetail detail;

  @override
  Widget build(BuildContext context) {
    final theme = FluentTheme.of(context);
    final resources = theme.resources;
    final palette = CodeLabPalette.of(theme);
    final strings = codeLabStringsOf(context);
    final mono = CodeLabText.styleOf(context, CodeLabTextRole.mono);
    final info = detail.info;
    final segments = detail.segments;
    final fields = detail.fields;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 8, 12, 4),
          child: Row(
            children: [
              Flexible(
                flex: 2,
                child: CodeLabText(
                  detail.title,
                  role: CodeLabTextRole.strong,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              // Теги переносятся, а не выталкивают `Copy` за край панели
              // (док 360 px, длинные подписи).
              Expanded(
                flex: 3,
                child: Wrap(
                  alignment: WrapAlignment.end,
                  spacing: 6,
                  runSpacing: 4,
                  children: [
                    for (final tag in detail.tags)
                      CodeLabBadge(label: tag.label, tone: tag.tone),
                  ],
                ),
              ),
              const SizedBox(width: 6),
              if (detail.onCopy != null)
                Button(
                  onPressed: detail.onCopy,
                  child: Text(strings.codeLabActionCopy),
                ),
            ],
          ),
        ),
        Expanded(
          child: SingleChildScrollView(
            padding: const EdgeInsets.only(bottom: 12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (info != null && (info.title.isNotEmpty))
                  Padding(
                    padding: const EdgeInsets.fromLTRB(12, 4, 12, 0),
                    child: _InfoBar(info: info),
                  ),
                if (segments != null)
                  Container(
                    margin: const EdgeInsets.fromLTRB(12, 8, 12, 0),
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 10,
                    ),
                    decoration: BoxDecoration(
                      color: resources.cardBackgroundFillColorSecondary,
                      border: Border.all(
                        color: resources.dividerStrokeColorDefault,
                      ),
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: SingleChildScrollView(
                      scrollDirection: Axis.horizontal,
                      child: Text.rich(
                        TextSpan(
                          style: mono?.copyWith(fontSize: 12, height: 1.5),
                          children: [
                            for (final segment in segments)
                              segment.masked
                                  ? TextSpan(
                                      text: strings.codeLabProtocolMasked,
                                      style: TextStyle(color: palette.warning),
                                    )
                                  : TextSpan(text: segment.text),
                          ],
                        ),
                        softWrap: false,
                      ),
                    ),
                  ),
                if (fields != null)
                  Padding(
                    padding: const EdgeInsets.all(12),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        for (final field in fields) _Field(field: field),
                      ],
                    ),
                  ),
                if (detail.note != null)
                  Padding(
                    padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
                    child: CodeLabText(
                      detail.note!,
                      role: CodeLabTextRole.caption,
                      color: resources.textFillColorSecondary,
                    ),
                  ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

class _Field extends StatelessWidget {
  const _Field({required this.field});

  final CodeLabProtocolField field;

  @override
  Widget build(BuildContext context) {
    final secondary = FluentTheme.of(context).resources.textFillColorSecondary;
    Widget? link;
    if (field.linkLabel != null) {
      link = HyperlinkButton(
        onPressed: field.onLink,
        child: Text(field.linkLabel!),
      );
      if (field.onLink == null && field.linkUnavailableHint != null) {
        link = Tooltip(message: field.linkUnavailableHint!, child: link);
      }
    }
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 160,
            child: CodeLabText(
              field.label,
              role: CodeLabTextRole.caption,
              color: secondary,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Wrap(
              crossAxisAlignment: WrapCrossAlignment.center,
              spacing: 8,
              children: [
                CodeLabText(field.value, role: CodeLabTextRole.caption),
                ?link,
              ],
            ),
          ),
        ],
      ),
    );
  }
}
