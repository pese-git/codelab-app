## ADDED Requirements

### Requirement: Клиентский доступ к секретам
`codelab_agent_io` SHALL предоставлять `ClientSecretAccess` (`lib/src/secrets/client_secret_access.dart`; реэкспорт из `codelab_setup/lib/io.dart`) — один путь клиентов (codelab-app, CLI) к хранилищу секретов агента (design.md change `add-provider-setup-ui`, D4):
- `open(codelabHome, environment, logger)` SHALL читать из `$CODELAB_HOME/config.yaml` только ключ `secrets.backend` (он допустим только в слое `user`) и открывать бэкенд `openSecretStore` с этим значением. Нечитаемый файл или недопустимое значение SHALL давать бэкенд `env` с `unavailableReason`, а не исключение: пока конфиг сломан, клиент ничего не записывает;
- `configProblem` SHALL быть непустым, только если `open` откатился на `env` из-за пользовательского конфига (нечитаемый файл, битый YAML, значение `secrets.backend` не строкой или недопустимое), и содержать тот же фиксированный текст, что `backend.unavailableReason`, без строк файла и без эха значения. При отсутствии файла или ключа и при `auto`, `env`, `file` — `null`; так клиент отличает сломанный конфиг от обычного `auto → env`;
- `backend` SHALL отдавать `SecretBackendInfo` выбранного бэкенда; `admin` — `SecretAdmin` над ним (запись, проверка, удаление, список имён по требованию «Программная запись секретов»);
- `isSet(name)` SHALL отвечать по `names()` бэкенда и непустой переменной `SecretNames.envOverride(name)`, не читая значения;
- `read(name)` SHALL возвращать значение переменной `SecretNames.envOverride(name)`, если она непуста, иначе значение бэкенда, иначе `null` — тот же порядок, что у резолвера агента. Результат НЕ SHALL кэшироваться: каждое чтение обращается к переменной и бэкенду заново.

Ни один метод НЕ SHALL писать значение в журнал, исключение или `toString()`; ошибка бэкенда при `read` SHALL давать `SecretStoreUnavailableException` с причиной без значения.

#### Scenario: Тот же порядок, что у агента
- **WHEN** в `file` сохранён `codelab/p` = `a`, а окружение клиента содержит `CODELAB_SECRET_CODELAB_P=b`
- **THEN** `read('codelab/p')` возвращает `b`; без переменной — `a`; `isSet('codelab/p')` в обоих случаях `true`

#### Scenario: Без кэша
- **WHEN** `read('codelab/p')` вернул `a`, после чего `codelab secret set codelab/p` в другом процессе записал `c`
- **THEN** следующий `read('codelab/p')` того же экземпляра возвращает `c`

#### Scenario: Бэкенд по пользовательскому слою
- **WHEN** `$CODELAB_HOME/config.yaml` содержит `secrets.backend: file`, затем — синтаксическую ошибку YAML
- **THEN** в первом случае `backend.id == "file"`, `writable == true` и `configProblem == null`; во втором — `backend.id == "env"`, `writable == false`, `unavailableReason` и `configProblem` непусты и не содержат строк файла

#### Scenario: Обычный auto без проблемы конфига
- **WHEN** `config.yaml` нет или в нём нет `secrets.backend`, затем `secrets.backend: wat`
- **THEN** в первом случае бэкенд `env` с `unavailableReason` про `auto`, а `configProblem == null`; во втором — бэкенд `env` и непустой `configProblem` без значения `wat`

#### Scenario: Значение не утекает
- **WHEN** `read` выполняется для секрета со значением `sk-test-leak-0123456789`, а логгер записывает все события `ClientSecretAccess`
- **THEN** ни одно событие и ни один `toString()` результатов не содержит маркера
