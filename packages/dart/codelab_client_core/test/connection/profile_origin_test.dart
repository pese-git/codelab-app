// Origin адреса профиля для текстов хостов (AGENTS.md §10, §16; design.md
// change `add-app-settings-shell`, D10, D17).

import 'package:codelab_client_core/codelab_client_core.dart';
import 'package:test/test.dart';

void main() {
  group('profileOrigin', () {
    test('IPv4 with a port', () {
      expect(
        profileOrigin(Uri.parse('ws://127.0.0.1:8765/acp')),
        'ws://127.0.0.1:8765',
      );
    });

    test('IPv4 without a port', () {
      expect(profileOrigin(Uri.parse('ws://127.0.0.1/acp')), 'ws://127.0.0.1');
    });

    test('a host name', () {
      expect(
        profileOrigin(Uri.parse('wss://agent.example.com/acp')),
        'wss://agent.example.com',
      );
      expect(
        profileOrigin(Uri.parse('wss://agent.example.com:443')),
        'wss://agent.example.com:443',
      );
    });

    test('an IPv6 host is in square brackets', () {
      expect(
        profileOrigin(Uri.parse('ws://[::1]:8765/acp')),
        'ws://[::1]:8765',
      );
      expect(
        profileOrigin(Uri.parse('ws://[2001:db8::1]/acp')),
        'ws://[2001:db8::1]',
      );
    });

    test('userinfo, path, query and fragment are dropped', () {
      final origin = profileOrigin(
        Uri.parse(
          'ws://user:sk-test-leak-pass@h.example:9/p?t=sk-test-leak-q#frag',
        ),
      );

      expect(origin, 'ws://h.example:9');
    });
  });
}
