// Проверка профиля без сессии (task 3.2 change `add-app-settings-shell`;
// spec acp-client-kit «Проверка профиля без сессии»; SETUP-20; design.md,
// D12). Транспорт — FakeAcpTransport, порядок событий задаётся явно, без
// Future.delayed.

import 'package:codelab_acp_protocol/codelab_acp_protocol.dart';
import 'package:codelab_acp_testing/codelab_acp_testing.dart';
import 'package:codelab_acp_transports/codelab_acp_transports.dart';
import 'package:codelab_client_core/codelab_client_core.dart';
import 'package:test/test.dart';

import '../support/profile_fakes.dart';

const _stdio = StdioProfile(id: 'dev', label: 'Dev', command: 'agent');

ProfileProbe _probeOver(
  FakeAcpTransport transport, {
  ProbeFailureClassifier? classifier,
}) => ProfileProbe(
  resolvers: [ConfigTransportResolver(stdio: (config) => transport)],
  classifier: classifier,
);

Iterable<String> _methods(FakeAcpTransport transport) => [
  for (final message in transport.sentMessages)
    if (message is JsonRpcRequest) message.method,
];

void main() {
  test('a successful initialize is Reachable; only initialize was sent, '
      'client capabilities are false, the transport is closed', () async {
    final transport = FakeAcpTransport()
      ..initializeAgentInfo = const Implementation(
        name: 'scripted',
        version: '1.2.3',
      );

    final outcome = await _probeOver(transport).probe(_stdio);

    expect(outcome, isA<Reachable>());
    final reachable = outcome! as Reachable;
    expect(reachable.agentName, 'scripted');
    expect(reachable.agentVersion, '1.2.3');
    expect(reachable.latency, isA<Duration>());
    expect(_methods(transport), ['initialize']);
    final request = transport.sentMessages.single as JsonRpcRequest;
    final params = request.params! as Map<String, Object?>;
    final capabilities = params['clientCapabilities']! as Map<String, Object?>;
    expect(capabilities['terminal'], isFalse);
    expect(
      (capabilities['fs']! as Map<String, Object?>).values,
      everyElement(false),
    );
    expect(transport.state, AcpTransportState.closed);
  });

  test('a silent agent gives TimedOut and the transport is closed', () async {
    final transport = FakeAcpTransport()..autoRespondToInitialize = false;

    final outcome = await _probeOver(
      transport,
    ).probe(_stdio, timeout: const Duration(milliseconds: 1));

    expect(outcome, isA<TimedOut>());
    expect(transport.state, AcpTransportState.closed);
    expect(_methods(transport), ['initialize']);
  });

  test('cancel before the answer closes the transport and gives no '
      'outcome', () async {
    final transport = FakeAcpTransport()..autoRespondToInitialize = false;
    final cancellation = ProbeCancellation();

    final future = _probeOver(
      transport,
    ).probe(_stdio, cancellation: cancellation);
    // Порядок задан явно: отменяем только после того, как initialize ушёл.
    await transport.sent.first;
    cancellation.cancel();

    expect(await future, isNull);
    expect(transport.state, AcpTransportState.closed);
    expect(_methods(transport), ['initialize']);
  });

  test('a probe cancelled before start opens no transport', () async {
    var opened = 0;
    final probe = ProfileProbe(
      resolvers: [
        ConfigTransportResolver(
          stdio: (config) {
            opened++;
            return FakeAcpTransport();
          },
        ),
      ],
    );
    final cancellation = ProbeCancellation()..cancel();

    expect(await probe.probe(_stdio, cancellation: cancellation), isNull);
    expect(opened, 0);
  });

  test('an incompatible protocol version is NotAcp', () async {
    final transport = FakeAcpTransport()
      ..initializeProtocolVersion = const ProtocolVersion(99);

    final outcome = await _probeOver(transport).probe(_stdio);

    expect(outcome, isA<NotAcp>());
    expect(transport.state, AcpTransportState.closed);
  });

  test('a profile without a resolver is Unsupported', () async {
    final probe = ProfileProbe(resolvers: const []);

    expect(await probe.probe(_stdio), isA<Unsupported>());
    expect(
      await probe.probe(
        const EmbeddedProfile(id: 'embedded', label: 'E', hostProfile: 'h'),
      ),
      isA<Unsupported>(),
    );
  });

  test('the env: token reference reaches the transport configuration, the '
      'value never reaches the outcome', () async {
    const leak = 'sk-test-leak-0123456789';
    WebSocketAcpTransportConfig? seen;
    final transport = FakeAcpTransport();
    final probe = ProfileProbe(
      resolvers: [
        ConfigTransportResolver(
          webSocket: (config) {
            seen = config;
            return transport;
          },
          secrets: const ProfileSecretSource({'DEVBOX_TOKEN': leak}),
        ),
      ],
    );

    final outcome = await probe.probe(
      WebSocketProfile(
        id: 'devbox',
        label: 'Devbox',
        uri: Uri.parse('wss://devbox:7420'),
        tokenRef: 'env:DEVBOX_TOKEN',
      ),
    );

    expect(seen?.token, leak);
    expect(outcome.toString(), isNot(contains(leak)));
  });

  group('a new token from memory (add-provider-setup-ui, D13)', () {
    const leak = 'sk-test-leak-0123456789';
    final profile = WebSocketProfile(
      id: 'devbox',
      label: 'Devbox',
      uri: Uri.parse('wss://devbox:7420'),
      tokenRef: 'secret:codelab/profiles/devbox/token',
    );

    test('the new token reaches the transport; nothing is stored and the '
        'outcome does not carry it', () async {
      final stored = FakeProfileSecrets();
      WebSocketAcpTransportConfig? seen;
      final probe = ProfileProbe(
        resolvers: [
          ConfigTransportResolver(
            webSocket: (config) {
              seen = config;
              return FakeAcpTransport();
            },
            secrets: ProfileSecretSource(const {}, stored: stored),
          ),
        ],
      );

      final outcome = await probe.probe(profile, token: const SecretText(leak));

      expect(outcome, isA<Reachable>());
      expect(seen?.token, leak);
      expect(stored.log.entries, isEmpty);
      expect(stored.values, isEmpty);
      expect(outcome.toString(), isNot(contains(leak)));
    });

    test('the new token also works for a profile without a token '
        'reference', () async {
      WebSocketAcpTransportConfig? seen;
      final probe = ProfileProbe(
        resolvers: [
          ConfigTransportResolver(
            webSocket: (config) {
              seen = config;
              return FakeAcpTransport();
            },
          ),
        ],
      );

      await probe.probe(
        WebSocketProfile(id: 'd', label: 'D', uri: Uri.parse('ws://localhost')),
        token: const SecretText('t'),
      );

      expect(seen?.token, 't');
    });

    test('Use stored secret reads the stored value with the same source '
        'as connect', () async {
      WebSocketAcpTransportConfig? seen;
      final probe = ProfileProbe(
        resolvers: [
          ConfigTransportResolver(
            webSocket: (config) {
              seen = config;
              return FakeAcpTransport();
            },
            secrets: ProfileSecretSource(
              const {},
              stored: FakeProfileSecrets(
                values: {'codelab/profiles/devbox/token': 'stored'},
              ),
            ),
          ),
        ],
      );

      await probe.probe(profile);

      expect(seen?.token, 'stored');
    });

    test('an empty new token is refused explicitly: no transport, and the '
        'store is not read for a secret reference', () async {
      var opened = 0;
      final stored = FakeProfileSecrets(
        values: {'codelab/profiles/devbox/token': 'stored'},
      );
      final probe = ProfileProbe(
        resolvers: [
          ConfigTransportResolver(
            webSocket: (config) {
              opened++;
              return FakeAcpTransport();
            },
            secrets: ProfileSecretSource(const {}, stored: stored),
          ),
        ],
      );

      final outcome = await probe.probe(profile, token: const SecretText(''));

      expect(outcome, isA<Unsupported>());
      expect(opened, 0);
      expect(stored.log.entries, isEmpty);
    });

    test('a resolver that cannot take a one-off token gives Unsupported '
        'instead of probing without it', () async {
      final probe = ProfileProbe(resolvers: [_PlainResolver()]);

      expect(
        await probe.probe(profile, token: const SecretText('t')),
        isA<Unsupported>(),
      );
    });
  });

  group('failures', () {
    ProfileProbe throwingOpen(Object error, {ProbeFailureClassifier? c}) =>
        ProfileProbe(
          resolvers: [ConfigTransportResolver(stdio: (config) => throw error)],
          classifier: c,
        );

    test(
      'an unclassified error is Unreachable with a redacted message',
      () async {
        const leak = 'sk-test-leak-0123456789';
        final outcome = await throwingOpen(
          StateError('cannot connect, Authorization: Bearer $leak'),
        ).probe(_stdio);

        expect(outcome, isA<Unreachable>());
        final unreachable = outcome! as Unreachable;
        expect(unreachable.message, isNot(contains(leak)));
        // Без типизированной причины откат — unknown (D12): UI не гадает.
        expect(unreachable.reason, UnreachableReason.unknown);
        expect(unreachable.statusCode, isNull);
      },
    );

    test(
      'the host classifier decides CommandNotFound and sees the error',
      () async {
        final error = StateError('boom');
        Object? classified;
        final outcome = await throwingOpen(
          error,
          c: (e) {
            classified = e;
            return const CommandNotFound();
          },
        ).probe(_stdio);

        expect(outcome, isA<CommandNotFound>());
        expect(classified, same(error));
      },
    );

    test('a classifier returning null falls back to Unreachable', () async {
      final outcome = await throwingOpen(
        StateError('x'),
        c: (e) => null,
      ).probe(_stdio);

      expect(outcome, isA<Unreachable>());
      expect((outcome! as Unreachable).reason, UnreachableReason.unknown);
    });

    test('Unreachable defaults to unknown and carries a typed reason', () {
      expect(const Unreachable('m').reason, UnreachableReason.unknown);
      expect(const Unreachable('m').statusCode, isNull);
      const refused = Unreachable(
        'm',
        reason: UnreachableReason.connectionRefused,
      );
      expect(refused.reason, UnreachableReason.connectionRefused);
      const http = Unreachable(
        'm',
        reason: UnreachableReason.httpStatus,
        statusCode: 502,
      );
      expect(http.statusCode, 502);
    });

    for (final reason in UnreachableReason.values) {
      test(
        'a classifier Unreachable($reason) passes through unchanged',
        () async {
          final outcome = await throwingOpen(
            StateError('x'),
            c: (e) => Unreachable(
              'diag',
              reason: reason,
              statusCode: reason == UnreachableReason.httpStatus ? 500 : null,
            ),
          ).probe(_stdio);

          final unreachable = outcome! as Unreachable;
          expect(unreachable.reason, reason);
          expect(
            unreachable.statusCode,
            reason == UnreachableReason.httpStatus ? 500 : null,
          );
        },
      );
    }
  });
}

/// Резолвер без поддержки одноразового источника секретов.
final class _PlainResolver implements TransportResolver {
  @override
  bool supports(ConnectionProfile profile) => true;

  @override
  Future<AcpTransport> open(
    ConnectionProfile profile, {
    required String projectDirectory,
  }) async => FakeAcpTransport();
}
