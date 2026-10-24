import 'dart:async';

/// Асинхронный mutex по ключу «нормализованный абсолютный путь»
/// (`agent-core-architecture` §6.3.4, TOOL-7).
///
/// Почему: `write` и `edit` читают файл, проверяют и записывают его с
/// `await` между шагами. Две параллельные правки одного файла без
/// блокировки прочитали бы одно и то же содержимое, и вторая запись
/// затёрла бы первую.
///
/// Для чего: правки одного пути исполняются по очереди в порядке вызовов,
/// правки разных путей — одновременно. Итог равен последовательному
/// применению вызовов ответа модели.
///
/// Как использовать: один экземпляр на сессию у точки исполнения. Место в
/// очереди занимается [reserve] при объявлении вызова, в порядке ответа, —
/// так очередь не зависит от того, чей хук разрешений ответит раньше.
/// Захват — `await ticket.acquired`, освобождение — [PathLockTicket.release]
/// на любом пути завершения. Для простого случая есть [run].
final class PathLock {
  final _tails = <String, Future<void>>{};

  /// Занимает место в очереди [key]; держатель ждёт `acquired` и обязан
  /// вызвать `release`, иначе следующие держатели не дождутся.
  PathLockTicket reserve(String key) {
    final previous = _tails[key] ?? Future<void>.value();
    final done = Completer<void>();
    _tails[key] = done.future;
    return PathLockTicket._(previous, () {
      if (done.isCompleted) {
        return;
      }
      done.complete();
      if (identical(_tails[key], done.future)) {
        _tails.remove(key);
      }
    });
  }

  /// Исполняет [body] под блокировкой [key]; ошибка тела не блокирует
  /// следующего держателя.
  Future<T> run<T>(String key, Future<T> Function() body) async {
    final ticket = reserve(key);
    try {
      await ticket.acquired;
      return await body();
    } finally {
      ticket.release();
    }
  }
}

/// Место в очереди [PathLock].
final class PathLockTicket {
  PathLockTicket._(this.acquired, this._release);

  /// Завершается, когда предыдущий держатель отпустил путь.
  final Future<void> acquired;
  final void Function() _release;

  /// Отпускает путь; повторный вызов ничего не делает.
  void release() => _release();
}
