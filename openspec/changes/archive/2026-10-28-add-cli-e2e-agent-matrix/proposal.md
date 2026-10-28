## Why

Критерий выхода вехи M2 (`delivery-roadmap.md` §4.3) и задача 6.10 этапа 6 требуют, чтобы e2e `codelab_cli` проходили против трёх агентов: scripted, Dart и Python. Сейчас тесты `apps/codelab_cli/test/e2e/` (`cli/*`) идут только против scripted-агента из `codelab_acp_testing`. Dart-агент проверен руками и прогоном корпуса фикстур (`test-scenario`), Python-агент — только руками. Аудит M2 (PR #143) оставил этот пункт открытым.

## What Changes

- Выбор агента для e2e CLI — переменная окружения `CODELAB_E2E_AGENT=scripted|dart|python`, по умолчанию `scripted`; так же устроены тесты app (`CODELAB_E2E_AGENT`, change `add-codelab-agent-binary`, D9).
- Помощник `apps/codelab_cli/test/e2e/support/e2e_agent.dart`:
  - возвращает значение `--agent` для режима сценария (`CodelabCompatibleStdioAgentMode`);
  - возвращает ожидания, которые у агентов различаются: текст ответа, заголовок и команда одобрения, итог одобрения, модели.
  - Тесты больше не зашивают тексты scripted-агента.
- **Dart-агент:**
  - `apps/codelab_agent/bin/codelab_agent.dart` один раз компилируется в kernel, как CLI. Процесс — `dart <agent>.dill serve --stdio --llm-script <сценарий>`, без импорта `codelab_agent_*` в тесты CLI (сторож).
  - Сценарии — `apps/codelab_cli/test/e2e/llm_scripts/<wireName>.json`. Их загрузку проверяет `apps/codelab_agent/test/llm_scripts_load_test.dart`.
- **Python-агент:**
  - запускается `codelab serve --stdio` из `PATH` с временным `CODELAB_HOME` и провайдером `mock`;
  - без установленного агента тесты пропускаются с сообщением;
  - гоняются только тесты обычного хода (тег `python-agent`).
- Тег `scripted-only` для тестов поведения, которое есть только у scripted-агента: WebSocket-агент теста, команды агента в slash-меню и сбои транспорта.
- Melos-скрипты `test:e2e:cli:dart-agent` и `test:e2e:cli:python-agent`.
- `check` и CI запускают e2e CLI против Dart-агента: это Dart VM, `AGENTS.md` §21.
- Прогон против Python-агента — локальный: в CI Python-агента нет.

## Capabilities

### New Capabilities

Нет.

### Modified Capabilities

- `testing-quality`:
  - «PTY-e2e терминального клиента» — матрица агентов, выбор через `CODELAB_E2E_AGENT`, теги `scripted-only` и `python-agent`, пропуск без Python-агента;
  - «Проверки workspace» — скрипты `test:e2e:cli:dart-agent` и `test:e2e:cli:python-agent`, первый входит в `check`;
  - «Непрерывная интеграция» — джоб e2e CLI против Dart-агента.

## Impact

- **Код:**
  - `apps/codelab_cli/test/e2e/` — все `*_test.dart` и `support/`;
  - новые `support/e2e_agent.dart`, `llm_scripts/*.json` и `dart_test.yaml` с тегами;
  - `apps/codelab_agent/test/llm_scripts_load_test.dart`.
  - `lib/` CLI и агента не меняется.
- **Конфигурация:** корневой `pubspec.yaml` (секция `melos:`), `.github/workflows/ci.yml`.
- **Документы:**
  - `09-11-stage-6-cli-mvp.md` (6.10 и DoD);
  - `delivery-roadmap.md` §4.3 (критерий M2 выполнен);
  - `agent-parity-goals.md` (U-01…U-07, H-01, H-02, P-09, S-04 — против трёх агентов).
- **Время CI:** отдельный джоб `e2e-cli-dart` — компиляция kernel агента и около 40 процессов CLI; остальные джобы не удлиняются.
