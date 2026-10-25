## MODIFIED Requirements

### Requirement: Порты детерминизма от хоста
Ядро агента НЕ SHALL само создавать HTTP-клиент, таймеры ожидания, источник случайности и идентификаторы (PKG-6). `Clock` (текущее время и ожидание), `IdGenerator` (id сессий, записей, вызовов), `Random` (`dart:math`) и `http.Client` SHALL приходить от хоста.

`IdGenerator` SHALL давать два вида id:
- `nextId()` — id ходов и вызовов;
- `nextChars(count, alphabet)` — строку из `count` символов алфавита для `SessionId` и `RecordId` журнала (§8.4, design.md change `add-agent-core-sessions-and-compaction`, D3).

Ядро SHALL предоставлять `RandomIdGenerator(Random)` — реализацию поверх `Random` хоста.

Для тестов `package:codelab_agent_core/testing.dart` SHALL предоставлять `FakeClock` и `SequentialIdGenerator`; `SequentialIdGenerator.nextChars` детерминирован и не повторяет значения в пределах одного генератора. Основной барель ядра тестовые реализации НЕ SHALL экспортировать.

#### Scenario: FakeClock не двигается сам
- **WHEN** тест ждёт задержку 10 с по `FakeClock` и не двигает часы
- **THEN** задержка не завершается, сколько бы реального времени ни прошло, и завершается сразу после ручного продвижения на 10 с

#### Scenario: Последовательные id повторяемы
- **WHEN** два экземпляра `SequentialIdGenerator` выдают по три id
- **THEN** обе последовательности равны `id-1`, `id-2`, `id-3`

#### Scenario: Последовательные символы повторяемы и уникальны
- **WHEN** два экземпляра `SequentialIdGenerator` выдают по 100 значений `nextChars(8, '0123456789abcdefghijklmnopqrstuvwxyz')`
- **THEN** последовательности равны, все значения имеют длину 8, состоят из символов алфавита и попарно различны

#### Scenario: Случайность повторяема
- **WHEN** два экземпляра `Random(42)` выдают по десять чисел
- **THEN** последовательности совпадают
