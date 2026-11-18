## ADDED Requirements

### Requirement: Учёт вызова суммаризатора отброшенного прохода
Если проход сжатия не применяется по CMP-10 (требование «Сжатие без выигрыша не применяется» change `fix-compaction-estimate-and-no-gain`) или его запись `compaction` не пишется с исходом `stale` по CMP-12 (требование «Запись сжатия ложится на текущий лист» change `fix-config-change-during-background-compaction`; решение пользователя Q6 (а)), а суммаризатор уже ответил, `compact` SHALL дописать в журнал одну запись `custom` с `customType: "codelab.compaction_discarded"` (design.md change `fix-discarded-compaction-usage`, D1; решение пользователя Q1 (а)). Это уточняет то требование: кроме этой записи журнал не меняется, а проекция `buildLlmContext`, транскрипт, `onCompacted` и исход прохода — те же, что без неё.

`data` записи SHALL содержать:
- `usage` — usage суммаризатора в форме `usage` §8.2.3; если проход делал несколько запросов, это их сумма (требование «Usage суммаризатора» change `add-usage-ledger`);
- `summaryModel` — `<provider>/<id>` модели ответа (всегда: `SummaryResult.model` не бывает `null`);
- `reason` — `"no reduction"` или `"stale"`;
- `trigger`, `pass`, `tokensBefore`, `tokensAfter` — согласованные оценки прохода.

Текста резюме запись НЕ SHALL содержать. Запись SHALL идти через `SessionWriter.append` без `durable` (родитель — лист в очереди писателя, SES-16), после проверки отмены, выбора навыков и проверки выигрыша, а для `stale` — после того, как построитель `appendWith` проверил отмену и вернул `null` из-за `stale`; проверка CMP-12 к записи учёта не применяется. Отмена хода или закрытие сессии, пришедшие после проверки выигрыша (для `stale` — после проверки в построителе), запись учёта и событие НЕ SHALL отменять: оплаченный вызов учитывается, а `/compact` отвечает прежним текстом `Nothing to compact.`; stopReason ответа на `session/prompt` определяет мост по правилам отмены ACP (при `session/cancel` — `cancelled`, ACP-5) (решение пользователя Q9 (а), уточнено по ACP-5). Сбой записи SHALL уходить из `compact` так же, как сбой записи `compaction` (SES-8).

После успешной записи ядро SHALL эмитить событие `CompactionDiscarded` с `tokensBefore`, `tokensAfter`, `usage` и `model` (строка `<provider>/<id>`, не `null`; D2). `ContextCompacted` для такого прохода НЕ SHALL эмититься. Usage вызова НЕ SHALL входить в `TurnEnded.usage`, в том числе на аварийном пути. Реплей журнала НЕ SHALL давать `CompactionDiscarded`.

Проход без точки среза, сбой суммаризатора (`CompactionFailed`), отмена после ответа суммаризатора и отмена, пришедшая, пока запись `compaction` ждала очереди писателя (CMP-12), записи учёта и события НЕ SHALL давать (R3 change `add-usage-ledger`; решение пользователя Q5 (а)). Лог `compaction.skipped` с `reason: "no reduction"` или `"stale"` SHALL дополнительно нести `usage_record_id` (id записи учёта) и `summary_model`. Токенов и денег в логе нет (D6).

#### Scenario: /compact без выигрыша записывает учёт
- **WHEN** пользователь отправляет `/compact`, суммаризатор модели `openai/gpt-4o-mini` отвечает резюме длиннее региона с usage `{input: 764, output: 171}`
- **THEN** ответ — `Nothing to compact.`; в журнале ровно одна новая запись — `custom` `codelab.compaction_discarded` с `data.usage` с этими числами, `data.summaryModel: "openai/gpt-4o-mini"`, `data.reason: "no reduction"`, `data.trigger: "manual"`, `data.pass: 1` и без текста резюме; записей `compaction` нет; сообщения `buildLlmContext` до и после совпадают; эмитится `CompactionDiscarded` с тем же usage и моделью, `ContextCompacted` нет; лог `compaction.skipped` несёт `usage_record_id` этой записи (`compactor_test.dart`, `builtin_slash_commands_test.dart`)

#### Scenario: Второй проход без выигрыша
- **WHEN** первый проход записан, оценка после него выше порога, а второй проход выигрыша не даёт
- **THEN** в журнале новая запись `compaction` первого прохода, за ней запись учёта с `data.pass: 2`; эмитятся один `ContextCompacted` и один `CompactionDiscarded`; исход — `Compacted` первого прохода

#### Scenario: Аварийное сжатие без выигрыша
- **WHEN** провайдер вернул `overflow`, а аварийный проход выигрыша не дал
- **THEN** в журнале запись учёта с `data.trigger: "overflow"`; повтора запроса нет, ход — `TurnEnded(failed)`, и его `usage` не включает usage суммаризатора (`overflow_then_compact_test.dart`)

#### Scenario: Нет точки среза
- **WHEN** в регионе нет точки среза
- **THEN** суммаризатор не вызван, записи учёта и `CompactionDiscarded` нет

#### Scenario: Сбой и отмена
- **WHEN** суммаризатор завершился ошибкой или токен отменён после его ответа
- **THEN** записи учёта и `CompactionDiscarded` нет; журнал побайтово не изменился

#### Scenario: Устаревший проход
- **WHEN** пока суммаризатор отвечает, на активную ветку записано сообщение (подставной журнал), и `appendWith` записи `compaction` возвращает `null`
- **THEN** исход — `NothingToCompact('stale')`; записи `compaction` нет; в журнале одна новая запись учёта с `data.reason: "stale"` и `parentId` — текущий лист; эмитится `CompactionDiscarded`, `ContextCompacted` нет; лог `compaction.skipped` (`warning`, `reason: "stale"`) несёт `usage_record_id`

#### Scenario: Смена режима во время резюме прохода без выигрыша
- **WHEN** пока суммаризатор отвечает, в журнал записан `mode_change`, а затем проход отброшен по CMP-10
- **THEN** запись учёта имеет `parentId` = id этого `mode_change`, лист — запись учёта, `pathToLeaf` содержит `mode_change`; после `loadSession` режим — новый

#### Scenario: Запись учёта в регионе следующего сжатия
- **WHEN** после отброшенного прохода сессия продолжается, и следующее сжатие получает запись учёта в регион
- **THEN** точка среза и запрос суммаризатора те же, что без этой записи; сжатие записывается без ошибок

#### Scenario: Реплей
- **WHEN** журнал с записью учёта открывается и проигрывается
- **THEN** реплей не даёт `CompactionDiscarded` и кадров для этой записи; ошибки чтения нет

#### Scenario: Старое ядро читает новую запись
- **WHEN** журнал с записью `custom` `codelab.compaction_discarded` открывает читатель, который этот `customType` не знает
- **THEN** сессия открывается, запись сохраняется по правилу `custom` (§8.2.4), контекст модели тот же, что без неё

## MODIFIED Requirements

### Requirement: Сжатие без выигрыша не применяется
Если согласованная оценка после прохода не меньше оценки до него (`after >= before`), проход SHALL NOT применяться (design.md change `fix-compaction-estimate-and-no-gain`, D3; CMP-10):
- запись `compaction` не пишется, транскрипт не меняется, `onCompacted` не вызывается; журнал меняется только записью учёта вызова суммаризатора `custom` `codelab.compaction_discarded` (требование «Учёт вызова суммаризатора отброшенного прохода»; design.md change `fix-discarded-compaction-usage`, D1);
- `ContextCompacted` не эмитится; после записи учёта эмитится `CompactionDiscarded` (D2 change `fix-discarded-compaction-usage`);
- пишется лог `compaction.skipped` уровня `info` с полями `session_id`, `trigger`, `pass`, `reason: "no reduction"`, `tokens_before`, `tokens_after`, `usage_record_id` (id записи учёта), `summary_model` и без текста резюме (D6 change `fix-discarded-compaction-usage`);
- исход первого прохода — `NothingToCompact('no reduction')`; исход следующего прохода — `Compacted` прошлого прохода.

Проход без точки среза SHALL писать тот же лог `compaction.skipped` уровня `info` с полями `session_id`, `trigger`, `pass` и `reason: "no cut point"` — на любом проходе, в том числе когда исход — `Compacted` прошлого прохода.

Проверка SHALL выполняться после проверки отмены и после выбора навыков записи; навыки НЕ SHALL выбрасываться ради появления выигрыша. Записанное сжатие SHALL удовлетворять `tokensAfter < tokensBefore` (CMP-10).

Для `preflight` и `overflow` такой исход SHALL означать «сжатие не помогло» по правилам `agent-loop` (`emergencyCompact` возвращает `null`); вызов считается аварийным вызовом хода (CMP-8). `/compact` SHALL отвечать на него, как на любой `NothingToCompact`, по требованию `agent-slash-commands` «Встроенные команды MVP».

#### Scenario: Резюме длиннее региона
- **WHEN** суммаризатор возвращает резюме, которое вместе с обёрткой оценивается не меньше убранного региона
- **THEN** `compact` возвращает `NothingToCompact('no reduction')`, в журнале одна новая запись — запись учёта `codelab.compaction_discarded`, сообщения `buildLlmContext` до и после совпадают, `ContextCompacted` нет, `onCompacted` не вызван, есть лог `compaction.skipped` с `pass: 1` и `reason: "no reduction"`

#### Scenario: Нет точки среза
- **WHEN** в регионе нет точки среза
- **THEN** `compact` возвращает `NothingToCompact('no cut point')`, суммаризатор не вызван, есть лог `compaction.skipped` с `pass: 1`, `reason: "no cut point"` и без полей оценок

#### Scenario: Навыки не выбрасываются ради выигрыша
- **WHEN** без сообщения навыков проход дал бы выигрыш, а с приложенным сообщением навыков согласованная оценка после не меньше оценки до
- **THEN** проход не применяется, записи `compaction` нет, активации навыков остаются в контексте как были

#### Scenario: Второй проход без выигрыша
- **WHEN** первый проход записан, оценка после него выше порога, а второй проход выигрыша не даёт
- **THEN** в журнале одна новая запись `compaction`, за ней запись учёта с `data.pass: 2`, `ContextCompacted` один, результат — `Compacted` первого прохода, есть лог `compaction.skipped` с `pass: 2`

#### Scenario: /compact без выигрыша
- **WHEN** пользователь отправляет `/compact`, а резюме не уменьшает оценку контекста
- **THEN** ответ — `Nothing to compact.`, суммаризатор вызван один раз, записи `compaction` в журнале нет, `TurnEnded` с `endTurn`

#### Scenario: Аварийное сжатие без выигрыша
- **WHEN** провайдер вернул `overflow`, а аварийный проход сжатия выигрыша не дал
- **THEN** записи `compaction` нет, повтора запроса нет, шаг завершается ошибкой `overflow`, ход — `TurnEnded(failed)`, второго сжатия в этом ходе нет
