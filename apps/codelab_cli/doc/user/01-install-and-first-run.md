# Установка и первый запуск

Установщика у `codelab` пока нет: его собирают из исходников. Глава проводит от сборки до первого вопроса агенту. Оглавление руководства — [руководство пользователя](../user-guide.md).

## Перед началом

- Нужен доступ к модели: ключ API облачного провайдера или локальный сервер (LM Studio, Ollama). Как это настроить — в [главе о провайдерах](06-providers.md).
- Агент работает в папке проекта. Запускайте `codelab` из неё или передайте папку флагом `-C <папка>`.

## Собрать `codelab`

1. Подготовьте репозиторий и сгенерируйте код по шагу 1 из [запуска из исходников](../../../../docs/user/run-from-source.md#1-подготовка).
2. Соберите бинарь из корня репозитория:

   ```bash
   fvm dart run melos run build:cli
   ```

   Появится файл `build/bin/codelab`.

3. Проверьте сборку:

   ```bash
   build/bin/codelab --version
   ```

   ```text
   codelab 0.1.0
   ```

В примерах руководства бинарь вызывается как `codelab`: добавьте `build/bin` в `PATH` или пишите полный путь. Подробнее о сборке — в [эксплуатации](../operations.md#сборка).

## Первый запуск

1. Откройте терминал в папке проекта и запустите:

   ```bash
   codelab
   ```

   Если провайдер модели ещё не настроен, откроется мастер:

   ```text
   No model provider is configured for the embedded agent.
   Let's set one up. Press Ctrl+C to quit; run "codelab provider add" later to change it.
   ? API type
     › OpenAI
       Anthropic
       OpenRouter
       Ollama (local, no key)
       Custom OpenAI-compatible endpoint
       Custom Anthropic-compatible endpoint
   ```

2. Выберите тип API стрелками ↑ и ↓ и нажмите Enter. Дальше мастер спросит адрес (`Base URL`), способ передать ключ (`API key source`), модель и, если её нет в списке сервера, размер контекстного окна. Ключ при вводе показывается звёздочками: Ctrl+R показывает и снова прячет его, Ctrl+U очищает поле.

   Если ключ нужно сохранить, а хранилище секретов ещё не настроено, мастер печатает строку `secret store env is read-only…` (она есть в снимке ниже). Она значит, что хранилище секретов пока только читает переменные окружения: ключ нельзя записать, его можно взять из переменной. Как включить запись — в [главе о секретах](07-secrets.md).

   Мастер проверяет адрес запросом `/models`. Если сервер недоступен, он предлагает повторить, продолжить без проверки или вернуться назад:

   ```text
   ? Base URL › http://127.0.0.1:9/v1
   secret store env is read-only. Add 'secrets.backend: file' to ~/.codelab/config.yaml to store secrets in ~/.codelab/secrets.yaml (plaintext, 0600), or set CODELAB_SECRET_<NAME> in the environment
   ? API key source
       Read from an environment variable
     › No key
   Checking http://127.0.0.1:9/v1/models … failed: Server unreachable
   ? The check failed
       Retry
     › Continue without checking
       Back
   not verified; the model list is unknown
   ? Model id › qwen3-demo
   ? Context window for qwen3-demo (tokens) › 32000
   ```

3. Проверьте сводку и подтвердите Enter (`? Save? [Y/n]`):

   ```text
   Provider "ollama"
     (openai-compatible, http://127.0.0.1:9/v1)
     key    none
     model  ollama/qwen3-demo (default)
     file   ~/.codelab/config.yaml
     Not verified: unreachable
   ? Save? [Y/n]
   Saving…
   Saved provider "ollama". Starting the embedded agent…
   >
   ```

   После `Saved provider "<id>". Starting the embedded agent…` откроется диалог с приглашением `> `.

4. Напишите вопрос и нажмите Enter.

   <!-- screenshot: текстовый снимок первого хода в построчном режиме: вопрос, ответ агента, приглашение `> ` — нужен живой провайдер модели -->

Ctrl+C в мастере выходит из `codelab` с кодом `130` и ничего не записывает. Мастер открывается только в терминале и только для встроенного агента: в `-p`, без терминала и с внешним агентом его нет.

Если провайдер настроен, но не хватает ключа, мастер не открывается. Что делает `codelab`, зависит от того, как провайдер ссылается на ключ.

**Ключ из переменной окружения (`api_key_env`).** `codelab` называет переменную, которую нужно задать:

```text
The key for "openai" is read from OPENAI_API_KEY, which is not set. Set it and restart codelab.
>
```

Задайте переменную и запустите `codelab` снова.

**Ключ из хранилища секретов (`api_key_secret`).** Если хранилище доступно для записи (`secrets.backend: file`), `codelab` предлагает сохранить ключ. Ввод ключа скрыт:

```text
Store a key for "openai" in file? [Y/n]
```

Ответ `n` запускает агента без ключа и подсказывает команду `codelab secret set <имя>`:

```text
Starting without a key for "openai". Store it later with: codelab secret set codelab/openai
>
```

Если хранилище только читает переменные окружения (бэкенд `env`), записать ключ некуда, и `codelab` сообщает, какую переменную задать:

```text
No writable secret store (OS keychain backends are not available in this version; set secrets.backend: file or CODELAB_SECRET_* variables). Set CODELAB_SECRET_CODELAB_OPENAI or the provider's api_key_env variable.
>
```

Секреты подробно — в [главе о секретах](07-secrets.md).

## Что дальше

- Команды диалога и клавиши — [глава «Диалог»](02-repl.md).
- Другие способы добавить провайдера и поменять модель — [провайдеры моделей](06-providers.md).
- Файлы `codelab`: каталог настроек — `~/.codelab`, другой задаёт переменная `CODELAB_HOME` — [каталог `CODELAB_HOME`](../../../../docs/ops/codelab-home.md).
