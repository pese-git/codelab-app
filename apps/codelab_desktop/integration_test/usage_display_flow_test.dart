// Приёмка строки статуса сессии под композером на реальном агенте (change
// `add-usage-extension`, задача 3.8, D-09; design.md D11, D23 Т2;
// agent-workbench-ui «Строка статуса сессии под композером»: «Агент без
// расширения», «Два хода», «Контекст близко к пределу»).
//
// Режим `withUsage` и числа (зафиксированы тестом протокольщика
// `codelab_acp_testing/test/usage_agent_test.dart`, задача 3.5):
//  - ход 1: стоимость сессии `0.04`, контекст 18 000 из 200 000 (9 %);
//  - ход 2: контекст 170 000 из 200 000 (85 %, `warning`), токены хода
//    input 20 000, output 1 500, cacheRead 140 000, cacheWrite 8 000,
//    reasoning 300, стоимость хода `0.05`, сессии `0.09`.
// Режим `withUsage` для scripted-агента выбирает режим стенда; для `dart` и
// `embedded` его `wireName` выбирает сценарий модели
// `llm_scripts/with_usage.json` (цены модели, `contextWindow`, `usage` шагов;
// задача 3.9): тот же сценарий обязан давать именно эти числа.
//
// Сценарий «агент без расширения» возможен только со scripted-агентом
// (Dart-агент и встроенный объявляют `usage` всегда, D3), поэтому
// `skip: !e2e.isScripted`.
//
// В `feature/*` файл не запускается (AGENTS.md §21): его проверяет только
// `fvm flutter analyze`; прогон — `test:e2e:app:usage` в `release/*`.

import 'dart:io';

import 'package:codelab_acp_testing/codelab_acp_testing.dart';
import 'package:codelab_desktop/app/app_scope.dart';
import 'package:codelab_desktop/app/codelab_app_widget.dart';
import 'package:codelab_ui/codelab_ui.dart';
import 'package:fluent_ui/fluent_ui.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

import 'support/e2e_agent.dart';

const _usageKey = ValueKey('status-bar-usage');
const _costKey = ValueKey('status-bar-cost');
const _contextKey = ValueKey('status-bar-context');

Finder _in(ValueKey<String> key, Finder matching) =>
    find.descendant(of: find.byKey(key), matching: matching);

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  final e2e = E2eAgent.current;

  Future<void> waitFor(
    WidgetTester tester,
    bool Function() done,
    String reason,
  ) async {
    final deadline = DateTime.now().add(const Duration(seconds: 15));
    while (!done() && DateTime.now().isBefore(deadline)) {
      await tester.pump(const Duration(milliseconds: 100));
    }
    expect(done(), isTrue, reason: reason);
  }

  testWidgets(
    'an agent without the extension shows «usage: —» and no numbers'
    '${e2e.isScripted ? '' : ' [skipped: the Dart and embedded agents always declare usage]'}',
    skip: !e2e.isScripted,
    (tester) async {
      await tester.pumpWidget(e2e.bootstrap());
      await tester.pumpAndSettle();

      final dir = await Directory.systemTemp.createTemp(
        'codelab_app_usage_none_e2e_',
      );
      addTearDown(() async {
        if (await dir.exists()) {
          await dir.delete(recursive: true);
        }
      });
      final launch = await e2e.launch(
        dir,
        mode: CodelabCompatibleStdioAgentMode.normal,
      );
      final shellCubit = codeLabDependenciesOf(
        tester.element(find.byType(CodeLabApp)),
      ).shellCubit;
      await launch.connect(tester, shellCubit);

      await tester.tap(find.byKey(const ValueKey('new-session-button')));
      await tester.pumpAndSettle();
      await shellCubit.submitPrompt('hello');
      await waitFor(
        tester,
        () => shellCubit.state.turnState == null,
        'the turn must finish',
      );
      await tester.pump(const Duration(milliseconds: 300));

      expect(_in(_usageKey, find.text('usage: —')), findsOneWidget);
      expect(find.byKey(_costKey), findsNothing);
      expect(find.byKey(_contextKey), findsNothing);
    },
  );

  testWidgets(
    'two turns: the turn and the session cost, five counters in the hint, '
    'context 85% in warning',
    (tester) async {
      await tester.pumpWidget(e2e.bootstrap());
      await tester.pumpAndSettle();

      final dir = await Directory.systemTemp.createTemp(
        'codelab_app_usage_e2e_',
      );
      addTearDown(() async {
        if (await dir.exists()) {
          await dir.delete(recursive: true);
        }
      });
      final launch = await e2e.launch(
        dir,
        mode: CodelabCompatibleStdioAgentMode.withUsage,
      );
      final shellCubit = codeLabDependenciesOf(
        tester.element(find.byType(CodeLabApp)),
      ).shellCubit;
      await launch.connect(tester, shellCubit);

      await tester.tap(find.byKey(const ValueKey('new-session-button')));
      await tester.pumpAndSettle();

      // Ход 1: контекст 9 %, стоимость сессии $0.04.
      await shellCubit.submitPrompt('first');
      await waitFor(
        tester,
        () =>
            shellCubit.state.turnState == null &&
            _in(_contextKey, find.textContaining('9%')).evaluate().isNotEmpty,
        'the first snapshot must reach the status bar',
      );
      await tester.pump(const Duration(milliseconds: 300));
      expect(_in(_costKey, find.textContaining(r'session $0.04')), findsOne);

      // Ход 2: поле хода — второй ход, поле сессии — сумма сессии.
      await shellCubit.submitPrompt('second');
      await waitFor(
        tester,
        () =>
            shellCubit.state.turnState == null &&
            _in(_contextKey, find.textContaining('85%')).evaluate().isNotEmpty,
        'the second snapshot must reach the status bar',
      );
      await tester.pump(const Duration(milliseconds: 300));

      // Вход = 20 000 + 140 000 + 8 000 = 168 000 (D24: `168.0k`).
      expect(_in(_usageKey, find.text('168.0k → 1.5k')), findsOneWidget);
      expect(
        _in(_costKey, find.text(r'$0.05 · session $0.09')),
        findsOneWidget,
      );

      final badge = tester.widget<CodeLabBadge>(
        _in(_contextKey, find.byType(CodeLabBadge)),
      );
      expect(badge.tone, CodeLabTone.warning);
      expect(badge.label, startsWith('85%'));

      // Подсказка токенов — пять счётчиков.
      final hint = tester
          .widget<Tooltip>(_in(_usageKey, find.byType(Tooltip)))
          .message!;
      for (final counter in [
        'input',
        'output',
        'cache read',
        'cache write',
        'reasoning',
      ]) {
        expect(hint, contains(counter));
      }
    },
  );
}
