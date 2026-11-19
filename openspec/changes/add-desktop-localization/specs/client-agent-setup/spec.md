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
