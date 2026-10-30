# 12. Наблюдаемость и модель ошибок

> Часть [архитектуры ядра агента CodeLab](../agent-core-architecture.md). Status: Accepted. Общие соглашения, термины и порядок чтения — в оглавлении.

← [11. Промпты](11-prompts.md) · [Оглавление ядра](../agent-core-architecture.md) · [13. ACP-адаптер](13-acp-adapter.md) →

## 12.1. Назначение

Сбои агента — обычная часть работы: сеть рвётся, модель отказывает, команда падает. Ядро
различает три класса ошибок, у каждого своя форма и свой путь к пользователю. Всё, что уходит
в лог, журнал сессии и события, проходит редакцию секретов. ACP-адаптер ведёт protocol trace,
по которому восстанавливается любой сеанс.

## 12.2. Контракт: три класса ошибок

| Класс | Источник | Форма | Что видит пользователь | Что видит модель |
|---|---|---|---|---|
| **Ожидаемый сбой работы** | провайдер LLM, сеть, инструмент, сжатие, запись журнала | событие: `ErrorEvent` → `AgentError`, `ToolCallFinished(failed)`, `TurnEnded(failed)` | сообщение об ошибке в клиенте, ход завершён штатно | результат-ошибку инструмента; ошибки провайдера модель не видит |
| **Ожидаемый сбой окружения** | файл, процесс, ACP `fs/*` и `terminal/*` | значение `Result.Err(FileError | ExecError)` | карточку вызова со статусом `failed` | текст причины в результате инструмента |
| **Ошибка программиста или конфигурации** | неверный профиль, нет сервиса, нарушение контракта, неверный конфиг | исключение: `ConfigException`, `HostWiringException`, `StateError`, `ArgumentError` | ошибку запуска или ответа API | ничего |

Правила:

1. Ожидаемые сбои **не бросаются** через публичный API ядра (OBS-1). `AgentSession.prompt()`
   завершается `TurnResult` с `reason: failed`, а не исключением.
2. Исключение внутри инструмента, хука или подписчика ловится единой точкой и превращается в
   ожидаемый сбой работы (TOOL-3, LOOP-1); текст для модели — сообщение без префиксов вида
   `Exception:` и без стека; стек уходит в лог.
3. Ошибки конфигурации проявляются **при старте**: конфиг валидируется до создания runtime
   (§15.5), сборка проверяет сервисы (§10.7).
4. Каждый `AgentError` имеет класс `cls` из `AgentErrorClass` (§5.3): `provider` (сбой или
   повтор запроса к модели; подробный `LlmErrorClass` — в тексте и в логе), `fallback` (переход
   к следующей модели), `compaction`, `hook` (исключение хука или внутренняя ошибка цикла),
   `storage` (запись журнала), и флаг `retrying`.
5. Тексты, которые видит модель (результаты и ошибки инструментов, уведомления об усечении,
   отказы в разрешении), — фиксированные английские строки из кода ядра; локализуется только
   то, что видит человек в клиенте.

Примеры:

| Ситуация | Класс | Что происходит |
|---|---|---|
| `connection reset` до первого вывода | работа | повтор (§2.4), `AgentError(cls: provider, errorClass: network, retrying: true)` в лог; пользователь видит только задержку |
| 401 от провайдера | работа | `AgentError(cls: provider, errorClass: auth, retrying: false)`, `TurnEnded(failed)`, ACP — JSON-RPC ошибка на `session/prompt` (§13.8) с подсказкой `check api_key_env` |
| `read` несуществующего файла | окружение | `Err(FileError.notFound)` → результат `failed` с текстом `File not found: lib/x.dart`; ход продолжается |
| `exec` с кодом 1 | окружение | результат-ошибка с выводом и кодом; ход продолжается |
| в профиле `mobile` включён `shellExec` | конфигурация | `HostWiringException` при `buildAgentCore`, агент не стартует |
| 429 без свободного ключа и резервной модели (после MVP, §17.10.4.1) | работа | `AgentError(cls: provider, errorClass: rateLimited, rateLimit: …)`, текст `Rate limit reached for openai/gpt-4.1: too many requests. Resets in 3 h.`; тело ответа — только лог debug |
| в конфиге неизвестный ключ `compaction.reserve_token` | конфигурация | `ConfigLoadResult.issues` с `ConfigIssue(kind: unknownKey)`, текст `config.yaml:3:3: compaction.reserve_token: unknown key (did you mean reserve_tokens?)`; бинарь — stderr и код `64` до старта транспорта, `orThrow()` — `ConfigException` |

## 12.3. Контракт: Logger

```dart
enum LogLevel { trace, debug, info, warning, error }
abstract interface class Logger {
  bool isEnabled(LogLevel level);
  void log(LogLevel level, String event,
      {Map<String, Object?> fields = const {}, Object? error, StackTrace? stack});
}
final class LogRecord {           // то, что получает sink хоста после редакции
  final DateTime time; final LogLevel level; final String event;
  final Map<String, Object?> fields; final String? error; final String? stack;
}
```

`Logger` — порт: ядро пишет в него, хост решает, куда (stderr для `codelab-agent serve --stdio`,
файл `$CODELAB_HOME/logs/agent.log`, лог-панель codelab-app). stdout в режиме stdio занят ACP —
писать туда логи запрещено.

`event` — стабильное имя в формате `<область>.<действие>` или `<область>.<объект>.<действие>`
(`llm.retry`, `turn.start`, `llm.request.start`); на него опираются тесты и фильтры. Перечень MVP:

| Область | События |
|---|---|
| `llm` | `llm.request.start`, `llm.request.end`, `llm.retry`, `llm.fallback`, `llm.finish_reason.unknown` (§2.7) |
| `turn` | `turn.start`, `turn.end`, `turn.budget_exceeded` |
| `tool` | `tool.start`, `tool.end`, `tool.validation_failed`, `tool.validate.error` (`debug`; `tool`, `tool_call_id` — исключение при валидации, §6.3.1 шаг 3), `tool.pairing_repaired`, `tool.misuse.warned`, `tool.misuse.blocked` (§6.3.7) |
| `tools` | `tools.switch.no_match` (§6.3.8) |
| `loop` | `loop.empty_response`, `loop.empty_response.stopped` (§5.4.1) |
| `prompts` | `prompts.override` (§11.6.1) |
| `permission` | `permission.request`, `permission.decision`, `permission.denied` |
| `session` | `session.create`, `session.open`, `session.repair`, `session.leaf.healed`, `session.append.failed`, `session.cycle`, `session.broken_link`, `session.compaction.lost_anchor` (§8.7); после MVP `session.origin.unknown` {`origin`} (§8.2.5) |
| `compaction` | `compaction.start`, `compaction.end`, `compaction.failed` |
| `mcp` | `mcp.server.skipped`, `mcp.server.era`, `mcp.server.connect`, `mcp.server.failed`, `mcp.server.closed`, `mcp.server.stderr` (`trace`), `mcp.servers.replace_failed`, `mcp.tools.changed`, `mcp.tools.refresh_failed`, `mcp.tool.invalid`, `mcp.tool.description_truncated`, `mcp.call.cancelled`, `mcp.call.timeout`, `mcp.message.ignored` (`debug`) (этап 8, поля ниже) |
| `acp` | `acp.frame.in`, `acp.frame.out`, `acp.frame.bad`, `acp.cancel.no_turn`, `acp.prompt.rejected`, `acp.detached`, `acp.client_capabilities.absent` (§13.2), `acp.terminal.release_failed` (§13.9) |
| `host` | `host.plan`, `host.config.loaded`, `serve.config.invalid` (бинарь `serve`, ошибка загрузки конфига) |
| `config` | `config.env.unknown`, `config.project.untrusted_key` (§15.3), `config.key.not_applied` (§15.5), `config.provider.key_missing`, `config.secret.unavailable`, `config.file.ignored`, `config.legacy_found` (§15.7), `config.session.outside_root` (§10.3); таблица ниже |

События `mcp.*` (этап 8; `openspec/changes/archive/2026-10-29-add-agent-mcp-client/design.md`, D13). `session_id` есть
всегда, `server` — `name` сервера:

| Событие | Уровень | Поля |
|---|---|---|
| `mcp.server.skipped` | info | `transport`, `reason`; из ACP-адаптера — тоже с `session_id`, строки клиента `type` и `name` обрезаются до 64 рун |
| `mcp.server.era` | info | `transport`, `era` (`modern`/`legacy`), `protocol_version`, `probe` (`discover_result`, `modern_error`, `fallback_error`, `fallback_timeout`, `cached`) |
| `mcp.server.connect` | info | `transport`, `era`, `protocol_version`, `server_info` (`name`/`version`, только для диагностики), `tools`, `duration_ms` |
| `mcp.server.failed` | warning | `transport`, `reason` (≤ 200 символов, правила ниже) |
| `mcp.server.closed` | info | `transport`, `exit_code` (stdio) или `reason` (HTTP: `HTTP session expired`); пишет транспорт через логгер сессии из `McpTransportFactory.open` |
| `mcp.server.stderr` | trace | `line` (≤ 4 КиБ); пишет транспорт через логгер сессии. Уровень trace, а не debug: профиль `--stdio` по умолчанию включает debug, а логгер хоста секреты не редактирует (до 8.11) |
| `mcp.servers.replace_failed` | warning | `error` (`runtimeType`) — `AgentSession.setMcpServers` бросил при `session/load` открытой сессии (§13.5) |
| `mcp.tools.changed` | info | `added`, `removed` |
| `mcp.tools.refresh_failed` | warning | `reason` (`tools/list failed (code N)`, `no answer to tools/list`) — перечитывание `tools/list` после `list_changed` не удалось, прежний набор инструментов остаётся |
| `mcp.tool.invalid` | warning | `tool` (имя от сервера, ≤ 64 рун), `reason` |
| `mcp.tool.description_truncated` | info | `tool`, `length` |
| `mcp.call.cancelled`, `mcp.call.timeout` | info | `tool_call_id`, `request_id` |
| `mcp.message.ignored` | debug | `kind` (`late_response`, `unknown_notification`, `parse_error`, `subscription_closed`, `subscription_failed`, `server_request`, `notification_stream_closed` — конец legacy GET-потока, поле `reason` (`stream closed`, `stream error`, `event too large`, `HTTP <status>`, `connection failed: <runtimeType>`), `stream_resume_failed` — неудачное возобновление потока ответа); у `subscription_failed` при сбое переиздания подписки — `error` (`runtimeType`); у `server_request` — `method` запроса сервера, не длиннее 64 символов (рун) |

События `config.*` и загрузки конфига (change `add-agent-configuration`, D16; новые отмечены).
Значения ключей, переменных и секретов в поля не попадают: только пути ключей, имена переменных и
секретов, источники и пути файлов. Каждое событие предупреждения загрузки (`config.*` ниже, кроме
`config.session.outside_root`, и `mcp.server.skipped`) несёт также поле `message` — английский текст
`ConfigIssue.message` без значений, та же строка, что печатает `config check`:

| Событие | Уровень | Поля |
|---|---|---|
| `host.config.loaded` | info | `sources`, `warnings` (число), `project_root`, `transport` (`stdio` \| `ws`), `models` (id моделей каталога) |
| `serve.config.invalid` | error | `issues` — список `{source, line, column, key, kind}`; те же строки в stderr, код выхода `64` |
| `config.env.unknown` | warning | `message` |
| `config.project.untrusted_key` (новое) | warning | `key`, `source`; в том числе смягчение `permissions.mode` и `trusted_projects` в проектном слое (§15.3) |
| `config.key.not_applied` (новое) | warning | `key`, `source`; ключ без потребителя или раздел «после MVP», один раз на лист за загрузку (§15.5) |
| `config.provider.key_missing` (новое) | warning | `provider`, `variable` |
| `config.secret.unavailable` (новое) | warning | `key` |
| `config.file.ignored` (новое) | warning | `path`, `hint` (`config.yml` рядом с `config.yaml`) |
| `config.legacy_found` (новое) | warning | `files` (только пути; содержимое файла не читается, §15.7) |
| `config.session.outside_root` (новое) | info | `session_id`, `cwd`, `config_root`; пишется логгером сессии, один раз на нормализованный `cwd` (§10.3) |
| `mcp.server.skipped` | info | `server`, `reason: "disabled in config"` (новая причина для `enabled: false`), `message` |

Прежние `config.legacy_ignored`, `config.legacy_key_dropped` и `config.legacy_active` удалены:
`codelab.toml` не читается (§15.7).

В поля НЕ попадают значения `env`, `headers`, `args`, `Mcp-Session-Id`, `Mcp-Param-*`, тела запросов
и ответов; причины ошибок транспорта формирует наш код, без текста заголовков (OBS-инварианты,
тест `mcp_logs_no_secrets_test.dart`). Редакция секретов MCP в журнале — 8.11.

`reason` событий `mcp.server.skipped`, `mcp.server.failed` и `mcp.tools.refresh_failed` содержит
только текст нашего кода: `message` и `data` ошибки сервера, неизвестный `resultType` и
`serverInfo` в причину не входят. Версии протокола сервера (`protocolVersion`, `supportedVersions`)
входят только после проверки формата `YYYY-MM-DD`, остальные отбрасываются. Имя метода запроса сервера
входит только в `mcp.message.ignored` с `kind: server_request` (debug, ≤ 64 рун). Ошибка JSON-RPC описывается методом и кодом
(`'<method> failed (code N)'`), локальный сбой HTTP-транспорта без JSON-RPC-тела — методом и причиной транспорта без кода (`'<method> failed: <reason>'`, например `tools/list failed: HTTP 500`), отказ modern-сервера на пробе `-32020`/`-32021` — `server rejected the probe (code N)`, непредвиденное исключение — `unexpected error: <runtimeType>`;
обрезка до 200 символов — по рунам Unicode. Полный список причин — design.md change
`add-agent-mcp-client`, D13.

Этап 8.6–8.8 (design.md change `add-agent-project-files`, D14; пишет логгер сессии; содержимое файлов, тела шаблонов и определений и
аргументы команд в поля не попадают):

| Событие | Уровень | Поля |
|---|---|---|
| `project_context.loaded` | info | `session_id`, `files`, `bytes`, `truncated`, `omitted`, `root` (`git` \| `cwd`) |
| `commands.loaded` | info | `session_id`, `count`, `project` (bool: проект доверенный, каталог проекта читается) |
| `agents.loaded` | info | `session_id`, `names` |
| `project_files.diagnostic` | warning (`error`/`warning`), debug (`info`) | `session_id`, `path`, `line`, `column`, `code`, `message` |
| `project_files.skipped` | info | `transport` (`ws`), `reason`; логгер хоста, один раз при запуске `serve --ws` (D16) |
| `command.expanded` | info | `session_id`, `name`, `source`, `args_bytes` |
| `agent.selected` | info | `session_id`, `agent`, `source`, `model`, `mode`, `mode_applied`, `tools` |
| `agent.mode.not_applied` | warning | `session_id`, `agent`, `mode`, `floor` |
| `agent.definition.missing` | warning | `session_id`, `agent` |

Уровни диагностик файлов проекта (D3, D6): `outside_root`, `not_utf8`, `unreadable`, `timeout` —
`warning`; `limit_exceeded` — `warning` для предела 100 файлов каталога шаблонов или агентов
(отброшенные файлы видны в `config check`) и `info` для предела 64 уровней обхода; `shadowed` — `info`; `unexpected` — `error` (непредвиденное исключение
порта; в поле `message` — только тип исключения). Коды содержимого шаблонов (D3): `unknown_key`,
`invalid_value`, `empty_body`, `too_large` — `error`; `invalid_name`, `reserved_name` — `warning`;
`shadowed`, `untrusted_project` — `info`; запись `*.md`, которая не обычный файл (FIFO, сокет,
устройство), — `unreadable` (`warning`). Коды определений агентов — по D10 того же change. Путь в `project_files.diagnostic` и `project_context.loaded` не
экранируется, в отличие от атрибута `path` блока в промпте (§11.5).

После MVP (§17) добавляются области:

| Область | События |
|---|---|
| `web` | `web.fetch.start`, `web.fetch.end`, `web.fetch.blocked`, `web.fetch.unresolved` (`debug`), `web.search.end` (§17.1.5) |
| `skills` | `skills.load`, `skills.catalog.truncated`, `skills.operative.dropped`, `skills.operative.truncated` (§17.2) |
| `subagent` | `subagent.start`, `subagent.end`, `subagent.type_overridden`, `subagent.cancel_grace_exceeded`, `subagent.approval_unavailable` (§17.3), `subagent.follow_up` {`subagentId`, `run`, `kind`: `send` \| `resume`}, `subagent.follow_up_rejected` {`subagentId`, `reason`}, `subagent.observe` {`subagentId`, `last`} (§17.3.8.1) |
| `spill` | `spill.write`, `spill.failed`, `spill.missing`, `spill.orphan_deleted` (§17.4) |
| `config` | `config.reload.applied`, `config.reload.failed`, `config.reload.noop`, `config.reload.restart_required`, `config.preconfig.shadowed`, `config.write` (§17.5) |
| `secrets` | `secrets.lookup` (только `--debug-secrets`), `secrets.backend.unavailable`, `secrets.backend.plaintext` (§17.5.4) |
| `mcp` (дополнение) | `mcp.server.state`, `mcp.server.retry` (§17.5.7); `mcp.tools.changed` уже в MVP |
| `session` (дополнение) | `session.lease.takeover`, `session.lease.lost`, `session.branch_summary.failed`, `session.fork.start`, `session.fork.end`, `session.fork.failed` (§17.6); `session.sealed` (info), `session.sealed.dropped` (warning, один раз на вид записи), `session.title_probe` (debug) (§8.5.1, §8.10.1); `session.search` (debug: `scope`, `terms` — число, `scanned`, `hits`, `truncated`, `skipped`, `durationMs`; без текста запроса и сниппетов) (§17.6.17) |
| `steer` | `steer.accepted`, `steer.refused` (§17.7.3.1) |
| `lsp` | `lsp.server.start`, `lsp.server.ready`, `lsp.server.stop`, `lsp.server.crash`, `lsp.server.failed`, `lsp.server.stderr` (`debug`), `lsp.request.timeout`, `lsp.frame.bad`, `lsp.sync.failed`, `lsp.edit.rollback` (§17.8.10) |
| `job` | `job.start`, `job.end`, `job.kill_timeout`, `job.log_failed`, `job.output_gap`, `job.yield_skipped`, `job.recovery` (`action: killed \| left \| gone`) (§17.9) |
| `llm` (дополнение) | `llm.catalog.changed`, `llm.catalog.failed`, `llm.catalog.truncated`, `llm.catalog.default_used` (§2.12.2) |
| `usage` | `usage.ledger.rebuild`, `usage.ledger.write_failed` (§12.6.1) |
| `redact` | `redact.config.disabled`, `redact.config.exact_forced`, `redact.applied` (`debug`: счётчики по слоям, без значений) (§12.4.1) |
| `log` | `log.file.open_failed`, `log.file.large`, `log.file.write_failed` (§12.3.1) |
| `llm` (дополнение, провайдеры) | `llm.schema.simplified`, `llm.key.cooldown`, `llm.key.rotated`, `llm.key.rejected`, `llm.key.duplicate`, `llm.role.unavailable`, `llm.think_tags.unclosed`, `llm.images.rejected`, `llm.usage.missing`, `llm.snapshot.written`, `llm.snapshot.limit`, `llm.prompt_tools.parse_failed`, `llm.prompt_tools.hallucinated_result`; поле `stall_class` в `llm.retry` и `llm.request.end` (§17.10); `llm.rate_limit` (info: `provider`, `model`, `kind`, `window`, `retry_after_ms`, `reset_at`, `source`), `llm.rate_limit.body` (debug: `provider`, `model`, `status`, `body` после редакции, ≤ 2000 символов), `llm.rate_limit.decode_failed` (warning: `provider`) (§17.10.4.1); `llm.stall.key_rotated` (info: `provider`, `from`, `to`, `stall_class` — метки ключей, не значения), поле `stage` (`retry`) у `llm.retry` (§17.10.10.1) |
| `images` | `images.prepare.failed` (warning: `source` — `prompt` \| `tool`, `reason`, `bytes`), `images.prepared` (debug: `source`, `from`, `to`, `steps`, `ms`) (§17.11.2.1) |
| `auth` | `auth.login.url`, `auth.login.succeeded`, `auth.login.failed`, `auth.token.refreshed`, `auth.token.refresh_failed` (§17.10.6) |
| `memory` | `memory.add`, `memory.delete`, `memory.recall` (`debug`), `memory.store_failed` (§17.11.4) |
| `vision` | `vision.inspect.end`, `vision.inspect.failed` (§17.11.5) |
| `checkpoint` | `checkpoint.rewind`, `checkpoint.refused` (`debug`) (§17.11.6) |
| `ask` | `ask.request`, `ask.answer`, `ask.timeout`, `ask.answer.bad` (§17.11.7) |
| `tools` (дополнение) | `tools.mount`, `tools.discover.disabled`, `tools.inspect_image.no_vision_model` (§17.11) |
| `tool` (дополнение) | `tool.stuck` (warning) (§17.12.3) |
| `loop` (дополнение) | `loop.final_check.error` (warning), `loop.final_check.revise_limit` (info) (§17.12.4) |
| `deadline` | `deadline.set`, `deadline.cleared`, `deadline.notice`, `deadline.stop` (info) (§17.12.5) |
| `exec` | `exec.secret_rewrite` (info), `exec.secret_rewrite.error` (warning) (§17.12.6) |
| `redact` (дополнение) | `redact.block.denied` (info) (§17.12.7) |
| `agent` | `agent.profile_overridden` (info) (§17.12.2) |
| `acp` (дополнение) | `acp.mode.legacy_alias` (info) (§17.12.2) |
| `session` (дополнение, масштаб) | `session.window.open`, `session.index.rebuild`, `session.segment.rotated` (§17.13.2) |
| `compaction` (дополнение) | `compaction.structured.pass`, `compaction.structured.fallback`, `compaction.structured.unavailable` (§17.13.4) |
| `context` | `context.expand` (§17.13.4) |
| `hook` | `hook.run`, `hook.timeout`, `hook.spawn_failed`, `hooks.unavailable` (§17.14.2) |
| `plugin` | `plugin.unknown`, `plugin.skipped`, `plugin.command.failed` (§17.14.3) |
| `a2a.client` | `a2a.client.card.fetched`, `a2a.client.card.invalid`, `a2a.client.unavailable`, `a2a.client.request` (`debug`), `a2a.client.task.state`, `a2a.client.stream.reconnect`, `a2a.client.cancel_refused`, `a2a.client.error` (§17.15.6) |
| `a2a.server` | `a2a.server.start`, `a2a.server.stop`, `a2a.server.auth.failed`, `a2a.server.request` (`debug`), `a2a.server.task.state` (аудит), `a2a.server.approval.request`, `a2a.server.approval.decision`, `a2a.server.approval.timeout` (аудит), `a2a.server.rejected` (§17.15.6) |

Поля записи (ключи `snake_case`, значения — JSON-совместимые):

| Поле | Когда обязательно | Пример |
|---|---|---|
| `session_id` | всё в пределах сессии | `01JB8Q2W6R9T3M5K7N1P4X8Z0C` |
| `turn_id` | всё в пределах хода | `t-0007` |
| `step` | события `llm.*`, `tool.*` | `3` |
| `tool_call_id`, `tool` | события `tool.*`, `permission.*` | `call_1`, `write` |
| `request_id` | события `acp.*` с JSON-RPC id | `42` |
| `model`, `provider` | `llm.*` | `gpt-4o`, `openai` |
| `duration_ms` | события `*.end` | `1834` |
| `http_status`, `error_class` | сбои `llm.*` | `429`, `rateLimited` |
| `tokens_in`, `tokens_out`, `cost` | `llm.request.end`, `turn.end` | `41000`, `600`, `0.106` |
| `cache_read`, `cache_write` | `llm.request.end`, `turn.end` (§2.12.1) | `38000`, `0` |
| `outcome` | `tool.end`, `permission.decision`, `turn.end` | `rejected` |
| `stall_class` | после MVP: `llm.retry`, `llm.request.end` при срабатывании сторожа (§17.10.10) | `first_byte_stall` |

Значения аргументов инструментов и тексты сообщений в лог уровня `info` не пишутся — только на
`debug` и после редакции.

### 12.3.1. Лог в файл (E-16)

Файловый sink получает **каждую** запись лога — ту же, что основной sink хоста, после той же
редакции (§12.4): `Logger` редактирует запись один раз и раздаёт готовый `LogRecord` всем sink.

**Путь** — первое заданное значение: флаг `--log-file <path>` → переменная `CODELAB_LOG_FILE` →
ключ `logging.file` (по умолчанию `$CODELAB_HOME/logs/agent.log`, §15.4). Флаг и переменная есть у
`codelab-agent serve` (`--stdio` и `--ws`) и у `codelab` (встроенный агент пишет в этот файл; лог
клиента — по правилам клиента, [`dart-agent-and-clients.md`](../dart-agent-and-clients.md) §9.11).
`~` раскрывается, относительный путь — от рабочего каталога процесса.
До этапа 8 бинарь `codelab-agent` конфиг не читает (§15.6), поэтому значения по умолчанию
`logging.file` у него нет: файл пишется, только если задан флаг или переменная (OpenSpec change
`add-codelab-agent-binary`, design.md D5).

| Хост | Основной sink | Файл |
|---|---|---|
| `codelab-agent serve --stdio` | stderr | путь выше |
| `codelab-agent serve --ws` | stderr | путь выше |
| `codelab` (встроенный агент) | нет (терминал занят интерфейсом) | путь выше |
| codelab-app (встроенный агент) | лог-панель | `logging.file` (флаг и переменная не читаются) |

**Правила.**

1. stdout не трогается никогда: путь `-`, `/dev/stdout`, `/dev/fd/1` или `/proc/self/fd/1` →
   ошибка использования (код выхода `64`, §13.10) с текстом
   `--log-file cannot point to stdout: stdout carries the ACP protocol`.
2. Открытие при старте, до создания runtime: каталоги создаются с правами `0700`, новый файл —
   `0600`, режим дописывания (`O_APPEND`); существующий файл дописывается, не обрезается.
3. Не удалось открыть путь из флага или переменной → ошибка запуска, код `64`, текст
   `cannot open log file <path>: <причина ОС>`. Не удалось открыть путь из конфига (в том числе
   по умолчанию) → warning `log.file.open_failed {path, reason}` в основной sink, работа без файла.
4. Формат файла — JSON Lines, одна запись — одна строка:
   `{"ts":"<ISO-8601 UTC>","level":"info","event":"turn.end", <поля записи>, "error":…, "stack":…}`;
   ключи `ts`, `level`, `event` первыми, затем поля в порядке вставки, `error` и `stack` — только
   если есть. Строка пишется одним вызовом `write` (несколько процессов могут дописывать один файл
   без перемешивания строк).
5. Буферизация: сброс на каждой записи уровня `warning` и выше, раз в 1 с и при `shutdown()`.
   Ошибка записи → одна запись `log.file.write_failed` в основной sink, файловый sink
   отключается до конца процесса; агент продолжает работу (OBS-4).
6. **Ротации в v1 нет.** При открытии файл размером ≥ 100 МиБ даёт одну запись warning
   `log.file.large {path, bytes}` (в основной sink и в сам файл). Ротацию делает внешний
   инструмент или пользователь; protocol trace (§12.5) ротируется сам, как раньше.
7. Смена `logging.file` при живой перезагрузке требует перезапуска (§17.5.6); флаг и переменная
   — параметры запуска.

Пример:

```text
$ CODELAB_LOG_FILE=/tmp/agent.log codelab-agent serve --stdio --log-file ./debug.log
# лог: stderr + ./debug.log (флаг сильнее переменной); /tmp/agent.log не создаётся
```

## 12.4. Алгоритм: редакция секретов

`Redactor` применяется **перед** логом, перед записью в журнал сессии, перед payload
`AgentError`, перед отправкой текста результата инструмента модели (секрет из вывода `env` не
должен уйти провайдеру) и (с этапа 3) перед записью файла выноса (§17.4.3, SPL-3): файл
результата на диске не содержит сырых значений секретов.

Источники «точных» секретов:

1. значения из `SecretStore` (ключи провайдеров, токены MCP-серверов);
2. значения переменных окружения, чьи имена совпадают с `(?i)(KEY|TOKEN|SECRET|PASSWORD|PASSWD|CREDENTIAL|AUTH)` и длина значения ≥ 8;
3. значения заголовков `Authorization`, `X-Api-Key`, `Api-Key` из конфигурации MCP и провайдеров;
4. после MVP (§17.5.3, §17.5.4): каждое значение, полученное через `SecretResolver`
   (`api_key_secret`, `api_key_env`, подстановка `${secret:<name>}` в `headers`/`env`,
   переопределение `CODELAB_SECRET_<…>`), и все значения `headers` предконфигурации из окружения
   (`CODELAB_PROVIDER_CONFIG`).

Шаблоны известных форматов (пишутся для CodeLab, расширяются через OpenSpec):

| Формат | Регулярное выражение | Замена |
|---|---|---|
| ключи вида `sk-…` (OpenAI и совместимые, Anthropic `sk-ant-…`) | `\bsk-(?:ant-|proj-)?[A-Za-z0-9_\-]{20,}` | `[REDACTED:sk]` |
| GitHub токены | `\b(?:gh[pousr]_[A-Za-z0-9]{36,}|github_pat_[A-Za-z0-9_]{60,})` | `[REDACTED:github]` |
| AWS access key id | `\b(?:AKIA|ASIA)[0-9A-Z]{16}\b` | `[REDACTED:aws]` |
| Google API key | `\bAIza[0-9A-Za-z_\-]{35}\b` | `[REDACTED:google]` |
| Slack токены | `\bxox[abposr]-[A-Za-z0-9\-]{10,}` | `[REDACTED:slack]` |
| JWT | `\beyJ[A-Za-z0-9_\-]{8,}\.eyJ[A-Za-z0-9_\-]{8,}\.[A-Za-z0-9_\-]{8,}` | `[REDACTED:jwt]` |
| заголовок Bearer | `(?i)(\bbearer\s+)[A-Za-z0-9._~+/\-]{12,}=*` | `$1[REDACTED]` |
| приватный ключ PEM | `-----BEGIN [A-Z ]*PRIVATE KEY-----[\s\S]*?-----END [A-Z ]*PRIVATE KEY-----` | `[REDACTED:private-key]` |
| присваивание секрета | `(?i)\b([A-Z0-9_]*(?:API_?KEY|TOKEN|SECRET|PASSWORD)[A-Z0-9_]*)\s*[:=]\s*(["']?)[^\s"']{8,}\2` | `$1=[REDACTED]` |
| URL с паролем | `\b([a-z][a-z0-9+.\-]*://[^/\s:@]+:)[^@\s/]+@` | `$1[REDACTED]@` |

```text
redact(text):
1. если text пуст → вернуть text
2. exact := точные секреты (длина ≥ 8), отсортированные по убыванию длины
   для s в exact: text := text.replaceAll(s, "[REDACTED]")     // длинные первыми: префикс не «съест» хвост
3. для каждого шаблона по порядку таблицы: text := replaceAllMapped(pattern, замена)
4. вернуть text

redactJson(value):                                             // для полей лога, записей журнала, rawInput
1. String → redact(s)
2. Map → для каждой пары: если имя ключа совпадает с (?i)^(api_?key|token|secret|password|authorization)$
          и значение — строка → "[REDACTED]"; иначе redactJson(значение)
3. List → поэлементно; прочее → как есть
```

Редакция идемпотентна: `redact(redact(x)) == redact(x)` (замены не совпадают ни с одним
шаблоном). Набор точных секретов обновляется при подключении MCP-сервера и при загрузке
конфига; регулярные выражения компилируются один раз.

Алгоритм `redact` выше — однослойная форма для этапа 1. С цели P-10 (этап 8, задача 8.11) нормативен
послойный алгоритм §12.4.1: на тексте без перекрывающихся совпадений он даёт тот же результат,
а таблица шаблонов выше остаётся его слоями 3–6. `redactJson` не меняется, только вызывает
послойный `redact`.

Где редакция **не** применяется: аргументы, которые уходят в инструмент на исполнение
(`exec` должен получить настоящую команду), и содержимое файлов, которые агент пишет по
просьбе пользователя. Редактируется только то, что сохраняется или показывается. Подробно —
таблица точек применения §12.4.2.

### 12.4.1. Слои редакции (P-10)

```dart
enum RedactionLayer { exact, credentialFiles, formats, pem, connectionStrings, keyValues, entropy }
                                                   // порядок enum = приоритет: exact — высший
final class RedactionContext {
  const RedactionContext({required this.point, this.toolName, this.readPath});
  final RedactionPoint point;
  final String? toolName;
  final String? readPath;                          // путь из аргументов read (слой credentialFiles)
}
enum RedactionPoint { userInput, toolResult, providerRequest, backgroundJob, log, journal, spill,
                      command, export }     // после MVP: command — команда exec (P-14, §17.12.6);
                                            // export — экспорт траектории (S-11, §17.13.3)

abstract interface class Redactor {
  String redact(String text, [RedactionContext? ctx]);
  Object? redactJson(Object? value, [RedactionContext? ctx]);
  /// После MVP (§17.12.6): шаги 1–4 алгоритма redact без замены — выбранные участки.
  List<SecretSpan> findSecrets(String text, [RedactionContext? ctx]);
  void addExactSecret(String value);               // SecretResolver, MCP, конфиг (источники выше)
  RedactionStats get stats;                        // счётчики замен по слоям и точкам; без значений
}

final class SecretSpan {                           // после MVP (§17.12.6)
  final int start, end;                            // участок секрета (без префикса группы: без "Bearer ")
  final RedactionLayer layer; final String tag;    // tag: known-secret, github, sk, aws, jwt, bearer,
}                                                  // private-key, connection-string, key-value, entropy
```

| Приоритет | Слой (`redact.layers`) | Что ловит | Замена |
|---|---|---|---|
| 1 | `exact` | точные значения известных секретов (источники 1–4 выше), длина ≥ 8 | `[REDACTED]` |
| 2 | `credential_files` | содержимое файла учётных данных в результате `read`, если `readPath` совпадает со списком ниже | значения и строки — `[REDACTED:credential-file]` |
| 3 | `formats` | строки таблицы шаблонов: `sk-…`, GitHub, AWS, Google, Slack, JWT, Bearer | как в таблице |
| 4 | `pem` | строка таблицы «приватный ключ PEM» | `[REDACTED:private-key]` |
| 5 | `connection_strings` | строка таблицы «URL с паролем»; пароль в DSN вида `Password=…;` — `(?i)\b(password\|pwd)\s*=\s*[^;\s"']+` | `$1[REDACTED]@`; `$1=[REDACTED]` |
| 6 | `key_values` | строка таблицы «присваивание секрета»; ключ в кавычках — `(?i)(["'][A-Za-z0-9_\-]*(?:api_?key\|token\|secret\|password\|passwd)[A-Za-z0-9_\-]*["']\s*:\s*)(["'])[^"'\n]{8,}\2` | `$1=[REDACTED]`; `$1$2[REDACTED]$2` |
| 7 | `entropy` (выключен по умолчанию) | непрерывный участок `[A-Za-z0-9+/_\-]{32,}={0,2}` с хотя бы одной цифрой и одной буквой и энтропией Шеннона по символам ≥ 4,2 бит на символ | `[REDACTED:entropy]` |

**Файлы учётных данных** (слой 2) — имя или хвост пути `readPath`: `.env`, `.env.*` (кроме
`.env.example`, `.env.sample`, `.env.template`, `.env.dist`), `id_rsa*`, `id_ecdsa*`,
`id_ed25519*` (кроме `*.pub`), `.aws/credentials`, `.npmrc`, `.netrc`, `.pypirc`, `.pgpass`,
`.docker/config.json`, `*.pem`, `*.key` — тот же список, что у режима `redact.block` (P-18). В
таком результате каждая строка после префикса номера строки `read` (§6) обрабатывается так:
пустая строка и комментарий (`#`, `;`, `//` первым непробельным символом) остаются; строка вида
`ключ = значение`, `ключ: значение`, `export ключ=значение`, `"ключ": "значение"` сохраняет ключ,
значение заменяется; любая другая строка заменяется целиком. Модель видит, какие переменные
есть, но не их значения. Результаты `exec` (`cat .env`) этот слой не ловит — их покрывают слои
1 и 3–7 и запрет P-18.

**Белый список** (`redact.allowlist`) применяется к слоям 3–7 и никогда к слоям 1–2: участок
секрета (для шаблонов с группой-префиксом — без префикса, например без `Bearer `), который
**целиком** совпадает с записью списка, не заменяется. Встроенные записи `builtin`: `git_sha` —
`^(?:[0-9a-f]{40}|[0-9a-f]{64})$`, `uuid` — `^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$`;
свои — `patterns` (ядро оборачивает каждое выражение в `^(?:…)$`, частичное совпадение не
считается).

```text
redact(text, ctx):
1. text пуст → вернуть text
2. layers := включённые слои (§12.4.3); exact включён всегда
3. spans := []
   для каждого слоя L из layers в порядке приоритета:
     для каждого совпадения m слоя L в ИСХОДНОМ text:          // слои не видят замен друг друга
       s := участок секрета в m
       L ≥ formats и allowlisted(s) → пропустить
       s целиком внутри маркера вида [REDACTED] или [REDACTED:<tag>] → пропустить   // идемпотентность
       spans.add(Span(start: m.start, end: m.end, layer: L, replacement: замена слоя для m))
4. отсортировать spans по (layer, −(end − start), start)       // приоритет, длиннее, раньше
   chosen := []; для каждого span: не пересекается ни с одним из chosen → chosen.add(span)
5. для span из chosen справа налево:
     breaks := все переводы строк (\r\n, \n, \r) внутри text[start:end] в исходном порядке
     text := text[0:start] + span.replacement + breaks.join() + text[end:]
6. stats[ctx.point][L] += число замен слоя L; вернуть text
```

Свойства: перекрытие всегда решает слой с более высоким приоритетом (точный секрет внутри
`Bearer …` даёт `Bearer [REDACTED]`, а не `[REDACTED]` от двух слоёв); число переводов строк
сохраняется (шаг 5), поэтому строки результата `read` и их номера не сдвигаются — многострочный
PEM-блок превращается в маркер и столько же пустых строк, сколько строк было в блоке; повторная
редакция ничего не меняет (шаг 3, последняя проверка). Регулярные выражения всех слоёв
компилируются один раз при сборке `Redactor` и при изменении `redact.*`.

### 12.4.2. Точки применения

| Точка (`RedactionPoint`) | Что редактируется | Когда |
|---|---|---|
| `userInput` | текстовые блоки `UserMessage` из `session/prompt` (промпт пользователя, развёрнутые шаблоны и MCP prompts) | до записи в журнал и до первого запроса к модели; slash-команды агента (§13.6) не редактируются — они не уходят ни в журнал, ни модели |
| `toolResult` | каждый `TextContent` результата инструмента (§6.3.1, шаг 8b) с `toolName`, для `read` — с `readPath` | до журнала, до ACP и до модели; до выноса в файл (§17.4.3) |
| `providerRequest` | весь `LlmContext` повторно перед каждым запросом: системный промпт, текст `UserMessage`, текст `ToolResultMessage` неосвобождённых инструментов, текстовые блоки `AssistantMessage` | после сборки payload из транскрипта (§8.7), до адаптера. Ловит секреты, ставшие известными позже записи (новый токен MCP, новый ключ), и журналы, записанные до расширения слоёв. Результат кэшируется по идентичности сообщения и поколению `Redactor` (меняется при `addExactSecret` и смене `redact.*`), поэтому неизменная история не редактируется заново на каждом шаге |
| `backgroundJob` | вывод фоновых задач (T-10) | до записи файла лога задачи и до выдачи модели через `job_output` |
| `log` | `LogRecord` через `redactJson` | до раздачи по sink (§12.3.1) |
| `journal` | записи журнала через `redactJson`, кроме полей ниже | до `append` |
| `spill` | текст выносимого результата | до записи файла (SPL-3) |
| `command` (после MVP) | текст команды `exec` до политики разрешений: найденные секреты заменяются ссылками на переменные окружения (§17.12.6) | шаг 0 единой точки исполнения (§6.3.1) |
| значения ключей пула и OAuth-токены (после MVP) | добавляются в слой `exact` через `addExactSecret` (§17.10.4, §17.10.6) | при загрузке пула и при получении или обновлении токена |
| тело ответа 429 провайдера (после MVP) | тело через `Redactor.redact`, затем обрезка до 2000 символов; в `errorMessage`, журнал, ACP и логи выше debug не попадает (PRV-16) | до записи в лог debug `llm.rate_limit.body` (§17.10.4.1) |
| тело снимка запроса в режиме `body` (после MVP) | снимок зависшего запроса `--debug-llm-snapshot=body` через `redactJson` (§17.10.10) | до записи файла снимка |
| `export` (после MVP) | весь документ экспорта траектории (§17.13.3), без освобождений: результаты write/edit, аргументы вызовов и thinking тоже | при `codelab trajectory export`, до вывода |

Не редактируются (кроме слоя `exact` в логе — лог редактируется всегда целиком):

1. **Результаты `write` и `edit`** и инструментов из `redact.exempt_tools` (например,
   MCP-инструмента записи файла): их текст и `diff` — это код, который написала модель.
   Замена внутри него дала бы модели `[REDACTED]` как исходный текст следующей правки, и правка
   записала бы маркер в файл. Признак — `AgentTool.redactResult == false` (§6.2): у `write` и
   `edit` — `false`, у остальных встроенных — `true`, у MCP — `true`, если инструмент не указан в
   `redact.exempt_tools`. В точке `providerRequest` их результаты тоже не трогаются.
2. **Аргументы вызовов `toolCall`** в payload и аргументы, уходящие в инструмент (`exec`
   получает настоящую команду). В журнале аргументы освобождённых инструментов хранятся как
   есть; аргументы прочих — через `redactJson`.
3. **Блоки `ThinkingContent`**: подпись рассуждения проверяется провайдером, любая правка текста
   делает блок недействительным (§2.8). В них может оказаться только то, что модель уже видела,
   а видела она текст после редакции.

### 12.4.3. Конфигурация и команда `/redact`

```yaml
redact:
  enabled: true
  layers: [exact, credential_files, formats, pem, connection_strings, key_values]   # entropy выключен
  allowlist:
    builtin: [git_sha, uuid]
    patterns: ["pk_test_[A-Za-z0-9]{24,}"]       # полное совпадение
  exempt_tools: [mcp__files__write_file]
```

| Ключ | Тип | По умолчанию | Смысл |
|---|---|---|---|
| `redact.enabled` | bool | `true` | `false` — работает только слой `exact`; при старте warning `redact.config.disabled` |
| `redact.layers` | string[] из имён слоёв | шесть слоёв без `entropy` | включённые слои; порядок в списке не важен — приоритет фиксирован; без `exact` → он всё равно включён, warning `redact.config.exact_forced`; неизвестное имя — `ConfigException` |
| `redact.allowlist.builtin` | string[] из `git_sha`, `uuid` | `[git_sha, uuid]` | встроенные записи белого списка |
| `redact.allowlist.patterns` | string[] регулярных выражений | `[]` | свои записи; невалидное выражение — `ConfigException` с путём ключа |
| `redact.exempt_tools` | string[] имён инструментов | `[]` | дополнительно к `write` и `edit` |
| `redact.block` | bool | `false` | P-18: `read`, команды-читатели `exec` и `search` не читают файлы учётных данных; отказ до разрешений (§17.12.7) |
| `redact.command_rewrite` | bool | `true` | P-14: секрет в команде `exec` заменяется ссылкой на переменную окружения (§17.12.6) |

Доверие (§15.3): проектный слой может только ужесточать — `enabled: true`, добавлять слои,
убирать записи `allowlist`; `enabled: false`, удаление слоёв, новые `allowlist.patterns` и
`exempt_tools` из проекта без `trusted_projects` игнорируются с предупреждением
`config.project.untrusted_key`. После MVP: `redact.block = true` и `redact.command_rewrite = true` из
проекта применяются всегда; `redact.block = false` и `redact.command_rewrite = false` — только при
доверии (§17.12.6, §17.12.7). Живая перезагрузка: со следующего вызова `redact` (без
перезапуска).

Агентская команда `/redact stats | layers` (§13.6) отвечает `agent_message_chunk` и
`stopReason: end_turn`, в журнал не пишется и модели не отправляется. Значения секретов, их длина
и позиции не печатаются никогда. Счётчики — в памяти процесса с момента открытия сессии.

```text
/redact stats
Redaction: enabled
Replacements in this session: 5
  exact: 1
  credential_files: 0
  formats: 3
  pem: 1
  connection_strings: 0
  key_values: 0
  entropy: off

/redact layers
Redaction: enabled
Layers in priority order:
  1. exact               on
  2. credential_files    on
  3. formats             on
  4. pem                 on
  5. connection_strings  on
  6. key_values          on
  7. entropy             off
Allowlist: git_sha, uuid; 1 custom pattern
Exempt tools: write, edit, mcp__files__write_file
```

После MVP (§17.12.6, §17.12.7): вывод `/redact stats` получает строку `Blocked credential reads: <n>`,
`/redact layers` — строки `Block mode: on|off` и `Command rewrite: on|off`.

Без аргумента или с другим аргументом — `Usage: /redact stats | layers`. При `enabled: false`
первая строка — `Redaction: disabled (only known secrets are replaced)`, у слоёв 2–7 — `off`.

## 12.5. Protocol trace

ACP-адаптер пишет каждый JSON-RPC-кадр в trace-sink хоста (по умолчанию — файл
`$CODELAB_HOME/logs/acp-trace.jsonl`, ротация по 10 МиБ, 3 файла). Одна строка — один кадр:

```json
{"ts":"2026-10-21T08:00:01.002Z","dir":"in","kind":"request","id":7,"method":"session/prompt","session_id":"01JB8Q2W6R9T3M5K7N1P4X8Z0C","bytes":214}
{"ts":"2026-10-21T08:00:03.511Z","dir":"out","kind":"notification","method":"session/update","update":"tool_call","session_id":"01JB8Q2W6R9T3M5K7N1P4X8Z0C","bytes":388}
{"ts":"2026-10-21T08:00:03.530Z","dir":"out","kind":"request","id":"perm-3","method":"session/request_permission","session_id":"01JB8Q2W6R9T3M5K7N1P4X8Z0C","bytes":902}
{"ts":"2026-10-21T08:00:09.120Z","dir":"in","kind":"response","id":"perm-3","method":"session/request_permission","duration_ms":5590,"bytes":96}
{"ts":"2026-10-21T08:00:12.004Z","dir":"out","kind":"response","id":7,"method":"session/prompt","duration_ms":11002,"error_code":null,"bytes":52}
```

| Поле | Смысл |
|---|---|
| `dir` | `in` (от клиента) или `out` (агенту → клиенту) |
| `kind` | `request`, `response`, `notification` |
| `id`, `method` | JSON-RPC id и метод; для ответа метод берётся из таблицы ожидающих запросов |
| `update` | значение `sessionUpdate` для `session/update` |
| `duration_ms` | для ответа — время от запроса с тем же id |
| `error_code` | код JSON-RPC ошибки ответа или `null` |
| `bytes` | размер кадра в UTF-8 |
| `payload` | **только** при `logging.trace_payload = true` и только в debug-сборке; после `redactJson` |

В release-сборке `trace_payload` игнорируется с предупреждением в лог (`AGENTS.md` §16).

## 12.6. Метрики и usage

```dart
final class TurnUsage {
  final int input, output, cacheRead, cacheWrite; final int? reasoning;
  final double? cost;              // null, если у модели нет цен
  final int steps, toolCalls, retries; final Duration duration;
  final List<ModelRef> models;     // все модели хода, если был fallback
  final Usage? subagentUsage;      // после MVP: сумма usage детей хода (§17.3.4, SUB-11); входит в итог
}
```

`TurnEnded.usage` — сумма `usage` всех шагов хода, включая неудачные попытки (§2.4) и вызовы
суммаризатора при аварийном сжатии (отдельной строкой `compactionUsage`). `ModelRequested`
несёт оценку токенов запроса (§9.3). В ACP usage не передаётся (стандартного поля нет); он
пишется в лог `turn.end`. Форма передачи клиенту (`_meta` в ответе `session/prompt`, отдельное
уведомление или иная) решается OpenSpec change `add-usage-extension` после этапа 9 (§16.3,
dart-agent-and-clients §12.1.5).

### 12.6.1. Журнал usage сессии (L-29)

`usage.json` — свёртка usage всех записей журнала сессии: по шагам, моделям, веткам, субагентам и
вызовам суммаризатора. Это **производный** файл: его можно удалить в любой момент, он
пересчитывается из журнала и никогда не служит источником истины — ядро не читает его ни для
бюджета (§5.2), ни для сжатия (§9), ни для опций. Поэтому после сбоя, ремонта хвоста журнала
(§8.6) или fork (§17.6.7) он не расходится с журналом: устаревшая версия просто пересчитывается.

**Расположение** — каталог сессии (§8.9): `<файл журнала без .jsonl>/usage.json`, например
`sessions/work-demo-9c3e51a7/2026-10-21T08-00-00-000Z_01JB8Q2W6R9T3M5K7N1P4X8Z0C/usage.json`.
Удаление сессии удаляет его вместе с каталогом.

**Формат** (`Usage` — форма §8.2.3; ключи в указанном порядке, `null` опускается):

```json
{
  "version": 1,
  "sessionId": "01JB8Q2W6R9T3M5K7N1P4X8Z0C",
  "source": {"bytes": 482113, "records": 214, "lastRecordId": "q1w2e3r4"},
  "steps": 37,
  "total": {"input": 120800, "output": 8200, "cacheRead": 902000, "cacheWrite": 41000, "reasoning": 1200,
            "cost": {"input": 0.302, "output": 0.082, "cacheRead": 0.2255, "cacheWrite": 0.0}},
  "inherited": null,
  "byModel": [{"model": "openai/gpt-4o", "steps": 30, "usage": {"…": "…"}}],
  "byBranch": [{"leafId": "c4d5e6f7", "active": true, "steps": 20, "usage": {"…": "…"}, "exclusive": null},
               {"leafId": "a1b2c3d4", "active": false, "steps": 17, "usage": {"…": "…"}, "exclusive": {"…": "…"}}],
  "subagents": {"runs": 2, "usage": {"…": "…"}},
  "summaries": {"count": 1, "usage": {"…": "…"}},
  "stepRecords": [{"recordId": "q1w2e3r4", "model": "openai/gpt-4o", "usage": {"…": "…"}}]
}
```

**Алгоритм свёртки** (чистая функция байтов журнала):

```text
rebuild(journalPath):
1. bytes := файл журнала целиком; записи разбираются тем же читателем, что при открытии (§8.6),
   но без ремонта на диске: неразбираемая строка пропускается; header := первая запись;
   после MVP журнал из нескольких сегментов читается сканером §17.13.2 сегмент за сегментом;
   записи hide и pin usage не несут
2. для каждой записи r в порядке файла:
   a. message с role assistant и usage → шаг: steps += 1; total += u;
      byModel["<provider>/<id>"] += u; stepRecords.add(r.id, model, u)
   b. subagent, последняя запись своего subagentId в файле, status завершён и usage есть →
      subagents.runs += 1; subagents.usage += u; total += u      // журналы детей не читаются
   c. compaction или branch с details.usage → summaries.count += 1; summaries.usage += u; total += u
   c'. после MVP: toolResult с auxUsage {model, usage} (вспомогательный запрос инструмента,
      inspect_image, §17.11.5) → total += usage; byModel[model] += usage; шагом не считается
   d. прочие записи и поля (spill, diff, toolMeta, outcome) не влияют
3. ветки: leaves := записи, чей id не является parentId ни одной записи; для каждого листа
   path := pathToLeaf (§8.4); usage := сумма usage-записей шага 2 на path;
   active := лист активной ветки по правилу §8.4; exclusive := сумма тех же записей на path,
   которых нет на пути активной ветки (у активной — null)
   порядок byBranch: активная первой, затем по позиции листа в файле
4. fork: header.forkedFrom есть → inherited := сумма usage-записей шага 2, являющихся предками
   записи forkedFrom.recordId или ею самой (их скопировал fork, §17.6.7); иначе null
5. byModel — по model лексикографически; суммирование — в порядке файла; каждое значение cost
   округляется до 10⁻⁶ при записи
6. source := {bytes: длина файла, records: число разобранных записей, lastRecordId: id последней}
7. JSON без пробелов вне строк, ключи в порядке формата, перевод строки в конце
```

Один и тот же журнал даёт побайтово один и тот же `usage.json`: в файле нет времени построения
и других значений вне журнала.

**Когда пересчитывается.** Файл **свежий**, если он разбирается, `version == 1` и `source.bytes`
и `source.lastRecordId` совпадают с текущим журналом (журнал только дописывается; ремонт хвоста
меняет длину). Иначе — устаревший.

1. `/usage` — файл свежий → показать; отсутствует, битый или устаревший → `rebuild`, записать,
   показать (лениво: ядро не пересчитывает файл после каждого хода).
2. `/usage rebuild` — `rebuild` всегда, независимо от свежести.
3. Запись — `usage.json.tmp` → `rename`, без `fsync` (файл производный). Сбой записи →
   warning `usage.ledger.write_failed {session_id, reason}`, отчёт всё равно показывается. Сессия
   только для чтения (§17.6.8) → свёртка в памяти, на диск не пишется.
4. Каждый пересчёт — лог info `usage.ledger.rebuild {session_id, reason: missing|invalid|stale|explicit,
   records, bytes, duration_ms}`.

**Вывод `/usage`** — агентская команда (§13.6), ответ `agent_message_chunk` и
`stopReason: end_turn`, в журнал не пишется, модели не отправляется. Текст фиксированный,
английский; числа — целые без разделителей, стоимость — `$` и 4 знака после точки; строка
`reasoning <n>` — только если значение есть. Шаблон строки usage:
`input <n>, output <n>, cache read <n>, cache write <n>[, reasoning <n>], cost $<x.xxxx>`.

```text
Session usage: 37 steps
Total: input 120800, output 8200, cache read 902000, cache write 41000, reasoning 1200, cost $0.6095
By model:
  openai/gpt-4o: 30 steps, input 100000, output 7000, cache read 800000, cache write 0, cost $0.4500
  anthropic/claude-sonnet-4: 7 steps, input 20400, output 1200, cache read 102000, cache write 41000, cost $0.1585
By branch:
  * c4d5e6f7: 20 steps, input 80400, output 5200, cache read 600000, cache write 41000, cost $0.4085
    a1b2c3d4: 17 steps, exclusive input 40000, output 3000, cache read 302000, cache write 0, cost $0.2000
Subagents: 2 runs, input 400, output 0, cache read 0, cache write 0, cost $0.0010
Summaries: 1, input 0, output 0, cache read 0, cache write 0, cost $0.0000
Ledger: rebuilt from journal (214 records)
```

Правила строк: `Total` — сумма шагов, субагентов и суммаризатора; `By model` — только шаги.
`Inherited from fork: <usage>` — сразу после `Total`, только при `inherited`; блок `By branch` —
только если веток больше одной, активная ветка помечена `*` и показывает usage своего пути,
остальные — usage, которого нет на активном пути, со словом `exclusive` перед ним; `Subagents` и `Summaries` — только при
ненулевом счётчике. Последняя строка — одна из: `Ledger: up to date (<n> records)`,
`Ledger: rebuilt from journal (<n> records)`, `Ledger: rebuilt in memory (read-only session)`,
`Ledger: rebuilt, not saved (<причина ОС на английском>)`. Пустая сессия — одна строка
`Session usage: no model requests yet`. Модели без цен дают `cost $0.0000` — цены неизвестны (§2.12).

## 12.7. Инварианты

1. **OBS-1.** Ни один публичный метод ядра не бросает для ожидаемых сбоев провайдера, сети и окружения.
2. **OBS-2.** Секреты не попадают в лог, журнал сессии, protocol trace, payload `AgentError` и в текст результата инструмента, отправляемый модели.
3. **OBS-3.** Каждая запись лога о вызове инструмента содержит `session_id`, `turn_id` и `tool_call_id`.
4. **OBS-4.** Ошибки fire-and-forget операций (фоновое сжатие, запись журнала, отправка уведомления) логируются, а не теряются.
5. **OBS-5.** Редакция идемпотентна и применяется до сохранения, а не при показе.
6. **OBS-6.** В release-сборке protocol trace не содержит payload кадров.
7. **OBS-7.** Файловый sink лога (§12.3.1) получает те же записи после той же редакции, что основной sink; ни один sink не пишет в stdout процесса с ACP по stdio.
8. **OBS-8.** Послойная редакция сохраняет число переводов строк текста; перекрывающиеся совпадения решает слой с более высоким приоритетом; белый список не отменяет слои `exact` и `credential_files`.
9. **OBS-9.** Результаты `write`, `edit` и инструментов из `redact.exempt_tools` не редактируются ни перед журналом, ни перед провайдером; все остальные точки таблицы §12.4.2 редактируются всегда, в том числе при `redact.enabled = false` слоем `exact`.
10. **OBS-10.** `usage.json` — чистая функция байтов журнала: одинаковый журнал даёт побайтово одинаковый файл; ядро не читает его для решений; файл, не совпадающий с журналом по `source`, пересчитывается до показа.

## 12.8. Обоснование решения

* **Ошибки работы — события.** Агент работает минутами; исключение посреди хода теряет
  частичный результат и состояние. Событие сохраняет ход завершённым и диагностируемым.
* **Редакция до записи.** Журнал сессии живёт дольше лога и может быть отправлен в отчёт об
  ошибке; секрет, попавший туда, уже не удалить без переписывания (SES-1).
* **Свои шаблоны, точные значения первыми.** Шаблоны ловят чужие ключи в выводе команд, точные
  значения — свои ключи любого формата. Порядок «длинные первыми» не оставляет хвостов.
* **Trace без payload по умолчанию.** Метаданных кадров хватает, чтобы восстановить порядок и
  задержки; payload нужен редко и опасен.
* **Слои с приоритетом вместо цепочки замен.** Последовательные `replaceAll` зависят от порядка:
  ранний шаблон съедает часть секрета, поздний не узнаёт остаток, и в тексте остаётся хвост.
  Совпадения всех слоёв по исходному тексту и выбор по приоритету дают один ответ на любое
  перекрытие и упрощают доказательство идемпотентности.
* **Число строк неприкосновенно.** Модель правит файлы по номерам строк из `read`; редакция,
  которая сдвигает строки, ломает следующую правку тише, чем любая утечка была бы заметна.
* **Код модели не редактируется.** Маркер внутри результата `edit` становится исходным текстом
  следующей правки и попадает в файл пользователя. Модель не может «узнать» секрет из
  собственного кода — она его и написала.
* **Повторная редакция перед провайдером.** Набор известных секретов растёт во время сессии, а
  история в журнале могла быть записана старыми правилами. Проход по всему контексту с кэшем по
  поколению стоит одной регулярки на новый текст.
* **`usage.json` — кэш, а не учёт.** Второй источник истины разошёлся бы с журналом после
  первого сбоя записи. Свёртка детерминирована и дёшева, поэтому её проще пересчитать, чем
  синхронизировать.
* **Лог в файл без ротации.** Несколько процессов дописывают один файл; ротация из процесса
  требует межпроцессной блокировки, а внешняя ротация уже есть у ОС. Предупреждение о размере
  покрывает главный риск — незаметно растущий файл.

## 12.9. Как проверить

* Тест с секретом в env, в аргументах команды и в выводе `exec`: лог, JSONL, trace, `AgentError` и запрос к модели (scripted LLM записывает payload) не содержат значения (OBS-2).
* Табличный тест `redact` на каждый шаблон: позитивные и негативные примеры (`sk-` в слове `task-list` не трогается), идемпотентность (OBS-5).
* Тест-перехватчик `Logger` в сценариях с инструментами: у каждой записи `tool.*` есть корреляционные поля (OBS-3).
* Тест «сбой записи журнала»: fake `SessionStore` бросает на `append` → запись `session.append.failed` в лог, `AgentError(storage)`, `TurnEnded(failed)` (OBS-4, SES-8).
* Тест «провайдер отвечает 500 на все 4 попытки» (`transient_retries: 3`): `prompt()` не бросает, `TurnResult.reason == failed` (OBS-1).
* Тест release-конфигурации trace: `trace_payload = true` в release → payload отсутствует, предупреждение в логе (OBS-6).
* `cli/log-file-tee-redacted` (`log_file_tee_test.dart`, процесс `codelab-agent serve --stdio`): с секретом в окружении и `--log-file <tmp>` — каждая запись stderr есть в файле в том же порядке, значения секрета нет ни там, ни там; stdout содержит только JSON-RPC-кадры; `CODELAB_LOG_FILE` без флага — файл по переменной; флаг и переменная вместе — побеждает флаг; `--log-file -` → код `64`; путь в несуществующем каталоге без прав → код `64`; повторный запуск дописывает файл (OBS-7).
* `core/redaction-before-journal` (`redaction_points_test.dart`): секрет в промпте пользователя, в выводе `exec`, в `.env`, прочитанном `read`, и в выводе фоновой задачи — журнал, лог, файл выноса и payload scripted LLM не содержат значения; секрет, зарегистрированный `addExactSecret` после записи истории, заменяется в следующем запросе к модели, но не в журнале (OBS-2, OBS-9).
* `core/redaction-preserves-line-count` (`redaction_layers_test.dart`): табличный тест на каждый слой и каждую пару перекрывающихся слоёв — победитель по приоритету; многострочный PEM внутри результата `read` с номерами строк — число строк и номера следующих строк не меняются; `redact(redact(x)) == redact(x)` на всём корпусе; git SHA и UUID не трогаются слоями 3–7, но точный секрет вида UUID заменяется; `entropy` выключен по умолчанию (OBS-5, OBS-8).
* `core/redaction-write-results-exempt` (`redaction_exempt_test.dart`): `write` и `edit` с содержимым `API_KEY=sk-…` — результат, `diff` в журнале и аргументы в payload следующего шага без маркеров; тот же текст в результате `exec` заменён; MCP-инструмент из `redact.exempt_tools` не редактируется, не указанный — редактируется (OBS-9).
* `redact_command_test.dart`: `/redact stats` и `/redact layers` дают фиксированный текст §12.4.3, без значений; `/redact` без аргумента — `Usage: /redact stats | layers`; ни одной записи в журнале.
* `core/usage-ledger-rebuild-deterministic` (`usage_ledger_test.dart`): журнал с ветками, fork, субагентом и сжатием — `rebuild` дважды даёт одинаковые байты; удалённый `usage.json` восстанавливается побайтово тем же; дописанная запись делает файл устаревшим, `/usage` пересчитывает; обрезанный ремонтом хвост — тоже; `inherited` у fork равен сумме скопированных шагов; поля `spill` не влияют на результат; вывод `/usage` совпадает с golden-текстом (OBS-10).

---

← [11. Промпты](11-prompts.md) · [Оглавление ядра](../agent-core-architecture.md) · [13. ACP-адаптер](13-acp-adapter.md) →
