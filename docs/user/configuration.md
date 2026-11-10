# Настройка агента

Встроенный агент CodeLab и бинарь `codelab-agent` читают одни и те же файлы `config.yaml`. Здесь — минимум, чтобы подключить модель. Полная схема ключей — [agent-core/15-configuration.md](../architecture/proposals/agent-core/15-configuration.md).

Команды ниже можно вызывать как `codelab …` или `codelab-agent …`: подкоманды `config` и `secret` у них общие.

## Слои конфигурации

Агент собирает настройки из файлов. Чем ниже в таблице, тем выше приоритет: позднейший слой перекрывает ранний.

| № | Файл | Для чего |
|---|---|---|
| 1 | значения по умолчанию | встроены в агент |
| 2 | `$CODELAB_HOME/config.yaml` (по умолчанию `~/.codelab/config.yaml`) | ваши провайдеры и ключи; общий для всех проектов |
| 3 | `<проект>/.codelab/config.yaml` | настройки проекта; его коммитят в репозиторий |
| 4 | `<проект>/.codelab/config.local.yaml` | ваши правки только для этого проекта; обычно в `.gitignore` |
| 5 | файл из `--config <файл>` (только у `codelab-agent serve`) или `CODELAB_CONFIG=<абсолютный путь>` | разовая подмена при запуске |
| 6 | переменные `CODELAB_*` | окружение запуска |
| 7 | флаги `codelab-agent serve` | запуск |

Проектный файл приходит из репозитория, поэтому ему доверяют не полностью. Отброшенный ключ не ломает запуск: агент печатает предупреждение `config.project.untrusted_key` с именем ключа и причиной.

- **Всегда, для слоёв 3 и 4.** `trusted_projects` и `secrets` читаются только из глобального конфига.
- **Слой 3 — всегда, даже у доверенного проекта.** Разделы `sessions`, `logging`, `exec` и `config` не читаются. `permissions.mode` может только ужесточить режим нижних слоёв.
- **Слои 3 и 4, пока проект не назван в `trusted_projects` глобального конфига.** Не читаются провайдеры (`providers`, `model_catalog`), MCP-серверы (`mcp.servers`) и `prompts`. Слой 4 теряет и `sessions`, `logging`, `exec`, `config`, и смягчение режима. Разрешения только ужесточаются: `permissions.deny` добавляется к спискам нижних слоёв, правило `permissions.tools.<инструмент>` применяется, только если оно строже нижнего. Редакция (`redact`), бюджеты и размер контекста проекта тоже только ужесточаются.

У доверенного проекта `config.local.yaml` (слой 4) не ограничен. Полные правила — [§15.3](../architecture/proposals/agent-core/15-configuration.md). Провайдеров держите в глобальном файле.

Посмотреть, где лежат файлы слоёв:

```bash
codelab config path            # все слои: user, project, local (и CODELAB_CONFIG, если задана) с пометкой (exists) или (missing)
codelab config path --project  # только путь <проект>/.codelab/config.yaml, без пометки
codelab config path --local    # только путь <проект>/.codelab/config.local.yaml
```

`config path` ничего не создаёт: путь с флагом удобно передать редактору — `$EDITOR "$(codelab config path --local)"`. Файл создаёт `codelab config set`.

Файл можно править руками или командами `codelab config set <ключ> <значение> [--project | --local]`: они сохраняют ваши комментарии. Запущенный агент подхватывает часть ключей на лету, остальные — после перезапуска; команда подскажет, какой случай ваш.

## Шаг 1. Подключите провайдера и модель

Минимальный `~/.codelab/config.yaml`:

```yaml
agent:
  default_model: openai/gpt-4o        # <id провайдера>/<id модели>

providers:
  openai:                             # id провайдера выбираете вы
    kind: openai-compatible           # или anthropic
    base_url: https://api.openai.com/v1
    api_key_env: OPENAI_API_KEY       # имя переменной окружения, не сам ключ
    models:
      gpt-4o:
        context_window: 128000
        max_output_tokens: 16384
```

То же командой (ключ не передаётся аргументом, только имя переменной):

```bash
codelab provider add openai --kind openai-compatible \
  --base-url https://api.openai.com/v1 --model gpt-4o --context-window 128000 \
  --api-key-env OPENAI_API_KEY --default
```

Модель, которой нет в `providers.<id>.models`, агент не примет: `config check` скажет об этом.

## Шаг 2. Задайте ключ API

Ключ не пишут в `config.yaml` значением. Есть два способа, оба хранят в файле только имя.

**Переменная окружения — `api_key_env`.** Самый простой способ:

```yaml
providers:
  openai:
    api_key_env: OPENAI_API_KEY
```

Переменная должна быть задана в окружении того, кто запускает агента. Встроенный агент в приложении получает окружение приложения, поэтому для приложения, запущенного из меню, а не из терминала, надёжнее второй способ.

**Именованный секрет — `api_key_secret`:**

```yaml
providers:
  openai:
    api_key_secret: codelab/openai
```

Значение секрета берётся из хранилища. Бэкенд по умолчанию (`secrets.backend: auto`) в этой версии — `env`: хранилище только читает переменные `CODELAB_SECRET_<ИМЯ>`. Для секрета `codelab/openai` это `CODELAB_SECRET_CODELAB_OPENAI`: имя в верхнем регистре, `/` и другие знаки меняются на `_`.

Хотите, чтобы `codelab secret set` записывал значения сами, включите файловый бэкенд в глобальном конфиге (хранилища ОС в этой версии нет):

```bash
codelab config set secrets.backend file
codelab secret set codelab/openai   # спросит значение; ввод не отображается
codelab secret list                 # печатает имена, не значения
```

Значение секрета не набирают в командной строке: аргумент и `echo "<ключ>" | …` остаются в истории оболочки и видны в списке процессов. В скрипте подавайте значение на stdin из переменной, прочитанной без эха, или из файла:

```bash
read -rs KEY && printf %s "$KEY" | codelab secret set codelab/openai; unset KEY
codelab secret set codelab/openai < ~/путь/к/файлу-с-ключом
```

Файловый бэкенд кладёт секреты открытым текстом в `$CODELAB_HOME/secrets.yaml` (права `0600`), и `secret set` предупреждает об этом. На Windows он не поддерживается — используйте `CODELAB_SECRET_*`. Раздел `secrets` читается только из глобального конфига: репозиторий не может его переключить.

Локальные серверы без ключа (LM Studio, Ollama) обходятся без обоих ключей `api_key_*`.

## Шаг 3. Проверьте конфигурацию

```bash
codelab config check
```

Пример вывода для рабочего конфига:

```text
Sources: defaults, /home/me/.codelab/config.yaml
Default model: openai/gpt-4o (config)
Config: valid
```

Команда читает файлы так же, как агент, и печатает использованные источники, ошибки и предупреждения с файлом, строкой и столбцом. Код выхода `0` — конфиг годится, `1` — есть ошибки. Типичные случаи:

```text
/home/me/.codelab/config.yaml:2:3: agent.default_modell: unknown key (did you mean default_model?)
Config: invalid (issues: 1)
```

```text
warning: /home/me/.codelab/config.yaml:7:5: providers.openai.api_key_env: the environment variable with the API key is not set
```

Предупреждение про переменную означает, что в окружении, где вы запустили проверку, её нет. Это не ошибка (код выхода `0`): важно, чтобы переменная была у того, кто запускает агента. `config check` не показывает значений ключей.

Остальные подкоманды: `codelab config get <ключ> [--layer user|project|local|merged]` показывает ключ и слой, откуда он взят (секретоподобные значения маскируются); `codelab config unset <ключ>` удаляет ключ.

## Пример: LiteLLM Proxy

[LiteLLM Proxy](https://docs.litellm.ai/docs/simple_proxy) выставляет десятки провайдеров как один OpenAI-совместимый эндпоинт. Для агента это обычный `openai-compatible` провайдер с адресом прокси в `base_url`. Отдельного вида провайдера «litellm» нет.

```yaml
agent:
  default_model: litellm/gpt-4o

providers:
  litellm:
    kind: openai-compatible
    base_url: http://localhost:4000/v1     # адрес вашего прокси
    api_key_env: LITELLM_API_KEY           # ключ прокси (master key или виртуальный)
    models:
      gpt-4o:                              # имя модели, как оно задано в конфиге прокси
        context_window: 128000
        max_output_tokens: 16384
```

Запустите прокси, задайте `LITELLM_API_KEY` в окружении и проверьте `codelab config check`. Если прокси требует свои заголовки, добавьте их в `providers.litellm.headers`; секреты в них пишутся ссылкой `${secret:<имя>}` или `${ПЕРЕМЕННАЯ}`.

## Пример: локальная модель (LM Studio)

В LM Studio запустите локальный сервер (по умолчанию `http://127.0.0.1:1234/v1`) и загрузите модель. Идентификатор модели смотрите в ответе сервера: `curl http://127.0.0.1:1234/v1/models`.

```yaml
agent:
  default_model: lmstudio/qwen/qwen3-1.7b

providers:
  lmstudio:
    kind: openai-compatible
    base_url: http://127.0.0.1:1234/v1
    models:
      qwen/qwen3-1.7b:                    # id модели целиком, с «/»
        context_window: 32768
        max_output_tokens: 4096
```

Ключ не нужен. Проверка и первый запрос:

```bash
codelab config check
codelab -p "Reply with the single word: pong"
```

Тот же файл подходит для Ollama: `base_url: http://localhost:11434/v1`, модель — как в `ollama list`.

## Что попадает в логи и журналы

- Значения из хранилища секретов и ключи API агент не логирует; `config check` и `secret list` значений не показывают, `config get` маскирует секретоподобные значения.
- На уровне лога `trace` вывод stderr MCP-серверов попадает в лог без редактирования: он может нести их секреты. Уровень `trace` включайте только для отладки.
- **До выпуска 1.0 тексты промптов и вывод инструментов не редактируются** ни в журнале сессии (`$CODELAB_HOME/sessions/…`), ни в логах агента. Если в разговоре был ключ или личные данные, они остаются в этих файлах. Не публикуйте журналы и логи, не просмотрев их.
- Каталог `$CODELAB_HOME/logs` и файл лога по умолчанию агент сам не создаёт. Файл лога пишет только `codelab-agent serve`, и только если задан `--log-file`, `CODELAB_LOG_FILE` или `logging.file`; встроенный агент в `codelab` и app `logging.file` пока не применяет.

## Что дальше

- Перешли с Python-агента — [перенос настроек](migrating-from-python-agent.md).
- Хотите подключить агента к Zed — [zed.md](zed.md).
