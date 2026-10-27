import 'dart:async';
import 'dart:io';

import 'exit_codes.dart';

/// Подписка на сигналы остановки процесса `codelab`.
///
/// Почему: первый `SIGINT` или `SIGTERM` отменяет ход и закрывает транспорт
/// вместе с процессом агента; второй, пока это идёт, выходит сразу —
/// пользователь не должен ждать зависшего агента (design.md change
/// `add-codelab-cli`, D13). Семантика та же, что у `codelab-agent`; код не
/// общий, потому что приложения не зависят друг от друга. `SIGTERM` на
/// Windows не поддерживается.
///
/// Как использовать: `watchStopSignals(onStop)`; [onStop] получает код
/// выхода (`130` или `143`); после завершения — [StopSignals.cancel]. Тесты
/// передают свои потоки [sigint], [sigterm] и [forceExit].
StopSignals watchStopSignals(
  void Function(int code) onStop, {
  Stream<ProcessSignal>? sigint,
  Stream<ProcessSignal>? sigterm,
  void Function(int code) forceExit = exit,
}) {
  var stopping = false;
  void handle(int code) {
    if (stopping) {
      forceExit(code);
      return;
    }
    stopping = true;
    onStop(code);
  }

  final term =
      sigterm ?? (Platform.isWindows ? null : ProcessSignal.sigterm.watch());
  return StopSignals._([
    (sigint ?? ProcessSignal.sigint.watch()).listen((_) => handle(sigintExit)),
    if (term != null) term.listen((_) => handle(sigtermExit)),
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
