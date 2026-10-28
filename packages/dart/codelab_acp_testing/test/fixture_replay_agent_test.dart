// Агент-повторитель фикстуры (tasks 8.1 change `add-codelab-cli`; spec
// acp-golden-fixtures «Агент-повторитель фикстуры»; design.md, D12).

import 'dart:convert';
import 'dart:io';

import 'package:codelab_acp_protocol/codelab_acp_protocol.dart';
import 'package:codelab_acp_testing/codelab_acp_testing.dart';
import 'package:codelab_acp_transports/codelab_acp_transports.dart';
import 'package:codelab_acp_transports/io.dart';
import 'package:test/test.dart';

import 'support/agent_process.dart';

/// Фикстуры, которые повторитель играет в памяти: роль `agent`, без
/// транспортного блока.
List<AcpFixture> _playable() => [
  for (final fixture in loadFixtureCorpus())
    if (fixture.roles.contains(FixtureRole.agent) &&
        fixture.setup.transport == null)
      fixture,
];

Future<AgentUnderTest> _replay(
  AcpTransport transport,
  AgentFixtureSetup setup,
) => FixtureReplayAgent.start(setup.fixture, transport, cwd: setup.cwd);

/// Копия [fixture] с изменённым первым кадром агента сценария.
AcpFixture _spoiled(AcpFixture fixture, Directory dir) {
  final json =
      jsonDecode(File(fixture.sourcePath!).readAsStringSync())
          as Map<String, Object?>;
  final frames = json['frames']! as List<Object?>;
  final frame = frames.cast<Map<String, Object?>>().firstWhere(
    (f) => f['dir'] == 'a2c' && f['frame'] != null && f['optional'] != true,
  );
  (frame['frame']! as Map<String, Object?>)['spoiled'] = true;
  final file = File('${dir.path}/${fixture.sourcePath!.split('/').last}')
    ..writeAsStringSync(jsonEncode(json));
  return loadFixtureFile(file.path);
}

void main() {
  test('the whole agent corpus passes against the replay agent', () async {
    final fixtures = _playable();
    expect(fixtures, isNotEmpty);

    for (final fixture in fixtures) {
      final result = await runAgentFixture(fixture, _replay);
      expect(result.skipped, isFalse, reason: fixture.id);
    }
  });

  test('a spoiled copy against the original replay fails with a '
      'diff', () async {
    final dir = await Directory.systemTemp.createTemp('replay_spoiled_');
    addTearDown(() => dir.delete(recursive: true));
    final original = loadFixtureCorpus().firstWhere(
      (f) => f.id == 'acp/prompt-text-end-turn',
    );
    final spoiled = _spoiled(original, dir);

    await expectLater(
      runAgentFixture(
        spoiled,
        (transport, setup) =>
            FixtureReplayAgent.start(original, transport, cwd: setup.cwd),
      ),
      throwsA(
        isA<AgentFixtureFailure>().having(
          (f) => f.toString(),
          'report',
          contains('spoiled'),
        ),
      ),
    );
  });

  test('a client frame the fixture does not expect is -32600', () async {
    final fixture = loadFixtureCorpus().firstWhere(
      (f) => f.id == 'acp/prompt-text-end-turn',
    );
    final link = InProcessAcpLink();
    final agent = await FixtureReplayAgent.start(
      fixture,
      link.agent,
      cwd: '/work',
    );
    addTearDown(agent.stop);
    await link.client.start();
    final reply = link.client.inbound.first;

    await link.client.send(
      const JsonRpcMessage.request(
        id: JsonRpcId.integer(42),
        method: 'session/unexpected',
      ),
    );

    final error = (await reply) as JsonRpcResponse;
    expect(error.id, const JsonRpcId.integer(42));
    expect(error.error?.code, -32600);
    expect(error.error?.message, contains('initialize'));
    await link.client.close();
  });

  test('runAgentFixtureOver with transportFixtures: false plays a fixture '
      'without a transport block and skips a transport one', () async {
    final corpus = loadFixtureCorpus();
    final plain = corpus.firstWhere((f) => f.id == 'acp/prompt-text-end-turn');
    final transport = corpus.firstWhere(
      (f) => f.id == 'acp/stdio-framing-large-line',
    );
    Future<AgentConnection> connect(AgentFixtureSetup setup) async {
      final link = InProcessAcpLink();
      return AgentConnection(
        client: link.client,
        agent: await _replay(link.agent, setup),
      );
    }

    final played = await runAgentFixtureOver(
      plain,
      connect,
      transportFixtures: false,
    );
    final skipped = await runAgentFixtureOver(
      transport,
      connect,
      transportFixtures: false,
    );

    expect(played.skipped, isFalse);
    expect(skipped.skipped, isTrue);
    expect(skipped.skipReason, contains('setup.transport'));
  });

  test('the process variant answers initialize over stdio', () async {
    final dir = await Directory.systemTemp.createTemp('replay_process_');
    addTearDown(() => dir.delete(recursive: true));
    final source = await writeFixtureReplayAgent(dir);
    final fixture = loadFixtureCorpus().firstWhere(
      (f) => f.id == 'acp/prompt-text-end-turn',
    );
    final packages = await fixtureReplayPackageConfig();
    final client = StdioAcpTransport(
      StdioAcpTransportConfig(
        command: dartExecutable(),
        args: ['--packages=$packages', source.path, fixture.sourcePath!],
        cwd: dir.path,
      ),
    );
    addTearDown(client.close);
    await client.start();
    final reply = client.inbound.first;

    // Тот же `initialize`, что шлёт агентский драйвер в handshake (§14.9).
    await client.send(
      const JsonRpcMessage.request(
        id: JsonRpcId.integer(0),
        method: 'initialize',
        params: {
          'protocolVersion': 1,
          'clientCapabilities': {
            'fs': {'readTextFile': true, 'writeTextFile': true},
            'terminal': true,
          },
          'clientInfo': {'name': 'fixture-client', 'version': '0.0.0'},
        },
      ),
    );

    final response =
        (await reply.timeout(const Duration(seconds: 60))) as JsonRpcResponse;
    expect(response.result, containsPair('protocolVersion', 1));
  });
}
