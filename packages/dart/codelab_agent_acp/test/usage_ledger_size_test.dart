@Tags(['slow'])
library;

import 'dart:convert';

import 'package:codelab_agent_acp/src/usage_accounting.dart';
import 'package:codelab_agent_core/codelab_agent_core.dart';
import 'package:test/test.dart';

import 'support/usage_journal.dart';

/// Замер R4: размер и время ответа `_codelab/session/usage/ledger` на журнале
/// из 1 000 ходов по 40 шагов (design.md change `add-usage-ledger`, D6, Q8
/// (а), R4; agent-acp-server «Запрос `_codelab/session/usage/ledger`»;
/// задача 2.4).
///
/// Почему: ответ отдаётся целиком, без пагинации. Если построение и
/// кодирование не укладываются в пороги, вопрос о пагинации (Q8 (б))
/// возвращается пользователю до итерации 3, а работа останавливается.
///
/// Что меряется: свёртка журнала (`buildUsageLedger`), проекция отчёта в
/// результат D6 (`UsageLedgerProjection`) и кодирование в JSON — то есть
/// всё, что запрос делает над журналом. Сервер и `session/load` в замере не
/// участвуют: реплей 80 000 записей кадрами `session/update` под
/// `flutter test` (путь CI: `melos run test` → `fvm flutter test`) идёт
/// минутами и квадратично растёт (150 ходов — 18 с, против секунд под
/// `dart test`), а к ответу журнала он отношения не имеет. Путь запроса через
/// сервер проверяет `usage_ledger_request_test.dart`.
///
/// Пороги: размер JSON — не больше 16 МБ, построение плюс кодирование — не
/// больше 5 с; размер считается в байтах UTF-8.
void main() {
  const turns = 1000;
  const stepsPerTurn = 40;
  const maxBytes = 16 * 1024 * 1024;
  const maxTime = Duration(seconds: 5);

  test(
    'the ledger of $turns turns x $stepsPerTurn steps fits 16 MiB and 5 s',
    () {
      final id = SessionId('01JB8Q2W6R9T3M5K7N1P4X8Z0C');
      final journal = UsageJournal(id);
      for (var t = 1; t <= turns; t++) {
        journal.user(
          'Ход $t: исправь тест и проверь результат на всех платформах',
        );
        for (var s = 0; s < stepsPerTurn; s++) {
          journal.toolStep(
            'call_${t}_$s',
            pricedUsage(1200 + s, 300, 10000, 800),
          );
        }
      }
      final snapshot = journal.snapshot();

      final watch = Stopwatch()..start();
      final report = UsageLedgerReport(
        ledger: buildUsageLedger(snapshot),
        state: UsageLedgerFileState.inMemory,
      );
      final result = UsageLedgerProjection.of(
        report,
      ).result(sessionId: id.value, seq: 0, running: false);
      final encoded = utf8.encode(jsonEncode(result));
      watch.stop();

      // Размер и время идут в вывод теста: по ним решают, нужна ли пагинация.
      // ignore: avoid_print — замер R4 печатается намеренно (задача 2.4).
      print(
        'usage ledger $turns x $stepsPerTurn: ${encoded.length} bytes '
        '(${(encoded.length / 1024 / 1024).toStringAsFixed(2)} MiB), '
        'build + encode ${watch.elapsedMilliseconds} ms',
      );
      expect((result['turns']! as List), hasLength(turns));
      expect(
        ((result['turns']! as List).first as Map)['steps'],
        hasLength(stepsPerTurn),
      );
      expect((result['total']! as Map)['steps'], turns * stepsPerTurn);
      expect(encoded.length, lessThanOrEqualTo(maxBytes));
      expect(watch.elapsed, lessThanOrEqualTo(maxTime));
    },
  );
}
