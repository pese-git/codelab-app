// Красные модульные тесты `ApprovalWaitMeter` (change
// `fix-usage-pane-live-cards`, задача 2.1; design.md D6, Q3 (а), Q4 (а);
// agent-loop «Бюджет хода»). Почему: параллельная группа запрашивает
// одобрения одновременно, а счётчик суммировал длительности, и `_progress`
// вычитал из времени хода больше настенного времени.
//
// ТЕКУЩИЙ КОД ЭТИ ТЕСТЫ НЕ КОМПИЛИРУЕТ — это ожидаемая «красная» причина:
// задача 2.2 заменяет `add(Duration)` парой «начать — закончить». Имена
// предложены тестами и могут быть уточнены исполнителем 2.2 вместе с этими
// тестами: `begin(DateTime at)`, `end(DateTime at)`, `totalAt(DateTime now)`
// (сумма закрытых отрезков плюс открытый на момент `now`).
import 'package:codelab_agent_core/codelab_agent_core.dart';
import 'package:test/test.dart';

void main() {
  final t0 = DateTime.utc(2026);
  DateTime at(int seconds) => t0.add(Duration(seconds: seconds));
  Duration s(int seconds) => Duration(seconds: seconds);

  late ApprovalWaitMeter meter;
  setUp(() => meter = ApprovalWaitMeter());

  test('одно ожидание — его длительность (прежнее поведение)', () {
    meter
      ..begin(at(0))
      ..end(at(60));

    expect(meter.totalAt(at(60)), s(60));
  });

  test('пересекающиеся ожидания считаются объединением, не суммой', () {
    // 0–60 и 10–70: объединение 70 с, сумма была бы 120 с.
    meter
      ..begin(at(0))
      ..begin(at(10))
      ..end(at(60))
      ..end(at(70));

    expect(meter.totalAt(at(70)), s(70));
  });

  test('одновременные ожидания параллельной группы — одно время', () {
    meter
      ..begin(at(0))
      ..begin(at(0))
      ..end(at(60))
      ..end(at(60));

    expect(meter.totalAt(at(61)), s(60));
  });

  test('вложенные ожидания — длительность внешнего', () {
    meter
      ..begin(at(0))
      ..begin(at(5))
      ..end(at(10))
      ..end(at(30));

    expect(meter.totalAt(at(30)), s(30));
  });

  test('непересекающиеся ожидания — сумма; зазор не считается', () {
    meter
      ..begin(at(0))
      ..end(at(10))
      ..begin(at(20))
      ..end(at(35));

    expect(meter.totalAt(at(40)), s(25));
  });

  test('открытое ожидание входит в итог на момент чтения (D6)', () {
    meter.begin(at(0));

    expect(meter.totalAt(at(7)), s(7));
    expect(meter.totalAt(at(9)), s(9));
  });

  test('после закрытия последнего ожидания итог перестаёт расти', () {
    meter
      ..begin(at(0))
      ..end(at(5));

    expect(meter.totalAt(at(5)), s(5));
    expect(meter.totalAt(at(500)), s(5));
  });

  test('итог не убывает между чтениями при закрытии одного из двух', () {
    meter
      ..begin(at(0))
      ..begin(at(0));
    final before = meter.totalAt(at(30));
    meter.end(at(30));
    final middle = meter.totalAt(at(30));
    final after = meter.totalAt(at(40));

    expect(middle, before);
    expect(after, s(40));
  });

  test('reset() обнуляет сумму и открытые ожидания (новый ход)', () {
    meter
      ..begin(at(0))
      ..end(at(10))
      ..begin(at(20));

    meter.reset();

    expect(meter.totalAt(at(30)), Duration.zero);
  });

  test('счётчики корня и потомка независимы (Q4 (а))', () {
    // У потомка свой `ToolServices` и свой счётчик: ожидание одобрения
    // потомка время корня не останавливает.
    final child = ApprovalWaitMeter();

    child
      ..begin(at(0))
      ..end(at(60));

    expect(child.totalAt(at(60)), s(60));
    expect(meter.totalAt(at(60)), Duration.zero);
  });
}
