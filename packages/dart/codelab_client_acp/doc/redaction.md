# Маскирование секретов на стороне клиента

Документ описывает, как клиент CodeLab не пускает секреты в журналы, кадры протокола, диагностику и интерфейс: правила `SecretRedactor`, политику полезной нагрузки `ProtocolPayloadPolicy` и места, где они применяются. Он полный: читать его можно подряд. Сторона агента — правило секретных имён ядра, маскирование адресов, настройки `redact.*`, ссылки `${secret:…}` — описана в [`redaction.md` ядра агента](../../codelab_agent_core/doc/algorithms/redaction.md). Здесь она не повторяется.

Секрет — значение, по которому можно войти от имени пользователя: токен, пароль, ключ API, приватный ключ, строка подключения с паролем. Маскирование — замена значения на `<redacted>` (константа `redactedSecret`). Редактор — `SecretRedactor`. Полезная нагрузка (payload) — JSON-сообщение ACP целиком: промпты, содержимое файлов, вывод команд.

## Что защищается и от чего

Клиент показывает и хранит то, что присылает агент, а агент может прочитать `.env`, выполнить `printenv` или процитировать ключ в тексте ошибки. Журнал и снимок диагностики пользователь прикладывает к баг-репорту, снимок экрана уходит в чат. Поэтому безопасность стоит выше наблюдаемости ([`AGENTS.md`](../../../../AGENTS.md) §2, §10, §16).

| Куда секрет мог бы утечь | Чем закрыто |
|---|---|
| журнал приложения и `codelab -v` | процессор `secretRedactionProcessor`, `CliLogger`, `CliEmbeddedLogger`; полезную нагрузку в записи `protocol_message` решает политика |
| журнал кадров ACP и панель Protocol | `ProtocolFrameRecorder` маскирует payload до хранения; при `metadataOnly` payload нет вообще |
| диагностика (`DiagnosticEntry`) | `_recordDiagnostic` маскирует сообщение и контекст; текст причины зависит от политики |
| строки интерфейса: деталь вызова, `rawInput` в инспекторе и блоке одобрения | `ToolRowFormatter`, `formatRedactedJson`, `describeFailure`; метка вида `other`, `secondary`, `summary` и команда одобрения не маскируются (см. «Пределы») |
| вывод команд и содержимое файлов в кадрах | политика `metadataOnly` по умолчанию, затем маскирование при `full` |
| ошибка запуска процесса агента | `StdioAcpTransport` убирает аргументы из `ProcessException` |
| промпт модели | не входит: клиент не маскирует то, что агент отправляет модели (раздел «Пределы») |

Требования: [`structured-logging`](../../../../openspec/specs/structured-logging/spec.md) («Маскирование секретов в structured-выводе»), [`approval-safety`](../../../../openspec/specs/approval-safety/spec.md) («Редактирование секретов»). Решения — [`design.md` change `extend-secret-name-redaction`](../../../../openspec/changes/extend-secret-name-redaction/design.md) (D1–D8) и [`design.md` change `redesign-protocol-pane`](../../../../openspec/changes/redesign-protocol-pane/design.md) (D3, D4, D17). Правила имён с `key` (K1–K5) и стоп-слово `key` у счётчиков токенов описаны только в дельте [`approval-safety` change `extend-secret-name-redaction`](../../../../openspec/changes/extend-secret-name-redaction/specs/approval-safety/spec.md): change ещё не архивирован, в `openspec/specs/` их пока нет. Общий принцип — [`observability.md`](../../../../docs/architecture/observability.md) §13–14а.

## Вход и выход

| | Что |
|---|---|
| Вход | значение любого типа и необязательное имя ключа, под которым оно лежит (`redact`); `Map` верхнего уровня (`redactMap`); строка (`redactText`) |
| Выход | копия значения: секретные значения заменены на `<redacted>`, остальное без изменений; числа, `bool`, `null` проходят как есть |
| Состояние | нет: `const SecretRedactor()` |
| Ошибки | нет: правила работают за линейное время и не бросают исключений |
| Идемпотентность | повторный проход по `<redacted>` ничего не меняет |

Один редактор — единственный источник правил клиента. Второго набора правил нет: журнал, кадры, диагностика и строки интерфейса зовут один и тот же класс (`lib/src/domain/secret_redaction.dart`).

## Путь данных

Схема показывает, где данные проходят редактор по пути к журналу и к интерфейсу. Агент для клиента — внешняя сторона: что он прислал, клиент считает недоверенным.

```mermaid
flowchart LR
  agent["Агент (ACP)"] --> core["AcpClientApplication"]
  core --> rec["ProtocolFrameRecorder"]
  core --> diag["_recordDiagnostic"]
  core --> logger["Logger"]
  rec -->|"full: redactMap"| frames["Кадры (буфер, панель Protocol)"]
  rec -->|"metadataOnly: без payload"| frames
  diag -->|"redactText, redactMap"| dbuf["Диагностика"]
  logger -->|"secretRedactionProcessor"| sink["Журнал app"]
  logger -->|"redactMap в CliLogger"| cli["stderr codelab"]
  core --> state["Сессия, транскрипт"]
  state -->|"ToolRowFormatter, formatRedactedJson"| ui["Интерфейс app и codelab"]
```

Сессия и транскрипт хранят данные агента как есть: они нужны для работы клиента. Маскируется копия на выходе — в журнал, кадр, диагностику или строку интерфейса.

## Псевдокод

Запись Dart-подобная. Комментарии `//` указывают место в коде: `файл: символ`. Порядок шагов совпадает с кодом. Пути относительны `packages/dart/codelab_client_acp/lib/src/`.

### Уровень 0. Значение под именем ключа

```text
// domain/secret_redaction.dart: SecretRedactor.redact(value, key)
R1. если value — число и key != null и _isTokenCounterKey(key):
        вернуть value                              // счётчик расхода, не секрет
R2. если _isSensitiveKey(key):
        вернуть '<redacted>'                       // любой тип значения
R3. по типу value:
        null, число, bool  -> value
        String             -> redactText(value)
        Map                -> _redactMap(value)
        Iterable           -> [для каждого item: redact(item)]   // без ключа
        иное               -> redactText(value.toString())
```

### Уровень 1. Правила имён

```text
// domain/secret_redaction.dart: _isSensitiveKey(key)
N1. key == null -> false
N2. совпал _sensitiveKeyPattern (api_key, auth, authorization, bearer, cookie,
    credential, jwt, pass/password, private_key, secret,
    session_token/cookie/secret/key, token; регистр не важен) -> true
N3. _isKeyLikeName(key)

// domain/secret_redaction.dart: _isKeyLikeName(name)
K1. в имени нет подстроки `key` (любой регистр) -> false
K2. имя оканчивается на `_key` или `-key`           -> true   // OPENAI_KEY
K3. имя содержит access_key / access-key / accesskey -> true   // AWS_ACCESS_KEY_ID
K4. имя оканчивается на `…Key` (строчная или цифра перед K) -> true   // openaiKey
K5. иначе false                                      // key, keyboard, monkey, KEY_ID

// domain/secret_redaction.dart: _isTokenCounterKey(key)
C1. имя не вида tokens / tokens_… / …_tokens                       -> false
C2. rest = key без первого вхождения части `tokens`
C3. _isSensitiveKey(rest)                                          -> false
C4. один из сегментов rest (по `_` и `-`) входит в
    {key, access, refresh, id, csrf, otp, pin, session}            -> false
C5. иначе true
```

### Уровень 2. Объект и пара `{name, value}`

```text
// domain/secret_redaction.dart: _redactMap(map)
M1. name = map['name']
M2. secretPair = name — строка и есть ключ 'value'
                 и _isSensitiveKey(name)
                 и не (value — число и _isTokenCounterKey(name))
M3. для каждого entry:
        secretPair и ключ == 'value' -> '<redacted>'
        иначе                        -> redact(entry.value, key: entry.key)

// domain/secret_redaction.dart: redactMap(map)    // Map верхнего уровня
M4. для каждого entry: redact(entry.value, key: entry.key)    // без правила пары
```

### Уровень 3. Текст

```text
// domain/secret_redaction.dart: redactText(text)
T1. если в тексте есть '-----BEGIN':
        _redactPrivateKeys(text)
            // от BEGIN … PRIVATE KEY до ближайшего END; нет END — до конца текста
T2. значение после Basic | Bearer | Digest | Token  ->  '<схема> <redacted>'
        // _authorizationPattern, регистр не важен
T3. если в тексте есть '://':
        всё между '://' и последним '@' авторитета -> '://<redacted>@'
        // _urlUserinfoPattern; граница — первый / ? # пробел " < > `
T4. если в тексте есть '=' или ':':
        _redactAssignments(text)

// domain/secret_redaction.dart: _redactAssignments(text)
A1. для каждого совпадения _assignmentNamePattern (имя, затем `=` или `:`),
    начало которого лежит вне уже скрытого значения:
A2.     имя не секретное (_isSecretAssignmentName) -> пропустить, идти дальше
        // после разделителя: вложенное url=https://h/x?access_token=abc найдётся
A3.     значение = символы до пробела, `,` или `;` (_assignmentValuePattern);
        значения нет -> пропустить
A4.     значение -> '<redacted>'; следующий поиск — после конца значения
```

### Уровень 4. Политика полезной нагрузки

```text
// application/protocol_frame_recorder.dart: ProtocolFrameRecorder.record(direction, message, generation, payloads)
F1. сменилось поколение соединения -> сбросить учёт запросов без ответа
F2. сопоставить сообщение с запросом (метод, сессия), посчитать размер JSON в байтах
F3. detail:
        ответ с ошибкой, payloads == full  -> clipText(redactText(error.message))   // до 120 символов
        ответ с ошибкой, payloads иначе    -> стандартное имя кода (standardErrorName)
F4. payloads == full:
        размер > 256 KiB            -> payload = null, omitted = tooLarge   // не маскируется вообще
        иначе redacted = redactMap(message.toJson());
              если размер * 4 > 256 KiB и замаскированный > 256 KiB -> tooLarge
              иначе payload = redacted
    payloads == metadataOnly        -> payload = null, omitted = policy

// application/acp_client_application.dart: _framePolicy
F5. действующая политика кадров = full, если базовая full или включён Trace;
    иначе metadataOnly. Запись `protocol_message` и данные диагностики
    следуют только базовой политике.
```

## Как это работает

**Имя секретнее значения.** `redact` сначала смотрит на имя ключа (R2): `api_key: 42` скрывается, хотя 42 — число. Значение не нужно разбирать, чтобы решить, что оно секретное. Поэтому проверка имени стоит раньше проверки типа.

**`sessionId` — не секрет.** Слова `session` в списке имён нет: ACP `sessionId` — корреляционный идентификатор ([`observability.md`](../../../../docs/architecture/observability.md) §4), и без него журнал не связать с ходом. Скрываются только `session_token`, `session_cookie`, `session_secret`, `session_key`.

**`tokens_in: 900` — не секрет, `access_tokens: 3` — секрет.** Правило «`token` в имени» скрывало статистику расхода модели (спека `approval-safety`, «Редактирование секретов»; решение D41 п. 7 change `add-subagents-and-tasks`). Исключение узкое (R1, C1–C5):

- число — только число; строка под `tokens_in` скрывается как прежде;
- из имени вырезается часть `tokens`, остаток не должен быть секретным (`secret_tokens`, `tokens_api_key`, `auth_tokens` скрыты);
- сегмент-стоп-слово (`access`, `refresh`, `id`, `csrf`, `otp`, `pin`, `session`; `key` — только по дельте активного change) делает имя множественным числом учётных данных: `access_tokens`, `id_tokens`, `session__tokens` скрыты;
- стоп-слово сравнивается с целым сегментом, поэтому `input_tokens`, `hidden_tokens`, `monkey_tokens` видны.

**Имена с `key` проверяются отдельно (K1–K5; пока только в дельте активного change).** Слово `key` в любом месте имени скрыло бы `keyboard` и `monkey`. Поэтому нужен конец имени (`OPENAI_KEY`, `X-Functions-Key`), `access_key` в любом месте (`AWS_ACCESS_KEY_ID`) или camelCase `…Key` (`openaiKey`); camelCase проверяется с учётом регистра (D1 change `extend-secret-name-redaction`). Голое `key` и `KEY_ID` не скрываются. Цена правила — `cache_key` и `hotKey` скрыты осознанно.

**Пара `{name, value}`.** Заголовки HTTP и переменные окружения MCP-серверов в ACP — объекты `{"name": "Authorization", "value": "…"}`: секрет лежит не под своим ключом, а в `value`. `_redactMap` применяет к `name` то же правило имён (M2), отдельного списка нет. Маскировать `value` любого объекта с `name` нельзя: `PATH` и `ResourceLink` стали бы бесполезны для отладки (`observability.md` §14а, D4 change `redesign-protocol-pane`).

**Порядок правил текста важен (T1–T4).** PEM-блок идёт первым: блок многострочный, и присваивания внутри него не нужны. Блок без `END` скрывается до конца текста: вывод могли оборвать. Userinfo адреса стоит перед присваиваниями, чтобы `DATABASE_URL=postgres://bob:pw@db/app` скрылся и под несекретным именем. Скрывается весь userinfo (`bob:pw`), потому что токен часто и есть имя пользователя (D4). Границей адреса служат `/`, `?`, `#`, пробел, кавычка, `<`, `>` и обратная кавычка, но не `\`: по RFC 3986 `https://h\user:pass@host` — это userinfo `h\user:pass`.

**Присваивания: слова текста уже слов ключа.** Для текста из словаря имён убраны `auth`, `authorization`, `bearer`: иначе `author: Bob` скрывался бы, а заголовок авторизации уже закрыт шагом T2 (`_assignmentWordPattern`). Имя находится целиком по границе последовательности символов, а проверка — кодом, а не одним большим выражением: так время линейно по длине текста (D3, D5).

**Быстрые пути.** Заголовок авторизации (T2) быстрого пути не имеет и выполняется всегда. Остальные правила запускаются, только если в тексте есть его обязательная подстрока (`-----BEGIN`, `://`, `=` или `:`). В режиме `full` маскируется payload каждого кадра стриминга, и без быстрых путей он дороже прогона без маскирования больше чем в 1,5 раза (`test/protocol_frame_cost_test.dart`).

**Размер кадра.** Больше 256 KiB — payload не хранится и не маскируется: хранить его нельзя, а маскировать мегабайтную строку дорого (F4). Малые сообщения повторно не кодируются: маскирование увеличивает JSON не больше чем в 4 раза.

**Политика payload.** Пакет не знает режима сборки, решение принимает composition root. `metadataOnly` — по умолчанию: в кадрах только метод, id, сессия, размер, `detail` и код ошибки; текст ошибки агента может содержать пути и фрагменты данных, поэтому заменён именем стандартного кода. `full` — payload после маскирования. Режим Trace (`setFrameTrace`) поднимает до `full` только кадры; запись `protocol_message` и диагностику он не меняет (D17). Решения по каждой точке:

| Данные | `metadataOnly` | `full` |
|---|---|---|
| payload кадра | нет, `omitted = policy` | `redactMap(message.toJson())` |
| `detail` ошибки кадра | имя стандартного кода | замаскированный текст до 120 символов |
| поле `payload` записи `protocol_message` | нет | `message.toJson()`, маскирует процессор журнала |
| сырые данные в диагностике (`_rawPayloadContext`) | только `size` в байтах | значение, затем `redactMap` контекста |
| причина сбоя (`_causeDetail`) | только имя класса ошибки | `redactText(cause.toString())` |

## Карта точек применения

| Где | Что маскируется | Чем | Файл |
|---|---|---|---|
| журнал приложения | любая запись: ключи и тексты | `secretRedactionProcessor` первым в цепочке `structured_log`, `redactMap` | `lib/src/infrastructure/structured_log_logger.dart` |
| кадры ACP | payload и `detail` ошибки | `redactMap`, `redactText` | `lib/src/application/protocol_frame_recorder.dart` |
| диагностика клиента | `message`, `context`; причина | `redactText`, `redactMap`, `_causeDetail` | `lib/src/application/acp_client_application.dart`: `_recordDiagnostic` |
| неизвестный вид вызова | значение вида в WARN, до усечения до 64 символов | `redactText`, затем усечение | `lib/src/application/acp_client_application.dart`: `_logUnrecognizedToolKind` |
| причина отброшенной попытки | `error` | `redactText` | `lib/src/application/acp_client_application.dart` |
| диагностика рабочего пространства | `message` | `redactText` | `codelab_client_core/lib/src/workspace/client_workspace.dart` |
| текст ошибки для интерфейса | исключение целиком | `redactText` в `describeFailure` | `codelab_client_core/lib/src/diagnostics/diagnostics.dart` |
| инспектор, блок одобрения | `rawInput`, `rawOutput`, ресурсы | `formatRedactedJson` (`redact` по значению) | `codelab_client_core/lib/src/diagnostics/diagnostics.dart`, `inspector/inspector_projection.dart` |
| строка инструмента | только деталь (до 160 символов) и отчёт субагента; query и фрагмент адреса отбрасываются. Не маскируются: метка вида `other` (сырой `title`, `_labelOf`), `secondary` (первая строка вывода упавшего вызова, `_firstLine`), `summary`, `summaryShort` | `redactText` в `_clean` | `codelab_client_core/lib/src/transcript/tool_row.dart` |
| журнал `codelab` | контекст записи | `redactMap` в `CliLogger`; `CliEmbeddedLogger` — то же для полей агента | `apps/codelab_cli/lib/src/cli_logger.dart`, `embedded_logger.dart` |
| блок одобрения REPL | только `rawInput`; команда (`_command()`) печатается без маскирования | `formatRedactedJson` | `apps/codelab_cli/lib/src/repl/approval_prompt.dart` |
| журнал приложения: события оболочки | текст события | `redactText` | `apps/codelab_desktop/lib/features/workbench/application/shell_part.dart` |
| журнал приложения: встроенный агент | поля записи | процессор журнала (адаптер ничего не добавляет) | `apps/codelab_desktop/lib/app/embedded_logger.dart` |
| панель Protocol | payload уже замаскирован; маркер `<redacted>` показан отдельным сегментом | повторного маскирования нет | `apps/codelab_desktop/lib/features/protocol/application/protocol_pane_view.dart` |
| ошибка запуска агента | аргументы команды (в них бывают ключи) | копия `ProcessException` без аргументов, не редактор | `codelab_acp_transports/lib/src/io/stdio_acp_transport.dart` |
| аргумент `--agent` | значение в тексте ошибки не повторяется, кроме `ws://`/`wss://` (`Invalid agent URL "<значение>"`, `profile_arg.dart:178`) | не печатается, не редактор | `apps/codelab_cli/lib/src/profiles/profile_arg.dart` |

Политику выбирают composition root: `codelab` — `--verbose` даёт `full`, иначе `metadataOnly` (`apps/codelab_cli/lib/src/composition_root.dart`); app — `full` в debug-сборке, иначе `metadataOnly` (`apps/codelab_desktop/lib/app/app_scope.dart`: `CodeLabProtocolModule`).

## Разобранные примеры

Источник: временные тесты в пакете `codelab_client_acp`, запущены `fvm dart test`. Тесты вызывали `SecretRedactor` и `ProtocolFrameRecorder` на перечисленных входах; файлы удалены. Значения фиктивные.

### Имя ключа

Вызов: `redact(value, key: имя)`.

| Имя | Значение | Результат | Почему |
|---|---|---|---|
| `sessionId` | `"sess-123"` | `"sess-123"` | нет секретного слова |
| `session_token` | `"abc"` | `<redacted>` | `session_token` в словаре |
| `tokens_in` | `900` | `900` | счётчик, число |
| `tokens_in` | `"sk-test-1"` | `<redacted>` | строка под счётчиком |
| `input_tokens` | `800` | `800` | счётчик |
| `access_tokens` | `3` | `<redacted>` | стоп-слово `access` |
| `key_tokens` | `1` | `<redacted>` | стоп-слово `key` |
| `monkey_tokens` | `5` | `5` | `monkey` — не сегмент `key` |
| `token` | `5` | `<redacted>` | имя без `tokens`: правило счётчика не действует |
| `OPENAI_KEY` | `"sk-test-abc"` | `<redacted>` | K2 |
| `openaiKey` | `"sk-test-1"` | `<redacted>` | K4 |
| `key`, `keyboard`, `monkey`, `KEY_ID` | любое | без изменений | K5 |
| `cache_key` | `"c"` | `<redacted>` | K2, осознанная цена |
| `author` | `"Bob"` | `<redacted>` | `auth` внутри слова |

### Пара `{name, value}` и вложенные структуры

| Вход | Результат |
|---|---|
| `redact({name: Authorization, value: "Bearer sk-test-1"})` | `{name: Authorization, value: <redacted>}` |
| `redact({name: PATH, value: "/usr/bin"})` | без изменений |
| `redact({name: tokens_in, value: 5})` | без изменений: число под счётчиком |
| `redact({headers: [{name: X-Functions-Key, value: "sk-test-9"}], usage: {tokens_in: 9}})` | `value` скрыт, `tokens_in: 9` виден |
| `redactMap({name: Authorization, value: "sk-test-1"})` | без изменений: `redactMap` верхнего уровня не знает правила пары |
| `redactMap({env: [{name: GITHUB_TOKEN, value: "sk-test-1"}]})` | `value` скрыт: пара вложена |

### Текст

Вызов: `redactText(строка)`.

| Вход | Результат | Правило |
|---|---|---|
| `OPENAI_KEY=sk-test-abc` | `OPENAI_KEY=<redacted>` | T4 |
| `X-Functions-Key: sk-test-abc` | `X-Functions-Key: <redacted>` | T4, K2 |
| `Authorization: Bearer sk-test-abc` | `Authorization: Bearer <redacted>` | T2 |
| `postgres://bob:p@ss@db/app` | `postgres://<redacted>@db/app` | T3: пароль с `@` скрыт целиком |
| `DATABASE_URL=postgres://bob:pw@db/app` | `DATABASE_URL=postgres://<redacted>@db/app` | T3, затем `DATABASE_URL` — не секретное имя |
| `url=https://h/x?access_token=abc&a=1` | `url=https://h/x?access_token=<redacted>` | A2: после несекретного имени поиск идёт дальше |
| `https://h\user:pass@host/p` | `https://<redacted>@host/p` | `\` не граница |
| PEM `BEGIN … END` и строка `ok` после | `<redacted>` и `ok` | T1 |
| PEM `BEGIN` без `END` | всё от `BEGIN` до конца текста | T1 |
| `password = hunter2 ; next` | `password = <redacted> ; next` | A3: значение до `;` |
| `token: "sk-test-1"` | `token: <redacted>` | значение до пробела захватывает кавычки |
| `tokens_in=900` | `tokens_in=<redacted>` | в тексте исключение счётчиков не действует |
| `secrets.backend: env` | `secrets.backend: <redacted>` | имя содержит `secret`: ложное срабатывание |
| `author: Bob` | без изменений | слова `auth` в словаре текста нет |
| `sessionId=abc` | без изменений | |

### Кадры

`ProtocolFrameRecorder.record` на уведомлении `session/update` с `rawOutput {api_key: sk-test-1, tokens_in: 9, text: "OPENAI_KEY=sk-test-2"}`:

| Политика | `payload` | `payloadOmitted` | `detail` |
|---|---|---|---|
| `full` | `{…, "rawOutput": {"api_key": "<redacted>", "tokens_in": 9, "text": "OPENAI_KEY=<redacted>"}}` | `null` | `tool_call_update` |
| `metadataOnly` | `null` | `policy` | `tool_call_update` |

Ответ с ошибкой `-32603`, текст `failed: token=sk-test-3`:

| Политика | `detail` | `errorCode` |
|---|---|---|
| `full` | `failed: token=<redacted>` | `-32603` |
| `metadataOnly` | `Internal error` | `-32603` |

Уведомление с одной строкой в 300 KiB при `full`: `payload = null`, `payloadOmitted = tooLarge` — без попытки маскирования.

## Пределы

Редактор ищет признаки: секретное имя, схему авторизации, адрес с учётными данными, PEM-блок. Секрет без признаков он не узнаёт. Таблица — то, что механизм не ловит или ловит с побочным эффектом.

| Случай | Что происходит | Почему |
|---|---|---|
| `sk-test-abc123` в произвольном тексте | остаётся | нет имени, схемы или разделителя; шаблонов формата ключей поставщиков нет |
| `curl -H "Authorization: sk-test-1" url` | остаётся | в словаре присваиваний в тексте нет `authorization` (иначе скрывался бы `author:`); значение без схемы `Bearer` шагом T2 не берётся |
| `--token sk-test-1` в командной строке | скрывается, но случайно | сработало правило `Token <значение>` (T2), а не имя флага; `--password hunter2` останется |
| элемент списка без своего ключа: `{args: ["--api-key", "sk-test-1"]}` | остаётся | `Iterable` обходится без имён ключей: значение следует за флагом, а не лежит под ним |
| `Token of appreciation` | `Token <redacted> appreciation` | правило T2 не отличает слово от схемы; сообщения клиента формулируются без `Token <слово>` |
| `Basic auth required`, `Digest of the message` | `Basic <redacted> required` | T2 срабатывает и на `Basic`, и на `Digest`, как на `Token` |
| `passport`, `bypass`, `compass` | значение скрыто: ключи `passport`, `bypass`; в тексте `passport: X123`, `compass=north` | `pass` в словаре имён ищется как подстрока |
| метка вида `other`, `secondary`, `summary`, `summaryShort` строки инструмента | не маскируются | `_labelOf` возвращает сырой `title`, `secondary` — `_firstLine(textOutput)` (app: `ui_mappers.dart`), `summary` — как пришёл; редактор есть только у детали и отчёта |
| команда в блоке одобрения | не маскируется | `_command` в `transcript_projector.dart` кладёт `rawInput.command` как есть; app показывает её через `approval.command` (`ui_mappers.dart`), REPL — через `_command()` в `approval_prompt.dart`; маскируется только `rawInput` целиком |
| `author`, `AUTHOR`, `cache_key`, `hotKey` | значение скрыто | осознанные ложные срабатывания: безопаснее скрыть |
| `ssh://git@host/repo` | `ssh://<redacted>@host/repo` | имя `git` нельзя отличить от токена-имени |
| `redactMap` верхнего уровня на паре `{name, value}` | `value` остаётся | правило пары живёт в `_redactMap` вложенных объектов; верхний уровень — `Map` кадра или записи, а не пара |
| деталь вызова `fetch`: `https://bob:pw@host/x` | `bob:pw@host/x` | `_withoutSchemeAndQuery` отбрасывает `https://` раньше, чем редактор видит `://`; адрес без схемы шагом T3 не берётся |
| строка вызова в REPL и TUI (`toolRow`) | название и команда не маскируются | печатается через `sanitizeTerminalText` без редактора (`apps/codelab_cli/lib/src/render/tool_row.dart`; в backlog — SMK-47 в [`smoke-2026-11-23-secret-redaction.md`](../../../../docs/backlog/smoke-2026-11-23-secret-redaction.md)) |
| строка решения headless `codelab: permission "…"` | заголовок не маскируется | `describeApproval` без редактора (SMK-48 там же) |
| payload больше 256 KiB | не хранится | не маскируется, а отбрасывается; в журнале остаётся размер |
| окружение запуска процесса агента | редактор не применяется | отдельного показа окружения в клиенте нет; форма профиля отклоняет имена, похожие на секрет (`KEY`, `*_KEY`, `*_TOKEN`, `*_SECRET`), правилом `_looksLikeSecret` в `profile_draft.dart`, а не `SecretRedactor` |
| то, что агент отправляет модели и пишет в свои файлы | не входит | клиент их не видит; сторона агента — в [документе агента](../../codelab_agent_core/doc/algorithms/redaction.md) |
| приёмник, не подключивший `secretRedactionProcessor` | запись `protocol_message` с `payload` пишется как есть | ядро кладёт сырой `message.toJson()`, маскирует приёмник журнала (`configureCodeLabLogging`); тестовый логгер без процессора увидит секрет |

## Параметры

Настроек маскирования у клиента нет: правила заданы кодом, ключи конфигурации `redact.*` относятся к агенту (см. [документ агента](../../codelab_agent_core/doc/algorithms/redaction.md)). Клиент выбирает только политику полезной нагрузки.

| Параметр | Где | Значения | Действие |
|---|---|---|---|
| `protocolPayloads` | конструктор `AcpClientApplication` | `metadataOnly` (по умолчанию), `full` | базовая политика процесса |
| `--verbose` / `-v` | `codelab` | флаг | `full` для кадров и записи `protocol_message` |
| debug-сборка | app | сборка | `full`; release — `metadataOnly` |
| режим Trace, `setFrameTrace(bool)` | `AcpClientApplication`, панель Protocol | вкл/выкл | `full` только для кадров, только если базовая политика `metadataOnly`; не сохраняется между запусками |
| `ProtocolFrameRecorder.maxPayloadBytes` | константа | 256 KiB | предел payload |
| `ProtocolFrameRecorder.maxDetailLength` | константа | 120 | предел `detail` ошибки |
| `ToolRowFormatter.maxDetailLength` | константа | 160 | предел детали строки инструмента |

## Как расширить

**Добавить секретное имя.**

1. Для слова — допишите альтернативу в `_sensitiveKeyPattern` (`lib/src/domain/secret_redaction.dart`). Для слов, которые не должны скрывать присваивания в тексте (как `auth`), не добавляйте их в `_assignmentWordPattern`.
2. Для признака вида `key` — правьте `_isKeyLikeName`, он общий для имён ключей и текста.
3. Если слово может встретиться в имени счётчика, проверьте правило `_isTokenCounterKey` и список `_credentialStopWords`.
4. Допишите тест в группу, которая соответствует правилу, в `test/secret_redaction_test.dart`: `a secret under a similar name is redacted`, `a key-like name is redacted`, `a key-like name that is not a secret stays visible`, `a key assignment in text is redacted`, `URL userinfo is redacted`. Для нового правила текста добавьте и проверку времени (`masking is linear in input length`).
5. Обновите требование «Редактирование секретов» в `openspec/specs/approval-safety/spec.md` и `observability.md` §14: правило имён — требование продукта, поэтому нужен OpenSpec change.
6. Прогоните тесты пакета и [`conformance:client`](04-testing-extending-troubleshooting.md), если менялись кадры: `fvm dart test` в пакете.

**Добавить точку применения.**

1. Данные идут в журнал — пишите их в `Logger`: процессор `secretRedactionProcessor` скроет ключи и тексты. Свой приёмник без процессора добавлять нельзя.
2. Данные идут в строку интерфейса — зовите `SecretRedactor.redactText` или `formatRedactedJson` (`codelab_client_core`) в той функции, что строит строку, а не в виджете: виджет не решает, что секрет ([`AGENTS.md`](../../../../AGENTS.md) §10).
3. Данные зависят от режима сборки — не читайте режим сами: берите `ProtocolPayloadPolicy` у composition root, как `_rawPayloadContext` и `_causeDetail`.
4. Маскируйте до усечения: усечение режет PEM-блок до того, как шаблон его узнает (`_logUnrecognizedToolKind`).
5. Добавьте тест, что секрет не доходит до выхода: примеры — `test/structured_logging_test.dart` (журнал), `test/protocol_frame_test.dart` и `test/payload_policy_diagnostics_test.dart` (кадры и диагностика), `codelab_client_core/test/diagnostics/` (строки интерфейса), `apps/codelab_cli/test/cli_logger_test.dart` и `embedded_logger_test.dart` (журнал `codelab`).
6. Внесите строку в таблицу «Карта точек применения».

## См. также

- [Документ агента](../../codelab_agent_core/doc/algorithms/redaction.md) — правила секретных имён ядра, `redact.*`, ссылки `${secret:…}`, маскирование вывода `config`.
- [Обзор и слои](01-overview.md) — политика payload и места в слоях.
- [Диагностика, кадры и инспектор в `codelab_client_core`](../../codelab_client_core/doc/11-inspector-diagnostics-frames.md).
- [`observability.md`](../../../../docs/architecture/observability.md) — журналы, корреляция, маскирование.
