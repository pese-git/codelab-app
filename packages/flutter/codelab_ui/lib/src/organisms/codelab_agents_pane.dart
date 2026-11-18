import 'package:fluent_ui/fluent_ui.dart';

import '../atomics/atomics.dart';
import '../atomics/codelab_pressable.dart';
import '../l10n/codelab_localizations.dart';
import '../l10n/strings.dart';
import '../rendering/escape_for_display.dart';
import 'codelab_compact_call_line.dart';
import 'codelab_tool_call_tile.dart';
import 'codelab_transcript_row.dart';

/// Состояние строки панели Agents (D33, D49 Т10). Порядок значений — порядок
/// счётчиков в заголовке: `running · waiting for approval · done · failed ·
/// cancelled`.
enum CodeLabAgentRowState {
  running,
  waitingForApproval,
  done,
  failed,
  cancelled,
}

/// Метка пункта списка `#N` у строки субагента и подсказка к ней (D49 Т6).
final class CodeLabAgentItemRef {
  const CodeLabAgentItemRef({required this.label, this.hint});

  /// Готовая метка, например `#2`.
  final String label;

  /// Заголовок пункта плана; `null` — пункта нет в плане, подсказки нет.
  final String? hint;
}

/// Строка панели Agents: данные уже отформатированы app (D49 Т9, Т10).
///
/// Поля без данных — `null`/пусто — не рисуются, без заглушек. [id] —
/// `toolCallId` вызова `agent`: по нему ключи `agents-row-<id>` и действия.
final class CodeLabAgentRow {
  const CodeLabAgentRow({
    required this.id,
    required this.depth,
    required this.type,
    required this.title,
    required this.state,
    this.time,
    this.calls,
    this.tokens,
    this.lastAction,
    this.items = const [],
  });

  final String id;

  /// Глубина: 1 — строка верхнего уровня; отступ растёт с глубиной.
  final int depth;
  final String type;
  final String title;
  final CodeLabAgentRowState state;
  final String? time;
  final String? calls;
  final String? tokens;
  final String? lastAction;
  final List<CodeLabAgentItemRef> items;
}

/// Панель Agents v1: обзор субагентов сессии (D33, D49 Т10; spec
/// agent-workbench-ui «Панель Agents v1»).
///
/// Почему: при трёх параллельных детях и глубине до 3 в длинной ленте трудно
/// найти, кто работает и кто ждёт решения пользователя; строки `agent` в ленте
/// свёрнуты (D27). Панель — навигация по уже показанным данным, а не вторая
/// панель решения: кнопок «Allow/Reject» и «Stop» в ней нет (PERM-4, D33).
///
/// Для чего: заголовок «Subagents» со счётчиками [counts], строки [rows] с
/// отступом по глубине и дерево шагов [steps] выбранной строки [selectedId],
/// раскрытое целиком на тех же компактных строках, что хвост ленты. Виджет
/// ничего не считает и не форматирует (`codelab_ui/AGENTS.md` §2): время,
/// число вызовов, токены, метки `#N` и счётчики приходят готовыми, а решения —
/// «опасно ли», «ждёт ли одобрения» — принимает app. Тексты модели (тип,
/// заголовок, последнее действие, подсказка `#N`, детали шагов) выводятся с
/// видимыми escape-символами (`escapeForDisplay`, AGENTS.md §10).
///
/// Как использовать: app строит [rows], [steps] (те же `CodeLabToolCallRow`,
/// что и в ленте) и колбэки. [onSelect] — выбор строки; [onGoToApproval] —
/// переход к блоку одобрения в ленте (строка в состоянии
/// `waitingForApproval` или шаг с `awaitsRootDecision`/`approval`);
/// [onShowInTranscript] — показ строки в ленте. Все колбэки получают id
/// (`toolCallId` у строки; у шага — id элемента ленты `<ход>/tool-…`). Ключи для тестов и автоматизации:
/// `agents-row-<id>`, `agents-go-to-approval-<id>` (у строки),
/// `agents-step-go-to-approval-<id>` (у шага; колбэк [onStepGoToApproval],
/// по умолчанию [onGoToApproval]),
/// `agents-show-in-transcript-<id>`, `agents-steps`.
class CodeLabAgentsPane extends StatelessWidget {
  const CodeLabAgentsPane({
    required this.rows,
    this.counts = const {},
    this.selectedId,
    this.steps = const [],
    this.onSelect,
    this.onGoToApproval,
    this.onStepGoToApproval,
    this.onShowInTranscript,
    super.key,
  });

  /// Ключ строки панели.
  static ValueKey<String> rowKey(String id) => ValueKey('agents-row-$id');

  /// Ключ действия «Go to approval» строки панели (у шага — [stepGoToApprovalKey]).
  static ValueKey<String> goToApprovalKey(String id) =>
      ValueKey('agents-go-to-approval-$id');

  /// Ключ действия «Go to approval» шага дерева (`agents-step-go-to-approval-<id>`):
  /// отдельный от [goToApprovalKey] строки, чтобы id вызова-шага не
  /// совпал с id строки панели.
  static ValueKey<String> stepGoToApprovalKey(String id) =>
      ValueKey('agents-step-go-to-approval-$id');

  /// Ключ действия «Show in transcript» строки.
  static ValueKey<String> showInTranscriptKey(String id) =>
      ValueKey('agents-show-in-transcript-$id');

  /// Ключ дерева шагов выбранной строки.
  static const stepsKey = ValueKey('agents-steps');

  /// Шаг отступа строки на уровень глубины.
  static const indentStep = 16.0;

  final List<CodeLabAgentRow> rows;
  final Map<CodeLabAgentRowState, int> counts;
  final String? selectedId;

  /// Дерево шагов выбранной строки: вложенные [CodeLabToolCallRow.children]
  /// показываются раскрытыми целиком. Показывается, только когда выбрана
  /// строка ([selectedId] не `null`).
  final List<CodeLabTranscriptRow> steps;
  final ValueChanged<String>? onSelect;
  final ValueChanged<String>? onGoToApproval;

  /// «Go to approval» шага дерева (id вызова-шага). `null` — шаг использует
  /// [onGoToApproval].
  final ValueChanged<String>? onStepGoToApproval;
  final ValueChanged<String>? onShowInTranscript;

  /// Заголовок со счётчиками: нули опускаются, порядок задаёт перечисление
  /// [CodeLabAgentRowState]. Счётчик — отдельное сообщение каталога с ICU
  /// `plural`, а не склейка числа и слова (D8).
  String _header(BuildContext context) {
    final strings = codeLabStringsOf(context);
    final parts = [
      for (final state in CodeLabAgentRowState.values)
        if ((counts[state] ?? 0) > 0) state.countLabel(strings, counts[state]!),
    ];
    return [strings.codeLabAgentsTitle, ...parts].join(' · ');
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
          child: CodeLabText(_header(context), role: CodeLabTextRole.strong),
        ),
        Expanded(
          child: SingleChildScrollView(
            padding: const EdgeInsets.only(bottom: 12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                for (final row in rows)
                  _AgentRowView(
                    row: row,
                    selected: row.id == selectedId,
                    onSelect: onSelect,
                    onGoToApproval: onGoToApproval,
                    onShowInTranscript: onShowInTranscript,
                  ),
                if (selectedId != null && steps.isNotEmpty)
                  _StepsTree(
                    steps: steps,
                    onGoToApproval: onStepGoToApproval ?? onGoToApproval,
                  ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

extension on CodeLabAgentRowState {
  /// Слово состояния в строке (смысл не только цветом).
  String word(CodeLabLocalizations strings) => switch (this) {
    CodeLabAgentRowState.running => strings.codeLabAgentsStateRunning,
    CodeLabAgentRowState.waitingForApproval =>
      strings.codeLabAgentsStateWaiting,
    CodeLabAgentRowState.done => strings.codeLabAgentsStateDone,
    CodeLabAgentRowState.failed => strings.codeLabAgentsStateFailed,
    CodeLabAgentRowState.cancelled => strings.codeLabAgentsStateCancelled,
  };

  /// Счётчик состояния для заголовка: «2 running», «2 выполняются».
  String countLabel(CodeLabLocalizations strings, int count) => switch (this) {
    CodeLabAgentRowState.running => strings.codeLabAgentsCountRunning(count),
    CodeLabAgentRowState.waitingForApproval =>
      strings.codeLabAgentsCountWaiting(count),
    CodeLabAgentRowState.done => strings.codeLabAgentsCountDone(count),
    CodeLabAgentRowState.failed => strings.codeLabAgentsCountFailed(count),
    CodeLabAgentRowState.cancelled => strings.codeLabAgentsCountCancelled(
      count,
    ),
  };

  CodeLabTone get tone => switch (this) {
    CodeLabAgentRowState.running => CodeLabTone.accent,
    CodeLabAgentRowState.waitingForApproval => CodeLabTone.warning,
    CodeLabAgentRowState.done => CodeLabTone.success,
    CodeLabAgentRowState.failed => CodeLabTone.danger,
    CodeLabAgentRowState.cancelled => CodeLabTone.neutral,
  };
}

/// Одна строка панели: тип, заголовок, слово состояния, готовые поля, метки
/// `#N` и действия. Поля без данных не рисуются, без заглушек (spec
/// «Панель Agents v1»).
class _AgentRowView extends StatelessWidget {
  const _AgentRowView({
    required this.row,
    required this.selected,
    this.onSelect,
    this.onGoToApproval,
    this.onShowInTranscript,
  });

  final CodeLabAgentRow row;
  final bool selected;
  final ValueChanged<String>? onSelect;
  final ValueChanged<String>? onGoToApproval;
  final ValueChanged<String>? onShowInTranscript;

  @override
  Widget build(BuildContext context) {
    final theme = FluentTheme.of(context);
    final facts = [?row.time, ?row.calls, ?row.tokens];
    // `container`: действия внутри строки остаются отдельными узлами
    // семантики (кнопки), а строка — кнопка с признаком выбора.
    return Semantics(
      container: true,
      button: true,
      selected: selected,
      child: CodeLabPressable(
        key: CodeLabAgentsPane.rowKey(row.id),
        onPressed: onSelect == null ? null : () => onSelect!(row.id),
        builder: (context, hovered, focused) {
          final background = selected
              ? theme.accentColor.withAlpha(
                  theme.brightness == Brightness.dark ? 56 : 30,
                )
              : hovered || focused
              ? theme.resources.subtleFillColorSecondary
              : null;
          return DecoratedBox(
            decoration: BoxDecoration(color: background),
            child: Padding(
              padding: EdgeInsets.fromLTRB(
                16 +
                    (row.depth - 1).clamp(0, 99) * CodeLabAgentsPane.indentStep,
                6,
                16,
                6,
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    children: [
                      CodeLabText(
                        escapeForDisplay(row.type),
                        role: CodeLabTextRole.mono,
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: CodeLabText(
                          escapeForDisplay(row.title),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      const SizedBox(width: 8),
                      // Flexible: в узком доке длинное слово состояния усекается
                      // (у бейджа ellipsis), а не вылезает за строку.
                      Flexible(
                        child: CodeLabBadge(
                          label: row.state.word(codeLabStringsOf(context)),
                          tone: row.state.tone,
                        ),
                      ),
                    ],
                  ),
                  if (facts.isNotEmpty || row.items.isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.only(top: 2),
                      child: Wrap(
                        spacing: 12,
                        runSpacing: 2,
                        crossAxisAlignment: WrapCrossAlignment.center,
                        children: [
                          for (final fact in facts)
                            CodeLabText(fact, role: CodeLabTextRole.caption),
                          for (final item in row.items) _ItemLabel(item: item),
                        ],
                      ),
                    ),
                  if (row.lastAction case final action?)
                    Padding(
                      padding: const EdgeInsets.only(top: 2),
                      child: CodeLabText(
                        escapeForDisplay(action),
                        role: CodeLabTextRole.caption,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  Wrap(
                    spacing: 8,
                    children: [
                      if (row.state == CodeLabAgentRowState.waitingForApproval)
                        _ActionLink(
                          key: CodeLabAgentsPane.goToApprovalKey(row.id),
                          label: codeLabStringsOf(
                            context,
                          ).codeLabActionGoToApproval,
                          onPressed: onGoToApproval == null
                              ? null
                              : () => onGoToApproval!(row.id),
                        ),
                      _ActionLink(
                        key: CodeLabAgentsPane.showInTranscriptKey(row.id),
                        label: codeLabStringsOf(
                          context,
                        ).codeLabActionShowInTranscript,
                        onPressed: onShowInTranscript == null
                            ? null
                            : () => onShowInTranscript!(row.id),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}

/// Метка пункта списка `#N`; подсказка — заголовок пункта плана (D49 Т6).
class _ItemLabel extends StatelessWidget {
  const _ItemLabel({required this.item});

  final CodeLabAgentItemRef item;

  @override
  Widget build(BuildContext context) {
    final label = CodeLabText(
      escapeForDisplay(item.label),
      role: CodeLabTextRole.mono,
    );
    return switch (item.hint) {
      final hint? when hint.isNotEmpty => Tooltip(
        message: escapeForDisplay(hint),
        child: label,
      ),
      _ => label,
    };
  }
}

/// Действие-ссылка строки панели: только переход к ленте, решения нет.
class _ActionLink extends StatelessWidget {
  const _ActionLink({required this.label, required this.onPressed, super.key});

  final String label;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    final theme = FluentTheme.of(context);
    return Semantics(
      button: true,
      label: label,
      excludeSemantics: true,
      child: CodeLabPressable(
        onPressed: onPressed,
        builder: (context, hovered, focused) => Padding(
          padding: const EdgeInsets.symmetric(vertical: 2),
          child: Text(
            label,
            style: theme.typography.caption?.copyWith(
              color: onPressed == null
                  ? theme.resources.textFillColorDisabled
                  : theme.accentColor,
              decoration: hovered || focused ? TextDecoration.underline : null,
            ),
          ),
        ),
      ),
    );
  }
}

/// Дерево шагов выбранной строки: вызовы и вызовы их потомков одной
/// компактной строкой, раскрыто целиком, без вывода и отчёта (D49 Т10).
/// Это не транскрипт потомка: текстов и мыслей потомков на проводе нет (D21).
class _StepsTree extends StatelessWidget {
  const _StepsTree({required this.steps, this.onGoToApproval});

  final List<CodeLabTranscriptRow> steps;
  final ValueChanged<String>? onGoToApproval;

  void _collect(
    BuildContext context,
    List<CodeLabTranscriptRow> rows,
    int depth,
    List<Widget> out,
  ) {
    for (final row in rows) {
      switch (row) {
        case final CodeLabToolCallRow call:
          final waiting = call.awaitsRootDecision || call.awaitsApproval;
          out.add(
            TailLine(
              key: ValueKey('agents-step-${call.id}'),
              row: call,
              indent: depth * CodeLabAgentsPane.indentStep,
              title: TailLine.titleOf(context, call),
              trailing: [
                if (waiting)
                  // Бейдж и ссылка переносятся, а не вылезают за край: док
                  // узкий, а строка шага уже занята отступом и заголовком.
                  Flexible(
                    child: Wrap(
                      spacing: 8,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: [
                        CodeLabBadge(
                          label: codeLabStringsOf(
                            context,
                          ).codeLabApprovalAwaiting,
                          tone: CodeLabTone.accent,
                        ),
                        _ActionLink(
                          key: CodeLabAgentsPane.stepGoToApprovalKey(call.id),
                          label: codeLabStringsOf(
                            context,
                          ).codeLabActionGoToApproval,
                          onPressed: onGoToApproval == null
                              ? null
                              : () => onGoToApproval!(call.id),
                        ),
                      ],
                    ),
                  ),
              ],
            ),
          );
          _collect(context, call.children, depth + 1, out);
        case CodeLabTaskOpsRow(:final text):
          out.add(
            Padding(
              padding: EdgeInsets.only(
                left: depth * CodeLabAgentsPane.indentStep,
              ),
              child: CodeLabTaskOpsLine(text: text),
            ),
          );
        default:
          break;
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final lines = <Widget>[];
    _collect(context, steps, 0, lines);
    return Padding(
      key: CodeLabAgentsPane.stepsKey,
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          CodeLabText(
            codeLabStringsOf(context).codeLabAgentsSteps,
            role: CodeLabTextRole.caption,
          ),
          const SizedBox(height: 4),
          ...lines,
        ],
      ),
    );
  }
}
