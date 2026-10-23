Задачи идут парами «тест → реализация» (§9.0, правило 3); в скобках — номер задачи этапа 0 (`dart-agent-and-clients/09-05-stage-0-foundation.md`) и сценарий спецификации, который задача закрывает. Группы 1–2, 3–6 и 7–8 — итерации 1, 2 и 3 (design.md, D8).

## 1. Конфигурация melos (0.1)

- [x] 1.1 Характеризация: сохранить вывод `fvm dart run melos list` и список скриптов; `fvm dart run melos run check` зелёный до изменений
- [x] 1.2 Перенести `test:e2e:app:plan-checklist`, `test:e2e:app:prompt-queue`, `test:e2e:app:multi-session` в секцию `melos:` корневого `pubspec.yaml`; удалить `melos.yaml`
- [x] 1.3 Проверка (testing-quality «Один источник конфигурации Melos»): вывод `melos list` и список скриптов совпадают с 1.1, `melos run check` зелёный, каждый из восьми `test:e2e:app:*` запускается; если секция не читается — запасной вариант design.md D2, решение записать в design.md

## 2. Разделение `acp_transports` (0.2)

- [x] 2.1 Характеризация: тесты `acp_transports`, `acp_client_core`, `codelab_app` (unit и `widget_test.dart`) и восемь `test:e2e:app:*` зелёные до изменений
- [x] 2.2 Тест (agent-transports «Основной барель не тянет dart:io»): в `acp_transports/test/` — тест, что `lib/acp_transports.dart` и `lib/src/transport_configs.dart` транзитивно не импортируют `dart:io` (красный)
- [x] 2.3 Перенести `StdioAcpTransportConfig`, `StdioAcpAgentProfile`, `WebSocketAcpTransportConfig` в `lib/src/transport_configs.dart` (`part 'transport_configs.freezed.dart'`); создать `lib/io.dart` с экспортом транспортов; перенести реализации в `lib/src/io/`, если перенос механический (иначе поимённый `exclude`, design.md D3)
- [x] 2.4 `fvm dart run build_runner build --delete-conflicting-outputs` в `packages/dart/acp_transports`; сгенерированный код в git не хранится (design.md D3): старые `*.freezed.dart` транспортов удалены из git, исключение в `.gitignore` убрано
- [x] 2.5 Обновить импорты: `apps/codelab_app` (`shell_cubit.dart`, `app_scope.dart`, `test/widget_test.dart`, `integration_test/fs_flow_test.dart`), `packages/dart/acp_testing`, `packages/dart/acp_transports/test`; перегенерировать `app_scope.module.cherrypick.g.dart`
- [x] 2.6 Проверка (agent-transports «Код создания транспорта импортирует io.dart»): тест 2.2 зелёный, тесты 2.1 зелёные, `grep -rn "dart:io" packages/dart/acp_transports/lib/acp_transports.dart packages/dart/acp_transports/lib/src/transport_configs.dart` пусто
  - Итог e2e после разделения (2026-10-22): зелёные `fs`, `terminal`, `plan-checklist`, `multi-session`, `open-project`, `stdio` (первый прогон — 2 сбоя UI, повторный — 5 из 5, нестабильность). Красные `permission` (ожидает 2 виджета с `/bin/bash`, находит 1) и `prompt-queue` (не находит «Allow once») — оба красные и на `develop` без изменений этого change, к транспорту не относятся; исправление — отдельный change. Характеризация e2e до изменений не снималась — сравнение выполнено прогоном `develop` после.

## 3. Пакет `codelab_agent_core` (0.3)

- [x] 3.1 Тест (workspace-architecture «Ядро агента собирается для web»): `test/web_smoke/main.dart` импортирует барель и печатает `codelabAgentCorePackageName`; `fvm dart compile js` падает, пока пакета нет (красный)
- [x] 3.2 Создать `packages/dart/codelab_agent_core`: `pubspec.yaml` по скелету `09-05` (зависимости `async`, `collection`, `http`, `meta` — PKG-2), `lib/codelab_agent_core.dart` с `const codelabAgentCorePackageName`, `analysis_options.yaml` как в соседних пакетах; добавить в `workspace:`
- [x] 3.3 Проверка: `fvm dart compile js -O1 ...` и `fvm dart compile wasm ...` в `build/web_smoke/` проходят

## 4. Сторож архитектуры (0.4)

- [x] 4.1 Создать `packages/dart/codelab_architecture_tests` (`pubspec.yaml` по скелету `09-05`, добавить в `workspace:`)
- [x] 4.2 Тест (workspace-architecture «Сторож сам проверен на нарушении»): `import_guard_test.dart: reports dart:io imported by a core library` на временном пакете (красный — сканера нет)
- [x] 4.3 Реализовать `test/support/import_scanner.dart` (import/export/part, каждая альтернатива условного импорта, `exclude`, `sealExclude`) — 4.2 зелёный
- [x] 4.4 Тесты сканера: `part`, `export`, `sealExclude` (файл вне `exclude` ссылается на исключённый → нарушение), `sealExclude: false` (каталог с разрешённым пакетом)
- [x] 4.5 `test/support/rules.dart`: правила `codelab_agent_core`, `acp_transports` (с исключением IO-точки входа), `acp_client_core`, `apps/codelab_app` (`package:codelab_agent_`); комментарии с правилами будущих этапов; цикл «пакет → тест» в `import_guard_test.dart` зелёный на текущем коде
- [x] 4.6 Тест (workspace-architecture «Зависимость вне allowlist»): `pubspec_allowlist_test.dart` — `dependencies` ядра ⊆ `{http, meta, collection, async, crypto}`; негативный случай на временном `pubspec.yaml`
- [x] 4.7 Проверка (workspace-architecture «Клиент импортирует ядро напрямую»): временное нарушение в рабочей копии ловится, затем откатывается — не коммитится
  - Корень репозитория тесты сторожа находят вверх по каталогам до `pubspec.yaml` с `workspace:` (`test/support/repo_root.dart`): `guard` запускается из корня, `melos run test` — из каталога пакета. Проверка 4.7: временные `import 'dart:io'` в ядре и `import 'package:codelab_agent_core/...'` в `apps/codelab_app/lib/main.dart` дали два нарушения, затем откатаны.

## 5. Скрипты melos (0.5)

- [x] 5.1 Добавить `test:dart`, `guard`, `web-compile` с `description` в секцию `melos:`; `check` — `check-format, analyze, guard, test, protocol-conformance, web-compile` (design.md D5)
- [x] 5.2 Проверка (testing-quality «Запускается полная проверка»): `fvm dart run melos run check` зелёный; `build/` в `.gitignore`

## 6. `AGENTS.md` (0.11)

- [x] 6.1 Корневой `AGENTS.md` §5: в дерево и назначение пакетов — `codelab_agent_core`, `codelab_architecture_tests`; ссылка на `docs/architecture/proposals/agent-core-architecture.md` как источник архитектуры агента; правило: сторонний код не копируется, атрибуция по `dart-agent-and-clients/07-decision-sources.md` §7а
- [x] 6.2 `packages/dart/codelab_agent_core/AGENTS.md`: PKG-1…PKG-6 (agent-core-architecture §1), сторож (`melos run guard`), TDD (§9.0, правило 3, исключения (а)–(д)), определение завершённой итерации (§9.0, правило 8)
- [x] 6.3 Проверка: ссылки из обоих файлов ведут на существующие документы

## 7. CI (0.6)

- [ ] 7.1 `.github/actions/prepare/action.yml` по `09-05` «Артефакт: CI» и после `pub get` — `build_runner build --delete-conflicting-outputs` в пакетах с `build_runner` (сгенерированный код не в git, design.md D3); проверка: чистый `git clone` + `prepare` → `melos run check` зелёный
- [ ] 7.2 `.github/workflows/ci.yml`: триггеры `push` в `master` и `develop`, `pull_request`, ночной `schedule`; матрица `format`, `analyze`, `test`, `conformance` (`protocol-conformance`), `guard`, `web-compile`; `e2e-macos` с восемью `test:e2e:app:*` (design.md D6)
- [ ] 7.3 `.github/pull_request_template.md`: чек-лист OpenSpec change, тесты (красный тест до кода или ссылка на критерий), `melos run check`, сторонний код (§7а, пункт 6)
- [ ] 7.4 Проверка (testing-quality «Pull request с нарушением»): pull request этой итерации — шесть джобов зелёные; временный коммит с нарушением формата даёт красный `format`, затем откатывается
- [ ] 7.5 Проверка (testing-quality «Pull request без метки e2e»): `e2e-macos` пропущен без метки; с меткой `e2e` — запущен и зелёный
- [ ] 7.6 После первого зелёного прогона на `develop`: добавить шесть джобов как обязательные проверки в ruleset `master`/`develop` (настройка GitHub, с подтверждения владельца репозитория)

## 8. Лицензия (0.9)

- [ ] 8.1 `LICENSE` — текст MIT, год 2026, правообладатель Sergey Penkovsky
- [ ] 8.2 `THIRD_PARTY_NOTICES.md` — заголовок, формат записи (название, URL, лицензия, уведомление, файлы), пустой список (licensing-and-attribution «Пустой реестр с форматом»)
- [ ] 8.3 Корневой `README.md`: назначение репозитория, ссылки на `AGENTS.md` и `docs/architecture/`, раздел о лицензии (licensing-and-attribution «Лицензия на месте»)

## 9. Завершение этапа

- [ ] 9.1 Definition of Done `09-05` в части этого change: `melos run check` зелёный; шесть джобов CI зелёные; негативный тест сторожа проходит; web-компиляция js и wasm проходит; `AGENTS.md` ядра на месте; `grep` по `acp_transports` пуст; восемь интеграционных тестов app проходят
- [ ] 9.2 `openspec validate add-workspace-ci-and-architecture-guards --strict`; архивировать change после слияния последней итерации (§9.0, правило 6)
