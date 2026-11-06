import 'dart:async';
import 'dart:io' as io;

/// Единственный читатель `stdin` процесса, который можно передавать
/// нескольким владельцам по очереди.
///
/// Почему: `io.stdin` — single-subscription, а отмена подписки закрывает
/// fd 0. Мастер первого запуска, следом REPL или `dart_tui` должны читать
/// один терминал, и второй `listen` на `io.stdin` невозможен (design.md change
/// `add-provider-setup-ui`, D15, D16, «Один владелец stdin»).
///
/// Для чего: [stream] — broadcast-поток поверх одной подписки на stdin.
/// Подписка живёт весь процесс, но пока у потока нет слушателей, она на
/// паузе: нажатия остаются в буфере ОС и достаются следующему владельцу.
///
/// Как использовать: `run.dart` создаёт один экземпляр на запуск и отдаёт
/// [stream] в `IoTerminal(input:)` и `TuiRunner(input:)`.
final class SharedStdin {
  SharedStdin([Stream<List<int>>? source]) : _source = source ?? io.stdin {
    _controller = StreamController<List<int>>.broadcast(
      onListen: _resume,
      onCancel: _pause,
    );
  }

  final Stream<List<int>> _source;
  late final StreamController<List<int>> _controller;
  StreamSubscription<List<int>>? _subscription;

  Stream<List<int>> get stream => _controller.stream;

  void _resume() {
    final subscription = _subscription ??= _source.listen(
      _controller.add,
      onError: _controller.addError,
      onDone: () => unawaited(_controller.close()),
    );
    if (subscription.isPaused) {
      subscription.resume();
    }
  }

  void _pause() => _subscription?.pause();
}
