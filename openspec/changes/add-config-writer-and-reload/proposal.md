## Why

После этапа 8.5–8.9 конфиг агента читается **один раз** при старте, а правится **только руками** в YAML (`09-13-stage-8-mcp-config.md`, задача 8.10). Отсюда четыре пробела:

- **Контейнер и CI.** Без файла конфига провайдера задают только флаги `--provider`/`--base-url` бинаря; встроенный агент и `config check` их не видят. Цель L-25 — провайдер из двух переменных окружения.
- **Одни настройки в двух клиентах.** `codelab config set`, `provider add`, `mcp add` не зарегистрированы (`Unknown command config set`, код `64`), а у клиентов нет описания ключей для страницы настроек. Цель E-15 — реестр настроек с тестом полноты.
- **Без перезапуска.** Правка конфига, новый ключ в `secrets.yaml` (ограничение 8.9, D15 change `add-agent-secret-store`) и смена списка MCP-серверов доходят до работающего агента — `serve`, встроенного в `codelab` и в codelab-app — только после перезапуска. Упавший MCP-сервер не возвращается до конца сессии. Цель E-04 — перечитывание конфига и переподключение MCP.
- **Видимость.** Человек в клиенте не видит ни состояния MCP-серверов, ни того, что ручная правка конфига не применилась (агентская часть E-13: команды `/mcp` и `/config`).

Задача 8.10 — **Should, MVP не блокирует** (этап 7 её не ждёт). Алгоритмы — `agent-core-architecture` §17.5.3, §17.5.5–§17.5.8, критерии — §17.5.13 и строки матрицы L-25, E-04, E-15.

## What Changes

- **Предконфигурация провайдера из окружения (L-25).** `CODELAB_PROVIDER_TYPE` и `CODELAB_PROVIDER_CONFIG` (или `CODELAB_PROVIDER_CONFIG_BASE64`) дают провайдера `providers.<id>` и `agent.default_model` без файла. Это часть слоя окружения `ConfigLoader`, поэтому её одинаково видят `serve`, встроенный агент и `config check`. У `serve` есть флаги `--provider-type` и `--provider-config <json | @путь>`; они затеняют переменные. Ошибка называет переменную и поле, но не цитирует значение. Ключ API значением в JSON — `inlineSecret` (CFG-9).
- **Реестр настроек (E-15).** `SettingsRegistry` в ядре (чистый Dart) — `SettingDescriptor` на каждый ключ схемы: тип, умолчание, `shared`/`fileOnly` с причиной, `restartRequired`, допустимые слои. Тест полноты падает на ключе схемы без дескриптора (CFG-19).
- **Типы правок в ядре.** `ConfigLayer`, `ConfigTarget`, `ConfigSnapshot`, `ConfigEdit` (`SetValue`, `UnsetValue`, `UpsertMcpServer`, `RemoveMcpServer`, `RemoveTable`), `ConfigConflictException`.
- **Запись конфига (`ConfigWriter`, `codelab_agent_io`).** Правка через `YamlEditor` из `package:yaml_edit`: комментарии, порядок ключей, стиль и перевод строк вне изменённых узлов сохраняются побайтово. Перед заменой итог проходит ту же проверку, что загрузка. Соблюдаются правило доверия проекту, допустимые слои ключа и отпечаток файла (защита от затирания ручной правки). Замена атомарная: lock-файл и tmp в том же каталоге, затем `rename`. Права исходного файла сохраняются, символическая ссылка остаётся ссылкой. Секрет значением не записывается никогда (CFG-9, CFG-13).
- **Маскирование вывода (R0-2).** `config get` и `provider list` печатают `<redacted>` вместо литеральных секретов (ключи `inlineSecretKeys`, секретные заголовки и `env`), имя источника вместо значений из окружения и URL без userinfo; ссылки `${…}` — как есть.
- **Подкоманды записи и чтения у обоих бинарей:** `config path|get|set|unset`, `provider add|list|remove`, `mcp add|list|remove`. Это одна реализация в `codelab_agent_io`, `codelab` вызывает её через `codelab_setup/io.dart`, поэтому вывод и коды выхода `codelab-agent` и `codelab` совпадают (`0`/`1`/`64`). `provider add --api-key-stdin` сначала сохраняет ключ через `SecretAdmin`, в конфиг попадает только имя секрета.
- **Живая перезагрузка (E-04).** Порт ядра `ConfigSource` и его реализация `FileConfigSource` в `codelab_agent_io`: `ConfigLoader` и `ConfigWatcher` (события каталога или опрос, debounce 300 мс, сравнение sha256). Ключи `config.watch` и `config.poll_interval` начинают применяться. `AgentRuntime.reloadConfig()`:
  - невалидный конфиг — прежний снимок остаётся целиком, клиентам ничего не уходит, ошибка видна в логе и в `/config check` (CFG-15);
  - валидный — снимок заменяется атомарно, новые значения действуют на границах: следующий шаг, вызов инструмента, ход или новая сессия (CFG-16);
  - ключи, требующие перезапуска, не применяются и перечисляются; к ним относятся и ключи, ослабляющие права, — `permissions.*`, `trusted_projects`, новые и изменённые stdio-серверы MCP (R0-1, защита в глубину поверх PERM-11), а также правки, способные направить секрет на другой адрес, — HTTP-серверы с подстановкой `${…}` и группа полей адреса и аутентификации провайдера с ключом (R0-4); доверие проектам закреплено на стартовом снимке;
  - функция модели и каталог пересобираются, кэш секретов сбрасывается (`SecretResolver.invalidate`);
  - смена списка моделей даёт `config_option_update`.

  Работает у `serve --stdio`, `serve --ws` и встроенного агента codelab и codelab-app; со сценарием `--llm-script` перезагрузки нет.
- **PERM-11 для глобальных файлов (OQ2).** Хост передаёт политике канонические пути конфигурации агента — те же файлы, что наблюдает `ConfigWatcher`, плюс `$CODELAB_HOME/agents` и `prompts`; правка их моделью критическая в любом режиме, в том числе через `exec`.
- **Переподключение MCP (E-04).** Сессия коннектора `codelab_agent_mcp` ведёт каждый сервер — и из конфига, и из `session/new` — по автомату `connecting → connected → failed → connecting`, плюс `disabled`. Повторы идут с задержкой 1…30 с, экспонента с джиттером, на часах и случайности хоста (PKG-6). Вызов в полёте при падении сервера — `isError` без повтора. Инструменты упавшего сервера остаются в реестре и отвечают `not connected`. Перезагрузка трогает только изменившиеся серверы конфига, кроме неизменённого сервера в `failed`: его она будит сразу (OQ8, D10); серверы `session/new` она не трогает никогда (CFG-17).
- **Агентские команды `/config reload|check` и `/mcp list|reload [<id>]|enable <id>|disable <id>`** (OQ1 — решение пользователя 2026-11-02: включить). Ответ — фиксированный английский текст `agent_message_chunk` и `stopReason: end_turn`, без модели и без записи в журнал (CFG-18). Команды объявляются стандартным `available_commands_update`. По WebSocket (`serve --ws`) `/config` не объявляется (R0-3), а `/mcp` там нет, потому что capability `mcp` выключена. Минимальный механизм «ответ агента без модели» становится точкой расширения для change встроенных команд.

## Не входит

- мастер провайдера, страницы настроек провайдеров и MCP-серверов в app, `/settings` в CLI, порт `AgentConfigStore`/`FileAgentConfigStore`, реэкспорт `ConfigEdit`/`SettingsRegistry` в основном бареле `codelab_setup` — change `add-provider-setup-ui` (`dart-agent-and-clients` §12.4); `codelab provider add` без флагов здесь — ошибка использования `64`, мастер на TTY добавит тот change;
- машиночитаемый статус MCP-серверов по ACP, поток `McpSupervisor.changes` для страницы настроек встроенного агента — вместе с потребителем (OQ4);
- остальные встроенные команды (`/status`, `/help`, `/compact`, `/mode`, `/model` и другие), ответ `Unknown command`, MCP prompts как команды — change встроенных команд (решение пользователя 2026-10-30, OQ1 change `add-agent-project-files`); строки `Config:` в `/status` — там же;
- перечитывание файлов проекта (`AGENTS.md`, шаблоны команд, определения агентов) живой сессией: в этом change новые значения действуют для новых сессий (D9);
- снимок конфига на каждый `cwd` сессии: модель «корень запуска + снимок без проекта» (D9 change `add-agent-configuration`) сохраняется (D8);
- `applyConfig` для мобильного и web-хостов, хранилище конфига в приложении — этап 10;
- `config export-providers`/`import-providers` (§17.14.4), `config migrate` (её нет: `codelab.toml` не читается);
- запись конфига удалённого агента по WebSocket (CFG-14) — клиенты его не пишут;
- распознавание литеральных секретов по шаблонам §12.4 (пункты 2–3 CFG-9) — 8.11; здесь только правило имён ключей и проверка секретных заголовков и `env` по нормализованному имени в итоговом поддереве записи (D5);
- изменения ACP: новых методов, полей, `_meta` и значений перечислений нет. Используются стандартные `available_commands_update`, `config_option_update`, `agent_message_chunk`.

## Capabilities

### New Capabilities
Нет.

### Modified Capabilities
- `agent-configuration`: предконфигурация провайдера из окружения; реестр настроек; запись конфига `ConfigWriter`; подкоманды `config path|get|set|unset`, `provider`, `mcp`; ключи `config.watch` и `config.poll_interval`; наблюдение за файлами.
- `agent-runtime`: живая перезагрузка конфигурации (`ConfigSource`, `reloadConfig`, границы применения, ключи перезапуска, гонки и отмена).
- `agent-permissions`: критические пути правок конфигурации агента дополняются путями, которые передаёт хост (`$CODELAB_HOME/config.yaml`, `secrets.yaml`, файл `CODELAB_CONFIG`, проектный конфиг корня запуска, `$CODELAB_HOME/agents`, `prompts`), с канонизацией и шаблонами `exec`.
- `agent-mcp-client`: переподключение и состояние серверов сессии.
- `agent-secrets`: сброс кэша резолвера при перезагрузке (`invalidate`).
- `agent-slash-commands`: встроенные команды `config` и `mcp`; список команд сессии начинается со встроенных.
- `agent-acp-server`: уведомления после перезагрузки; `session/new` объявляет встроенные команды.
- `agent-binary`: флаги предконфигурации, перезагрузка в `serve`, подкоманды записи `codelab-agent config|provider|mcp`.
- `codelab-cli`: подкоманды записи `codelab config`, `codelab provider`, `codelab mcp`.
- `embedded-agent`: перезагрузка встроенного агента и закрытие наблюдателя в `dispose`.
- `acp-golden-fixtures`: фикстура `acp/slash-mcp-list`; ожидаемые списки команд `acp/available-commands-no-tools` и `acp/prompt-template-command`.

## Impact

- **Пакеты** (раскладка — design.md, D1):
  - `codelab_agent_core`: `config/` — `settings_registry.dart`, `config_edit.dart`, `config_source.dart`, строки схемы `config.*`; `runtime/` — `reloadConfig`, `configStatus`, снимок под замену; `secrets/secret_resolver.dart` — `invalidate`; `mcp/mcp_connector.dart` — состояние сервера в сводке, `reconnect`/`setEnabled`; `commands/` — встроенные `config` и `mcp`; `host/` — `AgentCoreServices.config`, параметр `buildAgentCore(modelsFor:)`.
  - `codelab_agent_io`: `config/config_writer.dart`, `config_watcher.dart`, `file_config_source.dart`, `environment_layer.dart` (L-25); `cli/` — `ConfigCommands` (`path`, `get`, `set`, `unset`), `ProviderCommands`, `McpServerCommands`; `pubspec.yaml` — прямая зависимость `yaml_edit` (уже в allowlist `ioAllowlist`).
  - `codelab_agent_mcp`: супервизия серверов в сессии коннектора, задержки повторов.
  - `codelab_agent_acp`: уведомления сессий после перезагрузки, кадры встроенных команд.
  - `codelab_embedded`: `FileConfigSource` встроенного агента, закрытие в `dispose`.
  - `codelab_setup`: `lib/io.dart` реэкспортирует новые подкоманды.
  - `apps/codelab_agent`: флаги `--provider-type`, `--provider-config`, подкоманды `config|provider|mcp`, наблюдатель в `AgentHost`.
  - `apps/codelab_cli`: подкоманды `config|provider|mcp` в `cli_args.dart` и `run.dart`.
  - `apps/codelab_desktop` не меняется: встроенный агент получает перезагрузку через `codelab_embedded`.
- **Зависимости и сторож.** PKG-2 и allowlist зависимостей не меняются: `yaml_edit` уже утверждён (D2 change `add-agent-configuration`) и стоит в `ioAllowlist`. Правила `rules.dart` прежние, граф `README.md` прежний (D1).
- **Public API ядра** — только добавления, используемые сигнатуры не меняются: `McpServerSummary` получает поля с умолчаниями, `ConfigLoadResult` — поле `values`, `McpServerConfig` — `enabled`, `AgentCoreServices` — `config` и `agentConfigPaths`, `buildAgentCore` — необязательные `modelsFor` и `configCommand` (D8, D10–D12). Исключение — интерфейс `McpSessionTools` получает методы `reconnect` и `setEnabled`: его реализации, в том числе фейки тестов, правятся (D11).
- **Пользовательские данные.** Подкоманды пишут `config.yaml` слоёв `user`, `project`, `projectLocal` только по явной команде, атомарно и с сохранением формата; секреты — только через `SecretAdmin` в выбранный бэкенд. Lock-файл `<path>.lock` живёт секунды.
- **Безопасность.** Перезагрузка снимает барьер «правка конфига действует после перезапуска» — но не для ключей, ослабляющих права (R0-1). Правку глобального конфига моделью закрывает OQ2 (PERM-11 по путям хоста).
- **Документы** — задачи группы 0 и 8:
  - `agent-core/17-5-agent-setup.md`;
  - `agent-core/10-core-assembly-and-profiles.md` §10.3;
  - `agent-core/13-acp-adapter.md` §13.4, §13.6;
  - `agent-core/15-configuration.md` §15.4, §15.6;
  - `agent-core/12-observability-and-errors.md` §12.3;
  - `agent-core/07-permissions.md` §7.6.1;
  - `09-13-stage-8-mcp-config.md`, пункт 10 и DoD;
  - `09-11-stage-6-cli-mvp.md`;
  - `12-4-first-run-and-settings.md` §12.4.2;
  - `agent-parity-goals.md` — L-25, E-04, E-15, E-13 (агентская часть);
  - вложенные `AGENTS.md` пакетов `codelab_agent_io`, `codelab_agent_mcp`, `codelab_setup`, `codelab_embedded` и приложений `apps/codelab_agent`, `apps/codelab_cli`.
- **Матрица целей:**
  - L-25 — `core/provider-preconfig-from-env`;
  - E-15 — `core/settings-registry-complete`;
  - E-04 — `core/mcp-reconnect-after-crash`, `config_reload_test.dart`, `mcp_apply_config_test.dart`;
  - E-13, агентская часть — `acp/slash-mcp-list`.
