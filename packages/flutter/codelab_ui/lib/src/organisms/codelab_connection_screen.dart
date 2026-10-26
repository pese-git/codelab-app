import 'package:fluent_ui/fluent_ui.dart';

import '../atomics/atomics.dart';
import '../molecules/molecules.dart';

class CodeLabConnectionScreen extends StatelessWidget {
  const CodeLabConnectionScreen({
    required this.status,
    required this.transportLabel,
    required this.profileLabel,
    this.detail,
    this.description,
    this.onConnect,
    this.onReconnect,
    this.onConfigureConnection,
    this.isBusy = false,
    super.key,
  });

  final CodeLabConnectionStatus status;
  final String transportLabel;
  final String profileLabel;
  final String? detail;
  final String? description;
  final VoidCallback? onConnect;
  final VoidCallback? onReconnect;
  final VoidCallback? onConfigureConnection;
  final bool isBusy;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 520),
        child: DecoratedBox(
          decoration: BoxDecoration(
            border: Border.all(color: Colors.grey.withAlpha(64)),
            borderRadius: BorderRadius.circular(6),
          ),
          child: Padding(
            padding: const EdgeInsets.all(18),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    const CodeLabIcon(
                      FluentIcons.plug_connected,
                      tone: CodeLabTone.accent,
                      size: 22,
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: CodeLabText(
                        profileLabel,
                        role: CodeLabTextRole.title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
                if (description != null) ...[
                  const SizedBox(height: 8),
                  CodeLabText(
                    description!,
                    role: CodeLabTextRole.caption,
                    maxLines: 3,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
                const SizedBox(height: 16),
                CodeLabConnectionStatusRow(
                  status: status,
                  transportLabel: transportLabel,
                  profileLabel: profileLabel,
                  detail: detail,
                ),
                const SizedBox(height: 16),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  alignment: WrapAlignment.end,
                  children: [
                    if (onConfigureConnection != null)
                      CodeLabButton(
                        label: 'Configure connection',
                        icon: FluentIcons.settings,
                        onPressed: isBusy ? null : onConfigureConnection,
                      ),
                    if (onReconnect != null)
                      CodeLabButton(
                        label: 'Reconnect',
                        icon: FluentIcons.refresh,
                        onPressed: isBusy ? null : onReconnect,
                      ),
                    if (onConnect != null)
                      CodeLabButton(
                        label: 'Connect',
                        icon: FluentIcons.plug_connected,
                        emphasis: CodeLabButtonEmphasis.primary,
                        isLoading: isBusy,
                        onPressed: isBusy ? null : onConnect,
                      ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
