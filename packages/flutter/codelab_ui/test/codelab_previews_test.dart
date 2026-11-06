import 'package:codelab_ui/src/molecules/codelab_molecule_previews.dart';
import 'package:codelab_ui/src/organisms/codelab_organism_previews.dart';
import 'package:codelab_ui/codelab_ui.dart';
import 'package:fluent_ui/fluent_ui.dart' show FluentTheme;
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

    await tester.pumpWidget(codelabConnectionBannerPreview());
    expect(tester.takeException(), isNull);

    await tester.pumpWidget(codelabApprovalOptionGroupPreview());
    expect(tester.takeException(), isNull);

    await tester.pumpWidget(codelabSettingsSectionPreview());
    expect(tester.takeException(), isNull);

    // Виджеты формы (3.8a, D16): светлая и тёмная тема, все тона заметок и
    // оба состояния переключателя.
    await tester.pumpWidget(codelabFormPreview());
    expect(tester.takeException(), isNull);
    expect(find.byType(CodeLabForm), findsOneWidget);
    expect(find.byType(CodeLabFormRow), findsWidgets);
    expect(find.byType(CodeLabFormNote), findsNWidgets(3));
    expect(find.byType(CodeLabSegmentedControl<String>), findsOneWidget);

    await tester.pumpWidget(codelabFormDarkPreview());
    expect(tester.takeException(), isNull);
    expect(find.byType(CodeLabForm), findsOneWidget);
    expect(
      FluentTheme.of(tester.element(find.byType(CodeLabForm))).brightness,
      Brightness.dark,
    );
  });

  testWidgets('key-value list previews render in both themes', (tester) async {
    await tester.pumpWidget(codelabKeyValueListPreview());
    expect(tester.takeException(), isNull);
    expect(find.byType(CodeLabKeyValueList), findsOneWidget);

    await tester.pumpWidget(codelabKeyValueListDarkPreview());
    expect(tester.takeException(), isNull);
    expect(
      FluentTheme.of(
        tester.element(find.byType(CodeLabKeyValueList)),
      ).brightness,
      Brightness.dark,
    );
  });

  testWidgets('step breadcrumb previews render in both themes', (tester) async {
    await tester.pumpWidget(codelabStepBreadcrumbPreview());
    expect(tester.takeException(), isNull);
    expect(find.byType(CodeLabStepBreadcrumb), findsOneWidget);

    await tester.pumpWidget(codelabStepBreadcrumbDarkPreview());
    expect(tester.takeException(), isNull);
    expect(
      FluentTheme.of(
        tester.element(find.byType(CodeLabStepBreadcrumb)),
      ).brightness,
      Brightness.dark,
    );
  });

  testWidgets('organism previews render in bounded preview surfaces', (
    tester,
  ) async {
    await tester.pumpWidget(codelabTranscriptPanelFailedTurnPreview());
    expect(tester.takeException(), isNull);

    await tester.pumpWidget(codelabTranscriptPanelPreview());
    expect(tester.takeException(), isNull);

    await tester.pumpWidget(codelabTranscriptPanelThinkingPreview());
    expect(tester.takeException(), isNull);

    await tester.pumpWidget(codelabTranscriptPanelEmbeddedApprovalPreview());
    expect(tester.takeException(), isNull);

    await tester.pumpWidget(codelabTranscriptPanelVerbosePreview());
    expect(tester.takeException(), isNull);

    await tester.pumpWidget(codelabApprovalPromptPreview());
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

    await tester.pumpWidget(codelabSettingsNavigationPreview());
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);

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
