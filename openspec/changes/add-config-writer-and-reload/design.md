## Context

**Что есть в коде (после 8.5–8.9 и этапа 7):**
- **Загрузка конфига.** `ConfigLoader` (`codelab_agent_io/lib/src/config/`) собирает слои §15.2 в `ConfigTree`. `CoreConfig.fromLayers` (ядро, чистая функция) проверяет их и строит два снимка: полный для корня запуска (`CoreConfig.projectRoot`) и `CoreConfig.withoutProject` для сессий в другом `cwd` (D9 change `add-agent-configuration`).
  - Хост читает конфиг один раз: `AgentHost.build` (`apps/codelab_agent`), открыватель `codelab_embedded` (D5 change `add-embedded-agent-mode`).
  - Раздел `config` в `schema.dart` стоит в `afterMvpSections`: ключи `config.*` дают `config.key.not_applied`.
- **Окружение.** `environment_layer.dart` знает `CODELAB_MODEL`, `CODELAB_MAX_STEPS`, `CODELAB_PERMISSION_MODE` и семейство `CODELAB_PROVIDER_*`: предупреждения `config.env.unknown` оно не даёт, но и не читается.
- **Провайдеры.** Хост строит функцию модели `createConfiguredStreamFunction(config, llmServices, secrets:)` и каталог `StaticModelCatalog(config.providers)` до `buildAgentCore`. Цепочка провайдера кэширует ключ, разрешённый резолвером.
- **Секреты.** `SecretResolver` кэширует найденные значения до конца процесса. `invalidate()` отложен до 8.10 (D3 change `add-agent-secret-store`).
- **MCP.** Порт ядра `McpConnector.connect` → `McpSessionTools {tools, servers, takeUpdate(), replaceServers(), close()}`, реализация — `McpClientConnector` (`codelab_agent_mcp`).
  - `replaceServers` получает полный желаемый список: совпавшие серверы остаются, исчезнувшие закрываются, новые подключаются, отключённые пробуются заново.
  - `AgentSession.setMcpServers` во время хода откладывает замену до `TurnEnded`; последний вызов побеждает (счётчик поколений).
  - Сбой сервера окончателен до конца сессии: переподключения нет. `McpServerSummary` — только `{name, toolCount}`.
- **Команды.** `AgentSession.commands` — только шаблоны промптов (`SlashCommandSource.template`). Имена `config`, `mcp`, `status` и другие уже зарезервированы (`reservedCommandNames`). Механизма «ответ агента без модели» нет: change встроенных команд отложен решением пользователя 2026-10-30 (OQ1 change `add-agent-project-files`).
- **Подкоманды.** `ConfigCommands.check` и `SecretCommands` (`codelab_agent_io/lib/src/cli/`); `codelab` вызывает их через `codelab_setup/io.dart`. `config set|get|unset|path`, `provider`, `mcp` не зарегистрированы: код `64`.
- **Защита правок конфига моделью.** PERM-11 (§7.6.1) делает критическими `write`/`edit` и `exec` с целью `.codelab/config*.yaml` внутри корня сессии. `$CODELAB_HOME/config.yaml` и файл `CODELAB_CONFIG` в список не входят.
- **Зависимости.** `yaml_edit` утверждён D2 change `add-agent-configuration` и уже стоит в `ioAllowlist` сторожа и в списке `codelab_agent_io/AGENTS.md` §2. В `pubspec.yaml` пакета его нет; в `pubspec.lock` он есть транзитивно (2.2.4).

**Ограничения:**
- ACP не придумывается (`AGENTS.md` §3.4): только `available_commands_update` (агент МОЖЕТ слать его «at any time», `14-Slash Commands.md`, «Dynamic updates»), `config_option_update` (полный снимок, `13-Session Config Options.md`) и обычный ход `session/prompt` с `agent_message_chunk` и `stopReason`;
- ядро без `dart:io`, без своих таймеров и случайности (PKG-1, PKG-6), PKG-2 не расширяется;
- клиенты не импортируют `codelab_agent_*` (PKG-4);
- конкурентность по `docs/architecture/concurrency.md`, `AGENTS.md` §9 и §12: у долгоживущих подписок есть владелец, устаревшие результаты отбрасываются;
- CFG-9…CFG-19 (§17.5.11).

## Goals / Non-Goals

**Goals:**
- **L-25.** Провайдер и модель по умолчанию из двух переменных окружения без файла конфига, одинаково у `serve`, встроенного агента и `config check`.
- **E-15.** Каждый лист схемы покрыт ровно одним `SettingDescriptor`; тест полноты падает на необъявленном ключе.
- **Запись конфига.** CLI правит `config.yaml` без потери комментариев и формата, атомарно и только валидным итогом; вывод `codelab` и `codelab-agent` совпадает.
- **E-04.** Правка конфига применяется к работающему агенту без перезапуска; невалидная правка не ломает работающего агента; упавший MCP-сервер возвращается сам.
- Человек в клиенте видит состояние MCP-серверов и результат перезагрузки: `/mcp`, `/config` (OQ1 (а)).

**Non-Goals:** раздел «Не входит» в `proposal.md`.

## Decisions

### D1. Раскладка по пакетам, направление зависимостей, сторож

```mermaid
flowchart TB
    CLI["apps/codelab_cli<br/>codelab config|provider|mcp"] --> SETUP["codelab_setup<br/>lib/io.dart: реэкспорт подкоманд"]
    APP["apps/codelab_agent<br/>serve: FileConfigSource, флаги L-25<br/>config|provider|mcp"] --> IO
    EMB["codelab_embedded<br/>FileConfigSource встроенного агента"] --> IO
    EMB --> ACP["codelab_agent_acp<br/>уведомления после перезагрузки,<br/>кадры /config и /mcp"]
    EMB --> MCP
    APP --> ACP
    APP --> MCP["codelab_agent_mcp<br/>супервизия серверов сессии"]
    SETUP --> IO["codelab_agent_io<br/>config/: ConfigWriter, ConfigWatcher, FileConfigSource, слой L-25<br/>cli/: ConfigCommands, ProviderCommands, McpServerCommands"]
    IO --> CORE["codelab_agent_core<br/>config/: SettingsRegistry, ConfigEdit, ConfigSource<br/>runtime/: reloadConfig; commands/: config, mcp"]
    ACP --> CORE
    MCP --> CORE
```

| Пакет | Что добавляется |
|---|---|
| `codelab_agent_core` | `config/settings_registry.dart` (D4), `config/config_edit.dart` (D5), `config/config_source.dart` (D7); строки схемы `config.watch`, `config.poll_interval`. Также: `runtime/` — `reloadConfig`, `checkConfig`, `configStatus`, снимок под замену, типы отчёта `runtime/config_reload.dart` в барель (D8); `config/config_reload_plan.dart` — чистая функция `planConfigReload` (diff, отложенные ключи, `values` применённого снимка; вне бареля, D8); `config/secret_name_rule.dart` — `isSecretLikeName`, `hasSecretReference` в публичном барели: единственная копия правила имён D5 для R0-4 перезагрузки и `literal_secret_rule.dart`, предконфигурации и маскирования вывода `codelab_agent_io`; `secrets/secret_resolver.dart` — `invalidate` (D8); `mcp/mcp_connector.dart` — состояние сервера в `McpServerSummary` (`McpServerState`), `reconnect`, `setEnabled`, `McpConnectRequest.expandSecrets` (`McpSecretExpander`, `McpSecretsException`) (D11); `commands/builtin_commands.dart` (D12); `host/` — `AgentCoreServices.config`, `AgentCoreServices.agentConfigPaths`, `buildAgentCore(modelsFor:, configCommand:)` (D8, D12); `config/` — `ConfigLoadResult.values`, `McpServerConfig.enabled`, параметр `CoreConfig.fromLayers(pinnedTrustedProjects:)`, `CoreConfig.withDeferred`, `CoreConfig.validateSnapshot` (D8, D10); `permissions/` — пути PERM-11 от хоста (D8); ветка `AgentEvent` `ModelOptionsChanged` (D8); публичный барель экспортирует `nearestKey` из `config/key_path.dart` — подсказка «did you mean» для неизвестного поля предконфигурации (D3); итерация 3 (D5) расширяет публичный API: `configFingerprint` в `config/config_edit.dart` — отпечаток sha256 байтов файла для конфликта; `splitKeyPath`/`KeyPathSegment` из `config/key_path.dart` — единый разбор пути для писателя, `SettingsRegistry.lookup` и маскирования вывода итерации 4; `inlineSecretKeys` перенесён из `config/schema.dart` (не экспортируется, CFG-5) в `config/config_issue.dart` — список нужен писателю и маскированию; у `ConfigIssue` — структурный признак незаданной `${VAR}` (D5, «Кандидат»; ревью итерации 3): писатель и загрузчик не разбирают текст сообщения |
| `codelab_agent_io` | `config/provider_preconfig.dart` — слой предконфигурации L-25, `config/literal_secret_rule.dart` — правило литеральных секретов заголовков (D3, D5) поверх функций имён ядра (`secret_name_rule.dart`), своей копии правила имён нет; `config/config_writer.dart`, `config/config_write_lock.dart`, `config/yaml_document_edit.dart` (D5, «Где»), `config/config_watcher.dart` и `config/file_config_source.dart` (D7); `ConfigLoader.validateCandidate` → `ConfigCandidateResult` (D5; `loadWithLayers(candidate:)`, на котором он стоит, — внутренний, не публичный API); `ConfigWriteSeam` — шов тестов, в барель не экспортируется; `secrets/secret_process_runner.dart` — `chmodExecutablePath()`, общий у `FileSecretStore` и писателя (вне публичного бареля); `ConfigLoader.load(pinnedTrustedProjects:)` — только передаёт список в `CoreConfig.fromLayers` (D8); `cli/` — новые методы `ConfigCommands`, `ProviderCommands`, `McpServerCommands`, маскирование вывода `config_output.dart` (D6); `config/agent_config_paths.dart` — `agentConfigPathsFor` (D8); `pubspec.yaml` — `yaml_edit` (D2) |
| `codelab_agent_mcp` | супервизия серверов в сессии `McpClientConnector`: автомат, задержки, состояние, `Clock` и `Random` от хоста; `McpTool` вызывает `McpToolCaller` сервера, а не клиента; `McpClient(logFailures:)` (D11) |
| `codelab_agent_acp` | `ModelOptionsChanged` → `config_option_update`; кадры встроенных команд; `available_commands_update` со встроенными командами (D8, D12) |
| `codelab_embedded` | `FileConfigSource` при `config.watch`, `modelsFor`, `agentConfigPaths`, закрытие источника в `dispose` (D8, D13) |
| `codelab_setup` | `lib/io.dart` — реэкспорт `ProviderCommands`, `McpServerCommands` и их опций (D6) |
| `apps/codelab_agent` | флаги `--provider-type`, `--provider-config` (D3); `FileConfigSource`, `agentConfigPaths`, `configCommand: false` для `--ws` в `AgentHost` (D8, D13); подкоманды `config path|get|set|unset`, `provider`, `mcp` (D6) |
| `apps/codelab_cli` | подкоманды `config|provider|mcp` в `cli_args.dart`, вызов в `run.dart` (D6) |

Направление не меняется: приложения → мосты (`codelab_setup`, `codelab_embedded`) → `_io`, `_acp`, `_mcp` → ядро. Новых пакетов и рёбер нет, граф в `README.md` не меняется.

**Сторож.**
- PKG-2 не расширяется: всё новое в ядре — чистый Dart на `dart:async`, `meta` и `crypto` (уже в `coreAllowlist`, `pubspec_allowlist_test.dart`). `configFingerprint` живёт в ядре именно поэтому: в `ioAllowlist` `crypto` нет, а отпечаток должен совпадать у всех писателей и хостов.
- `ioAllowlist` уже содержит `yaml_edit`; меняется только `pubspec.yaml` пакета.
- Правило ядра в `rules.dart` уже запрещает `package:yaml_edit/` (CFG-5).
- `mcpAllowlist`, `acpAllowlist`, `setupAllowlist`, `embeddedAllowlist`, `cliAllowlist`, `binaryAllowlist` не меняются.
- `package:codelab_setup/io.dart` по-прежнему импортируется только из `apps/codelab_cli/lib/src/run.dart`.

Нового правила в `test/support/rules.dart` не нужно.

**Web-безопасность.** Основной барель ядра экспортирует `SettingsRegistry`, `ConfigEdit`, `ConfigSource`, `configFingerprint`, `splitKeyPath` — чистый Dart (`package:crypto` web-безопасен), их покрывает `web_smoke` (`melos run web-compile`). Основной барель `codelab_setup.dart` не меняется: реэкспорт `ConfigEdit`/`SettingsRegistry` приходит с потребителем — change `add-provider-setup-ui` (§13 корневого `AGENTS.md`).

**Исполнители.** Таблица зон `CLAUDE.md` не называет `codelab_agent_mcp`. По `codelab_agent_mcp/AGENTS.md` пакет — сторона агента (ядро, порты, PKG-3), поэтому его задачи помечены `[agent]`. `codelab_agent_acp` — `[protocol]`; `codelab_embedded` — `[agent]` (R6-1 change `add-embedded-agent-mode`).

### D2. Технология: `yaml_edit` (`AGENTS.md` §4)

Решение о технологии принято в D2 change `add-agent-configuration`: `yaml_edit` 2.2.4, `tools.dart.dev`, BSD-3-Clause, все платформы; в 8.5 он не подключался, потому что потребителя не было. Здесь появляется потребитель — `ConfigWriter`. В `packages/dart/codelab_agent_io/pubspec.yaml` добавляется `yaml_edit: ^2.2.4` с комментарием-ссылкой на этот D2 и D2 change `add-agent-configuration`. Версия в `pubspec.lock` не меняется (2.2.4), меняется только вид зависимости: `dependency: transitive` → `direct main`.

Второго решения той же задачи нет: разбор остаётся на `package:yaml`, сериализатора YAML в проекте нет. Альтернатива — свой построчный редактор — отклонена в §17.5.12: flow-стиль, кавычки, CRLF и комментарии дают большую поверхность ошибок. `THIRD_PARTY_NOTICES.md` не меняется: зависимости pub.dev туда не вносятся.

### D3. Предконфигурация провайдера из окружения (L-25)

**Где.** Слой предконфигурации в `codelab_agent_io/lib/src/config/provider_preconfig.dart` — по алгоритму `envPreconfigLayer` §17.5.3; `ConfigLoader` подмешивает его в слой окружения (6) или флагов (7). Правило литеральных секретов заголовков — `config/literal_secret_rule.dart` (D5). Подсказка по Левенштейну для неизвестного поля берёт `nearestKey` ядра (экспорт из бареля, D1). Так предконфигурацию одинаково видят `serve`, встроенный агент (D5 change `add-embedded-agent-mode`), `codelab-agent config check` и `codelab config check`. Второго пути загрузки провайдеров нет (§17.5.12).

**Порядок внутри слоя 6** (переменные `CODELAB_*`, spec agent-configuration «Слои конфигурации и их порядок»): сначала предконфигурация, затем `CODELAB_MODEL` — более частное значение. Слой 6 сильнее слоя 5 (`--config`/`CODELAB_CONFIG`) и проектных слоёв, флаги (слой 7) — сильнее всего (CFG-12). Таблица `providers.<id>` сливается с файлами по §15.2: поля окружения побеждают. Доверие §15.3 к слою не применяется.

**Слияние с доверенными файлами** (R1-2, решение пользователя 2026-11-02). Предконфигурация из окружения и флагов сливается с `providers.<id>` доверенных файлов (`user`, `--config`/`CODELAB_CONFIG`, доверенный проект) так же, как любой слой: поле, которого нет в предконфигурации, берётся из файла. Если доверенный файл задаёт `base_url` (или `headers`, `auth_header`) провайдера с тем же `id`, а предконфигурация его не задаёт, ключ предконфигурации уйдёт на адрес из файла. Это полномочие доверенного файла, а не обход: доверенный файл и без предконфигурации может направить любой ключ на свой адрес. Недоверенный проектный слой ключи `providers.*` не задаёт (§15.3). Риск записан в Risks.

**Флаги `serve`.** `--provider-type <kind>` и `--provider-config <json | @путь>` (путь — относительно текущего каталога процесса). Если задан хотя бы один из них:
- переменные `CODELAB_PROVIDER_*` не читаются, пишется `config.preconfig.shadowed {by: "flags"}` (info);
- источник слоя — `flags`;
- задан только один из двух флагов — ошибка использования `64`;
- вместе с `--provider`/`--base-url` (флаги этапа 4, провайдер `cli`) — ошибка использования `64` `--provider-type cannot be combined with --provider`: два способа задать провайдера флагами в одном запуске неоднозначны.

У встроенного агента флагов нет, только переменные.

**Приоритет с `--model` и `CODELAB_MODEL`** (ревью итерации 0). Внутри слоя 6 сначала предконфигурация из переменных, затем `CODELAB_MODEL`. Внутри слоя 7 (флаги) сначала предконфигурация из `--provider-type`/`--provider-config`, затем `--model`. Поэтому `--model` побеждает `agent.default_model` предконфигурации флагов, а `CODELAB_MODEL` проигрывает ей: флаг сильнее переменной.

**Справка и секреты флага.** Справка `serve` рекомендует `--provider-config @путь`: JSON в argv виден в `ps`. JSON флага и переменных проходит то же правило литеральных секретов заголовков, что `ConfigWriter` (D5, «Секреты»): значение секретного заголовка без `${secret:…}`/`${VAR}` — проблема `inlineSecret`, значение не цитируется.

**Ошибки** — `ConfigIssue` с источником `env:CODELAB_PROVIDER_CONFIG` (`…_BASE64`, `flags`), без строки:
- обе переменные `CONFIG` и `CONFIG_BASE64` сразу — проблема;
- только `TYPE` или только `CONFIG` — проблема, названия обеих переменных в тексте;
- неверный тип провайдера — список допустимых `openai-compatible, anthropic`;
- не base64 — `CODELAB_PROVIDER_CONFIG_BASE64: not base64`;
- не JSON — `<имя>: invalid JSON at offset <n>`; текст исключения парсера не включается, он цитирует вход;
- корень не объект — проблема;
- неизвестное поле — с подсказкой по Левенштейну, как у неизвестного ключа;
- `api_key`, `apiKey`, `key`, `token`, `secret`, `password` — `inlineSecret` с `suggestedSecretName = codelab/<id>` (CFG-9);
- неверный тип поля — с ожидаемым типом, значение не цитируется.

Тексты английские (как остальные `ConfigIssue`). Примеры §17.5.10 переводятся при сверке документов (задача 0.1).

**Наблюдаемость.** `host.config.loaded.sources` содержит `env:CODELAB_PROVIDER_CONFIG`, значений нет. Значения `headers` проходят тот же путь шаблонов, что у файлов (`SecretTemplate`, D4 change `add-agent-secret-store`); регистрация в `Redactor` — 8.11.

**Альтернатива** — только флаги, как у этапа 4 (`--provider`, `--base-url`), — отклонена: встроенный агент флагов не имеет, а L-25 требует переменных для контейнеров (OQ6 — оставить ли флаги `--provider-type`/`--provider-config` вообще).

### D4. Реестр настроек `SettingsRegistry` (E-15)

Контракт — §17.5.2. Реестр — отдельная таблица данных в `config/settings_registry.dart`, а не метаданные узлов `schema.dart`:
- схема описывает проверку (тип, перечисление, правило, область `core`/`host`, «применяется»); умолчаний и диапазонов в её узлах нет — умолчания применяет разрешение `CoreConfig`, диапазоны проверяет валидатор кодом;
- реестр описывает показ и запись: раздел UI, метка, описание, умолчание и границы для редактора, `shared`/`fileOnly`, `restartRequired`, `layers`.

Согласованность двух описаний держит тест полноты §17.5.8 (п. 1–8). Почему не одно описание: схема — дерево узлов валидатора с `SectionNode`/`ObjectListNode`, а реестр — плоский список для UI в порядке показа. Слить их — значит тащить UI-поля в валидатор и перестроить проверенный в 8.5 код (§19). Альтернатива «метаданные в узлах схемы» записана в Risks как путь рефакторинга, если расхождения начнут чинить вручную.

**Ограничение теста полноты (п. 3).** Схема не хранит умолчаний и диапазонов, поэтому сверка идёт не «со схемой», а с поведением:
- `min`/`max` каждого дескриптора типа `int` проверяются зондом валидатора: граница принимается, значение за ней отклоняется;
- умолчание дескриптора ключа, который ядро применяет, сверяется с разрешённым `CoreConfig` пустой конфигурации;
- умолчания остальных ключей (без потребителя, ключи хоста, непрозрачные узлы) сверить не с чем — они перечислены явной константой теста с пометкой «только по §15.4».

Перенос умолчаний и диапазонов в узлы схемы — вне 8.10 (Risks, «Дублирование описаний ключей»).

**Объём в 1.0.** Дескрипторы — на ключи схемы этой сборки, а не на всю таблицу §17.5.8:
- **Типы — как у узлов схемы**, даже если целевая таблица §17.5.8 говорит иначе: `tools.untrusted_paths` — `stringList` (в схеме `ListNode(string)`); `tools.project_context.max_bytes` и `loop.empty_response_retries` — листья `int`, а не карты; `agents` (ключ верхнего уровня схемы) — `map`/`fileOnly`: определения агентов — markdown-файлы, а не YAML.
- **Разделы после MVP** (`afterMvpSections`: `llm`, `images`, `skills`, `subagents`, `jobs`, `hooks`, `plugins`, `a2a`, `memory`, `steering`, `lsp`, а также непрозрачные узлы `tools.web`, `tools.spill` и подобные внутри разделов ядра) — непрозрачные узлы схемы. Каждый получает один дескриптор `map`/`fileOnly` с причиной `not supported in this version; edit the file manually`, `restartRequired: false`. Их строки §17.5.8 вводят change этих разделов вместе со схемой.
- **Непрозрачные узлы внутри разделов хоста** наследуют правило D8 своего раздела: `logging.llm_snapshot` — `restartRequired: true`, слои раздела `logging`; узлы `sessions.lease`, `sessions.window` и другие покрыты дескриптором `sessions`.
- **Ключи без потребителя** (узел схемы `applied: false`): `fileOnly` с причиной `not applied in this version`. Редактор в UI для ключа, правка которого ничего не меняет, вводит пользователя в заблуждение. Среди них ключи, которые целевая таблица §17.5.8 объявляет `shared`: `agent.fallback`, `agent.summary_model`, `permissions.timeout`, `tools.disabled`. Остальные: `model_catalog`, `tools.output`, `tools.untrusted_paths`, `loop.empty_response_retries`, `loop.misuse`, `exec`, `prompts`, `redact`, `providers.*.list_models`, `providers.*.list_models_include`, `logging.trace`, `logging.trace_payload`. `restartRequired` у них — по D8 (`permissions.*` и `logging.*` — `true`). Change, который даёт ключу потребителя, в том же изменении переводит узел в `applied: true`, а дескриптор — в целевой `scope` таблицы §17.5.8 и решает его `restartRequired` (D8, «Обязанность будущих change»).
- **Правило теста «`shared` ⇒ узел применяется»** (п. 8 §17.5.8): дескриптор `shared` покрывает только узлы схемы с `applied: true`. Так ключ без потребителя не попадёт в UI по ошибке, а перевод узла в `applied: true` без пересмотра дескриптора тест не ловит — это обязанность change потребителя (выше).
- **`config.watch`, `config.poll_interval`** — листья (D7), `fileOnly`, `restartRequired: true`, слои `user` и `projectLocal`.
- **`secrets.backend`** — `fileOnly`, `restartRequired: true`, слой только `user`.
- **`profile`** — `map`/`fileOnly`, `restartRequired: true` (D8), слои — все, как у загрузчика: `profile` читается из всех слоёв, и реестр не сужает то, что разрешает §15.3.

**Публичный API реестра** — `SettingsRegistry.all`, `lookup`, `parseCliValue`, `SettingDescriptor`, `SettingScope`, `SettingType`, `ConfigValueException`. Функция покрытия, на которой стоят `lookup` и тест полноты, публичной не является: тест проверяет её через `src/`, а клиенты пользуются только `lookup`.

**Единственный источник `restartRequired`.** Его используют `ConfigWriteResult.restartRequiredKeys` (D5) и перезагрузка (D8). `permissions.*` и `trusted_projects` — `restartRequired: true` (R0-1). У `mcp.servers` и `providers.*` флаг `false`: отложить нужно только отдельные элементы (stdio — R0-1, адрес секрета — R0-4), а это правило значения, а не ключа, — его держит шаг 5 перезагрузки (D8), а `ConfigWriteResult.restartRequiredKeys` перечисляет такие элементы (`mcp.servers[<name>]`, `providers.<id>`) по тому же правилу. П. 6 теста сверяет признак со списком ключей «только после перезапуска» из таблицы D8; этот список — константа теста со ссылкой на D8.

`parseCliValue(d, raw)` — разбор значения `config set` по `type`:
- `bool` — только `true`/`false`;
- `int`, `float` — с `min`/`max`;
- `duration` — `30s`;
- `enumeration` — по `enumValues`;
- `stringList`, `pathList`, `modelRefList`, `map`, `mapList` — JSON.

Ошибка — исключение ядра `ConfigValueException {key, expected}` (`config/settings_registry.dart`, экспорт из бареля): текст называет ожидаемый формат и никогда не цитирует значение. Подкоманда переводит его в код `64`. Почему не `ConfigUsageException`: она живёт в `codelab_agent_io` (`config_loader.dart`) и означает ошибку использования загрузчика; ядро её не видит (PKG-1), а переносить её в ядро ради одного вызывающего — менять чужой публичный тип. Типизированный результат вместо исключения отклонён: `parseCliValue` вызывается из одного места, и `Object` или исключение проще, чем `sealed`-результат.

**Порядок итераций.** В итерации 2 раздел `config` ещё в `afterMvpSections`: у него один непрозрачный дескриптор `map`/`fileOnly`, а константа ключей перезапуска теста — без `config.*`. Листья `config.watch`, `config.poll_interval` и ключи перезапуска `config.*` и R0-1 (D8) добавляет задача 5.4 вместе со схемой.

### D5. Типы правок и `ConfigWriter`

Типы ядра — §17.5.2 без изменений: `ConfigLayer`, `ConfigTarget`, `ConfigSnapshot`, `ConfigEdit` и пять подклассов. `ConfigConflictException` — тоже в ядре: её ловят клиенты через реэкспорт моста, не видя `codelab_agent_io` (§12.4.2).

**Конструктор** — `ConfigWriter({codelabHome, environment, loader, logger, processRunner: SecretProcessRunner, clock: Clock, random: Random, cwd, platform, seam})`: `chmod` идёт через порт, возраст lock и брошенных tmp — по `Clock` (в тестах `FakeClock`), nonce lock — из `Random` хоста. Необязательные `cwd` (корень для слоёв `project`, если его нет в `ConfigTarget`), `platform` (ветка Windows в тестах) и `seam` (`@visibleForTesting`, точки `ConfigWriteSeam` между шагами записи — сценарии «Сбой между tmp и переименованием», «Lock снят во время записи»). `ConfigWriteSeam` в барель `codelab_agent_io` не экспортируется: тесты берут его из `src/`, клиентам шов не нужен (ревью итерации 3).

**Где** (ревью итерации 3) — три файла `codelab_agent_io/lib/src/config/`, по ответственности:
- `config_writer.dart` — `ConfigWriter`, `ConfigWriteResult`, `ConfigWriteSeam`: порядок шагов `apply`, раскрытие и containment пути цели, проверка кандидата, tmp, права и `rename`;
- `config_write_lock.dart` — lock (`<path>.lock`, снятие устаревшего, проверка своего nonce), чистка брошенных tmp и **константы-шаблоны служебных имён** (`<имя>.lock`, `<имя>.lock.stale-*`, `<имя>.tmp-*`); их же берёт `ConfigWatcher` (D7), чтобы писатель и наблюдатель не разошлись в именах;
- `yaml_document_edit.dart` — применение `ConfigEdit` к тексту через `YamlEditor`: разбор пути `splitKeyPath`, поиск `mcp.servers[<name>]`, кавычки строк, порядок вставки.

Отдельного интерфейса над каждым файлом нет (§13 корневого `AGENTS.md`): это деление одного писателя, а не новые реализации.

**Алгоритм `apply`** — §17.5.5, шаги 1–8, с уточнениями:
1. **Проверка доверия (шаг 2).** Только при записи в проектный слой (`project`, `projectLocal`): у слоя `user` проверки доверия нет (ревью итерации 3). Использует `trusted_projects` текущих слоёв `user` и `--config`/`CODELAB_CONFIG` — те же, что у загрузки. Проверку выполняет `trust.dart` ядра; писатель своего правила не держит.
2. **Lock (шаг 3).** Эксклюзивное создание `<path>.lock` с содержимым `<pid> <nonce>` (nonce — случайные 16 байт хоста). Lock старше порога устаревания (10 с) снимается без гонки: `rename` в уникальное имя `<path>.lock.stale-<nonce>`, повторная проверка возраста и содержимого переименованного файла, затем удаление и `config.write.stale_lock` (warning). Если переименованный lock оказался свежим (его успел пересоздать другой писатель) — он возвращается на место, а запись получает `ConfigConflictException`. Занятый lock — `ConfigConflictException`. Свой lock писатель удаляет, только если в нём его nonce.
   - **Чистка брошенных tmp — после взятия lock** (ревью итерации 3). Без lock писатель мог бы удалить tmp другого, ещё живого писателя.
   - **Таймаут `chmod` (5 с) строго меньше порога устаревания lock (10 с).** Внешний `chmod` — единственный шаг записи, который может зависнуть. Если бы он ждал дольше 10 с, lock живого писателя выглядел бы устаревшим, и второй писатель снял бы его посреди записи. Точное значение — константа `config_write_lock.dart` рядом с порогом; тест сверяет неравенство.
   - **Перепроверка перед `rename`.** Перед переименованием tmp писатель перечитывает свой lock (в нём должен быть его nonce) и отпечаток цели (должен совпасть с прочитанным на шаге 4). Lock снят или заменён чужим, либо файл изменён в обход lock (редактор) — `ConfigConflictException`; tmp удаляется, цель не тронута, чужой lock не удаляется. Окно между перепроверкой и `rename` остаётся (атомарного «сравнить и переименовать» в `dart:io` нет), но оно сужено до одного системного вызова. Сценарий «Lock снят во время записи».
3. **Кандидат (шаг 6).** Проверяет новый метод `ConfigLoader.validateCandidate(target, text, {cwd, environment})` → `ConfigCandidateResult {issues, warnings}`: тот же порядок слоёв и `fromLayers`, этот слой заменён текстом.
   - **Незаданная `${VAR}`** — предупреждение `ConfigWriteResult.warnings`. Без значения переменной ядро не строит провайдера, и следом идут проблемы-последствия (`agent.default_model` не в каталоге). Поэтому проверка повторяется с подставленным значением-заглушкой, а исходные проблемы подстановки остаются предупреждениями. Незаданную переменную писатель узнаёт по **структурному признаку проблемы ядра** (`ConfigIssue`), а не по тексту сообщения (ревью итерации 3): текст — для человека и может меняться.
   - `validateCandidate` — единственный публичный вход проверки кандидата; `ConfigLoader.loadWithLayers(candidate:)`, на котором он стоит, — внутренний метод пакета.
   - **Блокируют только новые ошибки** (R3-1, решение пользователя 2026-11-02). Писатель проверяет тем же методом и исходный текст слоя — полной проверкой без обрыва ступеней (R3-3, ниже) — и сравнивает проблемы до и после правки по сигнатуре `kind|key|source`, без значений, текстов и позиции (ревью итерации 3). Позиции (`line:column`) в сигнатуре нет: вставка выше сдвигает строки, и прежняя ошибка ниже вставки выглядела бы новой. Сравнение — по количеству проблем каждой сигнатуры, а не по множеству: проблемы с пустым ключом (синтаксис, корень документа) не схлопываются в одну, и если после правки проблем с той же сигнатурой стало больше, лишние — новые. Проблема, которой не было до правки, — `ConfigException(issues)` только с новыми проблемами, файл не тронут. Проблема, которая была и до правки, переходит в `ConfigWriteResult.warnings`. Поэтому `config set budget.max_steps 40` и `provider add` без `--default` в пустом `$CODELAB_HOME` проходят с предупреждением `agent.default_model: required`, а `provider remove` последнего провайдера, на которого ссылается `agent.default_model`, отклоняется: ссылка становится новой ошибкой.
   - **База сравнения — полная проверка исходного текста** (R3-3, решение пользователя 2026-11-03, дефект ручного smoke). Загрузка проверяет конфиг ступенями: ошибки схемы и неизвестные ключи — раньше семантических, а семантика (провайдеры, `base_url`, каталог моделей, `agent.default_model`) — по построенному конфигу; ошибка ранней ступени обрывает проверку и скрывает ошибки поздних. Если базу строить так же, правка, исправляющая раннюю ошибку, открывает поздние, и они ошибочно считаются новыми. Пример smoke: в файле литеральный `providers.lm.api_key: sk-fake-1` и `base_url: "https://u:p@ss@host/v1"`; `config check` показывает одну проблему, а `config unset providers.lm.api_key` отказывал с кодом `1`, называя `base_url` и `agent.default_model … not in the model catalog`. Поэтому базу писатель вычисляет **полной проверкой исходного текста без обрыва ступеней**: набор проблем всех ступеней, включая каскадные (последствия ранней ошибки на поздних ступенях). Правка блокируется, только если в кандидате есть проблема, которой нет в полном наборе базы (сравнение — по сигнатуре и числу, как выше). Кандидат проверяется той же полной проверкой: иначе новая ошибка поздней ступени при сохранившейся ранней осталась бы скрытой и правка записалась бы. Ранние ошибки кандидата, которые есть в базе, и поздние, открывшиеся после их исправления, — предупреждения. Полная проверка — режим того же `ConfigLoader.validateCandidate` (параметр `collectAll` ядра `CoreConfig.fromLayers`: ключи с ошибкой слоя вырезаются из копии дерева, и поздние ступени выполняются) для базы и кандидата писателя; вырезается путь проблемы, а если он не находится — ближайший найденный предок ниже слоя (элемент списка, раздел); элемент с `name` не строкой — по номеру; дубликаты имени снимаются за один круг. Повтор идёт до неподвижной точки, не больше 8 кругов. Правило доверия (и всё, что по D5 блокирует всегда) считается по исходным слоям до любого вырезания: вырезание влияет только на поздние семантические ступени. Путь проблемы ищется детерминированно: сначала точное совпадение всего остатка с ключом, затем префиксы от длинного к короткому, с учётом имён элементов списка. **Fail-closed:** если пришлось вырезать предка вместо точного пути или весь слой, круг не дал прогресса или лимит исчерпан, проверка добавляет служебную проблему `config.validation.incomplete` (`the config could not be fully checked; fix the file by hand`, без значений). В кандидате она всегда новая — запись отклоняется (CLI код `1`), даже если она есть и в базе; неполнота одной базы правку не блокирует, чтобы испорченный элемент можно было удалить (`mcp remove`, `config unset`). Сравнение базы и кандидата — по мультимножеству сигнатур (ревью безопасности R3-3); форма входа (параметр или внутренний метод пакета) — деталь реализации, второго публичного входа проверки нет. Обычная загрузка (`config check`, `serve`, перезагрузка D8) по поведению не меняется: она по-прежнему обрывается на первой провалившейся ступени. Значения в проблемы и предупреждения не попадают: литерал `sk-fake-1` не появляется ни в выводе, ни в логах (CFG-9).
     - Альтернатива — ступенчатая база с известным консервативным ограничением (прежняя редакция D5) — отклонена smoke: удалить литеральный секрет, ради которого и нужен `config unset`, было нельзя, пока не исправлены все поздние ошибки, о которых `config check` не сообщал.
     - Альтернатива — полная проверка и для обычной загрузки — отклонена: меняет вывод `config check` и диагностику `serve` вне scope change; каскадные ошибки поздних ступеней по сломанной ранней ступени — шум для человека.
     - Альтернатива — сравнивать только ключи (без ступеней) или повторять проверку после каждого «исправления» — отклонена: первое теряет новые ошибки поздних ступеней, второе сложнее и не даёт детерминированной базы.
     - Граница: правка, вносящая действительно новую ошибку поздней ступени при имеющейся ранней (например, `config set budget.max_steps 0` в файле с `bogus_key`), отклоняется — проблемы `budget.max_steps` нет в полной базе. Сценарии «Ошибка ранней ступени» и «Новая ошибка поздней ступени при ранней» (agent-configuration).
   - **Блокируют всегда**, без сравнения: литеральный секрет, который вносит правка (правило ниже и CFG-9, п. 1), ключ вне реестра и слой, которого не разрешает дескриптор (шаг 1), и ключ, который правило доверия отбросило бы в недоверенном проекте (шаг 2). Литерал, оставшийся в файле от ручной правки до 8.11, — прежняя проблема: он переходит в предупреждения, иначе `config unset` не смог бы его удалить.
   - Альтернатива — блокировать любую ошибку итога — отклонена: первая запись в пустой конфиг упиралась бы в `agent.default_model: required`, и `config set` был бы бесполезен до `provider add --default`. Альтернатива — пропускать любую ошибку — отклонена: правка, ломающая загрузку, не должна попадать в файл (CFG-13).
4. **Права файла (шаг 7).** tmp создаётся эксклюзивно (`<path>.tmp-<pid>-<rand>`, режим создания без перезаписи) и **пустым**. Права существующего файла читаются `FileStat.mode` и выставляются на пустой tmp через существующий порт `SecretProcessRunner` (абсолютный `/bin/chmod`, в argv только режим и путь; D5 change `add-agent-secret-store`) **до** записи содержимого. Сбой `chmod` (код выхода, таймаут) → `ConfigException` `cannot set permissions on <path>`, tmp удаляется, `rename` не выполняется — fail closed: конфиг с правами `0600` не должен на мгновение стать `0644`. Новый файл получает права по umask процесса. На Windows права не переносятся.
   - Порт не переименовывается (§19). Doc-комментарий называет второго потребителя.
   - Альтернатива — писать в существующий файл на месте — отклонена: сбой посреди записи оставил бы обрезанный конфиг (CFG-13).
5. **Символическая ссылка.** Путь цели раскрывается `resolveSymbolicLinks`, tmp создаётся в каталоге цели. Ссылка остаётся ссылкой.
   - **Слой `user`** — ссылки разрешены куда угодно (раскладки dotfiles: `~/.codelab/config.yaml` → `~/dotfiles/…`).
   - **Проектные слои** (ревью итерации 3). Раскрытая цель `project`/`projectLocal` — как и сам каталог `.codelab`, если он ссылка, — обязана лежать внутри канонического `<cwd>/.codelab` (канонический `cwd` плюс `.codelab`, без раскрытия ссылки `.codelab`). Иначе — `ConfigException` с путём **до** взятия lock и до создания каталогов. Почему: проектный каталог приходит из чужого репозитория, и `.codelab/config.local.yaml` → `~/.codelab/config.yaml` (или `.codelab` → `~`) заставил бы `config set --local` писать в глобальный конфиг или в произвольный файл пользователя. Это containment пути записи, как у `BoundedEnv` для инструментов.
   - **Цепочка ссылок.** Больше 32 переходов (в том числе цикл) — `ConfigException` `too many symbolic links: <path>`; файл и каталоги не создаются.
   - **Каталог `$CODELAB_HOME`**, которого нет и который создаёт писатель, получает права `0700` (через тот же порт `SecretProcessRunner`, кроме Windows): в нём лежат конфиг и `secrets.yaml`. Существующий каталог писатель не трогает.
6. **Без fsync каталога** — отступление от §17.5.5, шаг 7: `dart:io` не открывает каталог. Содержимое tmp сбрасывается `flush(flushAll)` до `rename`. Потерять при отключении питания можно только последнюю правку, повреждённого файла не будет — как у `secrets.yaml` (D14 change `add-agent-secret-store`).
7. **Брошенные tmp** (`<path>.tmp-*` старше 10 с) удаляются следующей записью — после взятия lock (п. 2).
8. **Порядок вставки** (R3-2, решение пользователя 2026-11-02) — как у `YamlEditor`:
   - новый ключ в отображении, ключи которого уже отсортированы по алфавиту, встаёт на своё место по алфавиту; иначе — в конец отображения;
   - то же для новых ключей элемента `mcp.servers[<name>]`;
   - новый элемент списка (`mcp.servers`) — в конец;
   - недостающие предки создаются в блочном стиле с отступом файла; формат и комментарии вне изменённых узлов сохраняются.
   - **Известная граница** (ревью итерации 3): `YamlEditor` привязывает комментарий над ключом к промежутку перед ним, а не к самому ключу. Поэтому при вставке по алфавиту перед ключом, над которым есть комментарий, комментарий оказывается над **новым** ключом (`# про c` / `c: 1` + `b` → `# про c` / `b: …` / `c: 1`). Байты комментария сохраняются, меняется только его соседство. Обходить `YamlEditor` своей вставкой ради этого не стоит (альтернатива ниже); граница фиксируется сценарием «Порядок нового ключа» и §17.5.5, п. 2.
   Альтернатива — всегда в конец — потребовала бы обходить `YamlEditor` своей вставкой в текст и не дала бы пользователю ничего, кроме другого порядка.
9. **Уточнения реализации итерации 3:**
   - `UnsetValue`, `RemoveMcpServer` и `RemoveTable` отсутствующего ключа — `ConfigException` с `not present in <path>`;
   - `SetValue` с ключом из `inlineSecretKeys` отклоняется как секрет (`ConfigInlineSecretException`) до проверки реестра: ключ `api_key` в реестре отсутствует, и ответ «неизвестный ключ» спрятал бы настоящую причину;
   - повторная запись того же значения файл не трогает: правка без изменений не создаёт tmp и не меняет отпечаток;
   - реестр листовой: `SetValue("providers.p", {…})` — неизвестный ключ; таблицы (провайдер, модель) создаются листовыми правками, которые достраивают недостающих предков (так работает `provider add`);
   - отпечаток считает `configFingerprint` ядра (D1); пути правок разбирает `splitKeyPath` ядра — тот же разбор, что у `SettingsRegistry.lookup`, поэтому ключ модели с точкой пишется и ищется одинаково;
   - путь `chmod` — `chmodExecutablePath()` из `secret_process_runner.dart`, общий с `FileSecretStore`.

**Секреты.** `SetValue` с ключом из `inlineSecretKeys` или со значением-секретом по правилу CFG-9, п. 1 → `ConfigInlineSecretException`, файл не тронут. Правило литеральных секретов заголовков и окружения проверяется **по итоговому поддереву документа после всех правок**, а не по типу правки: так `config set mcp.servers '[…]'`, `config set providers.x.headers '{…}'` и `UpsertMcpServer` проходят одну проверку. Его получают `codelab mcp add`, `config set`, будущая страница MCP-серверов и предконфигурация флагов (D3):
- **где:** каждое значение в `providers.*.headers`, `mcp.servers[*].headers`, `mcp.servers[*].env`, которое изменилось этой записью;
- **глубина** (ревью безопасности итерации 2): правило применяется на любой глубине итогового поддерева, а не только к прямым детям перечисленных узлов. Запись значения-отображения или списка целиком (`config set exec '{…}'`, `config set mcp.servers '[…]'`, `config set providers.x '{…}'`) проверяется так же, как запись отдельного листа:
  - значения `exec.env` — по правилу имён ниже, как `mcp.servers[*].env` (ключ `exec` пока без потребителя, но литерал в файле остаётся литералом);
  - элементы `exec.secrets` хранят не значения, а имена: `env` — имя переменной, `secret` — имя секрета. Поле `secret` проверяется форматом `SecretNames.problem`: значение, которое не является допустимым именем секрета, отклоняется как литерал. Правило `inlineSecretKeys` к полю `secret` элемента `exec.secrets` не применяется — иначе любой правильный элемент был бы отклонён;
  - прочие листья с именем из `inlineSecretKeys` (`api_key`, `apiKey`, `token`, `secret`, `password`) внутри map-значений на любой глубине — по правилу CFG-9, п. 1, как у `SetValue` с таким ключом;
  - тесты итерации 3: `config set exec '{"env":{"GITHUB_TOKEN":"…"}}'` и вложенный `token` в значении-отображении — `ConfigInlineSecretException`, файл не тронут, значение не процитировано;
- **непрозрачные узлы** (ревью итерации 3): в поддеревьях узлов, которые схема не раскрывает по листьям (`providers.*.auth`, `providers.*.key_rotation`, `tools.web`, `llm`, `hooks` и прочие разделы после MVP — непрозрачные дескрипторы D4), нормализованное правило имён ниже применяется **к любому листу**, а не только к значениям `headers`/`env`: структура таких поддеревьев не известна этой сборке, и `client_secret`, `bearer_token` в них — литералы того же рода;
- **`inlineSecretKeys` — после нормализации имени** (ревью итерации 3): `API_KEY`, `Api-Key`, `api-key` совпадают с `api_key`/`apiKey` так же, как имена правила ниже;
- **нестроковый скаляр** (число, `bool`) под секретным именем — литерал (ревью итерации 3): ссылки `${…}` в нём быть не может, а `token: 123456` — такой же токен в файле;
- **дубли `name` в `mcp.servers`** (ревью итерации 3): «изменённое этой записью» значение элемента определяется по номеру элемента в списке, а не по `name`. Иначе второй элемент с тем же `name` сравнивался бы с первым, и литерал в нём выглядел бы прежним;
- **имя:** нормализуется — нижний регистр, без `-` и `_`; секретное, если содержит `token`, `secret`, `password`, `apikey`, `auth`, `cookie`, `key` или `privatetoken` (`Authorization`, `Proxy-Authorization`, `X-Api-Key`, `GITHUB_TOKEN`, `Cookie`);
- **что отклоняется:** значение секретного имени, в котором нет ни `${secret:…}`, ни `${VAR}`;
- **ответ:** `ConfigInlineSecretException` с `suggestedSecretName = SecretNames.forMcp(server, key)` (у провайдера — `SecretNames.suggestFor(path)`), значение не цитируется;
- **граница:** ручная правка файла с таким литералом до 8.11 загружается — пункты 2–3 CFG-9 по шаблонам §12.4 остаются за 8.11. Fail closed на пути записи дешевле, чем объяснять, почему CLI записал токен в файл. Ложные срабатывания (`X-Keyboard-Layout`) обходятся ссылкой `${VAR}`.
- **граница смешанных значений** (R1-1, решение пользователя 2026-11-02): правило проверяет только наличие подстановки, поэтому смешанное значение `Bearer sk-литерал ${X}` проходит — литерал рядом со ссылкой не распознаётся. Известная граница до 8.11: разбор значения по шаблонам §12.4 и редакция секретов закрывают её там. Тест итерации 1 фиксирует текущее поведение, а не требование. Та же граница у `api_key_env` в непрозрачных поддеревьях: литерал вида `sk_live_ABC123` совпадает с форматом имени переменной окружения и проходит — отличить его можно только эвристикой §12.4 (8.11).

Это же нормализованное правило имён использует маскирование вывода `config get` и `provider list` (D6, R0-2) и перезагрузка — для «провайдера с ключом» по литеральному секретному заголовку (D8, R0-4). Поэтому функции имён (`isSecretLikeName`, `hasSecretReference`) живут в ядре (`config/secret_name_rule.dart`, публичный барель), а `codelab_agent_io` только импортирует их: две копии разошлись бы, и писатель принял бы токен, который перезагрузка не сочла бы секретом, или наоборот.

**Исключения** — контракт §17.5.2: `ConfigConflictException`, `ConfigInlineSecretException`, затем `ConfigException(issues)` (подкласс проверяется раньше). Отказ `YamlEditor` — `ConfigException` с `cannot edit <key> automatically; edit the file manually`. Исключения IO при записи tmp или `rename` — `ConfigException` с проблемой `cannot write <path>: <runtimeType>`; tmp удаляется, исходный файл цел.

**Альтернатива** — сериализация дерева вместо правки документа — отклонена §17.5.12: теряются комментарии и порядок.

### D6. Подкоманды записи и чтения (CLI)

**Реализация** — `codelab_agent_io/lib/src/cli/`, по образцу `ConfigCommands.check` и `SecretCommands`: типизированные методы, результат `{exitCode, stdout, stderr}`; аргументы разбирает каждое приложение своим `package:args`.
- `ConfigCommands` получает `path`, `get`, `set`, `unset`.
- Новые классы `ProviderCommands` (`add`, `list`, `remove`) и `McpServerCommands` (`add`, `list`, `remove`). Имя `McpServerCommands`, а не `McpCommands`, — чтобы не путать с агентской командой `/mcp` (D12).

Все три класса и их опции реэкспортирует `codelab_setup/lib/io.dart`.

| Подкоманда | Правка, вывод |
|---|---|
| `config path [--project\|--local] [--cwd D]` | путь слоя; без флага — все слои `user`, `project`, `local` и файл `CODELAB_CONFIG` с пометкой `exists`/`missing` |
| `config get <key> [--layer user\|project\|local\|merged] [--cwd D]` | значение и слой-источник; без `--layer` — `merged`; маскирование R0-2 |
| `config set <key> <value> [--project\|--local] [--cwd D]` | `SetValue`, значение — `SettingsRegistry.parseCliValue` |
| `config unset <key> [--project\|--local] [--cwd D]` | `UnsetValue`: принимает и ключ вне реестра, если он есть в файле (так удаляются опечатки и `api_key`) |
| `provider add <id> --kind K [--base-url U] --model M --context-window N [--api-key-secret S \| --api-key-env V \| --api-key-stdin] [--default] [--project\|--local]` | одна `apply` со списком `SetValue`; существующий `<id>` — upsert; флаг ключа заменяет источник ключа целиком (R4-4) |
| `provider list [--cwd D]` | маскирование R0-2; `Secrets: <backend>` первой строкой; по строке на провайдера итогового конфига: id, kind, base_url, модели, источник ключа (`secret codelab/x: found\|not set\|unavailable`, `env VAR: set\|not set`) |
| `provider remove <id> [--project\|--local]` | `RemoveTable("providers.<id>")`; ссылка из `agent.*` — `ConfigException` с подсказкой сменить модель |
| `mcp add <name> --type stdio --command C [--arg A]… [--env K=V]… \| --type http --url U [--header K=V]… [--disabled] [--project\|--local]` | `UpsertMcpServer`; имя без пробелов, `[`, `]`, `"` |
| `mcp list [--cwd D]` | серверы файлов по слоям: name, type, layer, enabled; без подключения |
| `mcp remove <name> [--project\|--local]` | `RemoveMcpServer`: элемент ищется только по `name`, никогда по номеру; имя — по правилу `mcp add` |

**Правила:**
- **`get` никогда не раскрывает подстановки.** Печатается сырое значение слоя-победителя (`"${GITHUB_TOKEN}"`, `"Bearer ${secret:…}"`), даже при `--layer merged`. Значение `${VAR}` — содержимое окружения, а оно может быть секретом. Значения ключей `secret: true` — это имена секретов, они печатаются.
- **Маскирование вывода `config get` и `provider list`** (R0-2, решение пользователя 2026-11-02). Подкоманды печатают значения, а файл мог быть правлен руками до 8.11:
  - значение любого листа (на любой глубине, не только в `headers` и `env`), чьё имя — ключ из `inlineSecretKeys` (`api_key`, `token` и др.) или секретное по нормализованному правилу D5, → `<redacted>`, если в нём нет ни `${secret:…}`, ни `${VAR}`; ссылки печатаются как есть. Правило имён действует на листья без дескриптора реестра и на элементы отображений с произвольными ключами (`headers`, `env`); скалярный лист, описанный реестром (`api_key_secret`, `api_key_env`, `auth_header`, `max_output_tokens`), хранит имя, счётчик или перечисление и печатается как есть. Известная консервативная граница: `exec.secrets[].secret` (имя секрета) печатается `<redacted>` — ложноположительно, но безопасно;
  - непрозрачное поддерево схемы (`providers.*.auth`, `providers.*.key_rotation`, разделы после MVP) → `<opaque: edit the file>`: схемы его листьев в этой сборке нет, и правило имён не может гарантировать, что секрет не лежит под безобидным именем;
  - значение из слоя окружения (`env:CODELAB_MODEL`, `env:CODELAB_PROVIDER_CONFIG` и другие `env:*`) → имя источника `<from env:CODELAB_PROVIDER_CONFIG>` вместо значения: содержимое переменной могло прийти из секретного хранилища оркестратора; флагов у подкоманд нет, но правило то же (`<from flags>`);
  - URL (`base_url`, `url`, R4-5, решение пользователя 2026-11-03) разбирается как URI и печатается без userinfo: `https://user:pass@host/v1` → `https://host/v1`. Неразбираемый URL, а также URL с `@`, но без авторитета (`user:pass@host`, где `Uri` видит схему `user`), → `<redacted>`: разрезать строку вручную по `@` нельзя — пароль сам может содержать `@` (`https://u:p@ss@host`), и остаток пароля попал бы в вывод. Значение query-параметра, чьё имя секретное по тому же нормализованному правилу имён D5 (`api_key`, `token`, `access_token`), → `<redacted>`; значение-ссылка `${…}` печатается как есть, то же правило — к парам `имя=значение` во фрагменте (`#access_token=…`) и в matrix-параметрах пути (`;token=…`), прочие параметры не меняются. Пример: `https://u:p@ss@host/v1?api_key=X&v=2` не выводит ни `p@ss`, ни `X`;
  - отображение и список маскируются поэлементно; `--layer merged` и слой файла — одинаково.
  Маскирует одна функция `codelab_agent_io` (`cli/config_output.dart`), её используют обе подкоманды.
- **Слой.** Слой записи по умолчанию — `user`: `set`, `unset`, `provider add|remove`, `mcp add|remove`; `--project` и `--local` — слои 3 и 4. `config get` без `--layer` читает `merged` (решение пользователя 2026-11-03).
- **`cwd`.** `--cwd` есть у `config path|get|set|unset|check`, `provider list`, `mcp list`; у `provider add|remove` и `mcp add|remove` его нет — берётся общий `-C`/`--cwd` у `codelab`, иначе каталог процесса. Путь канонизирует загрузчик, как у `config check` (D14 change `add-agent-configuration`).
- **Отсутствующая запись** (решение пользователя 2026-11-03). `config unset`, `provider remove`, `mcp remove` для ключа, которого нет в файле слоя, — код `0` без записи и строка stdout `<key> is not set in <path>`: цель команды уже достигнута. `config get` отсутствующего ключа — код `1`, stderr `config get: <key> is not set` (со слоем — `… in the <layer> layer`): скрипт должен отличать «не задано» от пустого значения.
- **Наличие ключа — по пути, а не по значению** (ревью итерации 4). `config get`, `config unset`, `provider remove` и `mcp remove` проверяют, есть ли путь в документе слоя; ключ со значением `null` (`max_steps:` без значения) присутствует. Поэтому `config unset budget.max_steps` удаляет строку `max_steps:` (код `0`, `Removed …`), а не отвечает `is not set`: иначе пустой ключ нельзя было бы убрать командой.
- **`provider add` — upsert** (решение пользователя 2026-11-03). Для существующего `providers.<id>` переданные флаги перезаписывают свои поля, остальные поля и модели сохраняются; обязательные флаги (`--kind`, `--model`, `--context-window`) остаются обязательными. Так повторный `provider add <id> … --api-key-stdin` меняет ключ, не трогая остальное.
- **Флаг ключа заменяет источник ключа** (R4-4, решение пользователя 2026-11-03). Любой из `--api-key-stdin`, `--api-key-secret`, `--api-key-env` задаёт источник ключа целиком: та же `apply` удаляет (`UnsetValue`) поля другого источника, если они есть в файле слоя. Пары `api_key_env` + `api_key_secret` у провайдера после команды не бывает: иначе неочевидно, какой ключ возьмёт агент, а старый источник, который пользователь хотел заменить, продолжал бы жить в файле. Пример: провайдер `gw` с `api_key_env: GW_KEY`, `provider add gw … --api-key-stdin` → `api_key_secret: codelab/gw`, `api_key_env` удалён, код `0`. Без флага ключа источник не меняется (upsert выше).
- **Недостающие обязательные флаги** `provider add` перечисляются все сразу одной строкой stderr (код `64`), а не по одному за запуск.
- **`provider remove` со ссылкой** из `agent.*` — код `1`, stderr дополнительно содержит `change the model first: config set agent.default_model <provider>/<model>`.
- **Имя MCP-сервера** в `mcp add` и `mcp remove` не содержит пробелов, `[`, `]`, `"` — иначе ломается путь `mcp.servers[<name>]`; нарушение — `64` до чтения файла.
- **`mcp remove <name>` ищет только по `name`** (ревью итерации 4), никогда по номеру элемента: `mcp remove 0` при отсутствии сервера с именем `0` — код `0` и `mcp.servers[0] is not set in <path>`, первый элемент списка не тронут. Номер в списке не виден пользователю и меняется при любой правке, удаление по нему снесло бы чужой сервер.
- **Ошибка разбора argv** у `config set`, `config unset`, `provider` и `mcp` печатает фиксированную фразу и справку без цитирования слов argv: `invalid arguments for config <sub>` (`<sub>` — `set` или `unset`), `invalid arguments for provider`, `invalid arguments for mcp`. Значение ключа могли передать флагом по ошибке, а значение `config set` может начинаться с `-` и быть разобрано как флаг (та же политика, что у `secret`). У `config check|path|get` значения в argv нет, ошибка разбора печатает причину `package:args`.
- **Неизвестная подкоманда `provider`/`mcp`** (ревью итерации 4) — код `64`, stderr `<бинарь>: unknown <cmd> arguments (<n>)` (`<n>` — число лишних слов) и справка команды; присланное слово не цитируется по той же причине. Тот же текст дают лишние позиционные аргументы. Оба бинаря печатают одно и то же, кроме имени бинаря. У `codelab config` неизвестная подкоманда по-прежнему цитируется (`Unknown command config <sub>`, change `add-agent-configuration`), потому что слово до подкоманды значением быть не может; у `codelab-agent config` — `unknown config arguments (<n>)`.
- **Формат вывода** — часть общего контракта двух бинарей:
  - `config get`: значение (скаляр — одной строкой, отображение и список — JSON с отступом), затем `layer: <name>`; имена слоёв — `user`, `project`, `local`, `extra` (файл `CODELAB_CONFIG`/`--config`), `env`, `flags`. Победитель — старший слой, где ключ задан; его поддерево берётся целиком, без слияния со слоями ниже;
  - `config path`: строки `user: <path> (exists|missing)`, `project: …`, `local: …`, при заданной `CODELAB_CONFIG` — `CODELAB_CONFIG: …`; с `--project`/`--local` — только путь;
  - `provider list`: после `Secrets: <backend>` — `<id>  kind: …  base_url: …  models: a, b  key: <source>`; без `base_url` — `(default)`;
  - `mcp list`: `<name>  type: …  layer: …  enabled: true|false`;
  - успех записи: `Updated <key> in <path>`, `Updated providers.<id> in <path>`, `Updated mcp.servers[<name>] in <path>`, `Removed <key> from <path>`.
- **Коды выхода:** `0` — успех, в том числе удаление отсутствующей записи; `1` — новая ошибка загрузки итога (R3-1), отказ доверия, `inlineSecret`, конфликт после повтора, отказ хранилища секретов, `config get` отсутствующего ключа; `64` — ошибка использования: неизвестный ключ в `set`, разбор значения, лишние или недостающие аргументы, несовместимые флаги, `provider add` без `--kind`/`--model`/`--context-window`, недопустимое имя MCP-сервера в `mcp add` и `mcp remove`, неизвестная подкоманда.
- **Повтор при конфликте.** `ConfigConflictException` — одно автоматическое повторение `read` → `apply`: правки CLI декларативны, а устаревшего экрана, который нужно защитить, у CLI нет. Второй конфликт — код `1`, `config file changed during the edit; run the command again`.
- **Вывод успеха:** `Updated <key> in <path>` или `Removed …`, затем строки `warning: <key>: <message>` из `ConfigWriteResult.warnings` — в том числе проблемы, которые были в конфиге до правки (R3-1, D5): `config set budget.max_steps 40` в пустом `$CODELAB_HOME` печатает `warning: agent.default_model: required` и выходит с кодом `0` — и `note: restart the agent to apply: <keys>` при `restartRequiredKeys`. Работающий агент подхватывает правку перезагрузкой (D7).
- **`--api-key-stdin`:**
  1. проверка кандидата конфига без записи;
  2. `SecretAdmin.checkStore("codelab/<id>")` — тот же порядок, что `secret set` (D8 change `add-agent-secret-store`): бэкенд `env` → код `1` с подсказкой `secrets.backend: file` или переменной;
  3. ввод ключа через `SecretInput`;
  4. `SecretAdmin.store`;
  5. `apply` с `api_key_secret: codelab/<id>`.

  Сбой шага 5 оставляет сохранённый секрет и называет его в stderr (`the secret codelab/<id> was stored; the config was not changed: …`). Секрет без ссылки безвреден, а повтор команды перезапишет его тем же значением. Если секрет `codelab/<id>` уже есть (`SecretAdmin.store` вернул `SecretUpdated`), stdout получает строку `warning: replaced the existing secret codelab/<id>` — значение старого секрета не печатается.
- **Совпадение бинарей.** `codelab-agent config|provider|mcp …` и `codelab config|provider|mcp …` вызывают одни методы. stdout, stderr и коды выхода одинаковы, кроме имени бинаря в справке использования. Флаги подключения CLI вместе с этими подкомандами — `64`, как у `config check` и `secret`.
- **Мастер.** `codelab provider add` без флагов на TTY в этом change — ошибка использования, как у `codelab-agent`. Мастер (§12.4.4) добавит change `add-provider-setup-ui`, не меняя флаговую форму.

### D7. Источник конфига и наблюдатель

**Порт ядра** (`config/config_source.dart`) — отступление от §17.5.2 (D8: один корень на хост):

```dart
/// Источник конфигурации работающего агента: те же слои, окружение и флаги, что при старте хоста.
abstract interface class ConfigSource {
  /// Результат стартовой загрузки, с которым хост собрал ядро; исходные values для первого diff.
  ConfigLoadResult get initial;
  /// Загрузка для корня запуска хоста; ConfigLoadResult — как при старте (полный снимок и withoutProject).
  /// Доверие проектам закреплено на initial до перезапуска (D8, «Пересборка снимка»).
  /// rebase: false — загрузка для проверки (/config check): база наблюдателя не сдвигается.
  Future<ConfigLoadResult> load({bool rebase = true});
  /// Сигнал «прочитанные файлы изменились» — уже после debounce и сравнения sha256.
  Stream<void> get changes;
}
```

**Реализация** `FileConfigSource` (`codelab_agent_io`) — `ConfigLoader` с параметрами запуска хоста плюс `ConfigWatcher`. Хост создаёт её до сборки ядра, с результатом стартовой загрузки (`initial`), и база сравнения наблюдателя снимается в конструкторе — правки между стартовой загрузкой и конструктором не видны (Risks, «Окно до создания источника»); каждая `load()` вызывает `ConfigLoader.load(..., pinnedTrustedProjects: <initial.config.trustedProjects>)`, а загрузчик передаёт список в `CoreConfig.fromLayers` — доверие вычисляет ядро (D8, «Пересборка снимка»); новое значение ключа попадает только в `values`. `close()` останавливает наблюдение. Владелец источника — хост, который его создал: `AgentHost` или открыватель встроенного агента. Хост закрывает источник после `runtime.dispose()`.

**`ConfigWatcher`** следит за файлами, которые загрузчик читает или прочитал бы:
- `$CODELAB_HOME/config.yaml`;
- файл `--config`/`CODELAB_CONFIG`;
- `<root>/.codelab/config.yaml` и `config.local.yaml`, в том числе ещё не созданные;
- `$CODELAB_HOME/secrets.yaml` — при `secrets.backend: file`.

Последний пункт закрывает ограничение 8.9 «замена прочитанного секрета видна только после перезапуска»: замена ключа даёт перезагрузку без изменений конфига, а она сбрасывает кэш резолвера и пересобирает функцию модели (D8).

Механизм наблюдения:
- **События каталога.** `Directory.watch` без рекурсии на родительском каталоге: замена через `rename` — событие каталога. Одна подписка на каталог, сколько бы файлов в нём ни наблюдалось.
- **Отсутствующий каталог.** На macOS `Directory.watch` по несуществующему каталогу не бросает и не сообщает об ошибке — поток молча ничего не присылает. Поэтому настоящая фабрика `defaultDirectoryEvents` сама проверяет каталог и бросает `PathNotFoundException`, а наблюдатель переводит его файлы на опрос с `config.watch.fallback`. Файл, ушедший на опрос, остаётся на опросе до `close()`: каталог `.codelab/`, созданный после старта, наблюдается опросом, а не новой подпиской.
- **Опрос.** Если каталога нет, поток событий бросил, вернул ошибку или завершился (`onDone` — например, каталог удалён) — опрос раз в `config.poll_interval` (`2s`, `1s..60s`) по `(exists, mtime, size)`; при их смене — тот же debounce и сравнение sha256. Сбой замера правкой не считается, повтор — на следующем тике.
- **Какое событие — сигнал.** Debounce запускает только событие, у которого источник или цель `rename` имеет точное имя наблюдаемого файла этого каталога; остальные имена каталога игнорируются.
- **Debounce 300 мс** на часах `Clock` ядра (`FakeClock` в тестах): новые события перезапускают таймер.
- **Сравнение.** По истечении debounce наблюдатель считает sha256 всех наблюдаемых файлов; совпадение с базой — не изменение. Состояние файла — sha256 байтов, `null` (файла нет) или отдельное «нечитаемый» (ошибка чтения, `config.watch.failed`): оно отлично и от отсутствия, и от любого содержимого, а причину назовёт загрузчик. Файл больше лимита загрузчика (`maxConfigBytes`) не читается: его отпечаток — `(size, mtime)` (ревью итерации 5): загрузчик такой файл всё равно отклонит, а чтение без лимита в изоляте UI десктопа нежелательно (Risks, «Синхронный IO наблюдателя»).
- **База сравнения.** `start()` берёт текущие sha256 за базу; база обновляется при каждом сигнале и в `ConfigWatcher.rebase()`. `FileConfigSource.load()` вызывает `rebase()` перед чтением слоёв: собственное чтение повторного сигнала не даёт, а правка во время чтения — даёт (её sha256 отличается от базы, снятой до чтения). **`rebase()` — только на пути перезагрузки** (ревью итерации 5): `checkConfig()` вызывает `load(rebase: false)`. Иначе `/config check`, вызванный, пока правка ждёт debounce, сдвинул бы базу на новое содержимое, по истечении debounce sha256 совпали бы с базой, и перезагрузка потерялась бы (agent-configuration, сценарий «/config check во время debounce не теряет перезагрузку»).
- **Ссылки (symlink).** Для каждого наблюдаемого файла наблюдаются и лексический путь, и каноническая цель ссылки — каталог цели (`config.yaml -> ~/dotfiles/codelab/config.yaml`: правка в `~/dotfiles/codelab/` не порождает события в `$CODELAB_HOME`). Сигнал — по событию любого из путей; содержимое сравнивается через лексический путь, то есть по тому, что прочтёт загрузчик. Каноническая цель пересчитывается в `rebase()`: перенаправление ссылки видно со следующей загрузки.
- **Служебные файлы писателя** (подготовка итерации 5 по ревью итерации 3). `ConfigWriter` создаёт рядом с целью `config.yaml.lock`, `*.lock.stale-*` и `*.tmp-*` — в `$CODELAB_HOME` и в `.codelab/`. События по ним перезагрузку не запускают: наблюдатель отбрасывает их до debounce предикатом `isConfigWriterFileName` из `config_write_lock.dart` (D5, «Где»), а не держит свои шаблоны. Запись писателя видна наблюдателю одним событием — итоговым `rename` tmp поверх цели (источник служебный, цель наблюдаемая) — и даёт один сигнал.

Окружение и флаги не перечитываются: у живого процесса они не меняются.

**Ключи** `config.watch` (`true`) и `config.poll_interval` (`"2s"`) переходят из `afterMvpSections` в схему с потребителем:
- слои `user`, `projectLocal` и `--config`; в проектном слое 3 — отбрасываются с `config.project.untrusted_key` (§17.5.9, таблица доверия); в `config.local.yaml` недоверенного проекта — тоже: пока проект не в `trusted_projects`, слой 4 подчиняется правилам слоя 3 (§15.2);
- `restartRequired`: наблюдатель создаётся один раз;
- `config.watch: false` — `FileConfigSource` без наблюдателя: `changes` никогда не срабатывает, `/config reload` работает.

**Тестируемость.** Два узких шва `ConfigWatcher`, оба с настоящей реализацией по умолчанию:
- `typedef DirectoryEventsFactory = Stream<DirectoryChange> Function(Directory)` — поток событий каталога. `FileSystemEvent` в Dart 3 запечатан и вне SDK не строится, поэтому шов отдаёт свою узкую структуру `DirectoryChange {path, destination}` (`destination` — цель `rename`, если платформа её называет); `defaultDirectoryEvents` переводит в неё `FileSystemEvent` (`FileSystemMoveEvent.destination`). Исключение при вызове фабрики и ошибка потока переводят файлы каталога на опрос.
- `typedef ConfigFileProbe = ConfigFileStamp Function(String path)` — замер `(exists, mtime, size)` для опроса (`defaultConfigFileProbe` — `stat`); исключение замера — `config.watch.failed`.

Unit-тесты подают события вручную и двигают `FakeClock`, без ожидания настоящей ФС. Один интеграционный тест на временном каталоге проверяет настоящий `watch` с пределом «сигнал не позже 5 с» (D15).

**Защищаемые пути.** Тот же список файлов (плюс каталоги `$CODELAB_HOME/agents` и `$CODELAB_HOME/prompts`) хост передаёт политике разрешений как пути PERM-11 (D8, «Пути конфигурации агента для PERM-11»): что агент перечитывает на лету, то модель не правит без человека. Исключение из «того же списка» — `$CODELAB_HOME/secrets.yaml`: наблюдатель следит за ним только при `secrets.backend: file` (это перезагрузка), а защищён он при любом бэкенде (R5-1). Защищаемых путей поэтому не меньше, чем наблюдаемых.

**Ошибки наблюдателя** не теряются (`AGENTS.md` §12): ошибка потока `watch` переводит файл на опрос и пишет `config.watch.fallback {path, reason: <runtimeType>}` (info). Исключение замера при опросе и ошибка чтения файла при сравнении sha256 — `config.watch.failed` (warning, поля — D14); опрос продолжается, нечитаемый файл сравнивается как отдельное состояние.

### D8. Перезагрузка в `AgentRuntime`

**Единица перезагрузки — корень запуска хоста.** Снимок — пара «полный `CoreConfig` + `withoutProject`» (D9 change `add-agent-configuration`), и она заменяется атомарно целиком. Снимок на каждый `cwd` сессии (§17.5.6, «снимок `CoreConfig` на корень») не вводится:
- у встроенного агента корень один (папка проекта соединения);
- у `serve` сессии вне корня запуска уже получают снимок без проектных слоёв;
- чтение проектного конфига чужого `cwd` — новое поведение с вопросами доверия, его место — отдельный change.

Отсюда у `ConfigSource` нет параметра `cwd` (D7).

**API ядра** (добавления к §10.3):

```dart
// AgentCoreServices
final ConfigSource? config;     // null → перезагрузки нет, команды /config нет
final AgentConfigPaths? agentConfigPaths;   // PERM-11 (D8): пути, значения $HOME/$CODELAB_HOME и регистр ФС от хоста

// buildAgentCore(..., bool configCommand = true)   // false → /config не объявляется и не исполняется (serve --ws, R0-3)

// ConfigLoadResult (ядро) — новое поле:
final Map<String, Object?> values;   // плоская карта листьев итогового дерева после слияния: "budget.max_steps" → 40,
                                      // "mcp.servers[github]" → элемент целиком; основа diff шага 4

// buildAgentCore(..., ConfiguredModels Function(CoreConfig config)? modelsFor)
typedef ConfiguredModels = ({StreamFunction stream, ModelCatalog catalog});
// services.config != null и modelsFor == null → HostWiringException

// AgentRuntime
Future<ConfigApplyReport> reloadConfig();   // ConfigSource.changes, /config reload, /mcp reload
Future<ConfigLoadResult> checkConfig();     // /config check: load(rebase: false), план, withDeferred + validateSnapshot, без применения
ConfigStatus configStatus();

enum ConfigReloadOutcome { applied, unchanged, failed }
final class ConfigApplyReport {
  final ConfigReloadOutcome outcome;
  final List<ConfigIssue> issues;          // только failed
  final List<String> changedKeys;          // применённые листья; mcp.servers — "mcp.servers[<name>]"; отсортирован
  final List<String> restartRequiredKeys;  // ключи показа: лист, "mcp.servers[<name>]", "providers.<id>"; отсортирован
}
final class ConfigStatus {
  final DateTime loadedAt; final List<String> sources;
  final DateTime? lastFailureAt; final List<ConfigIssue> lastIssues;  // lastIssues очищает успех, lastFailureAt — история
  final List<String> pendingRestartKeys;   // restartRequiredKeys последней успешной перезагрузки (шаг 5)
}
```

**Контракт вызовов** (реализация задач 5.1–5.4):
- **Без источника.** `services.config == null` → `reloadConfig()` и `checkConfig()` бросают `StateError` (ошибка сборки хоста, а не конфига); `configStatus()` работает всегда — без источника это снимок сборки без источников.
- **`reloadConfig()` не бросает.** Исключение `ConfigSource.load()`, `CoreConfig.withDeferred`/`validateSnapshot` или `modelsFor` → итог `failed` с одной проблемой `the config could not be reloaded (<runtimeType>)`, `lastFailureAt`/`lastIssues` обновлены, лог `config.reload.failed {error_class}` (error). Текст исключения не попадает ни в проблему, ни в лог: он мог бы содержать значение ключа (CFG-2, D14). Подписка на `changes` дополнительно ловит ошибку вызова и пишет тот же `config.reload.failed {error_class}` — защита в глубину (`AGENTS.md` §12).
- **`dispose()`.** Вызов после `dispose()` и загрузка, завершившаяся после него, дают итог `unchanged` без побочных эффектов: снимок, `configStatus`, кэш секретов не меняются, событий сессиям и замен MCP нет. Исключение `load()` после `dispose()` — тоже `unchanged`, без `lastIssues`. Повтор коалесценции после `dispose()` не запускается и получает тот же итог.
- **`checkConfig()`** возвращает `ConfigLoadResult` загрузки без применения: состояние рантайма не меняется. Загрузка — `ConfigSource.load(rebase: false)`: проверка не сдвигает базу наблюдателя (D7, «База сравнения»). Невалидная загрузка возвращается как есть (`issues`). Для валидной считается тот же план шагов 4–5 против применённого снимка (по обоим снимкам, шаг 5) и прогоняется `CoreConfig.withDeferred(...).validateSnapshot()` (ревью итерации 5): проблема повторной проверки попадает в `issues` результата — `/config check` не должен печатать `Config: valid` там, где `/config reload` дал бы `failed`; каждый отложенный ключ — предупреждение результата (`warnings`) с `event: 'config.reload.restart_required'`, `key` и `fields: {key}` = ключ показа, сообщение `applies only after a restart`. Команда `/config check` (задача 7.2) печатает из этих предупреждений строку `Restart required: …`, отдельного поля результата нет. Исключение `load()` уходит вызывающему: команда показывает его как ошибку проверки.

**`modelsFor` и `streamFunction` при сборке** (решение 2026-11-02 по итогам итерации 0). `buildAgentCore` сохраняет `required StreamFunction streamFunction` — функцию модели начального снимка, как сейчас; начальный каталог — по-прежнему `AgentCoreServices.models` (у `CoreConfig` поля каталога нет). `modelsFor` необязателен и вызывается только на снимках, применённых перезагрузкой (шаг 6 алгоритма), при сборке — нет. Правила:
- `services.config != null` и `modelsFor == null` → `HostWiringException`;
- `services.config == null` → `modelsFor` не требуется и не вызывается (`--llm-script`, тесты, хосты без источника);
- хост с источником строит начальную функцию и каталог одним вызовом того же замыкания: `final models = modelsFor(config);` затем `services.models: models.catalog`, `streamFunction: models.stream`, `modelsFor: modelsFor` — одна дорога для старта и перезагрузки.

Альтернатива — `modelsFor(<начальный снимок>)` при сборке и `streamFunction` как взаимоисключающий тестовый шов (`HostWiringException` при обоих) — отклонена: она меняет обязательный параметр, который передают 24 файла хостов и тестов, ради инварианта, который хост соблюдает одной строкой выше; перевод `streamFunction` в тестовый шов — отдельный рефакторинг (§19 корневого `AGENTS.md`).

**`ConfigLoadResult.values` и прежние `HostSettings`** (ревью итерации 0). Шаг 4 сравнивает листья, а у `CoreConfig` и `HostSettings` их нет в общем виде. Поэтому `CoreConfig.fromLayers` дополнительно возвращает плоскую карту листьев итогового дерева `ConfigLoadResult.values` (пути — как у `SettingsRegistry` и `changedKeys`; элемент `mcp.servers` — целиком под `mcp.servers[<name>]`). Это добавление к публичному типу ядра: новое поле с умолчанием `const {}`, существующие вызовы не меняются. Значения в карте — те же, что в файлах (без раскрытия `${…}`); в лог и отчёты попадают только ключи. Рантайм хранит карту и `HostSettings` применённого снимка: ключи хоста `restartRequired`, и их прежние значения подставляются в новый снимок (шаг 5), а `HostSettings` не меняется до перезапуска.

**Почему `modelsFor`, а не пересборка в ядре.** Функцию модели и каталог строит хост: `http.Client` и сервисы LLM — его (PKG-6), `--llm-script` подставляет сценарий. `modelsFor` — замыкание хоста над `createConfiguredStreamFunction(config, llm, secrets:)` и `StaticModelCatalog(config.providers)`; ядро вызывает его на каждом применённом снимке. В отчёте отсутствуют поля `mcpConnected`/`mcpDisconnected`/`mcpReconnected` §17.5.2: серверы применяются после хода (D10), отчёт их ещё не знает. Итог MCP — в логе `mcp.server.*`.

**Алгоритм** (§17.5.6 с уточнениями):
1. **Коалесценция.** Перезагрузка уже идёт → отметить повтор (не больше одного в очереди) и вернуть `Future` повтора. Все вызовы во время идущей получают итог повтора, который видит последние файлы.
2. **Загрузка.** `result := await config.load()`. `dispose()` во время ожидания → результат отбрасывается, ничего не применяется, уведомлений нет, итог `unchanged`. Признак `dispose()` проверяется после единственного `await` — от него до замены снимка (шаг 6) кода с `await` нет, поэтому отдельный `CancelToken` не нужен.
3. **Ошибка.** Проблемы загрузки (`issues`), загрузка без `config` или проблемы повторной проверки снимка (шаг 5):
   - Записать `lastFailureAt` и `lastIssues`.
   - Лог `config.reload.failed {sources, issues: [{source, line, column, key, kind}]}` (error), без значений. Исключение вместо результата — та же ветка, но лог `config.reload.failed {error_class}` («Контракт вызовов»).
   - Прежний снимок остаётся целиком, клиентам ничего не уходит (CFG-15).
   - Итог — `failed`.
4. **Сравнение.** `diff` — листовые ключи с другим значением; `mcp.servers` сравнивается по `name` и `sameConnection`.
   - **Списки — листья diff** (ревью безопасности итерации 2): `permissions.deny`, `trusted_projects`, `tools.disabled` и любой другой список сравниваются целиком и дают один ключ (`permissions.deny`), без индексов элементов. Развёрнут только `mcp.servers` — по элементам `mcp.servers[<name>]`. Так ключ diff всегда совпадает с путём дескриптора реестра или покрывается им.
5. **Ключи перезапуска.**
   - `restart := diff ∩ {d.restartRequired}` (D4).
   - **Fail closed для ключа вне реестра** (ревью безопасности итерации 2): ключ diff, для которого `SettingsRegistry.lookup` не нашёл дескриптора, считается требующим перезапуска и попадает в `restart`. Расхождение схемы и реестра (тест полноты ловит его при сборке, но не в чужой сборке хоста) не должно превращаться в живое применение ключа, о котором реестр ничего не знает. Тест — в `config_reload_test.dart` (задача 5.3).
   - **План — по обоим снимкам** (R0-1 по обоим снимкам, ревью итерации 5). Сессии вне корня запуска работают на `withoutProject`, поэтому правила R0-1 и R0-4 применяются к сравнению и полного снимка, и `withoutProject` (поля `permissions`, `mcpServers`, `providers`, ссылки на модели); ключ отложен, если он отложен по любому из сравнений. Иначе ключ, перекрытый в полном снимке проектным слоем (проект задаёт `permissions.tools.exec: ask`, а глобальный конфиг меняется на `allow`), дал бы пустой diff полного снимка и применился бы на лету к сессиям вне корня (agent-runtime, сценарий «Проектный слой перекрывает ключ»).
   - Отложенные ключи берутся из применённого снимка, и снимок проверяется заново семантически (механизм — «Пересборка снимка с отложенными ключами» ниже). Ошибка — как шаг 3.
   - **`pendingRestartKeys := restart`** последней успешной перезагрузки (не объединение за всё время). Накопление получается по построению: `values` применённого снимка хранят *прежние* значения отложенных листьев, поэтому ключ, отложенный раньше и не возвращённый в файле, снова попадает в diff и в `restart` следующей перезагрузки. Ключ, возвращённый в файле к применённому значению, из diff и из набора уходит: набор отвечает на вопрос «чем файлы сейчас отличаются от работающего процесса», а не хранит историю. Неудачная перезагрузка (`failed`) набор не меняет. Непустой `restart` — лог `config.reload.restart_required {keys}` (warning).
   - Ключи хоста (`HostSettings`: `sessions.*`, `logging.*`, `profile.*`) — все `restartRequired` (D14, OQ5).
   - **Ключи, ослабляющие права, — тоже только после перезапуска** (R0-1, решение пользователя 2026-11-02; защита в глубину поверх PERM-11). По схеме этой сборки:
     - `permissions.mode`, `permissions.deny`, `permissions.tools` (весь раздел `permissions.*`; `permissions.timeout` пока не применяется);
     - `trusted_projects`: доверие закреплено в `CoreConfig.fromLayers(pinnedTrustedProjects:)` на стартовом снимке, загрузчик только передаёт список (ниже, «Пересборка снимка»), поэтому новое значение не меняет, какие проектные ключи действуют, — ни при добавлении проекта, ни при снятии доверия;
     - элемент `mcp.servers[<name>]` с `type: stdio`, для которого в прежнем (применённом) снимке нет элемента `old` с `old.sameConnection(new) && (old.enabled || !new.enabled)` — то есть новый (в том числе сразу с `enabled: false`), включённый из `enabled: false`, сменивший тип (`http` → `stdio`) или изменивший `command`, `args`, `env` (в том числе шаблоны `${secret:…}` в `env`, `secretValues`). Удаление и выключение (`true → false`) stdio-сервера применяются живой перезагрузкой.
     - **Выключенный сервер — тоже** (R6-1, решение пользователя 2026-11-03). Правка параметров соединения (всё, что не проходит `sameConnection`: `command`, `args`, `env`, `type`, а у HTTP-сервера с подстановкой — `url`, `headers`) у сервера с `enabled: false` откладывается так же, как у включённого. Иначе модель вписала бы команду в выключенный сервер, а человек потом включил бы его `/mcp enable` (D11), не видя подмены, — обход R0-1. `/mcp enable` подключает сервер с параметрами применённого снимка. `McpServerConfig.sameConnection` не включает `enabled`, поэтому смена признака сравнивается отдельно — второй половиной условия.
     - **Выключение вместе с правкой соединения.** Если правка одновременно ставит `enabled: false` и меняет параметры соединения, выключение применяется сразу, а параметры — после перезапуска: в применённом снимке элемент — прежний с `enabled: false` (и в `CoreConfig.mcpServers`, и в листе `values` `mcp.servers[<name>]`), ключ — в `pendingRestartKeys`. Так соблюдены обе половины R6-1: выключение не ждёт перезапуска, а новая команда не попадает в снимок, из которого её подключит `/mcp enable`.
   - **Правки, способные направить секрет на другой адрес, — тоже только после перезапуска** (R0-4, решение пользователя 2026-11-02). «Ссылка на секрет» определяется **по значению, а не по имени**: любая подстановка `${…}` — и `${secret:…}`, и `${VAR}` (значение переменной окружения тоже может быть ключом):
     - элемент `mcp.servers[<name>]` с `type: http`, для которого нет прежнего `old` с `old.sameConnection(new) && (old.enabled || !new.enabled)`, если в его `url`, `headers` или `env` есть подстановка `${…}` (`X-Gw: ${secret:gw}`, `Authorization: Bearer ${GITHUB_TOKEN}`); выключенный сервер — по тому же правилу, что stdio (R6-1);
     - провайдер `providers.<id>` «с ключом» — у которого в прежнем или новом снимке есть `api_key_secret` или `api_key_env`, подстановка `${…}` в `base_url`, `headers` или `auth_header`, или литеральный секретный заголовок по правилу имён D5 (после ручной правки), — если он новый или у него изменилось поле группы адреса и аутентификации: `kind`, `base_url`, `headers`, `auth_header`, `api_key_secret`, `api_key_env`; путь — `providers.<id>`. Группа атомарна: при отложенной правке прежними остаются все её поля, а модели (`providers.<id>.models.*`) — новые;
     - каждая ссылка на модели нового провайдера, исключённого этим правилом: `agent.default_model`; после появления потребителя — `agent.fallback`, `agent.summary_model`, `llm.roles.*`, модели субагентов. Ссылки откладываются вместе с провайдером, поэтому `validateSnapshot` не валит перезагрузку: итог — `applied` со строкой `Restart required`, а не `failed`.
     Живая перезагрузка остаётся для моделей провайдера, провайдеров без ключа, HTTP-серверов без подстановок, удаления и выключения серверов и провайдеров.
     `${…}` в `base_url` тоже делает провайдера «с ключом»: значение переменной может нести токен в query или userinfo. Запрет подстановок в `base_url` схемой отклонён — §17.5.3 и существующие конфиги их допускают (адрес шлюза из окружения), а запрет сломал бы загрузку; правило «с ключом» дешевле и не меняет схему.
     **Обязанность будущих change:** поля провайдера `preset`, `auth`, `key_rotation` (и другие поля адреса или аутентификации) при появлении потребителя входят в группу R0-4 — их change дополняет список и тест.
     Ключи без потребителя в этой сборке (`exec.*`, `tools.untrusted_paths`, `tools.disabled`, `redact.*`, а также `agent.fallback`, `agent.summary_model`, `permissions.timeout` и другие узлы `applied: false`, D4) дают `config.key.not_applied` и перезагрузкой не применяются вовсе. `tools.disabled` в этом списке не случайно: снятие запрета на лету снова включает инструмент, то есть ослабляет ограничение.
     **Обязанность будущих change** (ревью безопасности итерации 2): change, который делает `exec.*`, `tools.disabled` или `redact.*` применяемым (как и любой другой ключ без потребителя), в том же изменении решает его `restartRequired` в реестре (D4), дополняет таблицу «Когда действует новое значение» и константу ключей перезапуска теста полноты. Умолчание «на лету» для такого ключа без явного решения запрещено: ослабление `exec.env`, `redact.*` или снятие `tools.disabled` — изменение границы безопасности.
   - Отложенные ключи попадают в `restartRequiredKeys`, `pendingRestartKeys`, событие `config.reload.restart_required {keys}` и строку `Restart required: …` ответа `/config reload` и `/config check`.

**Пересборка снимка с отложенными ключами** (повторное ревью итерации 0). Механизм — в два звена, каждое там, где есть нужные данные:
1. **Доверие — закреплённый список в ядре.** Доверие вычисляет ядро: `CoreConfig.fromLayers` → `resolveConfig` → `_trustedRoots` (`resolve.dart`). Публичная функция ядра получает новый параметр `CoreConfig.fromLayers(..., pinnedTrustedProjects:)`; при нём по закреплённому списку строятся оба потребителя доверия: оценка проектных слоёв 3–4 (§15.3) и поле `CoreConfig.trustedProjects` полного снимка и `withoutProject`, по которому новая сессия читает `prompts` и `agents` проекта (`agent_runtime.dart`, `project_files.dart`). `ConfigLoader.load(pinnedTrustedProjects:)` лишь передаёт список; `FileConfigSource` берёт его из `initial.config.trustedProjects` на каждой перезагрузке до перезапуска. Новое значение `trusted_projects` попадает только в `values` и через diff — в `pendingRestartKeys`. Почему не подстановкой после загрузки: доверие решает, какие ключи проектных слоёв войдут в дерево, и после `fromLayers` этого уже не восстановить.
2. **Остальные отложенные ключи — в ядре, подстановкой из применённого снимка.** Чистая функция ядра `CoreConfig.withDeferred(CoreConfig previous, CoreConfig next, DeferredConfigParts deferred, {Map<String, Object?>? withoutProjectValues}) → CoreConfig` работает только над `CoreConfig` (и его `withoutProject` — тем же набором относительно `previous.withoutProject`, а без него — относительно `previous`). Набор отложенного передаётся **структурированно** — значением `DeferredConfigParts {providers, servers, permissions, defaultModel}`: идентификаторы провайдеров R0-4, имена серверов `mcp.servers`, признак «раздел `permissions` прежний», признак «`agent.default_model` прежняя» (будущие ссылки на модели добавят свои поля). Его строит план шага 5 (`planConfigReload` → `ConfigReloadPlan.deferred`, объединение `union` по обоим снимкам) из самих снимков, а не из строк ключей. Ключи показа (`mcp.servers[<name>]`) — только для отчёта, лога и `pendingRestartKeys` и повторно не разбираются (ревью итерации 5): имя сервера, заданное в файле вручную, может содержать `]` (или `[`, `"`), разбор `mcp.servers[a]b]` давал бы `null`, и новый stdio-сервер остался бы в снимке — fail-open (agent-runtime, сценарий «Имя сервера с ]»).
   **Карта листьев снимка без проекта — `CoreConfig.withoutProjectValues`** (плоская карта, как `ConfigLoadResult.values` полного снимка; `null` — снимка без проекта нет). Её заполняет `fromLayers`, читает `planConfigReload` для сравнения второго снимка (R0-1 по обоим снимкам), а `withDeferred` записывает в итог значения после подстановки (`withoutProjectValues:` — `ConfigReloadPlan.appliedWithoutProjectValues`; по умолчанию — из `next`), чтобы следующая перезагрузка сравнивала с ними. Карта лежит в `CoreConfig`, а не в `ConfigLoadResult`: адаптеры источника (`ConfigSource` хостов, тестовые) пересобирают `ConfigLoadResult` и потеряли бы её, а без карты сравнение второго снимка молча дало бы пустой diff — fail-open. Внутри `CoreConfig` карта едет вместе со снимком через любой адаптер; отсутствующая карта сравнивается как пустая — расхождение откладывается (fail closed). Подстановка: `permissions` — целиком прежние; элемент `mcpServers` по имени — прежний элемент, а новый — исключается; провайдер R0-4 — `CatalogProvider` собирается из прежних `config` (адрес, заголовки, `authHeader`), `key` и `headerTemplates` и новых `models`, запись `providerProblems` этого провайдера — прежняя; новый провайдер R0-4 исключается вместе со ссылками на его модели. `HostSettings` и `values` лежат в `ConfigLoadResult`, поэтому их подставляет рантайм сам: прежние `HostSettings`, `values` с прежними значениями отложенных листьев. `checkConfig()` (`/config check`) загружает конфиг тем же путём — по закреплённому доверию из `initial`, без сдвига базы наблюдателя (`load(rebase: false)`) — и прогоняет ту же подстановку и проверку; новое значение `trusted_projects` и другие отложенные ключи печатаются строкой `Restart required`. Затем `CoreConfig.validateSnapshot` — семантическая проверка (модель по умолчанию есть в каталоге, маршруты); ошибка — как шаг 3.

Альтернативы:
- **Слой-перекрытие `ConfigSource.load(overrides: …)` + `fromLayers`** — отклонён: какие элементы отложить (stdio, R0-4), видно только после сравнения с прежним снимком, то есть понадобилась бы вторая загрузка после diff (два чтения файлов и окно гонки между ними), а слияние `mcp.servers` по `name` не умеет «убрать элемент» без нового маркера в формате слоя.
- **Проектные слои из прежнего снимка** — отклонён: тогда не применялись бы и безопасные проектные ключи (бюджет, модели проекта), а рантайму пришлось бы хранить сырые слои.
6. **Применение.**
   - `secrets?.invalidate()` — всегда, даже при пустом `diff`: значение в хранилище могло смениться.
   - `models := modelsFor(next)` — всегда, по той же причине: цепочки провайдеров держат разрешённый ключ.
   - Атомарная замена снимка, функции модели и каталога.
   - **`unchanged` — только при пустом `diff`** (лог `config.reload.noop`, debug). Если `diff` непуст, но весь отложен (`changedKeys` пуст, `restartRequiredKeys` нет), итог — `applied` с `restart_required`: файлы изменились, и человек должен увидеть строку `Restart required`, а не `Config unchanged`.
7. **Живые сессии** (возвращённые вызывающему до замены и не закрытые):
   - a. серверы конфига — D10;
   - b. список id моделей нового каталога отличается от каталога прежнего снимка (по порядку каталога) → событие `ModelOptionsChanged` (новая ветка `AgentEvent`) → адаптер ACP шлёт `config_option_update` с полным снимком опций сессии (§13.6). Событие публикуется **синхронно в момент замены, вне очереди агента** — и во время хода: оно не часть хода модели и не ждёт `TurnEnded`. Закрытой сессии не шлётся. В журнал сессии событие не пишется: это проекция состояния рантайма, а не история разговора. **В историю хода оно тоже не буферизуется** (ревью итерации 5): подписчик, подключившийся к ходу позже, получает события хода, но не `ModelOptionsChanged` — к моменту подключения опции сессии уже актуальны, и повтор дал бы лишний `config_option_update` с устаревшим основанием.
8. **Итог.** `lastIssues := []`, лог `config.reload.applied {keys, restart_required}` (info), итог `applied`. `changedKeys` — применённые листья, `restartRequiredKeys` — ключи показа (лист; `mcp.servers[<name>]`; `providers.<id>` вместо листьев группы провайдера), оба отсортированы.

**`SecretResolver.invalidate()`** очищает кэш найденных значений. Поиск, начатый до `invalidate` и завершившийся после, отдаёт значение вызывающему, но в кэш его не кладёт: счётчик поколений не даёт устаревшему значению пережить сброс. Single-flight сохраняется внутри поколения.

**Когда действует новое значение** (CFG-16; ключи схемы этой сборки, остальные — §17.5.6 вместе со своими change):

| Ключи | Когда |
|---|---|
| `providers.*` (включая модели), маршруты | следующий шаг любой сессии: шаг берёт функцию модели в начале. Сессия, чья текущая модель исчезла из каталога, продолжает работать на функции модели прежнего снимка до смены модели; опция `model` показывает её текущей |
| `agent.default_model`, `agent.effort` | новые сессии; модель идущей сессии меняют `/model`, `session/set_config_option` |
| `budget.*`, `compaction.*` | следующий ход: сессия перечитывает бюджет хода и параметры сжатия из применённого снимка на границе хода (при старте `prompt`); идущий ход доигрывает с прежними. Права и режим там не читаются (R0-1) |
| `mcp.servers`: HTTP-серверы без ссылок на секреты, удаление и выключение любых серверов | после текущего хода, без хода — сразу (D10) |
| `tools.project_context.*` | новые сессии (файлы проекта фиксируются при создании, D9) |
| `tools.disabled` | не применяется в этой сборке (`config.key.not_applied`); `restartRequired` решит change потребителя (обязанность выше) |
| `redact.*` | не применяется до 8.11 (`config.key.not_applied` как сейчас) |
| `permissions.*`, `trusted_projects`, новые и изменённые stdio-серверы `mcp.servers[<name>]`, в том числе выключенные (`enabled: false`; R0-1, R6-1) | только после перезапуска (`restartRequired`): ослабление прав не применяется на лету |
| новые и изменённые HTTP-серверы с подстановкой `${…}` (`${secret:…}` или `${VAR}`), в том числе выключенные (R6-1), группа полей адреса и аутентификации провайдера с ключом, ссылки на модели нового отложенного провайдера (R0-4) | только после перезапуска: секрет не уходит на новый адрес без перезапуска |
| `sessions.*`, `logging.*` (включая `logging.level`, OQ5), `profile.*`, `secrets.backend`, `config.*` | только после перезапуска (`restartRequired`) |

Транспорт ACP (`--stdio`, `--ws`, порт, токен) — параметры запуска, а не конфиг.

**Конкурентность и поздние события** (`AGENTS.md` §9, §12):
- **Подписка.** Подписку на `ConfigSource.changes` держит рантайм. Она создаётся в `buildAgentCore` и отменяется в `dispose()`; сигнал после `dispose` не приходит.
- **Ошибки.** Ошибка `reloadConfig`, запущенного сигналом, не теряется: она ловится и пишется `config.reload.failed` с `error_class`, а не уходит в зону хоста.
- **Создание сессии.** `createSession`/`loadSession` берёт снимок один раз в начале. Сессия, создаваемая во время замены, получает старый снимок целиком, а в шаге 7 считается живой, только если вернулась до замены. Иначе её первый ход берёт новую функцию модели (шаг 7b для неё не нужен: опции в ответе `session/new` строились по снимку начала, а уведомление до ответа запрещено ACP-8). Расхождение списка моделей в этом окне исправит следующая перезагрузка. Риск принят (Risks).
- **Гонка с `close()` сессии.** Закрытая сессия пропускается, уведомлений ей нет.
- **Двойной снимок.** Невозможен: замена — одно присваивание записи `(config, withoutProject, models)` в изоляте рантайма. Шаг читает запись один раз.

**Модель сессии исчезла из каталога.** Сессия продолжает работать на функции модели прежнего снимка (таблица выше); рантайм пишет `config.reload.model_orphaned {session_id, model}` (info, один раз на сессию и модель): `model` — id `provider/model`, значений конфига нет (D14).

**Пути конфигурации агента для PERM-11** (находка ревью итерации 0 к OQ2). Политика получает от хоста значение `AgentCoreServices.agentConfigPaths: AgentConfigPaths {paths, expansions, caseInsensitive}`:
- `paths` — канонические абсолютные пути: `~` раскрыт, символические ссылки раскрыты по самому глубокому существующему предку (`resolveSymbolicLinks` предка, затем остаток пути), для ещё не созданных файлов — так же;
- `expansions` — значения `HOME` и `CODELAB_HOME` из окружения хоста для раскрытия `~`, `$HOME`, `$CODELAB_HOME` в командах `exec` (у ядра своего окружения нет);
- `caseInsensitive` — признак ФС без учёта регистра (macOS, Windows), его определяет хост. Состав — файлы `ConfigWatcher` (D7: `$CODELAB_HOME/config.yaml`, файл `--config`/`CODELAB_CONFIG`, `<корень запуска>/.codelab/config.yaml` и `config.local.yaml`), `$CODELAB_HOME/secrets.yaml` **при любом `secrets.backend`** и каталоги `$CODELAB_HOME/agents`, `$CODELAB_HOME/prompts` (паритет с проектными `.codelab/agents/**`, `.codelab/prompts/**` §7.6.1). `secrets.yaml` защищён всегда, а не только при `file` (R5-1, решение пользователя 2026-11-03): иначе при `keychain` агент мог бы создать файл со своим значением ключа, а следующей правкой (тоже критической, но уже с готовым файлом) переключить `secrets.backend` — или человек одобрил бы переключение, не зная о подложенном файле. Наблюдение за `secrets.yaml` при этом остаётся условным — при `file` (D7): это вопрос перезагрузки, а не защиты. Строит состав одна функция `codelab_agent_io` (`agentConfigPathsFor(...)`), которой пользуются `AgentHost` и открыватель `codelab_embedded`, — тот же вход, что у `FileConfigSource`, поэтому каждый наблюдаемый файл защищён по построению; защищаемых путей больше — `secrets.yaml` при другом бэкенде, `agents`, `prompts`. Почему поле `AgentCoreServices`, а не `HostProfile`: пути — данные запуска конкретного процесса, а профиль описывает возможности платформы. Сравнение:
- цель `write`/`edit` берётся после канонизации `BoundedEnv` (тот же результат, что для containment) и сравнивается с путями и префиксами каталогов, без учёта регистра при `caseInsensitive`;
- **подмена предка ссылкой.** Защищаемые пути перепроверяются на каждой проверке `write`/`edit`: их каноническая форма пересчитывается асинхронно в `beforeToolCall` политики тем же вызовом `ExecutionEnv`, которым `BoundedEnv` канонизирует цель для containment, поэтому если `.codelab` стал ссылкой на `sub`, то `write sub/config.yaml` совпадает с защищаемым `<root>/.codelab/config.yaml`. Кроме того, каталоги-предки защищаемых путей защищены от создания, переименования, удаления и подмены ссылкой. Каталогом-предком считается **любой** предок каждой формы защищаемого пути (переданной хостом и пересчитанной), кроме корня ФС `/`: не только `<корень запуска>/.codelab` и `$CODELAB_HOME`, но и `~`, корень запуска, каталог файла `--config` и выше. Это консервативно и принято (решение оркестратора 2026-11-03). Семантика `exec`:
  - `rm`, `rmdir`, `mkdir` с предком — критические всегда (`rm -rf ~` удалил бы `$CODELAB_HOME` целиком);
  - предок в роли источника `mv`/`ln` (`mv ~/proj x`, `ln -s ~/proj /tmp/c`) — критический всегда: перенос или второй путь к поддереву с конфигом;
  - предок в роли назначения `mv`/`ln` — критический, только пока его нет на диске: несуществующее назначение создаётся или подменяется, а существующий каталог-назначение кладёт файл внутрь — `mv a ~/.codelab` пишет `~/.codelab/a`, и это ловит обычное сравнение пути `DIR/x` с защищаемыми;
  - обычные операции внутри корня, не затрагивающие предков и защищаемые пути (`rm -rf build`, `mkdir -p src/x`, `mv a b`, `mv a .`), не критичны.
  - с R5-4 эти три правила — всё, что делает критичной команду с **широким** предком (корень запуска, `cwd` сессии, `~` и выше). **Близкий** предок (`.codelab`, `$CODELAB_HOME`, каталог `--config` и промежуточные) в аргументах любой команды не из белого списка чтения критичен как защищаемый путь (ниже, «`exec`: белый список чтения»).
  Граница: висячая ссылка не раскрывается (R5-3, Risks «Висячая ссылка на месте каталога-предка»);
- **удаление и усечение защищаемого файла** (R5-2, решение пользователя 2026-11-03) — тот же критический шаблон `write to agent configuration`: `rm`, `unlink`, `mv <защищаемый> …` (защищаемый путь — источник), `truncate` и перенаправление `>` (в том числе пустое `> file`, `: > file`) с защищаемым путём. Причина: удаление или обнуление файла — тоже правка конфигурации; например, удаление `<корень запуска>/.codelab/config.local.yaml` снимает записанный там `permissions.deny`, и запрещённый инструмент становится доступен без вопроса;
- **резолвер путей политики** (ревью итерации 5). Пересчёт защищаемых путей и второй проход `exec` идут через окружение сессии, только если оно реализует `PathResolver`; иначе — через окружение хоста `AgentCoreServices.baseEnv`. Причина — `serve`: окружение его сессий — клиент ACP (`fs/*`, `terminal/*`), который символические ссылки не раскрывает, а защищаемые пути — пути хоста, где работает наблюдатель и загрузчик. Для `--ws` клиент подключён по loopback, то есть это та же машина и та же ФС; встроенный агент и CLI дают сессии `PathResolver` хоста;
- **ссылка НА защищаемый файл** (`ln -s ~/.codelab/config.yaml /tmp/x`) с R5-4 критична: `ln` не в белом списке чтения, а защищаемый путь — его аргумент. Прежнее решение 2026-11-03 «ссылка НА защищаемый файл не критична» этим заменено. Запись по уже существующей ссылке (созданной человеком или до старта) ловится канонизацией цели: `write`/`edit` — канонизацией `BoundedEnv` (цель вне корня сессии вдобавок отклоняет containment; внутри корня — например, `ln -s .codelab/config.yaml c.yaml`, затем `write c.yaml` — срабатывает именно PERM-11); `exec` (`>`, `tee`, `sed -i`, `rm`, `truncate` по `c.yaml` или `/tmp/x`) — вторым проходом шаблона, который канонизирует проверенные пути команды через резолвер путей политики, если ссылка и её цель существуют. Жёсткая ссылка — другой случай (ниже): у неё нет канонической формы, ведущей к защищаемому пути;
- **жёсткая ссылка.** `ln` без `-s` и `cp -l`/`cp --link`, у которых защищаемый путь стоит в любой позиции (источник или цель), — критический шаблон: жёсткая ссылка на защищаемый файл из другого места позволила бы править его в обход сравнения путей;
- **`exec`: белый список чтения** (R5-4, решение пользователя 2026-11-03). Перечень пишущих команд не полон по построению (`yq -i`, `perl -pi`, `curl -o`, `git checkout -- …`, `rsync`, `tar -C`, `unzip -d`, `find -delete` пишут без `>` и `cp`), поэтому правило перевёрнуто: критична любая команда, кроме команд только чтения.
  - **Разбор.** Каждая простая команда строки: в цепочках `&&`, `||`, `;`, в конвейерах `|`, внутри `sh -c`/`bash -c`, после `env` (в том числе `env -C DIR`), после `cd DIR` — `DIR` становится рабочим каталогом следующих команд цепочки.
  - **Что проверяется.** Слова-аргументы, значения опций (`-o FILE`, `-C DIR`, `--output=FILE`, `-d DIR`, `of=FILE`) и рабочий каталог, заданный `cd`, `env -C` или `-C DIR`. Путь сравнивается после раскрытия `~`, `$HOME`, `${HOME}`, `$CODELAB_HOME`, `${CODELAB_HOME}` (значения — `expansions`) и разрешения относительно рабочего каталога команды (включая `../`); затем — вторым проходом через резолвер путей политики (ссылки).
  - **Правило.** Значение разрешается в защищаемый путь, путь внутри защищаемого каталога или близкий каталог-предок → команда критична, если она не из белого списка: `cat`, `less`, `more`, `head`, `tail`, `grep`/`egrep`/`fgrep`, `rg`, `ag`, `ls`, `stat`, `file`, `wc`, `diff`, `cmp`, `sha256sum`/`shasum`/`md5sum`, `jq`/`yq`, `git diff|log|show|status|blame`, `test`/`[`, `realpath`, `readlink`, `dirname`, `basename`, `echo`/`printf` — каждая без опций записи и исполнения (ниже, «Опции записи и исполнения»). Список консервативен: `sed -n p`, `cp <защищаемый> /tmp/b` (защищаемый путь — источник), `ln -s <защищаемый> x` тоже критичны; расширение списка — отдельным решением.
  - **Перенаправление** (`>`, `>>`, `>|`, `&>`, `2>`) в защищаемый путь критично всегда, в том числе у команды из белого списка и пустое (`> file`, `: > file`, R5-2).
  - **Широкий и близкий предок.** Широкий предок — корень запуска, `cwd` сессии, `~` и любой их предок: команда с ним критична, только если разрушает, перемещает или подменяет сам этот каталог (правило каталогов-предков выше); запись внутрь ловится сравнением конкретных путей. Поэтому `make`, `make -C .`, `cp -r src dst` в корне не критичны; исключения — распаковка архива и `rsync` с назначением в широком предке, патчи и git-подкоманды, стирающие дерево (ниже). Близкий предок — `<корень сессии или запуска>/.codelab`, `$CODELAB_HOME`, каталог файла `--config` и предки между ними и широкими предками: он в аргументах равен защищаемому пути (`cp -r evil/. ~/.codelab`, `tar -C ~/.codelab`, `unzip -d ~/.codelab`, `find ~/.codelab -delete`, `cd .codelab && git checkout .`).
  - **Маски** (glob `*`, `?`, `[`, brace `{…}`; ревью итерации 5). Раскрытие маски зависит от ФС в момент исполнения, поэтому слово с маской сравнивается по префиксу до первого символа маски: если префикс, разрешённый как путь, лежит внутри защищаемого пути, `<корень сессии или запуска>/.codelab` или `$CODELAB_HOME` либо совпадает с ними, команда не из белого списка критична (fail closed): `rm .codelab/*.yaml`, `cp x ~/.codelab/{agents,prompts}/`, `echo x > ~/.codelab/conf?g.yaml`. Маска, префикс которой короче (`rm -rf .c*` в корне, `rm -rf ~/.c*`), правилом не ловится — Risks «Остаточный обход PERM-11».
  - **Опции записи и исполнения у команд белого списка** (решение оркестратора 2026-11-03 по повторному ревью безопасности итерации 5, fail closed). Команда из белого списка с такой опцией перестаёт быть командой чтения и проверяется как любая другая (защищаемый путь или близкий предок в словах — критична):
    - `jq`/`yq` с `-i`, `--in-place*`, `--inplace*` (правка файла на месте), `-s` или `--split-exp` (у `yq` — запись файлов по выражению; у `jq` `-s` безвреден, но короткие опции двух утилит не различаются — fail closed);
    - `rg`/`ag` с `--pre`, `--pre-glob`, `--search-zip`/`-z` (запуск внешней программы-препроцессора на каждом файле);
    - `less` с `-o`, `-O`, `--log-file` (запись просмотренного в файл журнала) и `file` с `-C`, `--compile` (запись скомпилированной базы `magic`);
    - `git` с глобальными опциями до подкоманды `-c`, `--config-env`, `--exec-path`, `--git-dir`, `--work-tree` (подменяют пейджер, `core.fsmonitor`, `diff.external` и подобное, то есть исполняемую программу, или переносят репозиторий и дерево), а также `git diff` с `--output`, `--ext-diff`, `--textconv` (запись в файл и запуск внешних программ).
  - **Значения опций, которые сами — команды** (решение оркестратора 2026-11-03 по повторному ревью безопасности итерации 5). Значение, которое программа исполняет оболочкой, разбирается как вложенный текст команды — так же, как строка `sh -c`: каждая простая команда в нём проверяется по всем правилам PERM-11 и таблицы §7.6. Это `git -c` (и слитная `-cKEY=…`) с ключами `core.pager`, `core.fsmonitor`, `core.sshCommand`, `core.editor`, `core.askpass`, `core.gitProxy`, `interactive.diffFilter`, `diff.external`, `diff.<драйвер>.textconv|command`, `sequence.editor`, `alias.<имя>=!…`, `credential.helper`, `gpg.*program`, `merge.<драйвер>.driver`, `filter.<имя>.clean|smudge|process`, `pager.<команда>`, `web.browser`, `difftool|mergetool|browser.<имя>.cmd`, `receive.procReceive`; `rg --pre CMD`; `find -exec|-execdir|-ok|-okdir CMD … ;|+`; строка команды лаунчеров `watch [опции] CMD…` и `script -c|--command CMD`. **Переменные окружения с командой** — `GIT_PAGER`, `PAGER`, `GIT_EXTERNAL_DIFF`, `GIT_EDITOR`, `EDITOR`, `VISUAL`, `GIT_SEQUENCE_EDITOR`, `GIT_SSH_COMMAND`, `GIT_SSH`, `GIT_ASKPASS`, `SSH_ASKPASS`, `LESSOPEN`, `LESSCLOSE` — разбираются так же, где бы ни были заданы: префиксное присваивание (`GIT_PAGER='rm …' git log`), `env NAME=…`, а также `export|declare|typeset|readonly|local NAME=…` (действует на следующие команды цепочки: `export GIT_PAGER=…; git log`). Поэтому `git -c core.pager='rm .codelab/config.local.yaml' log` и `find . -exec rm .codelab/config.yaml \;` критичны, хотя защищаемый путь стоит не в словах внешней команды. Критичны **всегда** (fail closed: что исполнится, ядру неизвестно): `git --config-env` (значение ключа — из переменной окружения); `git -c` с `core.hooksPath`, `include.path`, `includeIf.*` (подгружают чужие хуки и конфиг); сегмент, где те же формы присваивания задают `GIT_CONFIG_COUNT`, `GIT_CONFIG_KEY_<n>`, `GIT_CONFIG_VALUE_<n>`, `GIT_CONFIG_PARAMETERS`, `GIT_EXEC_PATH`, `GIT_DIR`, `GIT_WORK_TREE` (окружением задаётся тот же конфиг, что `-c`, или подменяются программы и репозиторий; `ShellSegment.riskyEnvironment` в `shell_lexer.dart`).
  - **Распаковка архива, синхронизация и слияние копированием** (решение оркестратора 2026-11-03, fail closed). Критичны, если приёмник **широкий**: `tar -x`/`tar x` (в том числе `--extract`, `--get`, `-xf`, `xzf`; также `bsdtar`, `gtar`), `unzip` (кроме листинга `-l`/`-t`/`-p`/`-v`/`-Z`), `cpio -i` и `cpio -p`, `7z x|e`, `ditto` (всегда сливает содержимое источника), `jar x…` (распаковывает в каталог запуска), `rsync` и `cp -r|-R|-a` со **слитным источником** — `X/.`, `X/..`, `X/*` (любая маска), `.`, а также `X/` с косой чертой в конце: BSD `cp` (macOS) копирует содержимое такого источника, а не сам каталог. Широкий приёмник — корень запуска и любой его предок (включая `~`: `tar -xf a.tar -C ~` критичен), любой предок защищаемого пути, `<корень>/.codelab` и каталог конфигурации хоста (`~/.codelab`, `$CODELAB_HOME/agents`, `…/prompts`). Приёмник — `-C DIR`/`--directory=DIR` у `tar`, `-d DIR` у `unzip`, `-D DIR` у `cpio -i`, последний позиционный у `cpio -p`, `-oDIR` у `7z`, последний позиционный у `ditto` и `rsync` (значения его опций с аргументом не считаются), назначение `cp` (`-t DIR` или последний аргумент); без опции — каталог запуска команды (после `cd`, `env -C`). Причина: команда создаёт поддерево неизвестного состава, и двухшаговая запись обходит сравнение путей — модель сначала пишет обычный файл `evil/.codelab/config.yaml` (не защищён), затем распаковывает архив с ним, синхронизирует или сливает `evil/` в корень (`cp -r evil/. .`), и `.codelab/config.yaml` появляется без единого защищаемого пути в словах команды. Не критичны: приёмник — обычный подкаталог (`tar -xf a.tar -C build`, `unzip a.zip -d vendor`, `rsync -a src/ dst/`) и `cp -r src .` без слитного источника (кладёт только `./src`, а запись в защищаемый путь ловит сравнение целей).
  - **Патчи** — `git apply`, `git am`, `patch` критичны **всегда**: пути, которые они правят, задаёт содержимое файла патча, а не слова команды.
  - **git-подкоманды, стирающие дерево** (решение оркестратора 2026-11-03 по R5-2) — `git clean` с `-f`/`--force` в любой форме (`-fdx`, `-xdf`), `git reset --hard` (и `--merge`, `--keep` — тоже переписывают дерево; fail closed), `git stash` кроме `git stash list|show` (в том числе голый `git stash`, `push`, `drop`, `clear`, `pop`, `apply`), `git checkout`/`git restore` с путём `.` или другим широким предком (`checkout -- .`, `restore .`, `restore --staged --worktree .`), `git checkout`/`git switch` с `-f`/`--force`/`--discard-changes`, `git checkout-index` с `-a`/`--all` или `-f`/`--force`, `git read-tree -u` — критичны **всегда**, без проверки путей в словах. Причина: ядро не видит ФС и не знает, есть ли в дереве `.codelab`, поэтому корень репозитория считается содержащим его; `git clean -fdx` удалил бы неотслеживаемый `.codelab/config.local.yaml` с записанным `permissions.deny` (R5-2), а `git stash -u` убрал бы его в тайник. Обычные git-команды, меняющие отслеживаемые файлы (`checkout <ветка>`, `merge`, `pull`, `rebase`), не критичны — Risks «Остаточный обход PERM-11».
  - **Файлы политики.** Правила PERM-11 для `exec` (белый список, предки, распаковка, git) — `permissions/agent_config_rules.dart`; разбор аргументов команд (позиционные слова, цели `cp`/`mv`/`ln`/`install`, флаги, подкоманда `git`) — `permissions/command_args.dart`, общий для таблицы §7.6 (`critical_patterns.dart`) и PERM-11: две копии разбора разошлись бы, а расхождение — обход; оба файла внутренние, наружу не экспортируются.
  - **Сопоставление масок политики** — отдельная реализация `permissions/shell_glob.dart`, а не `tools/glob.dart` инструментов поиска: маска сравнивается с **одной компонентой** пути (как в оболочке, `*` не переходит через `/`, `**` не особый), действует правило точки (`*` не совпадает с `.codelab`, маска с явной точкой — совпадает), фигурные скобки со списком (`{a,b}`) раскрываются до сравнения, а нераскрытые (больше 64 вариантов, `{1..3}`) сравниваются по литеральному префиксу, а сломанная маска считается совпадающей — fail closed. Инструментальный glob иного назначения (рекурсивный поиск, `**`, отбор по каталогам), и его семантика ошибалась бы в обе стороны: пропускала бы `rm .c*`-подобные случаи с точкой или ловила бы лишнее; общая функция для двух контрактов связала бы правку поиска с границей безопасности.
  - **Примеры критичных:** `>`/`>>`, `tee`, `cp`, `mv`, `rename`, `ln`/`ln -sf`, `install`, `dd of=`, `sed -i`, `rm`, `unlink`, `truncate`, `yq -i`, `perl -pi`, `curl -o`, `wget -O`, `git checkout|restore -- .codelab/…`, `cp -r evil/. ~/.codelab`, `rsync`, `tar -C ~/.codelab`, `unzip -d ~/.codelab`, `find ~/.codelab -delete`, `cd ~/.codelab && …` с командой не из списка; `tar -xf a.tar` и `rsync -a evil/ .` в корне, `git apply x.patch`, `patch -p1 < x.patch`, `git clean -fdx`, `git reset --hard`, `git stash`, `yq -i`/`yq -s`, `rg --pre`, `git -c core.pager=… log` с защищаемым путём.
  - **Почему не прежний перечень с расширением.** Перечень пишущих команд пришлось бы дополнять после каждой находки, а пропуск — тихий обход без вопроса. Белый список ошибается в безопасную сторону: лишний вопрос человеку вместо пропущенной правки (приоритет 1 корневого `AGENTS.md` §2). Цена — вопросы на `cp <защищаемый> /tmp/…` и подобное чтение не из списка; учтено в выборе широких предков, чтобы обычная работа в корне не спрашивалась.
- чтение не ограничено.

Остаточный риск — в Risks: разбор `exec` не полон, а одобренный человеком `exec` правит файл законно.

**Ошибка перезагрузки не шлёт сообщений** (§17.5.6): вне хода в ACP нет канала для текста агента. Ошибку видно в логе, в `/config check`, в `/config reload` и в `codelab config check`.

**Альтернатива** — пересоздавать рантайм на каждый снимок — отклонена: идущие ходы, сессии и подписки MCP пришлось бы переносить, а ACP-сервер держит рантайм на всё соединение.

### D9. Файлы проекта и команды живой сессии — без перечитывания

§17.5.6, шаги 7b и 7d предлагают перечитывать для живых сессий шаблоны, skills и `AGENTS.md`. В этом change файлы проекта (контекст, шаблоны команд, определения агентов) читаются только при создании и загрузке сессии, как сейчас. Новые `tools.project_context.*` и `prompts.*` действуют для новых сессий; новые `trusted_projects` — только после перезапуска (R0-1, D8), поэтому и шаблоны вновь доверенного проекта появляются лишь после перезапуска.

Почему:
- наблюдатель файлы каталогов `prompts`/`agents` не видит, а перечитывание только по правке `config.yaml` дало бы неочевидное правило «шаблон обновится, если поправить конфиг»;
- список команд сессии остаётся неизменным, кроме встроенных (spec agent-slash-commands «Список команд сессии»), а `available_commands_update` после `session/new` не меняет форму;
- skills ещё нет.

Отступление вносится в §17.5.6 задачей 0.1. Перечитывание живой сессией — вместе со skills (§17.2.4) или отдельным change (OQ7).

### D10. MCP-серверы конфигурации при перезагрузке

Применение — существующей дорогой `McpSessionTools.replaceServers` с полным желаемым списком: новые серверы конфига, затем текущие серверы `session/new`. Отдельного `applyConfigServers` (§17.5.2) нет, потому что `replaceServers` уже делает то же:
- совпавшие по `sameConnection` серверы остаются;
- исчезнувшие и выключенные (`enabled: false`) закрываются;
- новые подключаются и занимают имена инструментов последними (коллизия отключает новый сервер).

Сервер `session/new` с тем же `name` по-прежнему затеняет сервер конфига.

**Когда.** Как у `setMcpServers` (D11 change `add-agent-mcp-client`, spec agent-runtime «MCP-серверы сессии»): без хода — до завершения шага 7a; во время хода — после `TurnEnded`.
- Замены от перезагрузки и от `session/load` идут через одну очередь сессии со счётчиком поколений: последний желаемый набор побеждает, устаревший результат не перекрывает новый.
- Список `session/new` берётся на момент применения, а не на момент перезагрузки.

**Отступление от §17.5.6–§17.5.7.** Там «сразу: подключение и отключение» и «дождаться вызовов в полёте ≤ 10 с, затем отмена».

Почему после хода:
- инструмент, удаляемый посреди пакета вызовов, ломал бы вызов в полёте;
- ожидание «≤ 10 с, затем отмена» — второй механизм рядом с уже проверенной отсрочкой `setMcpServers`;
- ход ограничен бюджетом, а правка списка серверов — не срочная операция.

Неизменённый сервер в `failed` при перезагрузке будится сразу, как сейчас «отключённый или не подключившийся сервер пробуется заново». Это расходится с §17.5.7, п. 5 «идущий backoff не сбрасывается», и тоже вносится в документ (OQ8).

**Новые и изменённые stdio-серверы и HTTP-серверы с подстановками `${…}`** конфига перезагрузкой не применяются (R0-1, R0-4; D8, шаг 5; «ссылка» — по значению: и `${secret:…}`, и `${VAR}`) — в том числе выключенные (R6-1): желаемый список строится из снимка, где такой элемент заменён прежним (или отсутствует). `/mcp enable <id>` работает только с серверами применённого снимка и подключает сервер с его параметрами: отложенный новый сервер — `Unknown MCP server: <id>`, у отложенного изменённого (включённого или выключенного) включается прежний вариант (прежние `command`, `env`, `url`).

**Выключенные серверы конфига** (ревью итерации 0; техрешения итерации 6). До этого change `resolve.dart` выбрасывал элемент с `enabled: false` при загрузке, и до коннектора он не доходил. С этим change `CoreConfig.mcpServers` и `McpConnectRequest.servers` несут и выключенные серверы — `McpServerConfig.enabled` (по умолчанию `true`):
- коннектор держит такой сервер в состоянии `disabled` без подключения, `/mcp list` его показывает (`acp/slash-mcp-list`), инструментов у него нет;
- лог загрузки `mcp.server.skipped {server, reason: disabled in config}` (info) сохраняется;
- **проверка не строже прежней.** Выключенный сервер строится тем же путём, что включённый, но проблемы и предупреждения его построения откатываются: конфиг с неполным или «сломанным» выключенным сервером был валиден и остаётся валидным. Элемент, который не из чего собрать (нет `type` либо `command`/`url` — например, `{name, enabled: false}` проектного слоя поверх сервера пользователя), как и прежде, выпадает из списка; от него остаётся только `mcp.server.skipped`;
- `ConfigLoadResult.values` содержит лист `mcp.servers[<name>]` и у выключенных серверов, попавших в `CoreConfig.mcpServers`: иначе смена `enabled` и правка выключенного сервера не дали бы ключа diff, и R6-1 нечем было бы проверить;
- `McpServerConfig.sameConnection` **не** включает `enabled`: это выбор, нужен ли процесс, а не параметр соединения. Смену признака сравнивают отдельно `replaceServers` (`sameConnection && enabled` равны — сервер тот же) и план перезагрузки (D8, шаг 5);
- `replaceServers`: `enabled` `true` → `false` закрывает сервер, `false` → `true` — новый сервер (для stdio и HTTP с подстановкой — после перезапуска, R0-1, R0-4); правка параметров соединения выключенного stdio-сервера или HTTP-сервера с подстановкой — тоже после перезапуска (R6-1).

**Ручной выбор `/mcp enable|disable` и перезагрузка** (R6-2, решение пользователя 2026-11-03). Выбор человека (`setEnabled`, D11) действует, пока элемент этого сервера в применённом снимке не изменился. «Не изменился» — то же сравнение, по которому `replaceServers` оставляет сервер: параметры соединения (`sameConnection`) и `enabled` прежние, а у сервера, которого человек касался `setEnabled`, ещё и сроки (`connect_timeout`, `call_timeout`). Поэтому:
- правки других ключей и других серверов выбор не сбрасывают: `replaceServers` оставляет сервер как есть, в том числе выключенный `/mcp disable` (он не будится вместе с `failed`) и включённый `/mcp enable` вопреки `enabled: false`;
- правка самого сервера в файле, в том числе `enabled`, даёт новое состояние из конфига: сервер пересоздаётся по элементу применённого снимка (выключенный — `disabled` без `lastError` команды, включённый — подключение);
- отложенная правка (R0-1, R0-4, R6-1) элемент применённого снимка не меняет, поэтому и выбор человека не сбрасывает: включённый `/mcp enable` stdio-сервер, у которого модель поменяла `command` в файле, продолжает работать с прежней командой до перезапуска;
- **сроки** (R6-2, уточнение 2026-11-03; буквальное «элемент изменился»): правка `connect_timeout`/`call_timeout` у сервера с ручным выбором сбрасывает выбор и пересоздаёт соединение (у stdio — перезапуск процесса) — сервер получает состояние из конфига с новыми сроками. У сервера без ручного выбора правка одних сроков соединение не трогает: перезапуск процесса ради срока отнял бы инструменты без причины, а оставленный сервер, как и до этого change, держит прежнее описание до пересоздания.

Альтернатива — сбрасывать ручной выбор на каждой перезагрузке — отклонена: `/mcp disable` шумного сервера отменялся бы любой правкой бюджета или модели, а включённый вручную сервер выключался бы посреди работы. Альтернатива «выбор живёт до конца сессии при любых правках» — отклонена: человек, выключивший сервер в файле, ожидает, что файл победит.

### D11. Переподключение серверов сессии (E-04)

**Где.** В сессии `McpClientConnector` (`codelab_agent_mcp`), которая уже владеет клиентами серверов, а не в новом интерфейсе ядра `McpSupervisor` (§17.5.2). Порт `McpSessionTools` расширяется:

```dart
enum McpServerState { connecting, connected, failed, disabled }
enum McpServerOrigin { config, session }
final class McpServerSummary {
  // Новые поля — с умолчаниями: origin = session, transport = 'stdio',
  // state = connected, lastError = null, retryIn = null.
  final String name; final int toolCount;               // как сейчас; у disabled — 0
  final McpServerOrigin origin; final String transport; // stdio | http
  final McpServerState state;
  final String? lastError;                              // текст кода CodeLab, ≤ 200 символов, без значений
  final Duration? retryIn;                              // только failed с назначенным повтором
}
// McpSessionTools: servers → List<McpServerSummary> (ВСЕ серверы сессии в порядке списка,
//   включая failed и disabled); Future<void> reconnect(String name);
//   Future<void> setEnabled(String name, bool enabled);
// McpConnectRequest: + McpSecretExpander? expandSecrets;
typedef McpSecretExpander = Future<McpServerConfig> Function(McpServerConfig server);
final class McpSecretsException implements Exception { final String reason; }
```

Новые поля `McpServerSummary` получают значения по умолчанию в конструкторе, но новые методы интерфейса `McpSessionTools` требуют правки каждой реализации: `codelab_agent_core/test/mcp/fake_mcp_connector.dart`, `codelab_agent_acp/test/support/server_harness.dart` и `_ConnectedSession` в `codelab_agent_mcp` (задача 6.2). `reconnect` и `setEnabled` нужны командам `/mcp` (D12; OQ1 (а), решение пользователя 2026-11-02). `servers` отдаёт сводку каждого сервера в любом состоянии: таблице `/mcp list` нужны и `failed`, и `disabled`; секция промпта §11.5 по-прежнему говорит о серверах с инструментами.

**`setEnabled`.**
- `setEnabled(name, false)` закрывает транспорт, снимает таймер, состояние `disabled`, `lastError: disabled by /mcp disable`.
- `setEnabled(name, true)` для сервера, выключенного командой или конфигом (`enabled: false`), подключает его в этой сессии с параметрами применённого снимка — тем описанием, которое коннектор получил последним (R6-1: правка соединения выключенного сервера до перезапуска в снимок не попадает). Это действие человека в клиенте, поэтому R0-1 к нему не относится. Конфиг и журнал не меняются; после `session/load` действует конфиг; при перезагрузке выбор держится по R6-2 (D10).
- Сервер, выключенный коллизией имён инструментов, при `enable` подключается заново; повторная коллизия снова даёт `disabled` с `lastError` `tool name collision: <имя инструмента>` (имя после нормализации; полный текст с обоими источниками — в `reason` лога `mcp.server.failed`).
- Неизвестное имя — ничего (команда `/mcp` проверяет имя по `servers` раньше, D12). Сервер, удалённый идущей `replaceServers`, ручными `setEnabled`/`reconnect` во время замены не подключается: коннектор ищет имя в новом списке. Прямые `_McpState.reconnect`/`setEnabled` рантайма в итерации 6 удалены; проведение команд `/mcp` через очередь замен сессии — итерация 7 (задача 7.2).

**Почему не отдельный `McpSupervisor`.** Второй объект на сессию держал бы тот же список клиентов, что и сессия коннектора, и пришлось бы синхронизировать два владельца одного транспорта. Порт `McpSessionTools` уже стоит в точке расширения ядра (§3 (г) `codelab_agent_core/AGENTS.md`). Отступление вносится в §17.5.2 задачей 0.1.

**Автомат** — §17.5.7 (`connecting`, `connected`, `failed`, `disabled`).
- **Сбой.** Выход процесса, закрытие транспорта, HTTP 404 сессии, ошибка или таймаут `initialize`/`tools/list`, неудачное раскрытие секрета → `failed`.
- **Задержка повтора:** `min(30 с, 2^attempt с × (1 + 0.2·r))`, `r ∈ [0, 1)`. `attempt` — число предыдущих сбоев подряд (первая задержка — `2^0`); сбрасывается, только если прошлое соединение прожило ≥ 10 с.
- **Часы и случайность.** Таймер — `Clock.timer`, `Random` — для `r`; оба коннектору передаёт хост (PKG-6): `McpClientConnector(clock:, random:)`. Коннектор не создаёт `Timer` и не читает системные часы. В тестах — `Random(0)` и `FakeClock`.
- **Первое подключение.** Сервер, не подключившийся при `session/new`, тоже переходит в `failed` и пробуется в фоне; ответ `session/new` по-прежнему ждёт только первую попытку (`connectTimeout`).
- **Отмена.** Отмена токена запроса (`McpConnectRequest.cancel`: закрытие сессии или `dispose()` во время подключения или раскрытия секретов) прерывает попытку: транспорт закрыт или не открыт, сервер — `failed` с `lastError: connection cancelled` **без таймера повтора** и без `mcp.server.failed`. Состояние не застревает в `connecting`, а сессии, которой больше нет, нечего повторять.
- **Вызовы.** Инструмент вызывает не клиента MCP, а `McpToolCaller` своего сервера (сервер сам реализует его): так инструменты переживают переподключение и после него идут на новое соединение без пересоздания `McpTool`. Вызов в полёте при падении → `isError: "MCP server <name> disconnected during the call: <reason>"`, без повтора: у вызова могли быть побочные эффекты. Вызов, пока сервер не `connected` после успешного подключения (в простое между попытками или во время попытки) → `isError: "MCP server <name> is not connected (retry in <n>s). Continue without it or try later."` без обращения к транспорту; `n` — секунды до назначенной попытки, округлённые до целого и не меньше 1 (без назначенной попытки — 1). Инструменты упавшего сервера остаются в реестре: смена схем ломала бы кэш префикса и сбивала модель (§17.5.12). Сервер, ни разу не подключившийся, инструментов не имеет.
- **Новый набор инструментов.** После таймерного переподключения набор попадает в реестр только через существующий `takeUpdate()` на границе шага (spec agent-mcp-client «Обновление списка инструментов»); неизменённый набор обновления не даёт. Явные действия, во время которых ход модели не идёт, — начальное подключение, `reconnect`, `setEnabled(true)`, `replaceServers`, — регистрируют инструменты в наборе сессии коннектора сразу, по итогу своей попытки (с проверкой коллизий); реестр сессии ядра получает их ближайшим `takeUpdate()` — до следующего шага или хода.
- **Закрытие.** `close()` сессии и `AgentRuntime.dispose()` отменяют таймеры и идущие подключения; сервер в `connecting` переходит в `failed` с `lastError: connection cancelled` без лога и таймера. Результат подключения, завершившегося после `close()`, закрывается сразу и не регистрируется (счётчик поколений на сервер). Процессов после `close()` не остаётся.
- **Логи.**
  - `mcp.server.state {server, from, to}` (debug) — каждый переход;
  - `mcp.server.failed {server, transport, reason}` (warning) — на 1-м и каждом 10-м подряд сбое (10, 20, …); коллизия имён — тоже `mcp.server.failed` с причиной, называющей оба источника;
  - `mcp.server.retry {server, attempt, delay_ms}` (info) — на остальных; `attempt` — номер сбоя подряд, считая с 1 (поэтому в `retry` он начинается с 2);
  - `mcp.server.connect` — при каждом успехе.

  `mcp.server.failed` сбоев подключения пишет только супервизор сессии: он считает сбои подряд. `McpClient` под коннектором создаётся с `logFailures: false`, иначе каждая попытка давала бы вторую запись. Рантайм ядра пишет `mcp.server.failed` только на исключение `connect` целиком (`MCP connector failed: <runtimeType>`, spec agent-runtime «MCP-серверы сессии»).

  Причины — тексты кода CodeLab (spec agent-mcp-client «Наблюдаемость MCP без секретов»). Поэтому `lastError` не содержит текстов сервера и секретов без `Redactor`; длина обрезается до 200 символов.

**Секреты при переподключении.** Шаблоны `${secret:…}` сервера конфига раскрываются заново перед каждой попыткой: `McpConnectRequest.expandSecrets` — замыкание ядра (`McpSecretExpander`) над `AgentCoreServices.secrets`; после `invalidate` новая попытка берёт новое значение. Коннектор зовёт его только для сервера с непустыми `secretValues` и использует копию только в этой попытке: в `_Server.config` остаются шаблоны. Неудачное раскрытие — `McpSecretsException(reason)` с готовым текстом `secret <name> is not set`, `secret <name> cannot be read: <backend> is unavailable` или `no secret store` (у ядра нет резолвера; имя секрета и бэкенд, без значения) — сбой попытки: состояние `failed`, `lastError` — `reason`, `mcp.server.failed` на первом сбое, дальше — обычная задержка повтора. Сервер с незаданным секретом **остаётся в списке сессии** (`/mcp list` показывает его `failed`), а не выпадает до `connect`, как было до этого change; после `codelab secret set` очередная попытка подключает его без перезагрузки. Это меняет требования agent-runtime «MCP-серверы сессии» (шаг 3, `setMcpServers`) и agent-secrets «Секреты MCP-серверов конфигурации» — дельты MODIFIED в `specs/agent-runtime/spec.md` и `specs/agent-secrets/spec.md`; `createSession`/`loadSession`, прерванные `dispose()` во время раскрытия, завершаются `CancelledException`; реализация — задача 6.4. Раскрытие живёт в ядре, поэтому коннектор получает от ядра замыкание, а не резолвер. Альтернатива — раскрыть один раз и хранить значение в коннекторе — отклонена: замена ключа требовала бы перезапуска, а значение жило бы дольше нужного.

### D12. Встроенные команды `/config` и `/mcp` (OQ1 (а), решение пользователя 2026-11-02)

**Механизм** (минимальный; его расширит change встроенных команд):
- `AgentSession.prompt` до разворачивания шаблонов проверяет первый текстовый блок: `/config` или `/mcp` и пробел или конец строки.
- Команда исполняется без модели. События хода — `TurnStarted`, `MessageStarted`, `MessageDelta` с текстом, `MessageEnded`, `TurnEnded(endTurn)`. Шагов и запросов к модели нет.
- Ответ в журнал не пишется (CFG-18): ни сообщение пользователя, ни ответ, поэтому после `session/load` их нет в реплее.
- Источник `SlashCommandSource.builtin`.
- `/x` для любого другого `x` без шаблона идёт модели, как сейчас (ответ `Unknown command` — change встроенных команд).

**Объявление и порядок.** `AgentSession.commands` начинается со встроенных команд, затем шаблоны в байтовом порядке. Порядок встроенных — §13.4 (`config`, затем `mcp`).
- `{"name":"config","description":"Reload or check the agent config","input":{"hint":"reload | check"}}` — только при `services.config != null` и `buildAgentCore(configCommand: true)` (по умолчанию). `serve --ws` передаёт `configCommand: false` (R0-3): ответ `/config check` содержит пути файлов и тексты проблем машины агента, а держатель токена WebSocket может быть на другой машине. Без объявления `/config` и не исполняется — промпт уходит модели как текст. Перезагрузка по наблюдателю у `serve --ws` работает.
- `{"name":"mcp","description":"List, reload, enable or disable MCP servers","input":{"hint":"list | reload [<id>] | enable <id> | disable <id>"}}` — при включённой capability `mcp` профиля. У `serve --ws` capability `mcp` выключена (§10.4, `agent_host.dart`), поэтому `/mcp` там нет без отдельного правила (R0-3). Если WS когда-нибудь получит `mcp` только с `http`, `/mcp list` можно оставить: таблица не показывает команд, аргументов, `env`, URL и заголовков — только имя, источник, транспорт, состояние, число инструментов и `lastError` из текстов кода CodeLab.

Список сессии не меняется до её закрытия (D9).

**Тексты** — §17.5.6 и §17.5.7, побайтово, английские:
- `/config reload` → `Config reloaded: <n> keys changed.` | `Config unchanged.` | `Config reload failed (<n> issues). Current settings kept. Run /config check.`; при отложенных ключах — строка `Restart required: <k1>, <k2>`;
- `/config check` → первая строка — та же, что последняя строка `config check` CLI: `Config: valid` или `Config: invalid (issues: <n>)`; затем по строке на проблему `- ` + `ConfigIssue.toString()` — `- <source>[:<line>:<column>]: <key>: <message>` (без `<key>: ` при пустом ключе), тот же формат, что у `config check` (§17.5.5), второго формата нет; затем `Sources: …`, `Restart required: …`;
- `/config <другое>` → `Usage: /config reload | /config check`;
- `/mcp list` (и `/mcp`) → таблица §17.5.7 в блоке ```` ```text ````; пустой список — `No MCP servers.`;
- `/mcp reload` → `reloadConfig()`, затем немедленное пробуждение всех `failed`, затем строка итога и таблица. Таблица показывает состояние на момент ответа: серверы конфига применятся после хода (D10), а `/mcp` сам ходом модели не является, поэтому замена происходит до ответа;
- `/mcp reload <id>` → `reconnect`, затем таблица;
- `/mcp enable|disable <id>` → только эта сессия, в памяти, не в конфиге и не в журнале; после `session/load` действует конфиг;
- неизвестный `<id>` → `Unknown MCP server: <id>. Run /mcp list.`;
- другой аргумент → `Usage: /mcp list | /mcp reload [<id>] | /mcp enable <id> | /mcp disable <id>`.

Строки, пришедшие от пользователя (`<id>`, неизвестный аргумент), в ответе обрезаются до 64 символов по рунам; тексты проблем конфига (`ConfigIssue.toString()`) не обрезаются — они те же, что у CLI.

**Слот хода и ход модели** (ревью итерации 0). Это два разных понятия:
- **слот хода** сессии — не больше одного `AgentSession.prompt` одновременно. Встроенная команда занимает слот так же, как ход модели: второй `prompt` во время `/mcp reload` отклоняется тем же путём, что во время хода модели. Правило держит `AgentSession`, а не мост ACP, поэтому оно действует и для встроенного агента, и для `codelab` вне моста;
- **ход модели** — промпт, ушедший в цикл с шагами. Только он откладывает замену серверов конфига до `TurnEnded` (D10). Встроенная команда ходом модели не является: `/mcp reload` занимает слот, но замену не откладывает — замена, которую он вызвал, применяется до ответа. Если к его началу ждала отложенная замена прежней перезагрузки, она уже применена на `TurnEnded` того хода; новая замена `/mcp reload` идёт следующим поколением той же очереди.

Отмена `session/cancel` во время `/config reload` отменяет только ожидание ответа: перезагрузка, начатая рантаймом, доводится до конца (её результат общий), команда отвечает `stopReason: cancelled` без текста и освобождает слот.

**Клиенты.** Клиенты ничего не меняют: команды приходят стандартным `available_commands_update`.
- В REPL и TUI `codelab` клиентская команда `/config` (опции сессии) имеет приоритет, агентская доступна как `/agent:config` (spec codelab-cli «Slash-меню и клиентские команды»); `/mcp` клиентской команды не имеет.
- В codelab-app команды видны в палитре.

**ACP.** Ничего нового: `available_commands_update`, `agent_message_chunk`, `stopReason: end_turn`/`cancelled`. Машиночитаемого статуса MCP по ACP нет (OQ4).

### D13. Хосты

| Хост | `ConfigSource` | `modelsFor` | Примечание |
|---|---|---|---|
| `serve --stdio` | `FileConfigSource(root: канонический cwd процесса, environment, flags)` при `config.watch` (или без наблюдателя) | `createConfiguredStreamFunction` + `StaticModelCatalog` | закрытие источника — после `runtime.dispose()` в остановке процесса |
| `serve --ws` | то же | то же | конфиг правит оператор на машине агента, перезагрузка по наблюдателю работает; `configCommand: false` → `/config` нет (R0-3); capability `mcp` выключена → `/mcp` нет |
| `serve --llm-script` | `null` | — | сценарий детерминирован: перезагрузки и `/config` нет |
| встроенный `embedded-cli`, `embedded-app-desktop` | `FileConfigSource(root: папка проекта)` | как у `serve` | источник создаёт открыватель после успешной загрузки; `EmbeddedAgent.dispose()` закрывает его новым шагом после `runtime.dispose()` (свой `try`, событие `embedded.agent.dispose_failed {step: "config_source"}`) |
| `scriptedEmbeddedAgentOpener` | `null` | — | как `--llm-script` |
| мобильный, web | — | — | нет файловой системы; `applyConfig` — этап 10 |

Каждый хост с источником передаёт и `AgentCoreServices.agentConfigPaths` (D8, PERM-11) из той же функции `agentConfigPathsFor`, что строит список наблюдаемых файлов. Хосты без источника (`--llm-script`, `scriptedEmbeddedAgentOpener`) передают `null`: `$CODELAB_HOME` они не читают, проектные пути по-прежнему защищает список §7.6.1.

Два процесса (`codelab` CLI и codelab-app) со встроенными агентами одного `CODELAB_HOME` наблюдают одни файлы независимо. Запись одного видят оба: каждый перезагружается сам.

### D14. Наблюдаемость

Новые события (§12.3; имена — §17.5.9):

| Событие | Уровень | Поля |
|---|---|---|
| `config.preconfig.shadowed` | info | `by: "flags"` |
| `config.write` | info | `path`, `keys` |
| `config.write.stale_lock` | warning | `path`, `age_ms` |
| `config.watch.debounce` | debug | `path` — событие ФС по наблюдаемому файлу принято и (пере)запустило debounce |
| `config.watch.fallback` | info | `path`, `reason` |
| `config.watch.failed` | warning | `path`, `error_class` |
| `config.reload.applied` | info | `keys`, `restart_required` |
| `config.reload.noop` | debug | — |
| `config.reload.failed` | error | `sources`, `issues` (`source`, `line`, `column`, `key`, `kind`) или `error_class` |
| `config.reload.restart_required` | warning | `keys` (в том числе ключи R0-1) |
| `config.reload.model_orphaned` | info | `session_id`, `model` (`provider/model`) — модель сессии исчезла из каталога, сессия на прежней функции |
| `mcp.server.state` | debug | `session_id`, `server`, `from`, `to` |
| `mcp.server.retry` | info | `session_id`, `server`, `attempt`, `delay_ms` |
| `command.builtin` | info | `session_id`, `name`, `subcommand` (без аргументов) |

Значения ключей, подстановок и секретов не пишутся ни в одно поле; `keys` — пути. `logging.level` в 1.0 — `restartRequired` (OQ5): уровень логгера принадлежит хосту, а канала «хост, примени новые настройки хоста» в ядре нет; такой канал ради одного ключа не вводится.

### D15. Тесты и фикстуры

- **Ядро** (`codelab_agent_core/test/`):
  - `config/settings_registry_complete_test.dart` (E-15);
  - `config/config_edit_test.dart`;
  - `runtime/config_reload_test.dart` — на фейковом `ConfigSource` и `FakeClock`: CFG-15, CFG-16, ключи перезапуска (в том числе R0-1: `permissions.*`, `trusted_projects`, новый и изменённый stdio-сервер), коалесценция, `dispose` во время загрузки, сессия в окне создания, `ModelOptionsChanged`, `config.reload.model_orphaned`, правила `modelsFor`/`streamFunction`;
  - `config/config_load_values_test.dart` — `ConfigLoadResult.values`: пути листьев, `mcp.servers[<name>]`, выключенные серверы с `enabled: false`;
  - `permissions/agent_config_paths_test.dart` — PERM-11 по `agentConfigPaths` (D8): symlink dotfiles, проектный конфиг корня запуска из сессии с другим `cwd`, файл `--config`, `exec` с `mv`/`rename`/`ln -sf`/`install`/`dd of=`/`cd ~/.codelab && …`, пути `~/…`, `$HOME/…`, `${CODELAB_HOME}/…`, `../../.codelab/…`, регистр на ФС без учёта регистра; режимы `bypass` и `autopilot`;
  - `secrets/secret_resolver_test.dart` — `invalidate` и поколения;
  - `runtime/mcp_apply_config_test.dart` — на fake-коннекторе: после хода, последний побеждает, сервер клиента не тронут;
  - `commands/builtin_commands_test.dart` — в том числе параллельный `prompt` во время `/mcp reload` (отклонён), `/mcp reload` после отложенной замены, `configCommand: false`.
- **`codelab_agent_io`:**
  - `config/provider_preconfig_env_test.dart` (L-25);
  - `config/config_writer_test.dart`, `config_writer_atomic_test.dart` — реальные файлы во временных `CODELAB_HOME`/`cwd`, фейковый `SecretProcessRunner` для `chmod`; литеральный секрет через `config set mcp.servers '…'` и `providers.*.headers`; сбой `chmod` → файл цел, tmp удалён; права выставлены до записи содержимого; гонка снятия устаревшего lock; lock снят или отпечаток изменён перед `rename`; ссылка проектного слоя наружу; цепочка ссылок длиннее 32; новый `$CODELAB_HOME` — `0700`;
  - `config/config_watcher_test.dart` — шов потока событий и `FakeClock` (unit), плюс один интеграционный тест настоящего `watch` во временном каталоге с пределом «не позже 5 с»;
  - `config/agent_config_paths_test.dart` — `agentConfigPathsFor`: тот же набор файлов, что у наблюдателя, плюс `agents`, `prompts`; канонизация `~` и symlink;
  - `config/file_config_source_test.dart`;
  - `cli/cli_config_commands_test.dart` — `config`, `provider`, `mcp`, в том числе `--api-key-stdin` на фейковом `SecretInput` и предупреждение о замене существующего секрета;
  - `cli/config_output_test.dart` — маскирование R0-2 по веткам: ключ `inlineSecretKeys`, секретный заголовок и `env` по нормализованному имени, ссылка `${secret:…}`/`${VAR}` как есть, слой `env:*` и предконфигурация → имя источника, userinfo URL, `--layer merged`.
- **`codelab_agent_mcp`:**
  - `test/supervisor/mcp_reconnect_test.dart` — `core/mcp-reconnect-after-crash`: `FakeMcpServer`, `FakeClock`, `Random(0)`;
  - `test/supervisor/mcp_supervisor_state_test.dart`.
- **`codelab_agent_acp`:**
  - `config_reload_notifications_test.dart` — `config_option_update` после перезагрузки, ни одного кадра при неудаче, ACP-8;
  - фикстура `acp/slash-mcp-list`;
  - обновлённая `acp/available-commands-no-tools`.
- **Процессные** (Dart VM, `Timeout(Duration(seconds: 60))`, временные каталоги):
  - `apps/codelab_agent/test/config_reload_process_test.dart` — правка `config.yaml` работающего `serve --stdio` → `config_option_update` не позже 5 с; битая правка → кадров нет;
  - `provider_preconfig_process_test.dart` — в том числе приоритет `--model` над предконфигурацией флагов и флагов над `CODELAB_MODEL`, отказ литерального секретного заголовка;
  - `mcp_reconnect_process_test.dart` — настоящий stdio fake-сервер падает и возвращается, после закрытия сессии процессов нет;
  - `agent_host_ws_commands_test.dart` — у `serve --ws` нет `config` в `available_commands_update`, `/config` уходит модели;
  - `config_write_command_process_test.dart`;
  - `apps/codelab_cli/test/e2e/config_write_command_test.dart` — совпадение вывода `codelab` и `codelab-agent`;
  - `codelab_embedded/test/embedded_config_reload_test.dart` — источник закрыт после `dispose`, процессов и наблюдателей не осталось.
- **Мост:** `codelab_setup/test/config_write_exports_test.dart`.

Задач `[desktop]` нет: `test:e2e:app:*` не запускаются (`AGENTS.md` §21), код desktop не меняется.

### D16. Итерации

Тонкие срезы, каждый — отдельный PR (или 2–3) в `develop`:
- **0** — документы;
- **1** — L-25;
- **2** — реестр и типы правок (E-15);
- **3** — `ConfigWriter`;
- **4** — подкоманды записи у обоих бинарей и мост;
- **5** — живая перезагрузка (ядро, `FileConfigSource`, хосты, `config_option_update`);
- **6** — переподключение MCP и серверы конфига при перезагрузке (E-04);
- **7** — команды `/config`, `/mcp` и фикстуры;
- **8** — матрица, сверка документов, DoD.

Зависимости: 3 ← 2; 4 ← 3; 6 ← 5 (D10); 7 ← 5 и 6. Итерация 1 независима, её можно делать параллельно с 2.

## Risks / Trade-offs

- **[Правка глобального конфига моделью действует сразу]**
  - Риск: до 8.10 правка `$CODELAB_HOME/config.yaml` командой `exec` в режиме `bypass` вступала в силу после перезапуска, а с перезагрузкой — на следующем шаге (например, `permissions.tools: {exec: allow}` или новый MCP-сервер). PERM-11 защищает только `.codelab/config*.yaml` внутри корня сессии.
  - Закрытие: список путей PERM-11 расширяется путями, которые передаёт хост (`agentConfigPaths`: файлы наблюдателя, `$CODELAB_HOME/secrets.yaml` при любом бэкенде (R5-1), `$CODELAB_HOME/agents`, `prompts`; OQ2 (а), D8; задачи 5.9–5.10), а ключи, ослабляющие права, не применяются до перезапуска (R0-1). Остаточный обход — пункт «Остаточный обход PERM-11».
- **[Окно между проверкой `write` и критическим `exec` того же пакета]** → перепроверка защищаемых путей идёт в `beforeToolCall` каждого вызова, но если в одном пакете вызовов `write sub/config.yaml` проверен раньше, чем исполнился одобренный человеком `exec ln -s sub .codelab`, запись пройдёт как обычная правка: путь на момент проверки не был защищаемым. Окно — один пакет и требует одобрения критического `exec`; правка ключей прав и адресов секретов всё равно ждёт перезапуска (R0-1, R0-4). Принято.
- **[Остаточный обход PERM-11]** → защищаемые пути передаёт хост (D8), `write`/`edit` сравниваются после канонизации `BoundedEnv`, а `exec` — по белому списку чтения (R5-4): любая команда не из списка с защищаемым путём или близким предком в аргументах, значениях опций или рабочем каталоге критична, перенаправление в защищаемый путь — всегда. Остаётся то, чего путь в словах команды не видно: интерпретатор со строкой программы (`python -c "open('/home/u/.codelab/config.yaml','w')"`, `node -e`, путь собран из частей или из переменной, кроме `HOME`/`CODELAB_HOME`), скрипт из файла (`python gen.py`, `make` с целью, которая пишет в `~/.codelab`), подстановка команды (`$(…)`, обратные кавычки) и маска с префиксом короче защищаемого пути (`rm -rf .c*`, `rm -rf ~/.c*`; маска, префикс которой лежит в `.codelab` или `~/.codelab`, ловится fail closed). Широкий предок не делает команду критичной, если она не разрушает сам каталог: `find . -delete` в корне запуска удалит и `.codelab/config.local.yaml`, но правилом не ловится (`git clean -f`, `git reset --hard`, `git stash`, распаковка и `rsync` в корень с повторного ревью итерации 5 критичны, D8). Приняты также (решение оркестратора 2026-11-03 по повторному ревью безопасности итерации 5):
  - удалённые команды — `ssh host "…"` (и `ssh localhost`): строка исполняется на другой машине, ядро её не разбирает;
  - `git worktree add`, `git submodule update`, `git cherry-pick`, `git revert` — пишут файлы по содержимому истории, а не по словам команды; не критичны, как и прочие git-подкоманды, меняющие отслеживаемые файлы (ниже);
  - `xargs rm` (и `xargs` с любой пишущей командой) из конвейера: пути приходят из вывода предыдущей команды (`ls ~/.codelab | xargs rm`, `find … | xargs …`), в словах `xargs` их нет;
  - интерпретаторы — строка программы (`python -c`, `node -e`, `perl -e`), скрипт из файла, подстановка `$(…)` и обратные кавычки — и переменные, кроме `HOME`/`CODELAB_HOME` (`$D/config.yaml`, `D=~/.codelab; …`): значение неизвестно ядру;
  - удалённое назначение `rsync` в форме `host:path` (и `user@host:path`): путь на другой машине с правилами назначения не сравнивается — локальная машина с `localhost:~/.codelab` тоже не ловится;
  - `**` без `globstar` (по умолчанию в `bash` и `sh`) — обычная `*` одной компоненты, а с `globstar` раскрывается рекурсивно; правило точки при этом действует, поэтому `**` не входит в точечные каталоги, и сравнение по префиксу ловит маску, только если её префикс уже лежит в `.codelab` или `$CODELAB_HOME`: `rm -rf **/config.yaml` в корне правилом масок не ловится (точечный `.codelab` оболочка тоже не раскроет без `dotglob`, но с `dotglob` — раскроет);
  - ложные срабатывания: путь внутри значения опции, которое путём записи не является, — `rsync -a --exclude=.codelab/config.local.yaml src/ dst/`, `git commit -m .codelab/config.yaml` — делает команду не из белого списка критичной (лишний вопрос человеку, fail closed);
  - git-подкоманды, меняющие отслеживаемые файлы, — `git checkout <ветка>`, `git switch <ветка>`, `merge`, `pull`, `rebase`, `cherry-pick`, `revert` — не критичны, хотя могут переписать закоммиченный `.codelab/config.yaml` содержимым другой ветки: для доверенного проекта это обычная работа с историей, а недоверенный проект и так не читает проектные слои (§15.3).
  В `bypass` и после одобрения человеком такой `exec` проходит. Запись `exec` по существующей ссылке на защищаемый файл (`c.yaml -> .codelab/config.yaml`) к обходу не относится: её ловит второй проход шаблона с канонизацией через `PathResolver` (D8); из ссылочных случаев остаётся только висячая ссылка (R5-3). Смягчение — R0-1: даже записанная правка `permissions.*`, `trusted_projects` и stdio-серверов не применяется до перезапуска, а перезапуск делает человек. Принято.
- **[Висячая ссылка на месте каталога-предка]** (R5-3, решение пользователя 2026-11-03) → в корне запуска нет `.codelab` и нет `sub`; модель вызывает `exec ln -s sub .codelab` — команда критическая как правка каталога-предка (D8) и проходит только с явного одобрения человека, — затем `write sub/config.yaml`. Пересчёт канонической формы защищаемых путей раскрывает ссылки по самому глубокому *существующему* предку, а `.codelab` — висячая ссылка: порт окружения `PathResolver` раскрывает только существующие пути и не умеет читать саму ссылку (`readlink`), поэтому каноническая форма `<root>/.codelab/config.yaml` остаётся прежней, и `write sub/config.yaml` не распознаётся как правка конфигурации (создаёт `sub` и файл в нём как обычная запись). Окно требует одобренного человеком критического `exec`, а ключи прав и адресов секретов всё равно ждут перезапуска (R0-1, R0-4). Известная граница; закрытие — новая capability порта окружения (чтение цели ссылки без её существования) отдельной задачей вне 5.9–5.10. Принято.
- **[Сужение E-04 решениями R0-1 и R0-4]** → правка `permissions.*`, `trusted_projects`, stdio-серверов, HTTP-серверов со ссылками на секреты и полей адреса и аутентификации провайдеров с ключом требует перезапуска; живая перезагрузка остаётся для моделей, провайдеров без ключа, бюджета, сжатия, HTTP-серверов без секретов, удаления и выключения серверов и ключа в `secrets.yaml`. Это осознанная цена защиты в глубину.
- **[Гонка перезагрузки и создания сессии]** → сессия, создаваемая во время замены, получает старый снимок целиком и новую функцию модели с первого хода. Её опции `model` могут разойтись с каталогом до следующей перезагрузки (D8). Окно — миллисекунды, следствие — устаревший список в палитре. Принято.
- **[Шторм событий файловой системы]** → debounce 300 мс, sha256, коалесценция до одного повтора (D7, D8).
- **[Сетевые файловые системы и редакторы с атомарной заменой]** → наблюдение за каталогом, переход на опрос (D7).
- **[Окно до создания источника]** → хост создаёт `FileConfigSource` до сборки ядра, с результатом стартовой загрузки, и база sha256 наблюдателя снимается в конструкторе (`ConfigWatcher.start()`), а не при чтении слоёв. Правка файла между стартовой загрузкой и конструктором не даёт сигнала: агент работает со стартовым снимком до следующей правки или `/config reload`. Окно — от конца стартовой загрузки до конструктора источника (подготовка хоста: секреты, функция модели, пути PERM-11), а не вся сборка ядра; закрыть его можно, только передав наблюдателю отпечатки стартового чтения, что потребовало бы менять `ConfigLoader`. Принято как граница (D7).
- **[Синхронный IO наблюдателя]** (ревью итерации 5) → наблюдатель и загрузчик работают синхронными вызовами: `statSync` на каждом тике опроса, чтение файлов для sha256 и `resolveSymbolicLinksSync` по сигналу, синхронный `ConfigLoader.load`. У встроенного агента они идут в изоляте UI десктопа. Файлы маленькие, тик опроса — раз в `config.poll_interval` (не чаще 1 с), чтение для отпечатка ограничено лимитом размера загрузчика (`maxConfigBytes`; больший файл сравнивается по `(size, mtime)` без чтения, D7), поэтому задержка кадра пренебрежима. Перенос в отдельный изолят — если профилирование десктопа покажет задержки. Принято.
- **[Каталог, созданный после старта]** → файлы отсутствующего при старте каталога (`.codelab/`) остаются на опросе до `close()`: правка видна не позже `config.poll_interval` + 300 мс, а не сразу. Принято (D7).
- **[Падающий по кругу MCP-сервер]** → задержка до 30 с, сброс счётчика только после 10 с жизни, `mcp.server.failed` на 1-м и каждом 10-м сбое. Процесс сервера запускается не чаще раза в 30 с, пока жива сессия; выключить его можно `/mcp disable` или `enabled: false` (D11).
- **[Вызов в полёте при падении сервера]** → `isError` без повтора: побочные эффекты уже могли случиться (D11).
- **[Сервер с незаданным секретом опрашивает хранилище]** → сервер в `failed` повторяет раскрытие по обычному расписанию, то есть не чаще раза в 30 с: одно чтение хранилища на попытку, без запуска процесса и без сети; предупреждение `secrets.backend.unavailable` ограничено одной записью на пару `(backend, reason)` за процесс (agent-secrets «Резолвер секретов»), `mcp.server.failed` — 1-м и каждым 10-м сбоем. Принято: взамен сервер подключается сам после `codelab secret set` (D11).
- **[Ручной выбор переживает отложенную правку]** (R6-2) → включённый `/mcp enable` сервер, у которого в файле изменили `command`, работает с прежней командой до перезапуска: применённый снимок не изменился, и выбор человека в силе. Новая команда не запускается ни перезагрузкой, ни `/mcp enable` (R6-1); `/config` показывает `Restart required: mcp.servers[<name>]`. Принято.
- **[Потерянная правка при одновременной записи]** → lock и отпечаток: второй писатель получает `ConfigConflictException`, CLI повторяет один раз (D5, D6). Ручная правка в редакторе lock не берёт: если редактор сохранит файл между `read` и `rename` писателя, правка писателя перезапишет её. Перепроверка отпечатка перед `rename` (D5, п. 2) сужает окно до одного системного вызова, но не закрывает его. Принято, как у любого `rename`-писателя.
- **[Литеральный токен в заголовке ручной правкой]** → загружается до 8.11; писатель его не пишет (D5).
- **[Смешанное значение секретного заголовка]** → `Bearer sk-литерал ${X}` проходит правило литеральных секретов (D5, «граница смешанных значений»): литерал попадает в файл через CLI или в предконфигурацию без `inlineSecret`. Закрывает 8.11 (редакция секретов, разбор по шаблонам §12.4). Принято (R1-1).
- **[Ключ предконфигурации на адрес доверенного файла]** → предконфигурация сливается с `providers.<id>` доверенных файлов (D3, «Слияние с доверенными файлами»): `base_url` из доверенного файла направит туда ключ из окружения или флагов. Это полномочие доверенного файла — он и так управляет адресом любого своего провайдера; недоверенный проектный слой `providers.*` не задаёт. Принято (R1-2).
- **[Нет fsync каталога]** → при отключении питания теряется последняя правка, повреждённого файла нет (D5).
- **[Дублирование описаний ключей]** → схема и реестр — два описания, которые держит тест полноты (D4). Умолчаний и диапазонов в узлах схемы нет: `min`/`max` сверяются зондом валидатора, умолчания — с разрешённым `CoreConfig` только для применяемых ключей, а умолчания остальных перечислены константой «только по §15.4» и не проверяются ничем, кроме ревью (D4, «Ограничение теста полноты»). Если расхождения начнут чинить вручную, путь — метаданные (умолчание, диапазон) в узлах схемы отдельным рефакторингом вне 8.10.
- **[Фикстуры и палитры клиентов]** → `available_commands_update` у сессий с MCP-capability теперь содержит `mcp`, а при наличии источника конфига — и `config` (D12). Меняются ожидания `acp/available-commands-no-tools`, `acp/prompt-template-command` (`mcp` перед `review`) и сценариев agent-acp-server. Фикстуры этапов 0 и 4 сверяют список через `$any` и не меняются.
- **[Forward compatibility ACP]** → только стандартные уведомления; неизвестных полей и `_meta` агент не шлёт (D12).
- **[Web-безопасность]** → новое в ядре — чистый Dart, `web-compile` в проверках итераций 2, 5, 6, 7.
- **[Allowlist]** → PKG-2 и allowlist пакетов не меняются; `yaml_edit` уже в `ioAllowlist` (D1, D2).
- **[Литеральный токен в `mcp.servers[*].args`]** → `mcp add … --arg --token --arg ghp_x` или `--arg --api-key=X` записывается, а `config get mcp.servers` печатает элемент `args` как есть: аргументы процесса — список строк без имён, правило имён D5 к ним неприменимо, а отличить токен от обычного аргумента можно только эвристикой §12.4. Известная граница до 8.11 вместе с R1-1: редакция секретов по шаблонам закрывает обе. Обход для пользователя — передать токен серверу через `--env K='${secret:…}'`, если сервер читает его из окружения. Принято (R4-6).
- **[Распознавание непрозрачного раздела эвристикой]** → маскирование вывода (D6) считает узел непрозрачным, если его дескриптор — `fileOnly`, тип `map` и `fileOnlyReason` начинается с `not supported in this version`. Смена текста причины в реестре молча откроет поддерево правилу имён. Рекомендация — явный флаг `opaque` на `SettingDescriptor` ядра отдельной задачей после change; до неё текст держит `config_output_test.dart` (ветка непрозрачных поддеревьев).
- **[Объём change]** → девять итераций, каждая — отдельный PR (OQ3 (а)).

## Migration Plan

1. **Итерация 0** — документы (задачи 0.x).
2. **Итерации 1–4** — L-25, реестр, писатель, подкоманды. Работающий агент их не замечает: правки CLI применяются при следующем запуске агента до итерации 5.
3. **Итерация 5** — живая перезагрузка. `config.watch: true` по умолчанию; откат — `config.watch: false` без релиза.
4. **Итерация 6** — переподключение MCP.
5. **Итерация 7** — команды `/config` и `/mcp`.
6. **Итерация 8** — матрица и DoD.

**Откат.** Каждая итерация — отдельный PR. Откат итераций 5–7 возвращает «конфиг читается при старте». Файлы, записанные подкомандами, остаются валидными YAML того же формата. Lock- и tmp-файлы, оставленные аварийно, удаляет следующая запись.

**Совместимость.** Новых обязательных ключей нет. `permissions.*`, `trusted_projects` и новые stdio-серверы по-прежнему действуют только после перезапуска, как до 8.10 (R0-1). `config.watch`/`config.poll_interval`, ранее дававшие `config.key.not_applied`, теперь применяются. Ключ `config` в проектном слое 3 теперь отбрасывается с `config.project.untrusted_key`, а не с `config.key.not_applied`.

## Open Questions

Открытых вопросов нет (OQ9 итерации 6 закрыт уточнением R6-2). Решения пользователя 2026-11-02 (все — по рекомендации):

| Вопрос | Решение | Где учтено |
|---|---|---|
| OQ1 | (а): команды `/config` и `/mcp` входят в этот change, итерация 7 остаётся; минимальный механизм «ответ без модели» — точка расширения change встроенных команд | D11 (`reconnect`, `setEnabled`), D12; agent-slash-commands «Встроенные команды config и mcp»; agent-acp-server «session/new»; acp-golden-fixtures; задачи 6.2, 7.1–7.4 |
| OQ2 | (а): список путей PERM-11 (§7.6.1) расширяется путями `$CODELAB_HOME/config.yaml`, `$CODELAB_HOME/secrets.yaml` и файлом `CODELAB_CONFIG`, которые передаёт хост: `write`/`edit` и `exec` с такой целью — критические в любом режиме, без `allow_always`, отказ без человека | Risks «Правка глобального конфига моделью»; задачи 5.9–5.10 |
| OQ3 | (а): один change, девять итераций, каждая — отдельный PR | D16; tasks.md |
| OQ4 | (а): машиночитаемого статуса MCP по ACP нет; расширение `_meta.codelab`/`_codelab/*` — только отдельным OpenSpec; поток состояний для встроенного агента — change `add-provider-setup-ui` | D12, «ACP»; proposal «Не входит» |
| OQ5 | (а): `logging.level` — только с перезапуском (`restartRequired`), отступление от таблицы §17.5.6 | D8, D14; задача 0.1 |
| OQ6 | (а): флаги `--provider-type` и `--provider-config` у `serve`, сочетание с `--provider`/`--base-url` — ошибка `64` | D3; agent-binary «Флаги предконфигурации провайдера»; задачи 1.3–1.4 |
| OQ7 | (а): файлы проекта читаются только новыми сессиями | D9; agent-slash-commands «Список команд сессии» |
| OQ8 | (а): неизменённый сервер в `failed` при перезагрузке будится сразу, как в `replaceServers` | D10; agent-runtime «Серверы конфигурации при перезагрузке»; задачи 0.1, 6.3 |

Решения пользователя 2026-11-02 по двойному ревью итерации 0:

| Решение | Суть | Где учтено |
|---|---|---|
| R0-1 | ключи, ослабляющие права, — `permissions.*`, `trusted_projects`, новые и изменённые (`command`, `args`, `env`) stdio-серверы `mcp.servers` — `restartRequired`: живая перезагрузка их не применяет, событие `config.reload.restart_required` и строка `Restart required` в `/config`; защита в глубину поверх PERM-11 | D4, D8, D10; agent-runtime «Живая перезагрузка конфигурации»; задачи 2.1, 5.3, 5.4, 6.3 |
| R0-2 | `config get` и `provider list` маскируют значения: `inlineSecretKeys`, секретные заголовки и `env` по нормализованному правилу → `<redacted>`; слои окружения и флаги — имя источника; userinfo URL удаляется; ссылки `${…}` — как есть | D5, D6; agent-configuration «Подкоманды записи и чтения конфига»; задачи 4.1, 4.2 |
| R0-4 | правки, способные направить секрет на другой адрес, — `restartRequired`: новый или изменённый HTTP MCP-сервер с подстановкой `${…}` (`${secret:…}` или `${VAR}` — по значению) в `url`/`headers`/`env`; новый провайдер с ключом и смена `kind`, `base_url`, `headers`, `auth_header`, `api_key_secret`, `api_key_env` у провайдера с ключом; живая перезагрузка остаётся для моделей, HTTP-серверов без секретов, удаления и выключения | D4, D8, D10; agent-runtime «Живая перезагрузка конфигурации»; задачи 5.3, 5.4, 6.3 |
| R0-3 | `/config` не объявляется и не исполняется у `serve --ws` (`configCommand: false`); `/mcp` там отсутствует, потому что capability `mcp` выключена профилем | D12, D13; agent-slash-commands, agent-binary; задачи 5.11, 5.12, 7.1 |

Решения пользователя 2026-11-02 по ревью итерации 1:

| Решение | Суть | Где учтено |
|---|---|---|
| R1-1 | смешанное значение секретного заголовка (`Bearer sk-литерал ${X}`) проходит правило литеральных секретов — известная граница до 8.11 (редакция секретов) | D5, «граница смешанных значений»; Risks «Смешанное значение секретного заголовка» |
| R1-2 | предконфигурация из окружения и флагов сливается с `providers.<id>` доверенных файлов, как любой слой (D3): `base_url` доверенного файла получает ключ предконфигурации — это полномочие доверенного файла | D3, «Слияние с доверенными файлами»; Risks «Ключ предконфигурации на адрес доверенного файла» |

Решения пользователя 2026-11-02 по итерации 3:

| Решение | Суть | Где учтено |
|---|---|---|
| R3-1 | запись блокируют только ошибки загрузки, которых не было до правки (сравнение проблем до и после по сигнатуре `kind|key|source`, без значений и позиции; ревью итерации 3); существовавшие — предупреждения `ConfigWriteResult.warnings`. `config set budget.max_steps 40` и `provider add` без `--default` в пустом `$CODELAB_HOME` проходят с предупреждением `agent.default_model: required`; удаление последнего провайдера, на которого ссылается `agent.default_model`, отклоняется. Литеральные секреты и запрещённые слои блокируют всегда | D5, шаг «Кандидат» (и полная база R3-3); D6, «Вывод успеха»; agent-configuration «Запись конфига ConfigWriter» (сценарии «Невалидный итог не пишется», «Первая запись в пустой конфиг», «Правка не вносит новую ошибку», «Ошибка ранней ступени», «Ранняя ошибка скрывает поздние», «Новая ошибка поздней ступени при ранней»), «Подкоманды записи и чтения конфига» («config set и get»); §17.5.5; задачи 3.5, 3.7 |
| R3-2 | порядок вставки нового ключа — как у `yaml_edit`: в отсортированном отображении — по алфавиту, иначе в конец; новый элемент списка (`mcp.servers`) — в конец; формат и комментарии сохраняются; граница: комментарий над следующим ключом оказывается над новым ключом (ревью итерации 3) | D5, «Порядок вставки»; agent-configuration «Запись конфига ConfigWriter» (сценарий «Порядок нового ключа»); §17.5.5, п. 2 и 4; задачи 3.6, 3.7 |
| R3-3 | (решение пользователя 2026-11-03, дефект R3-1 ручного smoke) база сравнения R3-1 вычисляется полной проверкой исходного текста слоя без обрыва ступеней — набор проблем всех ступеней, включая каскадные; правка блокируется, только если в кандидате есть проблема, которой нет в полном наборе базы. Файл с литеральным `providers.lm.api_key: sk-fake-1` и неверным `base_url` — `config unset providers.lm.api_key` даёт код `0`, `Removed …` и `warning:` для `base_url` и каталога; новая ошибка поздней ступени при имеющейся ранней по-прежнему отклоняется. Обычная загрузка (`config check`, `serve`) не меняется | D5, шаг «Кандидат» («База сравнения — полная проверка исходного текста»); agent-configuration «Запись конфига ConfigWriter» (сценарии «Ошибка ранней ступени», «Ранняя ошибка скрывает поздние», «Новая ошибка поздней ступени при ранней»); §17.5.5, шаг 6 |

Решения пользователя 2026-11-03 по итерации 4:

| Решение | Суть | Где учтено |
|---|---|---|
| R4-1 | `config get` без `--layer` — `merged`; слой `user` по умолчанию — только у записи (`set`, `unset`, `provider add\|remove`, `mcp add\|remove`) | D6, «Слой»; agent-configuration «Подкоманды записи и чтения конфига»; §17.5.5 |
| R4-2 | удаление отсутствующей записи (`config unset`, `provider remove`, `mcp remove`) — код `0` без записи, `<key> is not set in <path>`; `config get` отсутствующего ключа — код `1` | D6, «Отсутствующая запись», «Коды выхода»; agent-configuration (сценарии «Удаление отсутствующей записи», «get отсутствующего ключа»); §17.5.5 |
| R4-3 | `provider add <id>` для существующего провайдера — upsert: переданные флаги перезаписывают поля, остальные сохраняются | D6, «`provider add` — upsert»; agent-configuration (сценарий «provider add обновляет провайдера»); §17.5.5 |
| R4-4 | `provider add` с `--api-key-stdin`, `--api-key-secret` или `--api-key-env` заменяет источник ключа: поля другого источника удаляются; пары `api_key_env` + `api_key_secret` после команды нет | D6, «Флаг ключа заменяет источник ключа»; agent-configuration (сценарий «Флаг ключа заменяет источник ключа»); §17.5.5 |
| R4-5 | маскирование URL (`base_url`, `url`): разбор как URI без userinfo; неразбираемый URL → `<redacted>`; значения query-параметров с секретными именами → `<redacted>`, ссылки `${…}` — как есть | D6, «Маскирование вывода»; agent-configuration (сценарий «Маскирование URL»); §17.5.5 |
| R4-6 | литеральные токены в `mcp.servers[*].args` (`--token X`, `--api-key=X`) — известная граница до 8.11 вместе с R1-1: запись не отказывает, `config get` печатает как есть | Risks «Литеральный токен в `mcp.servers[*].args`»; §17.5.5 |

Решения пользователя 2026-11-03 по итерации 5 (PERM-11, задачи 5.9–5.10):

| Решение | Суть | Где учтено |
|---|---|---|
| R5-1 | `$CODELAB_HOME/secrets.yaml` входит в защищаемые пути конфигурации агента всегда, при любом `secrets.backend`: иначе агент мог бы создать файл и переключить бэкенд следующей правкой. Наблюдение `ConfigWatcher` за `secrets.yaml` — по-прежнему только при `file` (перезагрузка, D7); защищаемых путей не меньше, чем наблюдаемых | D7, «Защищаемые пути»; D8, «Пути конфигурации агента для PERM-11»; Risks «Правка глобального конфига моделью»; agent-permissions «Критические пути правок конфигурации агента» (сценарий «secrets.yaml при другом бэкенде»); §7.6.1; задача 5.10 |
| R5-2 | удаление или усечение самого защищаемого файла — критический шаблон `write to agent configuration`: `rm`, `unlink`, `mv <защищаемый> …`, `truncate`, перенаправление `>`; причина — удаление проектного конфига может снять `permissions.deny` | D8, «удаление и усечение защищаемого файла»; agent-permissions «Критические пути правок конфигурации агента» (сценарий «Удаление и усечение конфигурации»); §7.6.1 |
| R5-4 | белый список чтения для `exec` в PERM-11: команда (в том числе внутри `sh -c`, `env -C`, после `cd`, в цепочках и конвейерах), у которой слово-аргумент, значение опции или рабочий каталог разрешается в защищаемый путь или близкий каталог-предок, критична (`write to agent configuration`), кроме команд только чтения (`cat`, `less`, `more`, `head`, `tail`, `grep`/`egrep`/`fgrep`, `rg`, `ag`, `ls`, `stat`, `file`, `wc`, `diff`, `cmp`, `sha256sum`/`shasum`/`md5sum`, `jq`/`yq` без `-i`, `git diff\|log\|show\|status\|blame`, `test`/`[`, `realpath`, `readlink`, `dirname`, `basename`, `echo`/`printf`); перенаправление в защищаемый путь — всегда; широкий предок (корень запуска, `cwd`, `~`) — только при разрушении, перемещении или подмене самого каталога. Заменяет перечень пишущих команд (он остаётся примерами) и решение «ссылка НА защищаемый файл не критична». Там же (ревью итерации 5): маска с префиксом в защищаемом пути, `.codelab` или `$CODELAB_HOME` — fail closed; резолвер путей политики — env сессии при `PathResolver`, иначе `baseEnv`. Уточнения повторного ревью итерации 5 (решение оркестратора 2026-11-03, fail closed): белый список не действует при опциях записи и исполнения (`jq`/`yq -i`/`-s`, `rg --pre`, `less -o`, `file -C`, глобальные `git -c`/`--git-dir`/…, `git diff --output`); значения опций-команд (`git -c core.pager=…` и другие, `rg --pre`, `find -exec`, `watch`, `script -c`) и переменные с командой (`GIT_PAGER`, `EDITOR`, `LESSOPEN`, … в присваиваниях, `env`, `export`) разбираются как вложенная команда; `git --config-env`, `git -c core.hooksPath|include.path|includeIf.*` и переменные `GIT_CONFIG_*`, `GIT_EXEC_PATH`, `GIT_DIR`, `GIT_WORK_TREE` критичны всегда; `checkout-index -a|-f`, `read-tree -u` критичны; распаковка архива (и `ditto`, `jar x`), `rsync` и `cp -r|-a` со слитным источником (включая BSD `src/`) в широкий приёмник (корень запуска и выше, предок защищаемого пути, каталог конфигурации; по умолчанию каталог запуска) критичны; `git apply`, `git am`, `patch` критичны всегда; git-подкоманды, стирающие дерево (`clean -f`, `reset --hard`, `stash` кроме `list\|show`, `checkout\|restore .`, `--force`/`--discard-changes`), критичны всегда (по R5-2); маски политики — `permissions/shell_glob.dart` | D8, «`exec`: белый список чтения», «резолвер путей политики»; Risks «Остаточный обход PERM-11»; agent-permissions «Критические пути правок конфигурации агента» (сценарии «Белый список чтения — критичные команды», «Белый список чтения — чтение не критично», «Перенаправление критично и у команды чтения», «Широкий предок в аргументах не критичен», «Маска в аргументе», «Резолвер путей в serve», «Ссылка на защищаемый файл», «Опции записи и исполнения у команд чтения», «Значения опций-команд», «Переменные окружения с командой», «Распаковка и синхронизация в корень», «Патчи», «git, стирающий дерево»); §7.6.1; задачи 5.9, 5.10 |
| R5-3 | известная граница: висячая ссылка `ln -s sub .codelab` при несуществующем `sub` (сама команда критична как правка каталога-предка и требует явного одобрения), после чего `write sub/config.yaml` не распознаётся — порт `PathResolver` не раскрывает висячие ссылки (нет `readlink`). Закрытие — новая capability порта окружения отдельной задачей | Risks «Висячая ссылка на месте каталога-предка»; D8, «подмена предка ссылкой»; §7.6.1 |

Там же принято без отдельного номера: ссылка НА защищаемый файл (`ln -s ~/.codelab/config.yaml /tmp/x`) не критична — последующая запись по ней (`write`/`edit` и `exec`) ловится канонизацией цели, если ссылка и цель существуют (заменено R5-4: сама команда `ln -s` теперь критична, канонизация записи по существующей ссылке осталась); каталогом-предком считается любой предок каждой формы защищаемого пути, кроме `/` (консервативно; решение оркестратора): `rm`/`rmdir`/`mkdir` предка и предок-источник `mv`/`ln` критичны всегда, предок-назначение `mv`/`ln` — пока его нет на диске; `rm -rf build`, `mv a .` внутри корня не критичны. Учтено в D8, agent-permissions и §7.6.1.

Решения пользователя 2026-11-03 по итерации 6 (переподключение MCP, D10, D11):

| Решение | Суть | Где учтено |
|---|---|---|
| R6-1 | правка параметров соединения (`command`, `args`, `env`, `type`, `url`, `headers` с подстановкой — всё, что не проходит `sameConnection`) **выключенного** (`enabled: false`) stdio-сервера или HTTP-сервера с подстановкой `${…}` применяется только после перезапуска, как у включённого: иначе модель вписала бы команду в выключенный сервер, а человек включил бы его `/mcp enable`, не видя подмены (обход R0-1). Новый сервер сразу с `enabled: false` — тоже. `/mcp enable` (`setEnabled(true)`) подключает сервер с параметрами применённого снимка. Выключение `true → false` применяется сразу; вместе с правкой соединения — выключение сразу, параметры после перезапуска | D8, шаг 5; D10; D11, `setEnabled`; agent-runtime «Живая перезагрузка конфигурации», «Серверы конфигурации при перезагрузке»; agent-mcp-client «Переподключение и состояние серверов сессии»; задачи 6.3, 6.4 |
| R6-2 | ручной выбор `/mcp enable\|disable` действует, пока элемент этого сервера в применённом снимке не изменился (`sameConnection` и `enabled`); другие правки файла его не сбрасывают; правка самого сервера в файле, в том числе `enabled`, — новое состояние из конфига с учётом R0-1, R0-4 и R6-1; отложенная правка выбор не сбрасывает ; **уточнение** (закрывает OQ9): сервер с ручным выбором остаётся прежним, только если совпали и сроки `connect_timeout`/`call_timeout` — их правка сбрасывает выбор и пересоздаёт соединение (stdio — перезапуск процесса); у сервера без ручного выбора правка одних сроков соединение не сбрасывает | D10, «Ручной выбор»; agent-runtime «Серверы конфигурации при перезагрузке»; задачи 6.3, 6.4 |
