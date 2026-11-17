import 'dart:async';

import 'package:codelab_agent_core/codelab_agent_core.dart';
import 'package:test/test.dart';

import 'support/client_channel.dart';

/// `AcpClientExecutionEnv.exec`: отмена во время ожидания показа терминала
/// (ревью итерации 5 change `add-subagents-and-tasks`; D47 Т4, ENV-7).
///
/// Почему: кадр терминала потомка может быть отброшен мостом (ход отменён,
/// `cancel_grace` истёк), тогда `terminalShown` не завершается никогда, а
/// `exec` держит терминал. Отмена обязана прервать ожидание и освободить
/// терминал.
void main() {
  test(
    'cancel while waiting for the terminal to be shown releases it',
    () async {
      final ch = await ClientChannel.open();
      ch.client.serveTerminals(holdExit: true);
      final env = ch.env()..terminalShown = (_) => Completer<void>().future;
      final cancel = CancelTokenSource();

      final result = env.exec(
        'sleep 60',
        ExecOptions(cwd: '/work', cancel: cancel.token, onTerminal: (_) {}),
      );
      // `terminal/create` отвечен обработчиком, `exec` встал на показе
      // терминала: ждём, пока запрос дойдёт до клиента и ответ вернётся.
      for (var i = 0; i < 20; i++) {
        await Future<void>.delayed(Duration.zero);
      }
      cancel.cancel();

      expect(
        await result.timeout(const Duration(seconds: 2)),
        isA<Err<ExecResult, ExecError>>().having(
          (r) => r.error.code,
          'code',
          ExecErrorCode.aborted,
        ),
      );
      expect(ch.client.methods, contains('terminal/release'));
    },
  );

  test('a terminalShown that completes does not change the flow', () async {
    final ch = await ClientChannel.open();
    ch.client.serveTerminals(exitCode: 0);
    final env = ch.env()..terminalShown = (_) async {};

    final result = await env.exec(
      'true',
      ExecOptions(cwd: '/work', onTerminal: (_) {}),
    );

    expect(result, isA<Ok<ExecResult, ExecError>>());
    expect(ch.client.methods.last, 'terminal/release');
  });
}
