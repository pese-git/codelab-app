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

/// Шов сигналов для `runCodelab`: потоки сигналов и выход.
///
/// Почему: тесты не могут слать настоящие сигналы процессу, а выход `exit`
/// из теста завершил бы сам тест. По умолчанию — сигналы ОС и `exit`.
///
/// Как использовать: `runCodelab(…, signals: SignalSeam(sigint: …, sigterm:
/// …, forceExit: codes.add))`.
final class SignalSeam {
  const SignalSeam({this.sigint, this.sigterm, this.forceExit = exit});

  final Stream<ProcessSignal>? sigint;
  final Stream<ProcessSignal>? sigterm;
  final void Function(int code) forceExit;
}

/// Сигналы режима CLI (REPL, TUI, headless) на всё время его работы, включая
/// `dispose` встроенного агента.
///
/// Почему: пока агент завершается, процесс не должен остаться без
/// обработчиков — Ctrl+C ушёл бы в ОС без кода 130, а журнал мог не
/// дописаться (design.md change `add-embedded-agent-mode`, D6, «Выход CLI»;
/// `AGENTS.md` §12). Подписки снимаются только после `dispose`.
///
/// Для чего: пока [isStopped] ложно, первый сигнал вызывает [onStop] (отмена
/// хода), второй выходит сразу. Когда режим закончен ([isStopped] истинно,
/// идёт `dispose`), выходит сразу уже первый сигнал — с кодом `130`
/// (`SIGINT`) или `143` (`SIGTERM`).
///
/// [onSigint] — REPL: `SIGINT` вне raw-режима ведёт себя как Ctrl+C и не
/// считается сигналом остановки, пока режим не закончен.
StopSignals watchModeSignals({
  required void Function(int code) onStop,
  required bool Function() isStopped,
  void Function()? onSigint,
  SignalSeam seam = const SignalSeam(),
}) {
  final signals = watchStopSignals(
    (code) {
      if (isStopped()) {
        seam.forceExit(code);
      } else {
        onStop(code);
      }
    },
    sigint: onSigint == null ? seam.sigint : const Stream.empty(),
    sigterm: seam.sigterm,
    forceExit: seam.forceExit,
  );
  if (onSigint != null) {
    signals._subscriptions.add(
      (seam.sigint ?? ProcessSignal.sigint.watch()).listen((_) {
        if (isStopped()) {
          seam.forceExit(sigintExit);
        } else {
          onSigint();
        }
      }),
    );
  }
  return signals;
}
