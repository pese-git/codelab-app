import 'package:acp_ui/acp_ui.dart';
import 'package:fluent_ui/fluent_ui.dart';

import 'src/app_scope.dart';

void main() {
  runApp(const CodeLabBootstrap(child: CodeLabApp()));
}

class CodeLabApp extends StatelessWidget {
  const CodeLabApp({super.key});

  @override
  Widget build(BuildContext context) {
    codeLabDependenciesOf(context);

    return const FluentApp(title: 'CodeLab', home: CodeLabShell());
  }
}

class CodeLabShell extends StatelessWidget {
  const CodeLabShell({super.key});

  @override
  Widget build(BuildContext context) {
    return ScaffoldPage(
      header: const PageHeader(
        title: Text('Agent Workbench'),
        commandBar: AcpStatusIndicator(label: 'Disconnected'),
      ),
      content: Padding(
        padding: const EdgeInsets.all(24),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const SizedBox(
              width: 220,
              child: _WorkbenchPane(
                title: 'Sessions',
                child: Text('No active session'),
              ),
            ),
            const SizedBox(width: 16),
            const Expanded(
              flex: 3,
              child: _WorkbenchPane(
                title: 'Transcript',
                child: Text('Connect an ACP agent to start a session.'),
              ),
            ),
            const SizedBox(width: 16),
            const SizedBox(
              width: 280,
              child: _WorkbenchPane(
                title: 'Inspector',
                child: Text('Approvals, tool calls, and diagnostics.'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _WorkbenchPane extends StatelessWidget {
  const _WorkbenchPane({required this.title, required this.child});

  final String title;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        border: Border.all(color: Colors.grey.withAlpha(80)),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title, style: FluentTheme.of(context).typography.subtitle),
            const SizedBox(height: 12),
            child,
          ],
        ),
      ),
    );
  }
}
