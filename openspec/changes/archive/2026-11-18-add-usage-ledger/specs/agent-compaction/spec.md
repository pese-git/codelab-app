## ADDED Requirements

### Requirement: Usage суммаризатора
`Summarizer` SHALL возвращать вместе с текстом резюме usage и модель ответа модели (design.md change `add-usage-ledger`, D4; решение Q6 (а)). Если проход делает несколько запросов к модели (разрезанный ход: резюме региона и контекст начала хода), usage результата SHALL быть суммой usage всех запросов прохода. `compact` SHALL записывать этот usage в `details.usage` записи `compaction` в форме `usage` §8.2.3 (поле описано в §8.2.4), модель — в существующее `details.summaryModel`, а событие `ContextCompacted` SHALL нести `usage` и `model` — строку `<provider>/<id>` (не `ModelRef`); при нескольких проходах (CMP-5) у каждого прохода — своя запись и своё событие. Реплей SHALL брать `usage` из `details.usage`, а `model` — из `details.summaryModel`; без `details.usage` — `usage == null`, без `summaryModel` — `model == null`. Остальные поля `details` и алгоритм «Запись сжатия и пересборка» не меняются.

Usage суммаризатора НЕ SHALL входить в `TurnEnded.usage` — в том числе при аварийном сжатии посреди хода: он учитывается в сумме сессии и в журнале usage (`summaries`). Сбой суммаризатора (`CompactionFailed`) и отмена после ответа записи не пишут, их usage не учитывается.

#### Scenario: /compact с usage
- **WHEN** суммаризатор ответил резюме с usage `{input: 900, output: 120}` модели `openai/gpt-4o-mini`
- **THEN** запись `compaction` содержит `details.usage` с этими числами и стоимостью, а `ContextCompacted` — тот же `usage` и модель (`compaction_usage_test.dart`)

#### Scenario: Разрезанный ход
- **WHEN** точка среза делит ход, и проход делает два запроса к суммаризатору: резюме региона с usage `{input: 900, output: 120}` и контекст начала хода с usage `{input: 300, output: 40}`
- **THEN** одна запись `compaction` с `details.usage` `{input: 1200, output: 160}` и одно `ContextCompacted` с тем же `usage` (`compaction_usage_test.dart`)

#### Scenario: Реплей новой записи
- **WHEN** журнал с записью `compaction`, у которой есть `details.usage` и `details.summaryModel: "openai/gpt-4o-mini"`, открывается и проигрывается
- **THEN** `ContextCompacted` реплея несёт этот `usage` и `model == "openai/gpt-4o-mini"`

#### Scenario: Аварийное сжатие посреди хода
- **WHEN** проверка перед запросом запускает сжатие, и суммаризатор тратит токены
- **THEN** `TurnEnded.usage` хода равен сумме его шагов и детей, без usage суммаризатора; usage суммаризатора есть в записи `compaction`

#### Scenario: Старая запись без usage
- **WHEN** журнал с записью `compaction` без `details.usage` открывается и проигрывается
- **THEN** `ContextCompacted` реплея несёт `usage == null` и `model` из `details.summaryModel`, если оно есть, ошибки чтения нет
