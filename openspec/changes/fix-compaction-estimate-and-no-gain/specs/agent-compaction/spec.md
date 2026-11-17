## ADDED Requirements

### Requirement: Согласованная оценка после сжатия
Компактор SHALL считать оценку контекста после прохода сжатия от той же базы, что и оценку до него (`agent-core-architecture` §9.3; design.md change `fix-compaction-estimate-and-no-gain`, D1):

`after = max(0, before + H(после) − H(до))`,

где `H` — `estimateTokens` без якоря (системный промпт, схемы инструментов и все сообщения проекции), `H(до)` — по проекции `buildLlmContext` снимка перед проходом, `H(после)` — по проекции снимка с ещё не записанной записью `compaction` и приложенным сообщением навыков.

`before` первого прохода SHALL быть `estimateContextTokens` проекции перед проходом (с якорем на usage); `before` второго и третьего прохода SHALL быть `after` предыдущего прохода (D2).

Эта оценка SHALL использоваться для `tokensAfter` записи, `Compacted.tokensAfter`, `ContextCompacted.tokensAfter`, поля `tokens_after` логов `compaction.done` и `compaction.skipped` и проверки выигрыша (требование «Сжатие без выигрыша не применяется»). Без якоря на первом проходе результат SHALL совпадать с `H(после)`.

Сравнения компактора с порогом — проверка CMP-5 и проверки выброса навыков по окну — SHALL идти по `max(after, H(после))` для всех триггеров (D9): `H(после)` — та оценка, которую до следующего ответа модели увидят проверка `preflight` цикла и `afterTurn`, потому что в проекции после сжатия якоря нет.

#### Scenario: Якорь ниже эвристики постоянной части
- **WHEN** последний ответ модели несёт usage, а эвристика системного промпта и схем больше этого usage (как у реального провайдера с компактным токенайзером), и сжатие убирает регион, больший резюме с обёрткой
- **THEN** `tokensAfter` записи меньше `tokensBefore` и равен `tokensBefore + H(после) − H(до)`; `ContextCompacted` и ответ `/compact` несут те же числа

#### Scenario: Без якоря поведение прежнее
- **WHEN** в проекции перед сжатием нет assistant-сообщения с ненулевым `input + cacheRead + cacheWrite`
- **THEN** `tokensBefore` равен `H(до)`, а `tokensAfter` — `H(после)`

#### Scenario: Цепочка проходов
- **WHEN** после первого прохода оценка всё ещё выше порога, и выполняется второй проход
- **THEN** `tokensBefore` второй записи равен `tokensAfter` первой

#### Scenario: Порог проверяется и по эвристике без якоря
- **WHEN** после первого прохода согласованная оценка `after` не выше порога, а `H(после)` выше порога (якорь ниже эвристики промпта и схем больше чем на `reserveTokens`), и регион для следующего прохода есть
- **THEN** выполняется второй проход; компактор останавливается только когда `max(after, H(после))` не выше порога или проходов уже 3

#### Scenario: Аварийное сжатие не теряет ход из-за расхождения оценок
- **WHEN** провайдер вернул `overflow` (или сработал `preflight`), якорь ниже эвристики промпта и схем больше чем на `reserveTokens`, а сжатие способно уложить эвристику проекции в порог за разрешённые проходы
- **THEN** повторный запрос проходит проверку `preflight` без второго аварийного вызова, и ход не завершается ошибкой `overflow` из-за `preflight`

#### Scenario: Нижняя граница
- **WHEN** `H(до) − H(после)` больше `before`
- **THEN** `tokensAfter` равен 0, а не отрицательному числу

### Requirement: Сжатие без выигрыша не применяется
Если согласованная оценка после прохода не меньше оценки до него (`after >= before`), проход SHALL NOT применяться (design.md change `fix-compaction-estimate-and-no-gain`, D3; CMP-10):
- запись `compaction` не пишется, журнал и транскрипт не меняются, `onCompacted` не вызывается;
- `ContextCompacted` не эмитится;
- пишется лог `compaction.skipped` уровня `info` с полями `session_id`, `trigger`, `pass`, `reason: "no reduction"`, `tokens_before`, `tokens_after` и без текста резюме;
- исход первого прохода — `NothingToCompact('no reduction')`; исход следующего прохода — `Compacted` прошлого прохода.

Проход без точки среза SHALL писать тот же лог `compaction.skipped` уровня `info` с полями `session_id`, `trigger`, `pass` и `reason: "no cut point"` — на любом проходе, в том числе когда исход — `Compacted` прошлого прохода.

Проверка SHALL выполняться после проверки отмены и после выбора навыков записи; навыки НЕ SHALL выбрасываться ради появления выигрыша. Записанное сжатие SHALL удовлетворять `tokensAfter < tokensBefore` (CMP-10).

Для `preflight` и `overflow` такой исход SHALL означать «сжатие не помогло» по правилам `agent-loop` (`emergencyCompact` возвращает `null`); вызов считается аварийным вызовом хода (CMP-8). `/compact` SHALL отвечать на него, как на любой `NothingToCompact`, по требованию `agent-slash-commands` «Встроенные команды MVP».

#### Scenario: Резюме длиннее региона
- **WHEN** суммаризатор возвращает резюме, которое вместе с обёрткой оценивается не меньше убранного региона
- **THEN** `compact` возвращает `NothingToCompact('no reduction')`, журнал побайтово не изменился, `ContextCompacted` нет, `onCompacted` не вызван, есть лог `compaction.skipped` с `pass: 1` и `reason: "no reduction"`

#### Scenario: Нет точки среза
- **WHEN** в регионе нет точки среза
- **THEN** `compact` возвращает `NothingToCompact('no cut point')`, суммаризатор не вызван, есть лог `compaction.skipped` с `pass: 1`, `reason: "no cut point"` и без полей оценок

#### Scenario: Навыки не выбрасываются ради выигрыша
- **WHEN** без сообщения навыков проход дал бы выигрыш, а с приложенным сообщением навыков согласованная оценка после не меньше оценки до
- **THEN** проход не применяется, записи `compaction` нет, активации навыков остаются в контексте как были

#### Scenario: Второй проход без выигрыша
- **WHEN** первый проход записан, оценка после него выше порога, а второй проход выигрыша не даёт
- **THEN** в журнале одна новая запись `compaction`, `ContextCompacted` один, результат — `Compacted` первого прохода, есть лог `compaction.skipped` с `pass: 2`

#### Scenario: /compact без выигрыша
- **WHEN** пользователь отправляет `/compact`, а резюме не уменьшает оценку контекста
- **THEN** ответ — `Nothing to compact.`, суммаризатор вызван один раз, записи `compaction` в журнале нет, `TurnEnded` с `endTurn`

#### Scenario: Аварийное сжатие без выигрыша
- **WHEN** провайдер вернул `overflow`, а аварийный проход сжатия выигрыша не дал
- **THEN** записи `compaction` нет, повтора запроса нет, шаг завершается ошибкой `overflow`, ход — `TurnEnded(failed)`, второго сжатия в этом ходе нет

## MODIFIED Requirements

### Requirement: Запись сжатия и пересборка
`compact(snapshot, trigger, ...)` SHALL выполнять алгоритм §9.8:
1. регион и точка среза; нет среза → `NothingToCompact('no cut point')` и лог `compaction.skipped` с `reason: "no cut point"`;
2. резюме; `CompactionFailed` → лог `compaction.failed`, `AgentError(cls: compaction, retrying: false)`, журнал и транскрипт не меняются (CMP-3);
3. проверка отмены после ответа модели;
4. оценка после прохода — по требованию «Согласованная оценка после сжатия» по проекции с ещё не записанной записью и приложенным сообщением навыков;
5. нет выигрыша (`after >= before`) → проход не применяется по требованию «Сжатие без выигрыша не применяется»;
6. запись `compaction` с `summary`, `firstKeptId`, `tokensBefore`, `tokensAfter` (оценка шага 4) и `details` (прочитанные и изменённые файлы, `splitTurn`, модель резюме);
7. `append` с `durable`;
8. транскрипт сессии := сообщения `buildLlmContext`;
9. `ContextCompacted(tokensBefore, tokensAfter)`;
10. если `max(оценка шага 4, H(после))` всё ещё выше порога — следующий проход, всего не более 3 (CMP-5, D9); `before` следующего прохода — `tokensAfter` этого.

Сжатие НЕ SHALL удалять или менять записи журнала (CMP-2). Записанное сжатие SHALL уменьшать оценку контекста: `tokensAfter < tokensBefore` (CMP-10).

#### Scenario: Ошибка суммаризатора
- **WHEN** суммаризатор возвращает `ErrorEvent`
- **THEN** журнал побайтово не изменился, транскрипт тот же, в событиях есть `AgentError(cls: compaction)`

#### Scenario: Отмена посреди генерации
- **WHEN** токен отменяется, пока суммаризатор отвечает
- **THEN** `compact` бросает `CancelledException`, записи `compaction` нет

#### Scenario: Записанное сжатие уменьшает оценку
- **WHEN** проход сжатия записан
- **THEN** `tokensAfter` записи меньше её `tokensBefore`, а `ContextCompacted` несёт те же числа
