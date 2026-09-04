import 'package:acp_protocol/acp_protocol.dart';
import 'package:test/test.dart';

void main() {
  group('terminal DTOs', () {
    test('round-trips create terminal request with all fields', () {
      const request = CreateTerminalRequest(
        sessionId: SessionId('session-1'),
        command: 'npm',
        args: ['test', '--coverage'],
        env: [EnvVariable(name: 'NODE_ENV', value: 'test')],
        cwd: '/home/user/project',
        outputByteLimit: 1048576,
        meta: {'trace': 'terminal'},
      );

      expect(CreateTerminalRequest.fromJson(request.toJson()), request);
      expect(request.toJson(), {
        'sessionId': 'session-1',
        'command': 'npm',
        'args': ['test', '--coverage'],
        'env': [
          {'name': 'NODE_ENV', 'value': 'test'},
        ],
        'cwd': '/home/user/project',
        'outputByteLimit': 1048576,
        '_meta': {'trace': 'terminal'},
      });
    });

    test('round-trips create terminal request with only required fields', () {
      const request = CreateTerminalRequest(
        sessionId: SessionId('session-1'),
        command: 'echo',
      );

      expect(CreateTerminalRequest.fromJson(request.toJson()), request);
      expect(request.toJson(), {
        'sessionId': 'session-1',
        'command': 'echo',
        'args': <String>[],
        'env': <Object?>[],
      });
    });

    test('round-trips create terminal response', () {
      const response = CreateTerminalResponse(
        terminalId: TerminalId('term_xyz789'),
      );

      expect(CreateTerminalResponse.fromJson(response.toJson()), response);
      expect(response.toJson(), {'terminalId': 'term_xyz789'});
    });

    test('round-trips terminal output request', () {
      const request = TerminalOutputRequest(
        sessionId: SessionId('session-1'),
        terminalId: TerminalId('term_xyz789'),
      );

      expect(TerminalOutputRequest.fromJson(request.toJson()), request);
      expect(request.toJson(), {
        'sessionId': 'session-1',
        'terminalId': 'term_xyz789',
      });
    });

    test('round-trips terminal output response for a running process', () {
      const response = TerminalOutputResponse(
        output: 'Running tests...\n',
        truncated: false,
      );

      expect(TerminalOutputResponse.fromJson(response.toJson()), response);
      expect(response.toJson(), {
        'output': 'Running tests...\n',
        'truncated': false,
      });
    });

    test('round-trips terminal output response for an exited process', () {
      const response = TerminalOutputResponse(
        output: 'done\n',
        truncated: true,
        exitStatus: TerminalExitStatus(exitCode: 0, signal: null),
      );

      expect(TerminalOutputResponse.fromJson(response.toJson()), response);
      expect(response.toJson(), {
        'output': 'done\n',
        'truncated': true,
        'exitStatus': {'exitCode': 0},
      });
    });

    test('round-trips wait for terminal exit request/response', () {
      const request = WaitForTerminalExitRequest(
        sessionId: SessionId('session-1'),
        terminalId: TerminalId('term_xyz789'),
      );
      const response = WaitForTerminalExitResponse(exitCode: 0);
      const signaledResponse = WaitForTerminalExitResponse(signal: 'SIGKILL');

      expect(WaitForTerminalExitRequest.fromJson(request.toJson()), request);
      expect(WaitForTerminalExitResponse.fromJson(response.toJson()), response);
      expect(response.toJson(), {'exitCode': 0});
      expect(
        WaitForTerminalExitResponse.fromJson(signaledResponse.toJson()),
        signaledResponse,
      );
      expect(signaledResponse.toJson(), {'signal': 'SIGKILL'});
    });

    test('round-trips kill terminal command request/response', () {
      const request = KillTerminalCommandRequest(
        sessionId: SessionId('session-1'),
        terminalId: TerminalId('term_xyz789'),
      );
      const response = KillTerminalCommandResponse();

      expect(KillTerminalCommandRequest.fromJson(request.toJson()), request);
      expect(response.toJson(), <String, Object?>{});
      expect(KillTerminalCommandResponse.fromJson(null), response);
      expect(
        KillTerminalCommandResponse.fromJson(<String, Object?>{}),
        response,
      );
    });

    test('round-trips release terminal request/response', () {
      const request = ReleaseTerminalRequest(
        sessionId: SessionId('session-1'),
        terminalId: TerminalId('term_xyz789'),
      );
      const response = ReleaseTerminalResponse();

      expect(ReleaseTerminalRequest.fromJson(request.toJson()), request);
      expect(response.toJson(), <String, Object?>{});
      expect(ReleaseTerminalResponse.fromJson(null), response);
      expect(ReleaseTerminalResponse.fromJson(<String, Object?>{}), response);
    });

    test('rejects invalid terminal request shapes', () {
      expect(
        () => CreateTerminalRequest.fromJson({
          'sessionId': 'session-1',
          'command': 'npm',
          'cwd': 'relative/path',
        }),
        throwsA(isA<JsonRpcProtocolException>()),
      );
      expect(
        () => CreateTerminalRequest.fromJson({'sessionId': 'session-1'}),
        throwsA(isA<JsonRpcProtocolException>()),
      );
      expect(
        () => CreateTerminalRequest.fromJson({
          'sessionId': 'session-1',
          'command': 'npm',
          'outputByteLimit': 'huge',
        }),
        throwsA(isA<JsonRpcProtocolException>()),
      );
      expect(
        () => CreateTerminalResponse.fromJson({'terminalId': ''}),
        throwsA(isA<JsonRpcProtocolException>()),
      );
      expect(
        () => TerminalOutputResponse.fromJson({'output': 'x'}),
        throwsA(isA<JsonRpcProtocolException>()),
      );
      expect(
        () => TerminalOutputRequest.fromJson({'sessionId': 'session-1'}),
        throwsA(isA<JsonRpcProtocolException>()),
      );
      expect(
        () => KillTerminalCommandResponse.fromJson({'unexpected': true}),
        throwsA(isA<JsonRpcProtocolException>()),
      );
      expect(
        () => ReleaseTerminalResponse.fromJson({'unexpected': true}),
        throwsA(isA<JsonRpcProtocolException>()),
      );
    });

    test('accepts Windows drive and UNC absolute paths for cwd', () {
      expect(
        CreateTerminalRequest.fromJson({
          'sessionId': 'session-1',
          'command': 'npm',
          'cwd': r'C:\Users\dev\project',
        }).cwd,
        r'C:\Users\dev\project',
      );
      expect(
        CreateTerminalRequest.fromJson({
          'sessionId': 'session-1',
          'command': 'npm',
          'cwd': r'\\server\share\project',
        }).cwd,
        r'\\server\share\project',
      );
    });
  });
}
