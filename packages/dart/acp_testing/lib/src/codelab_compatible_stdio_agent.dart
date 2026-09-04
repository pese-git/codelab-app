import 'dart:io';

enum CodelabCompatibleStdioAgentMode {
  normal('normal'),
  exitOnStart('exit_on_start'),
  invalidStdout('invalid_stdout'),
  withConfigOptions('with_config_options'),
  crashMidPrompt('crash_mid_prompt'),
  withPermissionRequest('with_permission_request'),
  withFsAccess('with_fs_access'),
  withFsPathEscape('with_fs_path_escape'),
  echoesCwd('echoes_cwd'),
  withTerminalExecution('with_terminal_execution'),
  withTerminalPathEscape('with_terminal_path_escape'),
  withTerminalKill('with_terminal_kill');

  const CodelabCompatibleStdioAgentMode(this.wireName);

  final String wireName;
}

Future<File> writeCodelabCompatibleStdioAgent(
  Directory directory, {
  CodelabCompatibleStdioAgentMode mode = CodelabCompatibleStdioAgentMode.normal,
  String fileName = 'codelab_compatible_stdio_agent.dart',
}) async {
  final file = File('${directory.path}/$fileName');
  await file.writeAsString(codelabCompatibleStdioAgentSource(mode: mode));
  return file;
}

String codelabCompatibleStdioAgentSource({
  CodelabCompatibleStdioAgentMode mode = CodelabCompatibleStdioAgentMode.normal,
}) {
  return _codelabCompatibleStdioAgentSource.replaceAll(
    '__CODELAB_TEST_AGENT_MODE__',
    mode.wireName,
  );
}

const _codelabCompatibleStdioAgentSource = r'''
import 'dart:convert';
import 'dart:io';

const _mode = '__CODELAB_TEST_AGENT_MODE__';
const _sessionId = 'codelab-test-session';
const _permissionRequestId = 'perm-1';
const _fsReadRequestId = 'fs-read-1';
const _fsWriteRequestId = 'fs-write-1';
const _terminalCreateRequestId = 'terminal-create-1';
const _terminalWaitRequestId = 'terminal-wait-1';
const _terminalOutputRequestId = 'terminal-output-1';
const _terminalKillRequestId = 'terminal-kill-1';
var _currentModel = 'gpt-5';
Object? _pendingPromptId;
String? _sessionCwd;
String? _fsReadContent;
String? _terminalId;

Future<void> main(List<String> args) async {
  if (args.length != 2 || args[0] != 'serve' || args[1] != '--stdio') {
    stderr.writeln('usage: codelab serve --stdio');
    exitCode = 64;
    return;
  }

  stderr.writeln('codelab-compatible test agent ready');

  if (_mode == 'exit_on_start') {
    exitCode = 42;
    return;
  }

  if (_mode == 'invalid_stdout') {
    stdout.writeln('{not json');
    await stdout.flush();
    return;
  }

  await for (final line
      in stdin.transform(utf8.decoder).transform(const LineSplitter())) {
    if (line.isEmpty) {
      continue;
    }

    final message = jsonDecode(line) as Map<String, Object?>;
    final id = message['id'];
    final method = message['method'];

    if (method == null && id == _permissionRequestId) {
      // Not an incoming request/notification — this is the client's reply
      // to the `session/request_permission` request we sent below, matched
      // by id rather than dispatched through the method switch.
      _handlePermissionResponse(message);
      continue;
    }
    if (method == null && id == _fsReadRequestId) {
      _handleFsReadResponse(message);
      continue;
    }
    if (method == null && id == _fsWriteRequestId) {
      _handleFsWriteResponse(message);
      continue;
    }
    if (method == null && id == _terminalCreateRequestId) {
      _handleTerminalCreateResponse(message);
      continue;
    }
    if (method == null && id == _terminalWaitRequestId) {
      _handleTerminalWaitResponse(message);
      continue;
    }
    if (method == null && id == _terminalKillRequestId) {
      _handleTerminalKillResponse(message);
      continue;
    }
    if (method == null && id == _terminalOutputRequestId) {
      _handleTerminalOutputResponse(message);
      continue;
    }

    switch (method) {
      case 'initialize':
        _writeResponse(id, {
          'protocolVersion': 1,
          'agentCapabilities': {
            'loadSession': false,
            'mcpCapabilities': {'http': false, 'sse': false},
            'promptCapabilities': {
              'audio': false,
              'embeddedContext': false,
              'image': false,
            },
            'sessionCapabilities': {},
          },
          'agentInfo': {
            'name': 'codelab-compatible-test-agent',
            'version': '0.1.0',
          },
          'authMethods': <Object?>[],
        });
      case 'session/new':
        final params = message['params'] as Map<String, Object?>;
        _sessionCwd = params['cwd'] as String?;
        _writeResponse(id, {
          'sessionId': _sessionId,
          if (_mode == 'with_config_options')
            'configOptions': [_modelConfigOption()],
        });
      case 'session/prompt':
        if (_mode == 'crash_mid_prompt') {
          // Simulate the agent process dying unexpectedly while a turn is
          // running — no response, no notification, just gone. `exit()`
          // terminates the process immediately without flushing further
          // output, matching a real crash/kill more closely than closing
          // stdout gracefully would.
          exit(1);
        }
        if (_mode == 'with_fs_access') {
          // Read a file the test placed in the session's working directory,
          // then write a derived file back — a real fs/* round trip, no
          // approval step (see add-acp-fs-client-support/design.md).
          _pendingPromptId = id;
          _writeRequest(_fsReadRequestId, 'fs/read_text_file', {
            'sessionId': _sessionId,
            'path': '$_sessionCwd/input.txt',
          });
          break;
        }
        if (_mode == 'echoes_cwd') {
          // Reports the `cwd` this agent process actually received in
          // `session/new` back to the client, in-band — the only way an e2e
          // test can confirm a real wire round trip carried the selected
          // project's path, since `session.cwd` in the client's own domain
          // model just echoes what it sent, not what the agent received.
          _writeNotification('session/update', {
            'sessionId': _sessionId,
            'update': {
              'sessionUpdate': 'agent_message_chunk',
              'content': {'type': 'text', 'text': 'cwd was: $_sessionCwd'},
            },
          });
          _writeResponse(id, {'stopReason': 'end_turn'});
          break;
        }
        if (_mode == 'with_fs_path_escape') {
          // Attempt to read outside the working directory — the client
          // MUST reject this before touching the filesystem.
          _pendingPromptId = id;
          _writeRequest(_fsReadRequestId, 'fs/read_text_file', {
            'sessionId': _sessionId,
            'path': '$_sessionCwd/../escape.txt',
          });
          break;
        }
        if (_mode == 'with_terminal_execution') {
          // Runs a real command via terminal/create, waits for it to exit,
          // then fetches its output — the real terminal/* round trip, no
          // approval step (see add-acp-terminal-client-support/design.md).
          _pendingPromptId = id;
          _writeRequest(_terminalCreateRequestId, 'terminal/create', {
            'sessionId': _sessionId,
            'command': 'sh',
            'args': ['-c', 'echo hello-from-terminal; exit 3'],
          });
          break;
        }
        if (_mode == 'with_terminal_path_escape') {
          // Attempt to run a command outside the working directory — the
          // client MUST reject this before starting any process.
          _pendingPromptId = id;
          _writeRequest(_terminalCreateRequestId, 'terminal/create', {
            'sessionId': _sessionId,
            'command': 'echo',
            'args': ['should not run'],
            'cwd': '$_sessionCwd/../escape',
          });
          break;
        }
        if (_mode == 'with_terminal_kill') {
          // Starts a long-running process, then kills it immediately —
          // terminalId must stay valid afterwards for terminal/output.
          _pendingPromptId = id;
          _writeRequest(_terminalCreateRequestId, 'terminal/create', {
            'sessionId': _sessionId,
            'command': 'sleep',
            'args': ['30'],
          });
          break;
        }
        if (_mode == 'with_permission_request') {
          // Defer the `session/prompt` response until the client answers
          // our `session/request_permission` — a real agent waits for the
          // permission outcome before deciding how the turn ends.
          _pendingPromptId = id;
          _writeRequest(_permissionRequestId, 'session/request_permission', {
            'sessionId': _sessionId,
            'toolCall': {
              'toolCallId': 'test-tool-call-1',
              'title': 'Run test command',
              'kind': 'execute',
              'status': 'pending',
              'rawInput': {'command': 'echo hello', 'shell': '/bin/bash'},
            },
            'options': [
              {'optionId': 'allow_once', 'name': 'Allow once', 'kind': 'allow_once'},
              {'optionId': 'allow_always', 'name': 'Allow always', 'kind': 'allow_always'},
              {'optionId': 'reject_once', 'name': 'Reject once', 'kind': 'reject_once'},
              {'optionId': 'reject_always', 'name': 'Reject always', 'kind': 'reject_always'},
            ],
          });
          break;
        }
        _writeNotification('session/update', {
          'sessionId': _sessionId,
          'update': {
            'sessionUpdate': 'agent_message_chunk',
            'content': {
              'type': 'text',
              'text': 'hello from compatible stdio agent',
            },
          },
        });
        _writeResponse(id, {'stopReason': 'end_turn'});
      case 'session/set_config_option':
        final params = message['params'] as Map<String, Object?>;
        final configId = params['configId'];
        final value = params['value'];
        if (configId == 'model' && (value == 'gpt-5' || value == 'gpt-4')) {
          _currentModel = value! as String;
          _writeResponse(id, {
            'configOptions': [_modelConfigOption()],
          });
        } else {
          _writeError(id, -32602, 'Unknown config option or value');
        }
      default:
        _writeError(id, -32601, 'Method not found');
    }
  }
}

Map<String, Object?> _modelConfigOption() {
  return {
    'type': 'select',
    'id': 'model',
    'name': 'Model',
    'category': 'model',
    'currentValue': _currentModel,
    'options': [
      {'value': 'gpt-5', 'name': 'GPT-5'},
      {'value': 'gpt-4', 'name': 'GPT-4'},
    ],
  };
}

void _handlePermissionResponse(Map<String, Object?> message) {
  final promptId = _pendingPromptId;
  if (promptId == null) {
    return;
  }
  _pendingPromptId = null;

  final result = message['result'] as Map<String, Object?>?;
  final outcome = result?['outcome'] as Map<String, Object?>?;
  final selectedOptionId = outcome?['optionId'] as String?;

  _writeNotification('session/update', {
    'sessionId': _sessionId,
    'update': {
      'sessionUpdate': 'agent_message_chunk',
      'content': {
        'type': 'text',
        'text': selectedOptionId != null
            ? 'approved: $selectedOptionId'
            : 'permission request was cancelled',
      },
    },
  });
  _writeResponse(promptId, {
    'stopReason': selectedOptionId != null ? 'end_turn' : 'cancelled',
  });
}

void _handleFsReadResponse(Map<String, Object?> message) {
  final promptId = _pendingPromptId;
  if (promptId == null) {
    return;
  }

  final error = message['error'] as Map<String, Object?>?;
  if (error != null) {
    // Expected outcome for with_fs_path_escape — the client rejected the
    // out-of-bounds read before touching the filesystem.
    _pendingPromptId = null;
    _writeNotification('session/update', {
      'sessionId': _sessionId,
      'update': {
        'sessionUpdate': 'agent_message_chunk',
        'content': {
          'type': 'text',
          'text': 'fs/read_text_file rejected: ${error['message']}',
        },
      },
    });
    _writeResponse(promptId, {'stopReason': 'end_turn'});
    return;
  }

  final result = message['result'] as Map<String, Object?>;
  _fsReadContent = result['content'] as String;

  if (_mode == 'with_fs_path_escape') {
    // The read should have been rejected — reaching here (a successful
    // read of an out-of-bounds path) is itself the test failure; report it
    // in-band so the integration test's assertions catch it clearly.
    _pendingPromptId = null;
    _writeNotification('session/update', {
      'sessionId': _sessionId,
      'update': {
        'sessionUpdate': 'agent_message_chunk',
        'content': {
          'type': 'text',
          'text': 'SECURITY FAILURE: escaped read succeeded: $_fsReadContent',
        },
      },
    });
    _writeResponse(promptId, {'stopReason': 'end_turn'});
    return;
  }

  _writeRequest(_fsWriteRequestId, 'fs/write_text_file', {
    'sessionId': _sessionId,
    'path': '$_sessionCwd/output.txt',
    'content': 'echo: $_fsReadContent',
  });
}

void _handleFsWriteResponse(Map<String, Object?> message) {
  final promptId = _pendingPromptId;
  if (promptId == null) {
    return;
  }
  _pendingPromptId = null;

  final error = message['error'] as Map<String, Object?>?;
  _writeNotification('session/update', {
    'sessionId': _sessionId,
    'update': {
      'sessionUpdate': 'agent_message_chunk',
      'content': {
        'type': 'text',
        'text': error != null
            ? 'fs/write_text_file failed: ${error['message']}'
            : 'fs roundtrip complete: $_fsReadContent',
      },
    },
  });
  _writeResponse(promptId, {'stopReason': 'end_turn'});
}

void _handleTerminalCreateResponse(Map<String, Object?> message) {
  final promptId = _pendingPromptId;
  if (promptId == null) {
    return;
  }

  final error = message['error'] as Map<String, Object?>?;
  if (error != null) {
    // Expected outcome for with_terminal_path_escape — the client rejected
    // the out-of-bounds cwd before starting any process.
    _pendingPromptId = null;
    _writeNotification('session/update', {
      'sessionId': _sessionId,
      'update': {
        'sessionUpdate': 'agent_message_chunk',
        'content': {
          'type': 'text',
          'text': 'terminal/create rejected: ${error['message']}',
        },
      },
    });
    _writeResponse(promptId, {'stopReason': 'end_turn'});
    return;
  }

  final result = message['result'] as Map<String, Object?>;
  _terminalId = result['terminalId'] as String;

  if (_mode == 'with_terminal_kill') {
    _writeRequest(_terminalKillRequestId, 'terminal/kill', {
      'sessionId': _sessionId,
      'terminalId': _terminalId,
    });
  } else {
    _writeRequest(_terminalWaitRequestId, 'terminal/wait_for_exit', {
      'sessionId': _sessionId,
      'terminalId': _terminalId,
    });
  }
}

void _handleTerminalWaitResponse(Map<String, Object?> message) {
  _writeRequest(_terminalOutputRequestId, 'terminal/output', {
    'sessionId': _sessionId,
    'terminalId': _terminalId,
  });
}

void _handleTerminalKillResponse(Map<String, Object?> message) {
  _writeRequest(_terminalOutputRequestId, 'terminal/output', {
    'sessionId': _sessionId,
    'terminalId': _terminalId,
  });
}

void _handleTerminalOutputResponse(Map<String, Object?> message) {
  final promptId = _pendingPromptId;
  if (promptId == null) {
    return;
  }
  _pendingPromptId = null;

  final result = message['result'] as Map<String, Object?>;
  final output = result['output'];
  final exitStatus = result['exitStatus'];
  _writeNotification('session/update', {
    'sessionId': _sessionId,
    'update': {
      'sessionUpdate': 'agent_message_chunk',
      'content': {
        'type': 'text',
        'text': 'terminal output: $output exitStatus: $exitStatus',
      },
    },
  });
  _writeResponse(promptId, {'stopReason': 'end_turn'});
}

void _writeRequest(Object? id, String method, Map<String, Object?> params) {
  stdout.writeln(jsonEncode({
    'jsonrpc': '2.0',
    'id': id,
    'method': method,
    'params': params,
  }));
}

void _writeResponse(Object? id, Map<String, Object?> result) {
  stdout.writeln(jsonEncode({'jsonrpc': '2.0', 'id': id, 'result': result}));
}

void _writeNotification(String method, Map<String, Object?> params) {
  stdout.writeln(jsonEncode({
    'jsonrpc': '2.0',
    'method': method,
    'params': params,
  }));
}

void _writeError(Object? id, int code, String message) {
  stdout.writeln(jsonEncode({
    'jsonrpc': '2.0',
    'id': id,
    'error': {'code': code, 'message': message},
  }));
}
''';
