import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:acp_protocol/acp_protocol.dart';
import 'package:freezed_annotation/freezed_annotation.dart';

import 'acp_transport.dart';

part 'stdio_acp_transport.freezed.dart';

@freezed
abstract class StdioAcpTransportConfig with _$StdioAcpTransportConfig {
  const factory StdioAcpTransportConfig({
    required String command,
    @Default([]) List<String> args,
    String? cwd,
    @Default({}) Map<String, String> env,
  }) = _StdioAcpTransportConfig;
}

@freezed
abstract class StdioAcpAgentProfile with _$StdioAcpAgentProfile {
  const StdioAcpAgentProfile._();

  const factory StdioAcpAgentProfile({
    required String name,
    @Default('custom') String type,
    required String command,
    @Default([]) List<String> args,
    String? cwd,
    @Default({}) Map<String, String> env,
  }) = _StdioAcpAgentProfile;

  StdioAcpTransportConfig toTransportConfig() =>
      StdioAcpTransportConfig(command: command, args: args, cwd: cwd, env: env);
}

const codelabAgentStdioProfile = StdioAcpAgentProfile(
  name: 'Codelab Agent',
  command: 'codelab',
  args: ['serve', '--stdio'],
  env: {'CODELAB_LOG_LEVEL': 'DEBUG'},
);

final class StdioAcpTransport implements AcpTransport {
  StdioAcpTransport(this.config);

  final StdioAcpTransportConfig config;

  final _inboundController = StreamController<JsonRpcMessage>.broadcast(
    sync: true,
  );
  final _eventController = StreamController<AcpTransportEvent>.broadcast(
    sync: true,
  );
  final _subscriptions = <StreamSubscription<void>>[];

  Process? _process;
  Future<int>? _exitCode;
  AcpTransportState _state = AcpTransportState.idle;
  var _isClosed = false;

  @override
  Stream<JsonRpcMessage> get inbound => _inboundController.stream;

  @override
  Stream<AcpTransportEvent> get events => _eventController.stream;

  @override
  AcpTransportState get state => _state;

  @override
  Future<void> start() async {
    _ensureNotClosed();

    if (_state == AcpTransportState.connected ||
        _state == AcpTransportState.connecting) {
      return;
    }

    _setState(AcpTransportState.connecting);

    try {
      final process = await Process.start(
        config.command,
        config.args,
        workingDirectory: config.cwd,
        environment: config.env.isEmpty ? null : config.env,
      );
      _process = process;
      _exitCode = process.exitCode;
      _listenToProcess(process);
      _setState(AcpTransportState.connected);
    } on Object catch (error, stackTrace) {
      _fail(
        AcpTransportException(
          code: AcpTransportErrorCode.startFailed,
          message: 'Failed to start stdio ACP agent.',
          cause: error,
          stackTrace: stackTrace,
        ),
      );
      rethrow;
    }
  }

  @override
  Future<void> send(JsonRpcMessage message) async {
    _ensureConnected();

    try {
      _process!.stdin.writeln(encodeJsonRpcMessage(message));
      await _process!.stdin.flush();
    } on Object catch (error, stackTrace) {
      throw AcpTransportException(
        code: AcpTransportErrorCode.sendFailed,
        message: 'Failed to send ACP message over stdio.',
        cause: error,
        stackTrace: stackTrace,
      );
    }
  }

  @override
  Future<void> close({Duration? timeout}) async {
    if (_isClosed) {
      return;
    }

    _setState(AcpTransportState.closing);
    _isClosed = true;

    final process = _process;
    final exitCode = _exitCode;

    try {
      await process?.stdin.close();
    } on Object {
      // The process may already have exited.
    }

    if (process != null && exitCode != null) {
      await _waitForProcessExit(
        process,
        exitCode,
        timeout ?? const Duration(seconds: 5),
      );
    }

    for (final subscription in _subscriptions) {
      await subscription.cancel();
    }
    _subscriptions.clear();

    _process = null;
    _exitCode = null;

    _setState(AcpTransportState.closed);
    await _inboundController.close();
    await _eventController.close();
  }

  void _listenToProcess(Process process) {
    unawaited(
      process.exitCode.then((exitCode) {
        _handleProcessExit(exitCode);
      }),
    );

    _subscriptions
      ..add(
        process.stdout
            .transform(utf8.decoder)
            .transform(const LineSplitter())
            .listen(
              _handleStdoutLine,
              onError: (Object error, StackTrace stackTrace) {
                _fail(
                  AcpTransportException(
                    code: AcpTransportErrorCode.receiveFailed,
                    message: 'Failed to read ACP stdout stream.',
                    cause: error,
                    stackTrace: stackTrace,
                  ),
                );
              },
            ),
      )
      ..add(
        process.stderr
            .transform(utf8.decoder)
            .transform(const LineSplitter())
            .listen(
              _handleStderrLine,
              onError: (Object error, StackTrace stackTrace) {
                _fail(
                  AcpTransportException(
                    code: AcpTransportErrorCode.receiveFailed,
                    message: 'Failed to read ACP stderr stream.',
                    cause: error,
                    stackTrace: stackTrace,
                  ),
                );
              },
            ),
      );
  }

  Future<void> _waitForProcessExit(
    Process process,
    Future<int> exitCode,
    Duration timeout,
  ) async {
    try {
      await exitCode.timeout(timeout);
    } on TimeoutException {
      process.kill();
      await exitCode;
    }
  }

  void _handleProcessExit(int exitCode) {
    if (_isClosed || _state == AcpTransportState.failed) {
      return;
    }

    _fail(
      AcpTransportException(
        code: AcpTransportErrorCode.disconnected,
        message: 'Stdio ACP agent exited unexpectedly with code $exitCode.',
      ),
    );
  }

  void _handleStdoutLine(String line) {
    if (_isClosed || line.isEmpty) {
      return;
    }

    try {
      _inboundController.add(decodeJsonRpcMessage(line));
    } on JsonRpcProtocolException catch (error, stackTrace) {
      _fail(
        AcpTransportException(
          code: AcpTransportErrorCode.protocolViolation,
          message: 'Agent wrote invalid ACP JSON-RPC to stdout.',
          cause: error,
          stackTrace: stackTrace,
        ),
      );
    }
  }

  void _handleStderrLine(String line) {
    if (_isClosed || line.isEmpty) {
      return;
    }

    _eventController.add(
      AcpTransportEvent.diagnostic(
        message: line,
        severity: AcpTransportDiagnosticSeverity.info,
        source: 'stderr',
      ),
    );
  }

  void _ensureConnected() {
    _ensureNotClosed();

    if (_state != AcpTransportState.connected || _process == null) {
      throw AcpTransportException(
        code: AcpTransportErrorCode.sendFailed,
        message: 'Stdio ACP transport is not connected.',
      );
    }
  }

  void _ensureNotClosed() {
    if (_isClosed || _state == AcpTransportState.closed) {
      throw AcpTransportException(
        code: AcpTransportErrorCode.closed,
        message: 'Stdio ACP transport is closed.',
      );
    }
  }

  void _fail(AcpTransportException error) {
    if (_isClosed) {
      return;
    }

    _setState(AcpTransportState.failed);
    _eventController.add(AcpTransportEvent.failure(error));
  }

  void _setState(AcpTransportState state) {
    _state = state;
    _eventController.add(AcpTransportEvent.stateChanged(state));
  }
}
