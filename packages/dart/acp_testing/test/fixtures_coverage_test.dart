import 'package:acp_protocol/acp_protocol.dart';
import 'package:acp_testing/acp_testing.dart';
import 'package:test/test.dart';

import 'support/corpus_invariants.dart';

/// FIX-2, client part (design.md D5): every `sessionUpdate` kind of
/// `acp_protocol` and every method of `acp_method_codec.dart` occurs in at
/// least one fixture with the `client` role — except the elements still
/// waiting for their fixtures. The agent part is checked from task 4.8.
///
/// The list only shrinks: an element covered by a fixture must leave it.
const pendingCoverage = {
  // Stage 4: acp/session-load-replay, acp/session-list-cwd-filter.
  'session/load',
  'session/list',
  // Stage 4: acp/session-load-replay (replay of user words).
  'user_message_chunk',
  // Stage 4: acp/prompt-thought-chunk.
  'agent_thought_chunk',
  // Stage 4: acp/set-mode-updates-current-mode.
  'current_mode_update',
  // Stage 4: acp/config-effort-option and the agent-side option changes.
  'config_option_update',
  // Клиент codelab-app метод не вызывает: режимы — через configOptions
  // (§13.6). Агентскую сторону покрывают фикстуры acp/set-mode-*.
  'session/set_mode',
};

void main() {
  final clientFixtures = loadFixtureCorpus().where(
    (f) => f.roles.contains(FixtureRole.client),
  );
  final covered = coveredProtocolElements(clientFixtures);
  final methods = acpMethodRegistry.keys.toSet();
  final kinds = protocolSessionUpdateKinds();

  test('the protocol lists are read', () {
    expect(methods, contains(sessionPromptMethod));
    expect(kinds, containsAll(['agent_message_chunk', 'tool_call', 'plan']));
  });

  test('pendingCoverage names only protocol elements', () {
    expect(pendingCoverage.difference(methods.union(kinds)), isEmpty);
  });

  test('every method is covered by a client fixture or pending', () {
    expect(
      methods.difference(covered.methods).difference(pendingCoverage),
      isEmpty,
      reason: 'add a fixture with the client role or a pendingCoverage entry',
    );
  });

  test(
    'every sessionUpdate kind is covered by a client fixture or pending',
    () {
      expect(
        kinds.difference(covered.sessionUpdates).difference(pendingCoverage),
        isEmpty,
        reason: 'add a fixture with the client role or a pendingCoverage entry',
      );
    },
  );

  test('a covered element leaves pendingCoverage', () {
    expect(
      pendingCoverage.intersection(
        covered.methods.union(covered.sessionUpdates),
      ),
      isEmpty,
      reason: 'the element is covered now: remove it from pendingCoverage',
    );
  });
}
