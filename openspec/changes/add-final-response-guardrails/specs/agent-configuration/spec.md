## ADDED Requirements

### Requirement: Ключи проверок финального ответа
Раздел `loop.final_response` SHALL быть разделом схемы с применяемыми ключами, а не непрозрачным узлом (design.md change `add-final-response-guardrails`, D5):

| Ключ | Тип | По умолчанию | Ограничения |
|---|---|---|---|
| `loop.final_response.checks` | список строк | `[]` | id встроенных проверок: `open_tasks`, `unverified_success` |
| `loop.final_response.max_revisions` | int | `2` | `0..5` |
| `loop.final_response.on_revise_limit` | `hold` \| `accept` | `hold` | |

Неизвестный id в `checks` SHALL давать предупреждение валидации (`ConfigIssue` вида `semantic`, ключ `loop.final_response.checks`) и пропускаться; запуск НЕ SHALL прерываться. Значение `max_revisions` вне `0..5` и неизвестное значение `on_revise_limit` SHALL давать ошибку валидации ключа, как у других числовых и перечислимых ключей схемы. Прочие ключи раздела (например, `require_approval`) SHALL считаться неизвестными ключами схемы.

Ключи НЕ SHALL требовать перезапуска: новое значение SHALL действовать со следующего вызова финального гейта открытой сессии. Реестр настроек SHALL описывать раздел дескриптором раздела `Advanced` с правкой только в файле, без маски `<opaque: edit the file>`.

Недоверенный проект (корень не в `trusted_projects`) SHALL только ужесточать проверки; для `project` и `projectLocal` без доверия:
- `checks` SHALL объединяться со значением нижних слоёв, а не заменять его;
- `on_revise_limit: accept` поверх `hold` нижних слоёв или умолчания SHALL отбрасываться;
- `max_revisions` больше значения нижних слоёв или умолчания `2` SHALL отбрасываться.
- `max_revisions` меньше значения нижних слоёв или умолчания `2` SHALL отбрасываться, если итоговая политика `on_revise_limit` после этих правил — `accept`: при `accept` уменьшение лимита снимает проверки пользователя. При итоговой `hold` уменьшение применяется.

Каждое отбрасывание SHALL давать предупреждение `config.project.untrusted_key` с ключом. У доверенного проекта ограничений нет; слои `extra`, окружения и флагов правилам доверия не подчиняются.

#### Scenario: Умолчания
- **WHEN** ни один слой не задаёт `loop.final_response`
- **THEN** `checks` пуст, `max_revisions` равен `2`, `on_revise_limit` равен `hold`, проблем конфигурации нет

#### Scenario: Неизвестная проверка
- **WHEN** глобальный конфиг задаёт `loop.final_response.checks: [open_tasks, tone]`
- **THEN** `config check` показывает предупреждение по ключу `loop.final_response.checks` с id `tone`, в снимке `checks` равен `[open_tasks]`

#### Scenario: Лимит вне диапазона
- **WHEN** конфиг задаёт `loop.final_response.max_revisions: 9`
- **THEN** валидация даёт ошибку ключа `loop.final_response.max_revisions`

#### Scenario: Недоверенный проект не снимает проверку
- **WHEN** глобальный конфиг задаёт `checks: [unverified_success]`, а недоверенный проект — `checks: [open_tasks]` и `on_revise_limit: accept`
- **THEN** в снимке `checks` содержит обе проверки, `on_revise_limit` равен `hold`, есть предупреждение `config.project.untrusted_key` с ключом `loop.final_response.on_revise_limit`

#### Scenario: Недоверенный проект не увеличивает лимит
- **WHEN** недоверенный проект задаёт `max_revisions: 5` поверх умолчания
- **THEN** в снимке `max_revisions` равен `2`, есть предупреждение `config.project.untrusted_key` с ключом `loop.final_response.max_revisions`

#### Scenario: Доверенный проект
- **WHEN** проект в `trusted_projects` задаёт `checks: []`, `on_revise_limit: accept` и `max_revisions: 4` поверх глобальных `checks: [open_tasks]`
- **THEN** в снимке значения проекта, предупреждений доверия нет

#### Scenario: Недоверенный проект не снимает проверки лимитом
- **WHEN** глобальный конфиг задаёт `checks: [unverified_success]` и `on_revise_limit: accept`, а недоверенный проект — `max_revisions: 0`
- **THEN** в снимке `max_revisions` равен `2`, есть предупреждение `config.project.untrusted_key` с ключом `loop.final_response.max_revisions`

#### Scenario: Недоверенный проект ужесточает лимит при hold
- **WHEN** политика нижних слоёв — `hold` (умолчание), а недоверенный проект задаёт `max_revisions: 0`
- **THEN** в снимке `max_revisions` равен `0`, предупреждения доверия по этому ключу нет
