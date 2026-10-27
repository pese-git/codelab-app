import 'dart:async';

import 'package:fluent_ui/fluent_ui.dart';

import '../atomics/atomics.dart';
import '../molecules/molecules.dart';
import 'codelab_tool_call_tile.dart';
import 'codelab_transcript_notice.dart';
import 'codelab_transcript_row.dart';

/// Наибольшая ширина колонки переписки (артборд Main; требование
/// «Transcript reads as a conversation»).
const kTranscriptColumnMaxWidth = 760.0;

/// Пузырь пользователя — доля ширины колонки; в узкой колонке шире, чтобы
/// многострочный промпт не превращался в столбик слов (design, Risks).
const _bubbleWidthFactor = 0.78;
const _narrowBubbleWidthFactor = 0.9;
const _narrowColumnWidth = 560.0;

/// Раскрыта ли строка, если пользователь её не трогал (design D3 change
/// `redesign-transcript-rows`): мысли раскрыты во время стрима, кроме
/// `summary`; вызовы — только в `verbose`.
bool _expandedByDefault(CodeLabTranscriptRow row, CodeLabViewMode viewMode) {
  return switch (row) {
    CodeLabThoughtRow(:final streaming) => switch (viewMode) {
      CodeLabViewMode.summary => false,
      CodeLabViewMode.normal => streaming,
      CodeLabViewMode.verbose => true,
    },
    CodeLabToolCallRow() => viewMode == CodeLabViewMode.verbose,
    _ => false,
  };
}

/// Насколько близко к низу (в пикселях) лента считается «у хвоста».
///
/// Пока пользователь в пределах этого расстояния, лента следует за новыми
/// записями и прокручивается к новому pending approval; дальше — пользователь
/// читает историю, и позиция не меняется (`agent-workbench-ui`, требование
/// «Лента transcript следует за хвостом»).
const _autoScrollBottomThreshold = 80.0;

/// Лента переписки с агентом.
///
/// Почему: лента должна читаться как переписка — колонка по центру, пузырь
/// пользователя, ответ без карточки, свои виджеты для мыслей, вызовов и
/// заметок (change `redesign-transcript-rows`; §12.3.2).
///
/// Для чего: рисует [rows], следует за хвостом и прокручивается к новому
/// ожидающему одобрению. Ручное раскрытие строк хранит владелец
/// ([expansionOverrides]): строки виртуализированы, и `State` строки теряет
/// выбор при уходе с экрана (design D3).
///
/// Как использовать: хост передаёт строки и [onExpansionChanged]; без него
/// строки раскрываются только по умолчанию. Ожидающее одобрение всегда
/// раскрыто.
class CodeLabTranscriptPanel extends StatefulWidget {
  const CodeLabTranscriptPanel({
    required this.rows,
    this.expansionOverrides = const {},
    this.onExpansionChanged,
    this.emptyLabel = 'No transcript yet',
    this.viewMode = CodeLabViewMode.normal,
    super.key,
  });

  /// Ключ строки ленты по её id — для тестов и автоматизации.
  static ValueKey<String> rowKey(String id) => ValueKey('transcript-row-$id');

  final List<CodeLabTranscriptRow> rows;
  final Map<String, bool> expansionOverrides;
  final ValueChanged<({String rowId, bool expanded})>? onExpansionChanged;
  final String emptyLabel;
  final CodeLabViewMode viewMode;

  @override
  State<CodeLabTranscriptPanel> createState() => _AcpTranscriptPanelState();
}

/// Состояние ленты: владеет `ScrollController` и решает, когда двигать
/// прокрутку.
///
/// Почему: записи дописываются в конец ленты (ответы агента, карточки
/// инструментов, approval), а ленивый список сам к ним не прокручивается.
/// Для чего: два механизма прокрутки — анимированная к новому pending
/// approval и мгновенное следование за хвостом (change
/// `follow-transcript-tail`, D1–D4); оба отключаются, когда пользователь
/// прокрутил ленту вверх.
class _AcpTranscriptPanelState extends State<CodeLabTranscriptPanel> {
  final _controller = ScrollController();

  /// Пользователь прокрутил ленту вверх, дальше порога от низа, и читает
  /// историю. Меняется только прокруткой самого пользователя: рост ленты под
  /// нетронутой видимой частью не означает, что пользователь ушёл от хвоста.
  bool _isReadingHistory = false;
  bool _isUserScrolling = false;

  /// Выставлен, пока новый pending approval нужно держать в виду: ленивый
  /// список лишь оценивает высоту непостроенных записей, и реальный низ
  /// может сдвинуться уже после завершения прокрутки к нему.
  bool _isKeepingApprovalInView = false;

  /// Лента следует за хвостом: выставляется, когда обновление пришло, пока
  /// пользователь был у низа, и сбрасывается любой прокруткой пользователя
  /// (D2). Пока выставлен, лента догоняет сдвинувшийся низ так же, как для
  /// approval.
  bool _isFollowingTail = false;

  @override
  void initState() {
    super.initState();

    // Панель может появиться сразу с pending approval в первых записях (хост
    // обычно подставляет ленту, только когда записи уже есть) — предыдущей
    // сборки, с которой сравнил бы `didUpdateWidget`, нет.
    if (_pendingApprovalEntryIds(widget.rows).isNotEmpty) {
      _bringApprovalIntoView();
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  void didUpdateWidget(covariant CodeLabTranscriptPanel oldWidget) {
    super.didUpdateWidget(oldWidget);

    // Метрики контроллера ещё описывают прежнюю раскладку: после раскладки
    // новая запись уже отодвинет низ, и «был у низа» станет не отличить от
    // «читал историю» (D1).
    final wasAtTail = !_isReadingHistory && (_isFollowingTail || _isNearBottom);

    final pendingApprovalIds = _pendingApprovalEntryIds(widget.rows);
    if (pendingApprovalIds.isEmpty) {
      _isKeepingApprovalInView = false;
    }

    final newPendingApprovalIds = pendingApprovalIds.difference(
      _pendingApprovalEntryIds(oldWidget.rows),
    );
    if (newPendingApprovalIds.isNotEmpty && !_isReadingHistory) {
      // Анимация к approval важнее прыжка в этом кадре: `jumpTo` оборвал бы
      // её (D3).
      _bringApprovalIntoView();
      return;
    }

    if (wasAtTail && !identical(widget.rows, oldWidget.rows)) {
      _jumpToTail();
    }
  }

  bool get _isNearBottom {
    if (!_controller.hasClients) {
      // Первая раскладка с записями ещё не прошла: лента пуста или только
      // появилась, пользователь её не прокручивал.
      return true;
    }
    final position = _controller.position;
    return position.maxScrollExtent - position.pixels <=
        _autoScrollBottomThreshold;
  }

  void _jumpToTail() {
    _isFollowingTail = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && _controller.hasClients && _isFollowingTail) {
        _controller.jumpTo(_controller.position.maxScrollExtent);
      }
    });
  }

  void _bringApprovalIntoView() {
    _isKeepingApprovalInView = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_controller.hasClients) {
        return;
      }
      unawaited(
        _controller.animateTo(
          _controller.position.maxScrollExtent,
          duration: const Duration(milliseconds: 200),
          curve: Curves.easeOut,
        ),
      );
    });
  }

  bool _onScrollNotification(ScrollNotification notification) {
    if (notification is UserScrollNotification) {
      _isUserScrolling = true;
      _isKeepingApprovalInView = false;
      _isFollowingTail = false;
    } else if (notification is ScrollEndNotification) {
      if (_isUserScrolling) {
        _isUserScrolling = false;
        final metrics = notification.metrics;
        _isReadingHistory =
            metrics.maxScrollExtent - metrics.pixels >
            _autoScrollBottomThreshold;
      } else {
        _followMovedBottom(notification.metrics);
      }
    }
    return false;
  }

  bool _onScrollMetricsNotification(ScrollMetricsNotification notification) {
    if (!_controller.position.isScrollingNotifier.value) {
      _followMovedBottom(notification.metrics);
    }
    return false;
  }

  void _followMovedBottom(ScrollMetrics metrics) {
    final isHoldingBottom = _isKeepingApprovalInView || _isFollowingTail;
    if (!isHoldingBottom || _isReadingHistory || metrics.extentAfter <= 0) {
      return;
    }
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted &&
          _controller.hasClients &&
          (_isKeepingApprovalInView || _isFollowingTail)) {
        _controller.jumpTo(_controller.position.maxScrollExtent);
      }
    });
  }

  bool _isExpanded(CodeLabTranscriptRow row) {
    if (row is CodeLabToolCallRow && row.awaitsApproval) {
      return true;
    }
    return widget.expansionOverrides[row.id] ??
        _expandedByDefault(row, widget.viewMode);
  }

  void _toggle(String rowId, bool expanded) =>
      widget.onExpansionChanged?.call((rowId: rowId, expanded: expanded));

  @override
  Widget build(BuildContext context) {
    if (widget.rows.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: CodeLabText(widget.emptyLabel, role: CodeLabTextRole.caption),
        ),
      );
    }
    return NotificationListener<ScrollMetricsNotification>(
      onNotification: _onScrollMetricsNotification,
      child: NotificationListener<ScrollNotification>(
        onNotification: _onScrollNotification,
        child: ListView.builder(
          controller: _controller,
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
          itemCount: widget.rows.length,
          itemBuilder: (context, index) {
            final row = widget.rows[index];
            return Align(
              key: CodeLabTranscriptPanel.rowKey(row.id),
              alignment: Alignment.topCenter,
              child: ConstrainedBox(
                constraints: const BoxConstraints(
                  maxWidth: kTranscriptColumnMaxWidth,
                ),
                child: Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: _TranscriptRowView(
                    row: row,
                    expanded: _isExpanded(row),
                    onToggle: (expanded) => _toggle(row.id, expanded),
                  ),
                ),
              ),
            );
          },
        ),
      ),
    );
  }
}

Set<String> _pendingApprovalEntryIds(List<CodeLabTranscriptRow> rows) {
  return {
    for (final row in rows)
      if (row is CodeLabToolCallRow && row.awaitsApproval) row.id,
  };
}

/// Одна строка ленты: выбирает виджет по виду строки.
class _TranscriptRowView extends StatelessWidget {
  const _TranscriptRowView({
    required this.row,
    required this.expanded,
    required this.onToggle,
  });

  final CodeLabTranscriptRow row;
  final bool expanded;
  final ValueChanged<bool> onToggle;

  @override
  Widget build(BuildContext context) {
    return switch (row) {
      CodeLabUserRow(:final text) => _UserBubble(text: text),
      CodeLabAgentTextRow(:final text) => Align(
        alignment: Alignment.centerLeft,
        child: CodeLabText(text),
      ),
      CodeLabThoughtRow(:final text, :final streaming) => CodeLabThoughtBlock(
        text: text,
        streaming: streaming,
        expanded: expanded,
        onToggle: onToggle,
      ),
      final CodeLabToolCallRow call => CodeLabToolCallTile(
        row: call,
        expanded: expanded,
        onToggle: onToggle,
      ),
      final CodeLabNoticeRow notice => CodeLabTranscriptNotice(row: notice),
    };
  }
}

/// Сообщение пользователя — пузырь справа без подписи «You» (артборд Main).
class _UserBubble extends StatelessWidget {
  const _UserBubble({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    final theme = FluentTheme.of(context);
    return LayoutBuilder(
      builder: (context, constraints) {
        final factor = constraints.maxWidth < _narrowColumnWidth
            ? _narrowBubbleWidthFactor
            : _bubbleWidthFactor;
        return Align(
          alignment: Alignment.centerRight,
          child: ConstrainedBox(
            constraints: BoxConstraints(
              maxWidth: constraints.maxWidth * factor,
            ),
            child: DecoratedBox(
              decoration: BoxDecoration(
                color: theme.accentColor.withAlpha(
                  theme.brightness == Brightness.dark ? 64 : 34,
                ),
                borderRadius: const BorderRadius.only(
                  topLeft: Radius.circular(8),
                  topRight: Radius.circular(8),
                  bottomLeft: Radius.circular(8),
                  bottomRight: Radius.circular(2),
                ),
              ),
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 14,
                  vertical: 10,
                ),
                child: CodeLabText(text),
              ),
            ),
          ),
        );
      },
    );
  }
}
