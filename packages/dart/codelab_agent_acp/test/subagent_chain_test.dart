import 'package:codelab_acp_protocol/codelab_acp_protocol.dart' as acp;
import 'package:codelab_agent_acp/src/subagent_chain.dart';
import 'package:codelab_agent_core/codelab_agent_core.dart';
import 'package:test/test.dart';

/// Помощники цепочек вызовов потомков (задача 5.2 `[protocol]` change
/// `add-subagents-and-tasks`; design.md D47 Т2, Т3, D9).
void main() {
  const root = SessionId('sess_1');

  SubagentActivity activity(
    String subagent,
    String parent, {
    List<String> path = const [],
  }) => SubagentActivity(
    root,
    subagentId: subagent,
    parentToolCallId: parent,
    path: path,
    depth: path.length + 1,
    event: ToolCallFinished(
      const SessionId('child'),
      toolCallId: 'x',
      outcome: ToolOutcome.completed,
      content: const [],
    ),
  );

  group('SubagentChains', () {
    // Строка цепочки не разбирается: id провайдера может содержать `/`.
    test('a chain is built from the ancestor prefix, ids with a slash are '
        'kept whole', () {
      final chains = SubagentChains();

      expect(chains.prefixOf(activity('sub_c', 'call/1')), 'call/1');
      expect(
        chains.prefixOf(activity('sub_g', 'call_2', path: const ['sub_c'])),
        'call/1/call_2',
      );
      expect(
        chains.prefixOf(
          activity('sub_gg', 'call_3', path: const ['sub_c', 'sub_g']),
        ),
        'call/1/call_2/call_3',
      );
    });

    test('an unknown ancestor gives null and remembers nothing', () {
      final chains = SubagentChains();

      expect(
        chains.prefixOf(activity('sub_g', 'call_2', path: const ['sub_x'])),
        isNull,
      );
      expect(
        chains.prefixOf(activity('sub_h', 'call_4', path: const ['sub_g'])),
        isNull,
      );
    });

    test('clear forgets the prefixes', () {
      final chains = SubagentChains()..prefixOf(activity('sub_c', 'call_1'));

      chains.clear();

      expect(
        chains.prefixOf(activity('sub_g', 'call_2', path: const ['sub_c'])),
        isNull,
      );
    });
  });

  group('subagentToolCallsConsent', () {
    acp.ClientCapabilities caps(Object? codelab) =>
        acp.ClientCapabilities(meta: {'codelab': codelab});

    test('only an object with the integer version 1 is consent', () {
      expect(
        subagentToolCallsConsent(
          caps({
            'subagentToolCalls': {'version': 1},
          }),
        ),
        isTrue,
      );
      for (final version in <Object?>[2, '1', 1.5, null]) {
        expect(
          subagentToolCallsConsent(
            caps({
              'subagentToolCalls': {'version': version},
            }),
          ),
          isFalse,
          reason: 'version: $version',
        );
      }
      expect(
        subagentToolCallsConsent(caps({'subagentToolCalls': true})),
        isFalse,
      );
      expect(subagentToolCallsConsent(caps('x')), isFalse);
      expect(subagentToolCallsConsent(const acp.ClientCapabilities()), isFalse);
    });
  });
}
