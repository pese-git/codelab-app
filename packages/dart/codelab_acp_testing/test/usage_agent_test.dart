// Тесты режима scripted-агента `withUsage` (задача 3.5 change
// `add-usage-extension`; design D2, D3, D7, D9, D23 Т3): настоящий процесс
// агента на Dart VM, кадры JSON-RPC построчно через stdin/stdout.
//
// Красный до задачи 3.9: режима `CodelabCompatibleStdioAgentMode.withUsage`
// ещё нет, файл не компилируется. Числа ниже фиксируют сценарий, на который
// опираются PTY-e2e CLI (3.6, `ctx 9%`, `$0.04`) и интеграционный тест app
// (3.8, 85 % и пять счётчиков); реализация 3.9 обязана их выдавать.

import 'dart:io';

import 'package:codelab_acp_testing/codelab_acp_testing.dart';
import 'package:test/test.dart';

import 'support/agent_process.dart';

/// Имя уведомления расширения (D2).
const _method = '_codelab/session/usage';

void main() {
  late Directory directory;
  late AgentProcess agent;

  setUp(() async {
    directory = await Directory.systemTemp.createTemp('usage_agent_');
    final script = await writeCodelabCompatibleStdioAgent(
      directory,
      mode: CodelabCompatibleStdioAgentMode.withUsage,
    );
    agent = await AgentProcess.start(script);
  });
  tearDown(() async {
    await agent.stop();
    await directory.delete(recursive: true);
  });

  /// `initialize` клиента, объявляющего `_meta.codelab.usage` версии [usage]
  /// (без аргумента — без объявления вовсе, но с блоком `_meta.codelab`).
  Future<Map<String, Object?>> initialize({Object? usage}) async {
    final response = await agent.request('initialize', {
      'protocolVersion': 1,
      'clientCapabilities': {
        '_meta': {
          'codelab': {'usage': ?usage},
        },
      },
    });
    return (response['result']! as Map).cast<String, Object?>();
  }

  /// Снимки `_codelab/session/usage`, пришедшие агенту-клиенту, по порядку.
  List<Map<String, Object?>> snapshots() => [
    for (final frame in agent.received)
      if (frame['method'] == _method)
        (frame['params']! as Map).cast<String, Object?>(),
  ];

  Map<String, Object?> sub(Map<String, Object?> from, String key) =>
      (from[key]! as Map).cast<String, Object?>();

  test('initialize advertises _meta.codelab.usage version 1', () async {
    final result = await initialize(usage: {'version': 1});

    final meta = sub(sub(result, 'agentCapabilities'), '_meta');
    expect(sub(meta, 'codelab')['usage'], {'version': 1});
  });

  test('the first turn sends step and turn snapshots before the response, '
      'context 9 % and session cost 0.04', () async {
    await initialize(usage: {'version': 1});
    final sessionId = await agent.newSession(directory.path);

    final response = await agent.prompt(sessionId, 'hello');
    expect(response['result'], {'stopReason': 'end_turn'});

    // Порядок D7: чанк ответа, снимок step, снимок turn — и только потом
    // ответ; его кадр в `received` не попадает, поэтому три кадра хода
    // уже все.
    final turnFrames = [
      for (final frame in agent.received)
        if (frame['method'] == _method)
          'usage:${(frame['params']! as Map)['trigger']}'
        else if (frame['method'] == 'session/update')
          (((frame['params']! as Map)['update']! as Map)['sessionUpdate']),
    ];
    expect(turnFrames, ['agent_message_chunk', 'usage:step', 'usage:turn']);

    final [step, turn] = snapshots();
    expect(step['sessionId'], sessionId);
    expect(step['seq'], 1);
    expect(step['trigger'], 'step');
    expect(step['turnId'], isA<String>());
    expect(sub(step, 'step')['index'], 0);
    expect(turn['seq'], 2);
    expect(turn['trigger'], 'turn');
    expect(turn['turnId'], step['turnId']);

    // Деньги — десятичные строки D9, валюта в корне.
    for (final snapshot in [step, turn]) {
      expect(snapshot['currency'], 'USD');
      expect(sub(snapshot, 'session')['cost'], '0.04');
      expect(sub(snapshot, 'context'), {
        'used': 18000,
        'size': 200000,
        'compactAt': 160000,
      });
    }
    expect(sub(turn, 'turn')['steps'], 1);
    expect(sub(turn, 'session')['turns'], 1);
    // Провайдер `reasoning` на первом ходу не сообщил — ключа нет (D2).
    expect(sub(turn, 'session')['tokens'], {
      'input': 12000,
      'output': 800,
      'cacheRead': 5000,
      'cacheWrite': 200,
    });
    expect(sub(turn, 'session')['tokens'], isNot(contains('reasoning')));
  });

  test('two sessions of one process keep seq, cost and tokens apart '
      '(D4: агрегаты на сессию)', () async {
    await initialize(usage: {'version': 1});
    final first = await agent.newSession(directory.path);
    final second = await agent.newSession(directory.path);

    await agent.prompt(first, 'a');
    await agent.prompt(second, 'b');

    final all = snapshots();
    for (final id in [first, second]) {
      final own = [
        for (final s in all)
          if (s['sessionId'] == id) s,
      ];
      expect([for (final s in own) s['seq']], [1, 2]);
      final session = sub(own.last, 'session');
      expect(session['turns'], 1);
      expect(session['cost'], '0.04');
      expect(session['tokens'], {
        'input': 12000,
        'output': 800,
        'cacheRead': 5000,
        'cacheWrite': 200,
      });
    }
  });

  test('the second turn sends context 85 % and all five token counters '
      'with seq continuing', () async {
    await initialize(usage: {'version': 1});
    final sessionId = await agent.newSession(directory.path);
    await agent.prompt(sessionId, 'first');
    agent.received.clear();

    final response = await agent.prompt(sessionId, 'second');
    expect(response['result'], {'stopReason': 'end_turn'});

    final [step, turn] = snapshots();
    expect([step['seq'], turn['seq']], [3, 4]);
    expect(step['turnId'], isNot(isNull));
    for (final snapshot in [step, turn]) {
      expect(sub(snapshot, 'context'), {
        'used': 170000,
        'size': 200000,
        'compactAt': 160000,
      });
    }
    // Ход: пять счётчиков, включая `reasoning` (D2), и стоимость хода.
    expect(sub(turn, 'turn')['tokens'], {
      'input': 20000,
      'output': 1500,
      'cacheRead': 140000,
      'cacheWrite': 8000,
      'reasoning': 300,
    });
    expect(sub(turn, 'turn')['cost'], '0.05');
    // Сессия — накопление двух ходов.
    expect(sub(turn, 'session')['turns'], 2);
    expect(sub(turn, 'session')['cost'], '0.09');
    // D4 п. 4: токены сессии — сумма ходов, а не токены последнего хода;
    // `reasoning` есть только у второго хода и входит в сумму как есть.
    expect(sub(turn, 'session')['tokens'], {
      'input': 32000,
      'output': 2300,
      'cacheRead': 145000,
      'cacheWrite': 8200,
      'reasoning': 300,
    });
    expect(sub(turn, 'session')['steps'], 2);
    expect(sub(step, 'session')['tokens'], sub(turn, 'session')['tokens']);
  });

  test('a client without the usage declaration gets no snapshots', () async {
    await initialize();
    final sessionId = await agent.newSession(directory.path);

    final response = await agent.prompt(sessionId, 'hello');

    expect(response['result'], {'stopReason': 'end_turn'});
    expect(snapshots(), isEmpty);
    expect(agent.updates, isNotEmpty); // ответ агента при этом идёт
  });

  test('a client declaring another version gets no snapshots (D3)', () async {
    await initialize(usage: {'version': 2});
    final sessionId = await agent.newSession(directory.path);

    await agent.prompt(sessionId, 'hello');

    expect(snapshots(), isEmpty);
  });

  // change `add-usage-ledger`, D8, задача 2.8: `session/load` режима
  // `withUsage` отвечает без истории и шлёт снимок `load` с суммой двух
  // прежних ходов; следующий ход — третий.
  group('session/load (add-usage-ledger, D8)', () {
    test('initialize advertises loadSession', () async {
      final result = await initialize(usage: {'version': 1});

      expect(sub(result, 'agentCapabilities')['loadSession'], isTrue);
    });

    test('the load snapshot follows the answer with the full sum, without '
        'turnId, step, turn and context', () async {
      await initialize(usage: {'version': 1});

      final response = await agent.request('session/load', {
        'sessionId': 'journal-1',
        'cwd': directory.path,
        'mcpServers': <Object?>[],
      });

      expect(response['result'], <String, Object?>{});
      // Барьер: агент пишет кадры по порядку, ответ следующего запроса
      // приходит после снимка `load`.
      await agent.newSession(directory.path);
      final load = snapshots().single;
      expect(load['trigger'], 'load');
      expect(load['seq'], 1);
      expect(load['sessionId'], 'journal-1');
      expect(
        load.keys.toSet().intersection({'turnId', 'step', 'turn', 'context'}),
        isEmpty,
      );
      final session = sub(load, 'session');
      expect(session['turns'], 2);
      expect(session['steps'], 2);
      expect(session['cost'], '0.09');
      expect(session, isNot(contains('partial')));
    });

    test('the next turn continues the sum: seq 2 and 3, turns 3', () async {
      await initialize(usage: {'version': 1});
      await agent.request('session/load', {
        'sessionId': 'journal-1',
        'cwd': directory.path,
        'mcpServers': <Object?>[],
      });

      await agent.prompt('journal-1', 'more');

      final frames = snapshots();
      expect(frames.map((f) => f['seq']), [1, 2, 3]);
      expect(sub(frames.last, 'session')['turns'], 3);
      expect(sub(frames.last, 'session')['cost'], '0.14');
    });

    test('a client without the usage declaration gets no snapshot', () async {
      await initialize();

      final response = await agent.request('session/load', {
        'sessionId': 'journal-1',
        'cwd': directory.path,
        'mcpServers': <Object?>[],
      });

      expect(response['result'], <String, Object?>{});
      expect(snapshots(), isEmpty);
    });
  });
}
