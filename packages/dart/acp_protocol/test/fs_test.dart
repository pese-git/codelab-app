import 'package:acp_protocol/acp_protocol.dart';
import 'package:test/test.dart';

void main() {
  group('fs DTOs', () {
    test('round-trips read text file request with line/limit', () {
      const request = ReadTextFileRequest(
        sessionId: SessionId('session-1'),
        path: '/home/user/project/src/main.py',
        line: 10,
        limit: 50,
        meta: {'trace': 'fs'},
      );

      expect(ReadTextFileRequest.fromJson(request.toJson()), request);
      expect(request.toJson(), {
        'sessionId': 'session-1',
        'path': '/home/user/project/src/main.py',
        'line': 10,
        'limit': 50,
        '_meta': {'trace': 'fs'},
      });
    });

    test('round-trips read text file request without line/limit', () {
      const request = ReadTextFileRequest(
        sessionId: SessionId('session-1'),
        path: '/home/user/project/src/main.py',
      );

      expect(ReadTextFileRequest.fromJson(request.toJson()), request);
      expect(request.toJson(), {
        'sessionId': 'session-1',
        'path': '/home/user/project/src/main.py',
      });
    });

    test('round-trips read text file response', () {
      const response = ReadTextFileResponse(content: 'hello\n');

      expect(ReadTextFileResponse.fromJson(response.toJson()), response);
      expect(response.toJson(), {'content': 'hello\n'});
    });

    test('round-trips write text file request', () {
      const request = WriteTextFileRequest(
        sessionId: SessionId('session-1'),
        path: '/home/user/project/config.json',
        content: '{"debug": true}',
      );

      expect(WriteTextFileRequest.fromJson(request.toJson()), request);
      expect(request.toJson(), {
        'sessionId': 'session-1',
        'path': '/home/user/project/config.json',
        'content': '{"debug": true}',
      });
    });

    test('round-trips empty write text file response', () {
      const response = WriteTextFileResponse();

      expect(response.toJson(), <String, Object?>{});
      expect(WriteTextFileResponse.fromJson(null), response);
      expect(WriteTextFileResponse.fromJson(<String, Object?>{}), response);
    });

    test('accepts Windows drive and UNC absolute paths', () {
      expect(
        ReadTextFileRequest.fromJson({
          'sessionId': 'session-1',
          'path': r'C:\Users\dev\project\main.py',
        }).path,
        r'C:\Users\dev\project\main.py',
      );
      expect(
        ReadTextFileRequest.fromJson({
          'sessionId': 'session-1',
          'path': r'\\server\share\file.txt',
        }).path,
        r'\\server\share\file.txt',
      );
    });

    test('rejects invalid fs request shapes', () {
      expect(
        () => ReadTextFileRequest.fromJson({
          'sessionId': 'session-1',
          'path': 'relative/path.py',
        }),
        throwsA(isA<JsonRpcProtocolException>()),
      );
      expect(
        () => ReadTextFileRequest.fromJson({
          'sessionId': 'session-1',
          'path': '',
        }),
        throwsA(isA<JsonRpcProtocolException>()),
      );
      expect(
        () => ReadTextFileRequest.fromJson({'path': '/abs/path.py'}),
        throwsA(isA<JsonRpcProtocolException>()),
      );
      expect(
        () => ReadTextFileRequest.fromJson({
          'sessionId': 'session-1',
          'path': '/abs/path.py',
          'line': 'ten',
        }),
        throwsA(isA<JsonRpcProtocolException>()),
      );
      expect(
        () => ReadTextFileResponse.fromJson({}),
        throwsA(isA<JsonRpcProtocolException>()),
      );
      expect(
        () => WriteTextFileRequest.fromJson({
          'sessionId': 'session-1',
          'path': 'relative/config.json',
          'content': '{}',
        }),
        throwsA(isA<JsonRpcProtocolException>()),
      );
      expect(
        () => WriteTextFileRequest.fromJson({
          'sessionId': 'session-1',
          'path': '/abs/config.json',
        }),
        throwsA(isA<JsonRpcProtocolException>()),
      );
      expect(
        () => WriteTextFileResponse.fromJson({'unexpected': true}),
        throwsA(isA<JsonRpcProtocolException>()),
      );
    });
  });
}
