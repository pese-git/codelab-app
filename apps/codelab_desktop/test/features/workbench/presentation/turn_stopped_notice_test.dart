// Заметка исхода хода в ленте app (задача 6.1d-2 change
// `add-provider-setup-ui`; spec agent-workbench-ui «Заметка исхода хода в
// ленте», сценарий «Молчаливый max_tokens»; design.md D27, Q33).
//
// Ход, оборвавшийся по лимиту токенов без текста, не должен выглядеть
// молчаливым: проекция kit-а даёт `NoticeKind.turnStopped`, app показывает её
// строкой `CodeLabNoticeRow` в ленте. Красный тест: `NoticeKind.turnStopped`
// вводит `codelab_client_core` (6.1d-1), отображение — `ui_mappers.dart`.

import 'package:codelab_client_core/codelab_client_core.dart';
import 'package:codelab_desktop/features/workbench/application/ui_mappers.dart';
import 'package:codelab_ui/codelab_ui.dart';
import 'package:fluent_ui/fluent_ui.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('a turn that stopped at the token limit shows its note in the '
      'transcript and no empty-turn note', (tester) async {
    const text = 'The model reached its token limit, so the turn ended.';
    final rows = transcriptRowsOf(
      const [
        TranscriptItem.user(id: 't1/user', text: 'explain the repo'),
        TranscriptItem.notice(
          id: 't1/stopped',
          kind: NoticeKind.turnStopped,
          text: text,
        ),
      ],
      cwd: '/work',
      approvalsEnabled: true,
      onApprovalSelected: (_, _) {},
    );

    tester.view.physicalSize = const Size(900, 700);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      FluentApp(home: CodeLabTranscriptPanel(rows: rows)),
    );
    await tester.pumpAndSettle();

    expect(find.text(text), findsOneWidget);
    expect(find.textContaining('stopReason'), findsNothing);
  });
}
