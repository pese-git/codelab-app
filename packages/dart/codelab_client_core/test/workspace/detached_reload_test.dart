// Повторная загрузка detached-сессии у агента с `loadSession` (D16, Q26 change
// `require-project-folder`): сессия, не восстановленная после перезапуска,
// должна загружаться по запросу хоста, а не падать на старом соединении.

import 'package:codelab_acp_protocol/codelab_acp_protocol.dart';
import 'package:codelab_acp_transports/codelab_acp_transports.dart';
import 'package:codelab_client_core/codelab_client_core.dart';
import 'package:test/test.dart';

import '../support/kit_agent.dart';

void main() {
  late KitAgent agent;
  tearDown(() => agent.dispose());

  test(
    'a session detached after a failed restore loads again on request',
    () async {
      const caps = AgentCapabilities(loadSession: true);
      agent = KitAgent(capabilities: caps);
      await agent.start();
      final handle = await agent.newSession('s-root');
      agent.transport.fail(
        const AcpTransportException(
          code: AcpTransportErrorCode.closed,
          message: 'exited',
        ),
      );

      agent.restartAgent(capabilities: caps);
      final restore = agent.next(sessionLoadMethod);
      final reconnecting = agent.workspace.reconnect();
      agent.fail(await restore, 'Resource not found');
      await reconnecting;
      expect(handle.current.status, SessionStatusView.detached);

      // Третий «процесс» агента: ещё одно переподключение, как в desktop.
      agent.restartAgent(capabilities: caps);
      final restore2 = agent.next(sessionLoadMethod);
      final reconnecting2 = agent.workspace.reconnect();
      agent.fail(await restore2, 'Resource not found');
      await reconnecting2;

      final load = agent.next(sessionLoadMethod);
      final loading = agent.workspace.loadSession(
        const SessionId('s-root'),
        cwd: '/',
      );
      agent.respond(await load, const <String, Object?>{});
      await loading;

      expect(handle.current.status, isNot(SessionStatusView.detached));
    },
  );
}
