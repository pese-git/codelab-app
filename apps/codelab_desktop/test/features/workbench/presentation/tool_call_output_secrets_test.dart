// Красный виджет-тест задачи 3.4 change `redact-tool-row-text`: раскрытая
// строка инструмента в ленте показывает вывод без секретов и не повторяет
// однострочную ошибку (D7; agent-workbench-ui «Упавший fetch с паролем в
// ошибке», «Вывод успешного вызова замаскирован»).
//
// Проверяется поведение (какой текст виден), а не пиксели. Маскирует kit,
// виджет только показывает готовые строки.

import 'package:codelab_acp_protocol/codelab_acp_protocol.dart';
import 'package:codelab_client_core/codelab_client_core.dart';
import 'package:codelab_desktop/features/workbench/application/ui_mappers.dart';
import 'package:codelab_desktop/l10n/app_localizations_en.dart';
import 'package:codelab_ui/codelab_ui.dart';
import 'package:fluent_ui/fluent_ui.dart';
import 'package:flutter_test/flutter_test.dart';

/// Id строки в ленте: маппер даёт `tool-<индекс + 1>` у верхнего уровня.
const _rowId = 'tool-1';

Future<void> _pumpExpanded(WidgetTester tester, ToolCallView details) async {
  tester.view.physicalSize = const Size(900, 900);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  final rows = transcriptRowsOf(
    [
      TranscriptItem.toolCall(
        id: 't1/tool-call-1',
        toolCallId: const ToolCallId('call-1'),
        title: 'tool',
        details: details,
      ),
    ],
    cwd: '/work',
    approvalsEnabled: true,
    onApprovalSelected: (_, _) {},
    l10n: AppLocalizationsEn(),
  );
  await tester.pumpWidget(
    FluentApp(
      home: CodeLabTranscriptPanel(
        rows: rows,
        expansionOverrides: const {_rowId: true},
      ),
    ),
  );
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 100));
}

void main() {
  testWidgets('a failed fetch shows the masked error exactly once', (
    tester,
  ) async {
    await _pumpExpanded(
      tester,
      const ToolCallView(
        kind: ToolKind.fetch,
        status: ToolCallStatusView.failed,
        rawInput: {'url': 'https://host/x'},
        textOutput: ['Error: request to https://user:pass@host/x failed'],
      ),
    );

    expect(
      find.textContaining(
        'Error: request to https://<redacted>@host/x failed',
        findRichText: true,
      ),
      findsOneWidget,
    );
    expect(find.textContaining('pass', findRichText: true), findsNothing);
  });

  testWidgets('a completed read hides the secret in the output', (
    tester,
  ) async {
    await _pumpExpanded(
      tester,
      const ToolCallView(
        kind: ToolKind.read,
        status: ToolCallStatusView.succeeded,
        rawInput: {'path': '/work/.env'},
        textOutput: ['API_KEY=sk-live-123\nDEBUG=1'],
      ),
    );

    expect(
      find.textContaining('sk-live-123', findRichText: true),
      findsNothing,
    );
    expect(find.textContaining('DEBUG=1', findRichText: true), findsOneWidget);
  });
}
