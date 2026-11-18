import 'package:fluent_ui/fluent_ui.dart';

import '../l10n/strings.dart';

/// Панель дока инструментов рабочего места.
///
/// Почему: все инструменты — Files, Diff, Terminal, Plan и другие — живут в
/// одном доке справа, а не каждый в своей колонке (`dart-agent-and-clients`
/// §12.3 A13, шаги 0 и 6; change `redesign-workbench-shell`, D5).
///
/// Для чего: идентификатор панели для дока, переключателей app bar и ключей
/// тестов (`tool-pane-<pane>`, `tool-toggle-<pane>`, A13 шаг 8). Иконка —
/// [icon]; название зависит от языка и берётся функцией [toolPaneTitleOf], а
/// не полем enum (`add-desktop-localization`, D4).
///
/// Как использовать: хост передаёт доку и app bar только панели, для которых
/// есть данные; остальные значения ждут своих change, без заглушек в UI.
/// Название для показа — `toolPaneTitleOf(context, pane)`.
enum ToolPane {
  files(FluentIcons.folder),
  diff(FluentIcons.diff_side_by_side),
  terminal(FluentIcons.command_prompt),
  plan(FluentIcons.check_list),
  timeline(FluentIcons.timeline),
  agents(FluentIcons.robot),
  usage(FluentIcons.chart),
  branches(FluentIcons.branch_fork2),
  protocol(FluentIcons.code);

  const ToolPane(this.icon);

  final IconData icon;
}

/// Название панели [pane] на языке интерфейса.
///
/// Почему: название — пара «панель — подпись» внутри кита (`codelab_ui/AGENTS.md`
/// §5), а не данные app; прежнее поле enum было английским литералом
/// (D4). Для чего: заголовок вкладки дока, подсказка и подпись переключателя
/// app bar. Как использовать: в `build`, как `toolPaneTitleOf(context, pane)`;
/// без делегата кита вернёт английское название, как раньше.
String toolPaneTitleOf(BuildContext context, ToolPane pane) {
  final strings = codeLabStringsOf(context);
  return switch (pane) {
    ToolPane.files => strings.codeLabPaneFiles,
    ToolPane.diff => strings.codeLabPaneDiff,
    ToolPane.terminal => strings.codeLabPaneTerminal,
    ToolPane.plan => strings.codeLabPanePlan,
    ToolPane.timeline => strings.codeLabPaneTimeline,
    ToolPane.agents => strings.codeLabPaneAgents,
    ToolPane.usage => strings.codeLabPaneUsage,
    ToolPane.branches => strings.codeLabPaneBranches,
    ToolPane.protocol => strings.codeLabPaneProtocol,
  };
}
