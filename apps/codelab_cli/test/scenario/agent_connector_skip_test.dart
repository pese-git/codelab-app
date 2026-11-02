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

  group('embedded agent', () {
    const embedded = EmbeddedProfile(
      id: 'embedded',
      label: 'Embedded agent',
      hostProfile: 'embedded-cli',
    );
    final agent = ScenarioAgent(embedded, environment: const {});

    test('plays a plain fixture with an llm block', () {
      expect(agent.skipReason(_fixture('acp/prompt-text-end-turn')), isNull);
    });

    test('skips setup.mcp', () {
      expect(
        agent.skipReason(withMcp),
        contains('setup.mcp cannot be passed to the agent process'),
      );
    });

    test('skips setup.sessions, setup.config, setup.web and a foreign host '
        'profile with the reason', () {
      final corpus = loadFixtureCorpus();
      var checked = 0;
      for (final (label, test) in <(String, bool Function(AcpFixture))>[
        ('setup.sessions', (f) => f.setup.sessions.isNotEmpty),
        ('setup.config', (f) => f.setup.config != null),
        ('setup.web', (f) => f.setup.web != null),
        (
          'setup.profile',
          (f) =>
              f.setup.profile != null &&
              !const {'agent-serve', 'embedded-cli'}.contains(f.setup.profile),
        ),
      ]) {
        final fixture = corpus
            .where((f) => test(f) && f.setup.mcp.isEmpty)
            .firstOrNull;
        // Не каждый вид входа есть в корпусе сегодня (`setup.web` — нет):
        // проверяется то, что есть, но не меньше двух видов.
        if (fixture == null) {
          continue;
        }
        checked++;

        expect(
          agent.skipReason(fixture),
          allOf(isNotNull, contains('embedded'), contains(label)),
          reason: fixture.id,
        );
      }
      expect(checked, greaterThanOrEqualTo(2));
    });

    test('is not the codelab-agent binary and takes no {fixture}', () {
      expect(agent.isCodelabAgent, isFalse);
      expect(agent.takesFixture, isFalse);
    });
  });
}
