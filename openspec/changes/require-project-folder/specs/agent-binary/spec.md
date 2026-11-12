## ADDED Requirements

### Requirement: Проектный конфиг сессий в serve
`codelab-agent serve` (кроме прогона `--llm-script`) SHALL передавать ядру порт `ProjectConfigLoader` — источник `serveConfigSource` с теми же окружением, флагами, `--config` и закреплённым доверием. Сессия вне корня запуска тогда получает конфигурацию и функцию модели своей папки (флаги запуска входят в её слои) (spec agent-runtime «Конфигурация сессии вне корня запуска»; design.md change `require-project-folder`, D21). Корень запуска по-прежнему задаёт ключи процесса (`HostSettings`).

#### Scenario: serve обслуживает сессию другой папки
- **WHEN** `codelab-agent serve --stdio` запущен в `/A`, доверенный проект `/B` задаёт `budget.max_steps: 3`, и клиент создаёт сессию с `cwd: /B`
- **THEN** бюджет хода этой сессии — 3 шага, а флаги запуска (`--model`, `--provider`) по-прежнему действуют как слой флагов
