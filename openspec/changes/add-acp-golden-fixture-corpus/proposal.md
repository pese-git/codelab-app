## Why

Эталон поведения Dart-агента и обоих ACP-клиентов — спецификация ACP, golden-фикстуры ACP и интеграционные тесты клиентов (ADR-0001, Decision; `docs/architecture/proposals/agent-core/14-golden-fixtures.md`). Корпуса фикстур в репозитории нет: есть только `acp_protocol/test/protocol_conformance_test.dart` и fake-транспорт в `acp_testing`. Поведение клиента на конкретных последовательностях кадров (разрешение, отмена посреди инструмента, `fs/*` и `terminal/*`, незнакомый `session/update`) проверяется разрозненными тестами без общего формата, а агентская проверка этапа 4 и матрица целей паритета ссылаются на id фикстур, которых ещё нет. Этап 0 (`dart-agent-and-clients/09-05-stage-0-foundation.md`, задачи 0.7–0.8) создаёт формат, первые 12 фикстур и клиентский прогон, чтобы с этапа 1 каждая новая возможность закрывалась фикстурой.

## What Changes

- **Формат фикстуры** (agent-core-architecture §14.4): JSON-файл `packages/dart/acp_testing/fixtures/acp/<имя>.json` с полями `id`, `spec`, `description`, `goals`, `extensions`, `roles`, `setup`, `llm`, `frames`, `normalize`, `after`; `_schema.json` (JSON Schema draft 2020-12) описывает формат.
- **Поле `roles`** — `["agent", "client"]` по умолчанию: какие проверки берут фикстуру. Кадры `fs/*` и `terminal/*` — часть сценария обеих ролей.
- **Нормализация и матчеры** (§14.5, §14.6): переменные `${cwd}`, `${sessionId}`, `$capture`; плейсхолдер времени `<ts>`; пути; точное сравнение по умолчанию; матчеры `$any`, `$absent`, `$capture`, `$regex`, `$contains`, `$partial`, `$oneOf`, `$text`; `_meta` — всегда `$partial`.
- **Загрузчик** `acp_testing/lib/src/fixtures/fixture.dart`: громко падает на неполной или противоречивой фикстуре; проверяет инварианты корпуса FIX-1 и FIX-4 и клиентскую часть FIX-2.
- **Клиентский драйвер** `acp_testing/lib/src/fixtures/client_conformance.dart` (§14.10): проигрывает кадры `a2c` в `FakeAcpTransport`, сверяет кадры `c2a`, отвечает на `fs/*` и `terminal/*` из `setup.files` через fake-порты клиента, хук `onBeforeExpect` для действий пользователя.
- **12 фикстур этапа 0**: `acp/initialize-capabilities` (R-01), `acp/session-new-modes-config`, `acp/prompt-text-end-turn`, `acp/prompt-cancel-mid-tool`, `acp/prompt-tool-permission-allow` (P-02), `acp/prompt-tool-permission-reject-continues` (P-04), `acp/tool-status-lifecycle`, `acp/tool-read-range` (T-01), `acp/tool-exec-terminal-embed` (T-08), `acp/prompt-update-plan` (C-05), `acp/set-config-option-model` (R-06), `acp/errors-unknown-session-update-tolerated` (только `client`).
- **Клиентский прогон корпуса** `packages/dart/acp_client_core/test/fixtures/client_fixture_conformance_test.dart` — `AcpClientApplication` на каждой фикстуре с ролью `client`.
- **Скрипт melos `conformance:client`**, его включение в `check` и в джоб CI `conformance`.
- **Правила изменения фикстур**: фикстура меняется только вместе со ссылкой на раздел спецификации; правка ожидаемых кадров под реализацию без ссылки запрещена.

Не входит: агентский драйвер `agent_conformance.dart` и прогон агента (задача 4.8), инвариант FIX-3 (ссылки строк Must матрицы на фикстуры — проверяется вместе с агентским прогоном), фикстуры этапов 4 и 8.

## Capabilities

### New Capabilities
- `acp-golden-fixtures`: формат и корпус golden-фикстур ACP, нормализация и матчеры, инварианты корпуса, клиентский драйвер и правила изменения фикстур.

### Modified Capabilities
- `testing-quality`: добавляется требование о клиентской conformance-проверке на корпусе фикстур в составе полной проверки и CI.

## Impact

- `packages/dart/acp_testing`: каталог `fixtures/acp/` (12 фикстур и `_schema.json`), `lib/src/fixtures/` (`fixture.dart`, `matcher.dart`, `client_conformance.dart`), экспорт из публичного бареля, тесты загрузчика, матчера и покрытия.
- `packages/dart/acp_client_core/test/fixtures/` — новый тест.
- Корневой `pubspec.yaml` (скрипт `conformance:client`, `check`), `.github/workflows/ci.yml` (джоб `conformance`).
- Зависимости: новых нет — загрузчик проверяет структуру сам, `_schema.json` служит описанием формата (design.md, D2).
- Зависит от change `add-workspace-ci-and-architecture-guards`: скрипты `check` и CI добавляются туда, где они уже есть.
- Поведение `codelab_app`, `acp_client_core` и ACP-контракты не меняются; если клиентский прогон найдёт расхождение клиента со спецификацией, исправление — отдельный change.
