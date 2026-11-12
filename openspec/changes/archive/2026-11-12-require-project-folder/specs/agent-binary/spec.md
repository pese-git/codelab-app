## ADDED Requirements

### Requirement: Проектный конфиг сессий в serve
`codelab-agent serve --stdio` (кроме прогона `--llm-script`) SHALL передавать ядру порт `ProjectConfigLoader` — источник `serveConfigSource` с теми же окружением, флагами, `--config` и закреплённым доверием. Сессия вне корня запуска тогда получает конфигурацию и функцию модели своей папки (флаги запуска входят в её слои) (spec agent-runtime «Конфигурация сессии вне корня запуска»; design.md change `require-project-folder`, D21). Корень запуска по-прежнему задаёт ключи процесса (`HostSettings`). `serve --ws` порт НЕ SHALL передавать: по WebSocket `cwd` называет клиент, а проектные файлы бинарь по WebSocket не читает (requirement «Файлы проекта в бинаре»; design.md, Q18 (a)); сессия вне корня получает `withoutProject` и лог `config.session.outside_root`, как раньше.

#### Scenario: serve обслуживает сессию другой папки
- **WHEN** `codelab-agent serve --stdio` запущен в `/A`, доверенный проект `/B` задаёт `budget.max_steps: 3`, и клиент создаёт сессию с `cwd: /B`
- **THEN** бюджет хода этой сессии — 3 шага, а флаги запуска (`--model`, `--provider`) по-прежнему действуют как слой флагов

#### Scenario: serve --ws не читает конфиг папки клиента
- **WHEN** `codelab-agent serve --ws` запущен в `/A`, доверенный проект `/B` на машине агента задаёт `budget.max_steps: 3`, и клиент создаёт сессию с `cwd: /B`
- **THEN** проектные слои `/B` не читаются: сессия получает `withoutProject`, лог `config.session.outside_root`
