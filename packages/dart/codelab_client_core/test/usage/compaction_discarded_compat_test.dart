// Совместимость клиента с отброшенным вызовом сжатия (задача 3.1 change
// `fix-discarded-compaction-usage`; design.md, D5, R7).
//
// Почему: агент теперь шлёт `_codelab/session/usage` с
// `trigger: "compactionDiscarded"` и в ответе журнала добавляет
// `summaries.discarded`. Правка клиента в этот change не входит (R7):
// версия 1 расширения требует от клиента принимать незнакомый повод и
// незнакомое поле. Тест фиксирует это поведение, `lib/` не меняется.

import 'package:codelab_acp_protocol/codelab_acp_protocol.dart';
import 'package:codelab_client_core/codelab_client_core.dart';
import 'package:test/test.dart';

const _sessionId = SessionId('s-1');

Map<String, Object?> _tokens([int input = 100, int output = 10]) => {
  'input': input,
  'output': output,
  'cacheRead': 5,
  'cacheWrite': 0,
};

/// Снимок повода `compactionDiscarded` по D5: только `session` и `context`,
/// без `turnId`, `step` и `turn`.
Map<String, Object?> _discardedParams(int seq) => {
  'sessionId': 's-1',
  'seq': seq,
  'trigger': 'compactionDiscarded',
  'session': {
    'turns': 3,
    'steps': 7,
    'tokens': _tokens(9100, 2100),
    'cost': '0.0372',
  },
  'currency': 'USD',
  'context': {'used': 22900, 'size': 200000, 'compactAt': 183616},
};

Map<String, Object?> _ledger({Map<String, Object?>? summaries}) => {
  'sessionId': 's-1',
  'seq': 12,
  'currency': 'USD',
  'ledger': {'status': 'rebuilt', 'records': 3},
  'total': {'turns': 1, 'steps': 1, 'tokens': _tokens(300, 30), 'cost': '0.5'},
  'turns': <Object?>[],
  'models': <Object?>[],
  'summaries':
      summaries ??
      {'count': 3, 'tokens': _tokens(40, 4), 'cost': '0.07', 'discarded': 2},
};

void main() {
  group('снимок с поводом compactionDiscarded', () {
    test('разбирается как UsageTrigger.unknown без предупреждений', () {
      final warnings = <(String, String)>[];

      final snapshot = UsageDecoder().decode(
        _discardedParams(5),
        onWarning: (field, reason) => warnings.add((field, reason)),
      )!;

      expect(snapshot.trigger, UsageTrigger.unknown);
      expect(snapshot.turnId, isNull);
      expect(snapshot.turn, isNull);
      expect(snapshot.session.tokens.input, 9100);
      expect(snapshot.context?.used, 22900);
      expect(warnings, isEmpty);
    });

    test('обновляет session и context и не трогает lastTurn', () {
      const turn = UsageTotals(
        tokens: TokenCounts(input: 10, output: 0, cacheRead: 0, cacheWrite: 0),
      );
      var fold = UsageFold.initial(declared: true);
      fold = fold.apply(
        UsageSnapshot(
          sessionId: _sessionId,
          seq: 4,
          trigger: UsageTrigger.step,
          turnId: 't1',
          turn: turn,
          session: const UsageTotals(
            tokens: TokenCounts(
              input: 1,
              output: 0,
              cacheRead: 0,
              cacheWrite: 0,
            ),
          ),
        ),
        generation: 1,
      )!;

      final discarded = UsageDecoder().decode(
        _discardedParams(5),
        onWarning: (_, _) {},
      )!;
      fold = fold.apply(discarded, generation: 1)!;

      expect(fold.view.lastSeq, 5);
      expect(fold.view.lastTurn, turn);
      expect(fold.view.session?.tokens.input, 9100);
      expect(fold.view.context?.used, 22900);
      expect(fold.view.context?.compactAt, 183616);
    });
  });

  group('ответ журнала с summaries.discarded', () {
    test('разбирается без предупреждений, count и токены из ответа', () {
      final warnings = <(String, String)>[];

      final view = const UsageLedgerDecoder().decode(
        _ledger(),
        onWarning: (field, reason) => warnings.add((field, reason)),
      )!;

      expect(warnings, isEmpty);
      expect(view.summaries, isNotNull);
      expect(view.summaries!.count, 3);
      expect(view.summaries!.tokens.input, 40);
      expect(view.summaries!.tokens.output, 4);
      expect(view.summaries!.cost!.micros, 70000);
    });
  });
}
