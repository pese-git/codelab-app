// `probeOutcomeText` — тексты исхода «Test connection» (задача 3.8b change
// `add-app-settings-shell`; spec app-settings «Диалог «Add connection
// profile»»; design.md D12 (таблица), D17, D20).
//
// Проверяется только то, что видит пользователь: каждая строка таблицы D12 и
// отсутствие утечки. Текст `Unreachable.message` и аргументы команды в строку
// попадать не должны, даже если они несут секрет.

import 'package:codelab_client_core/codelab_client_core.dart';
import 'package:codelab_desktop/features/settings/application/probe_outcome_view.dart';
import 'package:codelab_desktop/features/settings/application/profile_view.dart';
import 'package:flutter_test/flutter_test.dart';

/// Маркер, которого не должно быть ни в одном тексте.
const _leak = 'sk-test-leak-0123456789';

void main() {
  group('Reachable', () {
    test('shows latency, agent name and version', () {
      const outcome = Reachable(
        latency: Duration(milliseconds: 42),
        agentName: 'codelab-agent',
        agentVersion: '0.3.1',
      );

      expect(
        probeOutcomeText(outcome),
        'Reachable · 42 ms · codelab-agent 0.3.1',
      );
      expect(probeOutcomeIsOk(outcome), isTrue);
    });

    test('omits the agent part when the agent sent no info', () {
      expect(
        probeOutcomeText(const Reachable(latency: Duration(milliseconds: 7))),
        'Reachable · 7 ms',
      );
    });
  });

  group('Command not found', () {
    test('names the command only, never arguments or env', () {
      expect(
        probeOutcomeText(const CommandNotFound(), command: 'codelab-agent'),
        'Command not found: codelab-agent',
      );
    });

    test('without a command there is no tail', () {
      expect(probeOutcomeText(const CommandNotFound()), 'Command not found');
    });
  });

  group('Unreachable by reason', () {
    final cases = <UnreachableReason, String>{
      UnreachableReason.connectionRefused: 'Unreachable: connection refused',
      UnreachableReason.hostNotFound: 'Unreachable: host not found',
      UnreachableReason.tlsFailed: 'Unreachable: TLS handshake failed',
      UnreachableReason.unknown: 'Unreachable',
    };
    for (final MapEntry(:key, :value) in cases.entries) {
      test('$key -> "$value"; the transport message stays out', () {
        final outcome = Unreachable(
          'refused wss://u:p@host:1/acp?t=$_leak',
          reason: key,
        );

        final text = probeOutcomeText(outcome);

        expect(text, value);
        expect(text, isNot(contains(_leak)));
        expect(probeOutcomeIsOk(outcome), isFalse);
      });
    }

    test('httpStatus shows the status code', () {
      const outcome = Unreachable(
        'HTTP 502 for /acp?t=$_leak',
        reason: UnreachableReason.httpStatus,
        statusCode: 502,
      );

      expect(probeOutcomeText(outcome), 'Unreachable: HTTP 502');
    });

    test('the default reason is unknown: bare "Unreachable"', () {
      expect(probeOutcomeText(const Unreachable('boom $_leak')), 'Unreachable');
    });
  });

  group('Unauthorized', () {
    test('with a token from a set variable: the agent rejected the token', () {
      expect(
        probeOutcomeText(
          const Unauthorized(),
          token: const EnvTokenView('DEVBOX_TOKEN', isSet: true),
        ),
        'Unauthorized: the agent rejected the token',
      );
    });

    test('without a token: the agent requires one', () {
      expect(
        probeOutcomeText(const Unauthorized(), token: const NoTokenView()),
        'Unauthorized: the agent requires a token',
      );
      expect(
        probeOutcomeText(const Unauthorized()),
        'Unauthorized: the agent requires a token',
      );
    });

    test('a variable that is not set was not sent: the agent requires a '
        'token', () {
      expect(
        probeOutcomeText(
          const Unauthorized(),
          token: const EnvTokenView('DEVBOX_TOKEN', isSet: false),
        ),
        'Unauthorized: the agent requires a token',
      );
    });

    test('an unsupported reference sends nothing: the agent requires a '
        'token', () {
      expect(
        probeOutcomeText(
          const Unauthorized(),
          token: const UnsupportedTokenView(),
        ),
        'Unauthorized: the agent requires a token',
      );
    });
  });

  test('the remaining outcomes', () {
    expect(probeOutcomeText(const TimedOut()), 'Timed out');
    expect(probeOutcomeText(const NotAcp()), 'Not an ACP agent');
    expect(probeOutcomeText(const Unsupported()), 'Not supported here');
  });

  test('outcome names for the log carry no text', () {
    expect(probeOutcomeName(const Unreachable('x $_leak')), 'unreachable');
    expect(probeOutcomeName(const CommandNotFound()), 'command_not_found');
  });
}
