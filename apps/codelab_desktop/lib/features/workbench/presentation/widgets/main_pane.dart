import 'dart:math' as math;

import 'package:codelab_ui/codelab_ui.dart';
import 'package:fluent_ui/fluent_ui.dart';

import '../../application/shell_cubit.dart';
import '../workbench_shell.dart' show selectPaletteCommand;
import 'connection_setup_dialog.dart';
import 'current_session_panel.dart';

class WorkbenchMainPane extends StatelessWidget {
  const WorkbenchMainPane({
    required this.state,
    required this.cubit,
    super.key,
  });

  final CodeLabShellState state;
  final CodeLabShellCubit cubit;

  @override
  Widget build(BuildContext context) {
    // Hidden once every entry is completed, not shown as "All Done" — see
    // add-plan-progress-checklist/design.md, Decisions (we don't carry
    // Zed's transcript-snapshot-on-completion behavior, so keeping it
    // visible would mean it stays until manually dismissed).
    final plan = state.currentPlan;
    final activityBarSections = <CodeLabActivityBarSection>[
      if (plan != null &&
          plan.any((entry) => entry.status != CodeLabPlanEntryStatus.completed))
        CodeLabProgressChecklist.section(
          id: 'plan',
          entries: plan,
          onDismiss: cubit.dismissPlan,
        ),
      if (state.queuedPrompts.isNotEmpty)
        CodeLabPromptQueuePanel.section(
          id: 'queue',
          items: state.queuedPrompts,
          onEdit: cubit.editQueuedPrompt,
          onDelete: cubit.deleteQueuedPrompt,
          onSendNow: cubit.sendQueuedPromptNow,
          onClearAll: cubit.clearQueuedPrompts,
        ),
    ];

    final Widget content;
    if (state.transcriptEntries.isEmpty) {
      content = LayoutBuilder(
        builder: (context, constraints) {
          return SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                CurrentSessionPanel(state: state),
                const SizedBox(height: 12),
                ConstrainedBox(
                  constraints: BoxConstraints(
                    minHeight: constraints.maxHeight > 180
                        ? constraints.maxHeight - 180
                        : 0,
                  ),
                  child: CodeLabConnectionScreen(
                    status: state.connectionStatus,
                    transportLabel: state.transportLabel,
                    profileLabel: state.profileLabel,
                    detail: state.connectionDetail,
                    description: 'Connect an ACP agent to start a session.',
                    onConnect: cubit.connect,
                    onReconnect: cubit.reconnect,
                    onConfigureConnection: () =>
                        ConnectionSetupDialog.show(context),
                  ),
                ),
              ],
            ),
          );
        },
      );
    } else {
      content = CodeLabTranscriptPanel(
        entries: state.transcriptEntries,
        viewMode: state.viewMode,
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (state.transcriptEntries.isNotEmpty) ...[
          CurrentSessionPanel(state: state),
          const SizedBox(height: 12),
        ],
        Expanded(
          child: _ContentWithActivityBar(
            content: content,
            activityBarSections: activityBarSections,
          ),
        ),
        const SizedBox(height: 12),
        CodeLabPromptComposer(
          enabled: state.isPromptEnabled,
          isSubmitting: state.isPromptSubmitting,
          canCancel: state.canCancel,
          initialPrompt: state.composerDraft,
          onSubmit: cubit.submitPrompt,
          onCancel: cubit.cancelTurn,
          commandActions: state.paletteActions,
          search: state.searchPalette,
          onCommandSelected: (action) =>
              selectPaletteCommand(context, cubit, action),
          configOptions: state.configOptions,
          onConfigOptionSelected: cubit.setSessionConfigOption,
          isRespondingToConfigOption: state.isRespondingToConfigOption,
        ),
      ],
    );
  }
}

/// Делит высоту между лентой (или экраном подключения) и activity bar.
///
/// Почему: развёрнутый план вместе с очередью и композером с рядом чипов
/// настроек не помещался в низкое окно — колонка переполнялась, а лента
/// сжималась до нуля. Это нарушало требование `agent-workbench-ui` «Full
/// checklist has a bounded, independently scrollable height»: план не должен
/// выталкивать ленту и композер.
///
/// Для чего: activity bar получает не больше [_maxActivityBarShare] высоты
/// этой области и оставляет ленте хотя бы [_minContentHeight]; не
/// поместившееся содержимое activity bar прокручивается внутри неё.
///
/// Как использовать: [WorkbenchMainPane] кладёт виджет в `Expanded` между
/// панелью сессии и композером; при пустом [activityBarSections] вся высота
/// достаётся [content].
class _ContentWithActivityBar extends StatelessWidget {
  const _ContentWithActivityBar({
    required this.content,
    required this.activityBarSections,
  });

  /// Минимальная высота ленты: в ней должна оставаться видна хотя бы одна
  /// строка записи, иначе ход агента не видно совсем.
  static const double _minContentHeight = 64;

  /// Доля высоты, которую activity bar может занять в высоком окне.
  static const double _maxActivityBarShare = 0.5;

  static const double _gap = 12;

  final Widget content;
  final List<CodeLabActivityBarSection> activityBarSections;

  @override
  Widget build(BuildContext context) {
    // Структура одна и та же с activity bar и без неё: иначе появление плана
    // или очереди переносило бы ленту в другое место дерева, и она теряла бы
    // состояние прокрутки.
    return LayoutBuilder(
      builder: (context, constraints) {
        final height = constraints.maxHeight;
        final maxActivityBarHeight = math.max(
          0.0,
          math.min(
            height * _maxActivityBarShare,
            height - _minContentHeight - _gap,
          ),
        );

        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Expanded(child: content),
            if (activityBarSections.isNotEmpty) ...[
              const SizedBox(height: _gap),
              ConstrainedBox(
                constraints: BoxConstraints(maxHeight: maxActivityBarHeight),
                // Своя прокрутка: в низком окне развёрнутый план выше
                // отведённой доли, и без неё колонка снова переполнилась бы.
                child: SingleChildScrollView(
                  child: CodeLabActivityBar(sections: activityBarSections),
                ),
              ),
            ],
          ],
        );
      },
    );
  }
}
