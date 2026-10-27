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
  withTerminalKill('with_terminal_kill'),
  withPlan('with_plan'),
  withQueuedPromptDrain('with_queued_prompt_drain'),
  withConcurrentSessions('with_concurrent_sessions'),

  /// Агент со списком и загрузкой сессий: объявляет `loadSession` и
  /// `sessionCapabilities.list`, отдаёт `session/list` страницами по две
  /// сессии с непрозрачным курсором и повторяет историю на `session/load`.
  /// Сессии хранятся в файле `<скрипт>.sessions.json` рядом со скриптом и
  /// переживают перезапуск процесса (design D8 change
  /// `add-session-list-and-reload`).
  withSessionList('with_session_list'),

  /// Агент с командами палитры: после ответа на `session/new` объявляет
  /// `available_commands_update` с `compact` без `input` и `plan` с
  /// `input.hint`; на промпт `/compact` отвечает отчётом о сжатии, на
  /// остальные — `echo: <text>` (design D6 change
  /// `add-command-palette-agent-commands`).
  withAvailableCommands('with_available_commands'),

  /// Агент, у которого ход срывается: на `session/prompt` — JSON-RPC ошибка
  /// `-32603` с `data.codelab` класса `provider` (design D10 change
  /// `add-codelab-cli`).
  promptError('prompt_error'),

  /// Агент, который завершает ход `end_turn` без единого
  /// `agent_message_chunk` (design D10 change `add-codelab-cli`).
  emptyResponse('empty_response'),

  /// Агент, который не отвечает на `session/prompt`, пока не придёт
  /// `session/cancel`, и тогда завершает ход `cancelled` (design D10 change
  /// `add-codelab-cli`).
  hangsUntilCancel('hangs_until_cancel'),

  /// Агент, который на промпт запрашивает одобрение опасной команды с
  /// `_meta.codelab.critical: true` (как Dart-агент) и вариантами
  /// `allow_once` и `reject_once`; затем сообщает выбранный вариант
  /// (design D10 change `add-codelab-cli`).
  withCriticalPermission('with_critical_permission'),

  /// Ход терминального клиента: три `agent_thought_chunk`, вызовы `read` и
  /// `execute` (с вложенным `rawInput.env`) со статусом `completed`, затем
  /// `edit` с запросом одобрения; после ответа — `completed` или `failed`
  /// правки и ответ агента (design D10 change `add-codelab-cli`).
  withToolCalls('with_tool_calls');

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
const _permissionRequestId = 'perm-1';
const _fsReadRequestId = 'fs-read-1';
const _fsWriteRequestId = 'fs-write-1';
const _terminalCreateRequestId = 'terminal-create-1';
const _terminalWaitRequestId = 'terminal-wait-1';
const _terminalOutputRequestId = 'terminal-output-1';
const _terminalKillRequestId = 'terminal-kill-1';
var _currentModel = 'gpt-5';
var _planPromptCount = 0;
var _queuedPromptDrainRequestCount = 0;
var _sessionCounter = 0;
// Creation order matters for `with_concurrent_sessions` ("the first session"
// vs. "a later one") — a `Set` would lose it.
final _sessionIds = <String>[];
// Independently tracks each session's own deferred `session/prompt` id, so
// two sessions on the same process (e.g. one hung on a permission request
// while another sends its own prompt) never clobber each other's pending
// response the way a single shared variable would.
final _pendingPromptIds = <String, Object?>{};
// Which session the *current* single-flight side-request (permission/fs/
// terminal) belongs to — set right before issuing it, read by that
// side-request's response handler, which has no session context of its own
// (the client's JSON-RPC response carries no `sessionId`). None of today's
// modes ever have two such side-requests outstanding at once, so one slot
// is enough — see codelab_compatible_stdio_agent.dart's per-mode branches.
String? _pendingSessionId;
String? _sessionCwd;
String? _fsReadContent;
String? _terminalId;

// Журнал сессий режима `with_session_list`: рядом со скриптом, чтобы новый
// процесс агента знал сессии прежнего.
File get _journalFile => File('${Platform.script.toFilePath()}.sessions.json');

List<Map<String, Object?>> _readJournal() {
  if (!_journalFile.existsSync()) {
    return [];
  }
  return [
    for (final session in jsonDecode(_journalFile.readAsStringSync()) as List)
      (session as Map).cast<String, Object?>(),
  ];
}

void _writeJournal(List<Map<String, Object?>> sessions) =>
    _journalFile.writeAsStringSync(jsonEncode(sessions));

Map<String, Object?>? _journalSession(
  List<Map<String, Object?>> journal,
  String sessionId,
) => journal.where((session) => session['sessionId'] == sessionId).firstOrNull;

String _createSessionId() {
  _sessionCounter += 1;
  // The first session keeps the exact, unsuffixed id existing single-session
  // tests already assert on; only a second/third/... session gets a suffix.
  final sessionId = _sessionCounter == 1
      ? 'codelab-test-session'
      : 'codelab-test-session-$_sessionCounter';
  _sessionIds.add(sessionId);
  return sessionId;
}

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
            'loadSession': _mode == 'with_session_list',
            'mcpCapabilities': {'http': false, 'sse': false},
            'promptCapabilities': {
              'audio': false,
              'embeddedContext': false,
              'image': false,
            },
            'sessionCapabilities': {
              if (_mode == 'with_session_list') 'list': <String, Object?>{},
            },
          },
          'agentInfo': {
            'name': 'codelab-compatible-test-agent',
            'version': '0.1.0',
          },
          'authMethods': <Object?>[],
        });
      case 'session/new':
        final params = message['params'] as Map<String, Object?>;
        if (_mode == 'with_session_list') {
          final journal = _readJournal();
          final sessionId = 'codelab-list-session-${journal.length + 1}';
          journal.add({
            'sessionId': sessionId,
            'cwd': params['cwd'],
            'turns': <Object?>[],
          });
          _writeJournal(journal);
          _writeResponse(id, {'sessionId': sessionId});
          break;
        }
        final sessionId = _createSessionId();
        _sessionCwd = params['cwd'] as String?;
        _writeResponse(id, {
          'sessionId': sessionId,
          if (_mode == 'with_config_options')
            'configOptions': [_modelConfigOption()],
        });
        if (_mode == 'with_available_commands') {
          // После ответа, как у Dart-агента (agent-acp-server): до ответа у
          // клиента ещё нет сессии, к которой отнести команды.
          _writeNotification('session/update', {
            'sessionId': sessionId,
            'update': {
              'sessionUpdate': 'available_commands_update',
              'availableCommands': [
                {'name': 'compact', 'description': 'Compact the conversation'},
                {
                  'name': 'plan',
                  'description': 'Create a plan',
                  'input': {'hint': 'what to plan'},
                },
              ],
            },
          });
        }
      case 'session/prompt':
        final promptParams = message['params'] as Map<String, Object?>;
        final sessionId = promptParams['sessionId'] as String;
        if (_mode == 'with_session_list') {
          final text =
              ((promptParams['prompt'] as List).first as Map)['text'] as String;
          final journal = _readJournal();
          final session = _journalSession(journal, sessionId);
          if (session == null) {
            _writeError(id, -32002, 'Resource not found');
            break;
          }
          session['title'] ??= text;
          (session['turns'] as List).add({
            'user': text,
            'agent': 'echo: $text',
          });
          _writeJournal(journal);
          _writeNotification('session/update', {
            'sessionId': sessionId,
            'update': {
              'sessionUpdate': 'agent_message_chunk',
              'content': {'type': 'text', 'text': 'echo: $text'},
            },
          });
          _writeResponse(id, {'stopReason': 'end_turn'});
          break;
        }
        if (_mode == 'with_available_commands') {
          // Команда приходит обычным промптом, текст начинается с `/name`
          // (`14-Slash Commands.md`); агент узнаёт её по префиксу.
          final text =
              ((promptParams['prompt'] as List).first as Map)['text'] as String;
          _writeNotification('session/update', {
            'sessionId': sessionId,
            'update': {
              'sessionUpdate': 'agent_message_chunk',
              'content': {
                'type': 'text',
                'text': text.startsWith('/compact')
                    ? 'Compacted the conversation.'
                    : 'echo: $text',
              },
            },
          });
          _writeResponse(id, {'stopReason': 'end_turn'});
          break;
        }
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
          _pendingSessionId = sessionId;
          _pendingPromptIds[sessionId] = id;
          _writeRequest(_fsReadRequestId, 'fs/read_text_file', {
            'sessionId': sessionId,
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
            'sessionId': sessionId,
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
          _pendingSessionId = sessionId;
          _pendingPromptIds[sessionId] = id;
          _writeRequest(_fsReadRequestId, 'fs/read_text_file', {
            'sessionId': sessionId,
            'path': '$_sessionCwd/../escape.txt',
          });
          break;
        }
        if (_mode == 'with_terminal_execution') {
          // Runs a real command via terminal/create, waits for it to exit,
          // then fetches its output — the real terminal/* round trip, no
          // approval step (see add-acp-terminal-client-support/design.md).
          _pendingSessionId = sessionId;
          _pendingPromptIds[sessionId] = id;
          _writeRequest(_terminalCreateRequestId, 'terminal/create', {
            'sessionId': sessionId,
            'command': 'sh',
            'args': ['-c', 'echo hello-from-terminal; exit 3'],
          });
          break;
        }
        if (_mode == 'with_terminal_path_escape') {
          // Attempt to run a command outside the working directory — the
          // client MUST reject this before starting any process.
          _pendingSessionId = sessionId;
          _pendingPromptIds[sessionId] = id;
          _writeRequest(_terminalCreateRequestId, 'terminal/create', {
            'sessionId': sessionId,
            'command': 'echo',
            'args': ['should not run'],
            'cwd': '$_sessionCwd/../escape',
          });
          break;
        }
        if (_mode == 'with_terminal_kill') {
          // Starts a long-running process, then kills it immediately —
          // terminalId must stay valid afterwards for terminal/output.
          _pendingSessionId = sessionId;
          _pendingPromptIds[sessionId] = id;
          _writeRequest(_terminalCreateRequestId, 'terminal/create', {
            'sessionId': sessionId,
            'command': 'sleep',
            'args': ['30'],
          });
          break;
        }
        if (_mode == 'with_plan') {
          // The first two prompts report a partial plan (one entry still
          // in_progress) so an e2e test can exercise the docked activity
          // bar's compact summary, expansion, and dismiss-then-repopulate
          // behavior; the third and any later prompt reports every entry
          // completed, so the same test can also confirm the section
          // disappears entirely once there is nothing left to show (see
          // add-plan-progress-checklist/design.md, Decisions).
          _planPromptCount += 1;
          final allCompleted = _planPromptCount >= 3;
          _writeNotification('session/update', {
            'sessionId': sessionId,
            'update': {
              'sessionUpdate': 'plan',
              'entries': [
                {
                  'content':
                      'Read auth module and locate token refresh call sites',
                  'priority': 'medium',
                  'status': 'completed',
                },
                {
                  'content': 'Run melos analyze to confirm no new lint issues',
                  'priority': 'high',
                  'status': allCompleted ? 'completed' : 'in_progress',
                },
                {
                  'content': 'Open PR for review',
                  'priority': 'low',
                  'status': allCompleted ? 'completed' : 'pending',
                },
              ],
            },
          });
          _writeResponse(id, {'stopReason': 'end_turn'});
          break;
        }
        if (_mode == 'prompt_error') {
          _writeErrorWithData(id, -32603, 'Turn failed', {
            'codelab': {
              'errorClass': 'provider',
              'message': 'Provider is unavailable',
              'retryable': false,
            },
          });
          break;
        }
        if (_mode == 'empty_response') {
          _writeResponse(id, {'stopReason': 'end_turn'});
          break;
        }
        if (_mode == 'hangs_until_cancel') {
          _pendingPromptIds[sessionId] = id;
          break;
        }
        if (_mode == 'with_critical_permission') {
          _pendingSessionId = sessionId;
          _pendingPromptIds[sessionId] = id;
          _writeRequest(_permissionRequestId, 'session/request_permission', {
            'sessionId': sessionId,
            'toolCall': {
              'toolCallId': 'test-tool-call-1',
              'title': 'Run rm -rf build',
              'kind': 'execute',
              'status': 'pending',
              'rawInput': {'command': 'rm -rf build'},
              '_meta': {
                'codelab': {'critical': true, 'label': 'recursive delete'},
              },
            },
            'options': [
              {'optionId': 'allow_once', 'name': 'Allow once', 'kind': 'allow_once'},
              {'optionId': 'reject_once', 'name': 'Reject once', 'kind': 'reject_once'},
            ],
          });
          break;
        }
        if (_mode == 'with_tool_calls') {
          // Ход терминального клиента целиком: мысли, два завершённых вызова
          // (у `execute` во `rawInput` вложенный объект `env` — строка
          // инструмента CLI не должна его показывать) и правка, которая ждёт
          // одобрения; ответ — после него (design D10 change
          // `add-codelab-cli`).
          void update(Map<String, Object?> update) => _writeNotification(
            'session/update',
            {'sessionId': sessionId, 'update': update},
          );
          for (final text in ['Looking at ', 'the failing ', 'test.']) {
            update({
              'sessionUpdate': 'agent_thought_chunk',
              'content': {'type': 'text', 'text': text},
            });
          }
          update({
            'sessionUpdate': 'tool_call',
            'toolCallId': 'read-1',
            'title': 'Read README.md',
            'kind': 'read',
            'status': 'in_progress',
            'rawInput': {'path': 'README.md'},
          });
          update({
            'sessionUpdate': 'tool_call_update',
            'toolCallId': 'read-1',
            'status': 'completed',
          });
          update({
            'sessionUpdate': 'tool_call',
            'toolCallId': 'exec-1',
            'title': 'Run dart test',
            'kind': 'execute',
            'status': 'in_progress',
            'rawInput': {
              'command': 'dart test',
              'env': {'CI': 'true', 'DART_TEST': '1'},
            },
          });
          update({
            'sessionUpdate': 'tool_call_update',
            'toolCallId': 'exec-1',
            'status': 'completed',
          });
          update({
            'sessionUpdate': 'tool_call',
            'toolCallId': 'edit-1',
            'title': 'Edit lib/main.dart',
            'kind': 'edit',
            'status': 'pending',
            'rawInput': {'path': 'lib/main.dart', 'newText': 'fixed'},
          });
          _pendingSessionId = sessionId;
          _pendingPromptIds[sessionId] = id;
          _writeRequest(_permissionRequestId, 'session/request_permission', {
            'sessionId': sessionId,
            'toolCall': {
              'toolCallId': 'edit-1',
              'title': 'Edit lib/main.dart',
              'kind': 'edit',
              'status': 'pending',
              'rawInput': {'path': 'lib/main.dart', 'newText': 'fixed'},
            },
            'options': [
              {'optionId': 'allow_once', 'name': 'Allow once', 'kind': 'allow_once'},
              {'optionId': 'reject_once', 'name': 'Reject once', 'kind': 'reject_once'},
            ],
          });
          break;
        }
        if (_mode == 'with_permission_request') {
          // Defer the `session/prompt` response until the client answers
          // our `session/request_permission` — a real agent waits for the
          // permission outcome before deciding how the turn ends.
          _pendingSessionId = sessionId;
          _pendingPromptIds[sessionId] = id;
          _writeRequest(_permissionRequestId, 'session/request_permission', {
            'sessionId': sessionId,
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
        if (_mode == 'with_queued_prompt_drain') {
          // The first prompt only — defers its response behind a permission
          // request, so the client's session stays busy long enough for an
          // e2e test to submit a second prompt through the real composer
          // and see it queue. Any later prompt (the queue's own auto-drained
          // entry, or a manual Send Now) needs no approval and completes
          // immediately with distinguishable text, so the test can confirm
          // it was actually delivered — not merely removed from the queue.
          _queuedPromptDrainRequestCount += 1;
          if (_queuedPromptDrainRequestCount == 1) {
            _pendingSessionId = sessionId;
            _pendingPromptIds[sessionId] = id;
            _writeRequest(_permissionRequestId, 'session/request_permission', {
              'sessionId': sessionId,
              'toolCall': {
                'toolCallId': 'test-tool-call-1',
                'title': 'Run test command',
                'kind': 'execute',
                'status': 'pending',
                'rawInput': {'command': 'echo hello', 'shell': '/bin/bash'},
              },
              'options': [
                {'optionId': 'allow_once', 'name': 'Allow once', 'kind': 'allow_once'},
              ],
            });
            break;
          }
          _writeNotification('session/update', {
            'sessionId': sessionId,
            'update': {
              'sessionUpdate': 'agent_message_chunk',
              'content': {'type': 'text', 'text': 'queued message delivered'},
            },
          });
          _writeResponse(id, {'stopReason': 'end_turn'});
          break;
        }
        if (_mode == 'with_concurrent_sessions') {
          // Only the very first session ever created hangs on a permission
          // request; every other session (created afterwards, on the same
          // process) always responds immediately — proving a later session's
          // `session/prompt` is never blocked by an earlier one's pending
          // approval. See add-multi-session-concurrency/design.md.
          if (_sessionIds.first == sessionId) {
            _pendingSessionId = sessionId;
            _pendingPromptIds[sessionId] = id;
            _writeRequest(_permissionRequestId, 'session/request_permission', {
              'sessionId': sessionId,
              'toolCall': {
                'toolCallId': 'test-tool-call-1',
                'title': 'Run test command',
                'kind': 'execute',
                'status': 'pending',
                'rawInput': {'command': 'echo hello', 'shell': '/bin/bash'},
              },
              'options': [
                {'optionId': 'allow_once', 'name': 'Allow once', 'kind': 'allow_once'},
              ],
            });
            break;
          }
          _writeNotification('session/update', {
            'sessionId': sessionId,
            'update': {
              'sessionUpdate': 'agent_message_chunk',
              'content': {
                'type': 'text',
                'text': 'hello from $sessionId',
              },
            },
          });
          _writeResponse(id, {'stopReason': 'end_turn'});
          break;
        }
        _writeNotification('session/update', {
          'sessionId': sessionId,
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
      case 'session/list' when _mode == 'with_session_list':
        final params = message['params'] as Map<String, Object?>? ?? const {};
        final cwd = params['cwd'] as String?;
        // Курсор — смещение строкой; для клиента он непрозрачен.
        final offset = int.parse(params['cursor'] as String? ?? '0');
        final matching = [
          for (final session in _readJournal().reversed)
            if (cwd == null || session['cwd'] == cwd) session,
        ];
        final page = matching.skip(offset).take(2).toList();
        _writeResponse(id, {
          'sessions': [
            for (final session in page)
              {
                'sessionId': session['sessionId'],
                'cwd': session['cwd'],
                if (session['title'] != null) 'title': session['title'],
              },
          ],
          if (offset + page.length < matching.length)
            'nextCursor': '${offset + page.length}',
        });
      case 'session/load' when _mode == 'with_session_list':
        final params = message['params'] as Map<String, Object?>;
        final sessionId = params['sessionId'] as String;
        final session = _journalSession(_readJournal(), sessionId);
        if (session == null) {
          _writeError(id, -32002, 'Resource not found');
          break;
        }
        // История повторяется до ответа (`03-Session Setup.md`, «Loading a
        // Session»).
        for (final turn in session['turns'] as List) {
          for (final (kind, key) in [
            ('user_message_chunk', 'user'),
            ('agent_message_chunk', 'agent'),
          ]) {
            _writeNotification('session/update', {
              'sessionId': sessionId,
              'update': {
                'sessionUpdate': kind,
                'content': {'type': 'text', 'text': (turn as Map)[key]},
              },
            });
          }
        }
        _writeResponse(id, <String, Object?>{});
      case 'session/cancel':
        // Уведомление: ответа нет (`07-Prompt Turn.md`, «Cancellation»).
        // Ход, который ждёт отмены, завершается `cancelled`.
        final params = message['params'] as Map<String, Object?>;
        final promptId = _mode == 'hangs_until_cancel'
            ? _pendingPromptIds.remove(params['sessionId'])
            : null;
        if (promptId != null) {
          _writeResponse(promptId, {'stopReason': 'cancelled'});
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
  final sessionId = _pendingSessionId;
  final promptId = sessionId == null ? null : _pendingPromptIds.remove(sessionId);
  if (sessionId == null || promptId == null) {
    return;
  }
  _pendingSessionId = null;

  final result = message['result'] as Map<String, Object?>?;
  final outcome = result?['outcome'] as Map<String, Object?>?;
  final selectedOptionId = outcome?['optionId'] as String?;

  if (_mode == 'with_tool_calls') {
    // Правка выполнена только при `allow_once`; отказ и отмена — `failed`.
    final allowed = selectedOptionId == 'allow_once';
    _writeNotification('session/update', {
      'sessionId': sessionId,
      'update': {
        'sessionUpdate': 'tool_call_update',
        'toolCallId': 'edit-1',
        'status': allowed ? 'completed' : 'failed',
      },
    });
    _writeNotification('session/update', {
      'sessionId': sessionId,
      'update': {
        'sessionUpdate': 'agent_message_chunk',
        'content': {
          'type': 'text',
          'text': allowed ? 'Fixed the test.' : 'Left the file unchanged.',
        },
      },
    });
    _writeResponse(promptId, {
      'stopReason': selectedOptionId != null ? 'end_turn' : 'cancelled',
    });
    return;
  }

  _writeNotification('session/update', {
    'sessionId': sessionId,
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
  final sessionId = _pendingSessionId;
  final promptId = sessionId == null ? null : _pendingPromptIds[sessionId];
  if (sessionId == null || promptId == null) {
    return;
  }

  final error = message['error'] as Map<String, Object?>?;
  if (error != null) {
    // Expected outcome for with_fs_path_escape — the client rejected the
    // out-of-bounds read before touching the filesystem.
    _pendingSessionId = null;
    _pendingPromptIds.remove(sessionId);
    _writeNotification('session/update', {
      'sessionId': sessionId,
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
    _pendingSessionId = null;
    _pendingPromptIds.remove(sessionId);
    _writeNotification('session/update', {
      'sessionId': sessionId,
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
    'sessionId': sessionId,
    'path': '$_sessionCwd/output.txt',
    'content': 'echo: $_fsReadContent',
  });
}

void _handleFsWriteResponse(Map<String, Object?> message) {
  final sessionId = _pendingSessionId;
  final promptId = sessionId == null ? null : _pendingPromptIds.remove(sessionId);
  if (sessionId == null || promptId == null) {
    return;
  }
  _pendingSessionId = null;

  final error = message['error'] as Map<String, Object?>?;
  _writeNotification('session/update', {
    'sessionId': sessionId,
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
  final sessionId = _pendingSessionId;
  final promptId = sessionId == null ? null : _pendingPromptIds[sessionId];
  if (sessionId == null || promptId == null) {
    return;
  }

  final error = message['error'] as Map<String, Object?>?;
  if (error != null) {
    // Expected outcome for with_terminal_path_escape — the client rejected
    // the out-of-bounds cwd before starting any process.
    _pendingSessionId = null;
    _pendingPromptIds.remove(sessionId);
    _writeNotification('session/update', {
      'sessionId': sessionId,
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
      'sessionId': sessionId,
      'terminalId': _terminalId,
    });
  } else {
    _writeRequest(_terminalWaitRequestId, 'terminal/wait_for_exit', {
      'sessionId': sessionId,
      'terminalId': _terminalId,
    });
  }
}

void _handleTerminalWaitResponse(Map<String, Object?> message) {
  _writeRequest(_terminalOutputRequestId, 'terminal/output', {
    'sessionId': _pendingSessionId,
    'terminalId': _terminalId,
  });
}

void _handleTerminalKillResponse(Map<String, Object?> message) {
  _writeRequest(_terminalOutputRequestId, 'terminal/output', {
    'sessionId': _pendingSessionId,
    'terminalId': _terminalId,
  });
}

void _handleTerminalOutputResponse(Map<String, Object?> message) {
  final sessionId = _pendingSessionId;
  final promptId = sessionId == null ? null : _pendingPromptIds.remove(sessionId);
  if (sessionId == null || promptId == null) {
    return;
  }
  _pendingSessionId = null;

  final result = message['result'] as Map<String, Object?>;
  final output = result['output'];
  final exitStatus = result['exitStatus'];
  _writeNotification('session/update', {
    'sessionId': sessionId,
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

void _writeErrorWithData(
  Object? id,
  int code,
  String message,
  Map<String, Object?> data,
) {
  stdout.writeln(jsonEncode({
    'jsonrpc': '2.0',
    'id': id,
    'error': {'code': code, 'message': message, 'data': data},
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
