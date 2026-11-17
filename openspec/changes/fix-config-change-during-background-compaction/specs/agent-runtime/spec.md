## ADDED Requirements

### Requirement: Смена конфигурации во время сжатия сохраняется в журнале
`setMode`, `setModel`, `setEffort` и `setAgent`, вызванные, пока идёт сжатие контекста — фоновое `afterTurn`, ручное `/compact` или аварийное `preflight`/`overflow` внутри хода, — SHALL оставлять свои записи (`mode_change`, `model_change`, `config_change`) на активной ветке журнала, так что `loadSession` восстанавливает значение последней смены (design.md change `fix-config-change-during-background-compaction`, D1, D2).

Смена конфигурации НЕ SHALL ждать завершения сжатия и НЕ SHALL отменять его (D4): вызов завершается так же, как вне сжатия. Сжатие, во время которого прошла смена, SHALL быть записано (требование agent-compaction «Запись сжатия ложится на текущий лист»), а транскрипт после него — тем же, что без смены.

#### Scenario: Режим во время фонового сжатия
- **WHEN** после хода идёт фоновое `afterTurn`-сжатие, суммаризатор ещё не ответил, вызывается `setMode(plan)` и завершается, затем суммаризатор отвечает, сессия закрывается и открывается `loadSession`
- **THEN** `setMode` завершился до ответа суммаризатора; в журнале одна запись `compaction` на активной ветке; после `loadSession` режим — `plan`

#### Scenario: Модель во время фонового сжатия
- **WHEN** во время фонового `afterTurn`-сжатия вызывается `setModel` на другую модель каталога
- **THEN** после `loadSession` модель сессии — выбранная, лога `session.model.not_restored` нет

#### Scenario: Уровень рассуждения во время фонового сжатия
- **WHEN** во время фонового `afterTurn`-сжатия вызывается `setEffort(high)`
- **THEN** после `loadSession` `effort == high`

#### Scenario: Агент во время фонового сжатия
- **WHEN** во время фонового `afterTurn`-сжатия вызывается `setAgent` с определением, задающим режим и модель
- **THEN** после `loadSession` активен этот агент, режим и модель — его

#### Scenario: Режим во время ручного сжатия
- **WHEN** идёт `/compact`, суммаризатор ещё не ответил, вызывается `setMode(plan)`
- **THEN** ответ `/compact` — `Compacted: …`; после `loadSession` режим — `plan`

#### Scenario: Модель во время аварийного сжатия
- **WHEN** провайдер ответил `overflow`, идёт аварийное сжатие, и в это время вызывается `setModel`
- **THEN** ход завершается `TurnEnded(completed)` с одной записью `compaction`; после `loadSession` модель — выбранная
