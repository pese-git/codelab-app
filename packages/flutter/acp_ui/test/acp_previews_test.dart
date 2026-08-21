import 'package:acp_ui/src/molecules/acp_molecule_previews.dart';
import 'package:acp_ui/src/organisms/acp_organism_previews.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('molecule previews render in bounded preview surfaces', (
    tester,
  ) async {
    await tester.pumpWidget(acpPromptComposerPreview());
    expect(tester.takeException(), isNull);

    await tester.pumpWidget(acpToolCallSummaryPreview());
    expect(tester.takeException(), isNull);

    await tester.pumpWidget(acpConnectionStatusRowPreview());
    expect(tester.takeException(), isNull);

    await tester.pumpWidget(acpApprovalOptionGroupPreview());
    expect(tester.takeException(), isNull);
  });

  testWidgets('organism previews render in bounded preview surfaces', (
    tester,
  ) async {
    await tester.pumpWidget(acpTranscriptPanelPreview());
    expect(tester.takeException(), isNull);

    await tester.pumpWidget(acpApprovalPanelPreview());
    expect(tester.takeException(), isNull);

    await tester.pumpWidget(acpConnectionScreenPreview());
    expect(tester.takeException(), isNull);

    await tester.pumpWidget(acpDebugLogPanelPreview());
    expect(tester.takeException(), isNull);

    await tester.pumpWidget(acpSessionSidebarPreview());
    expect(tester.takeException(), isNull);

    tester.view.physicalSize = const Size(1280, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      SizedBox(width: 1180, height: 720, child: acpWorkbenchLayoutPreview()),
    );
    expect(tester.takeException(), isNull);

    await tester.pumpWidget(
      SizedBox(
        width: 860,
        height: 720,
        child: acpWorkbenchLayoutMediumPreview(),
      ),
    );
    expect(tester.takeException(), isNull);

    await tester.pumpWidget(
      SizedBox(
        width: 430,
        height: 720,
        child: acpWorkbenchLayoutNarrowPreview(),
      ),
    );
    expect(tester.takeException(), isNull);
  });
}
