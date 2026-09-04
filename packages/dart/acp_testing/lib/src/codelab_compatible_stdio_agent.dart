import 'dart:io';

enum CodelabCompatibleStdioAgentMode {
  normal('normal'),
  exitOnStart('exit_on_start'),
  invalidStdout('invalid_stdout'),
  withConfigOptions('with_config_options'),
  crashMidPrompt('crash_mid_prompt'),
  withPermissionRequest('with_permission_request');

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
var _currentModel = 'gpt-5';
Object? _pendingPromptId;

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
