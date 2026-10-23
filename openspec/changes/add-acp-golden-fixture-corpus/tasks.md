Задачи идут парами «тест → реализация» (§9.0, правило 3); в скобках — задача этапа 0 (`dart-agent-and-clients/09-05-stage-0-foundation.md`) и сценарий спецификации. Группы 1–3 — итерация 1 (формат и инструменты), 4–6 — итерация 2 (фикстуры и прогон). Начинается после итерации 2 change `add-workspace-ci-and-architecture-guards` (скрипты melos), правка CI — после его итерации 3.

## 1. Модель и загрузчик фикстуры (0.7)

- [x] 1.1 Тест (acp-golden-fixtures «Неполная фикстура падает громко»): `acp_testing/test/fixture_loader_test.dart` — нет обязательного поля, `id` не совпадает с файлом, неизвестный ключ, неверный `dir`, неверный `roles`, неверное поле шага `llm` (красный)
- [x] 1.2 Тест (acp-golden-fixtures «Полная фикстура загружается»): минимальная фикстура во временном каталоге; `roles` по умолчанию `["agent", "client"]` (красный)
- [x] 1.3 Реализовать `lib/src/fixtures/fixture.dart`: модель (`AcpFixture`, `FixtureSetup` с `cwd`, `files`, `profile`, `mode`, `config`, `clientCapabilities`, `terminal`, `skipInitialize`; `FixtureFrame`; `llm` — структура по §14.7 без выполнения, design.md D6), загрузчик каталога корпуса (design.md D1) — 1.1 и 1.2 зелёные
- [x] 1.4 `fixtures/acp/_schema.json` по §14.4 (с `setup.terminal`); тест (acp-golden-fixtures «Схема и загрузчик согласованы») `fixtures_schema_sync_test.dart` — сначала красный, затем зелёный

## 2. Нормализация и матчер (0.7)

- [x] 2.1 Тест (acp-golden-fixtures «Мутация кадра ловится»): `matcher_test.dart` — лишний ключ, другой статус, другой порядок массива, отсутствующий ключ; каждый случай — провал с путём JSON (красный)
- [x] 2.2 Тесты матчеров `$any`, `$absent`, `$capture`, `$regex`, `$contains`, `$partial`, `$oneOf`, `$text` с `repeat: "+"`, `unordered`, `optional`; `_meta` как `$partial` (красные)
- [x] 2.3 Тесты нормализации: `${cwd}`, `${sessionId}`, `<ts>`, префикс `cwd` и разделители путей, `normalize.replace` (красные)
- [x] 2.4 Реализовать `lib/src/fixtures/matcher.dart` (нормализация и сравнение, список расхождений) — 2.1–2.3 зелёные; тест (acp-golden-fixtures «Захват id запроса агента») зелёный

## 3. Клиентский драйвер (0.7)

- [x] 3.1 Тест (acp-golden-fixtures «Фикстура только для агента»): фикстура с `roles: ["agent"]` пропускается с причиной (красный)
- [x] 3.2 Тест драйвера на минимальной фикстуре «prompt → текст → `end_turn`» во временном каталоге (красный)
- [x] 3.3 Реализовать `lib/src/fixtures/client_conformance.dart`: `runClientFixture(fixture, clientFactory, {onBeforeExpect})`, стандартный handshake, `a2c` → `emitInbound`, `c2a` → ожидание в `sentMessages` (таймаут 5 с), fs через `TextFileReader`/`TextFileWriter` поверх временного каталога из `setup.files`, terminal через `FakeTerminalProcessRunner` по `setup.terminal`, сверка `after.files` (design.md D4) — 3.1 и 3.2 зелёные
- [x] 3.4 Экспорт модели, загрузчика, матчера и драйвера из `package:acp_testing/acp_testing.dart`

## 4. Инварианты корпуса (0.7)

- [ ] 4.1 Тест (acp-golden-fixtures «Битая ссылка на спецификацию», «Расширение без объявления»): `fixtures_load_test.dart` — все фикстуры корпуса загружаются, FIX-1 (файл и якорь в `docs/acp/protocol/`), FIX-4; негативные случаи на временном каталоге
- [ ] 4.2 Тест (acp-golden-fixtures «Покрытие расширилось»): `fixtures_coverage_test.dart` — клиентская часть FIX-2 со списком `pendingCoverage` (design.md D5); падает и на непокрытом элементе вне списка, и на покрытом элементе из списка

## 5. Фикстуры этапа 0 (0.7)

Для каждой фикстуры: написать кадры по разделу спецификации (ссылка в `spec`), `goals` — id строки матрицы, блок `llm` для роли `agent` (design.md D6) → загрузка и FIX-1/FIX-4 зелёные → клиентский прогон (группа 6); при расхождении с клиентом — design.md D7, без правки кадров под клиента.

- [ ] 5.1 `acp/initialize-capabilities` (R-01) — `02-Initialization.md`
- [ ] 5.2 `acp/session-new-modes-config` — `03-Session Setup.md`, `13-Session Config Options.md`; `available_commands_update` со списком `{"$any": true}`
- [ ] 5.3 `acp/prompt-text-end-turn` — `05-Prompt Turn.md`
- [ ] 5.4 `acp/prompt-cancel-mid-tool` — `05-Prompt Turn.md` (отмена), без `_meta.codelab` в ожидаемых кадрах
- [ ] 5.5 `acp/prompt-tool-permission-allow` (P-02) — `08-Tool Calls.md#requesting-permission`
- [ ] 5.6 `acp/prompt-tool-permission-reject-continues` (P-04) — `08-Tool Calls.md`
- [ ] 5.7 `acp/tool-status-lifecycle` — `08-Tool Calls.md`
- [ ] 5.8 `acp/tool-read-range` (T-01) — `09-File System.md`
- [ ] 5.9 `acp/tool-exec-terminal-embed` (T-08) — `10-Terminal.md`, `setup.terminal`
- [ ] 5.10 `acp/prompt-update-plan` (C-05) — `11-Agent Plan.md`
- [ ] 5.11 `acp/set-config-option-model` (R-06) — `13-Session Config Options.md`
- [ ] 5.12 `acp/errors-unknown-session-update-tolerated` — `roles: ["client"]`; спецификация совместимости (`15-Extensibility.md`) и требование `acp-protocol-client` о незнакомом виде `session/update`
- [ ] 5.13 Проверка: в корпусе ровно 12 фикстур (кроме `_schema.json`); список `pendingCoverage` соответствует 4.2

## 6. Клиентский прогон корпуса (0.8)

- [ ] 6.1 Тест (testing-quality «Корпус этапа 0 проходит»): `packages/dart/acp_client_core/test/fixtures/client_fixture_conformance_test.dart` — для каждой фикстуры с ролью `client` поднимает `AcpClientApplication` на `FakeAcpTransport` с fs- и terminal-портами драйвера; хуки `onBeforeExpect` для `session/prompt`, выбора варианта разрешения и `session/cancel`; проверки итогового состояния сессии (вызов `completed`, план, опция конфигурации, ход завершён)
- [ ] 6.2 Скрипт melos `conformance:client` с `description`; добавить в `check` после `protocol-conformance`
- [ ] 6.3 `.github/workflows/ci.yml`: джоб `conformance` — `protocol-conformance conformance:client`
- [ ] 6.4 Шаблон pull request: пункт «Фикстуры изменены только со ссылкой на раздел спецификации» (acp-golden-fixtures «Правила изменения фикстур»)
- [ ] 6.5 Проверка (testing-quality «Полная проверка включает клиентский прогон»): `fvm dart run melos run check` зелёный; джоб CI `conformance` зелёный и запускает оба скрипта

## 7. Завершение

- [ ] 7.1 Definition of Done `09-05` в части этого change: `fvm dart test packages/dart/acp_client_core/test/fixtures` проходит на 12 фикстурах
- [ ] 7.2 `openspec validate add-acp-golden-fixture-corpus --strict`; архивировать change после слияния последней итерации (§9.0, правило 6)
