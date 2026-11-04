Задачи идут парами «тест → реализация» (dart-agent-and-clients §9.0, правило 3; `packages/dart/codelab_agent_core/AGENTS.md` §2). В скобках — требование спецификации этого change или решение design.md. Красный тест коммитится отдельно до кода; коммит — только по просьбе пользователя.

Метки исполнителей:
- `[agent]` — `codelab_agent_core`, `codelab_agent_io`, `codelab_setup`, `codelab_embedded`, `apps/codelab_agent`;
- `[client]` — `apps/codelab_cli`;
- `[desktop]` — `apps/codelab_desktop`;
- `[docs]` — `docs/architecture/**`, вложенные `AGENTS.md`.

Задач `[protocol]` нет: ACP не меняется (R8-1).

Итерации (design.md, D10) — каждая отдельным PR в `develop`:
- итерация 0 — документы;
- итерация 1 — распознавание и предупреждения загрузки;
- итерация 2 — писатель и R4-6;
- итерация 3 — `secret set|delete`, `secret migrate`, `mcp add --header-stdin|--env-stdin`;
- итерация 4 — codelab-app;
- итерация 5 — матрица и DoD.

Зависимости: 2 ← 1; 3 ← 1, 2; 4 ← 3; 5 ← все. Решения пользователя R8-1…R8-5 и сохранённые OQ — в design.md, «Open Questions».

Проверки каждой задачи — по `AGENTS.md` §21, только для затронутого:
- `fvm dart format` изменённых файлов;
- `fvm dart analyze` / `fvm flutter analyze` пакета;
- `fvm dart test` / `fvm flutter test` пакета;
- `fvm dart run melos run guard` — при правке импортов;
- `fvm dart run melos run web-compile` — при правке ядра и основного бареля `codelab_embedded`.

Полный `melos run check` — в CI pull request. Временные `CODELAB_HOME` и `cwd`; `FakeClock`; процессные тесты — с `Timeout(Duration(seconds: 60))`; `test:e2e:app:*` не запускаются.

Пункт ревью каждой итерации (D3): шаблоны написаны по §12.4 и публичным описаниям форматов; ничего не скопировано из gitleaks, detect-secrets, trufflehog; иначе — источник в документе, комментарий с лицензией и запись в `THIRD_PARTY_NOTICES.md`.

## 0. Документы (итерация 0)

- [x] 0.1 `[docs]` `agent-core/12-observability-and-errors.md`: §12.4–§12.4.3 целиком помечены «после 1.0» (R8-1; без переписывания разделов, находка №5); OBS-2, OBS-5, OBS-8, OBS-9 и тесты редакции §12.9 — «после 1.0»; что действует в 1.0 — вычистка `ProviderConfig.secrets` из текстов ошибок, правило лога §12.3, CFG-9 (D1, D2).
- [x] 0.2 `[docs]` `agent-core/06-tools.md` (`redactResult`, шаг 8b), `10-core-assembly-and-profiles.md` §10.3 (регистрация в `Redactor`), `13-acp-adapter.md` (OBS-2 у `data.codelab.message`): пометка «после 1.0» (R8-1) вместо «8.11».
- [x] 0.3 `[docs]` `agent-core/15-configuration.md` §15.4, §15.5, CFG-2 в §15.10 и `agent-core/17-5-agent-setup.md` §17.5.4–§17.5.5: CFG-9 пп. 1–3 в файле — предупреждение `config.secret.in_file` (R8-4); литеральный `api_key` — ключ провайдера, правило источников ключа, ссылки п. 3 не разрешаются, недоверенный проект без предупреждения, предконфигурация без изменений (D4); писатель, `args` и маскирование (D5, R8-5, OQ3); `secret set|delete` с именем-значением (D6); `secret migrate` (D7); `mcp add --header-stdin|--env-stdin` (D11); таблица подкоманд §17.5.5; таблица перезагрузки §17.5.6 — `redact.*` не применяются до P-10.
- [x] 0.4 `[docs]` `agent-parity-goals.md`: P-10 — этап «после 1.0» с причиной (R8-1) и ссылкой на находки ревью (design.md, «Перенесено после 1.0»); P-12 — статус: литерал в файле — предупреждение (R8-4), пп. 2–3 CFG-9 — 8.11. `delivery-roadmap.md` и `09-13-stage-8-mcp-config.md`, п. 11: новый объём, ссылка на change по имени, итерации, решения R8-1…R8-5; DoD 8.11. `09-11-stage-6-cli-mvp.md`: `secret migrate`, флаги stdin `mcp add` (D7, D11). `09-12-stage-7-embedded.md` или `12-3-desktop-display.md`: предупреждение и перенос в app (D8).
- [x] 0.5 `[docs]` `packages/dart/codelab_agent_core/AGENTS.md`: `config/inline_secrets.dart` — единственный источник распознавания литералов; ссылка на design.md change `add-config-literal-secrets-and-migrate` по имени, а не по пути. `apps/codelab_desktop/AGENTS.md`: `SecretMigrationRunner` реализуется только в `lib/app/` через `codelab_setup/io.dart` (D8).

- [x] 0.6 `[docs]` Повторное ревью 2026-11-04:
  - остатки «8.11 = редакция» помечены «после 1.0»: `delivery-roadmap.md`, `12-observability-and-errors.md` (§12.1, лог провайдера, `payload` после `redactJson`, OBS-2, `redact_command_test.dart`), `17-5-agent-setup.md` (§17.5.3, §17.5.7), `09-08-stage-3-sessions.md` (вынос от 8.11 не зависит);
  - §17.5.6 — литералы в R0-4 (D12);
  - единый шаблон текста `config.secret.in_file` в §15.4 и §17.5.4 (D4);
  - `codelab_embedded/io.dart` вместо `codelab_setup` для app в `12-3-desktop-display.md` и `apps/codelab_desktop/AGENTS.md` (D8);
  - NIT: пустые строки в `codelab_agent_core/AGENTS.md`.

**Критерий итерации 0.** Документы не расходятся с design.md; каждый изменённый абзац ссылается на D-решение или решение пользователя; ссылки на change — по имени.

## 1. Распознавание и предупреждения загрузки (итерация 1)

- [x] 1.1 `[agent]` Красный тест `codelab_agent_core/test/config/inline_secrets_test.dart` (agent-configuration «Литеральные секреты в файле конфига»; находки №8, №10):
  - `literalSecretTag` по каждому шаблону: позитивные и негативные примеры (`task-list`); литеральные части (`Bearer ${secret:x}` — `null`, `Bearer ghp_… ${X}` — `github`); DSN с паролем, разрезанным подстановкой (L5); белый список; тег без значения;
  - 1 МиБ враждебного текста для «присваивания секрета» — не дольше 2 с;
  - `findInlineSecrets` даёт находки пп. 1–3 с путём, видом, `suggestedSecretName` и участками;
  - значения п. 3: совпадающее с шаблоном (`sk-proj-…`, `ghp_<36 строчных>`) — находка; несовпадающее (`sk-test-secret-123`, `sk-Test Secret`) — нет (H2 арх.).

  Затем — `config/inline_secrets.dart` и экспорт в публичный барель (D3).
- [x] 1.2 `[agent]` Красный тест `test/config/config_secret_in_file_test.dart` (agent-configuration «Секреты только ссылками», «Литеральные секреты в файле конфига»):
  - литеральный `api_key` — предупреждение и ключ провайдера (`core/config-warns-inline-api-key`);
  - `api_key` + `api_key_secret` — проблема источников;
  - `token` у сервера — предупреждение, поле не применяется;
  - смешанный заголовок — предупреждение, заголовок применяется;
  - ссылка п. 3 — предупреждение;
  - недоверенный проект — без `config.secret.in_file`;
  - `CODELAB_CONFIG` — предупреждение без `--project`;
  - предконфигурация — без изменений, включая файл `--provider-config @путь`;
  - сценарии «Ключ вместо имени переменной/секрета» с двумя значениями: совпадающее — предупреждение и маркер `UnusableKeyRef` без проблемы формата, несовпадающее — проблема формата;
  - `api_key` в пользовательском слое и `api_key_secret` в проектном — проблема источников (R8-6);
  - находки выключенного сервера дают предупреждение (откат предупреждений выключенных серверов в `resolve.dart` их не снимает);
  - текст предупреждения — по одному шаблону, у `CODELAB_CONFIG` — `codelab secret set <name>`;
  - дескриптор `providers.*.api_key` — `fileOnly`, `secret: true` (тест полноты CFG-19);
  - текст без значений.

  Затем — `config/resolve.dart` на находках задачи 1.1 (D4). Существующие тесты, которые меняют ожидание: `config_inline_secret_test.dart` (`core/config-rejects-inline-api-key` → `core/config-warns-inline-api-key`) и `apps/codelab_agent/test/config_invalid_process_test.dart` (литеральный `api_key: sk-test-secret` сейчас ждёт отказ старта; теперь старт с предупреждением и без значения в stderr и логе).
- [x] 1.3 `[agent]` Красный тест `test/llm/literal_api_key_test.dart` (agent-secrets «Ключ провайдера при запросе»): литеральный ключ идёт в запрос без резолвера и вычищается из текста ошибки 401; ссылка п. 3 даёт ошибку `auth` без HTTP-запроса и без значения в тексте и в `secrets.lookup`; MCP-сервер с такой ссылкой — `failed` с тем же текстом. Затем — ключ провайдера и `_expandServerSecrets` (D4).
- [x] 1.4 `[agent]` Красный тест `codelab_agent_io/test/cli/config_check_secret_warning_test.dart`: `config check` печатает `warning:` по шаблону D4, код прежний; маркер `UnusableKeyRef` не ищется в хранилище (нет строки `secret <имя> is not set`), не даёт `config.provider.key_missing`, не попадает в `providerProblems` и `secrets.lookup` (`--debug-secrets`). Затем — `config_warnings.dart`, `config_commands.dart`, `resolve.dart` (D4). *Ревью итерации 1: реализация оказалась следствием 1.2 (маркер и предупреждения валидатора); отдельного кода в `config_commands.dart` не потребовалось.*
- [x] 1.5 `[agent]` Красный тест `codelab_agent_core/test/runtime/config_reload_literals_test.dart` (agent-runtime «Живая перезагрузка конфигурации», сценарии с литералами): HTTP-сервер с литеральным `Authorization` при смене `url`; провайдер с литеральным `api_key` при смене `base_url`; новый сервер с литералом — всё после перезапуска. Затем — `config_reload_plan.dart`: `api_key` в `_providerGroup`, находки в `_providerWithKey` и `_serverHasSubstitution` (D12).
- [x] 1.6 `[agent]` Красный тест — новый файл `codelab_agent_io/test/cli/provider_commands_test.dart`: `provider add --api-key-secret` при литеральном `api_key` удаляет его (R4-4, R8-6); `provider list` — `key: literal in config file`. Затем — `_keySourceFields` и вывод `provider list` (D4).

**Критерий итерации 1.** Литералы в файлах дают предупреждения, литеральный `api_key` работает, ссылки п. 3 не разрешаются; ни один текст не содержит значения.

## 2. Писатель и R4-6 (итерация 2)

- [x] 2.1 `[agent]` Красный тест `codelab_agent_io/test/config/literal_secret_rule_test.dart`: писатель отклоняет литерал по шаблону в `headers`/`env` (R1-1) и в элементе `args` с подсказкой `--env` (OQ3, R8-5); прежний литерал файла — предупреждение, `config unset` его удаляет. Затем — `literal_secret_rule.dart` поверх `literalSecretTag` (D5).
- [x] 2.2 `[agent]` Красный тест в `codelab_agent_io/test/cli/config_output_test.dart` (agent-configuration «Маскирование args MCP-серверов в выводе»): элементы `args` — по шаблону, после секретного флага, `--flag=value`; ссылки `${…}` — как есть. Затем — маскирование `args` в `cli/config_output.dart` (D5). *Ревью итерации 1: маскер всех листьев `config get`/`provider list` (литеральный `api_key`, ссылка п. 3 в листах реестра, значения с `${…}`; сценарий «config get не печатает литеральный ключ») перенесён в итерацию 1; в 2.2 остаются `args`, а писатель — в 2.1.*
- [x] 2.3 `[client]` E2e-тест совпадения `apps/codelab_cli/test/e2e/config_get_args_masking_test.dart`: вывод `codelab config get mcp.servers` совпадает с `codelab-agent`. Кода в CLI не ожидается.

**Критерий итерации 2.** R1-1 и R4-6 закрыты на записи и в выводе.

## 3. secret set|delete, secret migrate, mcp add из stdin (итерация 3)

- [x] 3.1 `[agent]` Красный тест в `codelab_agent_io/test/cli/secret_commands_test.dart` (agent-secrets «Имя секрета, похожее на значение»). Затем — проверка в `cli/secret_commands.dart` (D6).
- [x] 3.2 `[agent]` Красный тест `codelab_agent_io/test/secrets/secret_migrator_test.dart` (agent-secrets «Подкоманда secret migrate», все сценарии):
  - перенос провайдера и смешанного заголовка с комментариями;
  - `token` сервера — сохранён до удаления;
  - `--dry-run`;
  - бэкенд `env`;
  - конфликт с хранилищем и `--force` (текст про безвозвратность и ссылающиеся ключи, в том числе `--project --force` поверх пользовательского ключа);
  - одно имя у двух находок с разными значениями — суффикс `-2`; совпавшие `forMcp` разных серверов;
  - значения, которые не принял бы `secretValueProblem` (PEM, > 64 КиБ, непарный суррогат), — `not migrated … cannot be stored`, в `--dry-run` тоже;
  - ссылка-значение п. 3 переносится, проблем формата нет;
  - недоверенный проект — значение не в хранилище (H4);
  - повтор после сбоя записи (шов `ConfigWriteSeam`);
  - `args`;
  - `CODELAB_CONFIG`;
  - «нечего переносить»;
  - ни одного значения в отчёте и логе.

  Затем — `secrets/secret_migrator.dart` (D7).
- [x] 3.3 `[agent]` Красный тест `codelab_agent_io/test/cli/secret_migrate_command_test.dart`: строки CLI, флаги, коды, `restart the agent …`. Затем — `SecretCommands.migrate` (D7).
- [x] 3.4 `[agent]` Красный тест `codelab_agent_io/test/cli/mcp_add_stdin_test.dart` (agent-configuration «Значение заголовка или переменной mcp add из stdin»): заголовок со схемой и без, переменная; один флаг на вызов; `--header-scheme` без `--header-stdin`; имя одновременно в `--header` и `-stdin`; бэкенд `env` без чтения stdin; замена существующего секрета с предупреждением; сбой записи конфига после сохранения; имя, похожее на токен, — `64`; совпадение с `--header` без учёта регистра; имя секрета занято другим сервером или провайдером или совпало `forMcp` — код `1` до чтения stdin; значение нигде не напечатано. Затем — `McpServerCommands` (D11).
- [x] 3.5 `[agent]` `codelab_setup/io.dart`: реэкспорт `SecretMigrator`, `SecretMigrationReport`, опций и пунктов и опций `mcp add`; тест экспорта (находка №7).
- [x] 3.6 `[agent]` Красные процессные тесты `apps/codelab_agent/test/secret_migrate_process_test.dart` (agent-binary «Подкоманда secret бинаря», сценарий «Секрет из файла переносится») и `mcp_add_stdin_process_test.dart` («Флаги stdin у mcp add бинаря»). Затем — argv в `secret_cli.dart` и разбор `mcp add`; строка о 1.0 в справке `serve` и `secret` (R8-7, D13).
- [x] 3.7 `[client]` Красные e2e-тесты `apps/codelab_cli/test/e2e/secret_migrate_test.dart` и `mcp_add_stdin_test.dart` (codelab-cli «Подкоманда codelab secret», «Флаги stdin у codelab mcp add»): вывод, коды и байты файла совпадают с `codelab-agent`; `--cwd` подкоманды разрешён, `-C` верхнего уровня — `64`; справка `secret` и `codelab --help` содержат строку о 1.0 (R8-7). Затем — argv и справка в `codelab`.

**Критерий итерации 3.** Перенос и добавление секрета работают одной командой в обоих бинарях, без значений в выводе.

## 4. codelab-app (итерация 4)

- [x] 4.1 `[agent]` Красный тест `codelab_embedded/test/secrets_in_config_test.dart` (embedded-agent «Признак секретов в файле конфига», включая «Мигратор доступен через io.dart»). Затем — `EmbeddedAgent.secretsInConfig` в открывателях и реэкспорт `SecretMigrator` в `codelab_embedded/io.dart`; `melos run guard` и `web-compile` зелёные (D8).
- [x] 4.2 `[desktop]` Красный тест `apps/codelab_desktop/test/features/workbench/application/secret_migration_cubit_test.dart` (agent-workbench-ui «Перенос секретов встроенного агента»): автомат `hidden → offered → planning → planReady|planFailed → applying → applied|applyFailed` на фейке порта; бэкенд `env`; конфликт; поздний результат после закрытия; `Restart agent` недоступна во время хода. Затем — порт `SecretMigrationRunner` и `SecretMigrationCubit` (D8).
- [x] 4.3 `[desktop]` Красный тест резолвера и порта `apps/codelab_desktop/test/app/embedded_secret_offer_test.dart`:
  - `secretsInConfig` передаётся в `SecretMigrationOffer` и сбрасывается при закрытии агента;
  - порт берёт тот же `CODELAB_HOME`, `CODELAB_CONFIG` и окружение, что открыватель (`app_scope.dart`);
  - `planFailed`/`applyFailed` и лог — без `error.toString()`;
  - подсказка Windows — ветка `secret set`;
  - находки только в `CODELAB_CONFIG` — только `Close`.

  Затем — `lib/app/embedded_transport_resolver.dart`, `SecretMigrationOffer`, реализация порта через `codelab_embedded/io.dart` (D8).
- [x] 4.4 `[desktop]` Красный widget-тест `apps/codelab_desktop/test/features/workbench/presentation/secret_migration_banner_test.dart`: `InfoBar` с текстом и кнопкой, диалог с планом, тексты для `env` и конфликта, кнопка `Restart agent`. Затем — presentation (D8). `fvm flutter analyze` и тесты app; интеграционный прогон — только в `release/*`.

**Критерий итерации 4.** App не блокирует старт, предлагает перенос и перезапуск; виджеты без IO.

## 5. Матрица, сверка, DoD (итерация 5)

- [ ] 5.1 `[docs]` `agent-parity-goals.md`: P-12 — тесты итераций 1–3, критерий `core/config-rejects-inline-api-key` заменён `core/config-warns-inline-api-key` (в том числе §17.5.10 `17-5-agent-setup.md` и матрица этапа 8); P-10 — «после 1.0» (проверка ссылки на решение R8-1).
- [ ] 5.2 `[docs]` `09-13-stage-8-mcp-config.md`: отметка DoD 8.11 и строка матрицы этапа 8 с файлами тестов; R1-1 и R4-6 — закрыты (R1-1 — предупреждением и отказом записи, R4-6 — отказом записи и маскированием).
- [ ] 5.3 `[docs]` Сверка design.md, спецификаций и документов; комментарии новых сущностей — по `AGENTS.md` §15.
- [ ] 5.4 `[agent]` Ручной smoke: `codelab-agent serve --stdio` с литеральным `api_key` — предупреждение без значения; `secret migrate --dry-run`, затем перенос; `mcp add --env-stdin` с TTY — без эха. Результат — в описании PR.
- [ ] 5.5 `[docs]` Релизный чек-лист (R8-7, D13): в ветке `release/*` создать `CHANGELOG.md` или release notes с разделом «Известные ограничения» — до 1.0 вывод инструментов, промпты и журналы сессий не редактируются и уходят провайдеру как есть; литералы в конфиге — предупреждение, перенос `secret migrate`. В `feature/*` файл не создаётся.

**Критерий итерации 5.** Тесты итераций 1–4 зелёные; `melos run check` зелёный в CI pull request; документы и код не расходятся.
