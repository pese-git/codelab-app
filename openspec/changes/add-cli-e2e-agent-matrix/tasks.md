Задачи идут парами «тест → реализация» (§9.0, правило 3). В скобках — требование спецификации или решение design.md. Пути — в `apps/codelab_cli/`, если не указано иное.

Группы задач по итерациям — каждая итерация отдельным PR в `develop`:
- итерация 1 — группы 1–3: помощник, Dart-агент, `check` и CI;
- итерация 2 — группы 4–5: Python-агент, документы и DoD.

Модульные проверки пишутся первыми, отдельным красным коммитом до кода.

## 1. Помощник и теги (D1, D2, D5)

- [ ] 1.1 Тест (testing-quality «PTY-e2e терминального клиента»): `test/e2e/support/e2e_agent_test.dart`:
  - `CODELAB_E2E_AGENT` не задан → `scripted`, неизвестное значение → `ArgumentError`;
  - `launch` в режиме `scripted` даёт `--agent` scripted-агента и его ожидания (`hello from compatible stdio agent`, `Run test command`, `gpt-5`/`gpt-4`).

  Красный.
- [ ] 1.2 Реализовать `test/e2e/support/e2e_agent.dart` (`E2eAgentKind`, `E2eCliAgent`, `E2eCliLaunch`) и `dart_test.yaml` с тегами `scripted-only` и `python-agent` — 1.1 зелёный.
- [ ] 1.3 Перевести тесты `test/e2e/*_test.dart` на `E2eCliAgent.current.launch` и ожидания `E2eCliLaunch`; расставить теги по таблице D6. `melos run test:e2e:cli` против scripted-агента зелёный, число тестов прежнее (42).

## 2. Dart-агент (D3, D6)

- [ ] 2.1 Тест: `apps/codelab_agent/test/llm_scripts_load_test.dart` загружает каждый `apps/codelab_cli/test/e2e/llm_scripts/*.json` как сценарий `--llm-script`, а список файлов совпадает со списком режимов CLI из `E2eCliAgent`. Красный, пока сценариев нет.
- [ ] 2.2 Сценарии `test/e2e/llm_scripts/<wireName>.json` для режимов таблицы D6:
  - `normal`, `with_permission_request`, `with_config_options`, `with_session_list`;
  - `hangs_until_cancel`, `with_tool_calls`, `provider_error`, `empty_answer`.

  Тест 2.1 зелёный.
- [ ] 2.3 Режим `dart` в `E2eCliAgent`:
  - kernel `apps/codelab_agent/bin/codelab_agent.dart` один раз на прогон;
  - флаги режима по D3;
  - ожидания Dart-агента: `echo hello`, `scripted/gpt-5`/`scripted/gpt-4`, итог одобрения строкой вызова.

  Тест в `e2e_agent_test.dart`: `launch` в режиме `dart` даёт команду `dart <agent>.dill serve --stdio --llm-script <путь>` с флагами режима.
- [ ] 2.4 Прогон `CODELAB_E2E_AGENT=dart fvm dart test apps/codelab_cli/test/e2e --exclude-tags scripted-only` зелёный (testing-quality, сценарий «Тот же тест против Dart-агента»).

## 3. Скрипты, `check` и CI (D5)

- [ ] 3.1 Melos-скрипты `test:e2e:cli:dart-agent` и `test:e2e:cli:python-agent` в корневом `pubspec.yaml`; `check` включает `test:e2e:cli:dart-agent` (testing-quality «Проверки workspace»).
- [ ] 3.2 Джоб `e2e-cli-dart` в `.github/workflows/ci.yml` (testing-quality «Непрерывная интеграция»); комментарий-заготовку `stage 6: { job: e2e-cli … }` заменить.
- [ ] 3.3 Проверка итерации 1: `fvm dart run melos run check` зелёный; PR итерации 1.

## 4. Python-агент (D4)

- [ ] 4.1 Тест в `e2e_agent_test.dart`:
  - `unavailable` — причина, когда `codelab serve --help` не отвечает как Python-агент (подставная команда в `PATH`);
  - `launch` в режиме `python` пишет `codelab.toml` с `provider = "mock"` во временный `CODELAB_HOME` и даёт ответ `Mock response`.

  Красный.
- [ ] 4.2 Режим `python` в `E2eCliAgent`; тесты с тегом `python-agent` пропускаются с причиной без агента — 4.1 зелёный.
- [ ] 4.3 Прогон `fvm dart run melos run test:e2e:cli:python-agent`:
  - с установленным Python-агентом — зелёный;
  - без агента — пропуски с причиной (сценарии «Python-агент не установлен», «Ответ Python-агента»).

## 5. Документы и Definition of Done

- [ ] 5.1 `09-11-stage-6-cli-mvp.md`:
  - 6.10 — матрица агентов, `CODELAB_E2E_AGENT`, скрипты;
  - DoD — `test:e2e:cli:dart-agent` в `check` и CI, Python-агент — локально.
- [ ] 5.2 `agent-parity-goals.md`: критерии U-01…U-05, U-07, U-15, H-01, H-02, P-09, S-04 — e2e против scripted- и Dart-агента, H-01 и U-01 — также Python. `delivery-roadmap.md` §4.3: пункт e2e CLI против трёх агентов выполнен — ссылка на этот change.
- [ ] 5.3 Проверка DoD:
  - `fvm dart run melos run check` зелёный локально и в CI;
  - `test:e2e:cli:python-agent` зелёный с установленным Python-агентом;
  - `openspec validate add-cli-e2e-agent-matrix --strict` без ошибок;
  - PR итерации 2.
