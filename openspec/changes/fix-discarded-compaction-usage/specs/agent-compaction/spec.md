## ADDED Requirements

### Requirement: Учёт вызова суммаризатора отброшенного прохода
Если проход сжатия не применяется по CMP-10 (требование «Сжатие без выигрыша не применяется» change `fix-compaction-estimate-and-no-gain`), а суммаризатор уже ответил, `compact` SHALL дописать в журнал одну запись `custom` с `customType: "codelab.compaction_discarded"` (design.md change `fix-discarded-compaction-usage`, D1; решение пользователя Q1 (а)). Это уточняет то требование: кроме этой записи журнал не меняется, а проекция `buildLlmContext`, транскрипт, `onCompacted` и исход прохода — те же, что без неё.

`data` записи SHALL содержать:
- `usage` — usage суммаризатора в форме `usage` §8.2.3; если проход делал несколько запросов, это их сумма (требование «Usage суммаризатора» change `add-usage-ledger`);
- `summaryModel` — `<provider>/<id>` модели ответа, только если она известна;
- `reason: "no reduction"`;
- `trigger`, `pass`, `tokensBefore`, `tokensAfter` — согласованные оценки прохода.

Текста резюме запись НЕ SHALL содержать. Запись SHALL идти обычным `append` без `durable` после проверки отмены, выбора навыков и проверки выигрыша. Сбой записи SHALL уходить из `compact` так же, как сбой записи `compaction` (SES-8).

После успешной записи ядро SHALL эмитить событие `CompactionDiscarded` с `tokensBefore`, `tokensAfter`, `usage` и `model` (строка `<provider>/<id>` или `null`; D2). `ContextCompacted` для такого прохода НЕ SHALL эмититься. Usage вызова НЕ SHALL входить в `TurnEnded.usage`, в том числе на аварийном пути. Реплей журнала НЕ SHALL давать `CompactionDiscarded`.

Проход без точки среза, сбой суммаризатора (`CompactionFailed`) и отмена записи учёта и события НЕ SHALL давать (R3 change `add-usage-ledger`; Q5). Лог `compaction.skipped` с `reason: "no reduction"` SHALL дополнительно нести `usage_record_id` (id записи учёта) и `summary_model` (если модель известна). Токенов и денег в логе нет (D6).

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

#### Scenario: Запись учёта в регионе следующего сжатия
- **WHEN** после отброшенного прохода сессия продолжается, и следующее сжатие получает запись учёта в регион
- **THEN** точка среза и запрос суммаризатора те же, что без этой записи; сжатие записывается без ошибок

#### Scenario: Реплей
- **WHEN** журнал с записью учёта открывается и проигрывается
- **THEN** реплей не даёт `CompactionDiscarded` и кадров для этой записи; ошибки чтения нет

#### Scenario: Старое ядро читает новую запись
- **WHEN** журнал с записью `custom` `codelab.compaction_discarded` открывает читатель, который этот `customType` не знает
- **THEN** сессия открывается, запись сохраняется по правилу `custom` (§8.2.4), контекст модели тот же, что без неё
