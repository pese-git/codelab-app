// Характеризация опций конфигурации `CodeLabShellCubit` (задача 5.0,
// tasks 1.5).
//
// Фиксирует флаг запроса в полёте, его сброс после успеха и ошибки, отказ
// от второго запроса во время первого и опции из `config_option_update`.
// Текст тестов не меняется до конца change (design D1).

import 'package:codelab_acp_protocol/codelab_acp_protocol.dart';
import 'package:flutter_test/flutter_test.dart';

import 'harness.dart';

List<Map<String, Object?>> _modelOption(String current) => [
  {
    'type': 'select',
    'id': 'model',
    'name': 'Model',
    'currentValue': current,
    'options': [
      {'value': 'gpt-5', 'name': 'GPT-5'},
      {'value': 'gpt-4', 'name': 'GPT-4'},
    ],
  },
];

void main() {
  setUp(setUpCharacterization);

  test('setSessionConfigOption() is in flight until the agent answers, and '
      "the agent's answer becomes the shown value", () async {
    final h = ShellHarness();
    await h.connect();
    await h.createSession('session-1', configOptions: _modelOption('gpt-5'));
    expect(h.cubit.state.configOptions.single.currentValue, 'gpt-5');

    final requestFuture = h.nextSent(sessionSetConfigOptionMethod);
    final setFuture = h.cubit.setSessionConfigOption('model', 'gpt-4');
    final request = await requestFuture as JsonRpcRequest;
    expect(h.cubit.state.isRespondingToConfigOption, isTrue);
    expect(h.cubit.state.configOptions.single.currentValue, 'gpt-5');
    expect(request.params, containsPair('configId', 'model'));
    expect(request.params, containsPair('value', 'gpt-4'));

    h.agent.emitInbound(
      JsonRpcMessage.response(
        id: request.id,
        result: {'configOptions': _modelOption('gpt-4')},
      ),
    );
    await setFuture;

    expect(h.cubit.state.isRespondingToConfigOption, isFalse);
    expect(h.cubit.state.configOptions.single.currentValue, 'gpt-4');
  });

  test('a second call while one is in flight sends nothing', () async {
    final h = ShellHarness();
    await h.connect();
    await h.createSession('session-1', configOptions: _modelOption('gpt-5'));

    final requestFuture = h.nextSent(sessionSetConfigOptionMethod);
    final setFuture = h.cubit.setSessionConfigOption('model', 'gpt-4');
    final request = await requestFuture as JsonRpcRequest;
    final sentInFlight = h.agent.sentMessages.length;

    await h.cubit.setSessionConfigOption('model', 'gpt-5');
    expect(h.agent.sentMessages, hasLength(sentInFlight));

    h.agent.emitInbound(
      JsonRpcMessage.response(
        id: request.id,
        result: {'configOptions': _modelOption('gpt-4')},
      ),
    );
    await setFuture;
    expect(h.cubit.state.configOptions.single.currentValue, 'gpt-4');
  });

  test('an error answer clears the in-flight flag and keeps the old '
      'value', () async {
    final h = ShellHarness();
    await h.connect();
    await h.createSession('session-1', configOptions: _modelOption('gpt-5'));

    final requestFuture = h.nextSent(sessionSetConfigOptionMethod);
    final setFuture = h.cubit.setSessionConfigOption('model', 'gpt-4');
    final request = await requestFuture as JsonRpcRequest;
    h.agent.emitInbound(
      JsonRpcMessage.response(
        id: request.id,
        error: const JsonRpcError(code: -32602, message: 'unknown value'),
      ),
    );
    await setFuture;

    expect(h.cubit.state.isRespondingToConfigOption, isFalse);
    expect(h.cubit.state.configOptions.single.currentValue, 'gpt-5');
    expect(
      h.logEvents,
      contains(startsWith('Failed to set config option model')),
    );
  });

  test('config_option_update replaces the options shown for the active '
      'session', () async {
    final h = ShellHarness();
    await h.connect();
    await h.createSession('session-1');
    expect(h.cubit.state.configOptions, isEmpty);

    h.sessionUpdate('session-1', {
      'sessionUpdate': 'config_option_update',
      'configOptions': _modelOption('gpt-4'),
    });

    expect(h.cubit.state.configOptions.single.id, 'model');
    expect(h.cubit.state.configOptions.single.currentValue, 'gpt-4');
  });

  test('without an active session nothing is sent', () async {
    final h = ShellHarness();
    await h.connect();

    await h.cubit.setSessionConfigOption('model', 'gpt-4');

    expect(h.sentAfterInitialize(), isEmpty);
    expect(h.cubit.state.isRespondingToConfigOption, isFalse);
  });
}
