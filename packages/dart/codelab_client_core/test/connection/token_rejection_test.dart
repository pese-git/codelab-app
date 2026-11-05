// Отказ подключения из-за токена (HTTP 401/403 при рукопожатии): типизированное
// определение по цепочке причин и текст для хостов (spec acp-client-kit
// «Отказ подключения из-за токена»; design.md change `add-app-settings-shell`,
// D12).

import 'package:codelab_acp_transports/codelab_acp_transports.dart';
import 'package:codelab_client_acp/codelab_client_acp.dart';
import 'package:codelab_client_core/codelab_client_core.dart';
import 'package:test/test.dart';

import '../support/profile_fakes.dart';

/// Ошибка так, как её бросает `AcpClientApplication.connect` при отказе
/// рукопожатия: приложение → транспорт → отказ со статусом.
AcpClientApplicationException _rejected(int status) =>
    AcpClientApplicationException(
      'Failed to connect ACP transport.',
      cause: AcpTransportException(
        code: AcpTransportErrorCode.startFailed,
        message: 'Failed to connect',
        cause: AcpWebSocketHandshakeRejected(status),
      ),
    );

void main() {
  group('tokenRejectionStatus', () {
    test('401 and 403 in the cause chain are the rejection status', () {
      expect(tokenRejectionStatus(_rejected(401)), 401);
      expect(tokenRejectionStatus(_rejected(403)), 403);
    });

    test('a bare handshake rejection is found too', () {
      expect(
        tokenRejectionStatus(const AcpWebSocketHandshakeRejected(401)),
        401,
      );
    });

    test('other statuses and other failures are not a token rejection', () {
      expect(tokenRejectionStatus(_rejected(404)), isNull);
      expect(tokenRejectionStatus(_rejected(500)), isNull);
      expect(
        tokenRejectionStatus(
          const AcpClientApplicationException(
            'Failed to connect ACP transport.',
          ),
        ),
        isNull,
      );
      expect(tokenRejectionStatus(StateError('boom')), isNull);
    });
  });

  group('describeTokenRejection', () {
    test('with a token sent: the agent rejected the token', () {
      expect(
        describeTokenRejection(_rejected(401), tokenSent: true),
        'the agent rejected the token (HTTP 401)',
      );
      expect(
        describeTokenRejection(_rejected(403), tokenSent: true),
        'the agent rejected the token (HTTP 403)',
      );
    });

    test('without a token: the agent requires a token', () {
      expect(
        describeTokenRejection(_rejected(401), tokenSent: false),
        'the agent requires a token (HTTP 401)',
      );
    });

    test('anything else is null: the host keeps describeFailure', () {
      expect(describeTokenRejection(_rejected(404), tokenSent: true), isNull);
      expect(describeTokenRejection(StateError('x'), tokenSent: false), isNull);
    });
  });

  group('profileTokenSent', () {
    const secrets = ProfileSecretSource({'SET': 'v', 'EMPTY': ''});

    WebSocketProfile profile(String? ref) => WebSocketProfile(
      id: 'p',
      label: 'P',
      uri: Uri.parse('ws://h:1'),
      tokenRef: ref,
    );

    test('true only if the reference resolves to a non-empty value', () async {
      expect(await profileTokenSent(profile('env:SET'), secrets), isTrue);
      expect(await profileTokenSent(profile('env:EMPTY'), secrets), isFalse);
      expect(await profileTokenSent(profile('env:MISSING'), secrets), isFalse);
      expect(await profileTokenSent(profile('sk-not-a-ref'), secrets), isFalse);
    });

    test('no reference, no source and non-websocket profiles: false', () async {
      expect(await profileTokenSent(profile(null), secrets), isFalse);
      expect(await profileTokenSent(profile('env:SET'), null), isFalse);
      expect(
        await profileTokenSent(
          const StdioProfile(id: 's', label: 'S', command: 'x'),
          secrets,
        ),
        isFalse,
      );
    });

    test('a failing source is "not sent", not an exception', () async {
      expect(await profileTokenSent(profile('env:SET'), _Throwing()), isFalse);
    });
  });

  group('describeConnectFailureByToken', () {
    WebSocketProfile profile(String? ref) => WebSocketProfile(
      id: 'p',
      label: 'P',
      uri: Uri.parse('ws://h:1'),
      tokenRef: ref,
    );

    test(
      'an error without 401/403 is null and the source is not asked',
      () async {
        final source = _Counting('sk-test-leak-1');

        expect(
          await describeConnectFailureByToken(
            _rejected(500),
            profile('env:X'),
            source,
          ),
          isNull,
        );
        expect(
          await describeConnectFailureByToken(
            StateError('x'),
            profile('env:X'),
            source,
          ),
          isNull,
        );
        expect(source.reads, 0);
      },
    );

    test('a generic source: read decides rejected or required', () async {
      expect(
        await describeConnectFailureByToken(
          _rejected(401),
          profile('env:X'),
          _Counting('sk-test-leak-1'),
        ),
        'the agent rejected the token (HTTP 401)',
      );
      expect(
        await describeConnectFailureByToken(
          _rejected(403),
          profile('env:X'),
          _Counting(null),
        ),
        'the agent requires a token (HTTP 403)',
      );
    });

    test('ProfileSecretSource with secret: uses isSet, never read', () async {
      final stored = FakeProfileSecrets(
        values: {'codelab/profiles/p/token': 'sk-test-leak-2'},
      );
      final source = ProfileSecretSource(const {}, stored: stored);

      final set = await describeConnectFailureByToken(
        _rejected(401),
        profile('secret:codelab/profiles/p/token'),
        source,
      );
      final missing = await describeConnectFailureByToken(
        _rejected(401),
        profile('secret:codelab/profiles/other/token'),
        source,
      );

      expect(set, 'the agent rejected the token (HTTP 401)');
      expect(missing, 'the agent requires a token (HTTP 401)');
      expect(stored.readCalls, 0);
      expect(stored.isSetCalls, 2);
    });

    test(
      'ProfileSecretSource with env: looks at a non-empty variable',
      () async {
        const source = ProfileSecretSource({
          'SET': 'sk-test-leak-3',
          'EMPTY': '',
        });

        Future<String?> run(String ref) =>
            describeConnectFailureByToken(_rejected(401), profile(ref), source);

        expect(await run('env:SET'), contains('rejected'));
        expect(await run('env:EMPTY'), contains('requires'));
        expect(await run('env:MISSING'), contains('requires'));
        expect(await run('sk-test-leak-ref'), contains('requires'));
      },
    );

    test('no source or no reference: requires a token', () async {
      expect(
        await describeConnectFailureByToken(
          _rejected(401),
          profile('env:X'),
          null,
        ),
        contains('requires'),
      );
      expect(
        await describeConnectFailureByToken(
          _rejected(401),
          profile(null),
          const ProfileSecretSource({}),
        ),
        contains('requires'),
      );
    });
  });
}

/// Источник, считающий вызовы `read`: проверка «токен не читали».
final class _Counting implements SecretSource {
  _Counting(this.value);

  final String? value;
  var reads = 0;

  @override
  Future<String?> read(String ref) async {
    reads++;
    return value;
  }
}

final class _Throwing implements SecretSource {
  @override
  Future<String?> read(String ref) async => throw StateError('store down');
}
