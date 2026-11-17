// Сводка WebSocket-профиля в app — origin из kit (`profileOrigin`): IPv6 в
// скобках, без userinfo, пути и query (AGENTS.md §10, §16; design.md change
// `add-app-settings-shell`, D10, D17).

import 'package:codelab_client_core/codelab_client_core.dart';
import 'package:codelab_desktop/features/settings/application/profile_view.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('the summary of a WebSocket profile is its origin, IPv6 in '
      'brackets', () {
    final profile = WebSocketProfile(
      id: 'p',
      label: 'P',
      uri: Uri.parse(
        'ws://user:sk-test-leak-pass@[::1]:8765/acp?t=sk-test-leak-q',
      ),
    );

    expect(profileSummary(profile), 'ws://[::1]:8765');
  });
}
