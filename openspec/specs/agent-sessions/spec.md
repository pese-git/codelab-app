# agent-sessions Specification

## Purpose
Журнал сессии Dart-агента: append-only JSONL-дерево записей с `parentId` и листом — единственный источник истории. Порт `SessionStore` и хранилища `MemorySessionStore` и `JsonlSessionStore`, запись журнала из событий цикла, открытие с карантином битых строк и ремонтом, проекции для контекста модели и реплея `session/load`, продолжение прерванного хода без повторного вызова инструментов, список сессий и автоматический заголовок (`agent-core-architecture` §8).
## Requirements
### Requirement: Формат журнала JSONL
Журнал сессии SHALL быть UTF-8 файлом: одна JSON-запись на строку, разделитель `\n` (§8.2 документа ядра). Пустые строки при чтении пропускаются; логическая структура задаётся `parentId`, а не позицией строки.

Первая строка SHALL быть заголовком `{"type":"session","version":1,...}` с полями `id`, `cwd`, `created`, `agent` и необязательным `metadata` (§8.2.1). Заголовок не входит в дерево.

Записи этапа 3:
- `message` с сообщением в канонической JSON-форме §2.2 и полями записи `outcome`, `diff`, `toolMeta`, `origin`;
- `model_change`, `mode_change`, `config_change`, `plan`, `compaction`, `label`, `leaf`, `session_info`, `custom` (§8.2.4).

Поля записи (`outcome`, `diff`, `toolMeta`, `origin` и сопутствующие) SHALL лежать на верхнем уровне объекта рядом с общими полями и НЕ SHALL попадать в сообщение, которое видит модель.

Читатель SHALL:
- игнорировать неизвестные поля заголовка известной версии;
- сохранять неизвестные поля известной записи в `extra` и записывать их обратно при копировании;
- читать запись неизвестного `type` как `CustomRecord("unknown:<type>")` с исходным объектом (design.md, D2).

Решения «разрешить всегда», частичные снимки ответа, дельты и `ToolCallProgress` НЕ SHALL попадать в журнал.

#### Scenario: Golden-разбор
- **WHEN** `parseSessionLines` разбирает фикстуру `test/fixtures/sessions/all_records.jsonl`, где есть каждая запись MVP
- **THEN** каждая запись разобрана в свой тип, `toJson` каждой записи побайтово равен исходной строке

#### Scenario: Неизвестный тип записи
- **WHEN** в журнале встречается строка с `"type":"branch"`
- **THEN** она читается как `CustomRecord("unknown:branch")`, не участвует в проекциях и пишется обратно без изменений

### Requirement: Идентификаторы и дерево записей
`SessionId` SHALL иметь формат ULID: 10 символов времени по `Clock` хоста и 16 символов Crockford base32 из `IdGenerator.nextChars` (§8.4, design.md, D3). Тот же id уходит в ACP как `sessionId`.

`RecordId` SHALL состоять из 8 символов `0-9a-z` из `IdGenerator.nextChars`. При совпадении с id снимка id выдаётся заново, не более 16 раз, затем выдаётся 12 символов. Id записи не переиспользуется и не меняется; ссылки (`parentId`, `targetId`, `firstKeptId`) — только по id (SES-3).

Правила дерева:
- новая запись получает `parentId` = текущий лист (первая запись — `null`);
- лист после обычной записи — её `id`, после записи `leaf` — её `targetId`;
- активная ветка — путь от листа к корню по `parentId` в порядке root-first.

`pathToLeaf` SHALL завершаться на цикле `parentId` (лог `session.cycle`) и на отсутствующем родителе (лог `session.broken_link`) и НЕ SHALL проходить больше записей, чем есть в снимке.

#### Scenario: Запись `leaf` переключает ветку
- **WHEN** после ответа модели записан `leaf` с `targetId` первого сообщения пользователя, а затем новое сообщение
- **THEN** новое сообщение — сиблинг первого ответа, и `pathToLeaf` возвращает ветку без него

#### Scenario: Цикл родителей
- **WHEN** записи `a` и `b` ссылаются друг на друга через `parentId`
- **THEN** `pathToLeaf` завершается и пишет лог `session.cycle`

### Requirement: Слова пользователя
Решение «этот текст написал пользователь» по записи журнала SHALL принимать только `isUserWords`, а по событию — `isUserWordsEvent` (§8.2.5, SES-14):
- запись не `message` или роль не `user` → `false`;
- запись `user` без `origin` → `true`;
- известный `origin` → по `classifyOrigin`: `steer` и `parent_message` — слова пользователя, остальные значения `RecordOrigin` — служебные;
- неизвестный `origin` → `false` и одно предупреждение `session.origin.unknown` на значение за процесс.

Классификация SHALL быть полной: каждый элемент `RecordOrigin` и каждый подкласс `MessageOrigin` имеют явный класс (SES-15). Сообщение с неизвестным `origin` остаётся в контексте модели.

#### Scenario: Полнота классификации
- **WHEN** `user_words_test.dart` проходит таблицу всех записей фикстуры `all_origins.jsonl`
- **THEN** ответ совпадает с ожидаемым для каждой строки, а таблица ожиданий содержит строку на каждый элемент `RecordOrigin.values`

#### Scenario: Подсказка цикла не слова пользователя
- **WHEN** запись `user` имеет `origin: "loop_nudge"`
- **THEN** `isUserWords` возвращает `false`, а `buildLlmContext` включает сообщение в контекст

### Requirement: Порт SessionStore
Хранилище журнала SHALL реализовывать порт `SessionStore` (§8.3):
- `create(header)` — новый журнал с заголовком; существующий id → `StateError`;
- `append(id, record, {durable})` — одна полная строка за операцию;
- `flush(id)` — сброс записанного на носитель без новой записи (конец хода);
- `open(id)` — чтение, ремонт и снимок `SessionSnapshot`; нет журнала → `SessionNotFound`;
- `list({cwd, cursor, pageSize})` — страница сводок;
- `close(id)` — дождаться очереди записи и закрыть дескриптор.

`SessionSnapshot` содержит заголовок, записи в порядке файла, `byId` (первая копия id выигрывает), `leafId` и `RepairReport` (`quarantinedLines`, `headerMissing`, `healedLeafFrom`, `brokenLinks`, `interruptedToolCalls`, `isClean`).

Разбор, дерево, ремонт в памяти и проекции SHALL жить в ядре, чтобы хранилища отвечали только за байты и вели себя одинаково (§8.1). `MemorySessionStore` SHALL проходить тот же контрактный набор тестов, что и файловое хранилище.

#### Scenario: Контрактный набор
- **WHEN** общий набор `session_store_contract.dart` прогоняется на `MemorySessionStore`
- **THEN** `create`, `append`, `flush`, `open`, `list` и `close` ведут себя по контракту, а повторный `create` с тем же id даёт `StateError`

### Requirement: Запись журнала из событий
`SessionWriter` SHALL быть первым подписчиком `Agent` сессии и писать журнал по таблице §8.3 в объёме этапа 3 (design.md, D2, D4):

| Событие | Запись | `durable` |
|---|---|---|
| `MessageEnded` (user, assistant) | `message`; у служебных сообщений — `origin` из `MessageStarted.origin` | нет |
| `MessageEnded` (toolResult) | `message` с `outcome`, `diff`, `toolMeta` вызова | да |
| `ModeChanged` | `mode_change` | нет |
| `PlanUpdated` | `plan` | нет |
| `ContextCompacted` | `compaction` пишется компактором до события | да |
| `SessionTitleChanged` | `session_info` | нет |
| `TurnEnded` | ничего; сброс последней записи хода | да |

Каждое сообщение транскрипта SHALL быть записано до перехода цикла к следующему действию (SES-8). Результат каждого инструмента SHALL быть записан с `durable` до следующего запроса к модели (SES-9). Индекс снимка в памяти обновляется только после успешной записи.

Ошибка записи SHALL давать лог `session.append.failed`, `AgentError(cls: storage, retrying: false)` и `TurnEnded(failed)`: ход, который нельзя сохранить, не продолжается (design.md, D4).

#### Scenario: Побайтово одинаковый журнал
- **WHEN** один сценарий с вызовами `read` и `edit` дважды выполняется на `FakeClock` и `SequentialIdGenerator`
- **THEN** оба журнала побайтово равны (`deterministic_journal_test.dart`, PKG-6)

#### Scenario: Ошибка записи завершает ход
- **WHEN** хранилище возвращает ошибку на записи результата инструмента
- **THEN** эмитится `AgentError(cls: storage)`, ход завершается `TurnEnded(failed)`, следующий запрос к модели не делается

### Requirement: Открытие и ремонт журнала
`open(id)` SHALL выполнять алгоритм §8.6 документа ядра (S-01):
- **неизвестная версия заголовка** → `SessionOpenException(unsupportedVersion)`, файл побайтово не меняется (SES-2);
- **нет заголовка** → заголовок синтезируется в памяти (`headerMissing`), в файл не дописывается;
- **строка не разбирается** (оборванная, мусор, не объект, нет `id`) и **дубликат id** → строка уходит в файл-карантин `<file>.corrupt` строкой `{"line", "text", "reason", "at"}`;
- **после карантина** основной файл переписывается из заголовка и уцелевших строк через `<file>.tmp` и `rename`; если оборвана только последняя строка, файл вместо этого усекается до конца последней целой строки;
- **лист указывает на отсутствующий id** → лист — последняя уцелевшая запись не `leaf` (`healedLeafFrom`, лог `session.leaf.healed`), в файл ничего не пишется (SES-6);
- **`brokenLinks`** — число записей с ненайденным `parentId`.

Переписывание при карантине SHALL быть единственным изменением существующих строк (SES-1). Оборванная последняя строка НЕ SHALL мешать открыть сессию (SES-5).

#### Scenario: Обрыв посреди строки
- **WHEN** журнал обрезан посреди последней строки ответа модели
- **THEN** сессия открывается, все целые записи на месте, `.corrupt` содержит одну строку с `reason: truncated`, `quarantinedLines == 1`, а следующая запись прикрепляется к последней целой записи

#### Scenario: Мусор в середине
- **WHEN** строка `{oops` стоит между двумя записями
- **THEN** она уходит в `.corrupt`, остальные записи на месте, файл переписан через `.tmp`

#### Scenario: Неизвестная версия
- **WHEN** заголовок содержит `"version":2`
- **THEN** `open` бросает `SessionOpenException(unsupportedVersion)`, файл побайтово не изменён

### Requirement: JsonlSessionStore пакета codelab_agent_io
`JsonlSessionStore` SHALL реализовывать `SessionStore` на `dart:io` (§8.5, §8.9, design.md, D7):
- файл — `<root>/<cwdSlug(cwd)>/<created в ISO-8601 UTC, ':' и '.' заменены на '-'>_<sessionId>.jsonl`; `root` передаёт хост;
- одна запись — один вызов `write` строки с завершающим `\n`; строка с `\n` или `\r` внутри — `StateError`;
- очередь записи на путь общая для процесса: параллельные `append` не перемешивают байты (SES-4);
- `fsync` по политике `FsyncPolicy`: `checkpoints` (по умолчанию) — только для `durable`, `always` — после каждой записи, `never` — никогда;
- ошибка операции закрывает дескриптор и уходит вызывающему; следующая операция не наследует сбой;
- `list` кеширует сводки в `<root>/index.json` по размеру и `mtime` файла; повреждённый кеш игнорируется и пересоздаётся.

`cwdSlug` SHALL быть «последние два сегмента пути, очищенные до `[A-Za-z0-9._-]` и 48 символов» плюс `-` и FNV-1a 32 бит от UTF-8 байтов пути (§8.9); результат одинаков на Dart VM и в dart2js.

#### Scenario: Сто параллельных записей
- **WHEN** 100 `append` одной сессии запускаются без ожидания друг друга
- **THEN** в файле 100 разбираемых строк, у каждой уникальный id

#### Scenario: Разные слаги для похожих путей
- **WHEN** вычисляются слаги `/a/b-c` и `/a-b/c`
- **THEN** они различаются, а повторное вычисление даёт те же значения

### Requirement: Проекции журнала
Проекции SHALL быть чистыми функциями ядра над снимком (§8.3):
- `buildLlmContext` — алгоритм §8.7: путь до листа; последние `model_change`, `mode_change`, `config_change`; после последнего `compaction` — резюме как user-сообщение по `compaction/summary_wrapper.md` вместо записей до `firstKeptId`; usage assistant-сообщений до сжатия в проекции заменяется на `Usage.zero`, в журнале остаётся как был. Ремонт парности проекция не делает;
- `buildReplay` — события `AgentEvent` активной ветки для `session/load` (design.md, D4); служебные user-сообщения пропускаются;
- `summarize` — сводка §8.10: заголовок из последней `session_info` с непустым `title`, иначе из первой записи со словами пользователя (пробелы схлопнуты, 80 символов по границе слова с `…`); `updatedAt`, `messageCount`, `lastTurnFailed`.

`buildLlmContext` SHALL быть детерминирован: одинаковый снимок даёт одинаковый список сообщений (SES-7).

#### Scenario: Обнуление usage после сжатия
- **WHEN** в снимке есть запись `compaction`
- **THEN** assistant-сообщения до неё в проекции имеют `Usage.zero`, а в файле — исходный usage

#### Scenario: Заголовок из первого сообщения
- **WHEN** первое сообщение пользователя — «Почини   тест   парсера» и `session_info` нет
- **THEN** `summarize` возвращает заголовок `Почини тест парсера`

### Requirement: Продолжение прерванного хода
`healInterruptedTurn` SHALL находить вызовы последнего assistant-сообщения ветки без результата и строить для каждого синтетическую запись `toolResult` с `outcome: "interrupted"`, `isError: true`, `toolMeta` вызова и текстом §8.8 (S-13). `AgentSession` SHALL записать их с `durable` сразу после `open()`, до реплея и до любого нового шага; `RepairReport.interruptedToolCalls` содержит их `toolCallId` (SES-10).

Вызовы с результатом НЕ SHALL повторяться; прерванный вызов НЕ SHALL перезапускаться автоматически. Сессия после загрузки — в состоянии `idle`; следующий `prompt()` видит полную историю (SES-9).

#### Scenario: Сбой после инструмента
- **WHEN** ход выполнил `write a.txt`, начал долгий `exec`, и процесс остановился до результата `exec`
- **THEN** после `loadSession` у `write` результат из журнала, у `exec` — синтетический `interrupted`; после `prompt("продолжай")` счётчик вызовов `write` равен 1, а запрос к модели содержит обе пары вызов-результат

#### Scenario: Прерванный вызов не повторяется
- **WHEN** сессия с прерванным вызовом открывается дважды подряд
- **THEN** синтетический результат дописан один раз, инструмент не вызывался

### Requirement: Список сессий и автоматический заголовок
`list(cwd, cursor, pageSize)` SHALL выполнять шаги §8.10:
- перечислить `*.jsonl` каталогов слагов без рекурсии;
- оставить сводки с `header.cwd == cwd`, если `cwd` задан;
- сортировать по `updatedAt` по убыванию, при равенстве — по `id` по убыванию;
- курсор — base64url от `{"v":1,"after":"<updatedAt>|<id>"}`; страница — первые `pageSize` элементов строго после курсора, `nextCursor` — если остались;
- неразбираемый курсор → `InvalidCursor`.

После первого `TurnEnded` хода, в котором есть запись со словами пользователя, при отсутствии `session_info` с непустым `title` `AgentSession` SHALL записать `session_info` с заголовком по правилу `summarize` и `source: "auto"` и эмитить `SessionTitleChanged` (S-05, design.md, D6). Ход только из служебных сообщений заголовка не создаёт.

#### Scenario: Фильтр и сортировка
- **WHEN** две сессии созданы в `/a` и одна в `/b`
- **THEN** `list(cwd: "/a")` возвращает две, более новую первой

#### Scenario: Неверный курсор
- **WHEN** `list` получает курсор `not-a-cursor`
- **THEN** вызов завершается `InvalidCursor`

#### Scenario: Автоматический заголовок
- **WHEN** первый ход «Почини тест парсера» завершён
- **THEN** эмитится `SessionTitleChanged` с непустым заголовком, в журнале есть `session_info` с `source: "auto"`, а `list()` возвращает тот же заголовок

### Requirement: Поле записи command
Запись `message` с ролью `user`, полученная разворачиванием шаблона команды, SHALL нести необязательное поле записи `command` — объект `{"source": "template", "name": <string>, "args": <string>}` (§8.2.3; design.md change `add-agent-project-files`, D8). Поле НЕ SHALL входить в `Message` и в контекст модели. Запись без поля SHALL читаться как раньше. Неизвестное значение `source` SHALL сохраняться при чтении и записи без потери (совместимость вперёд), а реплей для такой записи SHALL показывать развёрнутый текст.

#### Scenario: Запись и чтение
- **WHEN** сессия разворачивает `/review lib` и журнал перечитывается `parseRecord`
- **THEN** запись сообщения содержит `command: {"source":"template","name":"review","args":"lib"}`, а `buildLlmContext` отдаёт модели только развёрнутый текст

#### Scenario: Неизвестный источник
- **WHEN** журнал содержит запись с `command.source: "plugin"`
- **THEN** запись читается без ошибки, поле сохраняется при повторной записи, реплей показывает текст сообщения

### Requirement: Заголовок сессии из команды
Для записи `message` с полем `command` и известным `source` заголовок сессии SHALL строиться по исходному тексту `/<name>` (или `/<name> <args>` при непустом `args`), как реплей, а не по развёрнутому телу: в `summarize`, в `session/list` и в автоматическом `session_info` с `source: "auto"` (а значит и в `session_info_update`) (design.md change `add-agent-project-files`, D8). Для записи с неизвестным `source` заголовок SHALL строиться по тексту сообщения.

#### Scenario: Автозаголовок по команде
- **WHEN** первый ход сессии — `/review lib/parser`, а тело шаблона — `Review $1 carefully`, и `session_info` нет
- **THEN** `session_info` с `source: "auto"` и `summarize` дают заголовок `/review lib/parser`, а не `Review lib/parser carefully`

