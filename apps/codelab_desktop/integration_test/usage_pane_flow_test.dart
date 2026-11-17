// Приёмка панели Usage на реальном агенте (change `add-desktop-usage-pane`,
// задача 3.5, D-09; design.md D1, D2, D5, D9; решение пользователя Q12 (а);
// agent-workbench-ui «Панель Usage»).
//
// Сценарии разделены по агентам, потому что ни один агент не даёт всего сразу:
//  - scripted-агент в режиме `withUsageBudget` присылает `budget` в снимках
//    usage, но журнала (`usageLedger`) не объявляет, поэтому панель «без
//    журнала» (D10): нет раскрытия хода, «Rebuild», CSV;
//  - Dart-агент и встроенный (`withUsage`, `llm_scripts/with_usage.json`)
//    ведут настоящий журнал, но лимитов `budget.*` в e2e у них нет.
// `This turn` и тик времени здесь не проверяются: ход scripted-агента
// мгновенный, их закрывают только widget-тесты задачи 3.3.
//
// Числа блока `Last turn` — режим `with_usage_budget` в
// `codelab_compatible_stdio_agent.dart` (ход 1): шаги `1 / 50`, токены
// `12000 + 800 = 12800` из `200000`, стоимость хода `0.04` из `0.5`, время
// `1500 мс` из `600000 мс`.
//
// В `feature/*` файл не запускается (AGENTS.md §21): его проверяет только
// `fvm flutter analyze`; прогон — `test:e2e:app:usage` в `release/*`.

import 'dart:convert';
import 'dart:io';

import 'package:codelab_acp_testing/codelab_acp_testing.dart';
import 'package:codelab_desktop/app/app_scope.dart';
import 'package:codelab_desktop/app/codelab_app_widget.dart';
import 'package:codelab_desktop/core/platform/usage_csv_saver.dart';
import 'package:fluent_ui/fluent_ui.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

import 'support/e2e_agent.dart';

/// Порт сохранения CSV, который пишет файл в каталог теста вместо системного
/// диалога (шов `createCodeLabRootScope(usageCsvSaver:)`, D5).
final class _DirectoryCsvSaver implements UsageCsvSaver {
  _DirectoryCsvSaver(this.directory);

  final Directory directory;
  String? savedName;
  File? file;

  @override
  Future<UsageCsvSaveResult> save({
    required String suggestedName,
    required String csv,
  }) async {
    savedName = suggestedName;
    final target = File('${directory.path}/$suggestedName');
    await target.writeAsString(csv);
    file = target;
    return const UsageCsvSaved();
  }
}

/// Строки хода таблицы `Per turn`: ключ `usage-turn-<id>`.
final _turnRows = find.byWidgetPredicate(
  (w) =>
      w.key is ValueKey<String> &&
      (w.key! as ValueKey<String>).value.startsWith('usage-turn-'),
);

/// Строки шагов раскрытого хода: ключ `usage-step-<id>`.
final _stepRows = find.byWidgetPredicate(
  (w) =>
      w.key is ValueKey<String> &&
      (w.key! as ValueKey<String>).value.startsWith('usage-step-'),
);

Finder _inBudgetRow(String id, Finder matching) => find.descendant(
  of: find.byKey(ValueKey('usage-budget-$id')),
  matching: matching,
);

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

  Future<Directory> tempDir(String prefix) async {
    final dir = await Directory.systemTemp.createTemp(prefix);
    addTearDown(() async {
      if (await dir.exists()) {
        await dir.delete(recursive: true);
      }
    });
    return dir;
  }

  testWidgets(
    'a click on the status row opens the pane without a ledger; '
    'the Last turn block shows the turn budget'
    '${e2e.isScripted ? '' : ' [skipped: the Dart and embedded agents have no budget limits in e2e]'}',
    skip: !e2e.isScripted,
    (tester) async {
      await tester.pumpWidget(e2e.bootstrap());
      await tester.pumpAndSettle();

      final dir = await tempDir('codelab_app_usage_budget_e2e_');
      final launch = await e2e.launch(
        dir,
        mode: CodelabCompatibleStdioAgentMode.withUsageBudget,
      );
      final shellCubit = codeLabDependenciesOf(
        tester.element(find.byType(CodeLabApp)),
      ).shellCubit;
      await launch.connect(tester, shellCubit);

      await tester.tap(find.byKey(const ValueKey('new-session-button')));
      await tester.pumpAndSettle();
      await shellCubit.submitPrompt('first');
      await waitFor(
        tester,
        () =>
            shellCubit.state.turnState == null &&
            find.byKey(const ValueKey('status-bar-cost')).evaluate().isNotEmpty,
        'the usage snapshot must reach the status bar',
      );
      await tester.pump(const Duration(milliseconds: 300));

      // Вся строка статуса — вход в панель (D6); панель ещё закрыта.
      expect(find.byKey(const ValueKey('usage-budget')), findsNothing);
      await tester.tap(find.byKey(const ValueKey('status-bar-usage')));
      await tester.pumpAndSettle();

      // Ход закончился (`ended`): блок называется `Last turn` (Q11 (а)).
      expect(find.text('Last turn'), findsOneWidget);
      expect(find.text('This turn'), findsNothing);
      expect(_inBudgetRow('steps', find.text('1 / 50')), findsOneWidget);
      expect(_inBudgetRow('tokens', find.text('12.8k / 200.0k')), findsOne);
      expect(_inBudgetRow('cost', find.text(r'$0.04 / $0.50')), findsOne);
      expect(_inBudgetRow('time', find.text('0:01 / 10:00')), findsOneWidget);

      // Агент без журнала (D10): ни «Rebuild», ни CSV, ни строк ходов.
      expect(find.byKey(const ValueKey('usage-rebuild')), findsNothing);
      expect(find.byKey(const ValueKey('usage-export')), findsNothing);
      expect(_turnRows, findsNothing);
    },
  );

  testWidgets(
    'the ledger pane expands a turn to steps, rebuilds from the log and '
    'exports CSV through the port'
    '${e2e.isScripted ? ' [skipped: scripted withUsage declares no ledger]' : ''}',
    // Журнал и «Rebuild» есть у настоящих агентов; scripted `withUsage` их не
    // объявляет (Q12 (а)).
    skip: e2e.isScripted,
    (tester) async {
      final dir = await tempDir('codelab_app_usage_pane_e2e_');
      final saver = _DirectoryCsvSaver(dir);
      await tester.pumpWidget(e2e.bootstrap(usageCsvSaver: saver));
      await tester.pumpAndSettle();

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
      await shellCubit.submitPrompt('first');
      await waitFor(
        tester,
        () =>
            shellCubit.state.turnState == null &&
            find.byKey(const ValueKey('status-bar-cost')).evaluate().isNotEmpty,
        'the usage snapshot must reach the status bar',
      );
      await tester.pump(const Duration(milliseconds: 300));

      await tester.tap(find.byKey(const ValueKey('status-bar-usage')));
      await tester.pumpAndSettle();

      // Журнал приезжает отдельным запросом при открытии панели (D3).
      await waitFor(
        tester,
        () => _turnRows.evaluate().isNotEmpty,
        'the ledger must list the finished turn',
      );
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('usage-ledger-status')), findsOne);

      // Раскрытие хода до шагов (D2 п. 4).
      expect(_stepRows, findsNothing);
      await tester.tap(_turnRows.first);
      await tester.pumpAndSettle();
      expect(_stepRows, findsWidgets);

      // «Rebuild from log»: запрос журнала с `rebuild`; ход остаётся в таблице.
      await tester.tap(find.byKey(const ValueKey('usage-rebuild')));
      await tester.pumpAndSettle();
      await waitFor(
        tester,
        () =>
            find.byKey(const ValueKey('usage-progress')).evaluate().isEmpty &&
            _turnRows.evaluate().isNotEmpty,
        'the rebuild must finish with the turn still listed',
      );
      // Сбой пересборки показал бы заметку; статус журнала — один из трёх
      // текстов маппера (`usage_pane_data.dart`).
      expect(find.byKey(const ValueKey('usage-note')), findsNothing);
      final status = tester.widget<Text>(
        find.descendant(
          of: find.byKey(const ValueKey('usage-ledger-status')),
          matching: find.byType(Text),
        ),
      );
      expect(
        status.data,
        anyOf(
          contains('up to date'),
          contains('rebuilt from journal'),
          contains('in memory'),
        ),
      );

      // Экспорт CSV: порт пишет файл во временный каталог теста.
      await tester.tap(find.byKey(const ValueKey('usage-export')));
      await tester.pumpAndSettle();
      await waitFor(
        tester,
        () => saver.file != null,
        'the CSV must reach the saver port',
      );
      expect(saver.savedName, matches(r'^codelab-usage-.+\.csv$'));
      final csv = utf8.decode(await saver.file!.readAsBytes());
      expect(
        csv,
        startsWith(
          'kind,turn,step,title,model,input,output,cache_read,cache_write,'
          'reasoning,cost,currency,partial',
        ),
      );
      // Заголовок и хотя бы одна строка хода.
      expect(csv.trim().split(RegExp(r'\r?\n')).length, greaterThan(1));
    },
  );
}
