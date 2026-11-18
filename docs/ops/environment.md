# Переменные окружения `CODELAB_*`

Переменные окружения читают `codelab`, CodeLab app и `codelab-agent`. Встроенный агент внутри `codelab` и app получает окружение процесса клиента, поэтому ключи и настройки нужно задавать там, где запущен клиент. Агент, которого запускает Zed или другой клиент, берёт окружение своего процесса: задавайте переменные в `env` настроек запуска клиента.

Пустое значение переменной равно её отсутствию. Значения секретов не попадают в лог и тексты ошибок: сообщения называют только имя переменной.

## Каталог и конфигурация

| Переменная | Для чего |
|---|---|
| `CODELAB_HOME` | каталог настроек и данных. Правила раскрытия `~` и значение по умолчанию — в [каталоге `CODELAB_HOME`](codelab-home.md#где-лежит-каталог). `~` раскрывается через `HOME`, затем `USERPROFILE` |
| `CODELAB_CONFIG` | абсолютный путь к дополнительному файлу конфигурации (`.yaml` или `.yml`), слой 5 — выше `config.local.yaml`, ниже переменных. Относительный путь и другое расширение — ошибка; в `codelab-agent` это код выхода `64`. У `codelab-agent serve` есть флаг `--config`, который главнее переменной |

## Значения, у которых есть ключ конфигурации

Слой 6 [слоёв конфигурации](../user/configuration.md#слои-конфигурации): переменная ниже флагов, выше файлов. Источник: `packages/dart/codelab_agent_io/lib/src/config/environment_layer.dart`.

| Переменная | Ключ конфигурации | Замечания |
|---|---|---|
| `CODELAB_MODEL` | `agent.default_model` | вид `<провайдер>/<модель>` |
| `CODELAB_MAX_STEPS` | `budget.max_steps` | целое число; нечисловое значение — ошибка конфигурации без значения в тексте |
| `CODELAB_PERMISSION_MODE` | `permissions.mode` | `autopilot` из переменной отклоняется: режим включается только флагом `--permission-mode autopilot` |
| `CODELAB_LOG_LEVEL` | `logging.level` | регистр не важен |
| `CODELAB_LOG_FILE` | `logging.file` | путь к файлу лога агента |

## Провайдер и токены

| Переменная | Для чего |
|---|---|
| `CODELAB_PROVIDER_TYPE`, `CODELAB_PROVIDER_CONFIG` | предконфигурация одного провайдера: вид (`openai-compatible` или `anthropic`) и JSON с полями (`id`, `base_url`, `model`, `api_key_env`, `api_key_secret`, `headers` и другие). Без флагов `--provider-type` и `--provider-config`; если флаги заданы, переменные игнорируются |
| `CODELAB_PROVIDER_CONFIG_BASE64` | тот же JSON в base64 |
| `CODELAB_API_KEY` | ключ провайдера, заданного флагом `--provider` у `codelab-agent serve`. В остальных запусках ключ берут из переменной, названной в `api_key_env` провайдера |
| `CODELAB_SECRET_<ИМЯ>` | значение секрета без файла хранилища — для CI и серверов. Правило имени — [шаг 2 настройки](../user/configuration.md#шаг-2-задайте-ключ-api) |
| `CODELAB_AGENT_TOKEN` | Bearer-токен WebSocket. `codelab-agent serve --ws` читает его при старте (имя меняет `--token-env`); `codelab` берёт его для агента `ws://…`, если профиль не задаёт другую ссылку на токен |

В CodeLab app токен WebSocket-профиля хранится ссылкой (`env:<ИМЯ>` или `secret:<имя>`) и читается при подключении. `CODELAB_AGENT_TOKEN` — имя по умолчанию в диалоге профиля, в варианте «From environment variable»; задайте другое имя, если токен лежит в другой переменной.

## Диагностика

| Переменная | Для чего |
|---|---|
| `CODELAB_DEBUG_SECRETS=1` | то же, что флаг `--debug-secrets` у `codelab` и `codelab-agent serve`: агент пишет в лог событие `secrets.lookup` — имя секрета, назначение, источник и найден ли он. Значение не пишется. В app — в лог приложения |

## Не меняют поведение

Эти имена агент знает, чтобы не ругаться на них, но в коде репозитория их ничто не читает: `CODELAB_PROFILE`, `CODELAB_TOOLS`, `CODELAB_POWER_HELPER`, `CODELAB_DEBUG_LLM_SNAPSHOT`. Не опирайтесь на них.

`CODELAB_SERVE_ALIAS_ACTIVE` ставит себе переходный алиас `codelab serve` при запуске агента. Задавать её не нужно.

## Опечатки

Неизвестная переменная `CODELAB_*` даёт предупреждение `config.env.unknown` в `codelab-agent serve`, `codelab-agent config check` и `codelab config check`: опечатка не пропадает молча. Известны все имена выше, семейства `CODELAB_SECRET_*`, `CODELAB_PROVIDER_*` и `CODELAB_REDACTED_*`, а у `codelab-agent serve` — ещё переменная из `--token-env`.

## Только для сборки и тестов

Эти переменные и параметры сборки нужны разработчикам; в эксплуатации их не задают.

| Имя | Для чего |
|---|---|
| `CODELAB_TEST_SECRET_STORE` | каталог тестового хранилища секретов. Читается только в сборке с `--dart-define=CODELAB_ALLOW_TEST_SECRETS=true`; в обычной сборке даёт `config.env.unknown` |
| `CODELAB_TEST_REPORT_DIR` | абсолютный путь каталога, куда скрипты Melos (`test`, `conformance:*`) пишут отчёты о прогоне — см. `pubspec.yaml` в корне; для `conformance:embedded` — [`codelab`: проверка фикстурами](../../apps/codelab_cli/doc/operations.md#проверка-агента-фикстурами-test-scenario) |
| `CODELAB_PARITY_RESULTS`, `CODELAB_PARITY_APP_RESULTS`, `CODELAB_REPORT_LEAKS_DIR` | каталоги отчётов для проверок сторожа: статус строк матрицы паритета и поиск секретов в отчётах; без них проверки пропускаются — [`codelab_architecture_tests`](../../packages/dart/codelab_architecture_tests/README.md) |
| `--dart-define=CODELAB_LOG_SERVER_URL`, `CODELAB_LOG_SERVER_KEY` | отправка событий app на сервер логов, только в сборке разработчика — [эксплуатация app](../../apps/codelab_desktop/doc/operations.md#логи-и-диагностика) |

## Что ещё читают приложения

Переменные, которые не относятся к `CODELAB_*`, описаны у приложений: `NO_COLOR`, `TERM`, `LC_*`, `LANG` — в [эксплуатации `codelab`](../../apps/codelab_cli/doc/operations.md#переменные-окружения), `SHELL` — в [эксплуатации app](../../apps/codelab_desktop/doc/operations.md#переменные-окружения).
