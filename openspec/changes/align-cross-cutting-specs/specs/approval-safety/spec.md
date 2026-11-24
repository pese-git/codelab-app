## MODIFIED Requirements

### Requirement: Уровни риска
CodeLab SHALL классифицировать действия агента по клиентским уровням риска `ApprovalRiskLevel` (`codelab_client_acp`) в порядке возрастания: `readOnly`, `unknown`, `localWrite`, `network`, `shell`, `destructive`. Уровень вызова SHALL считать `ApprovalPolicy` по виду (`ToolKind` ACP) и содержимому вызова. Последующие обновления и запросы разрешения уровень вызова SHALL NOT понижать (требование «Риск вызова неизвестного вида и смены режима»).

Уровень риска — подсказка для показа пользователю. Нужно ли одобрение, решает агент: он присылает или не присылает `session/request_permission` (`docs/architecture/permissions.md` §58). Автоматически, без вопроса пользователю, клиент отвечает только по политике headless CLI `--approve` (cli-headless «Политика одобрений headless»).

#### Scenario: Отображается запрос разрешения
- **WHEN** агент запрашивает разрешение на вызов с уровнем риска `unknown`
- **THEN** блок одобрения CLI называет риск `unknown risk` (`approval_prompt_test.dart`, «an unknown risk is shown as "unknown risk"»), а строка вызова app показывает тег `Unknown risk` (agent-workbench-ui «Тег неизвестного риска одобрения»)

#### Scenario: Деструктивная команда
- **WHEN** агент присылает вызов вида `execute` с заголовком `Run git reset --hard`
- **THEN** `ApprovalPolicy.classifyToolCall` даёт уровень `destructive`, а вызов `execute` без такой команды — `shell` (`codelab_client_acp_test.dart`)

### Requirement: Поток разрешений ACP
CodeLab SHALL отвечать на `session/request_permission`, выбирая предложенный агентом `PermissionOption` либо возвращая outcome `cancelled`. Запрос SHALL связываться с сессией, ходом и вызовом по id JSON-RPC запроса: решение для одного запроса SHALL NOT применяться к другому. Повторная доставка запроса с тем же id SHALL NOT создавать второе ожидающее одобрение. Ответ `cancelled` на запрос без активного хода и во время отмены хода — требование acp-protocol-client «Отмена prompt turn».

#### Scenario: Пользователь одобряет опцию
- **WHEN** пользователь выбирает опцию approval
- **THEN** CodeLab возвращает `selected` с выбранным `optionId`

#### Scenario: Turn отменяется во время approval
- **WHEN** prompt turn отменяется при наличии ожидающих запросов разрешения
- **THEN** CodeLab отвечает на каждый ожидающий запрос с outcome `cancelled` (`application_use_cases_test.dart`, «CancelTurn sends session/cancel and cancels pending approval»)

#### Scenario: Повторный запрос с тем же id
- **WHEN** агент дважды присылает `session/request_permission` с id `42`
- **THEN** у хода одно ожидающее одобрение `permission-42`, а сессия один раз переходит в `awaitingApproval` (`application_use_cases_test.dart`, «ignores duplicate permission request ids»)

### Requirement: Редактирование секретов
CodeLab SHALL редактировать секреты в данных клиента до того, как они попадут в:
- записи журнала — во всех sinks (structured-logging «Маскирование секретов в structured-выводе»);
- диагностику (`DiagnosticEntry` протокольного клиента, `WorkspaceDiagnostic` ядра клиента);
- строки вызовов инструментов транскрипта.

Какие данные протокола попадают в журнал вообще (payload сообщения, текст промпта), определяет политика payload (structured-logging «Protocol tracing выключен по умолчанию в release»). Маскирование действует при любой политике.

Не маскируются до 1.0: журналы сессий агента на диске, промпты и вывод инструментов, которые уходят провайдеру модели (codelab-cli: предупреждение `Note: before 1.0, tool output, prompts and session logs are not redacted…`).

Правило секретных имён SHALL быть одним: оно действует везде, где редактор сверяет имя с правилом секретных имён (ключ map и любое другое место, где редактор проверяет имя), отдельного списка имён для других мест SHALL NOT быть. Имя секретное, если выполняется хотя бы одно (design.md change `extend-secret-name-redaction`, D1):
- имя содержит, без учёта регистра, одно из слов `api_key`, `auth`, `authorization`, `bearer`, `cookie`, `credential`, `jwt`, `pass`, `password`, `private_key`, `secret`, `session_token`, `session_cookie`, `session_secret`, `session_key`, `token`; в составных словах вместо `_` допустимы `-` и пустая строка (`api-key`, `apiKey`);
- имя содержит, без учёта регистра, `access_key`, `access-key` или `accesskey` (`AWS_ACCESS_KEY_ID`, `accessKeyId`);
- последний сегмент имени — `key`, отделённый `_` или `-`, без учёта регистра (`OPENAI_KEY`, `STRIPE_KEY`, `ENCRYPTION_KEY`, `SIGNING_KEY`, `Ocp-Apim-Subscription-Key`, `X-Functions-Key`);
- имя оканчивается на `Key` с заглавной `K` сразу после строчной латинской буквы или цифры (camelCase, с учётом регистра: `openaiKey`, `signingKey`, `subscriptionKey`).

Имя `key` целиком SHALL NOT считаться секретным: в структурных событиях это путь ключа настроек. Имена `keyboard`, `monkey`, `turnkey`, `hotkey`, `keys`, `key_count`, `keyId`, `KEY_ID`, `signing_key_id` SHALL NOT считаться секретными. Имена-идентификаторы с последним сегментом `key` или camelCase-окончанием `Key` (`cache_key`, `primary_key`, `sort_key`, `partition_key`, `foreign_key`, `idempotency_key`, `public_key`, `prompt_cache_key`, `hot_key`, `hotKey`, `primaryKey`, `cacheKey`) SHALL считаться секретными: это осознанная цена правила, а не дефект (D1).

Числовое значение (`num`) под именем поля-счётчика токенов секретом НЕ SHALL считаться и SHALL показываться как есть: это счётчик расхода модели (`subagent.end`, сжатие контекста), а не учётные данные (решение пользователя 2026-11-15; design.md change `add-subagents-and-tasks`, D41 п. 7). Имя — счётчик токенов, если одновременно:
- имя имеет вид `tokens`, `tokens_<…>` или `<…>_tokens` (слово `tokens` во множественном числе, разделитель `_` или `-`, регистр не важен);
- остаток имени после вырезания части `tokens` (первое вхождение `(^|[_-])tokens([_-]|$)`) НЕ совпадает с правилом секретных имён (`secret`, `password`, `api_key`, `auth`, `token`, `cookie`, `credential`, последний сегмент `key`, …);
- остаток имени, разбитый на сегменты по разделителям `_` и `-` (любое их число подряд, регистр не важен), НЕ содержит отдельным сегментом ни одного стоп-слова учётных данных: `access`, `refresh`, `id`, `csrf`, `otp`, `pin`, `session`, `key` (design.md change `extend-secret-name-redaction`, D2).

Так `tokens`, `tokens_in`, `tokens_out`, `input_tokens`, `max_output_tokens`, `tokens_before`, `Tokens-In` с числом видны, а `secret_tokens`, `tokens_api_key`, `auth_tokens`, `password_tokens`, `tokens_key` (правило секретных имён) и `access_tokens`, `refresh_tokens`, `id_tokens`, `csrf_tokens`, `otp_tokens`, `pin_tokens`, `session_tokens`, `tokens_session`, `session__tokens`, `key_tokens` (стоп-слова) скрываются при любом значении. Стоп-слово сравнивается с целым сегментом, а не с подстрокой: `input` и `output` не содержат сегмента `pin` или `id`, `monkey` — сегмента `key`. Строковое значение под именем-счётчиком, любое значение под другими именами правила (`token`, `access_token`, `session_token`, `api_key`, `password`, `secret`, …) и пары `key=value` внутри текста SHALL по-прежнему скрываться.

В тексте присваивание `имя=значение` или `имя: значение` (имя — непрерывная последовательность символов `A–Z`, `a–z`, `0–9`, `_`, `.`, `-`; вокруг `=` или `:` допустимы пробельные символы; значение — до пробельного символа, `,` или `;`) SHALL скрывать значение, если имя содержит одно из слов `api_key`, `cookie`, `credential`, `jwt`, `pass`, `password`, `private_key`, `secret`, `session_token`, `session_cookie`, `session_secret`, `session_key`, `token` или подпадает под признаки `access_key`, последнего сегмента `key` или camelCase-окончания `Key` правила секретных имён. Имя при этом SHALL оставаться видимым. Присваивание внутри значения несекретного имени SHALL проверяться так же: `url=https://h/x?access_token=abc` скрывает `abc` (D3).

В тексте учётные данные адреса SHALL скрываться: в фрагменте `<схема>://<userinfo>@` userinfo целиком — всё от `://` до последнего `@` перед первым `/`, `?`, `#`, пробельным символом, `"`, `<`, `>` или `` ` `` — SHALL заменяться на `<redacted>`. Правило SHALL действовать для строкового значения под любым ключом, в том числе несекретным (`DATABASE_URL`, `REDIS_DSN`). Фрагменты без `://` (`git@github.com:org/repo.git`, `mailto:a@b.c`) и `@` после `/`, `?` или `#` SHALL оставаться как есть. Userinfo без секрета (`ssh://git@host`) скрывается тоже: это осознанная цена (D4). `\` границей SHALL NOT считаться: `https://h\user:pass@host/x` даёт `https://<redacted>@host/x` (разбор по RFC 3986 видит здесь userinfo).

В тексте приватный ключ SHALL скрываться: блок от `-----BEGIN <…>PRIVATE KEY-----` до ближайшего следующего `-----END <…>PRIVATE KEY-----` заменяется на `<redacted>`; если после `BEGIN` строки `END` нет (вывод оборван, усечён или ещё идёт), SHALL скрываться всё от `BEGIN` до конца текста (D8).

Каждое правило маскирования текста SHALL работать за время, линейное по длине входа, в том числе на строках без разделителей и на повторах секретного слова (D5).

#### Scenario: Отображаются переменные окружения
- **WHEN** launch environment показан в диагностике
- **THEN** значения, похожие на токены, пароли, API-ключи или приватные ключи, скрыты

#### Scenario: Полный payload в журнале маскируется
- **WHEN** ядро клиента с базовой политикой payload `full` отправляет `session/new` с заголовком MCP-сервера `{"name": "Authorization", "value": "ghp_abc123"}`
- **THEN** запись `protocol_message` несёт payload, в котором вместо `ghp_abc123` стоит `<redacted>` (`structured_logging_test.dart`, «full: запись с замаскированным payload»; правило пары — approval-safety «Секрет в паре name/value» change `redesign-protocol-pane`)

#### Scenario: Счётчик токенов виден
- **WHEN** запись лога встроенного агента несёт поля `tokens: 1200`, `tokens_in: 900`, `tokens_out: 300`, `input_tokens: 800`, `tokens_before: 4000`, `max_output_tokens: 4096`, `Tokens-In: 7`, `monkey_tokens: 5`
- **THEN** журнал app и лог `codelab --verbose` показывают эти числа как есть (`secret_redaction_test.dart`)

#### Scenario: Секрет под похожим именем скрыт
- **WHEN** запись несёт поля `tokens: "abc123"`, `token: 123`, `access_token: 5`, `api_key: 42`, `session_token: "s"`, а текстовое поле — строку `tokens_in=sk-abc`
- **THEN** все пять значений скрыты как `<redacted>`, в тексте значение после `tokens_in=` скрыто (`secret_redaction_test.dart`)

#### Scenario: Счётчик с секретным словом скрыт
- **WHEN** запись несёт числовые поля `secret_tokens: 1`, `tokens_api_key: 1`, `auth_tokens: 1`, `password_tokens: 1`, `tokens_key: 1` (правило секретных имён) и `access_tokens: 1`, `refresh_tokens: 1`, `id_tokens: 1`, `csrf_tokens: 1`, `otp_tokens: 1`, `pin_tokens: 1`, `session_tokens: 1`, `tokens_session: 1`, `session__tokens: 1`, `Access-Tokens: 1`, `key_tokens: 1` (стоп-слова)
- **THEN** все значения скрыты как `<redacted>`, хотя они числа (`secret_redaction_test.dart`)

#### Scenario: Имя ключа с последним сегментом key скрыто
- **WHEN** запись несёт поля `OPENAI_KEY: "sk-1"`, `STRIPE_KEY: "sk_live_1"`, `ENCRYPTION_KEY: "k"`, `SIGNING_KEY: "k"`, `openai-key: "sk-2"`, `openaiKey: "sk-3"`, `signingKey: "k"`, `subscriptionKey: "k"`
- **THEN** все значения скрыты как `<redacted>` (`secret_redaction_test.dart`)

#### Scenario: Ключ доступа AWS скрыт
- **WHEN** запись несёт поля `AWS_ACCESS_KEY_ID: "AKIA1"`, `aws_access_key: "AKIA2"`, `accessKeyId: "AKIA3"`
- **THEN** все значения скрыты как `<redacted>`

#### Scenario: Заголовки ключей API скрыты
- **WHEN** запись несёт поля `Ocp-Apim-Subscription-Key: "abc"` и `X-Functions-Key: "def"`
- **THEN** оба значения скрыты как `<redacted>`

#### Scenario: Присваивание ключа в тексте скрыто
- **WHEN** маскируется текст `OPENAI_KEY=sk-1`, `X-Functions-Key: abc`, `export AWS_ACCESS_KEY_ID=AKIA1`, `openaiKey: sk-2`, `url=https://h/x?access_token=abc`
- **THEN** результат — `OPENAI_KEY=<redacted>`, `X-Functions-Key: <redacted>`, `export AWS_ACCESS_KEY_ID=<redacted>`, `openaiKey: <redacted>`, `url=https://h/x?access_token=<redacted>`

#### Scenario: Учётные данные адреса скрыты
- **WHEN** запись несёт поле `DATABASE_URL: "postgres://user:pass@db.local:5432/app"`, а текст — `REDIS_DSN=redis://:pw@cache:6379/0`, `clone https://ghp_abc@github.com/org/repo.git` и `mysql://u:p@ss@h/db`
- **THEN** значение поля — `postgres://<redacted>@db.local:5432/app`, в тексте — `REDIS_DSN=redis://<redacted>@cache:6379/0`, `clone https://<redacted>@github.com/org/repo.git` и `mysql://<redacted>@h/db`

#### Scenario: Приватный ключ без строки END скрыт
- **WHEN** маскируется текст `out: -----BEGIN RSA PRIVATE KEY-----\nMIIEow…` без строки `-----END … PRIVATE KEY-----` (например, `head -n 10 id_rsa` или усечённый payload)
- **THEN** текст — `out: <redacted>`; полный блок `BEGIN … END` по-прежнему заменяется на `<redacted>`, а текст после `END` остаётся видимым

#### Scenario: Адрес без учётных данных не меняется
- **WHEN** маскируется текст `https://example.com/a?u=a@b`, `https://example.com/@user`, `git@github.com:org/repo.git`, `mailto:a@b.c`, `https://example.com`
- **THEN** текст не меняется

#### Scenario: Похожие на ключ имена видны
- **WHEN** запись несёт поля `key: "providers.openai.api_key"`, `keyboard: "us"`, `monkey: "m"`, `hotkey: "ctrl+k"`, `keys: 3`, `key_count: 3`, `keyId: "k1"`, `KEY_ID: "k2"`, `signing_key_id: "k3"`, а текст — `keyboard=us`, `key_count=3`, `hotkey=ctrl+k`
- **THEN** все значения и текст показаны как есть

#### Scenario: Идентификатор под именем key скрыт осознанно
- **WHEN** запись несёт поля `cache_key: "c1"`, `primary_key: "id"`, `idempotency_key: "i1"`, `public_key: "ssh-ed25519 AAAA"`, `hotKey: "k"`
- **THEN** все значения скрыты как `<redacted>`: правило имён не отличает идентификатор от секрета (D1)

#### Scenario: Маскирование длинного текста за линейное время
- **WHEN** маскируются строки длиной около 256 KiB: без разделителей, из повторов `_key`, `access_key` или `token` без `=`, из повторов `://` без `@`, цепочка `x=x=…` и присваивание `OPENAI_KEY=` с длинным значением
- **THEN** каждая строка маскируется за время в пределах бюджета теста, а результат на коротких строках с секретами прежний (`secret_redaction_test.dart`)

### Requirement: Review-first изменения
Когда агент запрашивает одобрение (`session/request_permission`) правки файла или команды терминала, CodeLab SHALL показывать пригодные для проверки детали вызова до ответа на запрос.

Исключение (`AGENTS.md` §10): методы agent → client `fs/write_text_file` и `terminal/*` клиент выполняет без собственного шага одобрения; разрешение на них — ответственность агента (`docs/protocols/acp/protocol/08-Tool Calls.md#requesting-permission`, `09-File System.md`, `10-Terminal.md`). Для них CodeLab SHALL NOT вводить показ diff или команды с ожиданием решения пользователя. Компенсирующий контроль — ограничение путей и `cwd` рабочей папкой сессии (acp-fs-client, acp-terminal-client).

#### Scenario: Запрошена правка файла
- **WHEN** запрос одобрения относится к вызову, содержимое которого включает diff со старым и новым текстом
- **THEN** CodeLab показывает diff до ответа на запрос

#### Scenario: Запрошена команда terminal
- **WHEN** запрос одобрения относится к вызову вида `execute`
- **THEN** CodeLab показывает команду, аргументы, рабочую папку и риск до ответа на запрос (`approval_prompt_test.dart`, «the block has the title, risk, command, folder and only the…»)

#### Scenario: Запись файла без одобрения клиента
- **WHEN** агент вызывает `fs/write_text_file` с путём внутри рабочей папки сессии без предшествующего `session/request_permission`
- **THEN** CodeLab выполняет запись без показа diff и без вопроса пользователю, а путь вне рабочей папки отклоняет до записи (acp-fs-client)

### Requirement: Риск вызова неизвестного вида и смены режима
CodeLab SHALL классифицировать вызов вида `switch_mode` (`docs/protocols/acp/protocol/17-Schema.md`, ToolKind) и вызов, чей строковый `kind` CodeLab не знает и разбирает как `other` (требование «Неизвестный вид вызова инструмента» acp-protocol-client), клиентским уровнем риска `unknown` (требование «Неизвестный уровень риска вызова» acp-client-kit). Такой вызов SHALL NOT получать уровень `readOnly`: одобрение смены режима может включить автоодобрение последующих действий (`12-Session Model.md`, «Exiting plan modes»). Автоматическая политика клиента SHALL NOT одобрять его: headless-политика `--approve read-only` отвечает `reject_once` (cli-headless «Политика одобрений headless»); в интерактивных клиентах решение принимает пользователь.

Для обновления вызова или запроса разрешения с незнакомым видом CodeLab SHALL сохранять вид записи для отображения, а уровень риска SHALL быть `max(риск записи, unknown)`, без записи — `unknown`. Обновление вызова или запрос разрешения с незнакомым видом или `switch_mode` SHALL NOT понижать уже известный уровень риска вызова (design.md change `tolerate-unknown-tool-kind`, D5, D9).

#### Scenario: Запрос на смену режима
- **WHEN** агент запрашивает разрешение на вызов с `kind: "switch_mode"` и вариантами `allow_always`, `allow_once`, `reject_once`
- **THEN** уровень риска одобрения — `unknown`, варианты агента показаны пользователю без изменений (`unknown_tool_kind_test.dart`)

#### Scenario: Незнакомый вид в tool_call
- **WHEN** агент присылает `tool_call` с `kind: "future_kind"` без diff и терминала, затем запрашивает на него разрешение
- **THEN** уровень риска записи вызова и одобрения — `unknown` (`unknown_tool_kind_test.dart`)

#### Scenario: Незнакомый вид в обновлении вызова чтения
- **WHEN** вызов пришёл с `kind: "read"` (риск `readOnly`), затем `tool_call_update` того же вызова с `kind: "future_kind"` без diff, терминала и опасного содержимого
- **THEN** вид вызова — `read`, уровень риска — `unknown`, и последующие обновления с `kind: "read"` риск не понижают (`unknown_tool_kind_test.dart`, «a read call lifted to unknown stays unknown…»)

#### Scenario: Запрос разрешения с незнакомым видом на вызов чтения
- **WHEN** вызов пришёл с `kind: "read"`, затем агент присылает `session/request_permission` для него с `toolCall.kind: "future_kind"`
- **THEN** вид вызова в ждущем одобрении — `read`, уровень риска одобрения — `unknown`, а не `readOnly` (`unknown_tool_kind_test.dart`, «a permission request with future_kind on a known read call keeps…»); тег в ленте app — agent-workbench-ui «Тег неизвестного риска одобрения»

#### Scenario: Headless read-only не одобряет незнакомый вид
- **WHEN** headless-запуск с `--approve read-only` получает запрос разрешения на вызов вида `read` с уровнем риска `unknown`
- **THEN** агент получает вариант `reject_once` с причиной `policy` (`approval_policy_test.dart` CLI, «read-only rejects a read whose risk is above readOnly»)

#### Scenario: Запрос разрешения на незнакомый вызов без записи
- **WHEN** агент запрашивает разрешение на вызов, которого нет в ходе, с `toolCall.kind: "future_kind"`
- **THEN** вид вызова — `other`, уровень риска — `unknown` (`unknown_tool_kind_test.dart`, «a permission request with future_kind on an unknown call is…»)

#### Scenario: Риск не понижается незнакомым видом
- **WHEN** вызов пришёл с `kind: "execute"` (риск `shell`), затем `tool_call_update` или `session/request_permission` того же вызова с `kind: "future_kind"` или `kind: "switch_mode"`
- **THEN** уровень риска вызова и одобрения остаётся `shell` (`unknown_tool_kind_test.dart`, «an execute call stays execute/shell…»)

## REMOVED Requirements

### Requirement: Режимы разрешений
**Reason**: Клиентские режимы `readOnly`, `ask`, `plan`, `autoEdits` в продукте не используются: `ApprovalPolicy.decidePermission` вызывают только тесты, `readOnly` в коде не отличается от `ask`, а запрос разрешения клиент всегда отдаёт пользователю. Запрет режима `bypass` противоречит агенту: режимы разрешений — его ответственность, и у него есть `yolo` и `autopilot` (спека `agent-permissions`, `codelab_agent_core/lib/src/permissions/modes.dart`, опция `mode` в `codelab_agent_acp/lib/src/config_options.dart`). Требование описывало несуществующее поведение (design.md change `align-cross-cutting-specs`, D9).
**Migration**: Режимы разрешений и их таблица решений — спека `agent-permissions`; выбор режима из клиента — опция конфигурации сессии ACP (`session/set_config_option`, acp-protocol-client «Исходящий session/set_config_option»). Автоматическая политика клиента — `--approve` CLI (cli-headless «Политика одобрений headless»). Мёртвые `PermissionMode`, `PermissionModeDecision`, `ApprovalPolicy.decidePermission` и `ApprovalPolicy.requiresExplicitApproval` удаляются из `codelab_client_acp` вместе с их тестами; `ApprovalRiskLevel` и `classifyToolCall*` остаются.
