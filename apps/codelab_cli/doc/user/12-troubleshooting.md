# Если что-то пошло не так

В главе — сообщения, которые печатает `codelab`, их причины и что сделать. Тексты сообщений взяты из кода и проверены запуском; сообщения агента и провайдера в других местах могут отличаться. Оглавление руководства — [руководство пользователя](../user-guide.md). Коды выхода — в [справочнике](11-reference.md#коды-выхода).

## Запуск и настройка

| Что видите | Почему | Что сделать |
|---|---|---|
| `codelab: …: agent.default_model: no model is configured; add a provider with at least one model` и `Configure the embedded agent in ~/.codelab/config.yaml; check it with: codelab config check` | у встроенного агента нет модели; невалидная конфигурация встроенного агента завершает `codelab` с кодом `64` | запустите `codelab` в терминале — откроется мастер, — или `codelab provider add` |
| `The key for "openai" is read from OPENAI_API_KEY, which is not set. Set it and restart codelab.` (в диалоге) или `codelab: API key variable OPENAI_API_KEY is not set (auth)` (в `-p`) | у провайдера задан `api_key_env`, а переменной нет в окружении `codelab` | задайте переменную в том терминале, где запускаете `codelab`, или сохраните ключ в [хранилище секретов](07-secrets.md) |
| `warning: …: providers.<id>.api_key_env: the environment variable with the API key is not set` в `codelab config check` | в окружении, где запущена проверка, переменной нет; код выхода при этом `0` | задайте переменную там, где будете запускать агента |
| `secret store env is read-only. Add 'secrets.backend: file' to … to store secrets in …` | значение секрета записать некуда: хранилище только читает `CODELAB_SECRET_<ИМЯ>` | включите файловый бэкенд — `codelab config set secrets.backend file` — или задайте переменную `CODELAB_SECRET_<ИМЯ>` |
| `codelab: provider check failed: unreachable (http://127.0.0.1:9)` | адрес провайдера не ответил на запрос `/models` | проверьте адрес и что сервер запущен; для локального сервера, который запустите позже, добавьте `--skip-check` |
| `codelab: missing required options: --context-window` | модели нет в списке сервера, а размер контекстного окна не задан | добавьте `--context-window <токены>` |
| `change the model first: config set agent.default_model <provider>/<model>` при `provider remove` | удаляемый провайдер задаёт модель по умолчанию | смените модель командой `codelab config set agent.default_model …` и повторите |
| `config set: unknown key agent.default_modell; did you mean agent.default_model?` | опечатка в ключе | поправьте ключ |
| `warning: …: providers.<id>.api_key: a secret is stored in the config file; move it to the secret store: codelab secret migrate` | ключ записан в файле значением | выполните `codelab secret migrate` — [секреты](07-secrets.md#перенести-ключи-из-конфигурации-в-хранилище) |
| `codelab: profile <id> has no stored secret value; connecting without a token.` | профиль ссылается на секрет, которого нет в хранилище | сохраните его: `codelab secret set <имя>` |

## Диалог и ходы агента

| Что видите | Почему | Что сделать |
|---|---|---|
| `codelab: request failed after 4 attempts in …` (в `-p`) или `error: request failed after …` (в диалоге) с `network (connection failed: …)` | провайдер модели не отвечает по адресу из конфигурации | проверьте адрес и что сервер запущен; для локальной модели — что запущены LM Studio или Ollama |
| `The turn stopped: budget exceeded: <лимит>.` в диалоге | ход остановился: агент исчерпал лимит бюджета. `<лимит>` — `steps` (`budget.max_steps`), `tokens` (`budget.max_tokens`), `cost` (`budget.max_cost`) или `duration` (`budget.max_duration`) | увеличьте соответствующий ключ секции `budget` в конфигурации агента и перезапустите агента. Если агент не назвал лимит, заметка читается «The turn reached the limit of model requests.» |
| ответ долго не приходит, хотя провайдер доступен | агент ждёт ваше разрешение или модель отвечает медленно | посмотрите, нет ли блока запроса разрешения — [разрешения](02-repl.md#разрешения); отмените ход Esc |
| клавиша `a` в запросе разрешения ничего не делает | агент не предложил вариант «разрешать всегда» | выберите `y` или `n` |
| `Session not found: <id>` при `--resume` | в папке нет сессии с таким идентификатором | посмотрите список `/sessions` или запустите с `-c` |
| `Nothing to cancel.` после `/cancel` | сейчас нет идущего хода | — |

## Выбор агента и режима

| Что видите | Почему | Что сделать |
|---|---|---|
| `codelab: Unknown agent profile. Run "codelab profiles list".` | профиля с таким id нет | посмотрите `codelab profiles list` |
| `codelab: cannot start the agent ws://…: Failed to connect ACP transport.` | агент по `ws://` недоступен или не принимает соединение | проверьте адрес и что агент запущен |
| `codelab: cannot start the agent "<команда>" with N arguments: Failed to connect ACP transport.` | программу-агент `stdio:…` не удалось запустить | проверьте, что команда есть в `PATH` и запускается в папке сессии |
| `the agent rejected the token (HTTP 401).` или `the agent requires a token (HTTP 401).` | агент по WebSocket не принял токен или ждёт его | задайте `CODELAB_AGENT_TOKEN` или секрет профиля |
| `codelab: embedded is built in; use --agent embedded` | попытка сохранить профиль с именем `embedded` или `default` | выберите другой id — [профили](05-folder-model-agent.md#профили) |
| `Provider settings are read-only for a remote agent. Run "codelab provider add" on the agent host.` | `/provider` или `/settings` выполнены при подключении к агенту по WebSocket | настройте провайдера на машине агента |

## Флаги и режимы

| Что видите | Почему | Что сделать |
|---|---|---|
| `codelab: --ui tui needs a terminal on stdin and stdout` | полноэкранный режим запущен с перенаправленным вводом или выводом | запустите в терминале без `<`, `>` и `\|` |
| `codelab: --ui applies only to the interactive mode` | `--ui=tui` вместе с `-p` | уберите один из флагов |
| `codelab: No prompt.` | пустой запрос в `-p`, `-f` или stdin | передайте текст запроса |
| `codelab: No such folder: <папка>` | папка из `-C` не существует | укажите существующую папку |
| `codelab: Unknown flag --foo` | нет такого флага | сверьтесь с `codelab --help` |
| `codelab: "foo" is not an allowed value for option "--approve".` | неверное значение флага | допустимы `reject`, `read-only`, `allow-all` |
| `codelab: Invalid duration "<значение>": use e.g. 90s, 10m, 1h30m.` | неверный формат `--timeout` | запишите время как `90s`, `10m` или `1h30m` |
| `codelab: timeout after <N>s, cancelling the turn` и код `130` | истёк `--timeout` | увеличьте предел или упростите запрос |
| `codelab: no fixtures were played` и код `1` (в `test-scenario`) | фильтр ничего не выбрал или все фикстуры пропущены | проверьте `--filter` и путь |

## Если проблема осталась

1. Запустите с `-v`: в stderr появится диагностика соединения.
2. Проверьте настройки: `codelab config check`.
3. Задайте чистый `CODELAB_HOME` и повторите запуск — так видно, виноваты ли старые файлы настроек: [каталог `CODELAB_HOME`](../../../../docs/ops/codelab-home.md).
4. Что попадает в логи и журналы сессий — [настройка агента](../../../../docs/user/configuration.md#что-попадает-в-логи-и-журналы).

## Смотрите также

- [Справочник флагов и команд](11-reference.md)
- [Эксплуатация `codelab`](../operations.md)
