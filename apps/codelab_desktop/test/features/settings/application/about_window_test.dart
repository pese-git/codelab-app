// Снимок окна для «Copy diagnostics» (ревью change `add-app-general-page`:
// правило «вид подключения, доступ, состояние» вынесено из composition root;
// spec app-settings «Диагностика для отчёта без секретов и путей»,
// design.md D12).
//
// Функция чистая: профиль и состояние подключения приходят аргументами, а
// доступ к настройкам агента решает мост `resolveSettingsAccess` (SETUP-2,
// SETUP-8) — app его правил не повторяет.

import 'package:codelab_client_acp/codelab_client_acp.dart'
    show ConnectionFailureReason;
import 'package:codelab_client_core/codelab_client_core.dart';
import 'package:codelab_desktop/core/platform/app_language_preferences.dart';
import 'package:codelab_desktop/features/settings/application/about_diagnostics.dart';
import 'package:codelab_desktop/features/settings/application/about_ports.dart'
    show AboutWindow;
import 'package:codelab_desktop/features/settings/application/about_window.dart';
import 'package:codelab_desktop/features/settings/application/embedded_profile.dart';
import 'package:flutter_test/flutter_test.dart';

const _own = ConnectionProfile.stdio(
  id: 'dev',
  label: 'Dev',
  command: '/opt/bin/codelab-agent',
  args: ['serve', '--stdio'],
);

const _foreign = ConnectionProfile.stdio(
  id: 'other',
  label: 'Other',
  command: 'python',
  args: ['-m', 'other_agent'],
);

final _remote = ConnectionProfile.webSocket(
  id: 'devbox',
  label: 'Devbox',
  uri: Uri.parse('wss://devbox:7420/acp?t=sk-test-leak-0123456789'),
);

AboutWindow _window(
  ConnectionProfile profile, {
  ConnectionView connection = const ConnectionView.connected(),
  Map<String, String> environment = const {},
}) => aboutWindowOf(
  profile: profile,
  connection: connection,
  codelabHome: '/home/u/.codelab',
  environment: environment,
);

void main() {
  group('вид подключения и доступ по профилю', () {
    test('встроенный агент: embedded, настройки правятся', () {
      final w = _window(embeddedConnectionProfile);

      expect(w.connection, DiagnosticsConnection.embedded);
      expect(w.access, DiagnosticsAccess.editable);
    });

    test('свой stdio-агент: stdio, настройки правятся', () {
      final w = _window(_own);

      expect(w.connection, DiagnosticsConnection.stdio);
      expect(w.access, DiagnosticsAccess.editable);
    });

    test('чужой stdio-агент: stdio, настройки не наши', () {
      final w = _window(_foreign);

      expect(w.connection, DiagnosticsConnection.stdio);
      expect(w.access, DiagnosticsAccess.notManaged);
    });

    test('WebSocket-агент: websocket, только чтение', () {
      final w = _window(_remote);

      expect(w.connection, DiagnosticsConnection.websocket);
      expect(w.access, DiagnosticsAccess.remoteReadOnly);
    });
  });

  group('состояние подключения', () {
    const reason = ConnectionFailureReason.unknown;
    final cases = <ConnectionView, DiagnosticsConnectionState>{
      const ConnectionView.disconnected():
          DiagnosticsConnectionState.disconnected,
      const ConnectionView.connecting(): DiagnosticsConnectionState.connecting,
      const ConnectionView.connected(): DiagnosticsConnectionState.connected,
      const ConnectionView.reconnecting(attempt: 1):
          DiagnosticsConnectionState.reconnecting,
      const ConnectionView.failed(reason: reason, message: 'x'):
          DiagnosticsConnectionState.failed,
      // Оборванное соединение для диагностики — не подключено.
      const ConnectionView.lost(reason: reason, message: 'x'):
          DiagnosticsConnectionState.disconnected,
    };

    cases.forEach((view, expected) {
      test('${view.runtimeType} → ${expected.name}', () {
        expect(_window(_own, connection: view).state, expected);
      });
    });
  });

  group('признак CODELAB_HOME', () {
    test('задан — custom', () {
      final w = _window(_own, environment: {'CODELAB_HOME': '/x/home'});

      expect(w.customConfigHome, isTrue);
    });

    test('не задан или пуст — default', () {
      expect(_window(_own).customConfigHome, isFalse);
      expect(
        _window(_own, environment: {'CODELAB_HOME': ''}).customConfigHome,
        isFalse,
      );
    });
  });

  test('ничего лишнего в буфере: WebSocket с токеном в адресе даёт '
      'websocket · connected и custom без маркеров', () {
    final w = _window(
      _remote,
      environment: {'CODELAB_HOME': '/Users/alice/.codelab-test'},
    );
    const about = AboutInfo(
      version: '0.1.0',
      os: 'macOS',
      arch: 'arm64',
      embeddedAgentVersion: '0.1.0',
      licenseName: 'MIT',
      licenseCopyright: 'Copyright (c) 2026 alice',
      configHome: '/Users/alice/.codelab-test',
      logDirectory: '/Users/alice/Library/logs',
      thirdPartyNotices: '',
    );

    final report = diagnosticsReportOf(
      about,
      DiagnosticsContext(
        connection: w.connection,
        connectionState: w.state,
        access: w.access,
        locale: 'en',
        languagePreference: AppLanguagePreference.system,
        customConfigHome: w.customConfigHome,
      ),
    );

    expect(report, contains('Connection: websocket · connected'));
    expect(report, contains('Agent settings: remote-read-only'));
    expect(report, contains('Config folder: custom'));
    for (final leak in [
      'sk-test-leak-0123456789',
      'devbox',
      '7420',
      '/acp',
      'alice',
      '/Users',
    ]) {
      expect(report, isNot(contains(leak)), reason: leak);
    }
  });
}
