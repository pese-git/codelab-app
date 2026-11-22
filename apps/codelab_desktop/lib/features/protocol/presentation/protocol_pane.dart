import 'dart:async';
import 'dart:math' as math;

import 'package:codelab_ui/codelab_ui.dart';
import 'package:fluent_ui/fluent_ui.dart';
import 'package:flutter/foundation.dart' show defaultTargetPlatform;
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:structured_log/structured_log.dart' show LogLevel;

import '../../../app/app_scope.dart';
import '../../../l10n/l10n.dart';
import '../../workbench/presentation/widgets/debug_log_viewer_dialog.dart';
import '../application/protocol_pane_cubit.dart';
import '../application/protocol_pane_state.dart';
import '../application/protocol_pane_view.dart';

/// Панель Protocol дока: кадры ACP и записи журнала (design.md change
/// `redesign-protocol-pane`, D1, D6, D7, D8, D11, D12).
///
/// Почему виджет тонкий: данные строит маппер `protocol_pane_view.dart` из
/// состояния `ProtocolPaneCubit`, раскладку и таблицу рисует организм кита
/// `CodeLabProtocolPane`; виджет только связывает их, переводит подписи
/// элементов управления и держит сочетания Alt-навигации.
///
/// Для чего: единственное тело вкладки Protocol. Действия шапки (`Trace`,
/// `Pause`, `Clear`, `Export…`) строит [WorkbenchProtocolActions] и передаёт в
/// `CodeLabDockTab.actions`, потому что они живут в строке вкладок.
///
/// Как использовать: `const WorkbenchProtocolPane()` внутри дока; Cubit берётся
/// из `BlocProvider` корня. Alt+←/→ и Alt+↑/↓ действуют, когда фокус внутри
/// панели и не в текстовом поле (DSK-18); фокус панель берёт по нажатию
/// указателя в любом её месте.
class WorkbenchProtocolPane extends StatefulWidget {
  const WorkbenchProtocolPane({super.key});

  @override
  State<WorkbenchProtocolPane> createState() => _WorkbenchProtocolPaneState();
}

class _WorkbenchProtocolPaneState extends State<WorkbenchProtocolPane> {
  final _focus = FocusNode(debugLabel: 'protocol-pane');

  @override
  void dispose() {
    _focus.dispose();
    super.dispose();
  }

  /// Alt-навигация (D11). В поле поиска Alt+←/→ двигают курсор по словам на
  /// macOS, поэтому там сочетание не перехватывается.
  KeyEventResult _onKey(FocusNode node, KeyEvent event) {
    if (event is KeyUpEvent) return KeyEventResult.ignored;
    final inTextField =
        FocusManager.instance.primaryFocus?.context
            ?.findAncestorWidgetOfExactType<EditableText>() !=
        null;
    if (inTextField) return KeyEventResult.ignored;
    final cubit = context.read<ProtocolPaneCubit>();
    final shortcut = cubit.state.view == ProtocolView.frames
        ? CodeLabShortcut.protocolFrameMove
        : CodeLabShortcut.protocolRecordMove;
    final keyboard = HardwareKeyboard.instance;
    // Порядок комбинаций каталога — «предыдущий / следующий» (D11).
    if (shortcut.combos[0].accepts(event, keyboard)) {
      cubit.selectPrevious();
      return KeyEventResult.handled;
    }
    if (shortcut.combos[1].accepts(event, keyboard)) {
      cubit.selectNext();
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  @override
  Widget build(BuildContext context) {
    final cubit = context.read<ProtocolPaneCubit>();
    return Listener(
      onPointerDown: (_) => _focus.requestFocus(),
      child: Focus(
        focusNode: _focus,
        onKeyEvent: _onKey,
        child: BlocBuilder<ProtocolPaneCubit, ProtocolPaneState>(
          builder: (context, state) => _buildPane(context, cubit, state),
        ),
      ),
    );
  }

  Widget _buildPane(
    BuildContext context,
    ProtocolPaneCubit cubit,
    ProtocolPaneState state,
  ) {
    final l10n = context.l10n;
    final platform = defaultTargetPlatform;
    final frames = state.view == ProtocolView.frames;
    String keys(CodeLabShortcut shortcut) =>
        '${shortcut.combos[0].compactFor(platform)} / '
        '${shortcut.combos[1].compactFor(platform)}';

    String? connectionTag(String? tag) =>
        tag == null ? null : l10n.protocolConnectionTag;

    final List<CodeLabProtocolTableRow> rows;
    final CodeLabProtocolDetail? detail;
    final String emptyText;
    final int total;
    if (frames) {
      final selected = state.selectedFrame;
      rows = [
        for (final frame in state.visibleFrames)
          _localized(
            protocolFrameRow(frame, selected: selected?.seq == frame.seq),
            connectionTag,
          ),
      ];
      detail = selected == null
          ? null
          : protocolFrameDetail(
              selected,
              basePolicy: cubit.basePolicy,
              traceEnabled: state.traceEnabled,
              l10n: l10n,
              onCopy: () => unawaited(
                cubit.guarded(
                  'copy',
                  () => Clipboard.setData(
                    ClipboardData(text: protocolFrameCopyText(selected)),
                  ),
                ),
              ),
            );
      total = state.framesCount;
      emptyText = total == 0
          ? l10n.protocolEmptyFrames
          : l10n.protocolNoFramesMatch;
    } else {
      final selected = state.selectedRecord;
      rows = [
        for (var i = 0; i < state.visibleRecords.length; i++)
          _localized(
            protocolRecordRow(
              state.visibleRecords[i],
              index: i,
              selected: identical(state.visibleRecords[i], selected),
            ),
            connectionTag,
          ),
      ];
      detail = selected == null
          ? null
          : protocolRecordDetail(
              selected,
              l10n: l10n,
              frameAvailable: state.selectedRecordHasFrame,
              onShowFrame: () => cubit.showFrameOfRecord(selected),
              onCopy: () => unawaited(
                cubit.guarded(
                  'copy',
                  () => Clipboard.setData(
                    ClipboardData(text: protocolRecordCopyText(selected)),
                  ),
                ),
              ),
            );
      total = state.logCount;
      emptyText = total == 0
          ? l10n.protocolEmptyRecords
          : l10n.protocolNoRecordsMatch;
    }

    return CodeLabProtocolPane(
      view: frames ? CodeLabProtocolView.frames : CodeLabProtocolView.log,
      onViewChanged: (view) => cubit.selectView(
        view == CodeLabProtocolView.frames
            ? ProtocolView.frames
            : ProtocolView.log,
      ),
      framesCount: state.framesCount,
      logCount: state.logCount,
      viewHint: frames
          ? l10n.protocolHintFrames(keys(CodeLabShortcut.protocolFrameMove))
          : l10n.protocolHintRecords(keys(CodeLabShortcut.protocolRecordMove)),
      filters: frames
          ? _FrameFilters(state: state, cubit: cubit)
          : _LogFilters(state: state, cubit: cubit),
      // Узкие фиксированные колонки по содержимому (измеряются шрифтом темы
      // и масштабом текста), гибкая — метод или событие: в доке 360 px ей
      // должно остаться место (D12), а время и заголовки не обрезаются.
      columnWidths: frames
          ? [
              28,
              null,
              _columnWidth(context, [l10n.protocolColumnId], sample: '0000'),
              _columnWidth(context, [
                l10n.protocolColumnTime,
              ], sample: '00:00:00'),
            ]
          : [
              _columnWidth(context, [
                l10n.protocolColumnTime,
              ], sample: '00:00:00.000'),
              _columnWidth(context, [
                l10n.protocolColumnLevel,
              ], sample: 'CRITICAL'),
              _columnWidth(context, [l10n.protocolColumnCategory]),
              null,
            ],
      columns: frames
          ? [
              '',
              l10n.protocolColumnMethod,
              l10n.protocolColumnId,
              l10n.protocolColumnTime,
            ]
          : [
              l10n.protocolColumnTime,
              l10n.protocolColumnLevel,
              l10n.protocolColumnCategory,
              l10n.protocolColumnEvent,
            ],
      // Frames: тон и тег — у колонки Method; Log: тон красит Level, тег
      // `connection` стоит у Event (D12).
      toneColumn: 1,
      tagColumn: frames ? 1 : 3,
      rows: rows,
      onRowSelected: (id) {
        if (frames) {
          final frame = state.visibleFrames
              .where((f) => '${f.seq}' == id)
              .firstOrNull;
          if (frame != null) cubit.selectFrame(frame);
        } else {
          final index = int.tryParse(id);
          if (index != null && index < state.visibleRecords.length) {
            cubit.selectRecord(state.visibleRecords[index]);
          }
        }
      },
      emptyRowsText: emptyText,
      notices: [
        if (state.focusedSessionId == null)
          CodeLabProtocolInfo(
            title: frames
                ? l10n.protocolNoFocusFrames
                : l10n.protocolNoFocusRecords,
            message: '',
          ),
        if (state.saveFailed)
          CodeLabProtocolInfo(
            title: l10n.protocolSaveFailed,
            message: '',
            tone: CodeLabTone.danger,
          ),
      ],
      detail: detail,
      // Хвост (D12): на паузе таблица не следует за потоком; область — сессия
      // в фокусе, её смена прыгает к последней строке.
      followTail: !(frames ? state.framesPaused : state.logPaused),
      tailScope: state.focusedSessionId,
      splitFraction: frames ? state.framesSplit : state.logSplit,
      onSplitChanged: cubit.setSplit,
      footer: l10n.protocolFooter(
        CodeLabShortcut.toggleProtocol.combos.single.compactFor(platform),
      ),
    );
  }

  CodeLabProtocolTableRow _localized(
    CodeLabProtocolTableRow row,
    String? Function(String?) tag,
  ) => CodeLabProtocolTableRow(
    id: row.id,
    cells: row.cells,
    tone: row.tone,
    selected: row.selected,
    tag: tag(row.tag),
  );
}

/// Поле поиска строки фильтров: текст берётся из состояния Cubit, чтобы
/// фильтр пережил закрытие вкладки и смену вида.
/// Ширина фиксированной колонки: самый широкий из заголовков [headers]
/// (жирным) и образца [sample] (обычным кеглем таблицы), плюс отступы ячейки
/// (по 10 px) и запас. Измерение — шрифтом темы и масштабом текста, поэтому
/// время и заголовки en и ru не обрезаются в доке 360 px (ручной смок change
/// `redesign-protocol-pane`).
double _columnWidth(
  BuildContext context,
  List<String> headers, {
  String? sample,
}) {
  double measure(String text, CodeLabTextRole role) {
    final painter = TextPainter(
      text: TextSpan(text: text, style: CodeLabText.styleOf(context, role)),
      textDirection: TextDirection.ltr,
      textScaler: MediaQuery.textScalerOf(context),
      maxLines: 1,
    )..layout();
    final width = painter.width;
    painter.dispose();
    return width;
  }

  var widest = sample == null ? 0.0 : measure(sample, CodeLabTextRole.caption);
  for (final header in headers) {
    widest = math.max(widest, measure(header, CodeLabTextRole.strong));
  }
  return (widest + 20 + 6).ceilToDouble();
}

class _SearchBox extends StatefulWidget {
  const _SearchBox({
    required this.text,
    required this.placeholder,
    required this.onChanged,
  });

  final String text;
  final String placeholder;
  final ValueChanged<String> onChanged;

  @override
  State<_SearchBox> createState() => _SearchBoxState();
}

class _SearchBoxState extends State<_SearchBox> {
  late final _controller = TextEditingController(text: widget.text);

  @override
  void didUpdateWidget(_SearchBox oldWidget) {
    super.didUpdateWidget(oldWidget);
    // Смена вида подставляет поиск другого вида.
    if (_controller.text != widget.text) {
      _controller.text = widget.text;
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => TextBox(
    key: const ValueKey('protocol-search'),
    controller: _controller,
    placeholder: widget.placeholder,
    onChanged: widget.onChanged,
  );
}

class _FrameFilters extends StatelessWidget {
  const _FrameFilters({required this.state, required this.cubit});

  final ProtocolPaneState state;
  final ProtocolPaneCubit cubit;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final filter = state.frameFilter;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _SearchBox(
          text: filter.query,
          placeholder: l10n.protocolSearchFramesHint,
          onChanged: cubit.setFrameQuery,
        ),
        const SizedBox(height: 6),
        Wrap(
          spacing: 6,
          runSpacing: 6,
          children: [
            ToggleButton(
              checked: filter.showRequests,
              onChanged: cubit.setShowRequests,
              child: Text(l10n.protocolFilterRequests),
            ),
            ToggleButton(
              checked: filter.showNotifications,
              onChanged: cubit.setShowNotifications,
              child: Text(l10n.protocolFilterNotifications),
            ),
            ToggleButton(
              checked: filter.errorsOnly,
              onChanged: cubit.setErrorsOnly,
              child: Text(l10n.protocolFilterErrorsOnly),
            ),
          ],
        ),
      ],
    );
  }
}

class _LogFilters extends StatelessWidget {
  const _LogFilters({required this.state, required this.cubit});

  final ProtocolPaneState state;
  final ProtocolPaneCubit cubit;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final filter = state.logFilter;
    final categories = state.logCategories;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _SearchBox(
          text: filter.query,
          placeholder: l10n.protocolSearchLogHint,
          onChanged: cubit.setLogQuery,
        ),
        const SizedBox(height: 6),
        Wrap(
          spacing: 6,
          runSpacing: 6,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            ComboBox<String?>(
              value: filter.category,
              // Для значения `null` («все») ComboBox не находит пункт меню и
              // показал бы пустое поле: подпись задаёт `placeholder`.
              placeholder: Text(l10n.protocolAllCategories),
              items: [
                ComboBoxItem<String?>(
                  value: null,
                  child: Text(l10n.protocolAllCategories),
                ),
                for (final category in categories)
                  ComboBoxItem<String?>(value: category, child: Text(category)),
              ],
              onChanged: cubit.setLogCategory,
            ),
            ComboBox<LogLevel?>(
              value: filter.minLevel,
              placeholder: Text(l10n.protocolAllLevels),
              items: [
                ComboBoxItem<LogLevel?>(
                  value: null,
                  child: Text(l10n.protocolAllLevels),
                ),
                for (final level in LogLevel.values)
                  ComboBoxItem<LogLevel?>(
                    value: level,
                    child: Text(level.name.toUpperCase()),
                  ),
              ],
              onChanged: cubit.setLogMinLevel,
            ),
            Tooltip(
              message: l10n.protocolExpand,
              child: IconButton(
                key: const ValueKey('protocol-log-expand'),
                icon: const Icon(FluentIcons.full_screen, size: 14),
                onPressed: () => unawaited(
                  cubit.guarded(
                    'expand',
                    () => DebugLogViewerDialog.show(
                      context,
                      codeLabDependenciesOf(context).logBuffer,
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ],
    );
  }
}

const _compactPadding = WidgetStatePropertyAll(
  EdgeInsets.symmetric(horizontal: 8, vertical: 4),
);
const _compactButton = ButtonStyle(padding: _compactPadding);

/// Действия вкладки Protocol в строке вкладок дока: `Trace` (только в
/// release-сборке), `Pause`/`Resume`, `Clear`, `Export…` (design.md change
/// `redesign-protocol-pane`, D1, D10, D17).
///
/// Почему отдельный виджет: действия стоят в шапке дока, а не в теле панели,
/// и читают то же состояние Cubit; `CodeLabDockTab.actions` показывает их
/// только у активной вкладки. Как использовать: передать
/// `actions: const [WorkbenchProtocolActions()]` вкладке Protocol.
class WorkbenchProtocolActions extends StatelessWidget {
  const WorkbenchProtocolActions({super.key});

  Future<bool> _confirmExport(BuildContext context) async {
    final l10n = context.l10n;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialog) => ContentDialog(
        title: Text(l10n.protocolExportConfirmTitle),
        content: Text(l10n.protocolExportConfirmBody),
        actions: [
          Button(
            key: const ValueKey('protocol-export-cancel'),
            onPressed: () => Navigator.of(dialog).pop(false),
            child: Text(l10n.commonCancel),
          ),
          FilledButton(
            key: const ValueKey('protocol-export-confirm'),
            onPressed: () => Navigator.of(dialog).pop(true),
            child: Text(l10n.protocolExportConfirmAction),
          ),
        ],
      ),
    );
    return confirmed ?? false;
  }

  @override
  Widget build(BuildContext context) {
    final cubit = context.read<ProtocolPaneCubit>();
    final l10n = context.l10n;
    return BlocBuilder<ProtocolPaneCubit, ProtocolPaneState>(
      builder: (context, state) {
        final frames = state.view == ProtocolView.frames;
        final paused = frames ? state.framesPaused : state.logPaused;
        final empty =
            (frames ? state.visibleFrames : state.visibleRecords).isEmpty;
        // Компактные кнопки: четыре действия с вкладкой должны помещаться в
        // док 360 px (остаток прокручивает кит).
        return Row(
          mainAxisSize: MainAxisSize.min,
          spacing: 6,
          children: [
            if (state.traceAvailable)
              // Родной стиль `ToggleButton`: у нажатой кнопки акцентный фон, как
              // у фильтров. Свой `style` стёр бы его; состояние читает и
              // скринридер (`toggled`).
              Semantics(
                toggled: state.traceEnabled,
                container: true,
                child: ToggleButton(
                  key: const ValueKey('protocol-trace'),
                  checked: state.traceEnabled,
                  onChanged: cubit.setTrace,
                  child: Text(l10n.protocolTrace),
                ),
              ),
            Button(
              style: _compactButton,
              onPressed: cubit.togglePause,
              child: Text(paused ? l10n.protocolResume : l10n.protocolPause),
            ),
            Button(
              style: _compactButton,
              onPressed: cubit.clear,
              child: Text(l10n.protocolClear),
            ),
            Button(
              style: _compactButton,
              onPressed: empty
                  ? null
                  : () => unawaited(
                      cubit.guarded(
                        'export',
                        () => cubit.exportActive(
                          confirm: () => _confirmExport(context),
                        ),
                      ),
                    ),
              child: Text(l10n.protocolExport),
            ),
          ],
        );
      },
    );
  }
}
