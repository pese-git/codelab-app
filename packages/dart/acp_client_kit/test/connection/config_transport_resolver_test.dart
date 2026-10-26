// Тесты `ConfigTransportResolver` и `InMemorySecretSource` (tasks 2.3;
// spec acp-client-kit «Профили и резолверы транспорта»: токен — ссылкой,
// значение даёт `SecretSource`).

import 'package:acp_client_kit/acp_client_kit.dart';
import 'package:acp_testing/acp_testing.dart';
import 'package:acp_transports/acp_transports.dart';
import 'package:test/test.dart';

void main() {
  test('a stdio profile becomes a stdio config; cwd is the project directory '
      'only when the profile runs in it', () async {
    final configs = <StdioAcpTransportConfig>[];
    final resolver = ConfigTransportResolver(
      stdio: (config) {
        configs.add(config);
        return FakeAcpTransport();
      },
    );
    const profile = StdioProfile(
      id: 'agent',
      label: 'Agent',
      command: 'codelab-agent',
      args: ['serve', '--stdio'],
      env: {'LOG': 'debug'},
    );

    expect(resolver.supports(profile), isTrue);
    await resolver.open(profile, projectDirectory: '/work');
    await resolver.open(
      profile.copyWith(runInProjectDirectory: true),
      projectDirectory: '/work',
    );

    expect(
      configs.first,
      const StdioAcpTransportConfig(
        command: 'codelab-agent',
        args: ['serve', '--stdio'],
        env: {'LOG': 'debug'},
      ),
    );
    expect(configs.last.cwd, '/work');
  });

  test('a WebSocket profile reads its token from the secret source by '
      'reference', () async {
    final configs = <WebSocketAcpTransportConfig>[];
    final secrets = InMemorySecretSource()..write('ws-token', 's3cr3t');
    final resolver = ConfigTransportResolver(
      webSocket: (config) {
        configs.add(config);
        return FakeAcpTransport();
      },
      secrets: secrets,
    );
    final profile = WebSocketProfile(
      id: 'remote',
      label: 'Remote',
      uri: Uri.parse('wss://agent.example.test/acp'),
      tokenRef: 'ws-token',
    );

    await resolver.open(profile, projectDirectory: '/work');
    await resolver.open(
      profile.copyWith(tokenRef: null),
      projectDirectory: '/work',
    );

    expect(configs.first.uri, Uri.parse('wss://agent.example.test/acp'));
    expect(configs.first.token, 's3cr3t');
    expect(configs.last.token, isNull);
  });

  test('a removed secret resolves to no token', () async {
    final secrets = InMemorySecretSource()
      ..write('ws-token', 's3cr3t')
      ..write('ws-token', null);

    expect(await secrets.read('ws-token'), isNull);
  });

  test('a profile kind without a factory is not supported', () {
    final resolver = ConfigTransportResolver(stdio: (_) => FakeAcpTransport());

    expect(
      resolver.supports(
        WebSocketProfile(
          id: 'remote',
          label: 'Remote',
          uri: Uri.parse('wss://agent.example.test/acp'),
        ),
      ),
      isFalse,
    );
  });
}
