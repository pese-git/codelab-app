import 'dart:async';

/// Очередь операций над файлами: одна цепочка `Future` на путь.
///
/// Почему общая для процесса: писатели сессии (сообщения, план, сжатие) и
/// хранилища над тем же каталогом пишут в один файл, а байты двух строк не
/// должны перемешиваться (SES-4, `agent-core-architecture` §8.5, шаг 3).
/// Межпроцессной блокировки в MVP нет: одна сессия — один процесс-писатель.
///
/// Для чего: `JsonlSessionStore` ставит в очередь каждую запись, сброс,
/// открытие с ремонтом и закрытие файла журнала, а также запись
/// `index.json`.
///
/// Как использовать: `await writeQueue.run(path, () async { ... })`.
/// Ошибка операции уходит её вызывающему, а следующая операция того же
/// пути выполняется как обычно — сбой не наследуется.
final class WriteQueue {
  final _tails = <String, Future<void>>{};

  Future<T> run<T>(String path, Future<T> Function() operation) {
    final previous = _tails[path] ?? Future<void>.value();
    final result = previous.then((_) => operation());
    // Хвост очереди не несёт ошибку: её получает только вызывающий.
    final tail = result.then<void>((_) {}, onError: (Object _) {});
    _tails[path] = tail;
    unawaited(
      tail.then((_) {
        if (identical(_tails[path], tail)) {
          _tails.remove(path);
        }
      }),
    );
    return result;
  }
}

/// Очередь процесса (D7: очередь на путь общая для всех хранилищ).
final writeQueue = WriteQueue();
