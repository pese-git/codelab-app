// Один читатель stdin на нескольких владельцев по очереди (ревью 4a, п. 14;
// design.md change `add-provider-setup-ui`, D15, D16).

import 'dart:async';

import 'package:codelab_cli/codelab_cli.dart';
import 'package:test/test.dart';

void main() {
  test('два владельца по очереди: источник слушают один раз, событие между '
      'ними не теряется', () async {
    var listens = 0;
    late StreamController<List<int>> source;
    source = StreamController<List<int>>(onListen: () => listens++);
    final shared = SharedStdin(source.stream);

    final first = <List<int>>[];
    final firstSub = shared.stream.listen(first.add);
    source.add([1]);
    await pumpEventQueue();
    await firstSub.cancel();

    // Нажатие, пока владельца нет: остаётся в источнике на паузе.
    source.add([2]);
    await pumpEventQueue();
    final second = <List<int>>[];
    final secondSub = shared.stream.listen(second.add);
    await pumpEventQueue();
    source.add([3]);
    await pumpEventQueue();
    await secondSub.cancel();

    expect(first, [
      [1],
    ]);
    expect(second, [
      [2],
      [3],
    ]);
    expect(listens, 1);
  });

  test('конец источника закрывает поток', () async {
    final source = StreamController<List<int>>();
    final shared = SharedStdin(source.stream);
    final done = Completer<void>();
    shared.stream.listen((_) {}, onDone: done.complete);

    await source.close();

    await done.future;
  });
}
