# Проверка и правка настроек

Настройки агента лежат в файлах `config.yaml` в нескольких слоях: у пользователя и в проекте. Глава объясняет, как проверить конфигурацию до запуска агента, посмотреть значение ключа и изменить его командами `codelab config` и из диалога. Что значат слои и ключи — в [настройке агента](../../../../docs/user/configuration.md). Оглавление руководства — [руководство пользователя](../user-guide.md).

## Проверить конфигурацию

```bash
codelab config check
```

```text
Sources: defaults, ~/.codelab/config.yaml
Default model: lmstudio/qwen/qwen3-1.7b (config)
Config: valid
```

`config check` читает файлы так же, как агент, печатает источники, ошибки и предупреждения с файлом и строкой. Код выхода `0` — конфигурация годится, `1` — есть ошибки. Если модель не настроена (пустой `CODELAB_HOME`):

```bash
codelab config check
```

```text
Sources: defaults
defaults: agent.default_model: no model is configured; add a provider with at least one model
Config: invalid (issues: 1)
```

Предупреждение о переменной с ключом (`the environment variable with the API key is not set`) значит, что в вашем окружении её нет, а ошибкой не считается — [шаг 3 настройки агента](../../../../docs/user/configuration.md#шаг-3-проверьте-конфигурацию). `--cwd <папка>` проверяет слои проекта другой папки.

## Где лежат файлы

```bash
codelab config path
```

```text
user: ~/.codelab/config.yaml (exists)
project: ~/projects/demo/.codelab/config.yaml (missing)
local: ~/projects/demo/.codelab/config.local.yaml (missing)
```

| Слой | Файл | Для чего |
|---|---|---|
| `user` | `$CODELAB_HOME/config.yaml` | ваши настройки для всех проектов |
| `project` | `<проект>/.codelab/config.yaml` | настройки проекта, их можно хранить в репозитории |
| `local` | `<проект>/.codelab/config.local.yaml` | ваши настройки только для этого проекта |

Приоритет слоёв и правила слияния — [слои конфигурации](../../../../docs/user/configuration.md#слои-конфигурации). `config path --project` и `--local` печатают путь одного файла.

## Прочитать значение

```bash
codelab config get agent.default_model
```

```text
lmstudio/qwen/qwen3-1.7b
layer: user
```

`config get <ключ> --layer user|project|local|merged` показывает значение одного слоя или итог всех слоёв (`merged` — по умолчанию). Ссылки вида `${VAR}` не раскрываются, а значения, похожие на секреты, маскируются. Если ключ не задан, команда пишет `config get: <ключ> is not set` (или `… is not set in the project layer`, если выбран слой).

## Изменить значение

Значения правят `config set` и `config unset`; по умолчанию они пишут в файл пользователя, а `--project` и `--local` выбирают файл проекта. Команды сохраняют комментарии в файле.

```bash
codelab config set agent.default_model lmstudio/qwen/qwen3-1.7b --project
```

```text
Updated agent.default_model in ~/projects/demo/.codelab/config.yaml
```

```bash
codelab config unset agent.default_model --project
```

```text
Removed agent.default_model from ~/projects/demo/.codelab/config.yaml
```

Опечатка в ключе не записывается:

```bash
codelab config set agent.default_modell x
```

```text
config set: unknown key agent.default_modell; did you mean agent.default_model?
```

Если изменение требует перезапуска агента, команда напоминает об этом строкой `note: restart the agent to apply: <ключ>`. Папку проекта для `--project` и `--local` выбирают по порядку: `--cwd <папка>` подкоманды, общий `-C`, текущая папка.

## Настройки из диалога

В диалоге и в полноэкранном режиме те же настройки доступны командой `/settings`: она показывает ключи в виде `ключ  значение  источник` и записывает значение в файл пользователя (`--local` — в локальный файл проекта), а `<ключ> --reset` удаляет ключ из слоя. Слой проекта (`.codelab/config.yaml`) из диалога не правится. В полноэкранном режиме `/settings` открывает экран с разделами — [глава о полноэкранном режиме](03-tui.md#настройки-и-мастер-провайдера).

```text
> /settings
Settings (key, value, source):
    agent.default_model  lmstudio/qwen/qwen3-1.7b  user
    agent.effort  medium  default
    providers.lmstudio.kind  openai-compatible  user
    providers.lmstudio.base_url  http://127.0.0.1:1235/v1  user
    providers.lmstudio.api_key_env  (not set)  default
    …
    providers.lmstudio.models.qwen/qwen3-1.7b.context_window  32768  user
    …
```

`/settings <ключ>` без значения предлагает допустимые значения и отмечает текущее:

```text
> /settings agent.effort
Reasoning effort (agent.effort):
    low
  * medium
    high
```

Часть настроек агента — лимиты хода (`budget.*`), субагенты, сжатие контекста, уровень журнала — описана в руководстве агента: [лимиты хода](../../../codelab_agent/doc/user/03-model-and-providers.md#лимиты-хода), [субагенты](../../../codelab_agent/doc/user/07-subagents-and-tasks.md), [сжатие контекста](../../../codelab_agent/doc/user/09-sessions.md).

## Другие подкоманды

- [`codelab provider`](06-providers.md) — провайдеры моделей.
- [`codelab mcp`](08-mcp.md) — MCP-серверы.
- [`codelab secret`](07-secrets.md) — секреты.
- Переменная `CODELAB_CONFIG` подставляет другой файл конфигурации; все переменные `CODELAB_*` — в [переменных окружения](../../../../docs/ops/environment.md).

## Смотрите также

- [Настройка агента](../../../../docs/user/configuration.md)
- [Каталог `CODELAB_HOME`](../../../../docs/ops/codelab-home.md)
- [Справочник флагов и команд](11-reference.md)
