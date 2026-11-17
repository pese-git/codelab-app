Задачи идут парами «тест → реализация» (TDD, `packages/dart/codelab_agent_core/AGENTS.md` §2). Первая задача каждой группы с кодом — красные тесты, затем код до зелёного. В скобках — сценарий спецификации этого change (`specs/agent-runtime/spec.md`) или решение design.md. Красный тест коммитится отдельно до кода; коммит — только по просьбе пользователя.

Метки исполнителей:
- `[agent]` — `codelab_agent_core`, тесты `codelab_embedded` и `apps/codelab_agent`, документы ядра и `docs/user/`;
- `[desktop]` — документы `apps/codelab_desktop` (через `docs-writer`).

Задач `[protocol]` и `[client]` нет: ACP, клиентский слой и CLI не меняются (design.md, D7, D10).

Задачи с пометками «R0-1» и «Q2» входят в change: пользователь ответил на Q1 вариантом (a1) и на Q2 — «да» (2026-11-16, design.md, Open Questions).

Проверки — только затронутое (AGENTS.md §21):
- `fvm dart format --set-exit-if-changed` изменённых файлов;
- `fvm dart analyze` в `codelab_agent_core`;
- `fvm dart test` в `codelab_agent_core`, `codelab_embedded`, `apps/codelab_agent`;
- `openspec validate defer-restart-keys-in-folder-sessions --strict`.

`guard`, `web-compile` и `conformance:*` не требуются: импорты между пакетами, `pubspec.yaml`, ACP-проекция и web-безопасные барели не меняются. `test:e2e:cli:dart-agent` — по желанию, если исполнитель хочет проверить бинарь целиком.

## 0. Документы (до кода)

- [x] 0.1 `[agent]` `docs/architecture/proposals/agent-core/10-core-assembly-and-profiles.md`, абзац «Снимок на корень запуска и конфигурация сессии другой папки». Тройка сессии строится после подстановки отложенных частей из применённого снимка. Перекрытие — по паре снимков загрузки папки. Отказ по `permissions` при проектных слоях (design.md, D1–D5). `process_keys_ignored` — по паре снимков (D8).
- [x] 0.2 `[agent]` `docs/architecture/proposals/agent-core/17-5-agent-setup.md`:
  - абзац «Снимок — на корень запуска хоста»: отложенное действует для сессий всех папок;
  - таблица R0 (строки R0-1 и R0-4): «только после перезапуска» — для всех сессий процесса;
  - смысл `pendingRestartKeys` (D7);
  - остаточный риск Q4.
- [x] 0.3 `[agent]` `docs/architecture/proposals/agent-core/12-observability-and-errors.md`: строки `config.session.project` (`process_root`), `config.session.restart_pending` и `config.session.process_keys_ignored` в таблице событий `config` (D6, D8).

## 1. Подстановка отложенного для сессии папки (чистая функция)

- [x] 1.1 `[agent]` Красные тесты `packages/dart/codelab_agent_core/test/config/folder_session_config_test.dart`. Снимки строятся через `CoreConfig.fromLayers`: база с проектными слоями корня и без них, загрузка папки с проектными слоями и без. Случаи:
  - глобальная смена `api_key_env` → группа базы, модели папки, ключ `providers.<id>` («Глобальная смена api_key_env ждёт перезапуска и в другой папке»);
  - проектный провайдер `local` при глобальной правке другого провайдера — не тронут («Проектный провайдер доверенной папки работает сразу»);
  - проект задаёт `base_url` и `api_key_secret` глобального провайдера — перекрыт, подстановки нет («Проект перекрывает группу глобального провайдера»);
  - проект задаёт только `api_key_secret`, глобальный `base_url` изменён — группа базы целиком («Проект наследует изменённый адрес», D3);
  - новый глобальный провайдер с ключом и `agent.default_model` на него — исключён, модель базы («Новый глобальный провайдер с ключом не появляется в другой папке»);
  - новый провайдер без ключа — в снимке («Новый глобальный провайдер без ключа появляется сразу»);
  - HTTP-сервер с `${secret:…}` (R0-4) — элемент базы или отсутствие; HTTP без подстановок — из папки;
  - R0-1: новый stdio-сервер — отсутствует; изменённая `command` — элемент базы; выключение вместе с правкой `command` — элемент базы с `enabled: false` (R6-1) («Новый глобальный stdio-сервер ждёт перезапуска в другой папке»);
  - R0-1: проект заменил сервер своим элементом — из папки («Проект перекрывает сервер своим элементом»);
  - R0-1: проектный элемент равен новому глобальному — элемент базы, fail closed («Совпадение с глобальным значением не считается перекрытием», D1);
  - R0-1: `permissions.tools.exec: allow` в глобальном слое — без проектных слоёв папки раздел базы, с проектными — проблема по ключу `permissions` с текстом D4 («Глобальные права после старта…», оба сценария);
  - пустая `withoutProjectValues` при наличии `withoutProject` — всё различие отложено (D9);
  - ключи показа отсортированы; ни в ключах, ни в тексте проблемы нет `sk-test-leak-0123456789`, адресов и имён переменных;
  - сторожевой тест: каждое поле `DeferredConfigParts` имеет правило перекрытия (D5).
- [x] 1.2 `[agent]` Реализация в `packages/dart/codelab_agent_core/lib/src/config/folder_session_config.dart`. Шаги — `planConfigReload` по снимкам без проекта, фильтр `DeferredConfigParts` по перекрытию, `CoreConfig.withDeferred` (D2–D5). Doc-комментарии по §15 корневого `AGENTS.md`. Без экспорта из бареля. Если в `config_reload_plan.dart` нужен доступ к списку полей группы провайдера (`_providerGroup`), он открывается внутри пакета, а не копируется.
- [x] 1.3 `[agent]` Тесты по итогам ревью в `folder_session_config_test.dart`:
  - группа «a key supplied by the project layer (D23 (a), R0-4, D3)»: глобальный адрес изменён, ключ только из проекта → группа базы без ключа, `providers.p` в ключах («Ключ проекта не уходит на изменённый глобальный адрес»); проект задал свой адрес с ключом → его группа; адрес не менялся → ключ проекта работает сразу;
  - «the pair of snapshots of the folder (D9)»: `withoutProject` без `withoutProjectValues` у загрузки папки — ничто не перекрыто (D1);
  - «default model and new provider (D3, D5)»: проект повторил `kind` нового глобального провайдера — не перекрытие, провайдер исключён (D1, D5); резервная модель из проектного слоя корня — без ложного отказа `validateSnapshot` (D5);
  - папка задала свою `agent.default_model` при исключённом новом провайдере → снимок сессии проходит `validateSnapshot` (вложенный `withoutProject` снят, D2).
- [x] 1.4 `[agent]` Реализация: кандидаты-провайдеры с ключом из проектного слоя (`providerWithKey`, `providerGroupField` открыты внутри пакета в `config_reload_plan.dart`, D3); неизвестная пара — без перекрытия (D1, D9); sealed `FolderSessionConfig` (`FolderSessionAccepted`, `FolderSessionRefused`) и `CoreConfig.withoutNestedProject` (`@internal`, D2); неявная модель в `CoreConfig.withDeferred`, если модель базы вне каталога прежних провайдеров (D5).

## 2. Рантайм: открытие сессии другой папки

- [x] 2.1 `[agent]` Красные тесты в `packages/dart/codelab_agent_core/test/runtime/config_outside_root_test.dart` (фейковые `ProjectConfigLoader` и `ConfigSource`):
  - лог `config.session.project` с `process_root: /A`, без `config_root`; существующие проверки `config_root` переписываются на `process_root` («Лог называет корень процесса», D6);
  - глобальная правка провайдера с ключом после старта → ходы сессии `/B` идут с группой применённого снимка; лог `config.session.restart_pending` с `session_id`, `cwd`, `keys`; после «перезапуска» (новый рантайм с новым `initial`) — новая группа;
  - R0-1: отказ по `permissions` при проектных слоях → `ProjectConfigException`, журнала нет (`listSessions`), лог `config.session.project_invalid`;
  - перезагрузка корня завершается во время `loadForProject` → база — снимок начала открытия («Перезагрузка во время открытия не меняет базу», D9);
  - `configStatus().pendingRestartKeys` не меняется открытием, `checkConfig()` даёт предупреждение `config.reload.restart_required` по `providers.<id>` («Открытие сессии не меняет состояние перезапуска», D7);
  - Q2: глобальная правка `logging.level` после старта без перезагрузки и папка без ключей процесса → нет `config.session.process_keys_ignored`; папка с `sessions.dir` в `config.local.yaml` → есть («Глобальная правка ключа процесса не приписывается папке», D8);
  - сессия в корне — без изменений, `loadForProject` не вызывается.
- [x] 2.2 `[agent]` Реализация в `AgentRuntime._projectScope`:
  - вызов функции 1.2 между `loadForProject` и `validateSnapshot` на базе `start`;
  - проблема функции → `_refuseProject`;
  - событие `config.session.restart_pending`;
  - поле `process_root`;
  - Q2: `_ignoredProcessKeys` сравнивает `values` и `withoutProjectValues` загрузки папки.
  
  Обновить doc-комментарии `_sessionConfig`, `_projectScope` и полей `_projectLogged`, `_processKeysLogged`.
- [x] 2.3 `[agent]` Тест `a host without a ConfigSource has no applied values: global permissions are neither refused nor reported (no-config-source branch of _projectScope)` в `config_outside_root_test.dart` («Хост без ConfigSource не подставляет отложенное», D2).
- [x] 2.4 `[agent]` Реализация: ветка `_projectScope` без `ConfigSource` — загрузка папки как есть, без подстановки (D2). `session_id` в `config.session.project_invalid` не добавляется — follow-up (design.md, Risks).

## 3. Интеграция с настоящим `FileConfigSource`

- [x] 3.1 `[agent]` Красный интеграционный тест `apps/codelab_agent/test/agent_host_project_config_test.dart` (временные `CODELAB_HOME` и папки):
  - `serve --stdio`, корень `/A`, глобальный провайдер с `api_key_env: K1`;
  - после старта `config.yaml` переписан на `K2`;
  - `session/new` в `/B` без `.codelab/` → функция модели сессии получает ключ из `K1` (фейковый HTTP-клиент, проверка заголовка), лог `config.session.restart_pending`;
  - доверенный `/C` с `config.local.yaml`-провайдером работает сразу.
- [x] 3.2 `[agent]` Тот же сценарий для встроенного агента в `packages/dart/codelab_embedded/test/io/local_opener_test.dart` (открыватель `codelab_embedded/io.dart`).
- [x] 3.3 `[agent]` Исправления по итогам 3.1–3.2, если тесты не зелёные после группы 2. Код `codelab_agent_io` и `codelab_embedded` по плану не меняется (D10). Если изменение всё же нужно, сначала дополняется design.md.

## 4. Продуктовая документация (через `docs-writer`, `.claude/skills/codelab-docs/SKILL.md`)

- [x] 4.1 `[agent]` `docs/user/configuration.md`: правки «после перезапуска» действуют для всех открытых папок только после перезапуска агента (D7). Сессия другой папки читает её `.codelab/config*.yaml` при открытии. Отказ «restart the agent to open sessions in this folder» и что с ним делать (D4).
- [x] 4.2 `[desktop]` `apps/codelab_desktop/doc/user-guide.md`: исправить «Агент запускается в папке выбранного проекта». Выбор проекта агента не перезапускает (D15 change `require-project-folder`), сессии проекта берут его конфигурацию, а правки с пометкой «после перезапуска» применяет «Restart agent» для всех проектов. В таблицу неполадок — строка про отказ D4.
- [x] 4.3 `[agent]` README и `doc/` пакетов `codelab_agent_core` и `codelab_embedded` — сверить с D3–D8 и обновить, если там описана конфигурация сессии другой папки или поле `config_root`.

## 5. Завершение

- [ ] 5.1 `[agent]` Проверки §21 по затронутому (список в начале файла). В описании PR — какие проверки запускались. Полный `melos run check` не запускался.
- [ ] 5.2 `[agent]` Сверить код и документы (критерий (е) `codelab_agent_core/AGENTS.md` §3). Перед архивированием проверить, не архивирован ли `add-agent-skills`; если да — перенести его правки требования «Конфигурация сессии вне корня запуска» в эту дельту (design.md, «Связь с активными changes»).
