import 'dart:async';

import 'package:codelab_acp_protocol/codelab_acp_protocol.dart' show SessionId;
import 'package:codelab_client_acp/codelab_client_acp.dart'
    show ProtocolFrame, ProtocolPayloadPolicy;
import 'package:codelab_client_core/codelab_client_core.dart';
import 'package:flutter_test/flutter_test.dart';

import 'fake_client_workspace.dart';

/// Двойник [AgentBackend] только с потоком кадров и Trace (design.md change
/// `redesign-protocol-pane`, D5, D17).
///
/// Почему: настоящий `ProtocolFrameLog` подписывается на `protocolFrames`
/// бэкенда, а Cubit панели читает буфер, а не ядро. Для чего: тест подаёт
/// кадры в [frames] и видит вызовы `setFrameTrace` в [traceCalls]. Поток
/// синхронный: тест не ждёт очередь событий.
final class FakeFrameBackend extends Fake implements AgentBackend {
  FakeFrameBackend({this.traceAvailable = true});

  final StreamController<ProtocolFrame> frames =
      StreamController<ProtocolFrame>.broadcast(sync: true);

  @override
  final bool traceAvailable;

  /// Согласована с [traceAvailable]: Trace возможен только при `metadataOnly`
  /// (D3, D17 change `redesign-protocol-pane`).
  @override
  ProtocolPayloadPolicy get protocolPayloads => traceAvailable
      ? ProtocolPayloadPolicy.metadataOnly
      : ProtocolPayloadPolicy.full;

  final List<bool> traceCalls = [];

  @override
  Stream<ProtocolFrame> get protocolFrames => frames.stream;

  @override
  void setFrameTrace(bool enabled) => traceCalls.add(enabled);
}

/// [FakeClientWorkspace] с настоящим буфером кадров над [FakeFrameBackend].
///
/// Как использовать: `push(frame)` кладёт кадр в буфер; `focus(id)` меняет
/// сессию в фокусе (`WorkspaceState.activeSessionId`, D6); `dispose` закрывает
/// буфер и поток состояния.
final class FakeProtocolWorkspace extends FakeClientWorkspace {
  FakeProtocolWorkspace({bool traceAvailable = true})
    : backend = FakeFrameBackend(traceAvailable: traceAvailable) {
    protocolFrames = ProtocolFrameLog(backend: backend);
  }

  final FakeFrameBackend backend;

  @override
  late final ProtocolFrameLog protocolFrames;

  void push(ProtocolFrame frame) => backend.frames.add(frame);

  void pushAll(Iterable<ProtocolFrame> frames) => frames.forEach(push);

  /// Переводит фокус на [id]; `null` — фокуса нет.
  void focus(String? id) => emit(
    current.copyWith(activeSessionId: id == null ? null : SessionId(id)),
  );

  @override
  Future<void> dispose() async {
    await protocolFrames.dispose();
    await backend.frames.close();
    await close();
  }
}
