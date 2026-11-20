import 'package:fluent_ui/fluent_ui.dart';

/// Узел фокуса композера и обработчик ухода полосы одобрения, которые рабочее
/// место отдаёт вниз по дереву.
///
/// Почему `InheritedWidget`: узел принадлежит `State` рабочего места
/// (`_CodeLabHomeState`: создаётся и освобождается там), а композер и лента
/// строятся глубоко внутри `WorkbenchMainPane`; пробрасывать два параметра
/// через все промежуточные виджеты не нужно (`fix-approval-focus`, D5).
///
/// Для чего: `WorkbenchMainPane` отдаёт [composerNode] композеру
/// (`textFocusNode`), а [onApprovalFocusReleased] — ленте. Решение, куда
/// вернуть фокус, принимает хост, а не виджет (`approvalFocusReturnOf`).
///
/// Как использовать: хост оборачивает `CodeLabShell`; виджеты читают
/// `WorkbenchFocus.maybeOf(context)`. Без хоста (изолированные тесты) значение
/// `null`, и композер заводит свой узел.
class WorkbenchFocus extends InheritedWidget {
  const WorkbenchFocus({
    required this.composerNode,
    required this.onApprovalFocusReleased,
    required super.child,
    super.key,
  });

  /// Узел поля ввода композера; принадлежит хосту.
  final FocusNode composerNode;

  /// Полоса одобрения с фокусом ушла из ленты.
  final VoidCallback onApprovalFocusReleased;

  static WorkbenchFocus? maybeOf(BuildContext context) =>
      context.getInheritedWidgetOfExactType<WorkbenchFocus>();

  @override
  bool updateShouldNotify(WorkbenchFocus oldWidget) =>
      composerNode != oldWidget.composerNode ||
      onApprovalFocusReleased != oldWidget.onApprovalFocusReleased;
}
