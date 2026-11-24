## MODIFIED Requirements

### Requirement: Неизвестный уровень риска вызова
Клиентский уровень риска одобрения (`ApprovalRiskLevel` пакета `codelab_client_acp`) SHALL иметь значение `unknown` для вызова, вид которого (`ToolKind` ACP) — `other` или не передан; `read`, `search` и `think` остаются `readOnly`. `unknown` SHALL ранжироваться выше `readOnly` и ниже `localWrite`. Автоматическая политика клиента SHALL NOT считать его чтением (AGENTS.md §10: неизвестная потенциально опасная capability не считается безопасной; решение пользователя 2026-11-08, design.md change `add-provider-setup-ui`, Q32, D27). Правила риска для незнакомого вида и `switch_mode` — approval-safety «Риск вызова неизвестного вида и смены режима». Новых полей и значений ACP это не вводит.

#### Scenario: Вид other
- **WHEN** агент запрашивает разрешение на вызов с `kind: other` без содержимого diff и терминала
- **THEN** уровень риска одобрения — `unknown`, CLI показывает `unknown risk` (`approval_prompt_test.dart`, «an unknown risk is shown as "unknown risk"»)

#### Scenario: Вид не передан
- **WHEN** `tool_call` пришёл без `kind`
- **THEN** уровень риска — `unknown`, а не `readOnly` (`codelab_client_acp_test.dart`, группа «unknown approval risk»)
