// `ScenarioAgent.skipReason` для фикстур с `setup.mcp` (change
// `add-agent-mcp-client`, D15; spec cli-scenario-driver «Команда
// test-scenario»).
import 'package:codelab_acp_testing/codelab_acp_testing.dart';
import 'package:codelab_cli/codelab_cli.dart';
import 'package:codelab_client_core/codelab_client_core.dart';
import 'package:test/test.dart';

AcpFixture _fixture(String id) =>
    loadFixtureCorpus().firstWhere((f) => f.id == id);

ScenarioAgent _agent(String command, [List<String> args = const []]) =>
    ScenarioAgent(
      StdioProfile(id: 'a', label: 'a', command: command, args: args),
      environment: const {},
    );

void main() {
  final withMcp = _fixture('acp/mcp-stdio-tool-call');

  test('fixture setup.mcp is non-empty (guard for the tests below)', () {
    expect(withMcp.setup.mcp, isNotEmpty);
  });

  test('codelab-agent skips a fixture with setup.mcp', () {
    expect(
      _agent('codelab-agent', ['serve', '--stdio']).skipReason(withMcp),
      contains('setup.mcp cannot be passed to the agent process'),
    );
  });

  test('a third-party agent skips a fixture with setup.mcp', () {
    expect(
      _agent('some-agent').skipReason(withMcp),
      contains('setup.mcp cannot be passed to the agent process'),
    );
  });

  test('a replay agent taking {fixture} plays a fixture with setup.mcp', () {
    expect(_agent('replay', ['{fixture}']).skipReason(withMcp), isNull);
  });

  test('codelab-agent does not skip a fixture without setup.mcp', () {
    final plain = _fixture('acp/prompt-text-end-turn');
    expect(plain.setup.mcp, isEmpty);
    expect(_agent('codelab-agent').skipReason(plain), isNull);
  });
}
