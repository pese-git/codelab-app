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
| `codelab_agent_core` | `config/settings_registry.dart` (D4), `config/config_edit.dart` (D5), `config/config_source.dart` (D7); строки схемы `config.watch`, `config.poll_interval`. Также: `runtime/` — `reloadConfig`, `configStatus`, снимок под замену (D8); `secrets/secret_resolver.dart` — `invalidate` (D8); `mcp/mcp_connector.dart` — состояние сервера в `McpServerSummary`, `reconnect`, `setEnabled` (D11); `commands/builtin_commands.dart` (D12); `host/` — `AgentCoreServices.config`, `AgentCoreServices.agentConfigPaths`, `buildAgentCore(modelsFor:, configCommand:)` (D8, D12); `config/` — `ConfigLoadResult.values`, `McpServerConfig.enabled`, параметр `CoreConfig.fromLayers(pinnedTrustedProjects:)`, `CoreConfig.withDeferred`, `CoreConfig.validateSnapshot` (D8, D10); `permissions/` — пути PERM-11 от хоста (D8); ветка `AgentEvent` `ModelOptionsChanged` (D8); публичный барель экспортирует `nearestKey` из `config/key_path.dart` — подсказка «did you mean» для неизвестного поля предконфигурации (D3); итерация 3 (D5) расширяет публичный API: `configFingerprint` в `config/config_edit.dart` — отпечаток sha256 байтов файла для конфликта; `splitKeyPath`/`KeyPathSegment` из `config/key_path.dart` — единый разбор пути для писателя, `SettingsRegistry.lookup` и маскирования вывода итерации 4; `inlineSecretKeys` перенесён из `config/schema.dart` (не экспортируется, CFG-5) в `config/config_issue.dart` — список нужен писателю и маскированию; у `ConfigIssue` — структурный признак незаданной `${VAR}` (D5, «Кандидат»; ревью итерации 3): писатель и загрузчик не разбирают текст сообщения |
| `codelab_agent_io` | `config/provider_preconfig.dart` — слой предконфигурации L-25, `config/literal_secret_rule.dart` — правило литеральных секретов заголовков (D3, D5); `config/config_writer.dart`, `config/config_write_lock.dart`, `config/yaml_document_edit.dart` (D5, «Где»), `config/config_watcher.dart` и `config/file_config_source.dart` (D7); `ConfigLoader.validateCandidate` → `ConfigCandidateResult` (D5; `loadWithLayers(candidate:)`, на котором он стоит, — внутренний, не публичный API); `ConfigWriteSeam` — шов тестов, в барель не экспортируется; `secrets/secret_process_runner.dart` — `chmodExecutablePath()`, общий у `FileSecretStore` и писателя (вне публичного бареля); `ConfigLoader.load(pinnedTrustedProjects:)` — только передаёт список в `CoreConfig.fromLayers` (D8); `cli/` — новые методы `ConfigCommands`, `ProviderCommands`, `McpServerCommands`, маскирование вывода `config_output.dart` (D6); `config/agent_config_paths.dart` — `agentConfigPathsFor` (D8); `pubspec.yaml` — `yaml_edit` (D2) |
| `codelab_agent_mcp` | супервизия серверов в сессии `McpClientConnector`: автомат, задержки, состояние (D11) |
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
   - **Блокируют только новые ошибки** (R3-1, решение пользователя 2026-11-02). Писатель проверяет тем же методом и исходный текст слоя и сравнивает проблемы до и после правки по сигнатуре `kind|key|source`, без значений, текстов и позиции (ревью итерации 3). Позиции (`line:column`) в сигнатуре нет: вставка выше сдвигает строки, и прежняя ошибка ниже вставки выглядела бы новой. Сравнение — по количеству проблем каждой сигнатуры, а не по множеству: проблемы с пустым ключом (синтаксис, корень документа) не схлопываются в одну, и если после правки проблем с той же сигнатурой стало больше, лишние — новые. Проблема, которой не было до правки, — `ConfigException(issues)` только с новыми проблемами, файл не тронут. Проблема, которая была и до правки, переходит в `ConfigWriteResult.warnings`. Поэтому `config set budget.max_steps 40` и `provider add` без `--default` в пустом `$CODELAB_HOME` проходят с предупреждением `agent.default_model: required`, а `provider remove` последнего провайдера, на которого ссылается `agent.default_model`, отклоняется: ссылка становится новой ошибкой.
   - **Ограничение ступенчатой проверки** (известное, консервативное). Загрузка проверяет конфиг ступенями: ошибки схемы и неизвестные ключи — раньше семантических. Если в исходном файле есть ошибка ранней ступени, семантические ошибки в базовой проверке не видны и после её исправления выглядят новыми. Пример: файл с `bogus_key` и `budget.max_steps: 0` — `config unset bogus_key` отклоняется с проблемой `budget.max_steps`, пока не исправлен `max_steps`. Ограничение блокирует запись, а не пропускает ошибку, поэтому принято; обход — исправить обе проблемы (или сначала семантическую) либо править файл вручную.
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

Это же нормализованное правило имён использует маскирование вывода `config get` и `provider list` (D6, R0-2).

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
| `config get <key> [--layer user\|project\|local\|merged] [--cwd D]` | значение и слой-источник; маскирование R0-2 |
| `config set <key> <value> [--project\|--local] [--cwd D]` | `SetValue`, значение — `SettingsRegistry.parseCliValue` |
| `config unset <key> [--project\|--local] [--cwd D]` | `UnsetValue`: принимает и ключ вне реестра, если он есть в файле (так удаляются опечатки и `api_key`) |
| `provider add <id> --kind K [--base-url U] --model M --context-window N [--api-key-secret S \| --api-key-env V \| --api-key-stdin] [--default] [--project\|--local]` | одна `apply` со списком `SetValue` |
| `provider list [--cwd D]` | маскирование R0-2; `Secrets: <backend>` первой строкой; по строке на провайдера итогового конфига: id, kind, base_url, модели, источник ключа (`secret codelab/x: found\|not set\|unavailable`, `env VAR: set\|not set`) |
| `provider remove <id> [--project\|--local]` | `RemoveTable("providers.<id>")`; ссылка из `agent.*` — `ConfigException` с подсказкой сменить модель |
| `mcp add <name> --type stdio --command C [--arg A]… [--env K=V]… \| --type http --url U [--header K=V]… [--disabled] [--project\|--local]` | `UpsertMcpServer` |
| `mcp list [--cwd D]` | серверы файлов по слоям: name, type, layer, enabled; без подключения |
| `mcp remove <name> [--project\|--local]` | `RemoveMcpServer` |

**Правила:**
- **`get` никогда не раскрывает подстановки.** Печатается сырое значение слоя-победителя (`"${GITHUB_TOKEN}"`, `"Bearer ${secret:…}"`), даже при `--layer merged`. Значение `${VAR}` — содержимое окружения, а оно может быть секретом. Значения ключей `secret: true` — это имена секретов, они печатаются.
- **Маскирование вывода `config get` и `provider list`** (R0-2, решение пользователя 2026-11-02). Подкоманды печатают значения, а файл мог быть правлен руками до 8.11:
  - значение любого листа (на любой глубине, не только в `headers` и `env`), чьё имя — ключ из `inlineSecretKeys` (`api_key`, `token` и др.) или секретное по нормализованному правилу D5, → `<redacted>`, если в нём нет ни `${secret:…}`, ни `${VAR}`; ссылки печатаются как есть;
  - непрозрачное поддерево схемы (`providers.*.auth`, `providers.*.key_rotation`, разделы после MVP) → `<opaque: edit the file>`: схемы его листьев в этой сборке нет, и правило имён не может гарантировать, что секрет не лежит под безобидным именем;
  - значение из слоя окружения (`env:CODELAB_MODEL`, `env:CODELAB_PROVIDER_CONFIG` и другие `env:*`) → имя источника `<from env:CODELAB_PROVIDER_CONFIG>` вместо значения: содержимое переменной могло прийти из секретного хранилища оркестратора; флагов у подкоманд нет, но правило то же (`<from flags>`);
  - URL (`base_url`, `url`) — без userinfo: `https://user:pass@host/v1` → `https://host/v1`;
  - отображение и список маскируются поэлементно; `--layer merged` и слой файла — одинаково.
  Маскирует одна функция `codelab_agent_io` (`cli/config_output.dart`), её используют обе подкоманды.
- **Слой по умолчанию — `user`.** `--project` и `--local` — для `cwd`: `--cwd` подкоманды, иначе общий `-C`/`--cwd` у `codelab`, иначе текущий каталог. Путь канонизирует загрузчик, как у `config check` (D14 change `add-agent-configuration`).
- **Коды выхода:** `0` — успех; `1` — новая ошибка загрузки итога (R3-1), отказ доверия, `inlineSecret`, конфликт после повтора, отказ хранилища секретов; `64` — ошибка использования: неизвестный ключ в `set`, разбор значения, лишние или недостающие аргументы, несовместимые флаги, `provider add` без `--kind`/`--model`/`--context-window`.
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
  Future<ConfigLoadResult> load();
  /// Сигнал «прочитанные файлы изменились» — уже после debounce и сравнения sha256.
  Stream<void> get changes;
}
```

**Реализация** `FileConfigSource` (`codelab_agent_io`) — `ConfigLoader` с параметрами запуска хоста плюс `ConfigWatcher`. Хост создаёт её с результатом стартовой загрузки (`initial`); каждая `load()` вызывает `ConfigLoader.load(..., pinnedTrustedProjects: <initial.config.trustedProjects>)`, а загрузчик передаёт список в `CoreConfig.fromLayers` — доверие вычисляет ядро (D8, «Пересборка снимка»); новое значение ключа попадает только в `values`. `close()` останавливает наблюдение. Владелец источника — хост, который его создал: `AgentHost` или открыватель встроенного агента. Хост закрывает источник после `runtime.dispose()`.

**`ConfigWatcher`** следит за файлами, которые загрузчик читает или прочитал бы:
- `$CODELAB_HOME/config.yaml`;
- файл `--config`/`CODELAB_CONFIG`;
- `<root>/.codelab/config.yaml` и `config.local.yaml`, в том числе ещё не созданные;
- `$CODELAB_HOME/secrets.yaml` — при `secrets.backend: file`.

Последний пункт закрывает ограничение 8.9 «замена прочитанного секрета видна только после перезапуска»: замена ключа даёт перезагрузку без изменений конфига, а она сбрасывает кэш резолвера и пересобирает функцию модели (D8).

Механизм наблюдения:
- **События каталога.** `FileSystemEntity.watch` на родительском каталоге: замена через `rename` — событие каталога.
- **Опрос.** Если каталога нет, `watch` бросает или файловая система без событий — опрос раз в `config.poll_interval` (`2s`, `1s..60s`) по `(exists, mtime, size)`, при смене — sha256.
- **Debounce 300 мс** на часах `Clock` ядра (`FakeClock` в тестах): новые события перезапускают таймер.
- **Сравнение.** Совпадение sha256 всех файлов с последней загрузкой — не изменение.
- **Служебные файлы писателя** (подготовка итерации 5 по ревью итерации 3). `ConfigWriter` создаёт рядом с целью `config.yaml.lock`, `*.lock.stale-*` и `*.tmp-*` — в `$CODELAB_HOME` и в `.codelab/`. События по ним перезагрузку не запускают: наблюдатель отбрасывает их до debounce. Шаблоны имён наблюдатель берёт из констант `config_write_lock.dart` (D5, «Где»), а не держит свои. Запись писателя видна наблюдателю одним событием — итоговым `rename` tmp поверх цели — и даёт один сигнал.

Окружение и флаги не перечитываются: у живого процесса они не меняются.

**Ключи** `config.watch` (`true`) и `config.poll_interval` (`"2s"`) переходят из `afterMvpSections` в схему с потребителем:
- слои `user`, `projectLocal` и `--config`; в проектном слое 3 — отбрасываются с `config.project.untrusted_key` (§17.5.9, таблица доверия); в `config.local.yaml` недоверенного проекта — тоже: пока проект не в `trusted_projects`, слой 4 подчиняется правилам слоя 3 (§15.2);
- `restartRequired`: наблюдатель создаётся один раз;
- `config.watch: false` — `FileConfigSource` без наблюдателя: `changes` никогда не срабатывает, `/config reload` работает.

**Тестируемость.** Поток событий каталога приходит в `ConfigWatcher` через узкий шов — фабрику `Stream<FileSystemEvent> Function(Directory)` (по умолчанию `dir.watch()`); unit-тесты подают события вручную на `FakeClock`, без ожидания настоящей ФС. Один интеграционный тест на временном каталоге проверяет настоящий `watch` с пределом «сигнал не позже 5 с» (D15).

**Защищаемые пути.** Тот же список файлов (плюс каталоги `$CODELAB_HOME/agents` и `$CODELAB_HOME/prompts`) хост передаёт политике разрешений как пути PERM-11 (D8, «Пути конфигурации агента для PERM-11»): что агент перечитывает на лету, то модель не правит без человека.

**Ошибки наблюдателя** не теряются (`AGENTS.md` §12): ошибка потока `watch` переводит файл на опрос и пишет `config.watch.fallback {path, reason: <runtimeType>}` (info). Исключение опроса — `config.watch.failed` (warning), опрос продолжается.

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
Future<ConfigLoadResult> checkConfig();     // /config check: загрузка без применения, по закреплённому доверию из initial
ConfigStatus configStatus();

enum ConfigReloadOutcome { applied, unchanged, failed }
final class ConfigApplyReport {
  final ConfigReloadOutcome outcome;
  final List<ConfigIssue> issues;                       // только failed
  final List<String> changedKeys, restartRequiredKeys;  // листовые пути; mcp.servers — "mcp.servers[<name>]"
}
final class ConfigStatus {
  final DateTime loadedAt; final List<String> sources;
  final DateTime? lastFailureAt; final List<ConfigIssue> lastIssues;
  final List<String> pendingRestartKeys;
}
```

**`modelsFor` и `streamFunction` при сборке** (решение 2026-11-02 по итогам итерации 0). `buildAgentCore` сохраняет `required StreamFunction streamFunction` — функцию модели начального снимка, как сейчас; начальный каталог — по-прежнему `AgentCoreServices.models` (у `CoreConfig` поля каталога нет). `modelsFor` необязателен и вызывается только на снимках, применённых перезагрузкой (шаг 6 алгоритма), при сборке — нет. Правила:
- `services.config != null` и `modelsFor == null` → `HostWiringException`;
- `services.config == null` → `modelsFor` не требуется и не вызывается (`--llm-script`, тесты, хосты без источника);
- хост с источником строит начальную функцию и каталог одним вызовом того же замыкания: `final models = modelsFor(config);` затем `services.models: models.catalog`, `streamFunction: models.stream`, `modelsFor: modelsFor` — одна дорога для старта и перезагрузки.

Альтернатива — `modelsFor(<начальный снимок>)` при сборке и `streamFunction` как взаимоисключающий тестовый шов (`HostWiringException` при обоих) — отклонена: она меняет обязательный параметр, который передают 24 файла хостов и тестов, ради инварианта, который хост соблюдает одной строкой выше; перевод `streamFunction` в тестовый шов — отдельный рефакторинг (§19 корневого `AGENTS.md`).

**`ConfigLoadResult.values` и прежние `HostSettings`** (ревью итерации 0). Шаг 4 сравнивает листья, а у `CoreConfig` и `HostSettings` их нет в общем виде. Поэтому `CoreConfig.fromLayers` дополнительно возвращает плоскую карту листьев итогового дерева `ConfigLoadResult.values` (пути — как у `SettingsRegistry` и `changedKeys`; элемент `mcp.servers` — целиком под `mcp.servers[<name>]`). Это добавление к публичному типу ядра: новое поле с умолчанием `const {}`, существующие вызовы не меняются. Значения в карте — те же, что в файлах (без раскрытия `${…}`); в лог и отчёты попадают только ключи. Рантайм хранит карту и `HostSettings` применённого снимка: ключи хоста `restartRequired`, и их прежние значения подставляются в новый снимок (шаг 5), а `HostSettings` не меняется до перезапуска.

**Почему `modelsFor`, а не пересборка в ядре.** Функцию модели и каталог строит хост: `http.Client` и сервисы LLM — его (PKG-6), `--llm-script` подставляет сценарий. `modelsFor` — замыкание хоста над `createConfiguredStreamFunction(config, llm, secrets:)` и `StaticModelCatalog(config.providers)`; ядро вызывает его на каждом применённом снимке. В отчёте отсутствуют поля `mcpConnected`/`mcpDisconnected`/`mcpReconnected` §17.5.2: серверы применяются после хода (D10), отчёт их ещё не знает. Итог MCP — в логе `mcp.server.*`.

**Алгоритм** (§17.5.6 с уточнениями):
1. **Коалесценция.** Перезагрузка уже идёт → отметить повтор (не больше одного в очереди) и вернуть `Future` повтора. Все вызовы во время идущей получают итог повтора, который видит последние файлы.
2. **Загрузка.** `result := await config.load()`. `dispose()` во время ожидания → результат отбрасывается, ничего не применяется, уведомлений нет. Внутренний `CancelToken` рантайма проверяется после каждого `await`.
3. **Ошибка.**
   - Записать `lastFailureAt` и `lastIssues`.
   - Лог `config.reload.failed {sources, issues: [{source, line, column, key, kind}]}` (error), без значений.
   - Прежний снимок остаётся целиком, клиентам ничего не уходит (CFG-15).
   - Итог — `failed`.
4. **Сравнение.** `diff` — листовые ключи с другим значением; `mcp.servers` сравнивается по `name` и `sameConnection`.
   - **Списки — листья diff** (ревью безопасности итерации 2): `permissions.deny`, `trusted_projects`, `tools.disabled` и любой другой список сравниваются целиком и дают один ключ (`permissions.deny`), без индексов элементов. Развёрнут только `mcp.servers` — по элементам `mcp.servers[<name>]`. Так ключ diff всегда совпадает с путём дескриптора реестра или покрывается им.
5. **Ключи перезапуска.**
   - `restart := diff ∩ {d.restartRequired}` (D4).
   - **Fail closed для ключа вне реестра** (ревью безопасности итерации 2): ключ diff, для которого `SettingsRegistry.lookup` не нашёл дескриптора, считается требующим перезапуска и попадает в `restart`. Расхождение схемы и реестра (тест полноты ловит его при сборке, но не в чужой сборке хоста) не должно превращаться в живое применение ключа, о котором реестр ничего не знает. Тест — в `config_reload_test.dart` (задача 5.3).
   - Отложенные ключи берутся из применённого снимка, и снимок проверяется заново семантически (механизм — «Пересборка снимка с отложенными ключами» ниже). Ошибка — как шаг 3.
   - Непустой `restart` — `pendingRestartKeys ∪= restart`, лог `config.reload.restart_required {keys}` (warning).
   - Ключи хоста (`HostSettings`: `sessions.*`, `logging.*`, `profile.*`) — все `restartRequired` (D14, OQ5).
   - **Ключи, ослабляющие права, — тоже только после перезапуска** (R0-1, решение пользователя 2026-11-02; защита в глубину поверх PERM-11). По схеме этой сборки:
     - `permissions.mode`, `permissions.deny`, `permissions.tools` (весь раздел `permissions.*`; `permissions.timeout` пока не применяется);
     - `trusted_projects`: доверие закреплено в `CoreConfig.fromLayers(pinnedTrustedProjects:)` на стартовом снимке, загрузчик только передаёт список (ниже, «Пересборка снимка»), поэтому новое значение не меняет, какие проектные ключи действуют, — ни при добавлении проекта, ни при снятии доверия;
     - элемент `mcp.servers[<name>]` с `type: stdio` и `enabled`, для которого в прежнем снимке нет элемента `old` с `old.enabled && old.sameConnection(new)` — то есть новый, включённый из `enabled: false`, сменивший тип (`http` → `stdio`) или изменивший `command`, `args`, `env` (в том числе шаблоны `${secret:…}` в `env`, `secretValues`). Удаление и выключение stdio-сервера применяются живой перезагрузкой.
   - **Правки, способные направить секрет на другой адрес, — тоже только после перезапуска** (R0-4, решение пользователя 2026-11-02). «Ссылка на секрет» определяется **по значению, а не по имени**: любая подстановка `${…}` — и `${secret:…}`, и `${VAR}` (значение переменной окружения тоже может быть ключом):
     - элемент `mcp.servers[<name>]` с `type: http` и `enabled`, для которого нет прежнего `old.enabled && old.sameConnection(new)`, если в его `url`, `headers` или `env` есть подстановка `${…}` (`X-Gw: ${secret:gw}`, `Authorization: Bearer ${GITHUB_TOKEN}`);
     - провайдер `providers.<id>` «с ключом» — у которого в прежнем или новом снимке есть `api_key_secret` или `api_key_env`, подстановка `${…}` в `base_url`, `headers` или `auth_header`, или литеральный секретный заголовок по правилу имён D5 (после ручной правки), — если он новый или у него изменилось поле группы адреса и аутентификации: `kind`, `base_url`, `headers`, `auth_header`, `api_key_secret`, `api_key_env`; путь — `providers.<id>`. Группа атомарна: при отложенной правке прежними остаются все её поля, а модели (`providers.<id>.models.*`) — новые;
     - каждая ссылка на модели нового провайдера, исключённого этим правилом: `agent.default_model`; после появления потребителя — `agent.fallback`, `agent.summary_model`, `llm.roles.*`, модели субагентов. Ссылки откладываются вместе с провайдером, поэтому `validateSnapshot` не валит перезагрузку: итог — `applied` (или `unchanged`) со строкой `Restart required`, а не `failed`.
     Живая перезагрузка остаётся для моделей провайдера, провайдеров без ключа, HTTP-серверов без подстановок, удаления и выключения серверов и провайдеров.
     `${…}` в `base_url` тоже делает провайдера «с ключом»: значение переменной может нести токен в query или userinfo. Запрет подстановок в `base_url` схемой отклонён — §17.5.3 и существующие конфиги их допускают (адрес шлюза из окружения), а запрет сломал бы загрузку; правило «с ключом» дешевле и не меняет схему.
     **Обязанность будущих change:** поля провайдера `preset`, `auth`, `key_rotation` (и другие поля адреса или аутентификации) при появлении потребителя входят в группу R0-4 — их change дополняет список и тест.
     Ключи без потребителя в этой сборке (`exec.*`, `tools.untrusted_paths`, `tools.disabled`, `redact.*`, а также `agent.fallback`, `agent.summary_model`, `permissions.timeout` и другие узлы `applied: false`, D4) дают `config.key.not_applied` и перезагрузкой не применяются вовсе. `tools.disabled` в этом списке не случайно: снятие запрета на лету снова включает инструмент, то есть ослабляет ограничение.
     **Обязанность будущих change** (ревью безопасности итерации 2): change, который делает `exec.*`, `tools.disabled` или `redact.*` применяемым (как и любой другой ключ без потребителя), в том же изменении решает его `restartRequired` в реестре (D4), дополняет таблицу «Когда действует новое значение» и константу ключей перезапуска теста полноты. Умолчание «на лету» для такого ключа без явного решения запрещено: ослабление `exec.env`, `redact.*` или снятие `tools.disabled` — изменение границы безопасности.
   - Отложенные ключи попадают в `restartRequiredKeys`, `pendingRestartKeys`, событие `config.reload.restart_required {keys}` и строку `Restart required: …` ответа `/config reload` и `/config check`.

**Пересборка снимка с отложенными ключами** (повторное ревью итерации 0). Механизм — в два звена, каждое там, где есть нужные данные:
1. **Доверие — закреплённый список в ядре.** Доверие вычисляет ядро: `CoreConfig.fromLayers` → `resolveConfig` → `_trustedRoots` (`resolve.dart`). Публичная функция ядра получает новый параметр `CoreConfig.fromLayers(..., pinnedTrustedProjects:)`; при нём по закреплённому списку строятся оба потребителя доверия: оценка проектных слоёв 3–4 (§15.3) и поле `CoreConfig.trustedProjects` полного снимка и `withoutProject`, по которому новая сессия читает `prompts` и `agents` проекта (`agent_runtime.dart`, `project_files.dart`). `ConfigLoader.load(pinnedTrustedProjects:)` лишь передаёт список; `FileConfigSource` берёт его из `initial.config.trustedProjects` на каждой перезагрузке до перезапуска. Новое значение `trusted_projects` попадает только в `values` и через diff — в `pendingRestartKeys`. Почему не подстановкой после загрузки: доверие решает, какие ключи проектных слоёв войдут в дерево, и после `fromLayers` этого уже не восстановить.
2. **Остальные отложенные ключи — в ядре, подстановкой из применённого снимка.** Чистая функция ядра `CoreConfig.withDeferred(CoreConfig previous, CoreConfig next, Set<String> deferredKeys) → CoreConfig` работает только над `CoreConfig` (и его `withoutProject`): `permissions` — целиком прежние; элемент `mcpServers` по имени — прежний элемент, а новый — исключается; провайдер R0-4 — `CatalogProvider` собирается из прежних `config` (адрес, заголовки, `authHeader`), `key` и `headerTemplates` и новых `models`, запись `providerProblems` этого провайдера — прежняя; новый провайдер R0-4 исключается вместе со ссылками на его модели. `HostSettings` и `values` лежат в `ConfigLoadResult`, поэтому их подставляет рантайм сам: прежние `HostSettings`, `values` с прежними значениями отложенных листьев. `checkConfig()` (`/config check`) загружает конфиг тем же путём — по закреплённому доверию из `initial`; новое значение `trusted_projects` и другие отложенные ключи печатаются строкой `Restart required`. Затем `CoreConfig.validateSnapshot` — семантическая проверка (модель по умолчанию есть в каталоге, маршруты); ошибка — как шаг 3.

Альтернативы:
- **Слой-перекрытие `ConfigSource.load(overrides: …)` + `fromLayers`** — отклонён: какие элементы отложить (stdio, R0-4), видно только после сравнения с прежним снимком, то есть понадобилась бы вторая загрузка после diff (два чтения файлов и окно гонки между ними), а слияние `mcp.servers` по `name` не умеет «убрать элемент» без нового маркера в формате слоя.
- **Проектные слои из прежнего снимка** — отклонён: тогда не применялись бы и безопасные проектные ключи (бюджет, модели проекта), а рантайму пришлось бы хранить сырые слои.
6. **Применение.**
   - `secrets?.invalidate()` — всегда, даже при пустом `diff`: значение в хранилище могло смениться.
   - `models := modelsFor(next)` — всегда, по той же причине: цепочки провайдеров держат разрешённый ключ.
   - Атомарная замена снимка, функции модели и каталога.
   - Пустой `diff` и пустой `restart` → лог `config.reload.noop`, итог `unchanged`.
7. **Живые сессии** (созданные до замены и не закрытые):
   - a. серверы конфига — D10;
   - b. новый каталог отличается списком моделей от каталога сессии → событие `ModelOptionsChanged` (новая ветка `AgentEvent`) → адаптер ACP шлёт `config_option_update` с полным снимком опций сессии (§13.6).
8. **Итог.** `lastIssues := []`, лог `config.reload.applied {keys, restart_required}` (info), итог `applied`.

**`SecretResolver.invalidate()`** очищает кэш найденных значений. Поиск, начатый до `invalidate` и завершившийся после, отдаёт значение вызывающему, но в кэш его не кладёт: счётчик поколений не даёт устаревшему значению пережить сброс. Single-flight сохраняется внутри поколения.

**Когда действует новое значение** (CFG-16; ключи схемы этой сборки, остальные — §17.5.6 вместе со своими change):

| Ключи | Когда |
|---|---|
| `providers.*` (включая модели), маршруты | следующий шаг любой сессии: шаг берёт функцию модели в начале. Сессия, чья текущая модель исчезла из каталога, продолжает работать на функции модели прежнего снимка до смены модели; опция `model` показывает её текущей |
| `agent.default_model`, `agent.effort` | новые сессии; модель идущей сессии меняют `/model`, `session/set_config_option` |
| `budget.*`, `compaction.*` | следующий ход |
| `mcp.servers`: HTTP-серверы без ссылок на секреты, удаление и выключение любых серверов | после текущего хода, без хода — сразу (D10) |
| `tools.project_context.*` | новые сессии (файлы проекта фиксируются при создании, D9) |
| `tools.disabled` | не применяется в этой сборке (`config.key.not_applied`); `restartRequired` решит change потребителя (обязанность выше) |
| `redact.*` | не применяется до 8.11 (`config.key.not_applied` как сейчас) |
| `permissions.*`, `trusted_projects`, новые и изменённые stdio-серверы `mcp.servers[<name>]` (R0-1) | только после перезапуска (`restartRequired`): ослабление прав не применяется на лету |
| новые и изменённые HTTP-серверы с подстановкой `${…}` (`${secret:…}` или `${VAR}`), группа полей адреса и аутентификации провайдера с ключом, ссылки на модели нового отложенного провайдера (R0-4) | только после перезапуска: секрет не уходит на новый адрес без перезапуска |
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
- `caseInsensitive` — признак ФС без учёта регистра (macOS, Windows), его определяет хост. Состав — файлы `ConfigWatcher` (D7: `$CODELAB_HOME/config.yaml`, файл `--config`/`CODELAB_CONFIG`, `<корень запуска>/.codelab/config.yaml` и `config.local.yaml`, `$CODELAB_HOME/secrets.yaml`) и каталоги `$CODELAB_HOME/agents`, `$CODELAB_HOME/prompts` (паритет с проектными `.codelab/agents/**`, `.codelab/prompts/**` §7.6.1). Строит его одна функция `codelab_agent_io` (`agentConfigPathsFor(...)`), которой пользуются `AgentHost` и открыватель `codelab_embedded`, — тот же вход, что у `FileConfigSource`, поэтому набор наблюдаемых и защищаемых файлов совпадает по построению. Почему поле `AgentCoreServices`, а не `HostProfile`: пути — данные запуска конкретного процесса, а профиль описывает возможности платформы. Сравнение:
- цель `write`/`edit` берётся после канонизации `BoundedEnv` (тот же результат, что для containment) и сравнивается с путями и префиксами каталогов, без учёта регистра при `caseInsensitive`;
- **подмена предка ссылкой.** Защищаемые пути перепроверяются на каждой проверке `write`/`edit`: их каноническая форма пересчитывается асинхронно в `beforeToolCall` политики тем же вызовом `ExecutionEnv`, которым `BoundedEnv` канонизирует цель для containment (IO — через env хоста), поэтому если `.codelab` стал ссылкой на `sub`, то `write sub/config.yaml` совпадает с защищаемым `<root>/.codelab/config.yaml`. Кроме того, каталоги-предки защищаемых путей (`<корень запуска>/.codelab`, `$CODELAB_HOME`) защищены от создания, переименования, удаления и подмены ссылкой: `exec` с `ln`, `mv`, `rm`, `mkdir` с такой целью — критический;
- **жёсткая ссылка.** `ln` без `-s` и `cp -l`/`cp --link`, у которых защищаемый путь стоит в любой позиции (источник или цель), — критический шаблон: жёсткая ссылка на защищаемый файл из другого места позволила бы править его в обход сравнения путей;
- `exec`: критический шаблон `write to agent configuration` срабатывает, если команда пишет (`>`, `>>`, `tee`, `cp`, `mv`, `rename`, `ln -s`/`ln -sf`, `install`, `dd of=`, `sed -i`) в путь, который после раскрытия `~`, `$HOME`, `${HOME}`, `$CODELAB_HOME`, `${CODELAB_HOME}` и относительно `cwd` команды (включая `../`) совпадает с защищаемым; команда со сменой каталога в защищаемый (`cd ~/.codelab && …`) — тоже критическая;
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

**Новые и изменённые stdio-серверы и HTTP-серверы с подстановками `${…}`** конфига перезагрузкой не применяются (R0-1, R0-4; D8, шаг 5; «ссылка» — по значению: и `${secret:…}`, и `${VAR}`): желаемый список строится из снимка, где такой элемент заменён прежним (или отсутствует). `/mcp enable <id>` работает только с серверами применённого снимка: отложенный новый сервер — `Unknown MCP server: <id>`, у отложенного изменённого включается прежний вариант (прежние `command`, `env`, `url`).

**Выключенные серверы конфига** (ревью итерации 0). Сейчас `resolve.dart` выбрасывает элемент с `enabled: false` при загрузке (лог `mcp.server.skipped`, причина `disabled in config`), и до коннектора он не доходит. С этим change `CoreConfig.mcpServers` и `McpConnectRequest.servers` несут и выключенные серверы — `McpServerConfig.enabled` (по умолчанию `true`):
- коннектор держит такой сервер в состоянии `disabled` без подключения, `/mcp list` его показывает (`acp/slash-mcp-list`), инструментов у него нет;
- лог загрузки `mcp.server.skipped` с причиной `disabled in config` сохраняется;
- `replaceServers`: `enabled` `true` → `false` закрывает сервер, `false` → `true` — новый сервер (для stdio — R0-1, после перезапуска).

### D11. Переподключение серверов сессии (E-04)

**Где.** В сессии `McpClientConnector` (`codelab_agent_mcp`), которая уже владеет клиентами серверов, а не в новом интерфейсе ядра `McpSupervisor` (§17.5.2). Порт `McpSessionTools` расширяется:

```dart
enum McpServerState { connecting, connected, failed, disabled }
enum McpServerOrigin { config, session }
final class McpServerSummary {
  final String name; final int toolCount;               // как сейчас
  final McpServerOrigin origin; final String transport; // stdio | http
  final McpServerState state;
  final String? lastError;                              // текст кода CodeLab, ≤ 200 символов
  final Duration? retryIn;                              // только failed
}
// McpSessionTools: servers → List<McpServerSummary> (все серверы сессии, в порядке списка);
// Future<void> reconnect(String name); Future<void> setEnabled(String name, bool enabled);
```

Новые поля `McpServerSummary` получают значения по умолчанию в конструкторе, но новые методы интерфейса `McpSessionTools` требуют правки каждой реализации: `codelab_agent_core/test/mcp/fake_mcp_connector.dart`, `codelab_agent_acp/test/support/server_harness.dart` и `_ConnectedSession` в `codelab_agent_mcp` (задача 6.2). `reconnect` и `setEnabled` нужны командам `/mcp` (D12; OQ1 (а), решение пользователя 2026-11-02).

**`setEnabled`.**
- `setEnabled(name, false)` закрывает транспорт, снимает таймер, состояние `disabled`, `lastError: disabled by /mcp disable`.
- `setEnabled(name, true)` для сервера, выключенного командой или конфигом (`enabled: false`), подключает его в этой сессии; это действие человека в клиенте, поэтому R0-1 к нему не относится. Конфиг и журнал не меняются; после `session/load` действует конфиг.
- Сервер, выключенный коллизией имён инструментов, при `enable` подключается заново; повторная коллизия снова даёт `disabled` с `lastError` `tool name collision: <name>`.

**Почему не отдельный `McpSupervisor`.** Второй объект на сессию держал бы тот же список клиентов, что и сессия коннектора, и пришлось бы синхронизировать два владельца одного транспорта. Порт `McpSessionTools` уже стоит в точке расширения ядра (§3 (г) `codelab_agent_core/AGENTS.md`). Отступление вносится в §17.5.2 задачей 0.1.

**Автомат** — §17.5.7 (`connecting`, `connected`, `failed`, `disabled`).
- **Сбой.** Выход процесса, закрытие транспорта, HTTP 404 сессии, ошибка или таймаут `initialize`/`tools/list` → `failed`.
- **Задержка повтора:** `min(30 с, 2^attempt с × (1 + 0.2·r))`, `r ∈ [0, 1)`. `attempt` сбрасывается, только если прошлое соединение прожило ≥ 10 с.
- **Часы и случайность.** Таймер — `Clock.timer` (PKG-6). `Random` приходит параметром `McpClientConnector` от хоста; в тестах — `Random(0)` и `FakeClock`.
- **Первое подключение.** Сервер, не подключившийся при `session/new`, тоже переходит в `failed` и пробуется в фоне; ответ `session/new` по-прежнему ждёт только первую попытку (`connectTimeout`).
- **Вызовы.** Вызов в полёте при падении → `isError: "MCP server <name> disconnected during the call: <reason>"`, без повтора: у вызова могли быть побочные эффекты. Вызов, пока сервер `failed` после успешного подключения → `isError: "MCP server <name> is not connected (retry in <n>s). Continue without it or try later."`. Инструменты упавшего сервера остаются в реестре: смена схем ломала бы кэш префикса и сбивала модель (§17.5.12). Сервер, ни разу не подключившийся, инструментов не имеет.
- **Новый набор инструментов** после переподключения попадает в реестр через существующий `takeUpdate()` на границе шага (spec agent-mcp-client «Обновление списка инструментов»).
- **Закрытие.** `close()` сессии и `AgentRuntime.dispose()` отменяют таймеры и идущие подключения. Результат подключения, завершившегося после `close()`, закрывается сразу и не регистрируется (счётчик поколений на сервер). Процессов после `close()` не остаётся.
- **Логи.**
  - `mcp.server.state {server, from, to}` (debug);
  - `mcp.server.failed` (warning) — на 1-м и каждом 10-м подряд сбое;
  - `mcp.server.retry {server, attempt, delay_ms}` (info) — на остальных;
  - `mcp.server.connect` — при каждом успехе.

  Причины — тексты кода CodeLab (spec agent-mcp-client «Наблюдаемость MCP без секретов»). Поэтому `lastError` не содержит текстов сервера и секретов без `Redactor`.

**Секреты при переподключении.** Шаблоны `${secret:…}` сервера конфига раскрываются заново перед каждой попыткой через `AgentCoreServices.secrets`: после `invalidate` новая попытка берёт новое значение. Неудачное раскрытие (`SecretMissing`, `SecretUnavailable`) — сбой попытки: состояние `failed`, `lastError` `secret <name> is not set` или `secret <name> cannot be read: <backend> is unavailable` (имя секрета, без значения), дальше — обычная задержка повтора. Раскрытие живёт в ядре (`_expandMcpSecrets`), поэтому коннектор получает от ядра замыкание раскрытия на сервер. Альтернатива — раскрыть один раз и хранить значение в коннекторе — отклонена: замена ключа требовала бы перезапуска, а значение жило бы дольше нужного.

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
  - Закрытие: список путей PERM-11 расширяется путями, которые передаёт хост (`agentConfigPaths`: файлы наблюдателя, `$CODELAB_HOME/agents`, `prompts`; OQ2 (а), D8; задачи 5.9–5.10), а ключи, ослабляющие права, не применяются до перезапуска (R0-1). Остаточный обход — пункт «Остаточный обход PERM-11».
- **[Окно между проверкой `write` и критическим `exec` того же пакета]** → перепроверка защищаемых путей идёт в `beforeToolCall` каждого вызова, но если в одном пакете вызовов `write sub/config.yaml` проверен раньше, чем исполнился одобренный человеком `exec ln -s sub .codelab`, запись пройдёт как обычная правка: путь на момент проверки не был защищаемым. Окно — один пакет и требует одобрения критического `exec`; правка ключей прав и адресов секретов всё равно ждёт перезапуска (R0-1, R0-4). Принято.
- **[Остаточный обход PERM-11]** → защищаемые пути передаёт хост (D8), `write`/`edit` сравниваются после канонизации `BoundedEnv`, а `exec` — по шаблонам записи. Разбор `exec` не полон: интерпретатор (`python -c`, `node -e`) или составная команда могут записать файл, не совпав с шаблоном; в `bypass` и после одобрения человеком такой `exec` проходит. Смягчение — R0-1: даже записанная правка `permissions.*`, `trusted_projects` и stdio-серверов не применяется до перезапуска, а перезапуск делает человек. Принято.
- **[Сужение E-04 решениями R0-1 и R0-4]** → правка `permissions.*`, `trusted_projects`, stdio-серверов, HTTP-серверов со ссылками на секреты и полей адреса и аутентификации провайдеров с ключом требует перезапуска; живая перезагрузка остаётся для моделей, провайдеров без ключа, бюджета, сжатия, HTTP-серверов без секретов, удаления и выключения серверов и ключа в `secrets.yaml`. Это осознанная цена защиты в глубину.
- **[Гонка перезагрузки и создания сессии]** → сессия, создаваемая во время замены, получает старый снимок целиком и новую функцию модели с первого хода. Её опции `model` могут разойтись с каталогом до следующей перезагрузки (D8). Окно — миллисекунды, следствие — устаревший список в палитре. Принято.
- **[Шторм событий файловой системы]** → debounce 300 мс, sha256, коалесценция до одного повтора (D7, D8).
- **[Сетевые файловые системы и редакторы с атомарной заменой]** → наблюдение за каталогом, переход на опрос (D7).
- **[Падающий по кругу MCP-сервер]** → задержка до 30 с, сброс счётчика только после 10 с жизни, `mcp.server.failed` на 1-м и каждом 10-м сбое. Процесс сервера запускается не чаще раза в 30 с, пока жива сессия; выключить его можно `/mcp disable` или `enabled: false` (D11).
- **[Вызов в полёте при падении сервера]** → `isError` без повтора: побочные эффекты уже могли случиться (D11).
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

Открытых вопросов нет. Решения пользователя 2026-11-02 (все — по рекомендации):

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
| R3-1 | запись блокируют только ошибки загрузки, которых не было до правки (сравнение проблем до и после по сигнатуре `kind|key|source`, без значений и позиции; ревью итерации 3); существовавшие — предупреждения `ConfigWriteResult.warnings`. `config set budget.max_steps 40` и `provider add` без `--default` в пустом `$CODELAB_HOME` проходят с предупреждением `agent.default_model: required`; удаление последнего провайдера, на которого ссылается `agent.default_model`, отклоняется. Литеральные секреты и запрещённые слои блокируют всегда | D5, шаг «Кандидат» (и ограничение ступенчатой проверки); D6, «Вывод успеха»; agent-configuration «Запись конфига ConfigWriter» (сценарии «Невалидный итог не пишется», «Первая запись в пустой конфиг», «Правка не вносит новую ошибку», «Ошибка ранней ступени»), «Подкоманды записи и чтения конфига» («config set и get»); §17.5.5; задачи 3.5, 3.7 |
| R3-2 | порядок вставки нового ключа — как у `yaml_edit`: в отсортированном отображении — по алфавиту, иначе в конец; новый элемент списка (`mcp.servers`) — в конец; формат и комментарии сохраняются; граница: комментарий над следующим ключом оказывается над новым ключом (ревью итерации 3) | D5, «Порядок вставки»; agent-configuration «Запись конфига ConfigWriter» (сценарий «Порядок нового ключа»); §17.5.5, п. 2 и 4; задачи 3.6, 3.7 |
