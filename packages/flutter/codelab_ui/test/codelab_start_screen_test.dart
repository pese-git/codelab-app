// Стартовый экран и подпись кнопки повтора (задача B3.4 change
// `require-project-folder`; design.md D18): виджеты без логики, только
// отображение переданного и вызов колбэков.

import 'package:codelab_ui/codelab_ui.dart';
import 'package:fluent_ui/fluent_ui.dart';
import 'package:flutter_test/flutter_test.dart';

Widget _host(Widget child) => FluentApp(
  home: ScaffoldPage(content: Center(child: child)),
);

void main() {
  sidebarExpandedTests();
  testWidgets('the start screen shows its message and calls the action', (
    tester,
  ) async {
    var taps = 0;
    await tester.pumpWidget(
      _host(
        CodeLabStartScreen(
          message: 'Start a new session in app.',
          actionLabel: 'New session',
          actionKey: const ValueKey('start-new-session'),
          onAction: () => taps++,
        ),
      ),
    );

    expect(find.text('Start a new session in app.'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('start-new-session')));
    await tester.pump(const Duration(seconds: 1));
    expect(taps, 1);
  });

  testWidgets('a busy start screen shows the progress label and keeps the '
      'action (D17: several intents are one start)', (tester) async {
    await tester.pumpWidget(
      _host(
        CodeLabStartScreen(
          message: 'Start a new session in app.',
          actionLabel: 'New session',
          actionKey: const ValueKey('start-new-session'),
          busyLabel: 'Starting Embedded agent…',
          onAction: () {},
        ),
      ),
    );

    expect(find.text('Starting Embedded agent…'), findsOneWidget);
    expect(find.byKey(const ValueKey('start-new-session')), findsOneWidget);
  });

  testWidgets('the retry label of the connection screen and banner is a '
      'parameter', (tester) async {
    await tester.pumpWidget(
      _host(
        Column(
          children: [
            CodeLabConnectionScreen(
              status: CodeLabConnectionStatus.failed,
              transportLabel: 'stdio',
              profileLabel: 'Agent',
              onReconnect: () {},
              reconnectLabel: 'Retry',
            ),
            CodeLabConnectionBanner(
              status: CodeLabConnectionBannerStatus.lost,
              onReconnect: () {},
              reconnectLabel: 'Retry',
            ),
          ],
        ),
      ),
    );

    expect(find.text('Retry'), findsNWidgets(2));
    expect(find.text('Reconnect'), findsNothing);
  });
}

// Q23 change `require-project-folder`: не выбранная группа с `expanded`
// раскрыта и показывает сессии со статусом (параметр без логики; решение —
// у маппера app).
void sidebarExpandedTests() {
  testWidgets('a non-current group with expanded shows its running session', (
    tester,
  ) async {
    await tester.pumpWidget(
      FluentApp(
        home: ScaffoldPage(
          content: SizedBox(
            width: 320,
            height: 600,
            child: CodeLabSessionSidebar(
              projects: const [
                CodeLabSidebarProject(
                  path: '/work/b',
                  name: 'b',
                  current: true,
                ),
                CodeLabSidebarProject(
                  path: '/work/a',
                  name: 'a',
                  expanded: true,
                  sessions: [
                    CodeLabSessionListItem(
                      id: 'sa',
                      title: 'Long task',
                      status: CodeLabSessionStatus.running,
                    ),
                  ],
                ),
              ],
              activeSessionId: null,
              onSessionSelected: (_) {},
            ),
          ),
        ),
      ),
    );

    expect(find.text('Long task'), findsOneWidget);
  });
}
