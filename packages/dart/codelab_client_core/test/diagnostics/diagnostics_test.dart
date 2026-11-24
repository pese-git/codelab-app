// Тесты диагностики kit (tasks 6.1; spec acp-client-kit «Диагностика без
// секретов»; design D9).

import 'package:codelab_acp_protocol/codelab_acp_protocol.dart';
import 'package:codelab_client_acp/codelab_client_acp.dart';
import 'package:codelab_client_core/codelab_client_core.dart';
import 'package:test/test.dart';

import '../support/kit_agent.dart';

void main() {
  group('describeFailureForDiagnostic', () {
    const error = AcpClientApplicationException(
      'ACP request x failed: PRIVATE api_key=sk-LEAKEDTOKEN123456',
      cause: JsonRpcError(code: -32603, message: 'PRIVATE'),
    );

    test('metadataOnly: метаданные без текста', () {
      expect(
        describeFailureForDiagnostic(error, ProtocolPayloadPolicy.metadataOnly),
        'AcpClientApplicationException: JSON-RPC error -32603 (Internal error)',
      );
    });

    test('full: замаскированный текст', () {
      final text = describeFailureForDiagnostic(
        error,
        ProtocolPayloadPolicy.full,
      );
      expect(text, contains('PRIVATE'));
      expect(text, isNot(contains('sk-LEAKEDTOKEN123456')));
    });
  });

  group('describeFailure', () {
    test('takes the message of the client core and transport errors', () {
      expect(
        describeFailure(
          const AcpClientApplicationException(
            'Failed to connect ACP transport.',
          ),
        ),
        'Failed to connect ACP transport.',
      );
      expect(
        describeFailure(
          const AcpTransportException(
            code: AcpTransportErrorCode.sendFailed,
            message: 'pipe closed',
          ),
        ),
        'pipe closed',
      );
      expect(
        describeFailure(const ClientWorkspaceException('Connect first.')),
        'Connect first.',
      );
    });

    test('any other error is its text', () {
      expect(describeFailure(StateError('boom')), 'Bad state: boom');
    });

    test('masks tokens in the text', () {
      final text = describeFailure(
        const AcpTransportException(
          code: AcpTransportErrorCode.startFailed,
          message: 'rejected: Authorization: Bearer s3cr3t-value',
        ),
      );

      expect(text, isNot(contains('s3cr3t-value')));
      expect(text, contains('Bearer <redacted>'));
    });
  });

  test('formatRedactedJson pretty-prints and masks sensitive keys', () {
    final text = formatRedactedJson({'command': 'ls', 'api_key': 'sk-123'})!;

    expect(text, contains('"command": "ls"'));
    expect(text, isNot(contains('sk-123')));
    expect(formatRedactedJson(null), isNull);
  });

  // approval-safety «Редактирование секретов», сценарий «Отображаются
  // переменные окружения» (задача 5.2 change `align-cross-cutting-specs`):
  // launch environment профиля в диагностике показывает секретоподобные
  // значения замаскированными, обычные — как есть.
  test('launch environment in diagnostics masks secret-like values', () {
    final text = formatRedactedJson({
      'env': {
        'PATH': '/usr/bin',
        'API_KEY': 'sk-live-123456',
        'GITHUB_TOKEN': 'ghp_abc123',
        'DB_PASSWORD': 'hunter2',
      },
    })!;

    expect(text, contains('"PATH": "/usr/bin"'));
    expect(text, isNot(contains('sk-live-123456')));
    expect(text, isNot(contains('ghp_abc123')));
    expect(text, isNot(contains('hunter2')));
  });

  group('workspace diagnostics', () {
    late KitAgent agent;

    setUp(() async {
      agent = KitAgent();
      await agent.start();
    });
    tearDown(() => agent.dispose());

    test('an unexpected transport failure is reported once, without the '
        'token', () async {
      agent.transport.fail(
        const AcpTransportException(
          code: AcpTransportErrorCode.disconnected,
          message: 'agent exited; token=s3cr3t-value',
        ),
      );

      final lost = agent.diagnostics.where(
        (d) => d.message.startsWith('Connection to ACP agent lost'),
      );
      expect(lost, hasLength(1));
      expect(lost.single.severity, DiagnosticSeverity.error);
      expect(lost.single.source, 'transport');
      expect(lost.single.message, isNot(contains('s3cr3t-value')));
    });

    test('prompt outcomes and cancellation are reported', () async {
      final session = await agent.newSession('s-1');
      final turn = await agent.prompt(session, 'hello');

      await session.cancel();
      expect(agent.diagnostics.last.message, 'Cancelled prompt turn turn-1.');

      agent.respond(turn.request, const {'stopReason': 'cancelled'});
      await turn.done;
      expect(
        agent.diagnostics.last,
        const WorkspaceDiagnostic(
          severity: DiagnosticSeverity.info,
          source: 'prompt',
          message: 'Prompt completed with stopReason cancelled.',
        ),
      );

      final failing = await agent.prompt(session, 'again');
      agent.fail(failing.request, 'agent crashed');
      await failing.done;
      expect(agent.diagnostics.last.severity, DiagnosticSeverity.error);
      expect(
        agent.diagnostics.last.message,
        startsWith('Failed to send prompt: '),
      );
    });
  });
}
