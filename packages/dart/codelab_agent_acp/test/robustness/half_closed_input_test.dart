import 'dart:async';

import 'package:acp_protocol/acp_protocol.dart';
import 'package:acp_transports/acp_transports.dart';
import 'package:codelab_agent_acp/codelab_agent_acp.dart';
import 'package:codelab_agent_core/codelab_agent_core.dart';
import 'package:codelab_agent_core/testing.dart';
import 'package:test/test.dart';

import '../support/server_harness.dart'
    show HostEnv, JournalStore, UnusedGate, scriptedModel, testAgentInfo;

/// Вход соединения закрыт, а выход ещё работает — так ведёт себя stdio:
/// `echo '{…initialize…}' | codelab-agent serve --stdio` закрывает stdin
/// сразу (§13.10, «Безопасное завершение»: соединение отвечает на начатые
/// запросы до закрытия транспорта; design.md change
/// `add-codelab-agent-binary`, D7).
void main() {
  test(
    'requests read before EOF are answered, then the transport closes',
    () async {
      final clock = FakeClock();
      final core = buildAgentCore(
        profile: HostProfile.of(
          'agent-serve',
        ).narrowed({HostCapability.fileListing: const CapabilityOff('test')}),
        services: AgentCoreServices(
          baseEnv: HostEnv(MemoryExecutionEnv(cwd: '/', clock: clock)),
          gate: const UnusedGate(),
          logger: RecordingLogger(),
          clock: clock,
          ids: SequentialIdGenerator(),
          sessions: JournalStore(),
        ),
        config: CoreConfig(defaultModel: scriptedModel),
        streamFunction: ScriptedStreamFunction.fromJson({
          'steps': <Object?>[],
        }, clock: clock).call,
      );
      final server = AcpAgentServer(
        core: core,
        config: const AcpServerConfig(
          agentInfo: testAgentInfo,
          detachGrace: Duration.zero,
        ),
        logger: RecordingLogger(),
        clock: clock,
      );
      final transport = _HalfClosedTransport();

      final served = server.serve(transport);
      transport.receive(
        const JsonRpcMessage.request(
          id: JsonRpcId.integer(0),
          method: 'initialize',
          params: {'protocolVersion': 1},
        ),
      );
      transport.endInput();
      await served.timeout(const Duration(seconds: 5));

      final answer = transport.sent.single as JsonRpcResponse;
      expect(answer.id, const JsonRpcId.integer(0));
      expect(answer.error, isNull);
      expect(transport.closed, isTrue);
    },
  );
}

/// Транспорт с отдельно закрываемым входом: отправка работает до [close].
final class _HalfClosedTransport implements AcpTransport {
  final _input = StreamController<JsonRpcMessage>();
  final sent = <JsonRpcMessage>[];
  var closed = false;
  AcpTransportState _state = AcpTransportState.idle;

  void receive(JsonRpcMessage message) => _input.add(message);

  void endInput() => unawaited(_input.close());

  @override
  Stream<JsonRpcMessage> get inbound => _input.stream;

  @override
  Stream<AcpTransportEvent> get events => const Stream.empty();

  @override
  AcpTransportState get state => _state;

  @override
  Future<void> start() async => _state = AcpTransportState.connected;

  @override
  Future<void> send(JsonRpcMessage message) async {
    if (closed) {
      throw const AcpTransportException(
        code: AcpTransportErrorCode.closed,
        message: 'closed',
      );
    }
    // Ответ уходит с задержкой, как запись в pipe.
    await Future<void>.delayed(const Duration(milliseconds: 10));
    sent.add(message);
  }

  @override
  Future<void> close({Duration? timeout}) async {
    closed = true;
    _state = AcpTransportState.closed;
  }
}
