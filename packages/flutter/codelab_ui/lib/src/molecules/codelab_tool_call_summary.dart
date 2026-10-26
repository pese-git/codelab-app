import 'package:fluent_ui/fluent_ui.dart';

import '../atomics/atomics.dart';
import 'codelab_view_mode.dart';

enum CodeLabToolCallStatus { queued, running, succeeded, failed, cancelled }

class CodeLabToolCallSummary extends StatelessWidget {
  const CodeLabToolCallSummary({
    required this.name,
    required this.status,
    this.target,
    this.detail,
    this.viewMode = CodeLabViewMode.normal,
    super.key,
  });

  final String name;
  final CodeLabToolCallStatus status;
  final String? target;
  final String? detail;
  final CodeLabViewMode viewMode;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        border: Border.all(color: Colors.grey.withAlpha(54)),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        child: viewMode == CodeLabViewMode.verbose
            ? _buildVerbose()
            : _buildCompact(),
      ),
    );
  }

  Widget _buildCompact() {
    return Row(
      children: [
        CodeLabStatusIndicator(label: _statusLabel, tone: _statusTone),
        const SizedBox(width: 10),
        Expanded(
          child: CodeLabText(
            _compactTitle,
            role: CodeLabTextRole.strong,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ),
        if (viewMode == CodeLabViewMode.normal && detail != null) ...[
          const SizedBox(width: 10),
          Flexible(
            child: CodeLabText(
              detail!,
              role: CodeLabTextRole.caption,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ],
    );
  }

  Widget _buildVerbose() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            CodeLabStatusIndicator(label: _statusLabel, tone: _statusTone),
            const SizedBox(width: 10),
            Expanded(
              child: CodeLabText(
                name,
                role: CodeLabTextRole.strong,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
        if (target != null) ...[
          const SizedBox(height: 6),
          CodeLabText(
            target!,
            role: CodeLabTextRole.caption,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
          ),
        ],
        if (detail != null) ...[
          const SizedBox(height: 4),
          CodeLabText(
            detail!,
            role: CodeLabTextRole.caption,
            maxLines: 3,
            overflow: TextOverflow.ellipsis,
          ),
        ],
      ],
    );
  }

  String get _compactTitle {
    if (viewMode == CodeLabViewMode.summary || target == null) {
      return name;
    }

    return '$name - $target';
  }

  String get _statusLabel {
    return switch (status) {
      CodeLabToolCallStatus.queued => 'Queued',
      CodeLabToolCallStatus.running => 'Running',
      CodeLabToolCallStatus.succeeded => 'Done',
      CodeLabToolCallStatus.failed => 'Failed',
      CodeLabToolCallStatus.cancelled => 'Cancelled',
    };
  }

  CodeLabStatusTone get _statusTone {
    return switch (status) {
      CodeLabToolCallStatus.queued => CodeLabStatusTone.idle,
      CodeLabToolCallStatus.running => CodeLabStatusTone.active,
      CodeLabToolCallStatus.succeeded => CodeLabStatusTone.active,
      CodeLabToolCallStatus.failed => CodeLabStatusTone.danger,
      CodeLabToolCallStatus.cancelled => CodeLabStatusTone.warning,
    };
  }
}
