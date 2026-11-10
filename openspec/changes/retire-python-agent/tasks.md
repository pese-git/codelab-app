Задачи кода идут парами «тест → реализация» (TDD, `packages/dart/codelab_agent_core/AGENTS.md` §2; дорожная карта §9.1). Сначала красный тест, затем код. В скобках — требование спецификации (`codelab-cli` «Алиас codelab serve», сценарий) или решение design.md. Красный тест коммитится отдельно до кода; коммит — только по просьбе пользователя.

Метки исполнителей — как в change `switch-default-agent-to-dart`:
- `[protocol]` — документы без владельца: план, дорожная карта, риски, §12.7;
- `[agent]` — документы агентской стороны, в том числе политика Python-агента в `docs/user/`;
- `[client]` — `apps/codelab_cli` и документы CLI;
- `[desktop]` — задач нет: app не меняется.

Раздел E — внешние шаги в репозитории Python-агента и в трекере. Их выполняет пользователь — владелец репозитория `pese-git/codelab-agent` (решение Q8), а не исполнители monorepo. Здесь они нужны только для учёта.

Итерации — каждая отдельным pull request в `develop` (design.md, D15):
- 0 — политика заморозки и документы (до ворот MVP);
- 1 — алиас `codelab serve`.

Зависимости: 1 ← 0 (решения Q1–Q8 — design.md, «Решения пользователя 2026-11-10»). Задача 4.4 `switch-default-agent-to-dart` ← итерация 0 и E.1 (D5).

Проверки — только затронутого (`AGENTS.md` §21):
- итерация 0: `openspec validate retire-python-agent --strict`, проверка ссылок изменённых документов;
- итерация 1:
  - `fvm dart format` изменённых файлов;
  - `fvm dart analyze` в `apps/codelab_cli`;
  - `fvm dart test` в `apps/codelab_cli` (модульные и `test/e2e/`);
  - `melos run test:e2e:cli:dart-agent`;
  - `guard` не нужен: `pubspec.yaml` и импорты между пакетами не меняются.

## 0. Политика заморозки и документы (итерация 0)

- [x] 0.1 `[agent]` `docs/user/migrating-from-python-agent.md` — раздел «Поддержка Python-агента» по D1:
  - с какого момента действует заморозка (D3);
  - перечень принимаемых исправлений и приватный канал сообщения об уязвимости (D2);
  - что не принимается;
  - условие удаления, метка `parity-regression`, кто решает (D4);
  - срок алиаса (D11).

  Первая фраза страницы ссылается на раздел. В `docs/user/README.md` — короткая ссылка.
- [x] 0.2 `[protocol]` План 9.9 (`09-14-stage-9-switch-default.md`):
  - распределение: этот change — заморозка, условие удаления и алиас; `remove-python-agent` — удаление (D13, Q6);
  - срок алиаса и semver (D11, Q3);
  - абзац «OpenSpec change» — оба change.

  Пометка в D1 change `switch-default-agent-to-dart` не нужна: он ссылается на этот change, а здесь распределение уточняется.
- [x] 0.3 `[protocol]` `delivery-roadmap.md`:
  - §4.4 — заморозка опубликована этим change (ссылка на раздел 0.1);
  - §4.5 — удаление: change `remove-python-agent` по условию D4.
- [x] 0.4 `[protocol]` Риски и допущения:
  - `10-risks.md`, строка «Конфликт имени команды `codelab`»: алиас — change `retire-python-agent`, срок — D11;
  - строка «Два агента одновременно»: ссылка на политику 0.1;
  - `11-assumptions-and-open-questions.md`, допущение 5: «один релиз» уточнён по D11.
- [x] 0.5 `[protocol]` `12-7-release-and-distribution.md` §12.7.8: исключение для переходного алиаса (D11, решение Q3 (а)). Пометка «deprecated» в `CHANGELOG.md` первой `stable` — обязанность ветки `release/<version>` (E.3).
- [x] 0.6 `[protocol]` `agent-parity-goals.md` §6: после фразы «только исправления безопасности до удаления» — ссылка на политику 0.1 и условие D4. Строки и приоритеты матрицы не меняются.
- [x] 0.7 `[protocol]` Запись для ворот: в `proposal.md` и задаче 4.4 change `switch-default-agent-to-dart` — ссылка на раздел 0.1 и чем закрывается 4.4: итерация 0 и E.1 (D5). Ссылку на коммит E.1 дописывает тот change при закрытии 4.4; задачу 4.4 отмечает он же после merge итерации 0 и E.1 (2026-11-10).

## 1. Алиас `codelab serve` (итерация 1)

Модульные тесты — `apps/codelab_cli/test/` без процессов, e2e — `apps/codelab_cli/test/e2e/serve_alias_test.dart`. Имена e2e — `cli/serve-alias-*`. Это не доказательства строк матрицы: `parity_evidence_test` их не ищет.

- [x] 1.1 `[client]` Тест: `parseCliArgs` (D8; «Сообщение serve в REPL», «serve без флагов»):
  - `['serve', '--stdio', '--port', '1']` → `CliCommand.serveAlias`, `positional == ['--stdio', '--port', '1']`;
  - `['serve']` → `serveAlias`, пустой `positional`;
  - `['serve', '--help']` → `serveAlias`, а не справка `codelab`;
  - `['--', 'serve']` и `['-v', 'serve']` → `repl` с первым сообщением `serve`.
- [x] 1.2 `[client]` Реализация: `CliCommand.serveAlias` и проверка `args.firstOrNull == 'serve'` до `ArgParser` в `cli_args.dart`.
- [x] 1.3 `[client]` Тест: `locateAgentExecutable` (D7; «Бинарь рядом важнее PATH», «codelab-agent не найден», «Алиас не вызывает сам себя»):
  - бинарь рядом важнее `PATH`;
  - порядок записей `PATH`;
  - пустая запись и `.` пропущены;
  - `codelab-agent.exe` на Windows;
  - кандидат с каноническим путём `codelab` отброшен;
  - ничего нет → `null`.
- [x] 1.4 `[client]` Реализация: `locateAgentExecutable` в `lib/src/serve_alias.dart` — чистая функция с подстановкой проверки файла и канонизации.
- [x] 1.5 `[client]` Тест: перевод кода выхода (`0`, `64`, `143` — как есть; `-15` → `143`, `-2` → `130`) и тексты предупреждения и «не найден» (D9).
- [x] 1.6 `[client]` Реализация: `runServeAlias` в `serve_alias.dart`:
  - предупреждение и `flush`, затем `Process.start(…, mode: ProcessStartMode.inheritStdio)`;
  - сигналы через `SignalSeam`: `SIGTERM` пересылается, ранний `SIGTERM` запоминается, `SIGINT` перехватывается без пересылки (D10);
  - `exitCode` → код по 1.5;
  - сбой `Process.start` → `1` и `ProcessException.message` без аргументов.

  Ветка `CliCommand.serveAlias` в `run.dart` до открытия домашнего каталога и профилей.
- [x] 1.7 `[client]` E2E (красные до 1.6). CLI из kernel, `PATH` — временный каталог с обёрткой `codelab-agent`, которая запускает kernel `apps/codelab_agent/bin/codelab_agent.dart` абсолютным путём `dart`. На Windows пропуск с причиной.
  - `cli/serve-alias-stdio` — `serve --stdio --llm-script <hello>`: `initialize` → ответ `protocolVersion: 1` в stdout, предупреждение — первая строка stderr, EOF → `0` («Агент по stdio через алиас»);
  - `cli/serve-alias-args` — `serve --stdio --bogus` → `64`, справка `codelab-agent` в stderr, stdout пуст («Аргументы передаются без изменений»);
  - `cli/serve-alias-no-flags` — `serve` → `64`, REPL не открыт («serve без флагов»);
  - `cli/serve-alias-missing` — `PATH` без `codelab-agent`, но с `.` и исполняемым `codelab-agent` в рабочей папке → `1`, текст «not found», файл-ловушка не запущен («codelab-agent не найден»);
  - `cli/serve-alias-sigterm` — `SIGTERM` процессу `codelab` во время работы агента → `143`, процесс агента завершён до выхода `codelab` («SIGTERM через алиас»).
- [x] 1.8 `[client]` Тест: `codelab --help` не содержит строки `codelab serve` (требование, последний абзац; слово `server` в справке `mcp` есть, поэтому проверяется фраза, а не подстрока `serve`).
- [x] 1.9 `[client]` Тест `test/e2e/support/e2e_agent_test.dart`, группа `python` (D12): фальшивый `codelab`, который на `serve --help` печатает справку `codelab-agent` в stderr и выходит `64`, — причина пропуска `Python agent (codelab serve) is not installed`. Код помощника не меняется; если тест красный, правило обнаружения сужается в этой задаче.
- [x] 1.10 `[client]` Документы CLI:
  - `apps/codelab_cli/AGENTS.md` §2 — алиас: распознавание до разбора, `serve_alias.dart` в списке мест `dart:io`, сигналы (D8, D10);
  - корневой `AGENTS.md` §5, строка `apps/codelab_cli` — «переходный алиас `codelab serve`»;
  - `docs/user/migrating-from-python-agent.md`, раздел «Профили и скрипты с `codelab serve`»: вместо `Unknown flag --stdio` и «алиас появится позже» — алиас, предупреждение, срок (D11), `which codelab` при двух `codelab`, «нет `codelab-agent`» → код `1`.
- [x] 1.11 `[client]` Ручная проверка: `build/bin/codelab serve --stdio` как внешний агент Zed по чек-листу Zed, шаги 1 и 3 (`docs/user/zed.md`). Предупреждение видно в «ACP logs» Zed, кадры — как у `codelab-agent serve --stdio`. Итог — в описании pull request.
- [x] 1.13 `[client]` По двойному ревью (решения пользователя Q9–Q12, 2026-11-10; D7, D9, D10; сценарии «SIGHUP через алиас», «Повторный вход в алиас», «Ранний SIGTERM и сбой запуска»): тест ветки сбоя запуска (без аргументов в stderr), `SIGHUP`, защита от рекурсии, кавычки `PATH` на Windows, швы `isExecutableFile`/`canonicalize`.
- [x] 1.14 `[agent]` По ручной проверке в Zed (1.11, 2026-11-10): агент, запущенный через алиас, писал `warning config.env.unknown {name: CODELAB_SERVE_ALIAS_ACTIVE}` при каждом запуске. Маркер добавлен в известные переменные `ConfigLoader` (`environment_layer.dart`) и в agent-core §15.6; тесты — `config_loader_test.dart` (группа `config.env.unknown`) и e2e `cli/serve-alias-stdio` (stderr без `config.env.unknown`).
- [ ] 1.12 `[client]` Архивирование change — только по просьбе пользователя, после итерации 1.

## E. Внешние шаги (пользователь — владелец `pese-git/codelab-agent`; Q8)

- [ ] E.1 README репозитория `pese-git/codelab-agent`: баннер «Заморожен: только исправления безопасности» со ссылкой на раздел 0.1 и на `docs/user/`; описание репозитория на GitHub — то же одной строкой. Ссылка на коммит — в `proposal.md` `switch-default-agent-to-dart` (D5).
- [ ] E.2 Трекер `codelab-app`: метка `parity-regression` и шаблон issue «Регрессия относительно Python-агента» с обязательным полем «строка матрицы» (D4). В Python-репозитории — приватные сообщения об уязвимостях (Security Advisories) включены (D2).
- [ ] E.3 Ветка `release/<version>` первой `stable`: в `CHANGELOG.md` — `codelab serve` deprecated, будет снят по условию D4 (D11).
- [ ] E.4 После подписи таблицы D4: архивировать `pese-git/codelab-agent` (GitHub Archive, только чтение). Python TUI удаляется вместе с ним: он в том же репозитории.
- [ ] E.5 После подписи таблицы D4: завершающий тег в `pese-git/codelab-agent` (последняя версия с исправлениями безопасности) и запись о прекращении поддержки в README — до архивирования E.4. Выпуска пакета нет: на PyPI Python-агент не публикуется (Q8).
- [ ] E.6 Change `remove-python-agent` в этом репозитории (D13): создаёт архитектор, когда выполнено условие D4.
