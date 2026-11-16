// `ReplSession.onOutcome(PromptQueued)`: строки статуса нет (задача 3.7
// change `add-usage-extension`; spec codelab-cli «Промпт в очередь»; design.md,
// D12, Q18 (а)).
//
// Почему отдельный модульный тест: сквозной тест REPL ловит печать на
// уровне вывода, а здесь проверяется сама ветка `outcome is PromptQueued`:
// исход «поставлен в очередь» — не конец хода, и строка с итогом хода до
// него была бы неверной.

import 'package:codelab_acp_protocol/codelab_acp_protocol.dart';
import 'package:codelab_cli/codelab_cli.dart';
import 'package:codelab_client_acp/codelab_client_acp.dart';
import 'package:codelab_client_core/codelab_client_core.dart';
import 'package:test/test.dart';

import '../support/fake_agent.dart';
import '../support/fake_terminal.dart';

const _usageCapabilities = AgentCapabilities(
  meta: {
    'codelab': {
      'usage': {'version': 1},
    },
  },
);

void main() {
  late FakeAgent agent;

  tearDown(() => agent.dispose());

  test(
    'PromptQueued не печатает строку статуса, PromptCompleted — печатает',
    () async {
      agent = FakeAgent(capabilities: _usageCapabilities);
      final opening = () async {
        await agent.workspace.connect(
          FakeAgent.profile,
          projectDirectory: '/work',
        );
        return openCliSession(agent.workspace, '/work');
      }();
      await agent.acceptNewSession(
        's1',
        configOptions: const [
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
        ],
      );
      final handle = await opening;

      final out = StringBuffer();
      final session = ReplSession(
        handle: handle,
        terminal: FakeTerminal(),
        renderer: TerminalRenderer(
          surface: OutputSurface.plain,
          out: out,
          err: StringBuffer(),
        ),
        editor: LineEditor(History(const [])),
      );

      session.onOutcome(
        PromptQueued(handle.id, const QueuedPrompt(id: 'q1', text: 'x')),
      );
      expect(out.toString(), isEmpty);

      // Контроль теста: исход завершённого хода строку печатает (иначе тест
      // прошёл бы и при пустой строке статуса).
      session.onOutcome(
        PromptCompleted(
          handle.id,
          PromptTurn(
            id: const PromptTurnId('t1'),
            sessionId: handle.id,
            prompt: const [],
            stopReason: StopReason.endTurn,
          ),
        ),
      );
      expect('─ '.allMatches(out.toString()), hasLength(1));
      expect(out.toString(), contains('─ ask'));
    },
  );
}
