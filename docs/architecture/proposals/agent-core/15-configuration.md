# 15. Конфигурация

> Часть [архитектуры ядра агента CodeLab](../agent-core-architecture.md). Status: Accepted. Общие соглашения, термины и порядок чтения — в оглавлении.

← [14. Формат golden ACP-фикстур](14-golden-fixtures.md) · [Оглавление ядра](../agent-core-architecture.md) · [16. Что не входит в MVP и открытые вопросы](16-non-mvp-and-open-questions.md) →

## 15.1. Назначение

Конфигурация задаёт провайдеров и модели, режим одобрения, бюджет хода, сжатие, MCP-серверы,
лимиты инструментов, окружение команд и сужение профиля. Формат — YAML 1.2 в строгом профиле
(§15.5, «Профиль YAML»); это единственный формат, который агент и клиенты читают и пишут.
`codelab.toml` Python-агента не читается: агент только предупреждает, что нашёл его, а перенос
настроек делает пользователь вручную (§15.7, решение пользователя 2026-10-29).
Конфиг читает **хост** (`apps/codelab_agent`, `codelab_embedded`) через `ConfigLoader` из
`codelab_agent_io`. Там же два разборщика: `package:yaml` — чтение YAML с позициями узлов для
сообщений об ошибках (тот же разборщик и тот же профиль читают frontmatter определений агентов,
§15.8, и skills, §17.2.2); `package:yaml_edit` — запись с сохранением форматирования (§17.5.5;
в зависимости пакета появляется вместе с первой записью конфига, не в этапе 8.5). Схема и
валидатор — чистая функция ядра `CoreConfig.fromLayers(List<ConfigTree>)` над уже разобранным
деревом и позициями его узлов: мобильный и web-хосты передают ей настройки из хранилища
приложения (без позиций) и получают ту же проверку. Ядро получает готовый провалидированный
`CoreConfig` (§10.3), файлов не читает и разборщиков YAML не импортирует (CFG-5). Любая ошибка конфига — отказ при старте
с указанием файла, строки, столбца и ключа, а не тихое значение по умолчанию.

```dart
/// Вид слоя: порядок и правила доверия (§15.2, §15.3).
enum ConfigLayerKind { defaults, user, project, projectLocal, extra, environment, flags, appStorage }

/// Разобранный слой конфига (codelab_agent_core/lib/src/config/config_tree.dart).
final class ConfigTree {
  final ConfigLayerKind kind;
  final String source;                         // путь файла, "defaults", "env", "flags", "app-storage"
  final Map<String, Object?> values;           // ключи — только String; значения — String, int, double, bool, List, Map
  final Map<String, ConfigPosition> positions; // путь ключа ("mcp.servers[github].url") → позиция; пусто — без строк
}
final class ConfigPosition { final int line, column; }   // нумерация с 1, как у package:yaml + 1
```

Результат проверки — `ConfigLoadResult {config, host, issues, warnings, sources}` (§17.5.2).
`ConfigIssue.kind` (`syntax | profile | unknownKey | type | value | inlineSecret | semantic`)
даёт тестам и `ConfigInlineSecretException` класс проблемы без разбора текста. Ключи, которые
читает хост, а не ядро (`sessions.dir`, `sessions.fsync`, `logging.level`, `logging.file`,
сужение `profile.<name>.*`), лежат в `HostSettings` результата, а не в `CoreConfig`.

## 15.2. Расположение и приоритет

От низшего приоритета к высшему (позднее перекрывает раннее):

| # | Источник | Путь | Кто пишет |
|---|---|---|---|
| 1 | встроенные значения по умолчанию | `ConfigLoader` в `codelab_agent_io` | разработчики |
| 2 | глобальный конфиг | `$CODELAB_HOME/config.yaml` (по умолчанию `~/.codelab/config.yaml`) | пользователь |
| 3 | проектный конфиг | `<cwd>/.codelab/config.yaml` | репозиторий (коммитится) |
| 4 | локальный проектный конфиг | `<cwd>/.codelab/config.local.yaml` | пользователь (обычно в `.gitignore`); пока проект не в `trusted_projects`, подчиняется тем же правилам доверия, что слой 3 (§15.3) |
| 5 | переменные окружения `CODELAB_*`; после MVP — первой в слое предконфигурация провайдера `CODELAB_PROVIDER_*` (§17.5.3) | §15.6 | окружение запуска |
| 6 | флаги командной строки | §15.6 | запуск |

`CODELAB_HOME` — корень глобального состояния: конфиг, сессии (§8.9), логи. По умолчанию
`~/.codelab`; на мобильных платформах и web — каталог документов приложения (задаёт хост).

Слияние: отображения (mapping) сливаются по ключам рекурсивно; скалярные значения и списки
заменяются целиком (список `fallback` из проектного конфига не дописывается к глобальному, а
заменяет его); список `mcp.servers` сливается по `name`: сервер с тем же `name` заменяется, новый
добавляется, `enabled: false` в более приоритетном файле выключает сервер. Исключение: `tools.disabled`
слоёв 2–4 объединяется, а не заменяется (§6.3.8). В проектных слоях недоверенного проекта (§15.3) `permissions.deny` объединяется со списком нижних слоёв, а `permissions.tools.<t>` применяется, только если не мягче значения нижних слоёв (`deny` > `ask` > `allow`; равное применяется): недоверенный проект не снимает глобальные запреты; после MVP так же объединяется `tools.mounted`
(§17.11.10). После MVP списки `hooks.before_tool` и `hooks.after_tool` сливаются по `name`, как
`mcp.servers` (§17.14.2.4).

Файлы `codelab.toml` Python-агента в этой таблице отсутствуют: агент их не читает. Если нет ни
одного YAML-файла слоёв 2–4 и не задан `--config`, загрузчик пишет одно предупреждение
`config.legacy_found` (§15.7).
Дополнительный слой 4а — `--config <path>` / `CODELAB_CONFIG` — читается всегда, когда задан,
и не подчиняется правилам доверия §15.3: файл назвал тот, кто запускает агента. Поэтому
`CODELAB_CONFIG` — только абсолютный путь (относительный — ошибка использования: переменная
переживает смену каталога, и путь от корня склонированного репозитория обошёл бы доверие), а
`--config` может быть относительным и разрешается от текущего каталога процесса. Явно названный, но
отсутствующий файл — проблема конфига `cannot read the file` (источник `--config` или
`CODELAB_CONFIG`), а не пропуск; отсутствующие слои 2–4 пропускаются (change
`add-agent-configuration`, D4).

## 15.3. Доверие к проектному конфигу

Проектный конфиг приходит из репозитория, который пользователь мог только что склонировать.
Поэтому слои 3 и 4 ограничены. Оба слоя лежат в дереве проекта, и репозиторий может принести и
`config.local.yaml`; поэтому, пока проект не в `trusted_projects`, слой 4 подчиняется тем же
правилам, что слой 3 (столбец «Слой 3»), а столбец «Слой 4» действует только для доверенного
проекта (решение пользователя 2026-10-30, change `add-agent-configuration`, D7). Сравнение «только уменьшение», «не мягче», «ужесточение» — с результатом
слияния нижних слоёв; смягчение отбрасывается с предупреждением `config.project.untrusted_key`.

| Ключи | Слой 3 (проект) | Слой 4 (локальный) | Условие снятия ограничения |
|---|---|---|---|
| `agent.default_model`, `compaction.*`, `budget.*` (только уменьшение), `tools.output.*` | да | да | — |
| `permissions.mode` | только ужесточение: итоговый режим — `narrow(режим нижних слоёв, режим проекта)` (§7.3.1, как у субагента §17.3.3, шаг 4): `bypass → accept-edits → standard → ask`; `plan` добавляет запреты `write`/`exec` к режиму нижних слоёв: `ask` + `plan` и `plan` + `ask` → `ask` с дополнительно запрещёнными уровнями `write`/`exec` (`PermissionsConfig.extraDeniedTiers`, §7.3.1) | да | — |
| `permissions.deny` | да — объединяется с нижними слоями | да | — |
| `permissions.tools.<t>` со значением не мягче нижних слоёв (`deny` > `ask` > `allow`; равное применяется) | да | да | — |
| `permissions.tools.<t>` мягче нижних слоёв | нет | да | проект в `trusted_projects` |
| `mcp.servers` | нет (игнорируется с предупреждением) | да | проект в `trusted_projects` |
| `providers.*` (адреса, заголовки) | нет | да | проект в `trusted_projects` |
| `prompts.*` (включая `append_system`, `append_system_text`, §11.6.1) | нет | да | проект в `trusted_projects` |
| `loop.*` (C-07, C-08), кроме ключей `loop.final_response.*` из строк §17.12 | да | да | — |
| `tools.disabled` (T-26) | да — только добавляет (объединение слоёв, §6.3.8) | да | — |
| `tools.project_context.max_bytes` | да — только уменьшение (как `budget.*`; design.md change `add-agent-project-files`, D5) | да | увеличение — проект в `trusted_projects` |
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
| `secrets.*` (с этапа 8.9, §17.5.9; change `add-agent-secret-store`, D7) | нет | нет | только пользовательский конфиг и `--config`/`CODELAB_CONFIG`; из обоих проектных слоёв отбрасывается всегда с `config.project.untrusted_key` (`ignored: secrets is read only from the global config`) |
| `config.*` (после MVP) | нет | да | — |
| `${secret:<name>}` в `headers`, `env` (с этапа 8.9, §17.5.4) | нет: `providers` и `mcp.servers` недоверенного проекта отбрасываются целиком, ссылка до резолвера не доходит (change `add-agent-secret-store`, D4) | да | проект в `trusted_projects` |
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

`trusted_projects` — массив только абсолютных путей (`~` раскрывается; относительный — ошибка
`expected an absolute path` на `trusted_projects[i]`) в **глобальном** слое (`user` или `appStorage`).
Загрузчик канонизирует корень проекта и каждый элемент `trusted_projects` (symlink раскрыт;
несуществующий путь — нормализованная запись), а runtime так же канонизирует `cwd` сессии перед
выбором снимка (§10.3): иначе один каталог, записанный через symlink и напрямую, получал бы разное
доверие и разные запреты;
в проектных слоях ключ отбрасывается с предупреждением `config.project.untrusted_key`
(`ignored: trusted_projects is read only from the global config`), а в слое `--config` — ошибка. Ключ из слоя 3 (и из слоя 4 недоверенного проекта), который
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
| `api_key_env` | string | нет | имя переменной окружения с ключом (`[A-Za-z_][A-Za-z0-9_]*`, иначе `expected an environment variable name`) |
| `api_key_secret` | string | нет | имя секрета (правило `SecretNames`, §17.5.2); значение читает `SecretResolver` при первом запросе к провайдеру, а не загрузка (этап 8.9; change `add-agent-secret-store`, D2, D4) |
| `auth_header` | string | `Authorization` (Bearer) / `x-api-key` | имя заголовка ключа |
| `headers` | map string→string | `{}` | дополнительные заголовки; допускают `${ENV}` и с этапа 8.9 — `${secret:<name>}` (шаблон, раскрывается при первом запросе; §15.5, п. 7; §17.5.4) |
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

Ключ API **нельзя** писать в конфиг значением: ключ `api_key` — проблема `inlineSecret`, у хоста —
`ConfigInlineSecretException` (`suggestedSecretName`, с этапа 8.9) с текстом
`providers.openai.api_key: secrets are not stored in the config; run: codelab secret set
codelab/openai, then use api_key_secret: codelab/openai (or api_key_env with an environment
variable)`.
Без `api_key_env` и `api_key_secret` запросы идут без ключа (локальные Ollama, LM Studio).
Провайдер `cli` из флагов (`--provider`, §15.6) получает `api_key_env: CODELAB_API_KEY`, только
если переменная задана и непуста, а слой флагов заменяет `providers.cli` целиком: `headers` и
ссылки на ключ одноимённого провайдера из файлов не уходят на адрес `--base-url`
(change `add-agent-configuration`, D4).
`api_key_env` и `api_key_secret` взаимоисключающие: оба сразу — `ConfigException`. Кроме
`api_key` отклоняются ключи `apiKey`, `token`, `secret`, `password` в `providers.*` и в элементах
`mcp.servers` (CFG-9, п. 1, §17.5.4; подсказка `codelab secret set <name>` с именем
`SecretNames.suggestFor` — с этапа 8.9); в `tools.web.search.backends.*` — вместе с инструментом
поиска (§17.1.6). Литеральные значения `headers.*` и `mcp.servers.*.env.*`, похожие на ключ по
шаблонам §12.4, и ключ, вписанный в `api_key_env`/`api_key_secret` вместо имени (CFG-9, п. 2–3), —
8.11; до него ключ вместо имени чаще всего отсекает формат имени (§17.5.4).

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
| `thinking_mode` | `"adaptive"` \| `"budget"` | нет (§2.12.2; безопасное значение `adaptive`) | форма рассуждения у Anthropic: `budget` — для Claude 4.5 и старше (§2.8, §2.12.3) |
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
| `project_context.max_bytes` | int | `32768` | общий бюджет файлов контекста проекта (§11.5), `0..262144`; `0` — контекст не читается (design.md change `add-agent-project-files`, D5) |
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
| `command`, `args`, `env` | string, string[], map string→string | — | для `stdio`; `${ENV}` допустим в `args` и значениях `env`; с этапа 8.9 в значениях `env` — и `${secret:<name>}` (раскрывается перед подключением; в `args` — проблема конфига, §15.5, п. 7; §17.5.4) |
| `url`, `headers` | string, map string→string | — | для `http`; `${ENV}` допустим; с этапа 8.9 в значениях `headers` — и `${secret:<name>}` (в `url` — проблема конфига, §15.5, п. 7) |
| `enabled` | bool | `true` | выключение сервера без удаления |
| `connect_timeout` | duration | `"10s"` | подключение при создании сессии |
| `call_timeout` | duration | `"10m"`; допустимо `1s..24h`, иначе ошибка | срок одного вызова `tools/call` этого сервера; `McpClientConnector` берёт `server.callTimeout ?? options.callTimeout` (change `add-agent-configuration`, D10). У серверов из `session/new` ключа нет: в ACP такого параметра нет, у них действует умолчание коннектора |

Другой `type` (`sse`, `websocket` и т. п.) в конфиге — ошибка: `mcp.servers[<name>].type: only stdio
and http are supported`. В `session/new` неизвестный тип сервера пропускается, а конфиг — файл
самого пользователя, и опечатка в нём не должна молча отключать сервер (CFG-1).

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

**`secrets`** (с этапа 8.9, §17.5.4; change `add-agent-secret-store`, D7) — только пользовательский
конфиг и `--config`/`CODELAB_CONFIG`; из проектных слоёв отбрасывается (§15.3), поэтому репозиторий
не может переключить агента на открытый файл. Потребитель — хост (`HostSettings.secretsBackend`).

| Ключ | Тип | По умолчанию | Смысл |
|---|---|---|---|
| `backend` | `"auto"` \| `"keychain"` \| `"env"` \| `"file"` | `"auto"` | хранилище секретов. В 1.0: `auto` — `env` на всех ОС, без проб и процессов, `file` не выбирает никогда (CFG-11); `env` — только переменные `CODELAB_SECRET_<…>`; `file` — открытый `$CODELAB_HOME/secrets.yaml` с правами `0600`, на Windows — проблема конфигурации `file backend is not supported on Windows; use env with CODELAB_SECRET_* variables` (добавляет `ConfigLoader`, D7, D14); `keychain` — проблема конфигурации `secrets.backend: keychain is not supported yet (supported: auto, env, file)`, значение остаётся в схеме для хранилищ ОС после 1.0 (черновик `add-agent-os-secret-backends`, D13). Другое значение — проблема `value` `expected one of: auto, keychain, env, file` |

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
`<name>` — только встроенные профили (§10.4), другое имя — `unknownKey`; неизвестная capability —
`unknownKey`, capability после MVP — `config.key.not_applied`. Расширение — `HostWiringException`,
который загрузчик переводит в ошибку с ключом `profile.<name>.<capability>` (ревью итерации 1
change `add-agent-configuration`).

## 15.5. Алгоритм загрузки и валидации

```text
loadConfig(cwd, env, flags):
1. layers := [defaults]
2. для пути в [global, project, projectLocal, flags.config?]:
     если файла нет: слои global, project, projectLocal → пропустить;
       явно названный flags.config (--config / CODELAB_CONFIG) → ConfigIssue(syntax,
       "cannot read the file", источник --config | CODELAB_CONFIG); CODELAB_CONFIG только
       абсолютный (относительный — ошибка использования хоста до загрузки)
     файл больше 1 MiB → ConfigIssue(syntax) без разбора
     иначе разобрать YAML (codelab_agent_io, package:yaml)
     и проверить профиль YAML (ниже) → ConfigTree(values, positions)
     синтаксическая ошибка или нарушение профиля → ConfigIssue(syntax | profile, путь, строка,
       столбец, сообщение) в результате загрузки (ConfigLoadResult.issues), а не исключение;
       исключение ConfigException бросает только ConfigLoadResult.orThrow() у хоста
     config.yml рядом с config.yaml не читается: предупреждение config.file.ignored
       {path, hint} с подсказкой переименовать файл (читать оба — значит выбирать между ними)
   ни одного YAML-файла не найдено и --config не задан → проверка наличия codelab.toml,
     auth.toml, codelab.local.toml (§15.7) без чтения: найден хотя бы один → одно
     предупреждение config.legacy_found {files} на процесс и cwd; YAML найден → предупреждения нет
3. для каждого слоя: validateKeys(layer, schema)          // строгость, ниже; позиции — из positions
     встроенные секреты (CFG-9, п. 1, §17.5.4): ключи api_key, apiKey, token, secret, password в
       providers.* и mcp.servers → проблема inlineSecret (orThrow — ConfigInlineSecretException);
       литералы по шаблонам §12.4 (п. 2–3) — 8.11
4. для слоёв 3–4: применить правила доверия §15.3
5. merged := merge(layers) по правилам §15.2
6. interpolate(merged)                                    // ${ENV}; ${secret:<name>} — шаблон без чтения (с 8.9, D4); ниже
7. после MVP: слой предконфигурации envPreconfigLayer(env, flags) (§17.5.3) — первым в слое 5,
     с той же строгой проверкой шагов 3 и 6, без правил доверия
   applyEnv(merged, env); applyFlags(merged, flags)       // §15.6
8. семантическая проверка:
     default_model, fallback, summary_model (если задан) и после MVP llm.roles.*.models существуют в каталоге моделей
     у каждого openai-compatible провайдера есть base_url
     providers.<id>.kind — известный вид, иначе ошибка со списком видов (подмены mock нет, DF-15)
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
9. вернуть ConfigLoadResult (§17.5.2): CoreConfig и HostSettings либо список проблем, плюс
   предупреждения (лог host.config.loaded)
```

**Строгая валидация.** Неизвестный ключ в любом отображении — `ConfigException` с путём ключа и
подсказкой ближайшего известного (расстояние Левенштейна ≤ 2):
`config.yaml:12:3: compaction.reserve_token: unknown key (did you mean reserve_tokens?)`.
Неверный тип — ошибка с ожидаемым типом. Исключения: отображения, чьи ключи — имена
(`providers`, `models`, `headers`, `env`, `profile`, после MVP — `tools.web.search.backends`,
`lsp.servers`, `lsp.servers.*.language_ids`, `a2a.agents`), проверяются по формату имени; значения
`lsp.servers.*.initialization_options` и `settings` — любые JSON-совместимые и не проверяются; ключи `llm.roles` — по фиксированному списку ролей; после MVP `plugins.<name>.*` проверяет
`buildAgentCore` по `CodelabPlugin.settings` (§17.14.3.3). Строка и столбец
берутся из `ConfigTree.positions`; у слоя без позиций (хранилище приложения, окружение, флаги)
сообщение называет источник и путь ключа без строки.

**Ключи без потребителя (`config.key.not_applied`).** Ключ, который есть в схеме §15.4, но которого
пока никто не читает (на этапе 8.5: `tools.*`, `loop.*`, `exec.*`, `prompts.*`, `agent.fallback`,
`agent.summary_model`, `permissions.timeout`, `model_catalog.*`, `providers.*.list_models*`,
`logging.trace*`, `redact.*` и др.), проверяется по схеме, а явно заданный даёт одно предупреждение
`config.key.not_applied {key, source}` на каждый явно заданный лист за загрузку; значение по умолчанию предупреждения не
даёт. Раздел верхнего уровня «после MVP» (`llm`, `images`, `skills`, `subagents`, `jobs`, `hooks`,
`plugins`, `a2a`, `memory`, `steering`, `lsp`, `secrets`, `config` и др.) распознаётся по имени и
даёт то же предупреждение без проверки типов: его схему введёт change, который добавит потребителя.
Ключ, которого нет ни в схеме, ни в списке разделов после MVP, — `unknownKey` (CFG-1). Ошибка на
документированном ключе сломала бы старт пользователю, который следует документу, а тихий приём
противоречил бы CFG-1; предупреждение называет ключ и источник и запуск не ломает. Разделы
`prompts.*`, `hooks`, `plugins`, `a2a`, `lsp` из проектных слоёв недоверенного проекта и `secrets` из
проектных слоёв любого проекта дают не `config.key.not_applied`, а `config.project.untrusted_key` и
отбрасываются (§15.3).

**Профиль YAML.** Конфиг — YAML 1.2 с семантикой core schema; ограничения проверяет
`codelab_agent_io` при разборе, до валидатора ядра, и каждое нарушение — `ConfigIssue` вида
`profile` (синтаксис — `syntax`) с файлом, строкой и столбцом узла в результате загрузки:

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
9. Пределы: файл не больше 1 MiB (иначе проблема `syntax` без разбора); вложенность отображений и
   списков не глубже 64 уровней (иначе проблема профиля в позиции узла; разбор не падает
   переполнением стека). Тег или якорь на корне документа — нарушение п. 2, нестандартный тег —
   тоже, и текст проблемы не содержит имени тега.

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
4. Переменная не задана → ошибка `mcp.servers[github].headers.Authorization: variable GITHUB_TOKEN is not set`.
   Пустая строка вместо отсутствующей переменной — источник тихих отказов авторизации.
5. Результат подстановки повторно не раскрывается.
6. Значения, полученные подстановкой в `headers` и `env`, добавляются в набор точных секретов
   редактора (§12.4).
7. С этапа 8.9 (§17.5.4; change `add-agent-secret-store`, D2, D4): в значениях
   `providers.*.headers.*`, `mcp.servers.*.headers.*` и `mcp.servers.*.env.*` допустима форма
   `${secret:<name>}`, где `<name>` проходит правило `SecretNames` (§17.5.2); неверное имя —
   проблема `value` с путём ключа на загрузке, текст называет правило, а не значение.
   `${secret:…}` в остальных ключах с `${ENV}` — `mcp.servers.*.args[*]`, `mcp.servers.*.url`,
   `providers.*.base_url` — проблема `value` `secret references ${secret:…} are allowed only in
   env and headers values`, конфиг невалиден: argv виден через `ps`, а URL попадает в логи и
   тексты ошибок, поэтому ссылка не раскрывается и не остаётся молчаливым литералом. Загрузка
   секрет не читает: значение с `${secret:…}` хранится **шаблоном** `SecretTemplate` — списком
   частей «литерал» и «ссылка», уже после раскрытия `${ENV}` и `$${`. Строкой его хранить нельзя:
   литерал `$${secret:x}` после раскрытия неотличим от ссылки и раскрылся бы повторно (п. 5). У
   провайдера шаблоны лежат в `CatalogProvider.headerTemplates`, у MCP-сервера конфига — в
   `McpServerConfig.secretValues`. Значение берёт `SecretResolver`: у провайдера — при первом
   запросе, у MCP-сервера конфига — перед подключением к сессии. Ненайденный секрет: провайдер —
   ошибка хода класса `auth` без HTTP-запроса (`… is not set. Run: codelab secret set <name>`),
   MCP-сервер — `mcp.server.failed {server, transport, reason}` с причиной `secret <name> is not
   set`, сессия создаётся без него; заголовки после раскрытия идут в порядке файла. `${secret:…}` в серверах `session/new.mcpServers` от клиента ACP — литерал: иначе клиент
   мог бы вытянуть любой секрет хранилища на свой адрес. Недоверенный проект до резолвера ссылку
   не доводит: его `providers` и `mcp.servers` отбрасываются целиком (§15.3).

## 15.6. Переменные окружения и флаги

| Переменная | Флаг | Ключ |
|---|---|---|
| `CODELAB_HOME` | — | корень состояния; по умолчанию `~/.codelab`. Значение `~` или `~/…` (тильду не раскрыла оболочка: unit launchd/systemd, `env` профиля, кавычки) раскрывается в домашний каталог — `HOME`, иначе `USERPROFILE`, — тем же правилом, что `trusted_projects` (§15.3). Прочие формы с `~` в начале (`~user/…`, `~\…`) — ошибка использования `CODELAB_HOME: ~user is not supported, use an absolute path`, код `64`; `~`/`~/…` без домашнего каталога — ошибка использования `CODELAB_HOME: cannot expand ~ without HOME or USERPROFILE, use an absolute path`, код `64`; одинаково у агента и CLI. Пустое значение — как незаданное. Со сценарием `--llm-script` `$CODELAB_HOME` не читается, поэтому значение не раскрывается и не проверяется (кода `64` нет, D16). Одно правило у `codelabHomeOf` (агент) и `CodelabHome` (CLI) (change `add-agent-project-files`, D17) |
| `CODELAB_CONFIG` | `--config <path>` | дополнительный файл (слой 4а) с приоритетом выше слоя 4, флаг сильнее переменной; расширение `.yaml` или `.yml`, иначе ошибка использования; для `.toml` — `--config needs a .yaml file; codelab.toml is not supported, see agent-core-architecture §15.7` (без подсказки `migrate`: команды нет). `CODELAB_CONFIG` — только абсолютный путь (относительный — ошибка использования, текст называет переменную); `--config` может быть относительным — от текущего каталога процесса. Отсутствующий файл — проблема конфига `cannot read the file`, код `64` (§15.2) |
| `CODELAB_MODEL` | `--model <provider/model>` | `agent.default_model`; без `--provider` выбирает модель из конфига, а `--model gpt` без косой черты — ошибка использования `--model needs <provider>/<model> without --provider`; повтор `--model` без `--provider` — ошибка использования `--model can be repeated only together with --provider`. Нет модели ни во флагах, ни в конфиге, ни в `--llm-script` — проблема `agent.default_model: required`, код `64` |
| — | `--provider <openai-compatible\|anthropic>` (с этапа 4) | провайдер из флагов с id `cli`: `providers.cli.kind`; с ним `--model <model>` — id модели этого провайдера (`agent.default_model = "cli/<model>"`), флаг можно повторять: первое значение — модель по умолчанию, все — модели `providers.cli.models`. Слой флагов заменяет `providers.cli` из файлов целиком, а не сливается с ним по полям (§15.4) |
| — | `--base-url <url>` (с этапа 4) | `providers.cli.base_url` |
| `CODELAB_API_KEY` | — (с этапа 4) | ключ провайдера `cli`: `providers.cli.api_key_env = "CODELAB_API_KEY"`, только если переменная задана и непуста (иначе провайдер без ключа, как Ollama и LM Studio на этапе 4); значение в флаги и логи не попадает |
| — | `--llm-script <file.json>` (с этапа 4, только тесты) | вместо провайдера — `ScriptedStreamFunction` из файла `{"llm": {...}}` формата §14.7; провайдер `scripted`, `--model` — его модели; слои 2–4 (`$CODELAB_HOME` и проектные файлы) не читаются — конфиг подаётся явно `--config`, окружением и флагами; в справке бинаря скрыт |
| — | `--sessions-dir <path>` (только тесты, только с `--llm-script`) | корень `JsonlSessionStore` сессий сценария вместо памяти: `loadSession` и `session/list` объявлены, `$CODELAB_HOME` не трогается; в справке бинаря скрыт (change `add-llm-script-session-store`). Со сценарием это единственный источник журнала: `sessions.dir` и `sessions.fsync` из `--config` не применяются и дают `config.key.not_applied {key, source}` (change `add-agent-configuration`, D4) |
| `CODELAB_PERMISSION_MODE` | `--permission-mode <mode>` | `permissions.mode` (`plan`, `ask`, `standard`, `accept-edits`, `bypass`); флаг допускает `autopilot` |
| `CODELAB_PROFILE` | `--profile <name>` | профиль хоста (`agent-serve` у бинаря) |
| `CODELAB_LOG_LEVEL` | `--log-level <level>` | `logging.level` |
| `CODELAB_LOG_FILE` | `--log-file <path>` | `logging.file`; флаг сильнее переменной, переменная сильнее конфига; путь в stdout — ошибка использования (§12.3.1) |
| `CODELAB_TOOLS` | `--tools <tool>=on\|off,…` (можно повторять) | `tools.disabled` по инструментам: `off` выключает, `on` возвращает выключенное слоями ниже; флаг применяется после переменной (§6.3.8, T-26) |
| — | `--system-prompt <text>` | `prompts.system_text` (перекрывает и `prompts.system`); вместе с `--system-prompt-file` — ошибка (§11.6.1, E-08) |
| — | `--system-prompt-file <path>` | `prompts.system` (перекрывает и `prompts.system_text`) |
| — | `--append-system-prompt <text>` | `prompts.append_system_text` (перекрывает и `prompts.append_system`) |
| `CODELAB_MAX_STEPS` | `--max-steps <n>` (`codelab-agent serve`, этап 8.5) | `budget.max_steps`; флаг — целое `≥ 1`, иначе ошибка использования; нечисловая переменная — проблема `budget.max_steps` |
| — | `--local-exec` | `exec.local_fallback = true` |
| — | `--cwd <path>` | `cwd` для `codelab -p` |
| — | `--role <role>=<provider/model>` (после MVP, L-10; можно повторять; в том числе `--role vision=<provider/model>`, §17.11.5) | `llm.roles.<role>.models = ["<provider/model>"]` на прогон |
| — | `--drain-timeout <duration>` (после MVP, только `codelab -p`, H-05) | `subagents.drain_timeout` (§17.3.9); `0` — не ждать |
| — | `--max-wakes <n>` (после MVP, только `codelab -p`, H-05) | `subagents.max_wakes` (§17.3.9); `0` — не будить |
| `CODELAB_PROVIDER_TYPE` | `--provider-type <kind>` (после MVP, L-25) | тип провайдера предконфигурации (§17.5.3) |
| `CODELAB_PROVIDER_CONFIG` | `--provider-config <json \| @путь>` (после MVP) | JSON провайдера предконфигурации; флаги затеняют обе переменные |
| `CODELAB_PROVIDER_CONFIG_BASE64` | — (после MVP) | тот же JSON в base64; вместе с `CODELAB_PROVIDER_CONFIG` — ошибка |
| `CODELAB_SECRET_<ИМЯ>` | — (с этапа 8.9, P-12; change `add-agent-secret-store`, D3) | переопределение секрета по имени, `SecretNames.envOverride` (§17.5.4): побеждает хранилище при любом `secrets.backend`; при `auto`/`env` в 1.0 — единственный источник секретов |
| `CODELAB_DEBUG_SECRETS=1` | `--debug-secrets` (с этапа 8.9, P-17, флаг `serve`; change `add-agent-secret-store`, D10, D11) | событие `secrets.lookup {name, purpose, source, found}` на каждое обращение, без значения, длины, префикса и хеша (CFG-10); уровень лога не меняет; другие значения переменной — как незаданная |
| — | `--debug-llm-snapshot[=headers\|body]` (после MVP, L-27) | `logging.llm_snapshot` |
| `CODELAB_DEBUG_LLM_SNAPSHOT` | — | `logging.llm_snapshot` |

**До этапа 8 действуют только флаги и переменные этой таблицы** (с этапа 8.5 бинарь читает и файлы
конфига; это абзац о прежнем минимуме). Бинарь `codelab-agent` этапа 4 файлы конфига (§15.2) не читает: провайдер, модель и ключ задаются `--provider`, `--base-url`,
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

## 15.7. Перенос настроек Python-агента

Пользователи Python-агента хранят настройки в `codelab.toml`. Dart-агент этот файл **не читает**:
не разбирает, не переводит и не пишет (решение пользователя 2026-10-29, change
`add-agent-configuration`, D12). Единственный формат конфига — YAML (§15.1). Чтобы пользователь не
потерял настройки молча, агент только предупреждает, что нашёл старые файлы, а перенос он делает
вручную по таблице ниже. Конфиг нового агента в TOML никогда не выпускался.

**Где ищутся файлы** — те же места, что у Python-агента (список путей; код Python-агента не
копируется). Проверяется только существование файла (`isFileSync`): содержимое и размер не читаются
и в лог не попадают, только пути.

| Файл | Куда переносить |
|---|---|
| `$CODELAB_HOME/codelab.toml` | `$CODELAB_HOME/config.yaml` (слой 2) |
| `$CODELAB_HOME/auth.toml` | тот же `$CODELAB_HOME/config.yaml`: ключи — только ссылками, см. таблицу |
| `<cwd>/codelab.toml` | `<cwd>/.codelab/config.yaml` (слой 3, правила доверия §15.3) |
| `<cwd>/codelab.local.toml` | `<cwd>/.codelab/config.local.yaml` (слой 4) |

`codelab.toml.example` не ищется никогда — это шаблон.

**Когда предупреждает.** Только если нет ни одного YAML-файла слоёв 2–4 и не задан `--config`
(шаг 2 §15.5): одно предупреждение `config.legacy_found {files}` на процесс и `cwd`. При любом
YAML-файле предупреждения нет: пользователь уже перешёл, повторять подсказку на каждом старте —
шум. С `--llm-script` файлы не ищутся (слои 2–4 не читаются, §15.6). Текст предупреждения:

```text
codelab.toml is not used by the Dart agent. Move the settings to config.yaml manually; the key mapping is in docs/architecture/proposals/agent-core/15-configuration.md, section 15.7. Also found: <other files>.
```

Хвост `Also found: …` печатается, только если найдено несколько файлов; первый файл — локация предупреждения, полный список — в поле `files` события.

`codelab-agent config check` и `codelab config check` печатают его строкой
`warning: <location>: <message>`, как любое предупреждение (`ConfigIssue.toString()` с префиксом
`warning: `). Локация — первый найденный файл; текст не повторяет путь, уже стоящий в локации, и
перечисляет только остальные найденные файлы, если они есть:

```text
warning: /work/demo/codelab.toml: codelab.toml is not used by the Dart agent. Move the settings to config.yaml manually; …
```

Код выхода от предупреждения не меняется, в счётчик `Config: invalid (issues: <n>)` оно не входит. Агент без `config.yaml` и без флагов провайдера
стартует с ошибкой `agent.default_model: required` (код `64`), и предупреждение стоит рядом в stderr.

**Как переносить.** Ключ из столбца «Новый ключ» записывается в `config.yaml` по схеме §15.4;
строки с прочерком не переносятся. Отдельных правил для старых ключей нет: файл `config.yaml`
проходит обычную строгую проверку (§15.5), поэтому неизвестный ключ, вид провайдера вне
`openai-compatible | anthropic | gemini` и определения агентов в YAML (`agents.definitions`, DF-12)
дают ошибку, а не подмену значением по умолчанию или провайдером `mock` (DF-15). Литеральный ключ API в
конфиг не переносят (CFG-2): `api_key = "${VAR}"` превращается в `api_key_env: VAR`, а литерал
хранится в переменной окружения или в хранилище секретов.

**Таблица соответствия** (для ручного переноса; своя запись схемы, не алгоритм чтения):

| Старый ключ | Новый ключ | Примечание |
|---|---|---|
| `[llm] provider`, `model` | `agent.default_model: "<provider>/<model>"` | модель всегда с префиксом провайдера: `openai/gpt-4o`, а не `gpt-4o` |
| `[llm] temperature` | — (не переносится) | в MVP температура не настраивается; модели с рассуждениями её не принимают |
| `[llm] max_tokens` | `providers.<id>.models.<m>.max_output_tokens` | для активной модели |
| `[llm.timeout] connect` | `providers.<id>.connect_timeout` | для каждого провайдера |
| `[llm.timeout] read` | `providers.<id>.idle_timeout` | смысл уже: пауза между событиями потока |
| `[llm.timeout] write`, `pool` | — | не нужны HTTP-клиенту Dart |
| `[llm.providers.<id>] api_key = "${VAR}"` | `api_key_env: VAR` | литеральный ключ не переносится: переменная окружения или хранилище секретов (CFG-2) |
| `[llm.providers.<id>] base_url` | `providers.<id>.base_url` | |
| `[llm.providers.<id>] default_model` | — | модель по умолчанию одна — `agent.default_model` |
| провайдеры `openai`, `openrouter`, `zen`, `go`, `ollama`, `lmstudio` | `kind: openai-compatible` | |
| провайдер `anthropic` | `kind: anthropic` | |
| провайдер `litellm` | `kind: openai-compatible`, `base_url` прокси | вызов библиотеки заменён прокси LiteLLM как OpenAI-совместимым эндпоинтом |
| провайдер `mock` | — (не переносится) | вида `mock` в `config.yaml` нет: `providers.<id>.kind: mock` — ошибка со списком видов (DF-15); для тестов есть `--llm-script` |
| `[llm.providers.<id>.models.<m>] context_window`, `max_output_tokens` | те же ключи | |
| `cost_per_input_token`, `cost_per_output_token` | `cost_input`, `cost_output` | умножить на 1 000 000 (цена за токен → за миллион) |
| `[llm.fallback] enabled`, `order` | `agent.fallback: [...]` | ключ проверяется, но до `ModelRoleResolver` не применяется (`config.key.not_applied`); `order` перечислял провайдеров, новый ключ — модели |
| `[llm.fallback] strategy`, `max_attempts`, `retry_on` | — | повторы задаются `transient_retries`, `rate_limit_retries` |
| `[agents] default_model` | `agent.default_model` | если отличается от `[llm]`, берут значение из `[agents]` |
| `[agents] context_window_limit` | `compaction.context_window_cap` | |
| `[agents] max_steps` | — | это шаги мультиагентной оркестрации, не хода; `budget.max_steps` задаётся отдельно |
| `[agents] strategy`, `fallback_strategy`, `slicer_*`, `max_sliced_tokens`, `debug` | — | разделы Python-рантайма: мультиагентности и Token-Slicing нет в MVP |
| `[agents.context]` | — | Context Manager вне MVP (раздел Python-рантайма) |
| `[agents.definitions.*]` | Markdown-файлы `.codelab/agents/<name>.md` (§15.8) | по файлу на определение вручную; ключ `agents.definitions` в `config.yaml` — ошибка с этой подсказкой (DF-12) |
| `[tui]` | — | настройки клиента, не агента |
| `[[mcp.servers]]` | `mcp.servers` (список) | поля совпадают; `env` и `headers` — из массива `{name, value}` в отображение; `${VAR}` без значения — ошибка; `type` только `stdio` или `http` |
| `codelab.local.toml` | `.codelab/config.local.yaml` | |
| `~/.codelab/auth.toml` | слой 2 вместе с `$CODELAB_HOME/codelab.toml` | `api_key = "${VAR}"` → `api_key_env`; литеральный ключ не переносят (CFG-2) |

## 15.8. Определения агентов в Markdown

**Назначение.** Пользователь описывает специализированного агента (ревьюер, архитектор,
документатор) одним Markdown-файлом: промпт, модель, разрешённые инструменты и режим. Клиент
выбирает агента опцией конфигурации `agent`. Это сохраняет возможность текущего CodeLab и
заменяет секции `[agents.definitions.*]` не читаемого более `codelab.toml` (§15.7).

**Расположение и приоритет.**

| Каталог | Источник | Когда действует |
|---|---|---|
| `$CODELAB_HOME/agents/*.md` | пользователь | всегда |
| `<cwd>/.codelab/agents/*.md` | репозиторий | только если канонический `cwd` сессии в `trusted_projects` (§15.3; `CoreConfig.trustedProjects`, design.md change `add-agent-project-files`, D4): тело файла — промпт, а промпты из недоверенного проекта не загружаются (CFG-3) |

Определение проекта с тем же `name` заменяет глобальное. Файлы читаются при создании и загрузке
сессии; изменения действуют в новых сессиях.

После MVP встроенные профили сессии `architect` и `review` (§17.12.2) загружаются первыми; файл с тем же
`name` и `scope` `session` или `both` заменяет профиль. На этапе 8.8 встроенных профилей нет.

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
// Определения сессии приходят из порта хоста ProjectFilesSource при createSession/loadSession
// (parseAgentDefinitions → AgentSession.agents, design.md change add-agent-project-files, D1, D10);
// ACP-адаптер строит из AgentSession.agents опцию `agent` (scope session | both),
// после MVP TaskTool — enum типов (scope subagent | both, §17.3.2).
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
1. name == "default" → снять профиль агента: базовый промпт, модель и режим базы (запомнены при
   выборе из default; база, восстановленная из журнала, зажата полом конфига — D11)
2. системный промпт = базовый промпт (§11) + последняя секция agent_profile
   "# Agent profile: <name>" с телом файла без пробельных краёв (шаг 10b §11.5); правила безопасности и ограды
   базового промпта остаются (тело их не заменяет)
3. model задан → сменить модель, опция `model` получает новое значение; переход на модель без
   рассуждения — та же заметка §2.12.3, что при смене опцией model
4. mode задан и не мягче режима конфигурации сессии (permissions.mode ?? режим профиля;
   порядок bypass → accept-edits → standard → ask, plan строже всех) → сменить режим так же,
   как session/set_mode (§13.6); мягче → режим не меняется, лог agent.mode.not_applied
   (design.md change add-agent-project-files, D11; решение пользователя 2026-10-30, OQ3); extraDeniedTiers, permissions.deny и
   критические шаблоны выбор агента не трогает
5. tools задан → набор схем следующего шага = инструменты профиля ∩ список (шаблоны по префиксу),
   только из включённых инструментов (§6.3.8): выключенный инструмент списком не возвращается;
   инструмент вне списка при вызове → отказ "Tool not available for agent <name>: <tool>" как
   неизвестный инструмент: до политики разрешений, считается в MisuseBreaker (TOOL-11); секция mcp
   промпта перечисляет только серверы с доступными инструментами (PR-6)
6. ответ на session/set_config_option — полный снимок опций (agent, model, mode); если режим
   изменился — current_mode_update до ответа; config_option_update в ответ на запрос клиента не
   дублируется (§13.6, п. 4, ACP-11)
7. изменения (режим политики разрешений, модель, промпт, инструменты) действуют со следующего шага;
   идущий вызов не прерывается, вызовы пакета текущего шага решаются по прежнему режиму и набору;
   смены mode/model/effort/agent сессии идут одной очередью, последний запрос выигрывает
   (design.md change add-agent-project-files, D11)
```

**ACP.** Опция конфигурации:

```json
{"id":"agent","name":"Agent","type":"select","currentValue":"default",
 "options":[{"value":"default","name":"Default"},
            {"value":"reviewer","name":"reviewer","description":"Reviews the current changes and reports defects"}]}
```

Поля `category` у опции нет: имена категорий без `_` зарезервированы ACP, а определены только
`mode`, `model`, `thought_level` (`13-Session Config Options.md`, «Option Categories»); своя
категория `_codelab_*` была бы расширением протокола (design.md change `add-agent-project-files`,
D12). Опция идёт после `mode`, `model`, `effort`. Опция присутствует, только если загружено хотя бы
одно определение со `scope` `session` или `both` (после MVP, со встроенными профилями — всегда). Выбранный агент пишется в
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
* `acp/set-config-option-agent`: `current_mode_update` до ответа, ответ на `session/set_config_option` содержит согласованные `agent`, `model`, `mode`, `config_option_update` не отправляется (ACP-11); края опции — `codelab_agent_acp/test/config_options_agent_test.dart`.

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
5. **CFG-5.** Ядро получает только провалидированный `CoreConfig` и не читает файлы конфига; разборщики YAML (`yaml`, `yaml_edit`) живут только в `codelab_agent_io`; TOML агент не разбирает.
6. CFG-6 … CFG-8 — определения агентов, §15.8.
7. CFG-9 … CFG-19 — секреты, предконфигурация, запись и живая перезагрузка конфига, MCP-супервизор, реестр настроек (после MVP), §17.5.11.
8. **CFG-20.** Агент и клиенты читают и пишут конфиг только в YAML. `codelab.toml` Python-агента не читается; если нет ни одного YAML-файла слоёв 2–4 и не задан `--config`, а старый файл найден, загрузчик пишет одно предупреждение `config.legacy_found` с путями и ссылкой на §15.7 (решение пользователя 2026-10-29).
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
* **Старый файл не читается, а только замечается.** Поддержка `codelab.toml` потребовала бы
  второго формата и второй таблицы перевода ради временной совместимости: читателя, зависимости
  `package:toml`, правил записи при активном старом файле и команды `config migrate`. Решение
  пользователя 2026-10-29: файл не читается; взамен одно предупреждение `config.legacy_found` не
  даёт потерять настройки молча, а таблица §15.7 делает ручной перенос быстрым. Половина старых
  ключей не действовала или меняет смысл, и перенос вручную заставляет увидеть это. Прежняя
  редакция (чтение в память и `config migrate`) снята этим решением; вернуть чтение можно только
  отдельным OpenSpec change.

## 15.12. Как проверить

* Табличные тесты валидатора: неизвестный ключ с подсказкой, неверный тип, `api_key`, `autopilot` в конфиге, запись `exec.secrets` строкой вместо `{env, secret}` и `env: github_token` (не `^[A-Z_][A-Z0-9_]*$`) (CFG-1, CFG-2, CFG-4).
* Тест слияния: списки заменяются, элементы `mcp.servers` сливаются по `name`, `enabled: false` выключает.
* Тест доверия: проектный конфиг с `mcp.servers` и `permissions.tools` = `allow` без `trusted_projects` → предупреждения, серверов и правил нет; с доверием — есть (CFG-3).
* Тесты подстановки: `${VAR}`, `$${`, `$VAR` как литерал, незаданная переменная — ошибка, подстановка вне разрешённых ключей — литерал.
* `config_yaml_profile_test.dart` (`codelab_agent_io`): якорь и ссылка, `<<: *base`, тег `!!str`, второй документ, ключ `1:` и составной ключ, повторяющийся ключ (обе позиции в сообщении) → проблема `profile` со строкой и столбцом; пустой файл и файл из комментариев → пустой слой; flow-стиль, CRLF и BOM читаются так же, как блочный стиль и LF; `yes` и `on` остаются строками — тип проверяет схема ядра (CFG-21).
* `config_schema_test.dart` (ядро): `compaction.enabled: yes` → ошибка типа с подсказкой `use true or false`, а `shell_exec: off` в `profile.*` — строка без проблемы; `output.max_lines: 2000` внутри `tools:` → неизвестный ключ с подсказкой вложенной формы; `null` у ключа схемы → ошибка типа (CFG-1, CFG-4, CFG-21).
* Файлы тестов 8.5 (change `add-agent-configuration`, D17): ядро — `codelab_agent_core/test/config/` (схема, позиции, `config.key.not_applied`, слияние, доверие, подстановка, секреты, `redact`, MCP-серверы), `test/llm/routed_stream_function_test.dart`, `test/runtime/config_outside_root_test.dart`; загрузчик — `codelab_agent_io/test/config/` (`config_yaml_profile_test.dart`, `config_loader_test.dart` с DoD этапа «invalid config reports key path and line», `config_legacy_found_test.dart`) и `test/cli/config_commands_test.dart`; бинарь — `apps/codelab_agent/test/` (`agent_host_config_test.dart`, `config_invalid_process_test.dart`, `config_mcp_servers_test.dart`, `config_mcp_ws_test.dart`, `config_untrusted_project_process_test.dart`, `config_run_test.dart`, `config_command_process_test.dart`); CLI — `apps/codelab_cli/test/config_command_test.dart` и e2e `cli/config-check-reports-issues`.
* `config_validator_positions_test.dart` (ядро): `ConfigTree` с позициями → `ConfigIssue` со строкой и столбцом; тот же слой без позиций (хранилище приложения) → сообщение с источником и путём ключа без строки (CFG-1).
* `agent_definition_parse_test.dart` и `skill_parse_test.dart` дополнены: якорь во frontmatter и `disable-model-invocation: yes` → ошибка по профилю §15.5 (CFG-21).
* `config_legacy_found_test.dart` (`codelab_agent_io`) — критерий **`core/config-legacy-found-warning`** (R-16): только `<cwd>/codelab.toml` (даже с синтаксической ошибкой TOML) и нет `config.yaml` → загрузка без проблем из этого файла, ровно одно `config.legacy_found` с путём файла и ссылкой на §15.7, содержимое в лог не попало; `config.yaml` рядом с `codelab.toml` → предупреждения нет; с `--llm-script` файлы не ищутся (CFG-20).
* `core/config-rejects-yaml-agent-definitions` (DF-12): `agents.definitions.reviewer` в `config.yaml` → проблема с ключом и подсказкой `.codelab/agents/reviewer.md`.
* `core/config-unknown-provider-error` (DF-15): `providers.foo.kind: mock` → проблема `providers.foo.kind` со списком известных видов, агент не стартует, провайдер `mock` не подставлен.
* Тест `config.yml`: рядом с `config.yaml` или без него → предупреждение `config.file.ignored` с подсказкой переименовать, файл не читается.
* После MVP: `config_sessions_test.dart` — `sessions.lease.stale_after < 3 × heartbeat` → `ConfigException`, `sessions.lease` в проектном конфиге игнорируется с предупреждением (§17.6.16); `config_steering_test.dart` — `yield_long_tools: true` при `jobs.enabled: false` → `ConfigException`, увеличение `steering.max_steps` в проектном конфиге без доверия отклонено, уменьшение принято (§17.7.11); `lsp_config_test.dart` — серверы из недоверенного проекта игнорируются, одно расширение у двух серверов → `ConfigException` (§17.8.14); `config_jobs_test.dart` (§17.9.16).
* `config_loop_test.dart` (с потребителем `loop.*`; до него ключи дают `config.key.not_applied`, §15.5): диапазоны `loop.empty_response_retries` и `loop.misuse.*`; `warn_after > block_after` → `ConfigException` (C-07, C-08).
* Тест-сторож: `codelab_agent_core` не импортирует `package:yaml`, `package:yaml_edit` и `package:toml`; `package:toml` нет в allowlist `codelab_agent_io` (CFG-5).

---

← [14. Формат golden ACP-фикстур](14-golden-fixtures.md) · [Оглавление ядра](../agent-core-architecture.md) · [16. Что не входит в MVP и открытые вопросы](16-non-mvp-and-open-questions.md) →
