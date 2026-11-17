@Tags(['slow'])
library;

import 'dart:convert';

import 'package:codelab_agent_core/codelab_agent_core.dart';
import 'package:test/test.dart';

import 'support/server_harness.dart';
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
/// Пороги: размер JSON — не больше 16 МБ, построение плюс кодирование — не
/// больше 5 с. Время реплея `session/load` в замер не входит: оно нужно, чтобы
/// сессия открылась в сервере, а не для ответа журнала. Красный до задачи 2.6:
/// пока метода нет, сервер отвечает `-32601`.
void main() {
  const turns = 1000;
  const stepsPerTurn = 40;
  const maxBytes = 16 * 1024 * 1024;
  const maxTime = Duration(seconds: 5);

  late ServerHarness h;

  tearDown(() => h.dispose());

  test(
    'the ledger of $turns turns x $stepsPerTurn steps fits 16 MiB and 5 s',
    () async {
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
      final store = JournalStore();
      store.prebuilt[id] = journal.snapshot();
      h = await ServerHarness.start(sessions: store);
      await h.initialize();
      final loaded = await h.client.request('session/load', {
        'sessionId': id.value,
        'cwd': '/work/demo',
        'mcpServers': <Object?>[],
      }, const Duration(minutes: 5));
      expect(loaded.error, isNull);

      final watch = Stopwatch()..start();
      final response = await h.client.request('_codelab/session/usage/ledger', {
        'sessionId': id.value,
      }, const Duration(minutes: 1));
      final encoded = utf8.encode(jsonEncode(response.result));
      watch.stop();

      // Размер и время идут в вывод теста: по ним решают, нужна ли пагинация.
      // ignore: avoid_print — замер R4 печатается намеренно (задача 2.4).
      print(
        'usage ledger $turns x $stepsPerTurn: ${encoded.length} bytes '
        '(${(encoded.length / 1024 / 1024).toStringAsFixed(2)} MiB), '
        'build + encode ${watch.elapsedMilliseconds} ms',
      );
      expect(response.error, isNull);
      final result = response.resultMap;
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
