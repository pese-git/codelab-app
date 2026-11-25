> Метки исполнителей — по `CLAUDE.md`:
> - `[client]` — `codelab_client_acp`, `codelab_client_io` и тест сторожа для их границы (`client-engineer`; правила сторожа правит тот, чью границу меняет задача);
> - `[agent]` — архитектурные документы и матрица целей (правит `codelab-architect`), документация пакетов ядра (`docs-writer`).
>
> Кода агента, протокола и desktop в change нет, поэтому меток `[protocol]` и `[desktop]` нет.
>
> Задачи идут парами «тест → реализация», красный тест первым. Красный тест коммитится отдельно до кода — только по явной просьбе пользователя.
>
> Q1–Q4 design.md решены пользователем 2026-11-26 по рекомендациям (Q1 — (а): песочница ОС не в 1.0, этот change плюс контейнер).
>
> **Порядок (design.md, D3):**
> - задачи 2–5 начинаются после влития `fix-acp-client-symlink-containment` в `develop`;
> - задачи раздела 1 от него не зависят.

## 1. Решение и архитектурные документы

- [ ] 1.1 `[agent]` ADR-0004:
  - вписать ответ Q1;
  - статус `Accepted` — после одобрения change, одновременно в шапке ADR, в реестре `docs/architecture/adr/README.md` §27 и в `docs/architecture/README.md` §3 (перенос из «На рассмотрении» в «Принятые решения»; строка уже внесена вместе с файлом).
- [ ] 1.2 `[agent]` Матрица целей `agent-parity-goals.md` (D5):
  - строка P-13 и её обоснование — по ответу Q1;
  - строка §8 «Песочница ОС» — «решено ADR-0004»;
  - сводка §7 «Итого»: при Q1 (а) — «Could — 78, Won't — 24», запись «Пересчёт» с датой и причиной;
  - затем `melos run guard` (`parity_evidence_test` разбирает матрицу).
- [ ] 1.3 `[agent]` Остальные архитектурные места, где песочница записана как Won't или «не берём» (D5):
  - `agent-core/00-six-concepts.md` («Чего нет сознательно»);
  - `agent-core/16-non-mvp-and-open-questions.md` §16.1 и §16.3;
  - `agent-core/17-12-loop-and-security.md`, пункт 5 запрета чтения («P-13 — Won't»);
  - `dart-agent-and-clients/04-target-architecture.md`, строка «декларативная песочница ОС … не берём»;
  - `delivery-roadmap.md`: §4.5 (вопрос до вехи, критерий выхода), §4.6 (M5) и §6.2 (пул 1.x) — P-13 Could, первый бэкенд macOS;
  - `dart-agent-and-clients/09-14-stage-9-switch-default.md`, пункт 11.

## 2. Окружение `terminal/create` (D2)

- [ ] 2.1 `[client]` Тесты `codelab_client_io`. Красный.
  - Чистая функция построения окружения (`isWindows: false` и `true`), без запуска процесса:
    - без `CODELAB_SECRET_OPENAI` и `OPENAI_API_KEY`, с `PATH`;
    - `env` запроса перекрывает `LANG`;
    - без `env` — только allowlist;
    - Windows: имена хоста в любом регистре (`Path`, `SYSTEMROOT`), `ComSpec`, `PSModulePath` сохраняются; `Path` из запроса заменяет `PATH` хоста, в окружении одна переменная пути.
  - Запуск `/usr/bin/env` через `IoTerminalProcessRunner(hostEnvironment: {...})` на POSIX: вывод без секретов хоста, с `PATH` и переменной запроса.
  - Сценарии `acp-terminal-client`: «Секрет клиента не виден команде», «Переменная запроса передаётся и перекрывает базовую», «Пустой env запроса», «Построение окружения на Windows», «Path запроса перекрывает PATH хоста на Windows», «Windows без системных переменных не ломается» (последний — на Windows-машине или в CI Windows, иначе `skip` с причиной).
- [ ] 2.2 `[client]` Реализация. После неё 2.1 и сквозной `symlink_containment_test.dart` (из `fix-acp-client-symlink-containment`) зелёные.
  - `IoTerminalProcessRunner`: конструктор остаётся `const`, необязательные `hostEnvironment` и `isWindows` разрешаются через `Platform.*` при `start`; окружение по allowlist, `includeParentEnvironment: false`;
  - вызовы `const IoTerminalProcessRunner()` в `app_scope.dart` и `composition_root.dart` не меняются;
  - doc-комментарии по-русски (§15);
  - doc-комментарий порта `TerminalProcessRunner.start` в `codelab_client_acp` описывает контракт `env`.
- [ ] 2.3 `[client]` Тест сторожа `codelab_architecture_tests`: POSIX-часть allowlist клиента (`codelab_client_io`) совпадает с `hostEnvironmentAllowlist` (`codelab_agent_io/lib/src/env/host_variables.dart`). Тест читает оба исходника как текст и без импорта пакетов (D4). Красный до 2.2, зелёный после; `melos run guard`.

## 3. Регрессия ACP-клиента

- [ ] 3.1 `[client]` `melos run conformance:client` и `melos run test:e2e:cli:dart-agent`. Dart-агент по stdio запускает команды через `terminal/create` клиента. Проверить, что сценарии e2e не зависят от переменных окружения клиента вне allowlist; если зависят — это проявление R2 (агент не передаёт фиксированный набор и `exec.env` только через `ExecOptions.env`). Зафиксировать результат в отчёте реализации и, если падает, вынести решение к Q4, а не добавлять переменные на стороне клиента.

## 4. Документация

- [ ] 4.1 `[agent]` Архитектурные документы, только абзацы об окружении (D3, D5):
  - `docs/architecture/permissions.md`, исключение `fs/*` и `terminal/*`: окружение `terminal/create` по allowlist;
  - `docs/architecture/platform-integration.md` §53, абзац «В коде»: `IoTerminalProcessRunner` строит окружение по allowlist; `StdioAcpTransport` наследует окружение клиента (Q3).
- [ ] 4.2 `[client]` `docs-writer`, после влития `fix-acp-client-symlink-containment`:
  - `packages/dart/codelab_client_acp/doc/execution-on-client.md`, таблица ограничений: строка «Команда терминала видит секреты клиента» (окружение) и строка «символическая ссылка внутри папки наружу … проверка лексическая» (по итоговому поведению того change);
  - `packages/dart/codelab_client_acp/doc/03-agent-requests-fs-terminal.md`, «Что проверка не покрывает»: пункт «Символические ссылки» и окружение терминала;
  - `packages/dart/codelab_client_io/README.md` и `doc/`: окружение терминала.
- [ ] 4.3 `[agent]` `docs-writer`:
  - `packages/dart/codelab_agent_core/doc/algorithms/secrets.md`: пределы секретов — команды `terminal/create` больше не видят окружение клиента; процесс стороннего агента видит его по-прежнему (Q3);
  - `packages/dart/codelab_agent_core/doc/algorithms/execution-sides.md`: окружение команды на двух сторонах, расхождение фиксированного набора (R2);
  - `packages/dart/codelab_agent_core/doc/01-overview.md`, абзац о песочнице: ссылка на ADR-0004;
  - пользовательская страница о границе исполнения в `docs/user/`:
    - что ограничивает команды агента и что нет; одобренная команда работает с правами пользователя;
    - предупреждение о режиме `bypass` (ADR-0004, Decision п. 3);
    - сторонний агент получает всё окружение клиента и может исполнять команды сам, минуя клиента (ADR-0004, S5b);
    - доверие к проекту привязано к папке, а не к содержимому `.codelab/config.yaml` (S9);
    - изоляция недоверенного репозитория контейнером через `codelab-agent serve --local-exec` после влития `add-agent-remote-exec`;
  - backlog: статус REV-29 — по Q3; Windows-окружение команд агента (`hostEnvironmentAllowlist`); подтверждение доверия при изменении проектного конфига (S9). Записи по Q4 заводит координатор.
- [ ] 4.4 `[client]` `docs-writer`: черновик строки раздела выпуска `CHANGELOG.md` об окружении `terminal/create` для сторонних агентов. В раздел выпуска строка переносится в `release/*`.

## 5. Проверки (§21)

- [ ] 5.1 `[client]` Проверки клиентских пакетов:
  - `fvm dart format --set-exit-if-changed` изменённых файлов;
  - `fvm dart analyze` в `codelab_client_io`, `codelab_client_acp`, `codelab_architecture_tests`;
  - тесты этих пакетов;
  - `melos run guard` (новый тест сторожа);
  - `melos run web-compile` (изменён doc-комментарий web-безопасного пакета).
- [ ] 5.2 `[agent]` `openspec validate add-os-sandbox-decision --strict`; `melos run guard` после правки матрицы (задача 1.2).
