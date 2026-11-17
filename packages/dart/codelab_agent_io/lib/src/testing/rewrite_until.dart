import 'dart:async';

/// Прогрев записи для тестов с настоящим `Directory.watch` (design.md change
/// `add-config-writer-and-reload`, D7).
///
/// Почему: у FSEvents/inotify есть задержка подписки, и одна запись сразу
/// после старта может пройти мимо — тест падал бы без вины кода. Поэтому
/// запись повторяется с разным содержимым (одинаковое не даст сигнала:
/// сравнение идёт по sha256), пока не наступит ожидаемое событие [done].
///
/// Как использовать: [done] создаётся до первой записи; [write] получает
/// номер попытки и пишет вариант файла с итоговым смыслом, различаясь хвостом
/// (комментарием). Шаг больше debounce 300 мс, иначе таймер перезапускался бы
/// бесконечно. [onTick] — необязательное действие каждые 5 мс (например,
/// сдвиг `FakeClock`, пока событие каталога идёт в реальном времени). Не
/// дождались за [limit] — `TimeoutException`.
Future<void> rewriteUntil(
  Future<Object?> done,
  void Function(int attempt) write, {
  Duration step = const Duration(milliseconds: 700),
  Duration limit = const Duration(seconds: 20),
  void Function()? onTick,
}) async {
  var finished = false;
  final guarded = done.then((_) => finished = true);
  final deadline = DateTime.now().add(limit);
  var attempt = 0;
  while (!finished && DateTime.now().isBefore(deadline)) {
    write(attempt++);
    final stepEnd = DateTime.now().add(step);
    while (!finished && DateTime.now().isBefore(stepEnd)) {
      onTick?.call();
      await Future.any<Object?>([
        guarded,
        Future<void>.delayed(const Duration(milliseconds: 5)),
      ]);
    }
  }
  if (!finished) {
    throw TimeoutException('no event after $attempt writes', limit);
  }
  await guarded;
}
