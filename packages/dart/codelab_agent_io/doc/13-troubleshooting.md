# Частые проблемы разработчика

Глава собирает случаи, с которыми сталкивается тот, кто меняет `codelab_agent_io` или встраивает его в хост. Каждый случай записан одинаково: симптом, причина, что сделать. Тексты ошибок и имена событий взяты из кода пакета; рядом указан файл. Тексты, помеченные «реальный вывод», получены запуском собранного бинаря `codelab-agent` с изолированным `CODELAB_HOME`.

Случаи по теме:

- конфигурация: [неизвестная переменная](#неизвестная-переменная-codelab_), [`config.yml` не читается](#configyml-не-читается), [`codelab.toml`](#codelabtoml-найден), [якоря и теги](#якоря-алиасы-и-теги-в-yaml), [ссылка проектного слоя](#ссылка-проектного-слоя-наружу), [проект недоверенный](#ключи-проекта-игнорируются), [`CODELAB_HOME` и `CODELAB_CONFIG`](#codelab_home-и-codelab_config-отвергнуты), [`Sources:` без файла](#в-sources-нет-моего-файла);
- запись: [конфликт при правке](#конфликт-при-правке), [файл вне профиля YAML](#правка-отвергнута-файл-вне-профиля-yaml), [отказ записи в проект](#отказ-записи-в-слой-проекта), [не удалось выставить права](#cannot-set-permissions), [слэш с обратной чертой в YAML](#слэш-с-обратной-чертой-в-строке-yaml);
- перезагрузка: [правка не замечена](#правка-файла-не-замечена);
- секреты: [хранилище только для чтения](#хранилище-секретов-только-для-чтения), [права и ссылки `secrets.yaml`](#secretsyaml-отвергнут), [секрет не найден](#секрет-не-найден), [`.secrets-tmp`](#каталог-secrets-tmp-остался), [Windows](#file-на-windows);
- сессии: [`.corrupt` и карантин](#в-каталоге-журнала-появился-corrupt), [список сессий устарел](#список-сессий-устарел), [память модели игнорируется](#память-последней-модели-игнорируется);
- процессы: [`exec` не стартует](#exec-не-стартует), [MCP-сервер не запустился](#mcp-сервер-не-запустился-или-закрылся), [осиротевшие процессы](#после-закрытия-остались-процессы);
- файлы проекта: [не читается шаблон, агент или навык](#файл-проекта-или-навык-не-читается);
- тесты: [тест падает только на macOS или в CI](#тест-падает-только-на-macos-или-в-ci), [сторож упал на импорте `testing.dart`](#сторож-упал-на-импорте-testingdart), [наблюдатель нестабилен в тесте](#наблюдатель-нестабилен-в-тесте).

События журнала пакета собраны в [таблице ниже](#события-журнала-пакета).

## Неизвестная переменная `CODELAB_*`

**Симптом.** `config check` или журнал `serve` показывает (реальный вывод):

```text
warning: env: unknown environment variable CODELAB_FOO
```

**Причина.** Загрузчик нашёл переменную с префиксом `CODELAB_`, которой нет среди известных и нет в семействах `CODELAB_SECRET_*`, `CODELAB_PROVIDER_*`, `CODELAB_REDACTED_*`. Чаще всего это опечатка. Событие — `config.env.unknown` (`lib/src/config/environment_layer.dart`).

**Что сделать.** Исправить имя. Если переменная настоящая, добавить её в `_knownVariables` ([рецепт 1](11-extending.md#рецепт-переменная-окружения-для-ключа)); имена, которые хост назвал сам (`--token-env`), передаются в `knownVariables` загрузчика. `CODELAB_TEST_SECRET_STORE` известна только в сборке с `-DCODELAB_ALLOW_TEST_SECRETS=true`.

## `config.yml` не читается

**Симптом.** Настройки из `config.yml` не действуют; в `check` (реальный вывод):

```text
warning: ~/demo/home/config.yml: ignored: only config.yaml and config.local.yaml are read; rename it to ~/demo/home/config.yaml
```

**Причина.** Читаются только `.yaml`. Выбирать между двумя расширениями значило бы угадывать намерение, а молчать — терять настройки. Событие `config.file.ignored` (`config_loader.dart`, `_ignoredYml`).

**Что сделать.** Переименовать файл. Явный `--config` может иметь расширение `.yml`.

## `codelab.toml` найден

**Симптом.** Конфигурации нет, а в `check` (реальный вывод):

```text
warning: ~/demo/home/codelab.toml: codelab.toml is not used by the Dart agent. Move the settings to config.yaml manually; the key mapping is in docs/architecture/proposals/agent-core/15-configuration.md, section 15.7.
```

**Причина.** Остались файлы Python-агента (`$CODELAB_HOME/codelab.toml`, `auth.toml`, `<cwd>/codelab.toml`, `codelab.local.toml`). Dart-агент их не читает и не открывает: проверяется только существование (`legacy_notice.dart`). Событие `config.legacy_found`.

**Что сделать.** Перенести настройки в `config.yaml` вручную ([миграция с Python-агента](../../../../docs/user/migrating-from-python-agent.md)). Подсказка исчезает, как только появляется любой YAML-файл слоёв 2–4 или задан `--config`.

## Якоря, алиасы и теги в YAML

**Симптом.** Файл, который «вроде бы валиден», отвергается (реальный вывод):

```text
~/demo/home/config.yaml:1:4: a: anchors, aliases, merge keys and tags are not supported
~/demo/home/config.yaml:2:1: b: anchors, aliases, merge keys and tags are not supported
Config: invalid (issues: 2)
```

**Причина.** Загрузчик принимает строгий профиль YAML (CFG-1, CFG-21): без якорей, алиасов, ключей слияния `<<`, тегов, повторов ключей, нескольких документов и вложенности глубже 64. Правило в `yaml_reader.dart`; таблица текстов — [глава 3](03-config-loading.md#строгий-профиль-yaml-readyamltree).

**Что сделать.** Развернуть повторы вручную. Тот же профиль у frontmatter шаблонов и агентов; у навыков есть починка `description: a: b` (`repairYaml`).

## Ссылка проектного слоя наружу

**Симптом.** `.codelab/config.yaml` не читается; в `check` (реальный вывод):

```text
~/demo/proj/.codelab/config.yaml: the config file resolves outside ~/demo/proj/.codelab/; symbolic links of a project config must stay inside .codelab
Config: invalid (issues: 1)
```

`config set --project …` отказывает тем же текстом.

**Причина.** Реальный путь файла проектного слоя вне канонического `<cwd>/.codelab`. Репозиторий не должен ссылкой втянуть чужой файл. Правило одно на загрузчик, писатель и наблюдатель (`config_link_containment.dart`); слой `user` и `--config` не ограничены.

**Что сделать.** Держать ссылку внутри `.codelab` или убрать её. Висячая ссылка слой не ломает: он молча отсутствует. Цикл ссылок и `..` в несозданном хвосте дают ту же проблему.

## Ключи проекта игнорируются

**Симптом.** Настройки из `.codelab/config.yaml` не действуют; в `check` (реальный вывод):

```text
warning: ~/demo/proj/.codelab/config.yaml:1:1: providers: ignored: the project is not trusted; add it to trusted_projects in the global config
note: ~/demo/proj/.codelab/prompts: the project is not trusted; add it to trusted_projects
```

**Причина.** Корня проекта нет в `trusted_projects` глобального слоя. Доверие решает ядро (CFG-3, [глава 9 ядра](../../codelab_agent_core/doc/09-config-prompts-commands.md#доверие-к-проекту)); пакет лишь передаёт ему канонический путь и канонизирует записи `trusted_projects` (`~` раскрыт, ссылка разрешена). Запись, которой нет на диске, остаётся как есть и ничему не равна. После перезагрузки на лету новое значение `trusted_projects` доверие не расширяет до перезапуска (закреплено на стартовом снимке).

**Что сделать.** Добавить в `trusted_projects` глобального `config.yaml` канонический путь папки (без символических ссылок) и перезапустить агента.

## `CODELAB_HOME` и `CODELAB_CONFIG` отвергнуты

**Симптом.** Код выхода `64` (реальный вывод):

```text
config check: CODELAB_HOME: ~user is not supported, use an absolute path
config check: CODELAB_CONFIG must be an absolute path
config check: CODELAB_CONFIG needs a .yaml file; codelab.toml is not supported, see agent-core-architecture §15.7
```

**Причина.** `ConfigUsageException` из `codelabHomeOf` и `checkConfigEnvPath` ([глава 3](03-config-loading.md#корень-состояния-codelabhomeof)). Молча принять `~bob/x` значило бы читать конфигурацию из каталога `./~bob`.

**Что сделать.** Указать абсолютный путь. `~` и `~/…` раскрываются в `HOME`; без `HOME` и `USERPROFILE` — не раскрываются. Для `--config` относительный путь допустим (считается от корня запуска).

## В `Sources:` нет моего файла

**Симптом.** Файл существует, а строка `Sources:` его не называет.

**Причина.** `Sources:` перечисляет только слои, которые удалось **прочитать**. Файл не попал в список, если он не прошёл проверку: больше 1 МиБ (`the file is larger than 1 MiB`), не UTF-8, нарушает профиль YAML, или это слой проекта со ссылкой наружу. Соответствующая проблема печатается строкой выше. Файлы слоёв 2–4 без проблем в списке есть всегда, если существуют.

**Что сделать.** Прочитать проблемы выше `Sources:`; исправить файл. Помните: пока есть проблемы чтения, ядро не вызывается ([глава 3](03-config-loading.md#что-делает-загрузчик)), и ошибки схемы появятся только после исправления.

## Конфликт при правке

**Симптом.** `config set` и подобные печатают (реальный текст из `config_edit_runner.dart`) `config file changed during the edit; run the command again`. Из кода `ConfigWriter.apply` летит `ConfigConflictException`.

**Причина.** Одно из трёх: файл изменился после `read` (отпечаток не совпал); блокировка `<файл>.lock` занята свежим писателем; lock оказался не нашим перед `rename` (его сочли устаревшим). Подкоманда повторяет правку **один** раз со свежим снимком; второй конфликт подряд — отказ.

**Что сделать.** Повторить команду. Если конфликт постоянный, ищите процесс, который держит lock или правит файл (редактор, второй агент). Брошенный lock старше 10 секунд снимается сам с событием `config.write.stale_lock`; брошенные `<файл>.tmp-*` старше 10 секунд убирает следующая запись под своим lock. Клиент настроек, получив `ConfigConflictException`, должен перечитать файл и повторить правку.

## Правка отвергнута: файл вне профиля YAML

**Симптом.** Запись отклоняется: `cannot edit <ключ> automatically; edit the file manually`.

**Причина.** Файл содержит конструкцию вне строгого профиля (якорь, тег, повтор ключа). `yaml_edit` не гарантирует сохранность структуры такого файла, и писатель отказывается (`yaml_document_edit.dart`).

**Что сделать.** Привести файл к профилю вручную: удалить якорь или повтор; затем команда сработает.

## Отказ записи в слой проекта

**Симптом.** `config set --project` отказывает (текст `untrustedProjectWritePrefix`):

```text
ignored in an untrusted project; use --local or add the project to trusted_projects in the global config
```

**Причина.** Загрузка отбросила бы записанный ключ как недоверенный (`config.project.untrusted_key`); запись отклоняется заранее, а не молча теряется. Для слоя `user` проверки нет.

**Что сделать.** Добавить проект в `trusted_projects` глобального конфига. Подсказка писателя называет ещё `--local` — для ключей, которые слой `local` читает; границы описывает таблица доверия в [главе 9 ядра](../../codelab_agent_core/doc/09-config-prompts-commands.md#доверие-к-проекту).

## `cannot set permissions`

**Симптом.** Запись конфигурации отказывает: `cannot set permissions on <файл>`.

**Причина.** Писатель переносит права существующего файла на tmp и выставляет `0700` созданному `$CODELAB_HOME` утилитой `chmod` через `SecretProcessRunner`. Любой сбой — отказ (fail closed): `rename` не выполняется. Бывает, если нет ни `/bin/chmod`, ни `/usr/bin/chmod`, или процесс не уложился в 5 секунд.

**Что сделать.** Проверить наличие `chmod` и права на каталог. В тесте — смотреть записи `FakeSecretProcessRunner.calls`.

## Слэш с обратной чертой в строке YAML

**Симптом.** После `mcp add` в файле строка `"@modelcontextprotocol\/server-filesystem"` со слэшем с обратной чертой.

**Причина.** Так `yaml_edit` записывает строку в двойных кавычках. Это допустимый YAML, значение читается верно. Не баг записи секрета.

**Что сделать.** Ничего. Если мешает, перепишите строку в одинарные кавычки вручную; следующая запись не тронет соседние узлы.

## Правка файла не замечена

**Симптом.** Правка `config.yaml` не вызывает перезагрузку агента.

**Причина** (по порядку проверки):

1. `config.watch: false` — наблюдателя нет; работает только `/config reload`.
2. Файл не в списке `watchedConfigFiles`: `secrets.yaml` наблюдается только при `secrets.backend: file`.
3. Содержимое не изменилось: сигнал даёт только разница sha256.
4. Проектный слой со ссылкой наружу не наблюдается вовсе: наблюдатель опрашивает только вердикт.
5. Файл больше 1 МиБ: отпечаток по размеру и mtime; загрузчик такой файл всё равно отвергнет.
6. Поток событий каталога упал или каталога нет — файлы ушли на опрос (раз в `config.poll_interval`, по умолчанию 2 с). Ищите `config.watch.fallback` (info): поле `reason` называет тип ошибки.

**Что сделать.** Включить `debug`-журнал и искать `config.watch.debounce` (замечена правка), `config.watch.fallback`, `config.watch.failed` (warning: файл нечитаем или замер упал). Затем смотрите [главу 4](04-config-writing-and-reload.md#наблюдение-за-файлами).

## Хранилище секретов только для чтения

**Симптом.** `secret set` и `provider add --api-key-stdin` отказывают (реальный вывод):

```text
secret store env is read-only. Add 'secrets.backend: file' to ~/demo/home/config.yaml to store secrets in ~/demo/home/secrets.yaml (plaintext, 0600), or set CODELAB_SECRET_CODELAB_GW in the environment
```

**Причина.** `auto` — это `env`, а `env` только читает (CFG-11). Открытый файл выбирается исключительно явно.

**Что сделать.** Включить `file` (`codelab config set secrets.backend file`) или задать переменную окружения. На Windows `file` недоступен.

## `secrets.yaml` отвергнут

**Симптом.** Команды секретов отказывают (реальный вывод):

```text
cannot list secrets: ~/demo/home/secrets.yaml has permissions 0644; run: chmod 600 ~/demo/home/secrets.yaml
```

Другие тексты из `file_secret_store.dart`: `<путь> is a symbolic link; refusing to read secrets`; `<home> is a symbolic link; refusing to keep secrets there`; `<home> is writable by group or others (mode 0775); run: chmod go-w <home>`; `<home> is not owned by the current user; refusing to write secrets`; `<путь> is larger than 1 MiB`; `<путь> is not a map of secret names to strings`.

**Причина.** `FileSecretStore` работает по правилам ssh и проверяет права перед каждым обращением ([глава 5](05-secrets.md#проверки-перед-каждым-обращением)). Предупреждение `secrets.file.refused` (поле `reason`) пишется один раз на процесс и путь, а сам отказ — каждый раз.

**Что сделать.** Выполнить подсказку (`chmod 600 …`, `chmod go-w <home>`). Файл с содержимым не в формате «имя → строка» исправить вручную; строки файла в ошибку не попадают (в них секреты).

## Секрет не найден

**Симптом.** В `check` (реальный вывод):

```text
warning: ~/demo/home/config.yaml:5:5: providers.gw.api_key_secret: secret codelab/gw is not set; set CODELAB_SECRET_CODELAB_GW or add 'secrets.backend: file' and run: codelab secret set codelab/gw
```

**Причина.** Ссылка `api_key_secret` есть, значения в хранилище и в переменной `CODELAB_SECRET_<ИМЯ>` нет. Код выхода `check` при этом не меняется: секрет нужен только при выборе этой модели. Если хранилище **недоступно** (права, ссылка), `check` печатает `warning: secrets: file is unavailable (<причина>)` — это другое состояние, требующее другого действия.

**Что сделать.** `codelab secret set <имя>` либо переменная. Резолвер кэширует только найденные значения: новый секрет агент найдёт при следующем обращении, а сменённое значение подхватит после перезагрузки конфигурации (она сбрасывает кэш). Перезапуск не нужен.

## Каталог `.secrets-tmp` остался

**Симптом.** Рядом с `secrets.yaml` лежит каталог `.secrets-tmp` (права `drwx------`).

**Причина.** Это приватный каталог временных файлов записи секретов, он остаётся после успешной записи ([глава 5](05-secrets.md#атомарная-запись)). Брошенные tmp внутри старше 10 минут удаляет следующая запись.

**Что сделать.** Ничего. Каталог не добавляйте в git и не делайте общим.

## `file` на Windows

**Симптом.** `file backend is not supported on Windows; use env with CODELAB_SECRET_* variables`; это проблема значения `secrets.backend` в `config check`.

**Причина.** `dart:io` не проверяет ACL NTFS, поэтому открытый файл на Windows недопустим. Проверка одна (`secretsBackendProblem`) на загрузчик, `openSecretStore` и `FileSecretStore`. На Windows подсказка про `file` не показывается.

**Что сделать.** Использовать `env` и переменные `CODELAB_SECRET_*`.

## В каталоге журнала появился `.corrupt`

**Симптом.** Рядом с журналом сессии лежит `<журнал>.jsonl.corrupt`; в логе `session.quarantined` (warning).

**Причина.** При `open` разбор нашёл строки, которые нельзя прочитать: оборванный хвост после падения процесса или мусор в середине. Эти строки сохранены в `.corrupt` (по строке JSON: `line`, `text`, `reason`, `at`), а файл починен: усечён до последнего `\n` (если повреждён только хвост) или переписан из целых строк. `truncated: true` в событии — чинился хвост ([глава 6](06-sessions-and-state.md#карантин-и-переписывание)).

**Что сделать.** Обычно ничего: сессия загружена, ход продолжается. Если повреждение массовое, смотрите `.corrupt` (там причина) и источник сбоя: два процесса-писателя на один журнал не поддерживаются.

## Список сессий устарел

**Симптом.** `session/list` показывает старый заголовок или не видит свежую сессию.

**Причина.** `index.json` — кэш по `(size, mtime)`; он производный. Нечитаемый кэш игнорируется (отладочное событие `session.index.ignored`).

**Что сделать.** Удалить `sessions/index.json`: список пересоберётся при следующем `list`. Журналы кэш не трогает.

## Память последней модели игнорируется

**Симптом.** Новая сессия берёт не ту модель; в логе `model.last_used.ignored` (warning, поле `reason`) и строка `config check` `warning: <путь>: last model state ignored: <причина>`.

**Причина.** `state/last-model.json` отвергнут без чтения содержимого: `not a file`, `too large` (больше 4 КиБ), `invalid json`, `unknown version`, `invalid model`, `unreadable` ([глава 6](06-sessions-and-state.md#память-последней-модели-filelastmodelstore)). Файл при этом не переписывается.

**Что сделать.** Удалить файл (он производный, секретов в нём нет) или исправить формат: `{"v":1,"model":"<провайдер>/<модель>"}`.

## `exec` не стартует

**Симптом.** Инструмент `exec` возвращает `spawnFailed` или `shellUnavailable`.

**Причина.** `spawnFailed` с `working directory does not exist` — `options.cwd` нет на диске; с другим `message` — `ProcessException` ОС. `shellUnavailable` — на POSIX нет файла оболочки (`/bin/sh` или параметр `shell`). Код: `local_execution_env.dart`.

**Что сделать.** Проверить `cwd` сессии и наличие оболочки. Команда не видит переменных вне allowlist: `PATH` и `HOME` берутся из окружения хоста.

## MCP-сервер не запустился или закрылся

**Симптом.** Инструменты сервера не появились; в логе `mcp.server.closed` с `exit_code` или ошибка `spawn failed: …`.

**Причина** (из `stdio_process_transport.dart`):

| Текст или событие | Значение |
|---|---|
| `spawn failed: <текст ОС>` | команда не найдена или нет прав; относительная команда ищется в `PATH` из allowlist |
| `spawn failed: invalid arguments` | NUL в команде, аргументе или `env` |
| `message too large` (причина закрытия) | строка stdout длиннее 16 МиБ |
| `message contains a newline` | клиент пытался отправить строку с переводом строки |
| `process exited` в `done` | сервер завершился сам; `exit_code` в `mcp.server.closed` |

**Что сделать.** Проверить команду и окружение (`env` сервера поверх allowlist). stderr сервера — только на уровне `trace` (`mcp.server.stderr`): включите `--log-level trace`, но помните, что в нём могут быть секреты.

## После закрытия остались процессы

**Симптом.** После `close()` или отмены `exec` живут потомки сервера или команды.

**Причина.** Dart не запускает процесс в новой группе, и потомки ищутся по таблице процессов (`ps -A -o pid=,ppid=`). Потомок, который успел уйти к init до снимка, в таблице уже не связан с корнем.

**Что сделать.** `StdioProcessTransport.close` берёт снимок потомков **до** закрытия stdin. В `exec` дерево снимается при таймауте и отмене, но не при нормальном выходе корня: фоновый процесс, запущенный командой, переживёт её. На Windows — `taskkill /T /F` (проверяется вручную).

## Файл проекта или навык не читается

**Симптом.** Шаблон команды, агент или навык не появился.

**Причина.** Смотрите диагностику в `config check` (`warning:` и `note:`). Коды: `untrusted_project`, `outside_root`, `too_large` (шаблон или агент больше 64 КиБ, `SKILL.md` больше 128 КиБ), `not_utf8`, `limit_exceeded` (больше 100 файлов или 1000 подкаталогов), `unresolved_root`, `unreadable`. Реальный пример — [глава 7](07-project-files.md#граница-boundedenv).

**Что сделать.** Исправить файл по коду; для недоверенного проекта добавить его в `trusted_projects`. Файлы читаются **один раз** при создании или загрузке сессии: изменения подхватит новая сессия.

## Тест падает только на macOS или в CI

**Симптом.** Тест сравнивает пути и расходится на `/var` и `/private/var`; тест stdio-процесса видит лишнюю строку в stdout.

**Причина.** На macOS `/var` — символическая ссылка на `/private/var`; пакет возвращает канонические пути. Под `flutter test` `Platform.resolvedExecutable` — это `flutter_tester`, который печатает адрес VM service в stdout.

**Что сделать.** Канонизировать временный каталог (`resolveSymbolicLinksSync()`, `tempRoot`); для дочерних процессов брать `dartExecutable()` из `test/support/dart_executable.dart`. Для проверки, жив ли процесс, берите pid и `ps -o stat= -p <pid>`, а не строку аргументов: на macOS и Linux она выглядит по-разному.

## Сторож упал на импорте `testing.dart`

**Симптом.** `melos run guard` красный: `package:codelab_agent_io/testing.dart` импортирован из `lib/` моста `codelab_embedded` (вне `src/testing/`) или `codelab_setup`.

**Причина.** Сторож запрещает импорт в `lib/` мостов `codelab_embedded` (кроме `src/testing/`) и `codelab_setup`; бинарь `apps/codelab_agent` и тесты правилом не охвачены (`packages/dart/codelab_architecture_tests/test/support/rules.dart`). Иначе сценарий модели попадал бы в рабочую сборку клиентов.

**Что сделать.** Перенести код под `test/` или в разрешённое место; сценарий для клиентов получают через `codelab_embedded/testing.dart`.

## Наблюдатель нестабилен в тесте

**Симптом.** Тест на настоящем `Directory.watch` иногда зависает или падает по таймауту.

**Причина.** Задержка подписки FSEvents и inotify: запись сразу после старта проходит мимо; одинаковое содержимое не даёт сигнала (сравнение по sha256).

**Что сделать.** Использовать `rewriteUntil` ([глава 10](10-scripted-model.md#rewriteuntil)) с разным содержимым и ждать событие `config.watch.debounce`; для логики debounce и фильтра — детерминированный `ConfigWatcher` с `FakeClock`.

## События журнала пакета

| Событие | Уровень | Где | Поля |
|---|---|---|---|
| `config.write` | info | `config_writer.dart` | `path`, `keys` |
| `config.write.stale_lock` | warning | `config_write_lock.dart` | `path`, `age_ms` |
| `config.watch.debounce` | debug | `config_watcher.dart` | `path` |
| `config.watch.fallback` | info | `config_watcher.dart` | `path`, `reason` |
| `config.watch.failed` | warning | `config_watcher.dart` | `path`, `error_class` |
| `config.file.ignored` | предупреждение загрузки | `config_loader.dart` | `path`, `hint` |
| `config.legacy_found` | предупреждение загрузки | `legacy_notice.dart` | `files` |
| `config.env.unknown` | предупреждение загрузки | `environment_layer.dart` | `name` |
| `config.preconfig.shadowed` | предупреждение загрузки | `provider_preconfig.dart` | `by` |
| `secrets.backend.selected` | info | `open_secret_store.dart` | `backend`, `path`, `reason` |
| `secrets.backend.plaintext` | warning | `open_secret_store.dart` | `path` |
| `secrets.file.refused` | warning (раз на процесс и путь) | `file_secret_store.dart` | `path`, `reason`, `mode` или `removed` |
| `secrets.client.fallback` | warning | `client_secret_access.dart` | `backend`, `reason` |
| `session.quarantined` | warning | `jsonl_session_store.dart` | `session_id`, `lines`, `truncated` |
| `session.leaf.healed` | warning | `jsonl_session_store.dart` | `session_id`, `from`, `to` |
| `session.index.ignored` | debug | `jsonl_session_store.dart` | `path` |
| `model.last_used.ignored` | warning | `last_model_file.dart` | `path`, `reason` |
| `mcp.server.closed` | info | `stdio_process_transport.dart` | `server`, `transport`, `exit_code` |
| `mcp.server.stderr` | trace | `stdio_process_transport.dart` | `server`, `line` |

Предупреждения загрузки пишет `logConfigWarnings(logger, loaded)`: уровень берётся из `ConfigIssue.level`, имя события — из поля `event`, остальные поля — из `fields`, плюс `message`. Значений секретов нет ни в одном событии; если вы добавляете событие, держите это правило ([рецепт 7](11-extending.md#рецепт-новое-событие-журнала)).

## Смотрите также

- [Глава 13 ядра: частые проблемы ядра](../../codelab_agent_core/doc/13-troubleshooting.md)
- [Обзор](01-overview.md), [начало работы](00-getting-started.md)
- [Каталог `CODELAB_HOME` для администратора](../../../../docs/ops/codelab-home.md), [переменные окружения](../../../../docs/ops/environment.md)
