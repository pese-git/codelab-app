// Монотонные часы отсчётов безопасности (design D14): не убывают и меряют
// прошедшее время, не завися от перевода системных часов.
import 'package:codelab_desktop/features/workbench/application/shell_cubit.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('часы по умолчанию не убывают и идут вперёд', () {
    final clock = createMonotonicClock();
    var previous = clock();
    final start = previous;
    final spin = Stopwatch()..start();
    while (spin.elapsedMilliseconds < 3) {
      final now = clock();
      expect(now.isBefore(previous), isFalse);
      previous = now;
    }
    expect(previous.difference(start), greaterThanOrEqualTo(Duration.zero));
    expect(previous.isAfter(start), isTrue);
  });
}
