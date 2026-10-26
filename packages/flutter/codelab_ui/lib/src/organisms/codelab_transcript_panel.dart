import 'dart:async';

import 'package:fluent_ui/fluent_ui.dart';

import '../atomics/atomics.dart';
import '../molecules/molecules.dart';
import 'codelab_approval_panel.dart';

enum CodeLabTranscriptEntryKind { user, agent, toolCall, approval, diagnostic }

/// Approval state carried by a [CodeLabTranscriptEntry] for the tool call it
/// belongs to — rendered inline in the entry's own row, not as a separate
/// panel outside the transcript.
sealed class CodeLabTranscriptApproval {
  const CodeLabTranscriptApproval();

  const factory CodeLabTranscriptApproval.pending({
    required CodeLabApprovalRisk risk,
    required List<CodeLabApprovalOption> options,
    required CodeLabApprovalOptionSelected onOptionSelected,
    String? reason,
    String? command,
    String? cwd,
    String? diffSummary,
    String? rawInput,
    String? selectedOptionId,
    bool enabled,
    String? approveOptionId,
    String? rejectOptionId,
    bool shortcutsEnabled,
  }) = CodeLabTranscriptApprovalPending;

  const factory CodeLabTranscriptApproval.resolved({required String label}) =
      CodeLabTranscriptApprovalResolved;
}

final class CodeLabTranscriptApprovalPending extends CodeLabTranscriptApproval {
  const CodeLabTranscriptApprovalPending({
    required this.risk,
    required this.options,
    required this.onOptionSelected,
    this.reason,
    this.command,
    this.cwd,
    this.diffSummary,
    this.rawInput,
    this.selectedOptionId,
    this.enabled = true,
    this.approveOptionId,
    this.rejectOptionId,
    this.shortcutsEnabled = true,
  });

  final CodeLabApprovalRisk risk;
  final List<CodeLabApprovalOption> options;
  final CodeLabApprovalOptionSelected onOptionSelected;
  final String? reason;
  final String? command;
  final String? cwd;
  final String? diffSummary;
  final String? rawInput;
  final String? selectedOptionId;
  final bool enabled;
  final String? approveOptionId;
  final String? rejectOptionId;
  final bool shortcutsEnabled;
}

final class CodeLabTranscriptApprovalResolved
    extends CodeLabTranscriptApproval {
  const CodeLabTranscriptApprovalResolved({required this.label});

  final String label;
}

class CodeLabTranscriptEntry {
  const CodeLabTranscriptEntry({
    required this.id,
    required this.kind,
    required this.title,
    this.body,
    this.toolCall,
    this.timestampLabel,
    this.approval,
  });

  final String id;
  final CodeLabTranscriptEntryKind kind;
  final String title;
  final String? body;
  final CodeLabToolCallSummary? toolCall;
  final String? timestampLabel;

  /// Non-null only for a [CodeLabTranscriptEntryKind.toolCall] entry that has an
  /// associated `ApprovalRequest` — pending (interactive) or resolved
  /// (compact marker).
  final CodeLabTranscriptApproval? approval;
}

/// Насколько близко к низу (в пикселях) лента считается «у хвоста».
///
/// Пока пользователь в пределах этого расстояния, лента следует за новыми
/// записями и прокручивается к новому pending approval; дальше — пользователь
/// читает историю, и позиция не меняется (`agent-workbench-ui`, требование
/// «Лента transcript следует за хвостом»).
const _autoScrollBottomThreshold = 80.0;

class CodeLabTranscriptPanel extends StatefulWidget {
  const CodeLabTranscriptPanel({
    required this.entries,
    this.emptyLabel = 'No transcript yet',
    this.viewMode = CodeLabViewMode.normal,
    super.key,
  });

  final List<CodeLabTranscriptEntry> entries;
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
    if (_pendingApprovalEntryIds(widget.entries).isNotEmpty) {
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

    final pendingApprovalIds = _pendingApprovalEntryIds(widget.entries);
    if (pendingApprovalIds.isEmpty) {
      _isKeepingApprovalInView = false;
    }

    final newPendingApprovalIds = pendingApprovalIds.difference(
      _pendingApprovalEntryIds(oldWidget.entries),
    );
    if (newPendingApprovalIds.isNotEmpty && !_isReadingHistory) {
      // Анимация к approval важнее прыжка в этом кадре: `jumpTo` оборвал бы
      // её (D3).
      _bringApprovalIntoView();
      return;
    }

    if (wasAtTail && !identical(widget.entries, oldWidget.entries)) {
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

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: FluentTheme.of(context).scaffoldBackgroundColor,
        border: Border.all(color: Colors.grey.withAlpha(54)),
        borderRadius: BorderRadius.circular(6),
      ),
      child: widget.entries.isEmpty
          ? Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: CodeLabText(
                  widget.emptyLabel,
                  role: CodeLabTextRole.caption,
                ),
              ),
            )
          : NotificationListener<ScrollMetricsNotification>(
              onNotification: _onScrollMetricsNotification,
              child: NotificationListener<ScrollNotification>(
                onNotification: _onScrollNotification,
                child: ListView.separated(
                  controller: _controller,
                  padding: const EdgeInsets.all(12),
                  itemCount: widget.entries.length,
                  separatorBuilder: (context, index) =>
                      const SizedBox(height: 10),
                  itemBuilder: (context, index) {
                    return _AcpTranscriptEntryRow(
                      entry: widget.entries[index],
                      viewMode: widget.viewMode,
                    );
                  },
                ),
              ),
            ),
    );
  }
}

Set<String> _pendingApprovalEntryIds(List<CodeLabTranscriptEntry> entries) {
  return {
    for (final entry in entries)
      if (entry.approval is CodeLabTranscriptApprovalPending) entry.id,
  };
}

class _AcpTranscriptEntryRow extends StatelessWidget {
  const _AcpTranscriptEntryRow({required this.entry, required this.viewMode});

  final CodeLabTranscriptEntry entry;
  final CodeLabViewMode viewMode;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: _backgroundColor(context),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Padding(
        padding: const EdgeInsets.all(10),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            CodeLabIcon(_icon, tone: _tone, size: 16),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: CodeLabText(
                          entry.title,
                          role: CodeLabTextRole.strong,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      if (entry.timestampLabel != null) ...[
                        const SizedBox(width: 8),
                        CodeLabText(
                          entry.timestampLabel!,
                          role: CodeLabTextRole.caption,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                    ],
                  ),
                  if (entry.body != null) ...[
                    const SizedBox(height: 6),
                    if (entry.kind == CodeLabTranscriptEntryKind.toolCall)
                      CodeLabText(
                        entry.body!,
                        maxLines: _bodyMaxLines,
                        overflow: TextOverflow.ellipsis,
                      )
                    else
                      CodeLabText(entry.body!),
                  ],
                  if (entry.toolCall != null) ...[
                    const SizedBox(height: 8),
                    _toolCallForMode(entry.toolCall!),
                  ],
                  if (entry.approval case final approval?) ...[
                    const SizedBox(height: 8),
                    _AcpTranscriptApprovalContent(approval: approval),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Color _backgroundColor(BuildContext context) {
    return switch (entry.kind) {
      CodeLabTranscriptEntryKind.user => Colors.blue.withAlpha(24),
      CodeLabTranscriptEntryKind.agent => Colors.grey.withAlpha(24),
      CodeLabTranscriptEntryKind.toolCall =>
        Colors.warningPrimaryColor.withAlpha(24),
      CodeLabTranscriptEntryKind.approval => Colors.orange.withAlpha(24),
      CodeLabTranscriptEntryKind.diagnostic => Colors.red.withAlpha(20),
    };
  }

  IconData get _icon {
    return switch (entry.kind) {
      CodeLabTranscriptEntryKind.user => FluentIcons.contact,
      CodeLabTranscriptEntryKind.agent => FluentIcons.robot,
      CodeLabTranscriptEntryKind.toolCall => FluentIcons.processing,
      CodeLabTranscriptEntryKind.approval => FluentIcons.permissions,
      CodeLabTranscriptEntryKind.diagnostic => FluentIcons.warning,
    };
  }

  CodeLabTone get _tone {
    return switch (entry.kind) {
      CodeLabTranscriptEntryKind.user => CodeLabTone.accent,
      CodeLabTranscriptEntryKind.agent => CodeLabTone.neutral,
      CodeLabTranscriptEntryKind.toolCall => CodeLabTone.warning,
      CodeLabTranscriptEntryKind.approval => CodeLabTone.warning,
      CodeLabTranscriptEntryKind.diagnostic => CodeLabTone.danger,
    };
  }

  int get _bodyMaxLines {
    return switch (viewMode) {
      CodeLabViewMode.summary => 1,
      CodeLabViewMode.normal => 4,
      CodeLabViewMode.verbose => 8,
    };
  }

  Widget _toolCallForMode(CodeLabToolCallSummary toolCall) {
    return CodeLabToolCallSummary(
      name: toolCall.name,
      status: toolCall.status,
      target: toolCall.target,
      detail: toolCall.detail,
      viewMode: viewMode,
    );
  }
}

class _AcpTranscriptApprovalContent extends StatelessWidget {
  const _AcpTranscriptApprovalContent({required this.approval});

  final CodeLabTranscriptApproval approval;

  @override
  Widget build(BuildContext context) {
    return switch (approval) {
      CodeLabTranscriptApprovalPending(
        :final risk,
        :final reason,
        :final command,
        :final cwd,
        :final diffSummary,
        :final rawInput,
        :final options,
        :final selectedOptionId,
        :final enabled,
        :final approveOptionId,
        :final rejectOptionId,
        :final shortcutsEnabled,
        :final onOptionSelected,
      ) =>
        CodeLabApprovalPanel(
          bordered: false,
          optionsLayout: CodeLabApprovalOptionsLayout.compactRow,
          risk: risk,
          reason: reason,
          command: command,
          cwd: cwd,
          diffSummary: diffSummary,
          rawInput: rawInput,
          options: options,
          selectedOptionId: selectedOptionId,
          enabled: enabled,
          approveOptionId: approveOptionId,
          rejectOptionId: rejectOptionId,
          shortcutsEnabled: shortcutsEnabled,
          onOptionSelected: onOptionSelected,
        ),
      CodeLabTranscriptApprovalResolved(:final label) => Row(
        children: [
          const CodeLabIcon(
            FluentIcons.check_mark,
            tone: CodeLabTone.success,
            size: 13,
          ),
          const SizedBox(width: 6),
          CodeLabText(label, role: CodeLabTextRole.caption),
        ],
      ),
    };
  }
}
