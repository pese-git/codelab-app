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
    this.reconnectLabel = 'Reconnect',
    this.onConfigureConnection,
    this.extraAction,
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

  /// Подпись кнопки повтора: хост без ручного Connect называет её `Retry`
  /// (design.md change `require-project-folder`, D18); по умолчанию прежняя.
  final String reconnectLabel;
  final VoidCallback? onConfigureConnection;

  /// Действие хоста без знания о его смысле (например, «Add provider»,
  /// change `add-provider-setup-ui`, D26); ставится перед стандартными
  /// кнопками.
  final Widget? extraAction;
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
                    ?extraAction,
                    if (onConfigureConnection != null)
                      CodeLabButton(
                        label: 'Configure connection',
                        icon: FluentIcons.settings,
                        onPressed: isBusy ? null : onConfigureConnection,
                      ),
                    if (onReconnect != null)
                      CodeLabButton(
                        label: reconnectLabel,
                        icon: FluentIcons.refresh,
                        onPressed: isBusy ? null : onReconnect,
                      ),
                    if (onConnect != null)
                      CodeLabButton(
                        label: 'Connect',
                        icon: FluentIcons.plug_connected,
                        // Основная кнопка одна: с действием хоста оно и есть
                        // основное, «Connect» — обычная.
                        emphasis: extraAction == null
                            ? CodeLabButtonEmphasis.primary
                            : CodeLabButtonEmphasis.secondary,
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
