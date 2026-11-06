## Why

Smoke 2026-11-06: `codelab-agent provider add <id> --kind … --base-url … --model m --context-window N --api-key-stdin` на пустом `CODELAB_HOME` записывает `providers.<id>`, но печатает `warning: agent.default_model: required`, и встроенный агент после этого не стартует. Пользователь добавил провайдера с моделью и всё равно должен отдельно выполнить `config set agent.default_model` или знать про `--default`.

Корень проблемы — обязательность `agent.default_model` в схеме (`agent-configuration` «Схема и строгая проверка», §15.5 шаг 8). Решение пользователя 2026-11-06: ключ становится необязательным, а модель новой сессии выбирается по цепочке, как в OpenCode: явная модель конфига → последняя выбранная пользователем модель → первая модель первого доступного провайдера. Первый вариант («`provider add` сам пишет `agent.default_model`», change `default-model-on-first-provider-add`) пользователь отклонил: он лечит одну команду и оставляет обязательность для всех остальных путей.

## What Changes

- **Схема** (`codelab_agent_core`): `agent.default_model` необязателен. `CoreConfig` получает `defaultModelSource` (`config` | `firstProvider`); `CoreConfig.defaultModel` остаётся непустым `ModelRef`: явная модель или первая модель первого доступного провайдера. Явная невалидная модель — ошибка, как раньше, без тихого отката.
- **Нет ни одной модели** (провайдеров нет или у них нет моделей) — проблема `agent.default_model` вида `value` с новым событием `config.model.none` и текстом `no model is configured; add a provider with at least one model`. Ключ и вид прежние: признак «нужна настройка провайдера» в `codelab_setup` не ломается.
- **Модель новой сессии** (`AgentRuntime.createSession`): при неявной модели конфига сначала берётся последняя выбранная модель из нового порта ядра `LastModelStore`, если она есть в каталоге; событие `session.model.selected {session_id, model, source}`.
- **Последняя выбранная модель** (`codelab_agent_io`): файл `$CODELAB_HOME/state/last-model.json` (`{"v":1,"model":"p/m"}`), атомарная запись, повреждённый файл игнорируется с событием `model.last_used.ignored`. Пишется только при явной смене модели (`setModel`, `session/set_config_option` опции `model`, явная модель `createSession`/`loadSession`). Путь входит в PERM-11.
- **Хосты**: бинарь `serve` (без `--llm-script`) и `codelab_embedded/io.dart` передают файловую память; сценарии, web-барель и тесты — без памяти.
- **`config check`** печатает `Default model: <p>/<m> (config|last-used|first-provider)` перед `Config: valid`.
- **`provider add`** без `--default` больше не даёт `warning: agent.default_model: required`; с `--default` — прежнее поведение. **`provider remove`**: явная ссылка `agent.default_model` по-прежнему ошибка; провайдер последней выбранной модели удаляется свободно; удаление последнего провайдера с моделью — код `1` без подсказки «change the model first».
- **Перезагрузка**: неявная модель пересчитывается после подстановки отложенных частей, в `pendingRestartKeys` не попадает.
- **Документы**: `docs/architecture/proposals/agent-core/15-configuration.md` (§15.4 `agent`, §15.5 шаг 8, §15.7), `17-5-agent-setup.md` (R3-1) и `13-acp-adapter.md` (`session/new`, опция `model`) обновлены в этом change.

ACP не меняется: `configOptions` опции `model` по-прежнему несут `currentValue` выбранной модели, новых методов, полей и состояний нет.

## Не входит

- Мастер провайдера app и CLI, баннер «Add provider», `providerSetupNeeded`, `checkProviderReadiness` (change `add-provider-setup-ui`, итерация 3) — меняются только в объёме D12 design.md (согласовано с сессией того change 2026-11-06): признак `providerSetupNeeded` опирается на событие `config.model.none`, `checkProviderReadiness` берёт модель как ядро; мастер, баннер и запись `agent.default_model` мастером не меняются.
- Показ неявной модели на странице Providers (тег «Default (auto)») — отдельная задача UX.
- Модель по проекту (последняя модель на `cwd`), история нескольких моделей, `agent.fallback`, `agent.summary_model`, роли `llm.roles.*`.
- Последняя модель при `loadSession` без модели журнала и для базы агента сессии: там остаётся `CoreConfig.defaultModel` (D5).
- Проверка наличия секрета в хранилище при выборе провайдера (D3).

## Impact

- Пакеты: `codelab_agent_core` (конфиг, перезагрузка, рантайм, новый порт), `codelab_agent_io` (файл состояния, `config check`, `provider remove`, PERM-11), `codelab_embedded` (подключение порта в `io.dart`), `apps/codelab_agent` (подключение порта в `AgentHost`). Клиенты (`apps/codelab_cli`, `apps/codelab_desktop`, `codelab_client_*`) кода не меняют; `codelab_setup` — `providerSetupNeeded` и `checkProviderReadiness` (D12); формулировки спек и design.md change `add-provider-setup-ui` (D16, D26).
- Публичный API ядра: новое поле `CoreConfig.defaultModelSource`, enum источника, порт `LastModelStore`, поле `AgentCoreServices.lastModel` (необязательное). Публичный API `codelab_agent_io`: `FileLastModelStore`.
- Пользовательские данные: новый файл `$CODELAB_HOME/state/last-model.json` без секретов; существующие конфиги с ключом работают как раньше.
- Тесты и спеки, фиксирующие `agent.default_model: required`, перечислены в `tasks.md` (§2).
