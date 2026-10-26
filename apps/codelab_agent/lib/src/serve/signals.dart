import 'dart:async';
import 'dart:io';

import 'exit_codes.dart';

/// Подписка на сигналы остановки процесса.
///
/// Почему: первый `SIGINT` или `SIGTERM` запускает безопасное завершение, а
/// второй, пока оно идёт, выходит сразу с тем же кодом — пользователь не
/// должен ждать зависший ход (design.md change `add-codelab-agent-binary`,
/// D7). `SIGTERM` на Windows не поддерживается.
///
/// Как использовать: `watchStopSignals(onStop)`; [onStop] получает код выхода;
/// результат — подписки, которые отменяются после завершения.
StopSignals watchStopSignals(void Function(int code) onStop) {
  var stopping = false;
  void handle(int code) {
    if (stopping) {
      exit(code);
    }
    stopping = true;
    onStop(code);
  }

  return StopSignals._([
    ProcessSignal.sigint.watch().listen((_) => handle(sigintExit)),
    if (!Platform.isWindows)
      ProcessSignal.sigterm.watch().listen((_) => handle(sigtermExit)),
  ]);
}

/// Подписки [watchStopSignals].
final class StopSignals {
  StopSignals._(this._subscriptions);

  final List<StreamSubscription<ProcessSignal>> _subscriptions;

  Future<void> cancel() async {
    for (final subscription in _subscriptions) {
      await subscription.cancel();
    }
  }
}
