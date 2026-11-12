import 'dart:async';

import 'package:codelab_acp_protocol/codelab_acp_protocol.dart' as acp;
import 'package:codelab_agent_acp/src/session_bridge.dart';
import 'package:codelab_agent_core/codelab_agent_core.dart';
import 'package:test/test.dart';

import 'support/client_channel.dart';
import 'support/server_harness.dart' show scriptedModel;

/// Детерминированный стенд гонки «клиентский запрос смены конфигурации и
/// `ModeChanged` встроенной команды `/mode`» (design.md change
/// `add-agent-builtin-slash-commands`, D6; ACP-3, ACP-11).
///
/// Почему не через сервер: в настоящем ядре смены конфигурации идут одна за
/// другой (`_serial`), и `ModeChanged` команды отделён от возврата
/// клиентского вызова считаными микрозадачами — гонку нельзя ни выдержать,
/// ни надёжно повторить. Фальшивая сессия задаёт порядок явно: клиентский
/// вызов держится на воротах, пока тест выпускает чужое `ModeChanged`.
///
/// Что проверяется: `config_option_update` чужой смены не принимается за эхо
/// клиентского запроса и не теряется, эхо запроса не дублирует его ответ
/// (ACP-11), а ответ на `session/prompt` не опережает задержанный кадр
/// (ACP-3).
void main() {
  late ClientChannel channel;
  late _FakeSession session;
  late SessionBridge bridge;
  late List<acp.SessionUpdate> sent;
  late List<String> log;

  setUp(() async {
    channel = await ClientChannel.open();
    session = _FakeSession();
    sent = [];
    log = [];
    bridge = SessionBridge(
      owner: Object(),
      sink: (n) {
        sent.add(n.update);
        log.add(_label(n.update));
      },
      link: channel.link,
      clock: channel.clock,
      logger: channel.logger,
    )..attach(session);
  });

  tearDown(() async {
    await session.dispose();
  });

  /// Прокачка очереди микрозадач и таймеров.
  Future<void> pump() async {
    for (var i = 0; i < 5; i++) {
      await Future<void>.delayed(Duration.zero);
    }
  }

  test('a foreign mode change during a client change keeps its '
      'config_option_update; the client echo gets none', () async {
    final client = bridge.setMode(ModeId.ask);
    await pump();
    // Эхо клиента (changeId 1) и чужая смена команды (changeId 2) — пока
    // клиентский вызов не вернулся.
    session.emit(ModeChanged(session.id, mode: ModeId.ask, changeId: 1));
    session.emit(ModeChanged(session.id, mode: ModeId.plan, changeId: 2));
    await pump();
    session.finishClientChange(
      const ConfigChangeResult(changeId: 1, mode: ModeId.ask),
    );
    await client;

    expect(log, [
      'current_mode_update:ask',
      'current_mode_update:plan',
      'config_option_update',
    ]);
    final snapshot = sent.last as acp.ConfigOptionUpdate;
    expect(snapshot.configOptions, isNotEmpty);
  });

  test('the response to session/prompt waits for the held frame '
      '(ACP-3)', () async {
    final client = bridge.setMode(ModeId.ask);
    await pump();
    session.emit(ModeChanged(session.id, mode: ModeId.ask, changeId: 1));
    session.emit(ModeChanged(session.id, mode: ModeId.plan, changeId: 2));
    await pump();

    final prompt = bridge
        .prompt(const [])
        .then((_) => log.add('response:prompt'));
    await pump();
    expect(
      log,
      isNot(contains('response:prompt')),
      reason: 'кадр чужой смены ещё придержан клиентским запросом',
    );

    session.finishClientChange(
      const ConfigChangeResult(changeId: 1, mode: ModeId.ask),
    );
    await client;
    await prompt;

    expect(log.indexOf('config_option_update'), isNonNegative);
    expect(
      log.indexOf('config_option_update'),
      lessThan(log.indexOf('response:prompt')),
    );
  });

  // ACP-5 (05-Prompt Turn.md, «Cancellation»): клиент прислал
  // `session/cancel` после того, как команда применила смену и ответила, но
  // до итога хода. Уведомления смены уже ушли, ответ на `session/prompt` —
  // `cancelled`, а не `end_turn` ядра.
  test('/mode plan then session/cancel: the frames stay, the response is '
      'cancelled (ACP-5)', () async {
    session.commandTurn = true;
    final prompt = bridge.prompt(const []);
    await pump();

    expect(bridge.cancel(), isTrue);
    session.commandRelease.complete();
    final response = await prompt;

    expect(response.stopReason, acp.StopReason.cancelled);
    expect(log, [
      'current_mode_update:plan',
      'config_option_update',
      'agent_message_chunk',
    ]);
  });
}

String _label(acp.SessionUpdate update) => switch (update) {
  acp.CurrentModeUpdate(:final currentModeId) =>
    'current_mode_update:${currentModeId.value}',
  acp.ConfigOptionUpdate() => 'config_option_update',
  acp.AgentMessageChunk() => 'agent_message_chunk',
  _ => update.runtimeType.toString(),
};

/// Сессия, у которой тест решает, когда вернётся клиентский `setMode` и
/// какие события выйдут раньше.
final class _FakeSession implements AgentSession {
  final _events = StreamController<AgentEvent>.broadcast(sync: true);
  final _gate = Completer<ConfigChangeResult>();

  /// Если задан, `prompt` публикует `ModeChanged` и сообщение команды, а
  /// `TurnEnded(completed)` — только после [commandRelease]: так тест
  /// подставляет `session/cancel` между применённой сменой и итогом хода.
  bool commandTurn = false;
  final commandRelease = Completer<void>();

  void emit(AgentEvent event) => _events.add(event);

  void finishClientChange(ConfigChangeResult result) => _gate.complete(result);

  Future<void> dispose() => _events.close();

  @override
  SessionId get id => const SessionId('sess_fake');

  @override
  Stream<AgentEvent> get events => _events.stream;

  @override
  ModelRef get model => scriptedModel;

  /// Каталог сессии (design.md change `require-project-folder`, D21): мост
  /// берёт варианты опции `model` из него, а не из каталога рантайма.
  @override
  ModelCatalog get models => FixedModelCatalog([scriptedModel]);

  @override
  ModeId get mode => ModeId.standard;

  @override
  ReasoningEffort get effort => ReasoningEffort.medium;

  @override
  List<AgentDefinition> get agents => const [];

  @override
  Future<ConfigChangeResult> setMode(ModeId mode) => _gate.future;

  @override
  Future<TurnResult> prompt(
    List<ContentBlock> content, {
    CancelToken? cancel,
  }) async {
    if (commandTurn) {
      emit(ModeChanged(id, mode: ModeId.plan, changeId: 1));
      emit(
        MessageDelta(
          id,
          delta: 'Mode: plan.',
          partial: AssistantMessage(
            content: const [],
            model: scriptedModel,
            usage: Usage.zero,
            stopReason: StopReason.stop,
            timestamp: DateTime.utc(2026),
          ),
        ),
      );
      await commandRelease.future;
    }
    emit(TurnEnded(id, reason: TurnEndReason.completed, usage: Usage.zero));
    return const TurnResult(reason: TurnEndReason.completed, usage: Usage.zero);
  }

  @override
  Future<void> cancel() async {}

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnimplementedError(invocation.memberName.toString());
}
