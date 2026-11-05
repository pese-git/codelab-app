## ADDED Requirements

### Requirement: Клиентский доступ к секретам
`codelab_agent_io` SHALL предоставлять `ClientSecretAccess` (`lib/src/secrets/client_secret_access.dart`; реэкспорт из `codelab_setup/lib/io.dart`) — один путь клиентов (codelab-app, CLI) к хранилищу секретов агента (design.md change `add-provider-setup-ui`, D4):
- `open(codelabHome, environment, logger)` SHALL читать из `$CODELAB_HOME/config.yaml` только ключ `secrets.backend` (он допустим только в слое `user`) и открывать бэкенд `openSecretStore` с этим значением. Нечитаемый файл или недопустимое значение SHALL давать бэкенд `env` с `unavailableReason`, а не исключение: пока конфиг сломан, клиент ничего не записывает;
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
- **THEN** в первом случае `backend.id == "file"` и `writable == true`; во втором — `backend.id == "env"`, `writable == false`, `unavailableReason` непуст и не содержит строк файла

#### Scenario: Значение не утекает
- **WHEN** `read` выполняется для секрета со значением `sk-test-leak-0123456789`, а логгер записывает все события `ClientSecretAccess`
- **THEN** ни одно событие и ни один `toString()` результатов не содержит маркера
