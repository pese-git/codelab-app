Решения Q1–Q5 — все (a) (design.md, «Решённые вопросы»): Q1–Q3 и Q5 принял пользователь, Q4 — координатор.

Порядок: 0 → 1 → 2 → 3; 4 и 5 — после 1–2, независимы друг от друга; 1.9–1.11 (по ревью) — после 1.5, 4.3 — после 1.10; 6 — последней.

TDD (вложенные `AGENTS.md`): красный тест каждой пары коммитится отдельно до кода — только по явной просьбе пользователя. Маркер утечки во всех тестах — `sk-test-leak-0123456789`. Каждый тест безопасности проверяет, что маркера нет там, куда тест смотрит: лог (`LogRecord` до редакции), `lastError`, `McpServerSummary`, журнал сессии, вывод команды. То, что хранилище не читалось ради заблокированного сервера, проверяется на двух уровнях, без счётчика в сквозных тестах: загрузка — у сервера пуст `secretValues` (раскрывать нечего), мигратор — `_SpyStore.reads` в `secret_migrator_test.dart`.

## 0. Документы

- [x] 0.1 `[agent]` Документы ядра до кода (выполнено архитектором 2026-11-13) (`codelab_agent_core/AGENTS.md`, «сначала документ»; design.md, D9):
  - `docs/architecture/proposals/agent-core/15-configuration.md`:
    - абзац «Группа провайдера и привязка ключа к адресу» — пункт про `mcp.servers`: сервер из одного слоя (слияние по `name`), правило 3 для HTTP-серверов (`headers`, `${ENV}` в `url`), stdio — граница доверия (D1), `config.mcp.key_unbound`, `blockedReason`;
    - строка таблицы доверия «`${secret:<name>}` в `headers`, `env`» — привязка к origin для HTTP-серверов;
    - §15.5 «Подстановка» — `${ENV}` в `url` и `headers` HTTP-сервера проектного слоя не раскрывается без привязки.
  - `docs/architecture/proposals/agent-core/17-5-agent-setup.md`:
    - §17.5.4 «секреты MCP-серверов» — сервер с `blockedReason` не раскрывается и не подключается;
    - §17.5.5 мигратор — абзац рядом с D26 (около строки 1070) по D7;
    - §17.5.7 — состояние `failed` с причиной блокировки, повтор без ввода-вывода.

## 1. Ядро: ссылки, привязка, загрузка (`codelab_agent_core`)

- [x] 1.1 `[agent]` Тест-закрепление D2 (зелёный сразу; agent-configuration «MCP-серверы конфигурации», сценарий «Сервер проектного слоя заменяет сервер пользователя целиком»): `test/config/config_mcp_servers_test.dart`. Элемент `github` в `projectLocal` поверх элемента пользователя с заголовком-шаблоном — в `CoreConfig.mcpServers` один `github` без `headers` и `secretValues` пользователя. Там же сценарий «Выключенный сервер доходит до коннектора» (D10).
- [x] 1.2 `[agent]` Красные тесты привязки, `test/config/config_provider_key_binding_test.dart` (D3; agent-secrets «Ссылки MCP-сервера проектного слоя привязаны к адресу», п. 3):
  - `mcpServerReferences`: `${secret:…}` и `${ENV}` в `headers.*` с `field` `headers.<Name>`, `${ENV}` в `url` с `field` `url`, `$${` — литерал;
  - `mcpServerOrigin`: регистр хоста, порт по умолчанию, незаданная переменная → `null`, не-http → `null`;
  - `ProviderKeyBinding.fromLayers` собирает ссылки глобальных HTTP-серверов MCP с origin их `url`; глобальные stdio-серверы и проектные слои привязок не дают; ссылка провайдера привязывает тот же origin для MCP (сценарий «Привязка через провайдера»).
- [x] 1.3 `[agent]` Реализация 1.2: `lib/src/config/provider_binding.dart`. Doc-комментарии `ProviderKeyBinding` и `ProviderReference` обновить: привязки из провайдеров и HTTP-серверов MCP (§15).
- [x] 1.4 `[agent]` Красные тесты загрузки, `test/config/config_mcp_key_binding_test.dart` (новый файл; agent-secrets «Ссылки MCP-сервера проектного слоя привязаны к адресу», пп. 3–5; D4, D5). Сценарии:
  - «Закоммиченный сервер уводит секрет пользователя на свой адрес» — уровень загрузки: `blockedReason` с текстом, `secretValues` без шаблона, `config.mcp.key_unbound {server, source, reference_kind: secret}` с ключом `mcp.servers[relay].headers.Authorization`;
  - «Переменная в заголовке закоммиченного сервера» — переменная `GITHUB_TOKEN=sk-test-leak-0123456789` в `environment`: маркера нет ни в `McpServerConfig`, ни в `warnings`, ни в `ConfigLoadResult.values`;
  - «Переменная в адресе закоммиченного сервера» — `url` без значения переменной, ключ предупреждения `mcp.servers[relay].url`;
  - «Сервер «This project only» работает», «Та же ссылка, связанная глобально с тем же адресом», «Привязка через провайдера» — `blockedReason == null`, шаблон на месте;
  - «Stdio-сервер доверенного проекта» — не судится;
  - имя-значение в ссылке (`literalSecretTag`) → в причине `a reference`;
  - длинное имя секрета (128 символов) — совет `move the server to …` целиком в первых 200 символах причины;
  - выключенный сервер — без предупреждения, `blockedReason` есть;
  - недоверенный проект — прежнее `config.project.untrusted_key`, `config.mcp.key_unbound` нет.
- [x] 1.5 `[agent]` Реализация 1.4:
  - `lib/src/mcp/mcp_server_config.dart`: `blockedReason` в конструкторах обеих ветвей, `withEnabled`, `withSecrets`, `sameConnection`; `toString` без него;
  - `lib/src/config/resolve.dart`: `_buildMcpServer` — проверка до `_interpolate` / `expand`, `_reportMcpUnbound` по образцу `_reportUnbound`.

  Комментарии — со ссылкой на D4 и требование.
- [x] 1.6 `[agent]` Красный `test/public_api_test.dart` (поле `McpServerConfig.blockedReason`, экспорт `mcpServerReferences`, `mcpServerOrigin` через `show`) → экспорт в `lib/codelab_agent_core.dart`.
- [x] 1.7 `[agent]` Красные тесты перезагрузки, `test/runtime/mcp_apply_config_test.dart` и `test/config/config_reload_plan_test.dart` (п. 6; D6):
  - снятие привязки правкой пользовательского слоя → проектный сервер заменён в живой сессии корня (`FakeMcpConnector` получил сервер с `blockedReason`);
  - появление привязки — заменён без причины;
  - сессия другой папки (`_isolated`) не тронута (сценарий «Пользователь снимает привязку перезагрузкой»).

  Реализация — 1.5 (`sameConnection`); если тесты требуют ещё кода в `config_reload_plan.dart`, — здесь же.
- [x] 1.8 `[agent]` Тест сессии другой папки, `test/runtime/config_outside_root_test.dart` (сценарий «Сессия другой папки»): сервер `/work/b` приходит коннектору с `blockedReason`, предупреждение записано портом загрузки папки.

- [x] 1.9 `[agent]` Красные тесты D12, `test/config/config_mcp_key_binding_test.dart` (agent-secrets «Ссылки MCP-сервера проектного слоя привязаны к адресу», п. 7; сценарии «Stdio-сервер закоммиченного конфига со ссылкой на секрет», «Тот же stdio-сервер в config.local.yaml»):
  - stdio-сервер слоя `project` с `${secret:…}` в `env` → ровно одно предупреждение `config.mcp.stdio_secret_reference` с ключом `mcp.servers[docs]`, полями `{server, source}` и текстом `a stdio server from the committed project config receives a secret reference; it runs as you, so move it to config.local.yaml if you did not write it`; шаблон в `secretValues` на месте, сервер не заблокирован;
  - два `${secret:…}` в `env` одного сервера — одно предупреждение;
  - нет предупреждения: `projectLocal`, пользовательский слой, `${NAME}` в `env`, HTTP-сервер, выключенный сервер;
  - имени секрета нет ни в полях, ни в тексте.
- [x] 1.10 `[agent]` Реализация 1.9: `lib/src/config/resolve.dart`, `_buildMcpServer`, ветка `stdio` (design.md, D12). Документ — п. 3 абзаца D23 в `15-configuration.md` (уже обновлён).
- [x] 1.11 `[agent]` Тесты сценариев «Ссылка на секрет в url — проблема загрузки» и «Имя ссылки, не проходящее правило имени» в `test/config/config_mcp_key_binding_test.dart` (D1, D5). Если они красные — правка в `resolve.dart`.

## 2. Коннектор (`codelab_agent_mcp`)

- [x] 2.1 `[agent]` Красные тесты, `test/supervisor/mcp_supervisor_state_test.dart`, группа `blocked` (D4; agent-secrets п. 4):
  - сервер с `blockedReason` → `failed`, `lastError` = причине, `mcp.server.failed` с той же причиной, фабрика транспорта и функция раскрытия не вызывались;
  - повтор по расписанию снова без транспорта и раскрытия;
  - `setEnabled(name, true)` выключенного заблокированного сервера → `failed` с причиной;
  - `close()` во время ожидания повтора — без таймеров и процессов.
- [x] 2.2 `[agent]` Реализация 2.1: `lib/src/connector.dart`, `_connectOnce` — проверка `blockedReason` первой.
- [x] 2.3 `[agent]` Сквозной тест на настоящем коннекторе, `packages/dart/codelab_embedded/test/fake_mcp_http_host_test.dart`: доверенный проект с HTTP-сервером на адресе фейкового хоста и непривязанной ссылкой на секрет → сессия создана, запросов к фейковому хосту 0, `McpStatusPort` даёт `failed` с причиной (`lastError`); затем тот же сервер в `config.local.yaml` → подключён, заголовок пришёл (сценарии «Закоммиченный сервер уводит секрет…», «Сервер «This project only» работает»). Чтения хранилища здесь не считаются (хрупко): их проверяют 1.4 (`secretValues` пуст) и 3.1 (`_SpyStore.reads`).

## 3. Мигратор (`codelab_agent_io`)

- [x] 3.1 `[agent]` Красные тесты, `test/secrets/secret_migrator_test.dart` (D7; agent-secrets «Подкоманда secret migrate», MODIFIED). Сценарии:
  - «HTTP-сервер закоммиченного конфига переносится в config.local.yaml»;
  - «Чужая ссылка в сервере не переносится» — `${secret:…}` и `${ENV}` в заголовке, `${ENV}` в `url`;
  - «config.local.yaml уже переопределяет сервер»;
  - «Stdio-сервер закоммиченного конфига — как раньше»;
  - «Значение HTTP-сервера, которое хранилище не примет» — строка `not migrated: mcp.servers[<name>] in <path>: a value of this server cannot be stored; move it by hand`, файлы и хранилище не меняются, все находки сервера на месте (тест уже есть);
  - находки в `headers` и `env` одного HTTP-сервера переезжают вместе, у каждой в копии — ссылка;
  - повтор после сбоя между записью `config.local.yaml` и `config.yaml` (R8-11);
  - `--dry-run` — тот же план;
  - недоверенный проект — прежняя строка.

  Перенесённый итог загружается без `config.mcp.key_unbound`.
- [x] 3.2 `[agent]` Реализация 3.1: `lib/src/secrets/secret_migrator.dart` (планирование рядом с `_planMoves`, проверка ссылок через `ProviderKeyBinding` по непроектным слоям), `SecretMcpServerMovedItem` с `describe()`; экспорт в `lib/codelab_agent_io.dart`, `packages/dart/codelab_setup/lib/io.dart`, `packages/dart/codelab_embedded/lib/io.dart`.

## 4. Клиент: CLI (`apps/codelab_cli`)

- [x] 4.1 `[client]` Тест `apps/codelab_cli/test/config_command_test.dart` (сценарий «config check показывает предупреждение»): `codelab config check --cwd <проект>` с проектным HTTP-сервером и непривязанной ссылкой на секрет со значением маркера:
  - строка `warning: …: mcp.servers[relay].headers.Authorization: the reference is bound to another address and is not used`;
  - последняя строка `Config: valid`, код `0`;
  - маркера в stdout и stderr нет.

  Код CLI не меняется; если тест требует правки, это дефект ядра — вернуть в 1.5.
- [x] 4.2 `[client]` Тест `apps/codelab_cli/test/secret_command_test.dart`: `codelab secret migrate --project --cwd <проект>` печатает строку переноса сервера из 3.2 через мост `codelab_setup/io.dart`.

- [x] 4.3 `[client]` Тест `apps/codelab_cli/test/config_command_test.dart` (после 1.10; сценарий «Stdio-сервер закоммиченного конфига со ссылкой на секрет»): `codelab config check --cwd <проект>` со stdio-сервером `docs` в закоммиченном `config.yaml` и `${secret:…}` в `env`:
  - строка `warning: <location>: mcp.servers[docs]: a stdio server from the committed project config receives a secret reference; it runs as you, so move it to config.local.yaml if you did not write it`;
  - последняя строка `Config: valid`, код `0`;
  - тот же сервер в `config.local.yaml` — строки нет;
  - маркера и имени секрета в выводе нет.

## 5. Desktop (`apps/codelab_desktop`)

- [x] 5.1 `[desktop]` Тест `test/features/settings/application/mcp_settings_cubit_test.dart` (app-settings «Непривязанный MCP-сервер на странице MCP servers», сценарий «Заблокированный сервер в панели Agent status»):
  - порт статуса отдаёт `failed` с причиной → строка `McpStatusRow` с `lastError` как есть;
  - состояние без `McpRejectedConfig`;
  - события `mcp_settings.*` без маркера.
- [x] 5.2 `[desktop]` Виджет-тест `test/features/settings/presentation/mcp_page_test.dart`: таблица «Agent status» показывает `failed` и текст причины, `mcp-rejected` отсутствует.
- [x] 5.3 `[desktop]` Тест сценария «Сервер «This project only» не блокируется» на уровне кубита (запись в `projectLocal` фейкового писателя и загрузка итога без предупреждения привязки). Код desktop не меняется; если тесты требуют правки, сначала вернуться к design.md.

## 6. Проверка

- [x] 6.1 `[agent]` Проверки затронутого (§21):
  - `fvm dart format --set-exit-if-changed` изменённых файлов;
  - `fvm dart analyze` в `codelab_agent_core`, `codelab_agent_mcp`, `codelab_agent_io`, `codelab_setup`, `codelab_embedded`, `apps/codelab_agent`, `apps/codelab_cli`, `apps/codelab_desktop` (публичный API ядра изменён);
  - тесты этих пакетов;
  - `melos run guard`, `melos run web-compile` (ядро и мосты web-безопасны), `melos run conformance:agent`, `melos run test:e2e:cli:dart-agent`.
- [x] 6.2 `[agent]` `openspec validate bind-mcp-secrets-to-origin --strict`.
