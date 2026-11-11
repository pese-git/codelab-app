import 'package:flutter/scheduler.dart';

import '../application/terminal_tabs_cubit.dart';

/// Записывает накопленный вывод вкладок в модели эмулятора на кадре.
///
/// Почему: вывод процесса приходит потоком, а запись в `Terminal` и перерисовка
/// дороги; запись порциями из обработчика потока заморозила бы UI isolate на
/// «Flood» (`add-integrated-terminal`, D3, D15). Cubit копит вывод в буфере
/// вкладки, а этот объект сбрасывает его в кадре планировщика.
///
/// Для чего: один на root scope, того же срока жизни, что и Cubit; работает и
/// без виджета панели (закрытая панель не копит вывод бесконечно). Сейчас —
/// простой сброс частями Cubit (до 4 КБ); бюджет времени на кадр — задачи
/// 2.7–2.8, константы появятся здесь же.
///
/// Как использовать: собирается в `CodeLabPresentationModule` и один раз
/// резолвится при создании scope; `dispose()` (cherrypick зовёт при закрытии
/// scope) снимает крючок Cubit и отменяет заказанный обратный вызов кадра.
final class TerminalOutputFlusher {
  TerminalOutputFlusher({
    required TerminalTabsCubit cubit,
    SchedulerBinding? binding,
  }) : _cubit = cubit,
       _injected = binding {
    _cubit.onPendingOutput = _schedule;
    // Вывод мог накопиться до создания объекта.
    if (_cubit.hasPendingOutput) _schedule();
  }

  final TerminalTabsCubit _cubit;
  final SchedulerBinding? _injected;

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
    _cubit.flushOutput();
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
