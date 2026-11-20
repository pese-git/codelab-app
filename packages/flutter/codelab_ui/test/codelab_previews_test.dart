import 'package:codelab_ui/src/molecules/codelab_molecule_previews.dart';
import 'package:codelab_ui/src/organisms/codelab_organism_previews.dart';
import 'package:codelab_ui/codelab_ui.dart';
import 'package:fluent_ui/fluent_ui.dart' show FluentTheme, ToggleSwitch;
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

    await tester.pumpWidget(codelabSessionStatusBarPreview());
    expect(tester.takeException(), isNull);
    expect(find.byType(CodeLabSessionStatusBar), findsOneWidget);

    await tester.pumpWidget(codelabSessionStatusBarClickablePreview());
    expect(tester.takeException(), isNull);
    expect(find.byType(CodeLabSessionStatusBar), findsOneWidget);

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

  testWidgets('selector bar preview renders without overflow', (tester) async {
    await tester.pumpWidget(codelabSelectorBarPreview());
    expect(tester.takeException(), isNull);
    expect(find.byType(CodeLabSelectorBar<String>), findsOneWidget);
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

  // Задача 5.6 change `add-provider-setup-ui` (D19): превью организма
  // `CodeLabStatusTable` в светлой и тёмной теме — функции
  // `codelabStatusTablePreview` и `codelabStatusTableDarkPreview` в
  // `codelab_organism_previews.dart` (реализация — задача 5.9).
  testWidgets('status table previews render in both themes', (tester) async {
    await tester.pumpWidget(codelabStatusTablePreview());
    expect(tester.takeException(), isNull);
    expect(find.byType(CodeLabStatusTable), findsOneWidget);
    // Строка с действием, строка сбоя и выключенная строка без действия.
    expect(find.byType(CodeLabButton), findsWidgets);
    expect(find.byType(CodeLabStatusIndicator), findsWidgets);

    await tester.pumpWidget(codelabStatusTableDarkPreview());
    expect(tester.takeException(), isNull);
    expect(
      FluentTheme.of(
        tester.element(find.byType(CodeLabStatusTable)),
      ).brightness,
      Brightness.dark,
    );
  });

  // Задача 3.2 change `add-app-skills-page` (D12): превью таблицы навыков.
  testWidgets('skills table preview shows tags, toggles and escaped text', (
    tester,
  ) async {
    await tester.pumpWidget(codelabSkillsTablePreview());
    expect(tester.takeException(), isNull);
    expect(find.byType(CodeLabBadge), findsWidgets);
    final toggles = tester
        .widgetList<ToggleSwitch>(find.byType(ToggleSwitch))
        .toList();
    expect(toggles.map((t) => t.checked), [true, false]);
    expect(toggles.last.onChanged, isNull);
    expect(find.text('deploy\\u202egpj'), findsOneWidget);
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

    // Панель Agents v1 (5b.1, D33): строки с отступом и дерево шагов.
    // `Overlay` превью хранит `initialEntries` в `State`: без сброса дерева
    // он показал бы записи предыдущего превью, а не панель.
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pumpWidget(codelabAgentsPanePreview());
    expect(tester.takeException(), isNull);
    expect(find.byType(CodeLabAgentsPane), findsOneWidget);
    expect(find.text('Review the change'), findsOneWidget);

    // Панель Usage (change `add-desktop-usage-pane`, D1): превью на готовых
    // строках; сброс дерева — по той же причине, что у панели Agents.
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pumpWidget(codelabUsagePanePreview());
    expect(tester.takeException(), isNull);
    expect(find.byType(CodeLabUsagePane), findsOneWidget);
    expect(find.text('This session'), findsOneWidget);

    // Сброс дерева: `Overlay` превью берёт записи только при создании.
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pumpWidget(codelabApprovalPromptPreview());
    expect(tester.takeException(), isNull);
    // Подсказки перехода больше нет (change `fix-approval-focus`, D14):
    // кнопки активного одобрения показывают сочетания ответа.
    expect(find.textContaining('to answer from the keyboard'), findsNothing);
    expect(find.byKey(CodeLabApprovalPrompt.focusFrameKey), findsNothing);

    // Превью с фокусом: рамка есть, подсказки нет.
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pumpWidget(codelabApprovalPromptFocusedPreview());
    await tester.pump();
    await tester.pump();
    expect(tester.takeException(), isNull);
    expect(find.byKey(CodeLabApprovalPrompt.focusFrameKey), findsOneWidget);
    expect(find.textContaining('to answer from the keyboard'), findsNothing);

    await tester.pumpWidget(codelabConnectionScreenPreview());
    expect(tester.takeException(), isNull);

    await tester.pumpWidget(codelabFileTreePreview());
    expect(tester.takeException(), isNull);
    await tester.pump();
    expect(tester.takeException(), isNull);

    await tester.pumpWidget(codelabFilePreviewPreview());
    expect(tester.takeException(), isNull);
    await tester.pump();
    expect(tester.takeException(), isNull);

    await tester.pumpWidget(codelabFilePreviewBinaryPreview());
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

  testWidgets('превью на русском показывает перевод кита, а текст агента нет', (
    tester,
  ) async {
    await tester.pumpWidget(codelabApprovalPromptRuPreview());

    expect(tester.takeException(), isNull);
    expect(find.text('Разрешить'), findsOneWidget);
    expect(find.text('Отклонить'), findsOneWidget);
    expect(find.text('Allow'), findsNothing);
    // Причина запроса приходит от агента и не переводится (D7).
    expect(
      find.text('The agent wants to verify the Flutter UI package.'),
      findsOneWidget,
    );
  });

  testWidgets('превью кейкапов и таблицы сочетаний рисуются без ошибок', (
    tester,
  ) async {
    await tester.pumpWidget(codelabKeycapsPreview());
    expect(tester.takeException(), isNull);
    expect(find.byType(CodeLabKeycaps), findsNWidgets(2));

    await tester.pumpWidget(codelabShortcutTablePreview());
    expect(tester.takeException(), isNull);
    expect(find.text('Allow always'), findsOneWidget);
  });

  testWidgets('превью таблицы сочетаний на русском: тексты и перевод союза', (
    tester,
  ) async {
    final handle = tester.ensureSemantics();
    await tester.pumpWidget(codelabShortcutTableRuPreview());

    expect(tester.takeException(), isNull);
    expect(find.text('Сочетание'), findsOneWidget);
    expect(find.text('Всегда разрешать'), findsOneWidget);
    expect(find.text('Allow always'), findsNothing);
    handle.dispose();
  });
}
