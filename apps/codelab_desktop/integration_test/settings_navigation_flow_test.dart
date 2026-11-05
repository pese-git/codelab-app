// Навигация настроек на устройстве (задача 3.9 change
// `add-app-settings-shell`; spec app-settings «Доступ к настройкам»,
// design.md D1, D2, D19).
//
// В `feature/*` файл только компилируется (`fvm flutter analyze`); на
// устройстве или симуляторе его запускает `release/<version>` (AGENTS.md
// §21).

import 'package:codelab_desktop/app/app_scope.dart';
import 'package:codelab_ui/codelab_ui.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'support/e2e_agent.dart';

/// Модификатор «команда» платформы: Cmd на macOS, Ctrl на остальных.
LogicalKeyboardKey get _commandKey =>
    defaultTargetPlatform == TargetPlatform.macOS
    ? LogicalKeyboardKey.metaLeft
    : LogicalKeyboardKey.controlLeft;

Future<void> _pressCommandComma(WidgetTester tester) async {
  await tester.sendKeyDownEvent(_commandKey);
  await tester.sendKeyEvent(LogicalKeyboardKey.comma);
  await tester.sendKeyUpEvent(_commandKey);
  await tester.pumpAndSettle();
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('Cmd/Ctrl+, opens "Connection" on the first launch, the last '
      'page is remembered, Esc returns to the session', (tester) async {
    await tester.pumpWidget(E2eAgent.current.bootstrap());
    await tester.pumpAndSettle();
    final connection = find.byKey(const ValueKey('settings-nav-connection'));
    expect(connection, findsNothing);

    await _pressCommandComma(tester);

    // Первое открытие: страницы ещё нет в настройках, открывается
    // «Connection».
    expect(connection, findsOneWidget);
    expect(
      find.byKey(const ValueKey('connection-add-profile')),
      findsOneWidget,
    );
    expect(
      (await SharedPreferences.getInstance()).getString(
        'codelab.settings.last_page',
      ),
      'connection',
    );

    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();
    expect(connection, findsNothing);
    expect(find.byKey(CodeLabSessionSidebar.settingsKey), findsOneWidget);

    // Повторное открытие — на последней странице.
    await _pressCommandComma(tester);
    expect(connection, findsOneWidget);

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pumpAndSettle();
    await closeCodeLabRootScope();
  });
}
