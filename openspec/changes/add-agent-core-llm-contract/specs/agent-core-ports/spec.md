## ADDED Requirements

### Requirement: Порты детерминизма от хоста
Ядро агента НЕ SHALL само создавать HTTP-клиент, таймеры ожидания, источник случайности и идентификаторы (PKG-6). `Clock` (текущее время и ожидание), `IdGenerator` (id сессий, записей, вызовов), `Random` (`dart:math`) и `http.Client` SHALL приходить от хоста. Для тестов `package:codelab_agent_core/testing.dart` SHALL предоставлять `FakeClock` и `SequentialIdGenerator`. Основной барель ядра их НЕ SHALL экспортировать.

#### Scenario: FakeClock не двигается сам
- **WHEN** тест ждёт задержку 10 с по `FakeClock` и не двигает часы
- **THEN** задержка не завершается, сколько бы реального времени ни прошло, и завершается сразу после ручного продвижения на 10 с

#### Scenario: Последовательные id повторяемы
- **WHEN** два экземпляра `SequentialIdGenerator` выдают по три id
- **THEN** обе последовательности равны `id-1`, `id-2`, `id-3`

#### Scenario: Случайность повторяема
- **WHEN** два экземпляра `Random(42)` выдают по десять чисел
- **THEN** последовательности совпадают

### Requirement: Порт логирования
Ядро SHALL писать диагностику только через порт `Logger` (`isEnabled(level)`, `log(level, event, {fields, error, stack})`) с уровнями `trace`, `debug`, `info`, `warning`, `error` (§12.3). `event` SHALL быть стабильным именем вида `<область>.<действие>` (например `llm.retry`, `llm.request.end`). Ключи `fields` SHALL быть в `snake_case`. Ядро НЕ SHALL печатать в stdout. Тексты сообщений и аргументы инструментов НЕ SHALL попадать в записи уровня `info` и выше.

#### Scenario: Повтор запроса логируется событием
- **WHEN** декоратор повтора делает новую попытку
- **THEN** `Logger` получает запись уровня `info` с событием `llm.retry` и полями `attempt`, `class`, `delay_ms`
