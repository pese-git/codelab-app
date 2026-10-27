import 'package:fluent_ui/fluent_ui.dart';

/// Панель дока инструментов рабочего места.
///
/// Почему: все инструменты — Files, Diff, Terminal, Plan и другие — живут в
/// одном доке справа, а не каждый в своей колонке (`dart-agent-and-clients`
/// §12.3 A13, шаги 0 и 6; change `redesign-workbench-shell`, D5).
///
/// Для чего: идентификатор панели для дока, переключателей app bar и ключей
/// тестов (`tool-pane-<pane>`, `tool-toggle-<pane>`, A13 шаг 8). Подпись и
/// иконка — [label] и [icon].
///
/// Как использовать: хост передаёт доку и app bar только панели, для которых
/// есть данные; остальные значения ждут своих change, без заглушек в UI.
enum ToolPane {
  files('Files', FluentIcons.folder),
  diff('Diff', FluentIcons.diff_side_by_side),
  terminal('Terminal', FluentIcons.command_prompt),
  plan('Plan', FluentIcons.check_list),
  timeline('Timeline', FluentIcons.timeline),
  agents('Agents', FluentIcons.robot),
  usage('Usage', FluentIcons.chart),
  branches('Branches', FluentIcons.branch_fork2),
  protocol('Protocol', FluentIcons.code);

  const ToolPane(this.label, this.icon);

  final String label;
  final IconData icon;
}
