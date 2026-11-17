// Организм `CodeLabTerminalPane` (задачи 2.3–2.4 change
// `add-integrated-terminal`; спецификация `integrated-terminal` «Панель
// Terminal в доке инструментов»; design.md D3, D12).
//
// Красный тест: организма ещё нет (задача 2.4). Ожидаемый публичный API
// фиксирует этот тест:
//
// * `CodeLabTerminalTab({required id, required title, required statusLabel,
//   statusTone = CodeLabTone.neutral})` — данные вкладки, без логики;
// * `CodeLabTerminalPane({required tabs, required activeTabId,
//   required hasSession, required content, disclosure, onSelected, onClosed,
//   onNewTab, onDisclosureClosed})`:
//   `hasSession == false` — подсказка «Open a session to use the terminal»
//   без «New terminal» и без `terminal-new-tab` (Q17); `tabs` пусто при
//   `hasSession` — пустое состояние с действием «New terminal»;
//   `disclosure` — текст предупреждения (`InfoBar`), `null` — не показывать;
//   `content` — слот с виджетом терминала активной вкладки, кит не знает
//   пакета рендера (`codelab_ui/AGENTS.md` §1–§2);
// * статические ключи, как у `CodeLabToolDock.paneKey`:
//   `CodeLabTerminalPane.tabKey(id)` = `terminal-tab-<id>`,
//   `closeKey(id)` = `terminal-tab-close-<id>`, `newTabKey` =
//   `terminal-new-tab`, `disclosureKey` = `terminal-disclosure`.
import 'package:codelab_ui/codelab_ui.dart';
import 'package:fluent_ui/fluent_ui.dart';
import 'package:flutter_test/flutter_test.dart';

const _tabs = [
  CodeLabTerminalTab(
    id: 'a',
    title: 'zsh',
    statusLabel: 'Running',
    statusTone: CodeLabTone.success,
  ),
  CodeLabTerminalTab(
    id: 'b',
    title: 'build',
    statusLabel: 'Exited 3',
    statusTone: CodeLabTone.warning,
  ),
];

Widget _host({
  List<CodeLabTerminalTab> tabs = _tabs,
  String? activeTabId = 'a',
  bool hasSession = true,
  String? disclosure,
  ValueChanged<String>? onSelected,
  ValueChanged<String>? onClosed,
  VoidCallback? onNewTab,
  VoidCallback? onDisclosureClosed,
  Widget content = const Text('terminal-content'),
}) => FluentApp(
  home: SizedBox(
    width: 520,
    height: 360,
    child: CodeLabTerminalPane(
      tabs: tabs,
      activeTabId: activeTabId,
      hasSession: hasSession,
      disclosure: disclosure,
      onSelected: onSelected,
      onClosed: onClosed,
      onNewTab: onNewTab,
      onDisclosureClosed: onDisclosureClosed,
      content: content,
    ),
  ),
);

Finder _badge(String label, CodeLabTone tone) => find.byWidgetPredicate(
  (w) => w is CodeLabBadge && w.label == label && w.tone == tone,
);

void main() {
  test('exports the terminal pane through the public package API', () {
    expect(CodeLabTerminalPane, isA<Type>());
    expect(CodeLabTerminalTab, isA<Type>());
  });

  testWidgets('has static keys for tabs, close, new tab and disclosure', (
    tester,
  ) async {
    expect(CodeLabTerminalPane.tabKey('a'), const ValueKey('terminal-tab-a'));
    expect(
      CodeLabTerminalPane.closeKey('a'),
      const ValueKey('terminal-tab-close-a'),
    );
    expect(CodeLabTerminalPane.newTabKey, const ValueKey('terminal-new-tab'));
    expect(
      CodeLabTerminalPane.disclosureKey,
      const ValueKey('terminal-disclosure'),
    );
  });

  testWidgets('renders a tab per entry with its title, status tag and close '
      'button', (tester) async {
    await tester.pumpWidget(_host());

    expect(find.byKey(CodeLabTerminalPane.tabKey('a')), findsOneWidget);
    expect(find.byKey(CodeLabTerminalPane.tabKey('b')), findsOneWidget);
    expect(find.byKey(CodeLabTerminalPane.closeKey('a')), findsOneWidget);
    expect(find.byKey(CodeLabTerminalPane.closeKey('b')), findsOneWidget);
    expect(find.text('zsh'), findsOneWidget);
    expect(find.text('build'), findsOneWidget);
    // Тег статуса — из переданных подписи и тона, кит их не вычисляет.
    expect(_badge('Running', CodeLabTone.success), findsOneWidget);
    expect(_badge('Exited 3', CodeLabTone.warning), findsOneWidget);
  });

  testWidgets('selects, closes and adds tabs through callbacks', (
    tester,
  ) async {
    final selected = <String>[];
    final closed = <String>[];
    var added = 0;
    await tester.pumpWidget(
      _host(
        onSelected: selected.add,
        onClosed: closed.add,
        onNewTab: () => added++,
      ),
    );

    await tester.tap(find.byKey(CodeLabTerminalPane.tabKey('b')));
    await tester.pump(const Duration(milliseconds: 100));
    await tester.tap(find.byKey(CodeLabTerminalPane.closeKey('b')));
    await tester.pump(const Duration(milliseconds: 100));
    await tester.tap(find.byKey(CodeLabTerminalPane.newTabKey));
    await tester.pump(const Duration(milliseconds: 100));

    expect(selected, ['b']);
    expect(closed, ['b']);
    expect(added, 1);
  });

  testWidgets('shows the slot content for the active tab', (tester) async {
    await tester.pumpWidget(_host());

    expect(find.text('terminal-content'), findsOneWidget);
    expect(find.text('Open a session to use the terminal'), findsNothing);
    expect(find.text('New terminal'), findsNothing);
  });

  testWidgets('empty state with a session offers "New terminal"', (
    tester,
  ) async {
    var added = 0;
    await tester.pumpWidget(
      _host(tabs: const [], activeTabId: null, onNewTab: () => added++),
    );

    expect(find.text('terminal-content'), findsNothing);
    expect(find.text('New terminal'), findsOneWidget);

    await tester.tap(find.text('New terminal'));
    await tester.pump(const Duration(milliseconds: 100));

    expect(added, 1);
  });

  testWidgets('without a session shows the hint and no way to start a '
      'terminal (Q17)', (tester) async {
    await tester.pumpWidget(
      _host(tabs: const [], activeTabId: null, hasSession: false),
    );

    expect(find.text('Open a session to use the terminal'), findsOneWidget);
    expect(find.text('New terminal'), findsNothing);
    expect(find.byKey(CodeLabTerminalPane.newTabKey), findsNothing);
    expect(find.text('terminal-content'), findsNothing);
  });

  testWidgets('shows the disclosure and reports closing it', (tester) async {
    var closed = 0;
    await tester.pumpWidget(
      _host(
        disclosure: 'Commands run with your permissions.',
        onDisclosureClosed: () => closed++,
      ),
    );

    expect(find.byKey(CodeLabTerminalPane.disclosureKey), findsOneWidget);
    expect(find.text('Commands run with your permissions.'), findsOneWidget);

    // Крестик встроенного `InfoBar`.
    await tester.tap(
      find.descendant(
        of: find.byKey(CodeLabTerminalPane.disclosureKey),
        matching: find.byType(IconButton),
      ),
    );
    await tester.pump(const Duration(milliseconds: 100));

    expect(closed, 1);
  });

  testWidgets('hides the disclosure when no text is passed', (tester) async {
    await tester.pumpWidget(_host());

    expect(find.byKey(CodeLabTerminalPane.disclosureKey), findsNothing);
  });
}
