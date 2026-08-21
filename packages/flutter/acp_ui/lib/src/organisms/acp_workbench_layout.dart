import 'package:fluent_ui/fluent_ui.dart';

class AcpWorkbenchLayout extends StatelessWidget {
  const AcpWorkbenchLayout({
    required this.commandBar,
    required this.sessionsPane,
    required this.mainPane,
    required this.inspectorPane,
    this.sessionsPaneWidth = 280,
    this.inspectorPaneWidth = 320,
    this.gap = 12,
    this.padding = const EdgeInsets.all(16),
    super.key,
  });

  static const commandBarKey = ValueKey('acp-workbench-command-bar');
  static const sessionsPaneKey = ValueKey('acp-workbench-sessions-pane');
  static const mainPaneKey = ValueKey('acp-workbench-main-pane');
  static const inspectorPaneKey = ValueKey('acp-workbench-inspector-pane');

  final Widget commandBar;
  final Widget sessionsPane;
  final Widget mainPane;
  final Widget inspectorPane;
  final double sessionsPaneWidth;
  final double inspectorPaneWidth;
  final double gap;
  final EdgeInsetsGeometry padding;

  @override
  Widget build(BuildContext context) {
    return ColoredBox(
      color: FluentTheme.of(context).micaBackgroundColor,
      child: Padding(
        padding: padding,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Semantics(
              container: true,
              label: 'Command bar',
              child: KeyedSubtree(key: commandBarKey, child: commandBar),
            ),
            SizedBox(height: gap),
            Expanded(
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  SizedBox(
                    key: sessionsPaneKey,
                    width: sessionsPaneWidth,
                    child: Semantics(
                      container: true,
                      label: 'Sessions pane',
                      child: sessionsPane,
                    ),
                  ),
                  SizedBox(width: gap),
                  Expanded(
                    key: mainPaneKey,
                    child: Semantics(
                      container: true,
                      label: 'Main pane',
                      child: mainPane,
                    ),
                  ),
                  SizedBox(width: gap),
                  SizedBox(
                    key: inspectorPaneKey,
                    width: inspectorPaneWidth,
                    child: Semantics(
                      container: true,
                      label: 'Inspector pane',
                      child: inspectorPane,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
