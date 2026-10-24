import 'dart:math';

/// Порт идентификаторов ядра (PKG-6).
///
/// Почему порт: id сессий, записей журнала, ходов и вызовов должны
/// повторяться от прогона к прогону в тестах, а ядро не создаёт источник
/// случайности само.
///
/// Для чего: [nextId] даёт id ходов и вызовов; [nextChars] — строки из
/// заданного алфавита для `SessionId` (ULID) и 8-символьных `RecordId`
/// журнала (§8.4; design.md change `add-agent-core-sessions-and-compaction`,
/// D3).
///
/// Как использовать: хост передаёт [RandomIdGenerator] над `Random.secure()`
/// в `AgentCoreServices.ids`; тесты — `SequentialIdGenerator`.
abstract interface class IdGenerator {
  String nextId();

  /// [count] символов [alphabet]; для журнала — независимые и
  /// равновероятные.
  String nextChars(int count, String alphabet);
}

/// [IdGenerator] поверх [Random] хоста.
///
/// Почему в ядре: алгоритм одинаков для всех хостов, а источник
/// случайности (`Random.secure()` или `Random(seed)`) по-прежнему приходит
/// снаружи (PKG-6).
final class RandomIdGenerator implements IdGenerator {
  RandomIdGenerator(this._random);

  final Random _random;

  static const _idAlphabet = '0123456789abcdefghijklmnopqrstuvwxyz';

  @override
  String nextId() => nextChars(16, _idAlphabet);

  @override
  String nextChars(int count, String alphabet) => String.fromCharCodes([
    for (var i = 0; i < count; i++)
      alphabet.codeUnitAt(_random.nextInt(alphabet.length)),
  ]);
}
