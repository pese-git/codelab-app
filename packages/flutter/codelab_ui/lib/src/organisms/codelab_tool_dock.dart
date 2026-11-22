import 'package:fluent_ui/fluent_ui.dart';

import '../atomics/atomics.dart';
import '../molecules/molecules.dart';

/// Вкладка дока: панель и её содержимое.
///
/// [actions] — действия панели (например, `Pause`, `Clear`, `Export…` у
/// Protocol): док показывает их справа в строке вкладок, только пока вкладка
/// активна; строка действий занимает не больше 70 % ширины дока и
/// прокручивается по горизонтали. Почему в доке, а не в теле панели: так устроен макет, а поле
/// нужно и будущим панелям Terminal и Diff (change `redesign-protocol-pane`,
/// D1, D12). Виджеты строит хост; док ничего о них не знает.
class CodeLabDockTab {
  const CodeLabDockTab({
    required this.pane,
    required this.content,
    this.actions,
  });

  final ToolPane pane;
  final Widget content;

  /// Действия активной вкладки; `null` или пусто — вид дока прежний.
  final List<Widget>? actions;
}

/// Док панелей инструментов справа от панели сессии.
///
/// Почему: бывшие колонки Inspector и Debug log и будущие Files, Terminal,
/// Diff должны жить в одном месте с вкладками, а не плодить колонки
/// (`dart-agent-and-clients` §12.3 A13, шаги 0 и 6; change
/// `redesign-workbench-shell`, D5).
///
/// Для чего: строка вкладок открытых панелей и содержимое активной; без
/// логики — какие панели открыты и какая активна, хранит хост.
///
/// Как использовать: хост передаёт [tabs] в порядке открытия и [active] из
/// своего состояния; [onSelected] делает вкладку активной, [onClosed]
/// закрывает панель. Без вкладок хост не показывает док вовсе. Содержимое
/// активной панели помечено ключом `tool-pane-<pane>` (A13, шаг 8).
class CodeLabToolDock extends StatelessWidget {
  const CodeLabToolDock({
    required this.tabs,
    required this.active,
    this.onSelected,
    this.onClosed,
    super.key,
  }) : assert(tabs.length > 0, 'the dock is shown only with open panes');

  /// Ключ содержимого панели (A13, шаг 8).
  static ValueKey<String> paneKey(ToolPane pane) =>
      ValueKey('tool-pane-${pane.name}');

  static ValueKey<String> tabKey(ToolPane pane) =>
      ValueKey('tool-tab-${pane.name}');

  static ValueKey<String> closeKey(ToolPane pane) =>
      ValueKey('tool-tab-close-${pane.name}');

  final List<CodeLabDockTab> tabs;
  final ToolPane active;
  final ValueChanged<ToolPane>? onSelected;
  final ValueChanged<ToolPane>? onClosed;

  @override
  Widget build(BuildContext context) {
    final theme = FluentTheme.of(context);
    // Активная панель может пропасть из вкладок раньше, чем хост обновит
    // [active]; тогда показывается первая вкладка, а не пустой док.
    final shown = tabs.firstWhere(
      (tab) => tab.pane == active,
      orElse: () => tabs.first,
    );

    return DecoratedBox(
      decoration: BoxDecoration(
        color: theme.resources.cardBackgroundFillColorDefault,
        border: Border.all(color: theme.resources.cardStrokeColorDefault),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Действия стоят справа и сжимаются: не больше 70 % ширины дока, всё
          // остальное прокручивается по горизонтали (док 360 px, длинные
          // подписи русского интерфейса); вкладки получают остаток.
          LayoutBuilder(
            builder: (context, constraints) => Row(
              children: [
                Expanded(
                  child: SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    padding: const EdgeInsets.fromLTRB(6, 6, 6, 0),
                    child: Row(
                      children: [
                        for (final tab in tabs)
                          _DockTabButton(
                            pane: tab.pane,
                            selected: tab.pane == shown.pane,
                            onSelected: onSelected,
                            onClosed: onClosed,
                          ),
                      ],
                    ),
                  ),
                ),
                // Действия — только у активной вкладки (D1).
                if (shown.actions case final actions? when actions.isNotEmpty)
                  ConstrainedBox(
                    constraints: BoxConstraints(
                      maxWidth: constraints.maxWidth * 0.7,
                    ),
                    child: SingleChildScrollView(
                      scrollDirection: Axis.horizontal,
                      padding: const EdgeInsets.fromLTRB(8, 4, 8, 0),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        spacing: 6,
                        children: actions,
                      ),
                    ),
                  ),
              ],
            ),
          ),
          Container(height: 1, color: theme.resources.cardStrokeColorDefault),
          Expanded(
            child: KeyedSubtree(key: paneKey(shown.pane), child: shown.content),
          ),
        ],
      ),
    );
  }
}

class _DockTabButton extends StatelessWidget {
  const _DockTabButton({
    required this.pane,
    required this.selected,
    required this.onSelected,
    required this.onClosed,
  });

  final ToolPane pane;
  final bool selected;
  final ValueChanged<ToolPane>? onSelected;
  final ValueChanged<ToolPane>? onClosed;

  @override
  Widget build(BuildContext context) {
    final theme = FluentTheme.of(context);
    return Padding(
      padding: const EdgeInsets.only(right: 2),
      child: HoverButton(
        key: CodeLabToolDock.tabKey(pane),
        onPressed: onSelected == null ? null : () => onSelected!(pane),
        builder: (context, states) => DecoratedBox(
          decoration: BoxDecoration(
            color: selected
                ? theme.resources.subtleFillColorSecondary
                : states.isHovered
                ? theme.resources.subtleFillColorTertiary
                : null,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(4)),
            border: selected
                ? Border(bottom: BorderSide(color: theme.accentColor, width: 2))
                : null,
          ),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(10, 6, 4, 6),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(pane.icon, size: 12),
                const SizedBox(width: 6),
                CodeLabText(
                  toolPaneTitleOf(context, pane),
                  role: selected
                      ? CodeLabTextRole.strong
                      : CodeLabTextRole.body,
                ),
                const SizedBox(width: 4),
                IconButton(
                  key: CodeLabToolDock.closeKey(pane),
                  icon: const Icon(FluentIcons.chrome_close, size: 8),
                  onPressed: onClosed == null ? null : () => onClosed!(pane),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
