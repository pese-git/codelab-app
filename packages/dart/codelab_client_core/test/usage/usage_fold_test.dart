// Прямые тесты `UsageFold` и `ContextFillView.compactionSoon` (задача 2.5
// change `add-usage-extension`; design.md, D7, D21 Т2, Т4; решение Q3 (б)).
//
// Почему отдельно от `session_usage_test.dart`: тот проверяет свёртку через
// `ClientWorkspace`, а границы правила «какой снимок применять» (смена
// поколения, опоздание старого поколения, порог 0.9) надёжнее фиксировать
// на чистом классе — без сокетов и порядка кадров.

import 'package:codelab_acp_protocol/codelab_acp_protocol.dart';
import 'package:codelab_client_core/codelab_client_core.dart';
import 'package:test/test.dart';

const _sessionId = SessionId('s1');

const _zeroTotals = UsageTotals(
  tokens: TokenCounts(input: 0, output: 0, cacheRead: 0, cacheWrite: 0),
);

UsageSnapshot _snapshot(int seq) => UsageSnapshot(
  sessionId: _sessionId,
  seq: seq,
  trigger: UsageTrigger.step,
  session: _zeroTotals,
);

const _turnA = UsageTotals(
  tokens: TokenCounts(input: 10, output: 0, cacheRead: 0, cacheWrite: 0),
);
const _turnB = UsageTotals(
  tokens: TokenCounts(input: 20, output: 0, cacheRead: 0, cacheWrite: 0),
);

UsageSnapshot _turnSnapshot(int seq, {String? turnId, UsageTotals? turn}) =>
    UsageSnapshot(
      sessionId: _sessionId,
      seq: seq,
      trigger: UsageTrigger.step,
      turnId: turnId,
      turn: turn,
      session: _zeroTotals,
    );

void main() {
  group('UsageFold.lastTurn (D8: привязан к turnId)', () {
    test('снимок без turnId не меняет lastTurn', () {
      var fold = UsageFold.initial(declared: true);
      fold = fold.apply(
        _turnSnapshot(1, turnId: 't1', turn: _turnA),
        generation: 1,
      )!;
      fold = fold.apply(_turnSnapshot(2), generation: 1)!;

      expect(fold.view.lastTurn, _turnA);
    });

    test('тот же turnId обновляет lastTurn: ход идёт', () {
      var fold = UsageFold.initial(declared: true);
      fold = fold.apply(
        _turnSnapshot(1, turnId: 't1', turn: _turnA),
        generation: 1,
      )!;
      fold = fold.apply(
        _turnSnapshot(2, turnId: 't1', turn: _turnB),
        generation: 1,
      )!;

      expect(fold.view.lastTurn, _turnB);
    });

    test('новый turnId без разобранного turn сбрасывает lastTurn в null', () {
      var fold = UsageFold.initial(declared: true);
      fold = fold.apply(
        _turnSnapshot(1, turnId: 't1', turn: _turnA),
        generation: 1,
      )!;
      fold = fold.apply(_turnSnapshot(2, turnId: 't2'), generation: 1)!;

      expect(fold.view.lastTurn, isNull);
    });
  });

  group('UsageFold', () {
    test('снимок нового поколения со seq: 1 применяется после seq: 5 '
        'старого (D7, D21 Т2: счёт нового агента начинается заново)', () {
      var fold = UsageFold.initial(declared: true);
      for (var seq = 1; seq <= 5; seq++) {
        fold = fold.apply(_snapshot(seq), generation: 1)!;
      }
      expect(fold.view.lastSeq, 5);

      final next = fold.apply(_snapshot(1), generation: 2);

      expect(next, isNotNull);
      expect(next!.generation, 2);
      expect(next.view.lastSeq, 1);
      expect(next.view.support, UsageSupport.reported);
    });

    test('снимок старого поколения отбрасывается после применения нового, '
        'даже с бо́льшим seq (D7, D21 Т2, Т4)', () {
      var fold = UsageFold.initial(declared: true);
      fold = fold.apply(_snapshot(1), generation: 1)!;
      fold = fold.apply(_snapshot(1), generation: 2)!;

      expect(fold.apply(_snapshot(1), generation: 1), isNull);
      expect(fold.apply(_snapshot(9), generation: 1), isNull);
    });

    test('дубль и опоздание в том же поколении отбрасываются (D7)', () {
      var fold = UsageFold.initial(declared: true);
      fold = fold.apply(_snapshot(3), generation: 1)!;

      expect(fold.apply(_snapshot(3), generation: 1), isNull);
      expect(fold.apply(_snapshot(2), generation: 1), isNull);
      expect(fold.apply(_snapshot(4), generation: 1), isNotNull);
    });
  });

  group('ContextFillView.compactionSoon', () {
    // Порог Q3 (б): used ≥ 0.9 × compactAt, сравнение в целых.
    test('ровно 90% порога — «скоро сжатие»', () {
      const view = ContextFillView(used: 900, size: 2000, compactAt: 1000);
      expect(view.compactionSoon, isTrue);
    });

    test('на токен ниже 90% порога — нет', () {
      const view = ContextFillView(used: 899, size: 2000, compactAt: 1000);
      expect(view.compactionSoon, isFalse);
    });

    test('огромные значения около 2^62 не переполняются на VM', () {
      const big = 1 << 62;
      // used·10 переполнило бы int64 и дало отрицательное число.
      expect(
        const ContextFillView(used: big, compactAt: big).compactionSoon,
        isTrue,
      );
      expect(
        const ContextFillView(used: big ~/ 2, compactAt: big).compactionSoon,
        isFalse,
      );
      expect(
        const ContextFillView(used: 1, compactAt: big).compactionSoon,
        isFalse,
      );
    });

    test('без compactAt — всегда нет', () {
      const view = ContextFillView(used: 5000, size: 2000);
      expect(view.compactionSoon, isFalse);
    });
  });
}
