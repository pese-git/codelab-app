// Режимы scripted-агента для сценариев CLI (tasks 4.11 change
// `add-codelab-cli`; design D10): настоящий процесс агента на Dart VM,
// кадры JSON-RPC построчно через stdin/stdout.

import 'dart:async';
import 'dart:io';

import 'package:codelab_acp_testing/codelab_acp_testing.dart';
import 'package:test/test.dart';

import 'support/agent_process.dart';

void main() {
  late Directory directory;
  late AgentProcess agent;

  Future<String> start(CodelabCompatibleStdioAgentMode mode) async {
    directory = await Directory.systemTemp.createTemp('cli_modes_agent_');
    agent = await AgentProcess.start(
      await writeCodelabCompatibleStdioAgent(directory, mode: mode),
    );
    await agent.request('initialize', {'protocolVersion': 1});
    return agent.newSession(directory.path);
  }

  tearDown(() async {
    await agent.stop();
    await directory.delete(recursive: true);
  });

  test('prompt_error answers session/prompt with a CodeLab error', () async {
    final sessionId = await start(CodelabCompatibleStdioAgentMode.promptError);

    final response = await agent.prompt(sessionId, 'hi');

    expect(response['error'], {
      'code': -32603,
      'message': 'Turn failed',
      'data': {
        'codelab': {
          'errorClass': 'provider',
          'message': 'Provider is unavailable',
          'retryable': false,
        },
      },
    });
  });

  test('empty_response ends the turn without an answer', () async {
    final sessionId = await start(
      CodelabCompatibleStdioAgentMode.emptyResponse,
    );

    final response = await agent.prompt(sessionId, 'hi');

    expect(response['result'], {'stopReason': 'end_turn'});
    expect(agent.updates, isEmpty);
  });

  test('hangs_until_cancel answers only after session/cancel', () async {
    final sessionId = await start(
      CodelabCompatibleStdioAgentMode.hangsUntilCancel,
    );

    final response = agent.prompt(sessionId, 'hi');
    var answered = false;
    unawaited(response.then((_) => answered = true));
    await Future<void>.delayed(const Duration(milliseconds: 300));
    expect(answered, isFalse);
    agent.notify('session/cancel', {'sessionId': sessionId});

    expect((await response)['result'], {'stopReason': 'cancelled'});
  });

  test('with_critical_permission asks with _meta.codelab.critical and '
      'reports the chosen option', () async {
    final sessionId = await start(
      CodelabCompatibleStdioAgentMode.withCriticalPermission,
    );

    final response = agent.prompt(sessionId, 'clean up');
    await Future.doWhile(() async {
      await Future<void>.delayed(const Duration(milliseconds: 20));
      return !agent.received.any(
        (f) => f['method'] == 'session/request_permission',
      );
    }).timeout(const Duration(seconds: 10));
    final request = agent.received.firstWhere(
      (f) => f['method'] == 'session/request_permission',
    );
    final toolCall = (request['params']! as Map)['toolCall']! as Map;
    expect(toolCall['_meta'], {
      'codelab': {'critical': true, 'label': 'recursive delete'},
    });
    expect(
      [
        for (final option in (request['params']! as Map)['options']! as List)
          (option as Map)['kind'],
      ],
      ['allow_once', 'reject_once'],
    );
    agent.reply(request['id'], {
      'outcome': {'outcome': 'selected', 'optionId': 'reject_once'},
    });

    expect((await response)['result'], {'stopReason': 'end_turn'});
    expect(
      [
        for (final update in agent.updates)
          if (update['sessionUpdate'] == 'agent_message_chunk')
            (update['content']! as Map)['text'],
      ],
      ['approved: reject_once'],
    );
  });
  test('with_tool_calls thinks, runs read and exec, asks for edit and then '
      'answers', () async {
    final sessionId = await start(
      CodelabCompatibleStdioAgentMode.withToolCalls,
    );

    final response = agent.prompt(sessionId, 'fix it');
    await Future.doWhile(() async {
      await Future<void>.delayed(const Duration(milliseconds: 20));
      return !agent.received.any(
        (f) => f['method'] == 'session/request_permission',
      );
    }).timeout(const Duration(seconds: 10));
    final request = agent.received.firstWhere(
      (f) => f['method'] == 'session/request_permission',
    );
    expect(((request['params']! as Map)['toolCall']! as Map)['kind'], 'edit');
    agent.reply(request['id'], {
      'outcome': {'outcome': 'selected', 'optionId': 'allow_once'},
    });

    expect((await response)['result'], {'stopReason': 'end_turn'});
    final kinds = [for (final u in agent.updates) u['sessionUpdate']];
    expect(kinds.take(3), everyElement('agent_thought_chunk'));
    expect(kinds.last, 'agent_message_chunk');
    final calls = {
      for (final u in agent.updates)
        if (u['sessionUpdate'] == 'tool_call') u['kind']: u,
    };
    expect(calls.keys, containsAll(['read', 'execute', 'edit']));
    expect(
      (calls['execute']!['rawInput']! as Map)['env'],
      isA<Map<String, Object?>>(),
    );
    final finished = {
      for (final u in agent.updates)
        if (u['sessionUpdate'] == 'tool_call_update' &&
            u['status'] == 'completed')
          u['toolCallId'],
    };
    expect(finished, hasLength(3));
  });
}
