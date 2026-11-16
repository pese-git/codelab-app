// Headless: строки статуса usage нет (задача 3.7 change `add-usage-extension`;
// spec codelab-cli «Строка статуса после хода в REPL», сценарий «Вывод в
// pipe»; spec cli-headless «Вывод headless»; design.md, D12, D23 Т5).
//
// Почему: строка после хода — часть REPL (`ReplSession.onOutcome`); stdout
// headless — ответ байт в байт (H-01), и `─ ask · a · ctx N%` в нём сломало
// бы конвейеры. Тест держит это при любом будущем переносе вывода в раннер.

import 'package:codelab_acp_protocol/codelab_acp_protocol.dart';
import 'package:codelab_cli/codelab_cli.dart';
import 'package:test/test.dart';

import '../support/fake_agent.dart';

const _usageCapabilities = AgentCapabilities(
  meta: {
    'codelab': {
      'usage': {'version': 1},
    },
  },
);

const _options = [
  {
    'type': 'select',
    'id': 'mode',
    'name': 'Mode',
    'category': 'mode',
    'currentValue': 'ask',
    'options': [
      {'value': 'ask', 'name': 'Ask'},
    ],
  },
  {
    'type': 'select',
    'id': 'model',
    'name': 'Model',
    'category': 'model',
    'currentValue': 'a',
    'options': [
      {'value': 'a', 'name': 'Model A'},
    ],
  },
];

Map<String, Object?> _usage(int seq, String trigger) => {
  'sessionId': 's1',
  'seq': seq,
  'trigger': trigger,
  'turnId': 'turn-1',
  'turn': {
    'steps': 1,
    'tokens': {'input': 18000, 'output': 500, 'cacheRead': 0, 'cacheWrite': 0},
    'cost': '0.04',
  },
  'session': {
    'turns': 1,
    'steps': 1,
    'tokens': {'input': 18000, 'output': 500, 'cacheRead': 0, 'cacheWrite': 0},
    'cost': '0.04',
  },
  'currency': 'USD',
  'context': {'used': 18000, 'size': 200000},
};

void main() {
  late FakeAgent agent;
  late StringBuffer stdout;
  late StringBuffer stderr;

  setUp(() {
    agent = FakeAgent(capabilities: _usageCapabilities);
    stdout = StringBuffer();
    stderr = StringBuffer();
  });
  tearDown(() => agent.dispose());

  test('`-p` с usage: stdout — только ответ, строки статуса нет', () async {
    final outcome = HeadlessRunner(
      workspace: agent.workspace,
      stdout: stdout,
      stderr: stderr,
      tokenSource: fakeTokenSource,
    ).run(profile: FakeAgent.profile, cwd: '/work', prompt: 'hello');
    await agent.acceptNewSession('s1', configOptions: _options);
    final prompt = await agent.next(sessionPromptMethod);

    agent.chunk('s1', 'answer');
    for (final (seq, trigger) in [(1, 'step'), (2, 'turn')]) {
      agent.transport.emitInbound(
        JsonRpcMessage.notification(
          method: '_codelab/session/usage',
          params: _usage(seq, trigger),
        ),
      );
    }
    agent.respond(prompt, {'stopReason': 'end_turn'});

    expect(await outcome, isA<TurnCompleted>());
    expect(stdout.toString(), 'answer\n');
    for (final output in [stdout.toString(), stderr.toString()]) {
      expect(output, isNot(contains('─')));
      expect(output, isNot(contains('ctx ')));
    }
  });
}
