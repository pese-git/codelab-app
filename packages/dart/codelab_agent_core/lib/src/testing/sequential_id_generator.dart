import '../util/ids.dart';

/// [IdGenerator] для тестов: одна и та же последовательность в каждом
/// прогоне.
///
/// Почему: сценарные тесты сравнивают события и журнал побайтово (PKG-6),
/// поэтому id не должны зависеть от случайности.
///
/// Как использовать: [nextId] даёт `id-1`, `id-2`, …; [nextChars] —
/// номер вызова в системе счисления алфавита, дополненный слева первым
/// символом алфавита. Счётчики двух методов независимы.
final class SequentialIdGenerator implements IdGenerator {
  SequentialIdGenerator({this.prefix = 'id-'});

  final String prefix;
  var _next = 1;
  var _nextChars = 1;

  @override
  String nextId() => '$prefix${_next++}';

  @override
  String nextChars(int count, String alphabet) {
    final base = alphabet.length;
    final digits = <int>[];
    for (var n = _nextChars++; n > 0; n ~/= base) {
      digits.add(alphabet.codeUnitAt(n % base));
    }
    final value = String.fromCharCodes(digits.reversed);
    // Длиннее count значение становится только после base^count вызовов;
    // хвост сохраняет уникальность в пределах одного прогона теста.
    return value.length >= count
        ? value.substring(value.length - count)
        : value.padLeft(count, alphabet[0]);
  }
}
