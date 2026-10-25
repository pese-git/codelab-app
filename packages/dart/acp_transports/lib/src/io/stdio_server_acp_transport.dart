import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:acp_protocol/acp_protocol.dart';

import '../acp_transport.dart';
import 'server_frames.dart';

/// Серверный stdio-транспорт агента: ACP по stdin/stdout своего процесса.
///
/// Почему: клиент (codelab-app, Zed) запускает агента дочерним процессом и
/// говорит с ним построчным JSON (R-13); клиентский `StdioAcpTransport`
/// делает обратное — запускает процесс сам. Транспорт сам отвечает на сырые
/// плохие кадры (`-32700`, `-32600`) и не рвёт соединение (ACP-4; design.md
/// change `add-codelab-agent-binary`, D2).
///
/// Для чего: порт `AcpTransport` для `AcpAgentServer.serve` в бинаре
/// `codelab-agent serve --stdio`. Одна строка UTF-8 — одно сообщение, длина
/// строки не ограничена; записи не перемешиваются; пустые строки
/// пропускаются; EOF входа закрывает [inbound], а отправка работает до
/// [close] — ответы на прочитанные запросы ещё уходят.
///
/// Как использовать: `StdioServerAcpTransport()` — stdin и stdout процесса;
/// тесты передают [input] и [output] в памяти. [inbound] — поток с одной
/// подпиской: сообщения до подписки не теряются. stdout транспорт не
/// закрывает — он принадлежит процессу.
final class StdioServerAcpTransport implements AcpTransport {
  StdioServerAcpTransport({Stream<List<int>>? input, IOSink? output})
    : _input = input ?? stdin,
      _output = output ?? stdout;

  final Stream<List<int>> _input;
  final IOSink _output;

  final _inbound = StreamController<JsonRpcMessage>();
  final _events = StreamController<AcpTransportEvent>.broadcast(sync: true);
  StreamSubscription<String>? _subscription;
  AcpTransportState _state = AcpTransportState.idle;

  /// Цепочка записей: каждая строка уходит целиком и по порядку.
  Future<void> _writes = Future.value();

  @override
  Stream<JsonRpcMessage> get inbound => _inbound.stream;

  @override
  Stream<AcpTransportEvent> get events => _events.stream;

  @override
  AcpTransportState get state => _state;

  @override
  Future<void> start() async {
    if (_state != AcpTransportState.idle) {
      return;
    }
    _setState(AcpTransportState.connected);
    _subscription = _input
        .transform(utf8.decoder)
        .transform(const LineSplitter())
        .listen(
          _onLine,
          onError: (Object error, StackTrace stack) => _fail(
            AcpTransportException(
              code: AcpTransportErrorCode.receiveFailed,
              message: 'Failed to read ACP stdin stream.',
              cause: error,
              stackTrace: stack,
            ),
          ),
          onDone: _onEof,
        );
  }

  @override
  Future<void> send(JsonRpcMessage message) {
    if (_state != AcpTransportState.connected) {
      return Future.error(
        const AcpTransportException(
          code: AcpTransportErrorCode.sendFailed,
          message: 'Stdio ACP server transport is not connected.',
        ),
      );
    }
    final line = encodeJsonRpcMessage(message);
    final written = _writes.then((_) async {
      _output.writeln(line);
      await _output.flush();
    });
    _writes = written.catchError((_) {});
    return written.catchError((Object error, StackTrace stack) {
      final failure = AcpTransportException(
        code: AcpTransportErrorCode.sendFailed,
        message: 'Failed to write an ACP message to stdout.',
        cause: error,
        stackTrace: stack,
      );
      _fail(failure);
      throw failure;
    });
  }

  @override
  Future<void> close({Duration? timeout}) async {
    if (_state == AcpTransportState.closed) {
      return;
    }
    _setState(AcpTransportState.closing);
    await _subscription?.cancel();
    _subscription = null;
    await _writes.timeout(
      timeout ?? const Duration(seconds: 5),
      onTimeout: () {},
    );
    await _finish();
  }

  void _onLine(String line) {
    if (line.trim().isEmpty) {
      return;
    }
    switch (decodeServerFrame(line)) {
      case ServerFrameMessage(:final message):
        _inbound.add(message);
      case ServerFrameRejected(:final answer, :final reason):
        _events.add(
          AcpTransportEvent.diagnostic(
            message: 'Rejected an ACP frame: $reason',
            severity: AcpTransportDiagnosticSeverity.warning,
            source: 'stdin',
          ),
        );
        unawaited(send(answer).catchError((_) {}));
    }
  }

  /// EOF входа закрывает только [inbound]: отправка живёт до [close].
  /// Клиент вида `echo '{…initialize…}' | codelab-agent serve --stdio` закрывает
  /// stdin сразу, а ответ на уже прочитанный запрос должен уйти (DoD этапа 4).
  void _onEof() {
    _subscription = null;
    unawaited(_inbound.close());
  }

  Future<void> _finish() async {
    if (_state == AcpTransportState.closed) {
      return;
    }
    _setState(AcpTransportState.closed);
    if (!_inbound.isClosed) {
      await _inbound.close();
    }
    await _events.close();
  }

  void _fail(AcpTransportException error) {
    if (_state == AcpTransportState.closed ||
        _state == AcpTransportState.failed) {
      return;
    }
    _setState(AcpTransportState.failed);
    _events.add(AcpTransportEvent.failure(error));
  }

  void _setState(AcpTransportState state) {
    _state = state;
    if (!_events.isClosed) {
      _events.add(AcpTransportEvent.stateChanged(state));
    }
  }
}
