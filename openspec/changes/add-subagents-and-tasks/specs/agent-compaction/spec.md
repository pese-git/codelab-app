## MODIFIED Requirements

### Requirement: Точки срабатывания сжатия
Сжатие SHALL запускаться (§9.5):
- `afterTurn` — после `TurnEnded(completed | maxTokens)` при `shouldCompact`, в фоне; следующий `prompt()` ждёт его завершения; после `cancelled` и `failed` не запускается;
- `preflight` — оценка payload шага больше окна (не порога): один аварийный вызов; запрос всё ещё больше окна → шаг завершается ошибкой `overflow`, ход — `TurnEnded(failed)`;
- `overflow` — провайдер вернул `errorClass: overflow`: сжатие и один повтор того же шага; второй `overflow` → `TurnEnded(failed)`;
- `manual` — вызов компактора с `focus` вне хода.

В пределах одного хода `preflight` и `overflow` вместе SHALL вызывать сжатие не более одного раза (CMP-8). При выключенной capability `compaction` сжатие не запускается ни одним триггером.

#### Scenario: Переполнение, затем успех
- **WHEN** scripted модель на первом запросе отвечает ошибкой `overflow`, а после сжатия — текстом
- **THEN** ход завершается `TurnEnded(completed)`, в журнале есть запись `compaction`, эмитится `ContextCompacted` (`overflow_then_compact_test.dart`)

#### Scenario: Повторное переполнение
- **WHEN** модель отвечает `overflow` и после сжатия
- **THEN** второго сжатия нет, ход завершается `TurnEnded(failed)`

#### Scenario: Длинная сессия продолжается
- **WHEN** сессия с окном 8 192 на настройках по умолчанию (в том числе `subagents.enabled: true`) проходит 30 ходов с крупными результатами инструментов на scripted модели
- **THEN** инструмента `agent` в схемах нет (окно меньше порога субагентов, design.md change `add-subagents-and-tasks`, D40); сжатие срабатывает, каждый запрос к модели проходит проверку парности, оценка после каждого сжатия ниже порога (CMP-1, CMP-5)
