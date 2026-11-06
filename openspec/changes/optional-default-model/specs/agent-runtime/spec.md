## ADDED Requirements

### Requirement: Модель новой сессии
`AgentRuntime.createSession(SessionSpec)` без `spec.model` SHALL выбирать модель так (design.md change `optional-default-model`, D5):
1. `CoreConfig.defaultModelSource == config` снимка сессии — `CoreConfig.defaultModel`, источник `config`;
2. иначе — модель из `AgentCoreServices.lastModel.read()`, если порт задан и каталог сессии (`AgentRuntime.models`) её разрешает, источник `last-used`;
3. иначе — `CoreConfig.defaultModel` (первый провайдер), источник `first-provider`.

С `spec.model` SHALL использоваться она, как раньше. Выбор SHALL писаться событием `session.model.selected {session_id, model, source}` уровня `info` (source — `config`, `last-used`, `first-provider`); значений секретов и адресов провайдеров в нём нет. Ошибка порта `read()` SHALL давать шаг 3 и событие `model.last_used.ignored {reason}`, а не ошибку `createSession`. `loadSession` без модели журнала и база модели агента сессии SHALL, как раньше, брать `CoreConfig.defaultModel` без шага 2. ACP-проекция не меняется: `configOptions` опции `model` SHALL иметь `currentValue` выбранной модели, новых полей и методов ACP нет. Смена модели в сессии (`AgentSession.setModel`, `session/set_config_option` опции `model`, запись `model_change`, восстановление при `session/load`) SHALL работать как раньше.

#### Scenario: Явная модель конфига побеждает последнюю
- **WHEN** конфиг задаёт `agent.default_model: a/x`, порт последней модели возвращает `b/y` из каталога, и вызывается `createSession` без модели
- **THEN** модель сессии — `a/x`, событие `session.model.selected` с `source: config`

#### Scenario: Последняя модель побеждает первого провайдера
- **WHEN** ключа модели нет, неявная модель `a/x`, порт возвращает `b/y` из каталога
- **THEN** модель сессии — `b/y`, `source: last-used`; первая запись журнала — `model_change` `b/y`; `configOptions` опции `model` — `currentValue: b/y`

#### Scenario: Последней модели нет в каталоге
- **WHEN** ключа модели нет, неявная модель `a/x`, порт возвращает `gone/z`, которой нет в каталоге
- **THEN** модель сессии — `a/x`, `source: first-provider`, файл состояния не меняется

#### Scenario: Сбой чтения последней модели
- **WHEN** порт `read()` бросает исключение
- **THEN** `createSession` возвращает сессию с неявной моделью, событие `model.last_used.ignored` с причиной без содержимого файла

#### Scenario: Пустой CODELAB_HOME и provider add
- **WHEN** `$CODELAB_HOME` пуст, выполняется `codelab-agent provider add gw --kind openai-compatible --base-url https://x/v1 --model m --context-window 8192 --api-key-env GW_KEY` без `--default`, затем бинарь запускается `serve --stdio` и клиент вызывает `session/new`
- **THEN** `provider add` — код `0` без `warning: agent.default_model: required`; бинарь стартует, модель сессии — `gw/m`, событие `session.model.selected` с `source: first-provider`

### Requirement: Последняя выбранная модель
Ядро SHALL иметь порт `LastModelStore` с операциями `read() → Future<ModelId?>` и `write(ModelId)`, передаваемый хостом в `AgentCoreServices.lastModel` (design.md change `optional-default-model`, D6–D8). `null` — памяти нет: шаг 2 требования «Модель новой сессии» пропускается, запись не выполняется.

**Когда пишется.** Ядро SHALL вызывать `write` после успешной явной смены модели: `AgentSession.setModel` (в том числе `session/set_config_option` опции `model`) после записи `model_change` в журнал, и `createSession`/`loadSession` с явно переданной моделью. Автоматический выбор, восстановление модели из журнала, смена агента и перезагрузка конфига `write` НЕ SHALL вызывать. Сбой `write` НЕ SHALL менять результат `setModel` и создание сессии: событие `model.last_used.write_failed {reason}` уровня `warning`.

**Файл.** Реализация `codelab_agent_io` SHALL хранить одну модель на `$CODELAB_HOME` в `$CODELAB_HOME/state/last-model.json` содержимым `{"v": 1, "model": "<provider>/<model>"}`:
- запись — во временный файл с уникальным именем в том же каталоге и атомарный `rename`; каталог `state` создаётся при первой записи; записи одного процесса идут по очереди, между процессами выигрывает последняя;
- отсутствующий файл SHALL давать `null` без события;
- файл больше 4 KiB, не JSON, неизвестная версия `v` или значение `model` не вида `<provider>/<model>` SHALL давать `null` и событие `model.last_used.ignored {path, reason}` уровня `warning`; файл при чтении не переписывается и не удаляется;
- в файле, событиях и логе НЕ SHALL быть ключей, секретов, адресов и заголовков провайдеров: только идентификатор модели;
- путь файла SHALL входить в пути PERM-11 (`agentConfigPathsFor`): правка его инструментами агента — критическая, как правка конфига.

Бинарь `serve` без `--llm-script` и настольный открыватель `codelab_embedded/io.dart` SHALL передавать файловую реализацию над своим `$CODELAB_HOME`; `--llm-script`, сценарный открыватель `codelab_embedded/testing.dart`, web-безопасный барель и тесты по умолчанию — `null`.

#### Scenario: Смена модели запоминается
- **WHEN** сессия на `a/x` получает `session/set_config_option` опции `model` со значением `b/y`, затем создаётся новая сессия без модели при конфиге без `agent.default_model`
- **THEN** `$CODELAB_HOME/state/last-model.json` содержит `{"v": 1, "model": "b/y"}`, модель новой сессии — `b/y`

#### Scenario: Автоматический выбор не пишет файл
- **WHEN** `createSession` без модели выбирает неявную модель `a/x`
- **THEN** файл состояния не создаётся и не меняется

#### Scenario: Повреждённый файл состояния
- **WHEN** `last-model.json` содержит `{"v": 1, "model": 42}`, во втором варианте — обрезанный JSON, в третьем — `{"v": 9, "model": "a/x"}`
- **THEN** `read()` возвращает `null`, событие `model.last_used.ignored` с путём и причиной, файл не изменён; сессия создаётся с моделью следующего шага

#### Scenario: Секретов нет в файле и логе
- **WHEN** провайдер `gw` задаёт `api_key_secret: codelab/gw` со значением `sk-test-leak-0123456789` в хранилище, сессия меняет модель на `gw/m` при `--log-level debug`
- **THEN** файл состояния содержит только `v` и `model`; ни файл, ни лог не содержат `sk-test-leak-0123456789`, `base_url` и заголовков

#### Scenario: Сбой записи не ломает смену модели
- **WHEN** `write` бросает исключение (каталог только для чтения)
- **THEN** `setModel` возвращает результат с новой моделью, журнал содержит `model_change`, событие `model.last_used.write_failed`

#### Scenario: Файл под защитой PERM-11
- **WHEN** модель вызывает инструмент записи в `$CODELAB_HOME/state/last-model.json`
- **THEN** действие классифицируется как критическое по PERM-11, как запись в `$CODELAB_HOME/config.yaml`
