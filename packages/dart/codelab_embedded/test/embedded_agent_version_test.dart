import 'dart:io';

import 'package:codelab_agent_core/testing.dart';
import 'package:codelab_embedded/codelab_embedded.dart';
import 'package:codelab_embedded/testing.dart';
import 'package:test/test.dart';

import 'support/acp_client.dart';

/// Версия встроенного агента для клиентов (embedded-agent «Версия встроенного
/// агента для клиентов»; design.md change `add-app-general-page`, D11).
///
/// Почему: страница «General» desktop показывает версию встроенного агента в
/// блоке «About» и не должна запускать агента ради одной строки; значение
/// берётся из константы основного бареля и обязано совпадать с тем, что агент
/// отдаёт клиенту в `agentInfo.version`.
void main() {
  late Directory temp;
  EmbeddedAgent? agent;
  TestAcpClient? client;

  setUp(() => temp = Directory.systemTemp.createTempSync('codelab_version_'));

  tearDown(() async {
    await client?.close();
    await agent?.dispose();
    agent = client = null;
    temp.deleteSync(recursive: true);
  });

  test('embeddedAgentVersion equals agentInfo.version of initialize', () async {
    final project = Directory('${temp.path}/project')..createSync();
    final opener = scriptedEmbeddedAgentOpener(
      llm: {'steps': <Object?>[]},
      codelabHome: '${temp.path}/home',
      logger: RecordingLogger(),
    );
    agent = await opener(cwd: project.path, hostProfile: 'embedded-cli');
    client = TestAcpClient(agent!.clientTransport);
    await client!.start();

    final result = await client!.initialize();

    final info = result['agentInfo']! as Map;
    expect(embeddedAgentVersion, isNotEmpty);
    expect(info['version'], embeddedAgentVersion);
  });
}
