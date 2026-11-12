## ADDED Requirements

### Requirement: Заполнение контекста после шага
`StepEnded` SHALL нести заполнение контекста после шага (design.md change `add-usage-extension`, D5): `used` — оценка `estimateContextTokens` контекста цикла после добавления результатов инструментов этого шага с якорем на usage только что полученного ответа; `window` — `effectiveContextWindow` модели следующего запроса с `AgentLoopConfig.contextWindowCap`; `compactAt` — порог автосжатия `afterTurn` в токенах по тому же правилу, что проверка `shouldCompact` рантайма, переданный циклу рантаймом, или `null` при выключенном автосжатии. Без оценщика `AgentLoopConfig.estimateTokens` поле SHALL быть `null`. Вычисление НЕ SHALL обращаться к провайдеру и НЕ SHALL менять транскрипт, журнал и бюджет хода.

#### Scenario: Шаг с инструментом
- **WHEN** ответ шага имеет usage `input 41000, cacheRead 9000, output 600`, а результат `read` — 12 000 символов
- **THEN** `StepEnded` несёт `used = 50600 + оценка результата` (по правилу `agent-compaction` «Оценка токенов с якорем на usage») и `window`, равное окну модели с учётом `contextWindowCap`

#### Scenario: Цикл без оценщика
- **WHEN** `AgentLoopConfig.estimateTokens` не задан
- **THEN** заполнение контекста в `StepEnded` — `null`, остальные поля события прежние

#### Scenario: Автосжатие выключено
- **WHEN** сессия собрана без сжатия контекста
- **THEN** `StepEnded` несёт `used` и `window`, а `compactAt` — `null`
