// Обновления сессии, пришедшие сразу за ответом на `session/new` (design D7
// change `add-command-palette-agent-commands`; spec acp-protocol-client
// «Обновления сразу после session/new»).
//
// Агент вправе прислать `available_commands_update` сразу после создания
// сессии (`docs/acp/protocol/14-Slash Commands.md`), и Dart-агент так и
// делает. Транспорт доставляет ответ и уведомление подряд, до того как
// `createSession` вернёт управление после `await`; найдено e2e R-20.

import 'package:codelab_acp_protocol/codelab_acp_protocol.dart';
import 'package:codelab_acp_testing/codelab_acp_testing.dart';
import 'package:codelab_client_acp/codelab_client_acp.dart';
import 'package:test/test.dart';

const _session = SessionId('session-1');

JsonRpcNotification _update(SessionId sessionId, SessionUpdate update) =>
    JsonRpcMessage.notification(
          method: sessionUpdateMethod,
          params: SessionNotification(
            sessionId: sessionId,
            update: update,
          ).toJson(),
        )
        as JsonRpcNotification;

const _commands = SessionUpdate.availableCommandsUpdate(
  availableCommands: [
    AvailableCommand(name: 'compact', description: 'Compact the conversation'),
  ],
);

void main() {
  late FakeAcpTransport transport;
  late AcpClientApplication client;

  setUp(() async {
    transport = FakeAcpTransport();
    await transport.start();
    client = AcpClientApplication(transport: transport);
  });
  tearDown(() => client.dispose());

  /// Отвечает на `session/new` и тем же синхронным шагом присылает [after].
  void answerNewSession(List<JsonRpcNotification> after) {
    final answering = transport.sent.listen((message) {
      if (message is JsonRpcRequest && message.method == sessionNewMethod) {
        transport.emitInbound(
          JsonRpcMessage.response(
            id: message.id,
            result: const NewSessionResponse(sessionId: _session).toJson(),
          ),
        );
        after.forEach(transport.emitInbound);
      }
    });
    addTearDown(answering.cancel);
  }

  test('an update right after the session/new answer applies to the new '
      'session', () async {
    answerNewSession([_update(_session, _commands)]);

    final session = await client.createSession(
      const CreateSessionCommand(cwd: '/workspace'),
    );

    expect(
      [for (final command in session.availableCommands) command.name],
      ['compact'],
    );
    expect(client.sessionById(_session)?.availableCommands, hasLength(1));
  });

  test('updates of another unknown session are still dropped', () async {
    answerNewSession([_update(const SessionId('other'), _commands)]);

    await client.createSession(const CreateSessionCommand(cwd: '/workspace'));
    await Future<void>.delayed(Duration.zero);

    expect(client.sessionById(const SessionId('other')), isNull);
    expect(client.sessionById(_session)?.availableCommands, isEmpty);
  });
}
