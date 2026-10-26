import 'package:fluent_ui/fluent_ui.dart';

import '../atomics/atomics.dart';
import 'acp_activity_bar.dart';

/// A prompt submitted while the session couldn't accept a new turn, held
/// client-side until it can be sent (or edited/deleted/sent-now by the
/// user). Never a protocol concept — the agent never sees a queued prompt
/// until it is actually dispatched.
class AcpQueuedPrompt {
  const AcpQueuedPrompt({required this.id, required this.content});

  final String id;
  final String content;
}

/// The client-side prompt queue, rendered as an [AcpActivityBarSection] —
/// same static-factory pattern as [AcpProgressChecklist] section, docked
/// alongside it (or alone) in the shared [AcpActivityBar].
class AcpPromptQueuePanel {
  AcpPromptQueuePanel._();

  static AcpActivityBarSection section({
    required String id,
    required List<AcpQueuedPrompt> items,
    required ValueChanged<String> onEdit,
    required ValueChanged<String> onDelete,
    required ValueChanged<String> onSendNow,
    required VoidCallback onClearAll,
  }) {
    return AcpActivityBarSection(
      id: id,
      headerBuilder: (context, expanded) =>
          _Header(count: items.length, onClearAll: onClearAll),
      bodyBuilder: (context) => _Body(
        items: items,
        onEdit: onEdit,
        onDelete: onDelete,
        onSendNow: onSendNow,
      ),
    );
  }
}

class _Header extends StatelessWidget {
  const _Header({required this.count, required this.onClearAll});

  final int count;
  final VoidCallback onClearAll;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        const Expanded(child: AcpText('Queue', role: AcpTextRole.caption)),
        AcpText('$count queued', role: AcpTextRole.caption),
        const SizedBox(width: 8),
        AcpIconButton(
          icon: FluentIcons.chrome_close,
          tooltip: 'Clear all',
          onPressed: onClearAll,
        ),
      ],
    );
  }
}

class _Body extends StatelessWidget {
  const _Body({
    required this.items,
    required this.onEdit,
    required this.onDelete,
    required this.onSendNow,
  });

  final List<AcpQueuedPrompt> items;
  final ValueChanged<String> onEdit;
  final ValueChanged<String> onDelete;
  final ValueChanged<String> onSendNow;

  static const double _maxHeight = 128;

  @override
  Widget build(BuildContext context) {
    return ConstrainedBox(
      constraints: const BoxConstraints(maxHeight: _maxHeight),
      child: ListView.separated(
        shrinkWrap: true,
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
        itemCount: items.length,
        separatorBuilder: (context, index) => const SizedBox(height: 6),
        itemBuilder: (context, index) {
          final item = items[index];
          return _EntryRow(
            entry: item,
            onEdit: () => onEdit(item.id),
            onDelete: () => onDelete(item.id),
            onSendNow: () => onSendNow(item.id),
          );
        },
      ),
    );
  }
}

class _EntryRow extends StatelessWidget {
  const _EntryRow({
    required this.entry,
    required this.onEdit,
    required this.onDelete,
    required this.onSendNow,
  });

  final AcpQueuedPrompt entry;
  final VoidCallback onEdit;
  final VoidCallback onDelete;
  final VoidCallback onSendNow;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: Padding(
            padding: const EdgeInsets.only(top: 3),
            child: AcpText(
              entry.content,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ),
        const SizedBox(width: 4),
        AcpIconButton(
          icon: FluentIcons.edit,
          tooltip: 'Edit',
          onPressed: onEdit,
        ),
        AcpIconButton(
          icon: FluentIcons.send,
          tooltip: 'Send now',
          onPressed: onSendNow,
        ),
        AcpIconButton(
          icon: FluentIcons.delete,
          tooltip: 'Delete',
          tone: AcpTone.danger,
          onPressed: onDelete,
        ),
      ],
    );
  }
}
