import 'package:codelab_ui/src/molecules/codelab_molecule_previews.dart';
import 'package:codelab_ui/src/organisms/codelab_organism_previews.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('molecule previews render in bounded preview surfaces', (
    tester,
  ) async {
    await tester.pumpWidget(codelabPromptComposerPreview());
    expect(tester.takeException(), isNull);

    await tester.pumpWidget(codelabToolCallSummaryPreview());
    expect(tester.takeException(), isNull);

    await tester.pumpWidget(codelabToolCallSummarySummaryPreview());
    expect(tester.takeException(), isNull);

    await tester.pumpWidget(codelabToolCallSummaryVerbosePreview());
    expect(tester.takeException(), isNull);

    await tester.pumpWidget(codelabConnectionStatusRowPreview());
    expect(tester.takeException(), isNull);

    await tester.pumpWidget(codelabApprovalOptionGroupPreview());
    expect(tester.takeException(), isNull);
  });

  testWidgets('organism previews render in bounded preview surfaces', (
    tester,
  ) async {
    await tester.pumpWidget(codelabTranscriptPanelPreview());
    expect(tester.takeException(), isNull);

    await tester.pumpWidget(codelabTranscriptPanelSummaryPreview());
    expect(tester.takeException(), isNull);

    await tester.pumpWidget(codelabTranscriptPanelVerbosePreview());
    expect(tester.takeException(), isNull);

    await tester.pumpWidget(codelabApprovalPanelPreview());
    expect(tester.takeException(), isNull);

    await tester.pumpWidget(codelabConnectionScreenPreview());
    expect(tester.takeException(), isNull);

    await tester.pumpWidget(codelabSessionSidebarPreview());
    expect(tester.takeException(), isNull);

    await tester.pumpWidget(codelabCommandPaletteEmptyQueryPreview());
    expect(tester.takeException(), isNull);

    await tester.pumpWidget(codelabCommandPaletteFilteredPreview());
    expect(tester.takeException(), isNull);

    await tester.pumpWidget(codelabCommandPaletteSelectedPreview());
    expect(tester.takeException(), isNull);

    tester.view.physicalSize = const Size(1280, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      SizedBox(
        width: 1180,
        height: 720,
        child: codelabWorkbenchLayoutPreview(),
      ),
    );
    expect(tester.takeException(), isNull);

    await tester.pumpWidget(
      SizedBox(
        width: 860,
        height: 720,
        child: codelabWorkbenchLayoutMediumPreview(),
      ),
    );
    expect(tester.takeException(), isNull);

    await tester.pumpWidget(
      SizedBox(
        width: 430,
        height: 720,
        child: codelabWorkbenchLayoutNarrowPreview(),
      ),
    );
    expect(tester.takeException(), isNull);
  });
}
