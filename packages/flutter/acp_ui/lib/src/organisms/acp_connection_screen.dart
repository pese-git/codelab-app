import 'package:fluent_ui/fluent_ui.dart';

import '../atomics/atomics.dart';
import '../molecules/molecules.dart';

class AcpConnectionScreen extends StatelessWidget {
  const AcpConnectionScreen({
    required this.status,
    required this.transportLabel,
    required this.profileLabel,
    this.detail,
    this.description,
    this.onConnect,
    this.onReconnect,
    this.onEditProfile,
    this.isBusy = false,
    super.key,
  });

  final AcpConnectionStatus status;
  final String transportLabel;
  final String profileLabel;
  final String? detail;
  final String? description;
  final VoidCallback? onConnect;
  final VoidCallback? onReconnect;
  final VoidCallback? onEditProfile;
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
                    const AcpIcon(
                      FluentIcons.plug_connected,
                      tone: AcpTone.accent,
                      size: 22,
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: AcpText(
                        profileLabel,
                        role: AcpTextRole.title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
                if (description != null) ...[
                  const SizedBox(height: 8),
                  AcpText(
                    description!,
                    role: AcpTextRole.caption,
                    maxLines: 3,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
                const SizedBox(height: 16),
                AcpConnectionStatusRow(
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
                    if (onEditProfile != null)
                      AcpButton(
                        label: 'Edit profile',
                        icon: FluentIcons.edit,
                        onPressed: isBusy ? null : onEditProfile,
                      ),
                    if (onReconnect != null)
                      AcpButton(
                        label: 'Reconnect',
                        icon: FluentIcons.refresh,
                        onPressed: isBusy ? null : onReconnect,
                      ),
                    if (onConnect != null)
                      AcpButton(
                        label: 'Connect',
                        icon: FluentIcons.plug_connected,
                        emphasis: AcpButtonEmphasis.primary,
                        isLoading: isBusy,
                        onPressed: onConnect,
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
