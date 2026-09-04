import 'package:acp_client_core/acp_client_core.dart';
import 'package:acp_protocol/acp_protocol.dart';
import 'package:acp_testing/acp_testing.dart';
import 'package:test/test.dart';

void main() {
  late FakeAcpTransport transport;
  late _RecordingTextFileIo fileIo;
  late AcpClientApplication client;

  setUp(() async {
    transport = FakeAcpTransport();
    await transport.start();
    fileIo = _RecordingTextFileIo();
    client = AcpClientApplication(
      transport: transport,
      textFileReader: fileIo,
      textFileWriter: fileIo,
    );
    await _createSession(client, transport);
    transport.drainSentMessages();
  });

  tearDown(() async {
    await client.dispose();
    await transport.close();
  });

  test('reads a file within the session working directory', () async {
    fileIo.contentToReturn = 'print("hi")\n';

    transport.emitInbound(
      _readRequest(id: 1, path: '/workspace/src/main.py', line: 2, limit: 10),
    );
    await _pump();

    expect(fileIo.readCalls, [
      const (path: '/workspace/src/main.py', line: 2, limit: 10),
    ]);
    final response = transport.sentMessages.single as JsonRpcResponse;
    expect(response.id, const JsonRpcId.integer(1));
    expect(
      ReadTextFileResponse.fromJson(response.result),
      const ReadTextFileResponse(content: 'print("hi")\n'),
    );
  });

  test('rejects a read whose path escapes the working directory without '
      'touching the filesystem adapter', () async {
    transport.emitInbound(
      _readRequest(id: 2, path: '/workspace/../etc/passwd'),
    );
    await _pump();

    expect(fileIo.readCalls, isEmpty);
    final response = transport.sentMessages.single as JsonRpcResponse;
    expect(response.id, const JsonRpcId.integer(2));
    expect(response.error, isNotNull);
    expect(response.error!.code, jsonRpcInvalidParamsCode);
  });

  test('writes a file within the session working directory immediately, with '
      'no approval request and no pending state', () async {
    transport.emitInbound(
      _writeRequest(
        id: 3,
        path: '/workspace/config.json',
        content: '{"debug":true}',
      ),
    );
    await _pump();

    expect(fileIo.writeCalls, [
      const (path: '/workspace/config.json', content: '{"debug":true}'),
    ]);
    final response = transport.sentMessages.single as JsonRpcResponse;
    expect(response.id, const JsonRpcId.integer(3));
    expect(response.error, isNull);
    expect(
      WriteTextFileResponse.fromJson(response.result),
      const WriteTextFileResponse(),
    );
    expect(
      client.sessionById(const SessionId('session-1'))?.status,
      SessionLifecycleStatus.active,
    );
  });

  test('rejects a write whose path escapes the working directory without '
      'touching the filesystem adapter', () async {
    transport.emitInbound(
      _writeRequest(id: 4, path: '/etc/passwd', content: 'evil'),
    );
    await _pump();

    expect(fileIo.writeCalls, isEmpty);
    final response = transport.sentMessages.single as JsonRpcResponse;
    expect(response.id, const JsonRpcId.integer(4));
    expect(response.error, isNotNull);
    expect(response.error!.code, jsonRpcInvalidParamsCode);
  });

  test('maps an IO failure from the write adapter to a typed error response '
      'without crashing the application', () async {
    fileIo.writeFailure = const FsIoFailure('disk is full');

    transport.emitInbound(
      _writeRequest(id: 5, path: '/workspace/big.bin', content: 'data'),
    );
    await _pump();

    final response = transport.sentMessages.single as JsonRpcResponse;
    expect(response.id, const JsonRpcId.integer(5));
    expect(response.error, isNotNull);
    expect(response.error!.code, jsonRpcInternalErrorCode);
    expect(response.error!.message, isNotEmpty);

    // The application is still usable after the failure.
    expect(
      client.sessionById(const SessionId('session-1'))?.status,
      SessionLifecycleStatus.active,
    );
  });
}

final class _RecordingTextFileIo implements TextFileReader, TextFileWriter {
  final readCalls = <({String path, int? line, int? limit})>[];
  final writeCalls = <({String path, String content})>[];
  String contentToReturn = '';
  FsIoFailure? writeFailure;

  @override
  Future<String> readText({required String path, int? line, int? limit}) {
    readCalls.add((path: path, line: line, limit: limit));
    return Future.value(contentToReturn);
  }

  @override
  Future<void> writeText({required String path, required String content}) {
    writeCalls.add((path: path, content: content));
    final failure = writeFailure;
    if (failure != null) {
      return Future.error(failure);
    }
    return Future.value();
  }
}

JsonRpcRequest _readRequest({
  required int id,
  required String path,
  int? line,
  int? limit,
}) {
  return JsonRpcMessage.request(
        id: JsonRpcId.integer(id),
        method: fsReadTextFileMethod,
        params: ReadTextFileRequest(
          sessionId: const SessionId('session-1'),
          path: path,
          line: line,
          limit: limit,
        ).toJson(),
      )
      as JsonRpcRequest;
}

JsonRpcRequest _writeRequest({
  required int id,
  required String path,
  required String content,
}) {
  return JsonRpcMessage.request(
        id: JsonRpcId.integer(id),
        method: fsWriteTextFileMethod,
        params: WriteTextFileRequest(
          sessionId: const SessionId('session-1'),
          path: path,
          content: content,
        ).toJson(),
      )
      as JsonRpcRequest;
}

Future<void> _createSession(
  AcpClientApplication client,
  FakeAcpTransport transport,
) async {
  final future = CreateSession(client)(
    const CreateSessionCommand(cwd: '/workspace'),
  ).run();
  await _pump();
  final request = transport.sentMessages.single as JsonRpcRequest;
  transport.emitInbound(
    JsonRpcMessage.response(
      id: request.id,
      result: const NewSessionResponse(
        sessionId: SessionId('session-1'),
      ).toJson(),
    ),
  );
  await future;
}

Future<void> _pump() => Future<void>.delayed(Duration.zero);
