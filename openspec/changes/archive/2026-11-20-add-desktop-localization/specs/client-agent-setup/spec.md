## ADDED Requirements

### Requirement: Типизированные ошибки и пояснения мастера провайдера
`ProviderSetupFlow` SHALL сопровождать каждое текстовое сообщение шага типизированными данными. По ним клиент строит текст на своём языке и не разбирает строку моста:
- состояния `EnteringBaseUrl`, `ChoosingKey`, `EnteringModelDetails` с ошибкой шага и `Reviewing` с ошибкой правки SHALL нести код ошибки (`errorCode`) из закрытого перечисления: адрес не `http` и не `https`; адрес с userinfo; хранилище секретов только для чтения; пустой ключ; сохранённый ключ уже есть; нечего оставлять; пустое имя переменной окружения; хранилище не записало ключ; окно контекста не положительное; лимит вывода не положительный; id провайдера занят или не подходит под шаблон; цель записи недоступна;
- у `EnteringBaseUrl`, `ChoosingKey` и `EnteringModelDetails` `error` SHALL быть задан тогда и только тогда, когда задан `errorCode`. Ошибку `Reviewing` SHALL сопровождать ровно одно из двух: `errorCode` (ошибка правки) или `refusal` (`PlanRefusal`, отказ записи плана);
- аргументы сообщений SHALL браться из полей состояния. У «сохранённый ключ уже есть» это имя секрета `existingSecret` (задано всегда вместе с этим кодом) и бэкенд `backend.id`. У «только чтение» — подсказка `readOnlyHint` и причина `backend.unavailableReason`, если они есть;
- `ChoosingKey` SHALL нести признак `literalKeyInConfig`: правится провайдер с литеральным ключом в файле конфига, и шаг показывает пояснение `notice`;
- `Reviewing` SHALL нести `notVerified` — вид пропущенной проверки (`unreachable` или `timeout`), если план записывается без проверки; иначе `null`.

Поля `error`, `notice` и `warnings` и их тексты SHALL не меняться: CLI показывает их как раньше. Новые поля SHALL быть аддитивными. Основной барель SHALL оставаться web-безопасным и без зависимости от локали. Тексты, которые мост получает от хранилища секретов или ядра агента, SHALL передаваться как есть. Это причина отказа записи ключа, подсказка бэкенда только для чтения и сообщения проблем конфига `ConfigIssue.message`.

#### Scenario: Пустой ключ
- **WHEN** на шаге ключа при записываемом бэкенде приходит `KeySubmitted(StoreSecret(''))`
- **THEN** состояние — `ChoosingKey` с кодом «пустой ключ» и `error` `Enter the API key.`

#### Scenario: Сохранённый ключ уже есть
- **WHEN** в хранилище есть `codelab/openai`, и пользователь выбирает `StoreSecret` без «Replace it»
- **THEN** `ChoosingKey` несёт код «сохранённый ключ уже есть» и `existingSecret` `codelab/openai`, а `error` — `A stored key codelab/openai already exists in <backend>.`, как до изменения

#### Scenario: Хранилище только для чтения без подсказки
- **WHEN** бэкенд секретов только для чтения, у него нет ни `readOnlyHint`, ни `unavailableReason`, и приходит `KeySubmitted(StoreSecret(…))`
- **THEN** `ChoosingKey` несёт код «хранилище секретов только для чтения» и `error` `The secret store is read-only.`

#### Scenario: Отказ записи плана без кода
- **WHEN** на «Review» приходит `ConfirmSave`, а провайдер с id плана уже появился в конфиге
- **THEN** `Reviewing` несёт `refusal` `providerExists` и `errorCode` `null`, а `error` — `A provider with this id already exists.`

#### Scenario: Ошибка правки на Review
- **WHEN** на «Review» приходит `ReviewEdited(providerId: 'Bad Id')`
- **THEN** `Reviewing` несёт код «id провайдера занят или не подходит под шаблон» и `refusal` `null`

#### Scenario: Литеральный ключ — признак, а не только текст
- **WHEN** правится провайдер с `api_key` в `config.yaml`, и мастер доходит до шага ключа
- **THEN** `ChoosingKey.literalKeyInConfig` — `true`, а `notice` — прежний английский текст

#### Scenario: Пропущенная проверка
- **WHEN** проверка закончилась `timeout`, пользователь подтверждает `SkipCheck`, выбирает модель, и мастер переходит в `Reviewing`
- **THEN** `Reviewing.notVerified` — `timeout`, а `warnings` — `Not verified: timeout`

#### Scenario: CLI не меняется
- **WHEN** мастер CLI добавляет провайдера `openai`, в хранилище уже есть `codelab/openai`, и автомат возвращает шаг ключа с ошибкой «сохранённый ключ уже есть»
- **THEN** CLI печатает строку ошибки `A stored key codelab/openai already exists in <backend>.`, как до изменения

#### Scenario: Ошибка с редактируемым провайдером
- **WHEN** мастер начинает правку провайдера, у которого в `base_url` есть userinfo
- **THEN** первое состояние — `EnteringBaseUrl` с кодом «адрес с userinfo» и `error` `Remove the user name and password from the address.`

### Requirement: Типизированные проблемы черновика MCP-сервера
Каждая проблема `McpDraftProblem`, которую возвращает `McpServerDraft.validate()` (и `McpServerInvalid.problems`), SHALL нести код из закрытого перечисления `McpDraftProblemCode`. По коду клиент строит текст на своём языке и не разбирает строку моста. Коды:
- имя не по правилу ядра;
- переименование при правке;
- имя уже есть в эффективном конфиге;
- пустая команда `stdio`;
- URL не `http` и не `https` или без хоста;
- URL с userinfo;
- ключ `env`/`headers` с пробелами по краям;
- два ключа с одним именем;
- пустое имя ключа;
- пустое значение нового секрета;
- два новых секрета с одним именем секрета.

У четырёх кодов о ключе (пробелы, совпадение, пустое значение секрета, совпадение имени секрета) проблема SHALL нести аргумент — имя ключа. У остальных кодов аргумента НЕ SHALL быть. Значение `env`, `headers`, URL или секрета в аргумент и в текст НЕ SHALL попадать.

Код и текст `message` SHALL строиться в одном месте моста. Текст `message` и его формулировки SHALL не меняться: CLI и прежние потребители показывают их как раньше. Для проблемы «два ключа с одним именем», которую клиент находит до построения черновика, мост SHALL давать способ построить проблему с кодом и тем же текстом, чтобы клиент не писал свою фразу. Новые поля SHALL быть аддитивными. Основной барель SHALL оставаться web-безопасным и без зависимости от локали.

#### Scenario: Ошибки черновика с кодами
- **WHEN** черновик имеет имя `a b`, тип `http` и URL `https://u:p@h/mcp`
- **THEN** `validate()` возвращает проблему с кодом «имя не по правилу ядра» и `message` `Use a name without spaces, [, ] or ".` и проблему с кодом «URL с userinfo» и `message` `Remove the user name and password from the URL.`; аргументов у них нет

#### Scenario: Код с именем ключа
- **WHEN** у `stdio`-черновика `docs` в `env` новый секрет `TOKEN` с пустым значением
- **THEN** `validate()` возвращает проблему поля `env` с кодом «пустое значение нового секрета», аргументом `TOKEN` и `message` `Enter the secret value for TOKEN.`

#### Scenario: Инвариант кода
- **WHEN** тест моста прогоняет `validate()` на всех черновиках своих сценариев
- **THEN** у каждой проблемы задан код, аргумент задан ровно у кодов о ключе, а `message` равен прежнему английскому тексту

#### Scenario: Совпавшие ключи до черновика
- **WHEN** клиент нашёл в форме два значения `headers` с именем `Authorization` и строит проблему средствами моста
- **THEN** проблема несёт код «два ключа с одним именем», аргумент `Authorization` и `message` `Two values are named Authorization.`

#### Scenario: CLI и web без изменений
- **WHEN** основной барель собирается для web, а CLI выводит проблемы черновика
- **THEN** сборка проходит, а тексты проблем совпадают с прежними

### Requirement: Типизированные подписи вида навыков
Вид расширений агента SHALL сопровождать английские подписи типизированными данными, по которым клиент строит подпись на своём языке:
- `SkillEntryView` SHALL нести `overridesScope` — область перекрытого навыка, которую называет `overridesLabel` (`Overrides <user|project|extra> skill`). Если подписи нет или она говорит о другом навыке той же области (`Overrides another skill`), `overridesScope` SHALL быть `null`. Правило выбора области SHALL оставаться в мосте, одно для подписи и поля;
- `SkillRootView` SHALL нести `extraEntry` — элемент `skills.extra_roots` как записан (или путь корня, если элемента нет) у известного корня области `extra`; у корней `project` и `user` и у неизвестного корня — `null`.

Подписи `overridesLabel` и `label` и их тексты SHALL не меняться. Новые поля SHALL быть аддитивными, а основной барель SHALL оставаться web-безопасным.

#### Scenario: Навык перекрывает пользовательский
- **WHEN** навык проекта `review` перекрывает навык `review` пользователя
- **THEN** `overridesLabel` — `Overrides user skill`, `overridesScope` — `user`

#### Scenario: Дополнительная папка навыков
- **WHEN** в `skills.extra_roots` записан `~/.claude/skills`, и из него загружен навык
- **THEN** `root.label` — `~/.claude/skills (extra root)`, `root.extraEntry` — `~/.claude/skills`
