import 'package:acp_protocol/acp_protocol.dart';
import 'package:acp_testing/acp_testing.dart';
import 'package:test/test.dart';

import 'support/corpus_invariants.dart';

/// FIX-2, агентская часть (задача 9.3; design.md change
/// `add-dart-agent-acp-server`, D8): каждый метод `acp_method_codec.dart`,
/// включая запросы агента `fs/*`, `terminal/*` и
/// `session/request_permission`, и каждый вид `sessionUpdate` встречается
/// хотя бы в одной фикстуре с ролью `agent`, кроме [agentPendingCoverage].
///
/// Список только сокращается: покрытый элемент обязан из него уйти.
const agentPendingCoverage = <String>{};

void main() {
  final agentFixtures = loadFixtureCorpus().where(
    (f) => f.roles.contains(FixtureRole.agent),
  );
  final covered = coveredProtocolElements(agentFixtures);
  final methods = acpMethodRegistry.keys.toSet();
  final kinds = protocolSessionUpdateKinds();

  test('agentPendingCoverage names only protocol elements', () {
    expect(agentPendingCoverage.difference(methods.union(kinds)), isEmpty);
  });

  test('every method is covered by an agent fixture or pending', () {
    expect(
      methods.difference(covered.methods).difference(agentPendingCoverage),
      isEmpty,
      reason:
          'add a fixture with the agent role or an agentPendingCoverage '
          'entry',
    );
  });

  test(
    'every sessionUpdate kind is covered by an agent fixture or pending',
    () {
      expect(
        kinds
            .difference(covered.sessionUpdates)
            .difference(agentPendingCoverage),
        isEmpty,
        reason:
            'add a fixture with the agent role or an agentPendingCoverage '
            'entry',
      );
    },
  );

  test('a covered element leaves agentPendingCoverage', () {
    expect(
      agentPendingCoverage.intersection(
        covered.methods.union(covered.sessionUpdates),
      ),
      isEmpty,
    );
  });
}
