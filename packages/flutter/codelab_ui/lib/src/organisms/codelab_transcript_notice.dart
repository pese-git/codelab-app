import 'package:fluent_ui/fluent_ui.dart';

import '../atomics/atomics.dart';
import '../molecules/molecules.dart';
import 'codelab_transcript_row.dart';

/// Заметка ленты, оформленная по тяжести.
///
/// Почему: любая заметка рисовалась красной карточкой с ⚠, и сообщение «a new
/// session was started» выглядело как ошибка (design D6 change
/// `redesign-transcript-rows`).
///
/// Для чего: [CodeLabNoticeSeverity.error] и
/// [CodeLabNoticeSeverity.warning] — `InfoBar` с заголовком, телом, Details
/// и действием; [CodeLabNoticeSeverity.info] — нейтральная строка с иконкой.
///
/// Как использовать: `CodeLabTranscriptNotice(row: noticeRow)`; строку
/// строит маппер приложения.
class CodeLabTranscriptNotice extends StatelessWidget {
  const CodeLabTranscriptNotice({required this.row, super.key});

  final CodeLabNoticeRow row;

  @override
  Widget build(BuildContext context) {
    final severity = row.severity;
    if (severity == CodeLabNoticeSeverity.info) {
      final muted = FluentTheme.of(context).resources.textFillColorSecondary;
      return Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(top: 2),
            child: Icon(FluentIcons.info, size: 13, color: muted),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: CodeLabText(
              [?row.title, row.body].join(' · '),
              role: CodeLabTextRole.caption,
              color: muted,
            ),
          ),
        ],
      );
    }

    final details = row.details;
    final action = row.action;
    return InfoBar(
      severity: severity == CodeLabNoticeSeverity.error
          ? InfoBarSeverity.error
          : InfoBarSeverity.warning,
      isLong: true,
      title: Text(row.title ?? ''),
      content: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(row.body),
          if (details != null) ...[
            const SizedBox(height: 6),
            CodeLabTextDisclosure(label: 'Details', text: details),
          ],
          if (action != null) ...[
            const SizedBox(height: 8),
            CodeLabButton(
              label: action.label,
              icon: action.icon,
              onPressed: action.onPressed,
            ),
          ],
        ],
      ),
    );
  }
}
