import 'package:codelab_ui/codelab_ui.dart';
import 'package:fluent_ui/fluent_ui.dart';

import '../../application/shell_cubit.dart';
import 'connection_setup_dialog.dart';

class WorkbenchCommandBar extends StatelessWidget {
  const WorkbenchCommandBar({
    required this.state,
    required this.cubit,
    super.key,
  });

  final CodeLabShellState state;
  final CodeLabShellCubit cubit;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: FluentTheme.of(context).scaffoldBackgroundColor,
        border: Border.all(color: Colors.grey.withAlpha(54)),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        child: Row(
          children: [
            Text('CodeLab', style: FluentTheme.of(context).typography.subtitle),
            const SizedBox(width: 16),
            Expanded(
              child: CodeLabConnectionStatusRow(
                status: state.connectionStatus,
                transportLabel: state.transportLabel,
                profileLabel: state.profileLabel,
                detail: state.connectionDetail,
              ),
            ),
            const SizedBox(width: 8),
            CodeLabIconButton(
              key: const ValueKey('command-bar-configure-connection'),
              icon: FluentIcons.settings,
              tooltip: 'Configure connection',
              onPressed: () => ConnectionSetupDialog.show(context),
            ),
            const SizedBox(width: 8),
            CodeLabButton(
              key: const ValueKey('command-bar-connect'),
              label: 'Connect',
              icon: FluentIcons.plug_connected,
              emphasis: CodeLabButtonEmphasis.primary,
              onPressed: cubit.connect,
            ),
          ],
        ),
      ),
    );
  }
}
