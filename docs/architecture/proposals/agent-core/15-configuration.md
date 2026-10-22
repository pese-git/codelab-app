# 15. Конфигурация

> Часть [архитектуры ядра агента CodeLab](../agent-core-architecture.md). Status: Proposed. Общие соглашения, термины и порядок чтения — в оглавлении.

← [14. Формат golden ACP-фикстур](14-golden-fixtures.md) · [Оглавление ядра](../agent-core-architecture.md) · [16. Что не входит в MVP и открытые вопросы](16-non-mvp-and-open-questions.md) →

## 15.1. Назначение

Конфигурация задаёт провайдеров и модели, режим одобрения, бюджет хода, сжатие, MCP-серверы,
лимиты инструментов, окружение команд и сужение профиля. Формат — YAML 1.2 в строгом профиле
(§15.5, «Профиль YAML»); это единственный формат, который агент и клиенты читают и пишут.
Устаревший `codelab.toml` Python-агента только читается, и только пока YAML-конфига нет (§15.7).
Конфиг читает **хост** (`apps/codelab_agent`, `codelab_embedded`) через `ConfigLoader` из
`codelab_agent_io`. Там же три разборщика: `package:yaml` — чтение YAML с позициями узлов для
сообщений об ошибках (тот же разборщик и тот же профиль читают frontmatter определений агентов,
§15.8, и skills, §17.2.2); `package:yaml_edit` — запись с сохранением форматирования (§17.5.5);
`package:toml` — только чтение устаревшего `codelab.toml` (§15.7). Схема и валидатор — чистая
функция ядра `CoreConfig.fromLayers(List<ConfigTree>)` над уже разобранным деревом и позициями
его узлов: мобильный и web-хосты передают ей настройки из хранилища приложения (без позиций) и
получают ту же проверку. Ядро получает готовый провалидированный `CoreConfig` (§10.3), файлов не
читает и разборщиков YAML и TOML не импортирует (CFG-5). Любая ошибка конфига — отказ при старте
с указанием файла, строки, столбца и ключа, а не тихое значение по умолчанию.

```dart
/// Разобранный слой конфига (codelab_agent_core/lib/src/config/config_tree.dart).
final class ConfigTree {
  final String source;                         // путь файла, "defaults", "env:…", "flags", "app-storage"
  final Map<String, Object?> values;           // ключи — только String; значения — String, int, double, bool, List, Map
  final Map<String, ConfigPosition> positions; // путь ключа ("mcp.servers[github].url") → позиция; пусто — без строк
}
final class ConfigPosition { final int line, column; }   // нумерация с 1, как у package:yaml + 1
```

## 15.2. Расположение и приоритет

От низшего приоритета к высшему (позднее перекрывает раннее):

| # | Источник | Путь | Кто пишет |
|---|---|---|---|
| 1 | встроенные значения по умолчанию | `ConfigLoader` в `codelab_agent_io` | разработчики |
| 2 | глобальный конфиг | `$CODELAB_HOME/config.yaml` (по умолчанию `~/.codelab/config.yaml`) | пользователь |
| 3 | проектный конфиг | `<cwd>/.codelab/config.yaml` | репозиторий (коммитится) |
| 4 | локальный проектный конфиг | `<cwd>/.codelab/config.local.yaml` | пользователь (в `.gitignore`) |
| 5 | переменные окружения `CODELAB_*`; после MVP — первой в слое предконфигурация провайдера `CODELAB_PROVIDER_*` (§17.5.3) | §15.6 | окружение запуска |
| 6 | флаги командной строки | §15.6 | запуск |

`CODELAB_HOME` — корень глобального состояния: конфиг, сессии (§8.9), логи. По умолчанию
`~/.codelab`; на мобильных платформах и web — каталог документов приложения (задаёт хост).

Слияние: отображения (mapping) сливаются по ключам рекурсивно; скалярные значения и списки
заменяются целиком (список `fallback` из проектного конфига не дописывается к глобальному, а
заменяет его); список `mcp.servers` сливается по `name`: сервер с тем же `name` заменяется, новый
добавляется, `enabled: false` в более приоритетном файле выключает сервер. Исключение: `tools.disabled`
слоёв 2–4 объединяется, а не заменяется (§6.3.8); после MVP так же объединяется `tools.mounted`
(§17.11.10). После MVP списки `hooks.before_tool` и `hooks.after_tool` сливаются по `name`, как
`mcp.servers` (§17.14.2.4).

Файлы `codelab.toml` Python-агента в этой таблице отсутствуют: они не дополняют YAML-слои, а
занимают места слоёв 2–4 целиком, только когда ни одного YAML-файла нет (§15.7).

## 15.3. Доверие к проектному конфигу

Проектный конфиг приходит из репозитория, который пользователь мог только что склонировать.
Поэтому слои 3 и 4 ограничены:

| Ключи | Слой 3 (проект) | Слой 4 (локальный) | Условие снятия ограничения |
|---|---|---|---|
| `agent.default_model`, `compaction.*`, `budget.*` (только уменьшение), `tools.output.*` | да | да | — |
| `permissions.mode` | только ужесточение: итоговый режим — `narrow(режим нижних слоёв, режим проекта)` (§7.3.1, как у субагента §17.3.3, шаг 4): `bypass → accept-edits → standard → ask`; `plan` добавляет запреты `write`/`exec` к режиму нижних слоёв (`ask` + `plan` → `ask` с запретом) | да | — |
| `permissions.deny`, `permissions.tools` со значениями `ask` и `deny` | да | да | — |
| `permissions.tools` со значением `allow` | нет | да | проект в `trusted_projects` |
| `mcp.servers` | нет (игнорируется с предупреждением) | да | проект в `trusted_projects` |
| `providers.*` (адреса, заголовки) | нет | да | проект в `trusted_projects` |
| `prompts.*` (включая `append_system`, `append_system_text`, §11.6.1) | нет | да | проект в `trusted_projects` |
| `loop.*` (C-07, C-08), кроме ключей `loop.final_response.*` из строк §17.12 | да | да | — |
| `tools.disabled` (T-26) | да — только добавляет (объединение слоёв, §6.3.8) | да | — |
| `agent.effort` | да | да | — |
| `redact.enabled = true`, добавление слоёв `redact.layers`, удаление записей `redact.allowlist.*` | да | да | — |
| `redact.enabled = false`, удаление слоёв, новые `redact.allowlist.*`, `redact.exempt_tools` | нет | да | проект в `trusted_projects` |
| `model_catalog.*` | нет | да | проект в `trusted_projects` |
| `exec.*`, `sessions.*`, `logging.*` | нет | да | — |
| `llm.roles.*` (после MVP, L-10) | да (как `agent.default_model`) | да | — |
| `tools.web.enabled = false`; уменьшение `tools.web.fetch_max_bytes`, `fetch_timeout`, `max_redirects` (после MVP, §17.1.6) | да | да | — |
| `tools.web.allow_private_network`, `tools.web.user_agent`, `tools.web.search.*` (после MVP) | нет | да | проект в `trusted_projects` |
| `permissions.tools.web_fetch = "allow"` (после MVP) | нет — как любое `allow` | да | проект в `trusted_projects` |
| `skills.enabled = false`, `skills.disabled`, уменьшение `skills.max_skills` и `skills.catalog_max_chars`, `skills.operative.enabled = false` (после MVP, §17.2.8) | да | да | — |
| `skills.extra_roots`, `prompts.templates_dirs` (после MVP) | нет | да | — (согласие даёт только пользователь) |
| `skills.operative.lines`, `skills.operative.max_tokens` (после MVP) | нет | да | проект в `trusted_projects` |
| каталоги `.codelab/skills`, `.codelab/prompts` (после MVP) | нет | — | проект в `trusted_projects` |
| `subagents.*` (после MVP, §17.3.10) | только ужесточение (меньшие лимиты, `enabled = false`; `follow_ups = false`, уменьшение `max_follow_ups`, `max_resumes`, но не включение и не увеличение, §17.3.8.1) | да | — |
| `tools.spill.enabled = false`; уменьшение любых ключей `tools.spill.*` (этап 3, §17.4.8) | да | да | — |
| увеличение ключей `tools.spill.*` (этап 3) | нет | да | глобальный конфиг или проект в `trusted_projects` |
| `secrets.*` (после MVP, §17.5.9) | нет | нет | только глобальный конфиг |
| `config.*` (после MVP) | нет | да | — |
| `${secret:<name>}` в `headers`, `env` (после MVP, §17.5.4) | нет (подстановка — литерал с предупреждением) | да | проект в `trusted_projects` |
| `steering.enabled = false`; уменьшение `steering.max_steps`, `steering.max_pending`, `steering.max_bytes` (после MVP, §17.7.7) | да (только ужесточение) | да | — |
| увеличение лимитов `steering.*` (после MVP) | нет | да | проект в `trusted_projects` |
| `lsp.enabled = false`, `lsp.servers.<id>.enabled = false`; уменьшение `lsp.max_servers`, таймаутов, `max_open_documents`, `rename_max_files`; `diagnostics_after_edit` (после MVP, §17.8.10) | да | да | — |
| новый `lsp.servers.<id>`; любое поле существующего сервера, кроме `enabled = false` (`command`, `args`, `env`, `extensions`, `language_ids`, `root_markers`, `initialization_options`, `settings`) (после MVP) | нет (игнорируется с предупреждением `config.project.untrusted_key`) | да | проект в `trusted_projects` |
| увеличение лимитов `lsp.*` (после MVP) | нет | да | глобальный конфиг или проект в `trusted_projects` |
| `${secret:<name>}` в `lsp.servers.*.env` (после MVP) | нет | да | проект в `trusted_projects` |
| `jobs.enabled = false`; уменьшение `jobs.max_running`, `jobs.max_duration`, `jobs.buffer_bytes`, `jobs.log_max_bytes` (после MVP, §17.9.12) | да | да | — |
| увеличение лимитов `jobs.*`, `jobs.poll_interval` (после MVP) | нет | да | глобальный конфиг или проект в `trusted_projects` |
| `llm.roles.vision` (после MVP, §17.11.5) | да (как `llm.roles.*`) | да | — |
| `tools.load`, `tools.mounted`, `tools.edit.anchors`; `enabled = false` и уменьшение лимитов `tools.read.*`, `tools.inspect_image.*`, `tools.checkpoint.*`, `tools.history.*`; `tools.ask.enabled = false`, уменьшение `tools.ask.timeout` (конечное значение поверх `null`); `memory.enabled = false`, `memory.inject = false`, уменьшение `memory.*` (после MVP, §17.11.10) | да | да | — |
| увеличение лимитов `tools.read.*`, `tools.inspect_image.*`, `tools.checkpoint.*`, `tools.history.*`, `memory.*`; `tools.ask.enabled = true` поверх `false` нижнего слоя, увеличение `tools.ask.timeout` (в том числе `null`) (после MVP) | нет | да | глобальный конфиг или проект в `trusted_projects` |
| `loop.final_response.require_approval = true`, `loop.final_response.on_revise_limit = hold`, `loop.final_response.max_revisions`; `tools.heartbeat.*`; `redact.block = true`; `redact.command_rewrite = true` (после MVP, §17.12) | да | да | — |
| `loop.final_response.require_approval = false` поверх глобального `true`, `loop.final_response.on_revise_limit = accept`; `redact.block = false`, `redact.command_rewrite = false` (после MVP) | нет | да | проект в `trusted_projects` |
| `hooks.*` (после MVP, §17.14.2.4), включая `enabled: false` и выключение хука по `name` | нет (игнорируется с предупреждением `config.project.untrusted_key`) | да | проект в `trusted_projects` |
| `${secret:<name>}` в `hooks.*.env` (после MVP) | нет | да | проект в `trusted_projects` |
| уменьшение `llm.retry.*`, `llm.timeouts.*`; `images.dedup = true`; уменьшение `images.max_bytes`, `images.max_dimension`, `images.max_input_*`, `images.max_per_request` (после MVP, §17.10.12, §17.11.10) | да | да | — |
| увеличение `llm.retry.*`, `llm.timeouts.*`, лимитов `images.*`; `images.dedup = false`; `images.jpeg_qualities`, `images.min_dimension` (после MVP) | нет | да | глобальный конфиг или проект в `trusted_projects` |
| `plugins.*` (после MVP, §17.14.3.4) | нет (игнорируется с предупреждением `config.project.untrusted_key`) | да | проект в `trusted_projects` |
| `a2a.agents.*` (после MVP, §17.15.5): новый удалённый агент и любое поле, кроме `enabled = false` | нет (игнорируется с предупреждением `config.project.untrusted_key`): иначе репозиторий направил бы код и секрет пользователя на свой адрес | да | проект в `trusted_projects` |
| `a2a.agents.<имя>.enabled = false`; уменьшение `a2a.client.*` (после MVP) | да | да | — |
| `a2a.server.*` (после MVP, §17.15.4) | нет | нет | только глобальный конфиг и флаги `serve --a2a` |

После MVP новые ключи провайдеров (§17.10.12: `preset`, `auth`, `key_rotation`, `key_cooldown`,
кварки, `overflow_phrases`, `models.<m>.tools`) — внутри `providers.*`, а `logging.llm_snapshot` —
внутри `logging.*`: новых правил доверия они не добавляют. Ключи `compaction.engine` и
`compaction.structured.*` (§17.13.4) покрыты строкой `compaction.*`, а `sessions.window.*` и
`sessions.segments.*` (§17.13.2) — строкой `sessions.*`.

Слои 5 и 6 (окружение, флаги и после MVP предконфигурация провайдера `CODELAB_PROVIDER_*`,
§17.5.3) правилам доверия не подчиняются: их задаёт тот, кто запускает агента.

`trusted_projects` — массив абсолютных путей в **глобальном** конфиге. Ключ из слоя 3, который
требует доверия, без него не ошибка, а предупреждение `config.project.untrusted_key` с именем
ключа: репозиторий не может сломать запуск, но и не может расширить права агента.

## 15.4. Схема MVP

Значения по умолчанию указаны для профиля `agent-serve`. Типы: `string`, `int`, `float`,
`bool`, `duration` (строка вида `"30s"`, `"2m"`, `"1h"`), `path` (строка; `~` раскрывается).
Соответствие типов узлам YAML — профиль §15.5. Путь ключа в документе пишется через точку
(`providers.<id>.kind`), в файле это вложенные отображения:

```yaml
providers:
  openai:
    kind: openai-compatible
```

**Корень**

| Ключ | Тип | По умолчанию | Смысл |
|---|---|---|---|
| `trusted_projects` | path[] | `[]` | только глобальный конфиг; §15.3 |

**`providers.<id>`** — `<id>`: `[a-z0-9_-]+`, имя для ссылок `"<id>/<model>"`.

| Ключ | Тип | По умолчанию | Смысл |
|---|---|---|---|
| `kind` | `"openai-compatible"` \| `"anthropic"` \| `"gemini"` | обязателен, если нет `preset` | адаптер (§2.5, §17.10.3) |
| `base_url` | string | для `anthropic` — `https://api.anthropic.com`; для `gemini` — `https://generativelanguage.googleapis.com`; для `openai-compatible` обязателен | эндпоинт |
| `api_key_env` | string | нет | имя переменной окружения с ключом |
| `api_key_secret` | string | нет | имя секрета в `SecretStore` (keychain) |
| `auth_header` | string | `Authorization` (Bearer) / `x-api-key` | имя заголовка ключа |
| `headers` | map string→string | `{}` | дополнительные заголовки; допускают `${ENV}`, после MVP — `${secret:<name>}` (§17.5.4) |
| `connect_timeout` | duration | `llm.timeouts.connect` (`"30s"`) | заголовки ответа не пришли (§2.4) |
| `idle_timeout` | duration | `llm.timeouts.idle` (`"120s"`) | пауза между событиями SSE |
| `rate_limit_retries` | int | `llm.retry.rate_limit_retries` (`3`) | бюджет повторов при 429, не считая первой попытки: `RetryPolicy.rateLimitRetries` (§2.10) |
| `transient_retries` | int | `llm.retry.transient_retries` (`3`) | повторы сетевых сбоев и 5xx до видимого вывода, не считая первой попытки: `RetryPolicy.maxAttempts = transient_retries + 1` (§2.10); после MVP `timeout` до вывода тратит не его, а `stall_retries` (§17.10.10.1) |
| `idle_timeout_reasoning` | duration | `llm.timeouts.idle_reasoning` (`"600s"`) | простой до первого контентного блока у модели с `hidden_reasoning` (§2.10.5); не меньше `idle_timeout` |
| `prompt_cache_key` | bool | `true` для хоста `api.openai.com`, иначе `false` | отправлять `prompt_cache_key` = id сессии (§2.12.1); только `openai-compatible` |
| `reasoning_format` | `"openai"` \| `"openrouter"` \| `"none"` | `openrouter` для хоста `openrouter.ai`, иначе `openai` | поле уровня рассуждения (§2.12.3) |
| `list_models` | bool | `true` | запрашивать список моделей endpoint (§2.12.2) |
| `list_models_include` | string[] (глобы id) | `[]` (все) | сужение списка endpoint (§2.12.2) |
| `preset` | enumeration id пресета | нет | после MVP: значения по умолчанию из `ProviderPresets` (§17.10.2) |
| `auth` | `"api-key"` \| `"oauth"` \| `"none"` | из пресета; иначе `api-key` при `api_key_*`, `none` без них | после MVP: `oauth` — токен `codelab/oauth/<id>` (§17.10.6); с `api_key_*` вместе — `ConfigException` |
| `key_rotation` | bool | `true` | после MVP: пул ключей `NAME_2…` (§17.10.4) |
| `key_cooldown` | duration | `"60s"` | после MVP: охлаждение ключа после 429; `1s..15m` |
| `think_tags`, `usage_in_choice`, `image_reject_retry`, `schema_simplify_retry` | bool | из пресета, иначе `false` | после MVP: кварки совместимости (§17.10.2) |
| `overflow_phrases` | string[] | `[]` | после MVP: дописываются к фразам пресета (§17.10.8) |
| `retry_base_delay`, `retry_max_delay`, `max_retry_after` | duration | `llm.retry.base_delay`, `.max_delay`, `.max_retry_after` | после MVP: переопределение `llm.retry.*` на провайдера (§17.10.10.1, §17.10.12) |
| `stall_retries`, `stall_key_rotations` | int | `llm.retry.stall_retries`, `.stall_key_rotations` | после MVP: переопределение `llm.retry.*` на провайдера (§17.10.10.1) |
| `stall_base_delay`, `stall_max_delay` | duration | `llm.retry.stall_base_delay`, `.stall_max_delay` | после MVP: переопределение `llm.retry.*` на провайдера (§17.10.10.1) |

Ключ API **нельзя** писать в конфиг значением: ключ `api_key` — ошибка
`ConfigException("providers.openai.api_key: ключи не хранятся в конфиге, используйте api_key_env или api_key_secret")`.
Без `api_key_env` и `api_key_secret` запросы идут без ключа (локальные Ollama, LM Studio).
`api_key_env` и `api_key_secret` взаимоисключающие: оба сразу — `ConfigException`. После MVP
правило о встроенном секрете расширено (CFG-9, §17.5.4): кроме `api_key` отклоняются ключи
`apiKey`, `token`, `secret`, `password` в `providers.*`, `tools.web.search.backends.*` и
`mcp.servers.*`, литеральные значения `headers.*` и `mcp.servers.*.env.*`, похожие на ключ по
шаблонам §12.4, и ключ, вписанный в `api_key_env`/`api_key_secret` вместо имени; ошибка —
`ConfigInlineSecretException` с подсказкой `codelab secret set <name>`.

**`providers.<id>.models.<model>`** — `<model>` — id модели у провайдера: один ключ YAML, даже
если в нём есть `.` или `/` (`gpt-4o`, `qwen2.5-coder-32b`, `org/model`); с `:` или пробелом,
или если ключ начинается с символа разметки YAML, его пишут в кавычках (`"llama3.1:70b"`). В
путях сообщений об ошибках такой сегмент тоже в кавычках:
`providers.ollama.models."llama3.1:70b".context_window`.

| Ключ | Тип | По умолчанию | Смысл |
|---|---|---|---|
| `context_window` | int | нет | окно модели, токены; не задано — порядок источников §2.12.2 |
| `max_output_tokens` | int | нет (§2.12.2) | лимит ответа |
| `name` | string | id модели | имя в селекторе `model` (§13.6) |
| `image` | bool | `false` | принимает картинки |
| `reasoning` | bool | `false` | поддерживает рассуждения |
| `cost_input`, `cost_output` | float | нет | цена за 1 млн токенов, USD |
| `cost_cache_read`, `cost_cache_write` | float | нет | то же для кеша |
| `hidden_reasoning` | bool | нет | закрытое рассуждение: длинный таймаут простоя до первого контента (§2.10.5) |
| `tools` | bool | нет (§2.12.2) | после MVP: `false` — вызов инструментов через промпт (§17.10.11) |

**`agent`**

| Ключ | Тип | По умолчанию | Смысл |
|---|---|---|---|
| `default_model` | string `"provider/model"` | обязателен | модель новой сессии; должна быть в каталоге |
| `fallback` | string[] | `[]` | цепочка `withFallback` (§2.10.3) после `default_model` |
| `summary_model` | string? | `null` | модель суммаризатора (§9.7): `null` → роль `smol` (§17.10.5), иначе модель сессии; порядок — переопределение роли `smol` на сессию, `agent.summary_model`, `llm.roles.smol.models`, модель сессии |
| `effort` | `"low"` \| `"medium"` \| `"high"` | `"medium"` | начальное значение опции сессии `effort` (§2.12.3, §13.6) |

**`llm.roles.<role>`** (после MVP, цель L-10) — `<role>`: `default` (основная), `smol` (сжатие,
заголовок сессии, исследование), `slow` (ревью), `plan`, `subagent`, `vision` (разбор изображений,
§17.11.5); другое имя — `ConfigException`.
Тип ядра — `ModelRole`; роли использует, например, выбор модели субагента (§17.3.3, шаг 7).
Алгоритм выбора, потребители ролей и `/model --role` — §17.10.5.

| Ключ | Тип | По умолчанию | Смысл |
|---|---|---|---|
| `models` | string[] `"provider/model"` | нет | цепочка моделей роли: первая доступная, дальше — fallback (§2.10.3); каждая — в каталоге моделей |
| `connect_timeout` | duration | из провайдера | переопределяет `providers.<id>.connect_timeout` для запросов этой роли |
| `stream_idle_timeout` | duration | из провайдера | переопределяет `providers.<id>.idle_timeout` для запросов этой роли |
| `context_window`, `max_output_tokens` | int | нет | значения роли в порядке разрешения §2.12.2 (после явного override модели) |

Роль без таблицы или без доступной модели — основная модель (`agent.default_model` и
`agent.fallback`) с одной заметкой в логе; исключение — `vision`: без её модели инструмент
`inspect_image` не регистрируется (§17.11.5). `llm.roles.default.models` при наличии заменяет
`agent.default_model` + `agent.fallback`. Переопределение на прогон — флаг `--role` (§15.6).

**`llm.retry`, `llm.timeouts`** (после MVP, L-33) — общие бюджеты повторов и таймауты; порядок:
роль (только таймауты) → `providers.<id>` → `llm.*` → встроенное значение. Ключи и границы —
таблица §17.10.12: `retry.transient_retries` (3), `retry.rate_limit_retries` (3),
`retry.base_delay` ("1s"), `retry.max_delay` ("30s"), `retry.max_retry_after` ("120s"),
`retry.stall_retries` (1), `retry.stall_base_delay` ("5s"), `retry.stall_max_delay` ("60s"),
`retry.stall_key_rotations` (2), `timeouts.connect` ("30s"), `timeouts.idle` ("120s"),
`timeouts.idle_reasoning` ("600s").

**`images`** (после MVP, T-29, C-16) — подготовка и однократная передача картинок; ключи и
границы — таблица §17.11.10: `max_bytes` (3932160), `max_dimension` (2000), `min_dimension`
(256), `max_input_bytes` (33554432), `max_input_pixels` (50000000), `jpeg_qualities`
([85, 70, 55, 40]), `dedup` (true), `max_per_request` (50).

**`model_catalog`** — каталог моделей (§2.12.2).

| Ключ | Тип | По умолчанию | Смысл |
|---|---|---|---|
| `ttl` | duration | `"24h"` | свежесть кэша списков и удалённого каталога |
| `fetch_timeout` | duration | `"10s"` | таймаут запроса `/models` и каталога |
| `metadata_url` | string (https) | нет (выключен) | удалённый каталог метаданных; только дополняет (§2.12.2) |

**`permissions`** (`PermissionPolicy`, §7)

| Ключ | Тип | По умолчанию | Смысл |
|---|---|---|---|
| `mode` | `"plan"` \| `"ask"` \| `"standard"` \| `"accept-edits"` \| `"bypass"` | режим профиля (§10.5) | режим новой сессии (§13.6); синонимы `alwaysAsk` → `ask`, `write` → `standard`, `acceptEdits` → `accept-edits`, `yolo` → `bypass` — это внутренние имена `PermissionMode` (§7.3); устаревшие ACP-синонимы `architect`, `debug`, `code` (§13.6) в конфиге не принимаются; `autopilot` в конфиге запрещён (только флаг) |
| `timeout` | duration | нет (ждать) | ожидание ответа пользователя; по истечении — `cancelled`, то есть отказ |
| `deny` | string[] | `[]` | явные запреты `PermissionKey` в форме `"<tool>:<pattern>"` (`"exec:git push --force"`, `"write:.env"`); сильнее всего (PERM-2) |

**`permissions.tools`** — per-tool override (`PolicyRules.toolPolicies`): ключ — имя
инструмента (включая `mcp__<server>__<tool>`), значение — `"allow"`, `"ask"` или `"deny"`.
Пример: `read: allow`, `exec: ask`, `mcp__github__create_issue: deny`. Критические
команды спрашиваются даже при `exec = "allow"` (§7.6). Разрешения по шаблону аргументов в
конфиге нет: «разрешить всегда» по `(tool, pattern)` даёт только пользователь в ходе сессии, и
это решение живёт до закрытия сессии (§7.4).

**`budget`** (`TurnBudget`, §5.2)

| Ключ | Тип | По умолчанию | Смысл |
|---|---|---|---|
| `max_steps` | int | `50` | запросов к модели за ход (ACP `max_turn_requests`) |
| `max_tokens` | int | нет | сумма input + output за ход |
| `max_cost` | float | нет | USD за ход; работает только при известных ценах |
| `max_duration` | duration | нет | время хода без ожидания одобрения |

**`compaction`**

| Ключ | Тип | По умолчанию | Смысл |
|---|---|---|---|
| `enabled` | bool | `true` | автоматическое сжатие; `/compact` работает всегда при capability |
| `context_window_cap` | int | нет | ограничение окна сверху (`effectiveContextWindow`, §9.3) |
| `reserve_tokens` | int | `forWindow` | §9.4, с ограничением `w/4` |
| `keep_recent_tokens` | int | `forWindow` | §9.4, с ограничением `w/2` |
| `keep_recent_user_turns` | int | `1` | §9.6 |
| `engine` | `"classic"` \| `"structured"` | `"classic"` | после MVP: движок сжатия; новые и загружаемые сессии (§17.13.4) |
| `structured.target_fraction` | float | `0.5` | после MVP: до какой доли окна скрывать; `0.2..0.8` |
| `structured.elide_min_tokens` | int | `256` | после MVP: меньшие результаты не скрываются по одному; `32..65536` |
| `structured.preview_chars` | int | `60` | после MVP: длина начала результата в маркере; `0..200` |
| `structured.marker_budget_fraction` | float | `0.125` | после MVP: бюджет маркеров fold; `0.02..0.25` |
| `structured.expand_max_tokens` | int | `8000` | после MVP: предел результата `context_expand`; `512..65536`, итог `min(·, w/4)` |
| `structured.max_expands_per_turn` | int | `8` | после MVP: `1..64` |
| `structured.pin_budget_fraction` | float | `0.25` | после MVP: бюджет пинов; `0..0.5`, `0` — пины выключены |
| `structured.fallback_classic` | bool | `true` | после MVP: классическое сжатие, если скрытия не хватило |

**`tools`** (пути с точкой — вложенные отображения: `tools.output.max_lines`)

| Ключ | Тип | По умолчанию | Смысл |
|---|---|---|---|
| `output.max_lines` | int | `2000` | усечение вывода (§6.3) |
| `output.max_bytes` | int | `51200` | 50 КиБ |
| `untrusted_paths` | string[] | `["node_modules", ".dart_tool", "vendor"]` | каталоги, вывод `read`/`search` из которых считается недоверенным (§6.3.6, §10.6) |
| `project_context.max_bytes` | int | `32768` | лимит `AGENTS.md` (§11.5) |
| `disabled` | string[] | `[]` | выключенные инструменты: имена встроенных, `mcp__<server>__<tool>`, `mcp__<server>__*`, `mcp__*`; слои 2–4 объединяются (§6.3.8, T-26) |
| `load` | `"all"` \| `"essential"` | `"all"` | после MVP: режим загрузки инструментов (T-27, §17.11.9) |
| `mounted` | string[] | `[]` | после MVP: селекторы §6.3.8, подключённые в режиме `essential`; слои 2–4 объединяются |
| `heartbeat.after` | duration | `"10s"` | после MVP: первый heartbeat долгого вызова (§17.12.3); `1s..600s` |
| `heartbeat.every` | duration | `"10s"` | после MVP: период heartbeat; `1s..600s` |
| `heartbeat.stuck_after` | duration | `"120s"` | после MVP: тишина до `ToolCallStuck`; `0` — выкл. |

После MVP ключи `tools.read`, `tools.edit`, `tools.inspect_image`, `tools.checkpoint`, `tools.ask`,
`tools.history` — лимиты и включение дополнительных инструментов (лимиты картинок — секция
`images`, §17.11.2.1): `read.archive_max_bytes` (`67108864`),
`read.archive_member_max_bytes` (`16777216`), `read.archive_max_entries` (`10000`),
`read.sqlite_max_bytes` (`67108864`), `edit.anchors` (`false`), `inspect_image.enabled` (`true`),
`inspect_image.timeout` (`"60s"`), `inspect_image.max_output_tokens` (`1024`),
`checkpoint.enabled` (`true`), `checkpoint.max_rewinds_per_turn` (`3`),
`checkpoint.report_max_chars` (`4000`), `ask.enabled` (`true`; `false` → capability
`userQuestions` off), `ask.timeout` (`null` — ждать), `history.enabled` (`true`),
`history.max_scan_records` (`20000`). Границы и смысл — §17.11.10.

**`loop`** — поведение цикла при сбоях модели (§5.4.1, §6.3.7).

| Ключ | Тип | По умолчанию | Смысл |
|---|---|---|---|
| `empty_response_retries` | int | `2` | повторы пустого ответа подряд с подсказкой; `0..5` (§5.4.1, C-07) |
| `misuse.enabled` | bool | `true` | предохранитель неверных вызовов (§6.3.7, C-08) |
| `misuse.warn_after` | int | `3` | с какого одинакового неверного вызова за ход дописывается предупреждение |
| `misuse.block_after` | int | `6` | после скольких одинаковых неверных вызовов за ход вызов блокируется до конца хода; `1 ≤ warn_after ≤ block_after ≤ 50` |
| `final_response.max_revisions` | int | `2` | после MVP: лимит ревизий ответа проверками `FinalResponseCheck`; `0..5` (§17.12.4) |
| `final_response.on_revise_limit` | `"hold"` \| `"accept"` | `"hold"` | после MVP: что делать, если после лимита проверка снова просит доработку (§17.12.4) |
| `final_response.require_approval` | bool | `false` | после MVP: встроенная проверка `approval` — ответ ждёт `/approve` (§17.12.4) |

**`exec`** (`exec`, `EnvVarsEnv`, §4.5)

| Ключ | Тип | По умолчанию | Смысл |
|---|---|---|---|
| `shell` | string | `"/bin/sh"` | shell для команды; вызывается как `<shell> -c <команда>` локально и в `terminal/create` |
| `default_timeout` | duration | `"120s"` | таймаут `exec` без явного аргумента |
| `max_timeout` | duration | `"30m"` | верхняя граница аргумента `timeout` |
| `secrets` | `{env, secret}`[] | `[]` | секреты, которые передаются командам переменными окружения: `env` — имя переменной (`^[A-Z_][A-Z0-9_]*$`), `secret` — имя секрета `SecretStore` (правило `SecretNames`, §17.5.2); значения редактируются (§12.4) |
| `local_fallback` | bool | `false` | `agent-serve`: исполнять локально, если клиент не объявил `terminal` |

**`exec.env`** — постоянные переменные окружения команд (`NAME: value`), поверх базового
набора §4.5 (`PATH`, `HOME`, `USER`, `LANG`, `LC_ALL`, `TMPDIR`, `SHELL` из окружения хоста и
фиксированные `TERM=dumb`, `PAGER=cat`, `GIT_PAGER=cat`, `GIT_TERMINAL_PROMPT=0`). Остальное
окружение процесса хоста командам не передаётся (ENV-6).

**`mcp.servers`** — список отображений, по одному на сервер

| Ключ | Тип | По умолчанию | Смысл |
|---|---|---|---|
| `name` | string | обязателен | префикс инструментов `mcp__<name>__` |
| `type` | `"stdio"` \| `"http"` | обязателен | транспорт |
| `command`, `args`, `env` | string, string[], map string→string | — | для `stdio`; `${ENV}` допустим в `args` и значениях `env`; после MVP в значениях `env` — и `${secret:<name>}` (§17.5.4) |
| `url`, `headers` | string, map string→string | — | для `http`; `${ENV}` допустим; после MVP в значениях `headers` — и `${secret:<name>}` |
| `enabled` | bool | `true` | выключение сервера без удаления |
| `connect_timeout` | duration | `"10s"` | подключение при создании сессии |

**`sessions`**

| Ключ | Тип | По умолчанию | Смысл |
|---|---|---|---|
| `dir` | path | `$CODELAB_HOME/sessions` | корень журналов (§8.9) |
| `fsync` | `"checkpoints"` \| `"always"` \| `"never"` | `"checkpoints"` | §8.5 |
| `lease.enabled` | bool | `true` | после MVP (§17.6.8): `false` — lease только внутри процесса (`process`), для ФС без атомарного `rename`; сравнение ревизии остаётся |
| `lease.heartbeat` | duration | `"5s"` | после MVP: период пульса lease; `1s..60s` |
| `lease.stale_after` | duration | `"15s"` | после MVP: возраст mtime, после которого lease протух; не меньше `3 × lease.heartbeat`, иначе `ConfigException` |
| `branch_summary.enabled` | bool | `true` | после MVP (§17.6.5): `false` — сводки покинутых веток не генерируются, заметка об эффектах остаётся |
| `branch_summary.on_switch` | bool | `true` | после MVP: сводка по умолчанию при переключении ветки |
| `branch_summary.on_rewind` | bool | `false` | после MVP: сводка по умолчанию при перемотке |
| `branch_summary.model` | string? | `null` | после MVP: `provider/model`; `null` → модель суммаризатора §9.7 (`agent.summary_model`, роль `smol`, модель сессии; §17.10.5) |
| `branch_summary.timeout` | duration | `"60s"` | после MVP: после него — `summaryStatus: failed` |
| `read_only.tail_interval` | duration | `"1s"` | после MVP (§17.6.8): период слежения за файлом в режиме только чтения; `200ms..10s` |
| `window.enabled` | bool | `true` | после MVP (§17.13.2): `false` — всегда полное открытие §8.6 |
| `window.threshold_bytes` | int | `67108864` | после MVP: журнал из одного сегмента меньше порога открывается полностью; `1048576..17179869184` |
| `window.replay_max_records` | int | `2000` | после MVP: записей пути в реплее; `100..1000000` |
| `window.chunk_bytes` | int | `1048576` | после MVP: чанк сканера; `65536..16777216` |
| `window.max_line_bytes` | int | `67108864` | после MVP: длиннее — карантин `line too long`; `1048576..268435456` |
| `segments.max_bytes` | int | `268435456` | после MVP (§17.13.2): порог ротации сегмента; `0` — без ротации; иначе `16777216..4294967296` |
| `search.enabled` | bool | `true` | после MVP (§17.6.17, D-17): `false` — capability `sessionSearch` не объявляется |
| `search.allow_all` | bool | `true` | после MVP: `false` — `_codelab/session/search` только с `scope: "cwd"` |

Ключи `sessions.*` в проектном конфиге не принимаются (§15.3); подробно — §17.6.12.

**`prompts`** — §11.6: `system` (path) или `system_text` (string), `modes.plan`,
`compaction.summary`, `compaction.summary_update`; `append_system` (path) или
`append_system_text` (string) — дополнение после базы (§11.6.1); пары `system`/`system_text` и
`append_system`/`append_system_text` взаимоисключающие. `context_files` (string[], этап 8, цель
E-17, §11.5) — дополнительные имена файлов контекста проекта, которые читаются на каждом уровне
обхода наряду с `AGENTS.md` и `CLAUDE.md` (`GEMINI.md`, `.github/copilot-instructions.md`,
`.github/instructions/*.instructions.md`). После MVP (§17.2.8): `templates` (bool,
`true` — шаблоны промптов как команды) и `templates_dirs` (path[], дополнительные каталоги
шаблонов, только слой 2 и 4).

**`tools.web`**, **`tools.web.search`**, **`tools.web.search.backends.<name>`** (после MVP) —
web-инструменты: `enabled` (`false` — capability `network` off), `fetch_max_bytes` (2 МиБ),
`fetch_timeout` (`"20s"`), `max_redirects` (`5`), `allow_private_network` (`false`), `user_agent`;
поиск — `backend` (`"duckduckgo"`), `timeout` (`"15s"`); бэкенд с ключом — `preset`
(`brave` \| `tavily`), `url`, `method`, `api_key_secret` или `api_key_env` (значение ключа в конфиге —
`ConfigException`, как CFG-2) и поля разбора. Подробно — §17.1.6.

**`skills`**, **`skills.operative`** (после MVP) — `enabled`, `extra_roots` (только слои 2 и 4),
`disabled`, `max_skills` (`200`), `catalog_max_chars` (`8000`); пины — `enabled`, `max_tokens`
(`2048`), `lines`. Подробно — §17.2.8.

**`subagents`** (после MVP) — `enabled` (`true`), `max_concurrent` (`3`), `max_per_turn` (`10`),
бюджет ребёнка `max_steps` (`30`), `max_tokens`, `max_cost`, `max_duration` (`"10m"`),
`report_max_bytes` (`16384`), `progress_interval`, `heartbeat_interval`, `cancel_grace` (`"10s"`),
`drain_timeout` (`"60s"`); фоновый режим (§17.3.8) — `background` (`true`), `max_background`
(`4`, `0..8`), `auto_wake` (`true`), `max_wakes` (`3`). Подробно — §17.3.10.

**`jobs`** (после MVP, §17.9.12) — фоновые команды: `enabled` (`true`), `max_running` (`4`),
`max_duration` (`"8h"`), `buffer_bytes` (`1048576`), `log_max_bytes` (`16777216`), `poll_interval`
(`"5s"`). Подробно — §17.9.12.

**`hooks`** (после MVP, §17.14.2.4) — `enabled` (`true`), `default_timeout` (`"10s"`, `1s..120s`),
`max_output_bytes` (`8192`, `1024..65536`), списки `before_tool` и `after_tool`: `name`, `command`,
`tools` (`["*"]`), `pattern`, `timeout`, `on_error` (`"block"`, только `before_tool`), `env`,
`enabled`. Подробно — §17.14.2.4.

**`plugins`** (после MVP, §17.14.3.4) — `enabled` (string[], `[]`) и `plugins.<name>.*` по схеме
плагина; неизвестные ключи проверяет плагин, раздел несобранного плагина — предупреждение
`plugin.unknown`.

**`a2a`** (после MVP, §17.15.5) — `a2a.agents.<имя>`: `url`, `card_url`, `description`, `auth`
(`scheme`: `bearer` \| `apiKey` \| `oauth2_client_credentials`, `secret` — имя секрета, `client_id`,
`token_url`, `scopes`), `timeout`, `allow_streaming` (`true`), `enabled` (`true`); `a2a.client`:
`poll_interval` (`"1s"`), `poll_max_interval` (`"10s"`), `reconnect_attempts` (`3`), `max_part_bytes`
(`1048576`); `a2a.server`: `host` (`"127.0.0.1"`), `port` (`8340`), `cwd`, `tokens`, `auth.api_key`
(`false`), `skills` (`["general"]`), `permission_mode` (`"standard"`), `approvals` (`"ask"`),
`approval_timeout` (`"5m"`), `max_concurrent_tasks` (`2`), `max_request_bytes` (`1048576`),
`rate_limit` (`60`), `artifact_max_bytes` (`65536`), `progress_interval` (`"2s"`). Подробно — §17.15.5.

**`memory`** (после MVP, §17.11.10) — долговременная память (T-17): `enabled` (`true`; `false` →
capability `memory` off), `max_notes` (`500`, `10..10000`, на scope), `note_max_chars` (`1000`,
`50..10000`), `inject` (`true` — вставка релевантных заметок), `inject_max_notes` (`5`, `1..20`),
`inject_max_tokens` (`1024`, `64..8192`). Подробно — §17.11.4.

**`tools.spill`** (этап 3, §17.4.8) — вынос огромного результата в файл. Порог — существующие
`tools.output.max_bytes` и `output.max_lines`: результат выносится ровно тогда, когда без
выноса был бы усечён.

| Ключ | Тип | По умолчанию | Смысл |
|---|---|---|---|
| `enabled` | bool | `true` | `false` → capability `outputSpill` off |
| `head_lines`, `tail_lines` | int | `80`, `80` | строки начала и конца во фрагменте; `1..500` |
| `head_bytes`, `tail_bytes` | int | `8192`, `8192` | байты начала и конца; `256..65536`; `head_bytes + tail_bytes ≤ output.max_bytes / 2`, иначе `ConfigException` |
| `max_file_bytes` | int | `16777216` | 16 МиБ, лимит одного файла и `outputByteLimit` для `exec`; `1048576..268435456` |
| `max_session_bytes` | int | `268435456` | 256 МиБ, сумма файлов сессии; не меньше `max_file_bytes` |

**`steering`** (после MVP, §17.7.7) — сообщения пользователя посреди хода.

| Ключ | Тип | По умолчанию | Смысл |
|---|---|---|---|
| `enabled` | bool | `true` | объявлять `_meta.codelab.steering` и принимать `_codelab/session/steer` |
| `max_steps` | int | `20` | `maxSteeringSteps` (LOOP-8): шагов, добавленных steering-ом за ход; общий с уведомлениями субагентов |
| `max_pending` | int | `8` | принятых и ещё не доставленных пользовательских сообщений за раз |
| `max_bytes` | int | `65536` | суммарный UTF-8 размер текстовых блоков одного сообщения |
| `yield_long_tools` | bool | `false` | уступка долгого `exec` в фоновую задачу при steering (§17.9.7); `true` при `jobs.enabled: false` → `ConfigException` |
| `yield_after` | duration | `"10s"` | сколько вызов должен проработать до уступки (§17.9.7) |

**`lsp`**, **`lsp.servers.<id>`** (после MVP, §17.8.10) — языковые серверы для инструмента `lsp`:
`enabled` (`false` — capability `languageServers` off), `max_servers` (`4`), `idle_timeout`
(`"10m"`), `startup_timeout` (`"60s"`), `request_timeout` (`"30s"`), `diagnostics_timeout`
(`"10s"`), `diagnostics_after_edit` (`false`), `max_restarts` (`3`), `max_open_documents` (`200`),
`rename_max_files` (`200`); сервер — `command` (без shell), `args`, `env` (`${ENV}`,
`${secret:<name>}`), `extensions`, `language_ids`, `root_markers`, `initialization_options`,
`settings`, `enabled`. Встроенное значение по умолчанию — сервер `dart`. Подробно — §17.8.10.

**`redact`** — редакция секретов (§12.4.3).

| Ключ | Тип | По умолчанию | Смысл |
|---|---|---|---|
| `redact.enabled` | bool | `true` | `false` — работает только слой `exact`; при старте warning `redact.config.disabled` |
| `redact.layers` | string[] из имён слоёв | шесть слоёв без `entropy` | включённые слои; порядок в списке не важен — приоритет фиксирован; без `exact` → он всё равно включён, warning `redact.config.exact_forced`; неизвестное имя — `ConfigException` |
| `redact.allowlist.builtin` | string[] из `git_sha`, `uuid` | `[git_sha, uuid]` | встроенные записи белого списка |
| `redact.allowlist.patterns` | string[] регулярных выражений | `[]` | свои записи; невалидное выражение — `ConfigException` с путём ключа |
| `redact.exempt_tools` | string[] имён инструментов | `[]` | дополнительно к `write` и `edit` |
| `redact.block` | bool | `false` | P-18, после MVP: отказ чтения файлов учётных данных (§17.12.7) |
| `redact.command_rewrite` | bool | `true` | P-14, после MVP: секрет в команде `exec` заменяется ссылкой на переменную окружения (§17.12.6) |

**`logging`**

| Ключ | Тип | По умолчанию | Смысл |
|---|---|---|---|
| `level` | `"trace"`…`"error"` | `"info"` | уровень `Logger` |
| `file` | path | `$CODELAB_HOME/logs/agent.log` | sink логов; переопределяется `--log-file` и `CODELAB_LOG_FILE` (§12.3.1) |
| `trace` | bool | `true` | protocol trace (§12.5) |
| `trace_payload` | bool | `false` | payload кадров; только debug-сборка |
| `llm_snapshot` | `"off"` \| `"headers"` \| `"body"` | `"off"` | после MVP: снимок запроса при зависании (§17.10.10) |

**`secrets`** (после MVP, §17.5.4) — только глобальный конфиг.

| Ключ | Тип | По умолчанию | Смысл |
|---|---|---|---|
| `backend` | `"auto"` \| `"keychain"` \| `"env"` \| `"file"` | `"auto"` | хранилище секретов: ОС-хранилище, если доступно, иначе `env`; `file` — открытый `$CODELAB_HOME/secrets.yaml` с правами `0600` |

**`config`** (после MVP, §17.5.6) — слои 2 и 4.

| Ключ | Тип | По умолчанию | Смысл |
|---|---|---|---|
| `watch` | bool | `true` | наблюдение за файлами конфига и живая перезагрузка |
| `poll_interval` | duration | `"2s"` | период опроса, где события ФС недоступны; `1s..60s` |

**`profile.<name>`** — сужение встроенного профиля (§10.2): ключи — имена capability в
snake_case, значения — `"off"` или список транспортов. Пример:
`profile.agent-serve.mcp = ["http"]`, `shell_exec = "off"` (в файле `off` пишется в кавычках, чтобы
читатель YAML 1.1 не принял его за логическое значение). После MVP — также `network = "off"`
(§17.1.5), `skills = "off"` (§17.2), `language_servers = "off"` (§17.8.10), `background_jobs = "off"`
(§17.9.12), `memory = "off"`, `user_questions = "off"` (§17.11) и `user_hooks = "off"` (§17.14.2).
Расширение — `HostWiringException`.

## 15.5. Алгоритм загрузки и валидации

```text
loadConfig(cwd, env, flags):
1. layers := [defaults]
2. для пути в [global, project, projectLocal, flags.config?]:
     если файла нет → пропустить; иначе разобрать YAML (codelab_agent_io, package:yaml)
     и проверить профиль YAML (ниже) → ConfigTree(values, positions)
     синтаксическая ошибка или нарушение профиля → ConfigException(путь, строка, столбец, сообщение)
   ни одного файла не найдено → legacyLayers(home, cwd) (§15.7): найденные codelab.toml
     читаются в память как слои 2–4; YAML найден → legacy-файлы не читаются,
     при их наличии — одно предупреждение config.legacy_ignored
3. для каждого слоя: validateKeys(layer, schema)          // строгость, ниже; позиции — из positions
     после MVP: проверка встроенных секретов (CFG-9, §17.5.4) → ConfigInlineSecretException
4. для слоёв 3–4: применить правила доверия §15.3
5. merged := merge(layers) по правилам §15.2
6. interpolate(merged)                                    // ${ENV}, после MVP — ${secret:<name>}; ниже
7. после MVP: слой предконфигурации envPreconfigLayer(env, flags) (§17.5.3) — первым в слое 5,
     с той же строгой проверкой шагов 3 и 6, без правил доверия
   applyEnv(merged, env); applyFlags(merged, flags)       // §15.6
8. семантическая проверка:
     default_model, fallback, summary_model (если задан) и после MVP llm.roles.*.models существуют в каталоге моделей
     у каждого openai-compatible провайдера есть base_url
     api_key_env указывает на существующую переменную → иначе предупреждение (не ошибка:
       ключ может понадобиться только при выборе этой модели), ошибка — при выборе
     mcp.servers: уникальные name; stdio имеет command; http имеет url
     reserve_tokens > 0, keep_recent_tokens > 0, max_steps ≥ 1
     permissions.mode != autopilot
     exec.secrets: env соответствует ^[A-Z_][A-Z0-9_]*$, secret — SecretNames.pattern, env уникальны
       → иначе ConfigException с путём ключа
     loop.empty_response_retries ∈ 0..5; 1 ≤ loop.misuse.warn_after ≤ loop.misuse.block_after ≤ 50
     tools.disabled — селекторы §6.3.8; неизвестное имя → ConfigException со списком известных
     prompts: system и system_text вместе, append_system и append_system_text вместе → ConfigException
     providers.*.idle_timeout_reasoning < providers.*.idle_timeout → ConfigException
     после MVP: llm.timeouts.idle_reasoning < llm.timeouts.idle; *.stall_max_delay < *.stall_base_delay;
       *.max_delay < *.base_delay; images.min_dimension > images.max_dimension;
       images.jpeg_qualities не по убыванию или вне 1..100 → ConfigException
     model_catalog.metadata_url не https → ConfigException
     redact.layers: неизвестное имя слоя → ConfigException;
       redact.allowlist.patterns: невалидное выражение → ConfigException с путём ключа
     после MVP: sessions.lease.stale_after ≥ 3 × sessions.lease.heartbeat (§17.6.12);
       steering: max_steps ≥ 1, 1 ≤ max_pending ≤ max_steps, 1024 ≤ max_bytes ≤ 1048576;
       steering.yield_long_tools требует jobs.enabled (§17.9.7, §17.9.12);
       jobs: 1 ≤ max_running ≤ 16, 1m ≤ max_duration ≤ 7d, 65536 ≤ buffer_bytes ≤ 16777216,
         log_max_bytes = 0 или 1048576 ≤ log_max_bytes ≤ tools.spill.max_session_bytes,
         1s ≤ poll_interval ≤ 60s;
       lsp: диапазоны §17.8.10; одно расширение у двух включённых lsp.servers → ConfigException
       providers (§17.10.12): preset известен; kind согласован с пресетом; auth: oauth без oauth
         в пресете → ConfigException("providers.<id>.auth: preset <p> has no sign-in");
         auth: oauth вместе с api_key_env/api_key_secret → ConfigException; key_cooldown ∈ 1s..15m
       tools (§17.11.10): диапазоны tools.read.*, tools.inspect_image.*, tools.checkpoint.*,
         tools.ask.timeout, tools.history.max_scan_records, memory.*;
         tools.read.archive_member_max_bytes > tools.read.archive_max_bytes × 4 → ConfigException;
         tools.mounted — селекторы §6.3.8
       tools.heartbeat.after, .every ∈ 1s..600s; stuck_after = 0 или after ≤ stuck_after ≤ 3600s;
         loop.final_response.max_revisions ∈ 0..5 (§17.12)
       compaction.structured.*, sessions.window.*, sessions.segments.max_bytes — диапазоны
         §17.13.4 и §17.13.2
       hooks (§17.14.2.4): name уникально в фазе слоя, tools не пуст, on_error только в
         before_tool, default_timeout и timeout ∈ 1s..120s, max_output_bytes ∈ 1024..65536
       a2a (§17.15.5): имена agents и tokens — ^[a-z][a-z0-9-]{0,47}$; url и card_url — https
         (http — только loopback), card_url с той же схемой, хостом и портом; auth.secret —
         SecretNames.pattern; client_id и https-token_url ровно при oauth2_client_credentials;
         timeout ∈ 1m..24h; poll_interval ≤ poll_max_interval ∈ 1s..60s; server.skills — известные
         определения или general; server.permission_mode != autopilot; approval_timeout ∈ 10s..1h
9. вернуть CoreConfig + список предупреждений (лог host.config.loaded)
```

**Строгая валидация.** Неизвестный ключ в любом отображении — `ConfigException` с путём ключа и
подсказкой ближайшего известного (расстояние Левенштейна ≤ 2):
`config.yaml:12:3: неизвестный ключ compaction.reserve_token (может быть, reserve_tokens?)`.
Неверный тип — ошибка с ожидаемым типом. Исключения: отображения, чьи ключи — имена
(`providers`, `models`, `headers`, `env`, `profile`, после MVP — `tools.web.search.backends`,
`lsp.servers`, `lsp.servers.*.language_ids`, `a2a.agents`), проверяются по формату имени; значения
`lsp.servers.*.initialization_options` и `settings` — любые JSON-совместимые и не проверяются; ключи `llm.roles` — по фиксированному списку ролей; после MVP `plugins.<name>.*` проверяет
`buildAgentCore` по `CodelabPlugin.settings` (§17.14.3.3). Строка и столбец
берутся из `ConfigTree.positions`; у слоя без позиций (хранилище приложения, окружение, флаги)
сообщение называет источник и путь ключа без строки.

**Профиль YAML.** Конфиг — YAML 1.2 с семантикой core schema; ограничения проверяет
`codelab_agent_io` при разборе, до валидатора ядра, и каждое нарушение — `ConfigException` с
файлом, строкой и столбцом узла:

1. Ровно один документ. Пустой файл (или только комментарии) — пустой слой; второй документ
   после `---` — ошибка `multiple YAML documents are not supported`.
2. Якоря (`&a`), ссылки (`*a`), ключ слияния `<<` и явные теги (`!tag`, `!!str`) — ошибка
   `anchors, aliases, merge keys and tags are not supported`: конфиг читается без скрытых связей,
   и писатель (§17.5.5) не обязан сохранять их при правке.
3. Ключи отображений — только строки: ключ-число (`1:`), `null`, `true` или составной ключ
   (`? [a, b]`) — ошибка. Повторяющийся ключ в одном отображении — ошибка с позициями обоих.
4. Логические значения — только `true` и `false`. Без кавычек `yes`, `no`, `on`, `off`, `y`,
   `n` — строки (как в YAML 1.2), поэтому для поля типа `bool` это ошибка типа с подсказкой
   `use true or false`; в поле типа `string` или в перечислении (`shell_exec: off`) — обычная строка.
5. `null` (`~`, пустое значение после `key:`) у ключа схемы — ошибка типа: чтобы вернуть значение
   по умолчанию, ключ удаляют. Исключение — отображения-контейнеры без листьев (`exec:` без
   вложенных ключей) читаются как пустые.
6. Числа — по core schema: `int` — десятичная запись (`0x…` и `0o…` тоже), `float` принимает и
   целое (`2` → `2.0`), `int` не принимает `2.0`. Длительности и строки — как написаны:
   `30s` и `"30s"` равны, значение не приводится к числу.
7. Точка в ключе — часть имени, а не вложенность: `output.max_lines: 2000` внутри `tools:` — один
   неизвестный ключ, и подсказка предлагает вложенную форму `output:` → `max_lines:`.
8. Блочный и flow-стиль (`{…}`, `[…]`) читаются одинаково; перевод строк LF или CRLF; кодировка
   UTF-8 (BOM допускается и отбрасывается).

Тот же разборщик и пункты 1–6 действуют для YAML-frontmatter определений агентов (§15.8) и
skills (§17.2.2); набор и типы полей frontmatter задают их собственные таблицы. Машинные файлы
агента — фикстуры, `index.json`, журналы JSONL, индекс имён секретов — остаются JSON.

**Подстановка `${ENV}`.**

1. Разрешена только в: `providers.*.base_url`, `providers.*.headers.*`, `mcp.servers.*.args[*]`,
   `mcp.servers.*.env.*`, `mcp.servers.*.url`, `mcp.servers.*.headers.*`. В остальных ключах
   `${` — литерал.
2. Синтаксис — только `${NAME}`, где `NAME` — `[A-Za-z_][A-Za-z0-9_]*`; форма `$NAME` без скобок
   не поддерживается (это литерал).
3. `$${` — литерал `${`.
4. Переменная не задана → `ConfigException("mcp.servers[github].headers.Authorization: переменная GITHUB_TOKEN не задана")`.
   Пустая строка вместо отсутствующей переменной — источник тихих отказов авторизации.
5. Результат подстановки повторно не раскрывается.
6. Значения, полученные подстановкой в `headers` и `env`, добавляются в набор точных секретов
   редактора (§12.4).
7. После MVP (§17.5.4): в значениях `providers.*.headers.*`, `mcp.servers.*.headers.*` и
   `mcp.servers.*.env.*` допустима форма `${secret:<name>}`, где `<name>` соответствует
   `SecretNames.pattern`; неверное имя — `ConfigException` на загрузке. Значение берётся из
   `SecretResolver` при подключении сервера или запросе к провайдеру, а не при загрузке;
   отсутствующий секрет — ошибка подключения с текстом `secret <name> is not set`. В
   недоверенном проектном слое 3 форма остаётся литералом с предупреждением (§15.3).

## 15.6. Переменные окружения и флаги

| Переменная | Флаг | Ключ |
|---|---|---|
| `CODELAB_HOME` | — | корень состояния |
| `CODELAB_CONFIG` | `--config <path>` | дополнительный файл с приоритетом выше слоя 4; расширение `.yaml` или `.yml`, иначе ошибка использования (для `.toml` — с подсказкой `codelab config migrate <path>`, §15.7) |
| `CODELAB_MODEL` | `--model <provider/model>` | `agent.default_model` |
| — | `--provider <openai-compatible\|anthropic>` (с этапа 4) | провайдер из флагов с id `cli`: `providers.cli.kind`; с ним `--model <model>` — id модели этого провайдера (`agent.default_model = "cli/<model>"`), флаг можно повторять: первое значение — модель по умолчанию, все — модели `providers.cli.models` |
| — | `--base-url <url>` (с этапа 4) | `providers.cli.base_url` |
| `CODELAB_API_KEY` | — (с этапа 4) | ключ провайдера `cli`: `providers.cli.api_key_env = "CODELAB_API_KEY"`; значение в флаги и логи не попадает |
| — | `--llm-script <file.json>` (с этапа 4, только тесты) | вместо провайдера — `ScriptedStreamFunction` из файла `{"llm": {...}}` формата §14.7; провайдер `scripted`, `--model` — его модели; в справке бинаря скрыт |
| `CODELAB_PERMISSION_MODE` | `--permission-mode <mode>` | `permissions.mode` (`plan`, `ask`, `standard`, `accept-edits`, `bypass`); флаг допускает `autopilot` |
| `CODELAB_PROFILE` | `--profile <name>` | профиль хоста (`agent-serve` у бинаря) |
| `CODELAB_LOG_LEVEL` | `--log-level <level>` | `logging.level` |
| `CODELAB_LOG_FILE` | `--log-file <path>` | `logging.file`; флаг сильнее переменной, переменная сильнее конфига; путь в stdout — ошибка использования (§12.3.1) |
| `CODELAB_TOOLS` | `--tools <tool>=on\|off,…` (можно повторять) | `tools.disabled` по инструментам: `off` выключает, `on` возвращает выключенное слоями ниже; флаг применяется после переменной (§6.3.8, T-26) |
| — | `--system-prompt <text>` | `prompts.system_text` (перекрывает и `prompts.system`); вместе с `--system-prompt-file` — ошибка (§11.6.1, E-08) |
| — | `--system-prompt-file <path>` | `prompts.system` (перекрывает и `prompts.system_text`) |
| — | `--append-system-prompt <text>` | `prompts.append_system_text` (перекрывает и `prompts.append_system`) |
| `CODELAB_MAX_STEPS` | `--max-steps <n>` | `budget.max_steps` |
| — | `--local-exec` | `exec.local_fallback = true` |
| — | `--cwd <path>` | `cwd` для `codelab -p` |
| — | `--role <role>=<provider/model>` (после MVP, L-10; можно повторять; в том числе `--role vision=<provider/model>`, §17.11.5) | `llm.roles.<role>.models = ["<provider/model>"]` на прогон |
| — | `--drain-timeout <duration>` (после MVP, только `codelab -p`, H-05) | `subagents.drain_timeout` (§17.3.9); `0` — не ждать |
| — | `--max-wakes <n>` (после MVP, только `codelab -p`, H-05) | `subagents.max_wakes` (§17.3.9); `0` — не будить |
| `CODELAB_PROVIDER_TYPE` | `--provider-type <kind>` (после MVP, L-25) | тип провайдера предконфигурации (§17.5.3) |
| `CODELAB_PROVIDER_CONFIG` | `--provider-config <json \| @путь>` (после MVP) | JSON провайдера предконфигурации; флаги затеняют обе переменные |
| `CODELAB_PROVIDER_CONFIG_BASE64` | — (после MVP) | тот же JSON в base64; вместе с `CODELAB_PROVIDER_CONFIG` — ошибка |
| `CODELAB_SECRET_<ИМЯ>` | — (после MVP, P-12) | переопределение секрета по имени, `SecretNames.envOverride` (§17.5.4) |
| `CODELAB_DEBUG_SECRETS=1` | `--debug-secrets` (после MVP, P-17) | лог каждого обращения к секретам без значений |
| — | `--debug-llm-snapshot[=headers\|body]` (после MVP, L-27) | `logging.llm_snapshot` |
| `CODELAB_DEBUG_LLM_SNAPSHOT` | — | `logging.llm_snapshot` |

**До этапа 8 действуют только флаги и переменные этой таблицы.** Бинарь `codelab-agent` этапа 4
файлы конфига (§15.2) не читает: провайдер, модель и ключ задаются `--provider`, `--base-url`,
`--model` и `CODELAB_API_KEY`, режим — `--permission-mode`, остальные ключи — значения по
умолчанию §15.4 (dart-agent-and-clients §9.9, задача 4.6). На этапе 8 YAML-конфиг (§15.2–§15.5)
заменяет этот минимум, а флаги остаются переопределениями слоя 6. Флаги `--provider` и
`--provider-type`/`--provider-config` (после MVP, §17.5.3) взаимоисключающие: оба сразу — ошибка
использования.

Других переменных `CODELAB_*` ядро не читает; неизвестная переменная с префиксом `CODELAB_`
даёт предупреждение (опечатка не должна молча игнорироваться). Переменные семейства
`CODELAB_SECRET_<ИМЯ>` и `CODELAB_PROVIDER_*` известны целиком, предупреждения не дают; так же
зарезервировано семейство `CODELAB_REDACTED_<n>` — переменные, которыми редакция команды
передаёт процессу вырезанные секреты (после MVP, §17.12.6). Не дают предупреждения и переменные
клиентов: `CODELAB_AGENT_TOKEN` (токен WebSocket-подключения CLI,
[`dart-agent-and-clients.md`](../dart-agent-and-clients.md) §9.11) и `CODELAB_POWER_HELPER`
(только тестовая сборка, [`dart-agent-and-clients.md`](../dart-agent-and-clients.md) §12.6.6). Переменные
пула ключей `NAME_2`… для `api_key_env` (после MVP, §17.10.4) — не `CODELAB_*`, правила
предупреждений не меняются. Тестовая
переменная `CODELAB_TEST_SECRET_STORE=<каталог>` (файловое хранилище секретов для E2E клиентов,
[`dart-agent-and-clients.md`](../dart-agent-and-clients.md) §12.4.13) читается только сборкой с
`--dart-define=CODELAB_ALLOW_TEST_SECRETS=true`; в обычной сборке она не читается и, как любая
неизвестная `CODELAB_*`, даёт предупреждение.

## 15.7. Совместимость с `codelab.toml` (только чтение)

Пользователи Python-агента хранят настройки в `codelab.toml`. Новый агент читает эти файлы
**только для чтения** и только пока у пользователя нет YAML-конфига; ни агент, ни клиенты TOML
не пишут. Перевод в `config.yaml` — команда `codelab config migrate` (ниже). Конфиг нового
агента в TOML никогда не выпускался, поэтому совместимость нужна только для `codelab.toml`.

**Где ищутся устаревшие файлы** — те же места и тот же порядок, что у Python-агента; каждый файл
занимает место соответствующего YAML-слоя §15.2 и подчиняется его правилам доверия (§15.3):

| Устаревший файл | Место слоя | Цель `config migrate` |
|---|---|---|
| `$CODELAB_HOME/codelab.toml` | слой 2 | `$CODELAB_HOME/config.yaml` |
| `$CODELAB_HOME/auth.toml` | слой 2, поверх `codelab.toml` | тот же `$CODELAB_HOME/config.yaml` |
| `<cwd>/codelab.toml` | слой 3 | `<cwd>/.codelab/config.yaml` |
| `<cwd>/codelab.local.toml` | слой 4 | `<cwd>/.codelab/config.local.yaml` |

`codelab.toml.example` не читается никогда — это шаблон.

**Выбор источника** (шаг 2 §15.5, для каждого `cwd`):

```text
legacyLayers(home, cwd):
1. yamlFound := существует хотя бы один из $CODELAB_HOME/config.yaml,
     <cwd>/.codelab/config.yaml, <cwd>/.codelab/config.local.yaml или задан --config
2. yamlFound:
     устаревшие файлы не читаются; если хотя бы один существует — одно предупреждение
     config.legacy_ignored {files} в логе (один раз на процесс и cwd)
     вернуть []
3. legacy := существующие файлы из таблицы выше, в её порядке; пусто → вернуть []
4. для каждого файла: разобрать TOML (package:toml, codelab_agent_io);
     синтаксическая ошибка → ConfigException(путь, строка, столбец, сообщение)
5. перевести дерево по таблице соответствия ниже — тем же кодом, что и config migrate:
     ключ из столбца «отброшен» → предупреждение config.legacy_key_dropped {file, key, reason}
     неизвестный ключ → ConfigException("<файл>:<строка>: неизвестный ключ <путь>") —
       ни подмены на значение по умолчанию, ни mock-провайдера (R-16, DF-15)
     провайдер вне списка таблицы → ConfigException("llm.providers.foo: неизвестный провайдер")
     [agents.definitions.*] → ConfigException с подсказкой перенести определения в
       .codelab/agents/<name>.md (§15.8; config migrate делает это сам), как в YAML (DF-12)
     литеральный api_key → ConfigInlineSecretException (CFG-9) с подсказкой
       codelab secret set <name>; "${VAR}" → api_key_env = "VAR"
6. результат — ConfigTree с source "legacy:<путь>" (позиции — строки TOML-файла); дальше —
   шаги 3–9 §15.5 без изменений: строгая проверка, доверие, слияние, подстановка ${ENV}
7. при старте одна подсказка в лог (warning config.legacy_active {files}) и, у CLI и
   `codelab-agent` с TTY на stderr, строка:
     Run "codelab config migrate" to convert codelab.toml to config.yaml.
```

`ConfigWatcher` (§17.5.6) следит и за устаревшими файлами, и за путями YAML-слоёв: правка
`codelab.toml` перечитывается как обычный слой, появление `config.yaml` переключает источник при
следующей перезагрузке (и `codelab.toml` с этого момента игнорируется с предупреждением).

**Только чтение.** Пока активный конфиг `cwd` получен из `codelab.toml`
(`ConfigLoadResult.legacy == true`), `ConfigWriter.apply` в любой слой отказывает исключением
`ConfigLegacyReadOnlyException(legacyFiles)` и ничего не пишет (§17.5.5): запись первого
`config.yaml` молча выключила бы все настройки из `codelab.toml`. CLI на `config set|unset`,
`provider add|remove`, `mcp add|remove` и `secret set`, если она меняла бы конфиг, печатает
подсказку `Run "codelab config migrate" first: codelab.toml is read-only.` и выходит с кодом 1;
страницы настроек и мастер провайдера в app показывают значения только для чтения с действием
«Migrate to config.yaml» ([`dart-agent-and-clients.md`](../dart-agent-and-clients.md) §12.4).

**Команда `codelab config migrate [<путь>] [--print] [--project|--local]`** (та же у `codelab-agent`):

1. Без `<путь>` — переводит все устаревшие файлы, найденные для текущего `cwd`, каждый в свою цель
   по таблице выше (`codelab.toml` и `auth.toml` из `$CODELAB_HOME` — в один файл). С `<путь>` —
   один указанный файл в `$CODELAB_HOME/config.yaml` (`--project` и `--local` выбирают слой 3 или 4).
2. Перевод — та же функция, что в `legacyLayers` шаг 5; итог проходит валидацию §15.5 до записи.
   Литеральный ключ API не переносится: команда завершается кодом 1, ничего не пишет и называет
   ключ и команду `codelab secret set <name>`; значение в вывод не попадает.
3. Запись — через `ConfigWriter` (`.lock`, временный файл, `fsync`, `rename`, §17.5.5), все цели
   одной командой или ни одной. Цель уже существует → код 1, `<путь> already exists; nothing
   written (use --print)`.
4. Каждый отброшенный ключ — YAML-комментарий в начале соответствующего отображения:
   `# migrate: dropped llm.temperature (not configurable)`. Определения
   `[agents.definitions.*]` — файлы `.codelab/agents/<name>.md` (для глобального файла —
   `$CODELAB_HOME/agents/<name>.md`); существующий файл не перезаписывается.
5. `--print` печатает результат в stdout (перед каждой целью — комментарий `# --- <путь цели>`) и
   ничего не пишет.
6. `codelab.toml` и `auth.toml` не удаляются и не меняются. После записи команда печатает, что
   устаревшие файлы теперь игнорируются и их можно удалить вручную.

**Срок поддержки.** Чтение `codelab.toml` живёт, пока поддерживается Python-агент. После этапа 9
(переключение профиля по умолчанию на Dart-агента, proposal §9.14) чтение объявляется устаревшим:
к подсказке при старте добавляется срок удаления. Удаление читателя и зависимости `package:toml`
из `codelab_agent_io` — отдельный OpenSpec change; команда `config migrate` удаляется вместе с ним.

**Таблица соответствия** (общая для чтения в память и для `config migrate`):

| Старый ключ | Новый ключ | Примечание |
|---|---|---|
| `[llm] provider`, `model` | `agent.default_model = "<provider>/<model>"` | |
| `[llm] temperature` | — (отброшен) | в MVP температура не настраивается; модели с рассуждениями её не принимают |
| `[llm] max_tokens` | `providers.<id>.models.<m>.max_output_tokens` | для активной модели |
| `[llm.timeout] connect` | `providers.<id>.connect_timeout` | для всех провайдеров |
| `[llm.timeout] read` | `providers.<id>.idle_timeout` | смысл уже: пауза между событиями потока |
| `[llm.timeout] write`, `pool` | — | не нужны HTTP-клиенту Dart |
| `[llm.providers.<id>] api_key = "${VAR}"` | `api_key_env = "VAR"` | литеральный ключ не переносится: печатается ошибка с просьбой перенести его в env или keychain |
| `[llm.providers.<id>] base_url` | `providers.<id>.base_url` | |
| `[llm.providers.<id>] default_model` | — | модель по умолчанию одна — `agent.default_model` |
| провайдеры `openai`, `openrouter`, `zen`, `go`, `ollama`, `lmstudio` | `kind = "openai-compatible"` | |
| провайдер `anthropic` | `kind = "anthropic"` | |
| провайдер `litellm` | `kind = "openai-compatible"`, `base_url` прокси | вызов библиотеки заменён прокси LiteLLM как OpenAI-совместимым эндпоинтом |
| `[llm.providers.<id>.models.<m>] context_window`, `max_output_tokens` | те же ключи | |
| `cost_per_input_token`, `cost_per_output_token` | `cost_input`, `cost_output` | ×1 000 000 (цена за токен → за миллион) |
| `[llm.fallback] enabled`, `order` | `agent.fallback = [...]` | при `enabled = false` — пустой массив; `order` перечислял провайдеров, новый ключ — модели: берётся `default_model` каждого провайдера |
| `[llm.fallback] strategy`, `max_attempts`, `retry_on` | — | повторы задаются `transient_retries`, `rate_limit_retries` |
| `[agents] default_model` | `agent.default_model` | если отличается от `[llm]`, побеждает `[agents]` |
| `[agents] context_window_limit` | `compaction.context_window_cap` | |
| `[agents] max_steps` | — | это шаги мультиагентной оркестрации, не хода; `budget.max_steps` задаётся отдельно |
| `[agents] strategy`, `fallback_strategy`, `slicer_*`, `max_sliced_tokens`, `debug` | — | мультиагентности и Token-Slicing нет в MVP |
| `[agents.context]` | — | Context Manager вне MVP |
| `[agents.definitions.*]` | Markdown-файлы `.codelab/agents/<name>.md` (§15.8) | `config migrate` создаёт по файлу на определение; при чтении `codelab.toml` в память и в `config.yaml` (ключ `agents.definitions`) — ошибка с подсказкой о переносе (DF-12) |
| `[tui]` | — | настройки клиента, не агента |
| `[[mcp.servers]]` | `mcp.servers` (список) | поля совпадают; `env` и `headers` — из массива `{name, value}` в отображение; `${VAR}` без значения теперь ошибка |
| `codelab.local.toml` | `.codelab/config.local.yaml` | |
| `~/.codelab/auth.toml` | слой 2 вместе с `$CODELAB_HOME/codelab.toml` | `api_key = "${VAR}"` → `api_key_env`; литеральный ключ — ошибка (CFG-9): ключи — только env или хранилище секретов |

## 15.8. Определения агентов в Markdown

**Назначение.** Пользователь описывает специализированного агента (ревьюер, архитектор,
документатор) одним Markdown-файлом: промпт, модель, разрешённые инструменты и режим. Клиент
выбирает агента опцией конфигурации `agent`. Это сохраняет возможность текущего CodeLab и
заменяет секции `[agents.definitions.*]` устаревшего `codelab.toml` (§15.7).

**Расположение и приоритет.**

| Каталог | Источник | Когда действует |
|---|---|---|
| `$CODELAB_HOME/agents/*.md` | пользователь | всегда |
| `<cwd>/.codelab/agents/*.md` | репозиторий | только если проект в `trusted_projects` (§15.3): тело файла — промпт, а промпты из недоверенного проекта не загружаются (CFG-3) |

Определение проекта с тем же `name` заменяет глобальное. Файлы читаются при создании и загрузке
сессии; изменения действуют в новых сессиях.

Встроенные профили сессии `architect` и `review` (§17.12.2) загружаются первыми; файл с тем же
`name` и `scope` `session` или `both` заменяет профиль.

**Формат файла.** YAML-frontmatter между строками `---`, затем тело — инструкции агента.

```markdown
---
name: reviewer
description: Reviews the current changes and reports defects
model: anthropic/claude-sonnet-4
mode: plan
tools:
  - read
  - search
  - ls
  - mcp__github__*
---
You are a code reviewer. Read the diff of the working tree, look for correctness bugs,
missing tests and unsafe changes. Report findings as a numbered list with file and line.
Do not modify files.
```

| Поле | Тип | Обязательно | Правило |
|---|---|---|---|
| `name` | string | да | `^[a-z][a-z0-9-]{0,47}$`; уникально в каталоге; `default` зарезервировано |
| `description` | string | да | 1–200 символов; показывается клиенту в списке вариантов |
| `model` | string | нет | `"<provider>/<model>"` из конфига (§15.4); неизвестная модель — ошибка определения |
| `mode` | string | нет | `plan`, `ask`, `standard`, `accept-edits`, `bypass` (§13.6); `autopilot` запрещён (CFG-4) |
| `tools` | string[] | нет | список имён инструментов; `*` в конце — префиксный шаблон (`mcp__github__*`); без поля — все инструменты профиля (для субагента — все инструменты родителя, §17.3.3) |
| `scope` | `session` \| `subagent` \| `both` | нет | после MVP: где определение доступно — опция `agent` сессии, тип в `task` (§17.3.2) или оба; по умолчанию `both` |
| тело | text | да | непустое; не больше 32 КиБ |

Неизвестное поле frontmatter — ошибка определения (как CFG-1). Разбор — полноценный YAML
(пакет `yaml` в загрузчике конфигурации; ядро получает готовые объекты, CFG-5) в том же профиле,
что конфиг (§15.5, «Профиль YAML», пункты 1–6: без якорей и тегов, повторяющийся ключ — ошибка,
логические — только `true`/`false`), поэтому многострочные списки и кавычки работают, а разбор
одинаков у конфига и определений.

**Контракт.**

```dart
enum AgentScope { session, subagent, both }    // после MVP, §17.3.2

final class AgentDefinition {
  final String name, description, prompt;   // prompt — тело файла
  final ModelRef? model;
  final ModeId? mode;
  final List<String>? tools;                // null — все инструменты профиля; для субагента — все инструменты родителя
  final String source;                      // путь файла или 'builtin:<name>', для диагностики
  final AgentScope scope;                   // после MVP: по умолчанию both (§17.3.2)
  final ModelRole? role;                    // после MVP: роль модели (L-10), если model не задана; только у встроенных типов
}
// SessionSpec получает список определений; ACP-адаптер строит из него опцию `agent`
// (определения со scope session | both), TaskTool — enum типов (scope subagent | both, §17.3.2).
```

**Алгоритм применения.**

```text
loadAgentDefinitions(home, cwd, trusted):
1. files := home/agents/*.md, затем (если trusted) cwd/.codelab/agents/*.md
2. для каждого файла: отделить frontmatter, разобрать YAML, проверить поля по таблице
     ошибка → диагностика "<путь>:<строка>: <сообщение>", файл пропускается, остальные грузятся
3. одинаковый name в одном каталоге → оба файла пропускаются с диагностикой
4. проектное определение заменяет глобальное с тем же name
5. вернуть список, отсортированный по name

selectAgent(session, name):            // session/set_config_option agent=<name>
1. name == "default" → снять профиль агента: базовый промпт, модель и режим сессии
2. системный промпт = базовый промпт (§11) + секция "## Agent profile: <name>" с телом файла;
   правила безопасности и ограды базового промпта остаются (тело их не заменяет)
3. model задан → сменить модель, опция `model` получает новое значение
4. mode задан → сменить режим так же, как session/set_mode (§13.6)
5. tools задан → набор схем следующего шага = инструменты профиля ∩ список (шаблоны по префиксу),
   только из включённых инструментов (§6.3.8): выключенный инструмент списком не возвращается;
   инструмент вне списка при вызове → отказ "tool not available for agent <name>"
6. разослать config_option_update с полным снимком (agent, model, mode)
7. изменения действуют со следующего шага; идущий вызов инструмента не прерывается
```

**ACP.** Опция конфигурации:

```json
{"id":"agent","name":"Agent","category":"other","type":"select","currentValue":"default",
 "options":[{"value":"default","name":"Default"},
            {"value":"reviewer","name":"reviewer","description":"Reviews the current changes and reports defects"}]}
```

Опция присутствует, только если загружено хотя бы одно определение (со встроенными профилями —
всегда). Выбранный агент пишется в
журнал записью `config_change` (§8) и восстанавливается при `session/load`.

**Инварианты.**

6. **CFG-6.** Определение из проекта, не входящего в `trusted_projects`, не загружается.
7. **CFG-7.** Список `tools` только сужает набор инструментов профиля и не обходит проверку разрешений: каждый вызов по-прежнему проходит §7.
8. **CFG-8.** Тело определения добавляется к базовому промпту и не удаляет из него правила безопасности и ограды недоверенного вывода.

**Как проверить.**

* `agent_definition_parse_test.dart`: frontmatter с многострочным списком `tools`, кавычками и
  комментариями; неизвестное поле, пустое тело, неверное `name`, `mode: autopilot` → ошибки с
  путём и строкой.
* `agent_definition_trust_test.dart`: проектное определение без доверия не загружено, с доверием
  — заменяет глобальное (CFG-6).
* `agent_select_test.dart` (`core/agent-definition-markdown-frontmatter`): выбор `reviewer` даёт
  промпт с секцией профиля, модель и режим из файла, схемы только `read`, `search`, `ls` и
  инструментов `mcp__github__*`; вызов `write` → отказ; возврат к `default` восстанавливает всё
  (CFG-7, CFG-8).
* `acp/set-config-option-agent`: `config_option_update` содержит согласованные `agent`, `model`, `mode`.

## 15.9. Полный пример

```yaml
# ~/.codelab/config.yaml
trusted_projects:
  - /Users/me/work/demo

agent:
  default_model: openai/gpt-4o
  fallback: [anthropic/claude-sonnet-4]
  summary_model: openai/gpt-4o-mini

providers:
  openai:
    kind: openai-compatible
    base_url: https://api.openai.com/v1
    api_key_env: OPENAI_API_KEY
    models:
      gpt-4o:
        name: GPT-4o
        context_window: 128000
        max_output_tokens: 16384
        image: true
        cost_input: 2.5
        cost_output: 10.0
      gpt-4o-mini:
        context_window: 128000
        max_output_tokens: 16384
        cost_input: 0.15
        cost_output: 0.6
  anthropic:
    kind: anthropic
    api_key_secret: codelab/anthropic
    models:
      claude-sonnet-4:
        name: Claude Sonnet 4
        context_window: 200000
        max_output_tokens: 64000
        image: true
        reasoning: true
  ollama:
    kind: openai-compatible
    base_url: http://localhost:11434/v1
    idle_timeout: 300s
    models:
      "llama3.1:70b":
        context_window: 32768
        max_output_tokens: 8192

permissions:
  mode: standard
  deny:
    - "exec:git push --force"
    - "write:.env"
  tools:
    update_plan: allow
    mcp__github__create_issue: ask

budget:
  max_steps: 50
  max_cost: 2.0

compaction:
  enabled: true
  keep_recent_user_turns: 1

tools:
  output:
    max_lines: 2000
    max_bytes: 51200
  web:                         # после MVP (§17.1.6)
    search:
      backend: brave
      backends:
        brave:
          preset: brave
          api_key_secret: codelab/search-brave
  spill:                       # этап 3 (§17.4.8)
    head_lines: 120
    tail_lines: 120

exec:
  default_timeout: 120s
  secrets:
    - {env: GITHUB_TOKEN, secret: github/token}
  env:
    PUB_CACHE: /Users/me/.pub-cache

mcp:
  servers:
    - name: github
      type: http
      url: https://api.githubcopilot.com/mcp
      headers:
        Authorization: "Bearer ${GITHUB_TOKEN}"
    - name: filesystem
      type: stdio
      command: npx
      args: ["-y", "@modelcontextprotocol/server-filesystem", "${HOME}/notes"]

sessions:
  fsync: checkpoints

logging:
  level: info
  trace: true

profile:
  agent-serve:
    mcp: [http]

# после MVP (§17)
llm:
  roles:
    smol:
      models: [openai/gpt-4o-mini]
    vision:                    # разбор изображений inspect_image (§17.11.5)
      models: [openai/gpt-4o]

skills:
  extra_roots: ["~/.claude/skills"]
  operative:
    lines: ["Run dart format before finishing."]

subagents:
  max_concurrent: 2

jobs:
  max_running: 4
```

Ключи из разных разделов и этапов (`tools.spill` — этап 3, `tools.web` — после MVP) живут в том же отображении
`tools:`, что и ключи MVP: второй `tools:` на верхнем уровне — ошибка повторяющегося ключа (§15.5).

```yaml
# /Users/me/work/demo/.codelab/config.yaml (проектный, коммитится)
agent:
  default_model: anthropic/claude-sonnet-4

permissions:
  mode: ask                    # ужесточение разрешено

compaction:
  context_window_cap: 100000
```

## 15.10. Инварианты

1. **CFG-1.** Неизвестный ключ, неверный тип и незаданная переменная в `${…}` — ошибка при старте с файлом, строкой, столбцом и путём ключа.
2. **CFG-2.** Ключ API не хранится в конфиге значением; только `api_key_env` или `api_key_secret`.
3. **CFG-3.** Проектный конфиг без доверия не может расширить права агента: разрешающие правила, MCP-серверы, провайдеры и промпты из него игнорируются с предупреждением; режим одобрения — только ужесточается.
4. **CFG-4.** `autopilot` включается только флагом запуска.
5. **CFG-5.** Ядро получает только провалидированный `CoreConfig` и не читает файлы конфига; разборщики YAML и TOML (`yaml`, `yaml_edit`, `toml`) живут только в `codelab_agent_io`.
6. CFG-6 … CFG-8 — определения агентов, §15.8.
7. CFG-9 … CFG-19 — секреты, предконфигурация, запись и живая перезагрузка конфига, MCP-супервизор, реестр настроек (после MVP), §17.5.11.
8. **CFG-20.** Агент и клиенты пишут конфиг только в YAML. Устаревший `codelab.toml` читается только при отсутствии YAML-файлов слоёв 2–4 и `--config`, через ту же таблицу соответствия, что `config migrate`, с той же строгостью (неизвестный ключ или провайдер — ошибка, не mock); при любом YAML-файле он игнорируется с одним предупреждением `config.legacy_ignored`; пока он активен, любая запись конфига отклоняется `ConfigLegacyReadOnlyException`; `config migrate` не меняет и не удаляет `codelab.toml`.
9. **CFG-21.** Конфиг и YAML-frontmatter разбираются в одном профиле (§15.5): один документ, без якорей, ссылок, ключей слияния и тегов, ключи — только строки и без повторов, логические — только `true` и `false`; нарушение — ошибка с файлом, строкой и столбцом, а не тихое значение.

## 15.11. Обоснование решения

* **Строгость.** Опечатка в имени ключа в Python-конфиге молча давала значение по умолчанию;
  строгий разбор превращает её в понятную ошибку при старте.
* **Ограниченное доверие к проекту.** Конфиг в репозитории — недоверенный ввод, такой же, как
  файл с prompt injection: он не должен включать MCP-серверы (это запуск произвольных программ)
  или разрешать команды без вопроса.
* **Ключи только из env и keychain.** Конфиги копируют, коммитят и прикладывают к отчётам об
  ошибках; ключ в них рано или поздно утечёт.
* **YAML, а не TOML.** Frontmatter определений агентов и skills уже YAML; один разборщик и один
  профиль для конфига и frontmatter — одна модель ошибок и одни тесты. Для YAML в Dart есть
  разборщик с позициями узлов (`package:yaml`) и редактор с сохранением комментариев и порядка
  (`package:yaml_edit`), поэтому писателю (§17.5.5) не нужен собственный построчный редактор.
  Строгий профиль снимает известные ловушки YAML: `no`/`off` как логическое значение, скрытые
  связи через якоря, повторяющиеся ключи, которые молча перекрывают друг друга.
* **Устаревший файл — только чтение, перевод — командой.** Пользователь Python-агента запускает
  новый агент без подготовки: его `codelab.toml` читается через ту же таблицу, что и
  `config migrate`, поэтому чтение и миграция не расходятся. Половина старых ключей не
  действовала или меняет смысл: предупреждения при чтении и комментарии миграции показывают, что
  отброшено. Запись в TOML потребовала бы второго писателя и второго формата навсегда; запрет
  записи до миграции не даёт первому `config.yaml` молча отключить настройки из `codelab.toml`.

## 15.12. Как проверить

* Табличные тесты валидатора: неизвестный ключ с подсказкой, неверный тип, `api_key`, `autopilot` в конфиге, запись `exec.secrets` строкой вместо `{env, secret}` и `env: github_token` (не `^[A-Z_][A-Z0-9_]*$`) (CFG-1, CFG-2, CFG-4).
* Тест слияния: списки заменяются, элементы `mcp.servers` сливаются по `name`, `enabled: false` выключает.
* Тест доверия: проектный конфиг с `mcp.servers` и `permissions.tools` = `allow` без `trusted_projects` → предупреждения, серверов и правил нет; с доверием — есть (CFG-3).
* Тесты подстановки: `${VAR}`, `$${`, `$VAR` как литерал, незаданная переменная — ошибка, подстановка вне разрешённых ключей — литерал.
* `config_yaml_profile_test.dart` (`codelab_agent_io`): якорь и ссылка, `<<: *base`, тег `!!str`, второй документ, ключ `1:` и составной ключ, повторяющийся ключ (обе позиции в сообщении) → `ConfigException` со строкой и столбцом; `compaction.enabled: yes`, `on`, `off` → ошибка типа с подсказкой `use true or false`, а `shell_exec: off` в `profile.*` — строка; `"30s"` и `30s` равны; `output.max_lines: 2000` внутри `tools:` → неизвестный ключ с подсказкой вложенной формы; `key:` без значения → ошибка типа; пустой файл и файл из комментариев → пустой слой; flow-стиль и CRLF читаются так же, как блочный стиль и LF (CFG-21).
* `config_validator_positions_test.dart` (ядро): `ConfigTree` с позициями → `ConfigIssue` со строкой и столбцом; тот же слой без позиций (хранилище приложения) → сообщение с источником и путём ключа без строки (CFG-1).
* `agent_definition_parse_test.dart` и `skill_parse_test.dart` дополнены: якорь во frontmatter и `disable-model-invocation: yes` → ошибка по профилю §15.5 (CFG-21).
* `config_reads_legacy_codelab_toml_test.dart` — критерий **`core/config-reads-legacy-codelab-toml`** (R-16): только `codelab.toml` с `[llm.providers.local]`, `[[mcp.servers]]` и `api_key = "${API_KEY}"` → провайдер с ключом из окружения и MCP-сервер, предупреждения `config.legacy_key_dropped` для `temperature`, подсказка `config migrate`; неизвестный провайдер `foo` → `ConfigException("llm.providers.foo: неизвестный провайдер")`, агент не стартует; неизвестный ключ → ошибка с путём и строкой; `[agents.definitions.reviewer]` → ошибка с подсказкой о Markdown (DF-12); литеральный ключ → `ConfigInlineSecretException` без значения; `<cwd>/codelab.toml` с `mcp.servers` без доверия → предупреждение, сервера нет (CFG-3).
* `config_legacy_ignored_test.dart`: есть `$CODELAB_HOME/config.yaml` и `codelab.toml` → действует только YAML, ровно одно предупреждение `config.legacy_ignored`; появление `config.yaml` при живом агенте → перезагрузка переключает источник (CFG-20).
* `config_writer_legacy_test.dart`: при активном `codelab.toml` `ConfigWriter.apply` в каждый слой → `ConfigLegacyReadOnlyException`, ни одного файла не создано; байты `codelab.toml` не изменились (CFG-20).
* Golden-тест `config migrate` на `codelab.toml.example` Python-агента: результат — `config.yaml`, совпадающий с golden, проходит валидацию, каждый отброшенный ключ упомянут YAML-комментарием; `--print` ничего не пишет; существующая цель → код 1, ничего не записано; `codelab.toml` после команды побайтово тот же (CFG-20).
* После MVP: `config_sessions_test.dart` — `sessions.lease.stale_after < 3 × heartbeat` → `ConfigException`, `sessions.lease` в проектном конфиге игнорируется с предупреждением (§17.6.16); `config_steering_test.dart` — `yield_long_tools: true` при `jobs.enabled: false` → `ConfigException`, увеличение `steering.max_steps` в проектном конфиге без доверия отклонено, уменьшение принято (§17.7.11); `lsp_config_test.dart` — серверы из недоверенного проекта игнорируются, одно расширение у двух серверов → `ConfigException` (§17.8.14); `config_jobs_test.dart` (§17.9.16).
* `config_loop_test.dart`: диапазоны `loop.empty_response_retries` и `loop.misuse.*`; `warn_after > block_after` → `ConfigException` (C-07, C-08).
* Тест-сторож: `codelab_agent_core` не импортирует `package:yaml`, `package:yaml_edit` и `package:toml`; `package:toml` импортируется только из `codelab_agent_io/lib/src/config/legacy/` (CFG-5).

---

← [14. Формат golden ACP-фикстур](14-golden-fixtures.md) · [Оглавление ядра](../agent-core-architecture.md) · [16. Что не входит в MVP и открытые вопросы](16-non-mvp-and-open-questions.md) →
