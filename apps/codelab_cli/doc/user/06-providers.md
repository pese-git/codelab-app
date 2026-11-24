# Провайдеры моделей

Провайдер — сервис, который выполняет модель: OpenAI, Anthropic, OpenRouter, Ollama или любой совместимый адрес. Глава объясняет, как добавить провайдера, посмотреть список и удалить провайдера, и как выбрать модель. Настройки хранятся в файле `config.yaml`; как он устроен — в [настройке агента](../../../../docs/user/configuration.md). Оглавление руководства — [руководство пользователя](../user-guide.md).

## Добавить провайдера

Три способа:

1. **Мастер.** `codelab provider add` в терминале без других флагов задаёт вопросы по шагам — как при [первом запуске](01-install-and-first-run.md#первый-запуск). В диалоге то же делает `/provider add`.
2. **Готовый набор без вопросов.** Флаг `--preset` принимает `openai`, `anthropic`, `openrouter`, `ollama`, `custom-openai` и `custom-anthropic`. `--yes` не спрашивает подтверждения, `--skip-check` сохраняет провайдера, даже если проверка адреса не дождалась ответа (сервер недоступен или не ответил вовремя).
3. **Все поля флагами.** Пример — в [шаге 1 настройки агента](../../../../docs/user/configuration.md#шаг-1-подключите-провайдера-и-модель).

Пример второго способа для локального сервера:

```bash
codelab provider add --preset ollama --base-url http://127.0.0.1:9/v1 --model qwen3-demo --context-window 32000 --yes --skip-check
```

```text
Saved provider "ollama". Models are available in /model.
```

- Если модели нет в списке, который вернул сервер, нужен `--context-window` — размер контекстного окна в токенах. Без него команда отвечает `missing required options: --context-window`.
- Для `custom-openai` и `custom-anthropic` нужен `--base-url`.
- Мастер и `--preset` сначала проверяют адрес запросом `/models`. Если сервер недоступен и нет `--skip-check`, команда завершается ошибкой:

  ```text
  codelab: provider check failed: unreachable (http://127.0.0.1:9)
  ```

- С `--preset` слой проекта (`--project`) не поддерживается: используйте `--local` или файл пользователя. Флаг `--api-key-secret` с `--preset` тоже не поддерживается: подайте ключ через `--api-key-stdin` или `--api-key-env`.
- Без терминала `--preset` требует `--yes`.

### Ключ API

Ключ API не передаётся аргументом: строка команды остаётся в истории оболочки и видна в списке процессов. Укажите:

| Флаг | Что делает |
|---|---|
| `--api-key-env <ПЕРЕМЕННАЯ>` | ключ берётся из переменной окружения; в файл пишется только её имя |
| `--api-key-secret <имя>` | ключ берётся из хранилища секретов по имени |
| `--api-key-stdin` | ключ читается со stdin и записывается в хранилище как `codelab/<id>` |

`--api-key-stdin` записывает ключ в хранилище секретов, поэтому нужен файловый бэкенд `secrets.backend: file` — см. [главу о секретах](07-secrets.md) и [шаг 2 настройки агента](../../../../docs/user/configuration.md#шаг-2-задайте-ключ-api). Локальные серверы без ключа (LM Studio, Ollama) обходятся без этих флагов.

### Полный набор флагов

Без `--preset` команда принимает все поля провайдера:

```bash
codelab provider add lmstudio --kind openai-compatible --base-url http://127.0.0.1:1234/v1 --model qwen/qwen3-1.7b --context-window 32768 --default
```

| Флаг | Что задаёт |
|---|---|
| `<id>` | имя провайдера в конфигурации |
| `--kind` | тип API: `openai-compatible`, `anthropic` или `gemini` (`gemini` — только без `--preset`, `--yes`, `--skip-check`) |
| `--base-url` | адрес провайдера |
| `--model`, `--context-window` | модель и размер её контекстного окна в токенах |
| `--api-key-secret`, `--api-key-env`, `--api-key-stdin` | ключ API, см. выше |
| `--default` | сделать `<id>/<модель>` моделью по умолчанию |
| `--project`, `--local` | записать в файл проекта (`.codelab/config.yaml`) или в локальный файл проекта (`.codelab/config.local.yaml`) вместо файла пользователя |

Справку печатает `codelab provider` без аргументов.

## Посмотреть и удалить провайдеров

```bash
codelab provider list
```

```text
Secrets: env (OS keychain backends are not available in this version; set secrets.backend: file or CODELAB_SECRET_* variables)
lmstudio  kind: openai-compatible  base_url: http://127.0.0.1:1234/v1  models: qwen/qwen3-1.7b  key: none
```

Первая строка называет хранилище секретов. `--cwd <папка>` у `provider list` читает проектные слои другой папки.

Удалить провайдера: `codelab provider remove <id>`. Если удаляемый провайдер задаёт модель по умолчанию, команда отказывает и просит сначала сменить её:

```bash
codelab provider remove lmstudio
```

```text
~/.codelab/config.yaml:2:3: agent.default_model: lmstudio/qwen/qwen3-1.7b is not in the model catalog; declare it in providers.lmstudio.models
change the model first: config set agent.default_model <provider>/<model>
```

Смените модель по умолчанию командой `codelab config set agent.default_model <провайдер>/<модель>` и повторите удаление.

## Выбрать модель

- Модель по умолчанию — ключ `agent.default_model` вида `<провайдер>/<модель>`. Задайте его командой `--default` при добавлении провайдера или `codelab config set agent.default_model …` — [проверка и правка настроек](09-config.md).
- `-m <id>` выбирает модель для одного запуска, `/model` меняет её в диалоге — [папка, модель, режим и агент](05-folder-model-agent.md#выбрать-папку-модель-и-режим).
- Цена модели (`cost_input`, `cost_output`) нужна, чтобы строка статуса показывала стоимость.

Лимиты хода и рассуждение модели — в [главе о модели и провайдерах](../../../codelab_agent/doc/user/03-model-and-providers.md#лимиты-хода).

## Смотрите также

- [Секреты](07-secrets.md)
- [Настройка агента](../../../../docs/user/configuration.md)
- [Справочник флагов и команд](11-reference.md)
