# AGENTS.md — codelab_acp_testing

Правила этого пакета дополняют корневой `AGENTS.md`.

Источники: корневой `AGENTS.md` §3.4, §5, §21; `README.md` пакета («Golden-фикстуры»); `openspec/specs/acp-golden-fixtures/spec.md`; `.claude/agents/acp-protocol-engineer.md` (TDD: фикстуру проигрывают обе роли).

## 1. Назначение

Фикстуры, fake-транспорты и драйверы для conformance-тестов ACP; корпус golden-фикстур лежит в `fixtures/acp/`. Формат и API — в `README.md`.

## 2. Границы

* Другие пакеты подключают этот пакет только как `dev_dependency`. Исключение — `apps/codelab_cli`: импорт `package:codelab_acp_testing/` разрешён только из `lib/src/scenario/` (корневой `AGENTS.md` §5; сторож — `rules.dart`, правило `apps/codelab_cli/lib/src`).

## 3. Правила

* Фикстуры описывают ACP по `docs/protocols/acp/`: поле `spec` ссылается на существующие файлы и якоря; методы и поля не придумываются (§3.4). Формат — `fixtures/acp/_schema.json`, правится вместе с загрузчиком (`README.md`, «Как добавить фикстуру»).
* Сторонние фикстуры НЕ ДОЛЖНЫ копироваться (§5).
* Новую фикстуру ДОЛЖНЫ проигрывать обе роли, если `roles` не сужает её (`conformance:client`, `conformance:agent`).

## 4. Проверки

`fvm dart test` в пакете; `melos run conformance:client`, `conformance:agent`, `guard` (§21).
