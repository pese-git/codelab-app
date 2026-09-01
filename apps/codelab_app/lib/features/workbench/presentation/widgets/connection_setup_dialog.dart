import 'package:fluent_ui/fluent_ui.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../application/shell_cubit.dart';
import 'transport_setup_panel.dart';

/// Modal presentation of [TransportSetupPanel] — the connection profile form
/// is ephemeral UI state (open/closed), not part of [CodeLabShellState], so
/// this dialog owns its own visibility via [showDialog] rather than the
/// cubit (see complete-transport-setup-actions/design.md).
class ConnectionSetupDialog extends StatelessWidget {
  const ConnectionSetupDialog({super.key});

  static Future<void> show(BuildContext context) {
    return showDialog<void>(
      context: context,
      builder: (_) => const ConnectionSetupDialog(),
    );
  }

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<CodeLabShellCubit, CodeLabShellState>(
      builder: (context, state) {
        final cubit = context.read<CodeLabShellCubit>();

        return ContentDialog(
          constraints: const BoxConstraints(maxWidth: 640, maxHeight: 560),
          title: const Text('Configure connection'),
          content: TransportSetupPanel(state: state, cubit: cubit),
          actions: [
            Button(
              child: const Text('Close'),
              onPressed: () => Navigator.of(context).pop(),
            ),
          ],
        );
      },
    );
  }
}
