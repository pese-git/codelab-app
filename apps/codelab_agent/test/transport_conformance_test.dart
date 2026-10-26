import 'package:codelab_acp_testing/codelab_acp_testing.dart';
import 'package:test/test.dart';

import 'support/transport_starter.dart';

/// Транспортные фикстуры корпуса против процесса бинаря (задача 4.8;
/// acp-golden-fixtures «Транспортный драйвер фикстур»; design.md change
/// `add-codelab-agent-binary`, D8): кадры идут через настоящий stdio или
/// WebSocket, сравнение — тем же алгоритмом, что у агентского драйвера.
void main() {
  final fixtures = [
    for (final fixture in loadFixtureCorpus())
      if (fixture.setup.transport != null) fixture,
  ];

  test('the corpus has the transport fixtures of stage 4', () {
    expect(fixtures.map((f) => f.id).toSet(), {
      'acp/stdio-framing-large-line',
      'acp/ws-auth-bearer-required',
    });
  });

  for (final fixture in fixtures) {
    test(fixture.id, () async {
      final result = await runAgentFixtureOver(
        fixture,
        connectAgentProcess,
        frameTimeout: const Duration(seconds: 30),
      );
      expect(result.skipped, isFalse);
    }, timeout: const Timeout(Duration(minutes: 2)));
  }
}
