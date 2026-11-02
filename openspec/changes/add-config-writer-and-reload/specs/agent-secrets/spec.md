## MODIFIED Requirements

### Requirement: Резолвер секретов
Ядро SHALL получать значение секрета только через `SecretResolver` (`codelab_agent_core/lib/src/secrets/`, чистый Dart, без `dart:io`). `SecretResolver.secret(name, purpose)` SHALL возвращать `SecretFound(value, source)`, `SecretMissing(backend)` или `SecretUnavailable(backend, reason)` (design.md change `add-agent-secret-store`, D3).

Порядок:
1. Кэш процесса содержит имя → `SecretFound(source: "cache")`.
2. Переменная `SecretNames.envOverride(name)` задана и непуста → её значение, `source: "env"`.
3. `DescribedSecretStore.read(name)`:
   - найдено → `source` — id бэкенда;
   - `null` или пусто → `SecretMissing`;
   - `SecretStoreUnavailableException` → `SecretUnavailable` и предупреждение `secrets.backend.unavailable {backend, reason}`, не чаще одного раза на пару `(backend, reason)` за процесс.

Найденное значение SHALL кэшироваться до вызова `invalidate()` или до конца жизни резолвера, ненайденное НЕ SHALL кэшироваться. `invalidate()` SHALL очищать кэш найденных значений; его вызывает перезагрузка конфигурации (capability `agent-runtime`, «Живая перезагрузка конфигурации»; design.md change `add-config-writer-and-reload`, D8). Чтение хранилища, начатое до `invalidate()` и завершившееся после, SHALL отдавать значение своим вызывающим, но НЕ SHALL класть его в кэш.

Одновременные запросы одного имени SHALL приводить к одному вызову `read` в пределах одного поколения кэша. Переменная переопределения SHALL побеждать хранилище при любом бэкенде. `SecretFound.toString()` НЕ SHALL содержать значение. `SecretResolver.env(variable, purpose)` SHALL читать только окружение, переданное резолверу.

#### Scenario: Переменная побеждает хранилище
- **WHEN** `MemorySecretStore` содержит `codelab/openai = store-value`, а окружение — `CODELAB_SECRET_CODELAB_OPENAI=env-value`
- **THEN** `secret("codelab/openai")` даёт `env-value` с `source: env`, а `read` хранилища не вызывается

#### Scenario: Кэш и отсутствие
- **WHEN** секрет `codelab/a` найден в хранилище, а `codelab/b` отсутствует; оба запрашиваются дважды, а между запросами `codelab/b` записывается в хранилище
- **THEN** `read("codelab/a")` вызван один раз, второй ответ — `source: cache`; `codelab/b` сначала `SecretMissing`, затем `SecretFound`

#### Scenario: Одно обращение на имя
- **WHEN** три вызова `secret("codelab/a")` начинаются до завершения первого `read`
- **THEN** хранилище получает один `read`, все три вызова получают одно значение

#### Scenario: Хранилище недоступно
- **WHEN** `read` бросает `SecretStoreUnavailableException(backend: "file", reason: "<path> has permissions 0644; run: chmod 600 <path>")` на двух разных именах
- **THEN** оба вызова дают `SecretUnavailable`, а в логе ровно одно `secrets.backend.unavailable`

#### Scenario: Сброс кэша
- **WHEN** `codelab/a` найден и закэширован со значением `v1`, затем хранилище получает `v2`, и вызывается `invalidate()`
- **THEN** следующий `secret("codelab/a")` вызывает `read` и даёт `v2` с `source` бэкенда

#### Scenario: Чтение во время сброса
- **WHEN** `read("codelab/a")` начат, затем вызван `invalidate()`, затем `read` завершается значением `v1`, а хранилище уже содержит `v2`
- **THEN** вызывающий первого запроса получает `v1`, а следующий `secret("codelab/a")` снова вызывает `read` и получает `v2`
