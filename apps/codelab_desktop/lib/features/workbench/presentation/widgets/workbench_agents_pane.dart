import 'package:fluent_ui/fluent_ui.dart';

/// Панель Agents дока: строки субагентов сессии в фокусе и дерево шагов
/// выбранной строки.
///
/// ВРЕМЕННАЯ ЗАГЛУШКА красных тестов 5b.1 (`[desktop]`): рисует пустое, чтобы
/// `test/features/workbench/presentation/agents_pane_test.dart` компилировался
/// и падал по существу. Реализация — задача 5b.4 (design.md change
/// `add-subagents-and-tasks`, D33, D49 Т9–Т11; spec agent-workbench-ui
/// «Панель Agents v1»).
///
/// Как использовать: слот `ToolPane.agents` в доке `CodeLabShell`.
/// [clock] — часы виджета для тика раз в секунду (D49 Т9): по умолчанию
/// `DateTime.now`, widget-тесты внедряют свои.
class WorkbenchAgentsPane extends StatelessWidget {
  const WorkbenchAgentsPane({this.clock, super.key});

  /// Часы виджета; `null` — `DateTime.now`.
  final DateTime Function()? clock;

  @override
  Widget build(BuildContext context) => const SizedBox.shrink();
}
