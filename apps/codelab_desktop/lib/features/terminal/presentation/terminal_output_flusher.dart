import 'package:flutter/scheduler.dart';

import '../application/terminal_tabs_cubit.dart';

/// Бюджет времени записи в эмулятор на один кадр (D3, D15).
///
/// Почему: на «Flood» запись частей без ограничения занимает кадр целиком и
/// даёт рывки; 8 мс оставляют кадру запас на раскладку и отрисовку. Размер
/// части — `terminalWriteChunkSize` (4 КБ) у Cubit. Значения стартовые; итог
/// ручного замера записывается в D3 (задача 2.8).
const terminalFrameBudget = Duration(milliseconds: 8);

/// Записывает накопленный вывод вкладок в модели эмулятора на кадре.
///
/// Почему: вывод процесса приходит потоком, а запись в `Terminal` и перерисовка
/// дороги; запись порциями из обработчика потока заморозила бы UI isolate на
/// «Flood» (`add-integrated-terminal`, D3, D15). Cubit копит вывод в буфере
/// вкладки, а этот объект сбрасывает его в кадре планировщика.
///
/// Для чего: один на root scope, того же срока жизни, что и Cubit; работает и
/// без виджета панели (закрытая панель не копит вывод бесконечно). На кадре
/// пишет части Cubit (до 4 КБ), пока не исчерпан [terminalFrameBudget];
/// хотя бы одна часть за кадр пишется всегда (прогресс при дорогой записи),
/// остаток уходит на следующий кадр (тест 2.7).
///
/// Как использовать: собирается в `CodeLabPresentationModule` и один раз
/// резолвится при создании scope; `dispose()` (cherrypick зовёт при закрытии
/// scope) снимает крючок Cubit и отменяет заказанный обратный вызов кадра.
final class TerminalOutputFlusher {
  TerminalOutputFlusher({
    required TerminalTabsCubit cubit,
    SchedulerBinding? binding,
    Duration Function()? clock,
    this.frameBudget = terminalFrameBudget,
  }) : _cubit = cubit,
       _injected = binding,
       _clock = clock ?? _monotonicClock() {
    _cubit.onPendingOutput = _schedule;
    // Вывод мог накопиться до создания объекта.
    if (_cubit.hasPendingOutput) _schedule();
  }

  final TerminalTabsCubit _cubit;
  final SchedulerBinding? _injected;

  /// Бюджет записи за кадр; тесты подставляют своё значение.
  final Duration frameBudget;
  final Duration Function() _clock;

  /// Монотонные часы по умолчанию: `DateTime.now` прыгает при смене времени
  /// системы и ломал бы бюджет.
  static Duration Function() _monotonicClock() {
    final watch = Stopwatch()..start();
    return () => watch.elapsed;
  }

  /// Привязка берётся лениво: root scope собирается и там, где виджетов нет
  /// (тесты без `WidgetsBinding`), а кадр нужен, только когда пришёл вывод.
  SchedulerBinding get _binding => _injected ?? SchedulerBinding.instance;
  int? _callbackId;
  bool _disposed = false;

  void _schedule() {
    if (_disposed || _callbackId != null) return;
    // `scheduleFrameCallback` сам кадр не заказывает: без `scheduleFrame()` в
    // неподвижном окне вывод остался бы в буфере до следующего события.
    _callbackId = _binding.scheduleFrameCallback(_onFrame);
    _binding.scheduleFrame();
  }

  void _onFrame(Duration _) {
    _callbackId = null;
    if (_disposed) return;
    final started = _clock();
    var first = true;
    _cubit.flushOutput(
      canContinue: () {
        if (first) {
          first = false;
          return true;
        }
        return _clock() - started < frameBudget;
      },
    );
    if (_cubit.hasPendingOutput) _schedule();
  }

  /// Снимает крючок и отменяет заказанный кадр; повтор безопасен.
  void dispose() {
    if (_disposed) return;
    _disposed = true;
    if (_cubit.onPendingOutput == _schedule) _cubit.onPendingOutput = null;
    final id = _callbackId;
    if (id != null) _binding.cancelFrameCallbackWithId(id);
    _callbackId = null;
  }
}
