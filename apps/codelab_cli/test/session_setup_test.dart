// Текст причины сбоя старта агента и описание профиля в нём (spec codelab-cli
// «Отказ подключения из-за токена», «Аргументы stdio-профиля в выводе CLI»;
// AGENTS.md §10, §16).

import 'package:codelab_cli/codelab_cli.dart';
import 'package:codelab_client_core/codelab_client_core.dart';
import 'package:test/test.dart';

import 'support/fake_agent.dart';

/// Источник, считающий `read`: «токен не читали».
final class _CountingSource implements SecretSource {
  var reads = 0;

  @override
  Future<String?> read(String ref) async {
    reads++;
    return fakeTokenMarker;
  }
}

void main() {
  group('describeStartFailure', () {
    test('401 with a token: the agent rejected the token', () async {
      expect(
        await describeStartFailure(
          handshakeRejected(401),
          wsProfile(),
          tokenSource: fakeTokenSource,
        ),
        'the agent rejected the token (HTTP 401).',
      );
    });

    test('403 without a token: the agent requires a token', () async {
      expect(
        await describeStartFailure(
          handshakeRejected(403),
          wsProfile(withToken: false),
          tokenSource: fakeTokenSource,
        ),
        'the agent requires a token (HTTP 403).',
      );
    });

    test('another error keeps describeFailure and never reads the '
        'token', () async {
      final source = _CountingSource();
      final error = handshakeRejected(500);

      expect(
        await describeStartFailure(error, wsProfile(), tokenSource: source),
        describeFailure(error),
      );
      expect(
        await describeStartFailure(
          StateError('boom'),
          wsProfile(),
          tokenSource: source,
        ),
        describeFailure(StateError('boom')),
      );
      expect(source.reads, 0);
    });
  });

  group('describeProfile', () {
    test('a WebSocket profile is its origin: no userinfo, path or '
        'query', () {
      final text = describeProfile(wsProfile());

      expect(text, 'ws://127.0.0.1:9');
      for (final leak in fakeUrlLeaks) {
        expect(text, isNot(contains(leak)));
      }
    });

    test('an IPv6 address keeps its square brackets', () {
      final profile = WebSocketProfile(
        id: 'x',
        label: 'X',
        uri: Uri.parse('ws://[::1]:8765/acp'),
      );

      expect(describeProfile(profile), 'ws://[::1]:8765');
    });

    test('an address without a port has no port in the origin', () {
      final profile = WebSocketProfile(
        id: 'x',
        label: 'X',
        uri: Uri.parse('wss://host.example/acp?t=sk-test-leak-9'),
      );

      expect(describeProfile(profile), 'wss://host.example');
    });
  });

  // Значения аргументов stdio-профиля не печатаются (design.md change
  // `redact-cli-stdio-profile-args`, D1, D2).
  group('describeProfile of a stdio profile', () {
    const marker = 'sk-test-leak-0123456789';

    StdioProfile stdio(String command, [List<String> args = const []]) =>
        StdioProfile(id: 'p', label: 'P', command: command, args: args);

    test('without arguments it is the quoted command', () {
      expect(describeProfile(stdio('codelab-agent')), '"codelab-agent"');
    });

    test('one argument is "1 argument"', () {
      expect(
        describeProfile(stdio('codelab-agent', ['--stdio'])),
        '"codelab-agent" with 1 argument',
      );
    });

    test('argument values never reach the description', () {
      final text = describeProfile(
        stdio('my-agent', ['--api-key', marker, marker]),
      );

      expect(text, '"my-agent" with 3 arguments');
      expect(text, isNot(contains(marker)));
      expect(text, isNot(contains('--api-key')));
    });
  });
}
