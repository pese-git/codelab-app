// Usage и заметка бюджета на корпусе фикстур (задача 2.7b change
// `add-usage-extension`; spec acp-golden-fixtures «Клиентский прогон»,
// «Причина бюджета у клиента»; design.md, D13, D21 Т7).
//
// `conformance:client` живёт в `codelab_client_acp`, который не зависит от
// kit, поэтому `SessionView.usage` и текст заметки проверяются здесь, на том
// же драйвере `runClientFixture` (`14-golden-fixtures.md` §14.10 допускает
// фабрику клиента kit). Драйвер сам падает на любом кадре клиента, которого
// нет в фикстуре, — так проверяется «клиент не отвечает на уведомления».

import 'package:codelab_acp_protocol/codelab_acp_protocol.dart';
import 'package:codelab_acp_testing/codelab_acp_testing.dart';
import 'package:codelab_client_acp/codelab_client_acp.dart';
import 'package:codelab_client_core/codelab_client_core.dart';
import 'package:test/test.dart';

/// Прогоняет [fixtureId] с рабочим пространством kit поверх клиента
/// фикстуры; возвращает вид сессии после сценария.
Future<SessionView> _runWithWorkspace(String fixtureId) async {
  final fixture = loadFixtureCorpus().singleWhere(
    (fixture) => fixture.id == fixtureId,
  );
  late ClientFixtureUser user;
  late ClientWorkspace workspace;
  final result = await runClientFixture<AcpClientApplication>(
    fixture,
    (env) {
      user = ClientFixtureUser(env);
      workspace = ClientWorkspace(
        backend: AcpClientBackend(user.app),
        resolvers: const [],
      );
      return user.app;
    },
    onBeforeExpect: (step) {
      // Запрос журнала в рабочем пространстве идёт через
      // `ClientWorkspace.refreshUsageLedger` (design.md change
      // `add-usage-ledger`, D10: `refreshUsageLedger(sessionId, {rebuild})`), а
      // не прямым вызовом приложения: состояние `SessionView.usageLedger`
      // ведёт рабочее пространство.
      if (step.expected['method'] == '_codelab/session/usage/ledger') {
        step.track(
          workspace.refreshUsageLedger(
            const SessionId(standardFixtureSessionId),
          ),
        );
        return;
      }
      user.act(step);
    },
  );
  addTearDown(() async {
    await workspace.dispose();
    await user.app.dispose();
  });
  expect(result.skipped, isFalse, reason: result.skipReason);
  return workspace.session(const SessionId(standardFixtureSessionId))!.current;
}

void main() {
  test('acp/prompt-usage-steps: the fold ends at the last snapshot of the '
      'fixture', () async {
    final view = await _runWithWorkspace('acp/prompt-usage-steps');

    final usage = view.usage;
    expect(usage.support, UsageSupport.reported);
    // Три снимка фикстуры: seq 1 и 2 (`step`), 3 (`turn`).
    expect(usage.lastSeq, 3);
    const tokens = TokenCounts(
      input: 2700,
      output: 700,
      cacheRead: 22000,
      cacheWrite: 800,
    );
    const money = Money(micros: 28200, currency: 'USD');
    const totals = UsageTotals(tokens: tokens, cost: money, steps: 2);
    expect(usage.lastTurn, totals);
    expect(usage.session, totals);
    expect(
      usage.context,
      const ContextFillView(used: 14700, size: 32768, compactAt: 24576),
    );
  });

  test('acp/prompt-turn-budget-exceeded: the turn notice names the limit '
      '(D10)', () async {
    final view = await _runWithWorkspace('acp/prompt-turn-budget-exceeded');

    final notices = view.transcript.whereType<NoticeItem>().where(
      (notice) => notice.kind == NoticeKind.turnStopped,
    );
    expect(notices.single.text, 'The turn stopped: budget exceeded: tokens.');
  });

  // Роль `client` фикстуры `acp/usage-ledger-request` (change
  // `add-usage-ledger`, задача 3.5; spec acp-golden-fixtures «Клиентский
  // прогон журнала»; design.md D10): после ответа `SessionView.usageLedger` —
  // `loaded` с одним ходом и двумя шагами.
  test('acp/usage-ledger-request: the ledger state is loaded with one turn '
      'and two steps', () async {
    final view = await _runWithWorkspace('acp/usage-ledger-request');

    final state = view.usageLedger;
    expect(state, isA<UsageLedgerLoaded>());
    final ledger = (state as UsageLedgerLoaded).view;
    expect(ledger.seq, 3);
    expect(ledger.turns, hasLength(1));
    expect(ledger.turns.single.steps, hasLength(2));
  });

  // Роль `client` фикстуры `acp/prompt-usage-budget` (change
  // `add-desktop-usage-pane`, задача 3.1; spec acp-golden-fixtures «Клиентский
  // прогон», design.md D7, D9, Q11 (а)): после снимка `turn` бюджет хода
  // итоговый.
  test('acp/prompt-usage-budget: the budget after the turn snapshot is '
      'final with steps, tokens and cost, without duration', () async {
    final view = await _runWithWorkspace('acp/prompt-usage-budget');

    final budget = view.usage.budget;
    expect(budget, isNotNull);
    expect(budget!.ended, isTrue);
    expect(budget.steps, const BudgetCount(used: 2, limit: 50));
    expect(budget.tokens, const BudgetCount(used: 3400, limit: 200000));
    expect(
      budget.cost,
      const BudgetCost(
        used: Money(micros: 28200, currency: 'USD'),
        limit: Money(micros: 500000, currency: 'USD'),
      ),
    );
    expect(budget.duration, isNull);
    // Свёртка закончилась на снимке `turn` (seq 3), как у prompt-usage-steps.
    expect(view.usage.lastSeq, 3);
  });
}
