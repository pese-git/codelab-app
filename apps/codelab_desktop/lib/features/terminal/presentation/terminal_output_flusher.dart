import 'dart:async';

import 'package:cherrypick/cherrypick.dart' show Disposable;
import 'package:flutter/scheduler.dart';

import '../application/terminal_tabs_cubit.dart';

/// Бюджет времени записи в эмулятор на один кадр (D3, D15).
///
/// Почему: на «Flood» запись частей без ограничения занимает кадр целиком и
/// даёт рывки; 8 мс оставляют кадру запас на раскладку и отрисовку. Размер
/// части — `terminalWriteChunkSize` (4 КБ) у Cubit. Итог ручного замера на
/// «Flood» записан в D3 (задача 2.8): худший кадр 29–36 мс при цели < 50 мс.
const terminalFrameBudget = Duration(milliseconds: 8);

/// Через сколько после заказа кадра без самого кадра вывод сбрасывается по
/// таймеру (Q20).
///
/// Почему: у скрытого или свёрнутого окна кадров нет, `scheduleFrame()` ничего
/// не запускает, и вывод копился бы в буфере, пока окно не вернётся. Кадров
/// «нет» определяем честно по факту: обратный вызов не пришёл за этот срок
/// (`SchedulerBinding.framesEnabled` и lifecycle не годятся — первый не
/// отражает занятый кадр, второй зависит от платформы). 250 мс заметно больше
/// периода кадра (16 мс), поэтому при живом окне таймер не срабатывает, а при
/// скрытом сбрасывает ~4 порции бюджетом в секунду.
const terminalFrameFallback = Duration(milliseconds: 250);

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
/// scope только у `Disposable`, поэтому класс его реализует) снимает крючок
/// Cubit, отменяет заказанный обратный вызов кадра и таймер-страховку.
/// Если кадр не пришёл за [frameFallback] (окно скрыто), тот же сброс с тем же
/// бюджетом идёт по таймеру (Q20).
final class TerminalOutputFlusher implements Disposable {
  TerminalOutputFlusher({
    required TerminalTabsCubit cubit,
    SchedulerBinding? binding,
    Duration Function()? clock,
    this.frameBudget = terminalFrameBudget,
    this.frameFallback = terminalFrameFallback,
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

  /// Срок ожидания кадра до сброса по таймеру; тесты подставляют своё.
  final Duration frameFallback;
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
  Timer? _fallback;
  bool _disposed = false;

  void _schedule() {
    if (_disposed || _callbackId != null) return;
    // `scheduleFrameCallback` сам кадр не заказывает: без `scheduleFrame()` в
    // неподвижном окне вывод остался бы в буфере до следующего события.
    _callbackId = _binding.scheduleFrameCallback(_onFrame);
    _binding.scheduleFrame();
    _fallback = Timer(frameFallback, _onFallback);
  }

  /// Кадра нет: заказанный обратный вызов снимается (иначе он сработал бы
  /// позже поверх таймера) и вывод сбрасывается тем же порядком (Q20).
  void _onFallback() {
    _fallback = null;
    final id = _callbackId;
    if (id != null) _binding.cancelFrameCallbackWithId(id);
    _callbackId = null;
    _flush();
  }

  void _onFrame(Duration _) {
    _fallback?.cancel();
    _fallback = null;
    _callbackId = null;
    _flush();
  }

  void _flush() {
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

  /// Снимает крючок, отменяет заказанный кадр и таймер; повтор безопасен.
  @override
  void dispose() {
    if (_disposed) return;
    _disposed = true;
    _fallback?.cancel();
    _fallback = null;
    if (_cubit.onPendingOutput == _schedule) _cubit.onPendingOutput = null;
    final id = _callbackId;
    if (id != null) _binding.cancelFrameCallbackWithId(id);
    _callbackId = null;
  }
}
