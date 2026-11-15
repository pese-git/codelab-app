import 'dart:async';

import 'package:codelab_acp_protocol/codelab_acp_protocol.dart' as acp;
import 'package:codelab_agent_acp/src/session_bridge.dart';
import 'package:codelab_agent_core/codelab_agent_core.dart';
import 'package:test/test.dart';

import 'support/client_channel.dart';
import 'support/fake_bridge_session.dart';
import 'support/server_harness.dart' show scriptedModel;

/// Реплей `SessionBridge.replayInto` одним методом (замечание ревью
/// итерации 5 change `add-subagents-and-tasks`; D47 Т6, ACP-3, AGENTS.md §9).
///
/// Почему: двухшаговый `replay()` + `finishReplay()` при перекрытии реплеев
/// двух соединений отпускал придержанные кадры раньше времени, а исключение
/// между шагами оставляло сессию молчащей. `replayInto(emit)` отдаёт кадры
/// сам, держит буфер по счётчику реплеев и отпускает его в `finally`.
void main() {
  const root = SessionId('sess_fake');

  late FakeBridgeSession session;

  /// Лента порядка: `replay:<вид>` — кадр реплея, `live:<вид>` — кадр, ушедший
  /// в очередь соединения.
  late List<String> log;

  Future<SessionBridge> open() async {
    final channel = await ClientChannel.open(
      capabilities: const acp.ClientCapabilities(
        terminal: true,
        meta: {
          'codelab': {
            'subagentToolCalls': {'version': 1},
          },
        },
      ),
    );
    session = FakeBridgeSession();
    log = [];
    return SessionBridge(
      owner: Object(),
      sink: (n) => log.add('live:${n.update.toJson()['sessionUpdate']}'),
      link: channel.link,
      clock: channel.clock,
      logger: channel.logger,
    )..attach(session);
  }

  tearDown(() => session.dispose());

  Future<void> pump() async {
    for (var i = 0; i < 5; i++) {
      await Future<void>.delayed(Duration.zero);
    }
  }

  void emitLive() => session.emit(
    MessageDelta(
      root,
      delta: 'live',
      partial: AssistantMessage(
        content: const [],
        model: scriptedModel,
        usage: Usage.zero,
        stopReason: StopReason.stop,
        timestamp: DateTime.utc(2026),
      ),
    ),
  );

  void emitFrame(acp.SessionUpdate update) =>
      log.add('replay:${update.toJson()['sessionUpdate']}');

  test(
    'a live frame held during the replay goes after its frames, in order',
    () async {
      final bridge = await open();
      final gate = Completer<void>();
      session.replayTreeGates.add(gate);

      final replay = bridge.replayInto(emitFrame);
      await pump();
      emitLive();
      emitLive();
      await pump();
      expect(log, isEmpty, reason: 'ничего не уходит до конца чтения журналов');
      gate.complete();
      await replay;

      final firstLive = log.indexWhere((e) => e.startsWith('live:'));
      expect(firstLive, greaterThan(0));
      expect(
        log.sublist(0, firstLive).every((e) => e.startsWith('replay:')),
        isTrue,
      );
      expect(log.sublist(firstLive), [
        'live:agent_message_chunk',
        'live:agent_message_chunk',
      ]);
    },
  );

  test('replayTree throwing releases the held frames and rethrows', () async {
    final bridge = await open();
    final gate = Completer<void>();
    session
      ..replayTreeGates.add(gate)
      ..replayTreeError = StateError('journal is broken');

    final replay = bridge.replayInto(emitFrame);
    final failed = expectLater(replay, throwsStateError);
    await pump();
    emitLive();
    await pump();
    gate.complete();
    await failed;
    // Сессия не молчит: кадр, придержанный на время реплея, ушёл, а новые
    // кадры идут сразу.
    expect(log, ['live:agent_message_chunk']);
    emitLive();
    await pump();
    expect(log, ['live:agent_message_chunk', 'live:agent_message_chunk']);
  });

  test('an error of the emit callback releases the held frames', () async {
    final bridge = await open();
    final gate = Completer<void>();
    session.replayTreeGates.add(gate);

    final replay = bridge.replayInto((_) => throw StateError('closed'));
    final failed = expectLater(replay, throwsStateError);
    await pump();
    emitLive();
    gate.complete();
    await failed;

    expect(log, ['live:agent_message_chunk']);
    emitLive();
    await pump();
    expect(log, hasLength(2));
  });

  test(
    'overlapping replays hold the live frame until the last one ends',
    () async {
      final bridge = await open();
      final first = Completer<void>();
      final second = Completer<void>();
      session.replayTreeGates.addAll([first, second]);

      final a = bridge.replayInto((u) => log.add('replay-a'));
      await pump();
      emitLive();
      final b = bridge.replayInto((u) => log.add('replay-b'));
      await pump();

      // Первый реплей закончился, второй ещё читает журналы: живой кадр не
      // должен уйти раньше кадров второго.
      first.complete();
      await a;
      await pump();
      expect(log.where((e) => e.startsWith('live:')), isEmpty);

      second.complete();
      await b;

      final lastReplay = log.lastIndexWhere((e) => e.startsWith('replay-b'));
      final live = log.indexWhere((e) => e.startsWith('live:'));
      expect(live, greaterThan(lastReplay));
      expect(log.where((e) => e.startsWith('live:')), hasLength(1));
    },
  );

  test(
    'a client without the consent: plain replay, no hold, no tree read',
    () async {
      final channel = await ClientChannel.open();
      session = FakeBridgeSession();
      log = [];
      final bridge = SessionBridge(
        owner: Object(),
        sink: (n) => log.add('live:${n.update.toJson()['sessionUpdate']}'),
        link: channel.link,
        clock: channel.clock,
        logger: channel.logger,
      )..attach(session);

      await bridge.replayInto(emitFrame);

      expect(session.replayTreeCalls, 0);
      expect(log, isNotEmpty);
    },
  );
}
