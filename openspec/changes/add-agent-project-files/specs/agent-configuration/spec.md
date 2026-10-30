## ADDED Requirements

### Requirement: Ключ tools.project_context.max_bytes
Ключ `tools.project_context.max_bytes` SHALL применяться: целое `0..262144`, по умолчанию `32768`; `0` выключает чтение контекста проекта (design.md change `add-agent-project-files`, D5). Значение вне диапазона SHALL быть проблемой конфига с путём ключа. В проектных слоях недоверенного проекта значение SHALL приниматься только на уменьшение относительно результата слияния нижних слоёв; увеличение SHALL отбрасываться с предупреждением `config.project.untrusted_key`. Ключ НЕ SHALL давать `config.key.not_applied`.

#### Scenario: Увеличение из недоверенного проекта
- **WHEN** глобальный конфиг не задаёт ключ, а `.codelab/config.yaml` недоверенного проекта задаёт `tools.project_context.max_bytes: 200000`
- **THEN** итоговое значение `32768`, предупреждение `config.project.untrusted_key` с ключом `tools.project_context.max_bytes`

#### Scenario: Уменьшение из проекта
- **WHEN** недоверенный проект задаёт `tools.project_context.max_bytes: 4096`
- **THEN** итоговое значение `4096`, предупреждения нет

### Requirement: Доверенные проекты в CoreConfig
`CoreConfig` SHALL содержать `trustedProjects` — канонические абсолютные корни из `trusted_projects` глобального слоя (после раскрытия `~` и symlink в `ConfigLoader`); снимок `withoutProject` SHALL содержать тот же список. Проектные слои список не меняют (CFG-3).

#### Scenario: Список доступен сессии вне корня
- **WHEN** глобальный конфиг доверяет `/work/a` и `/work/b`, а проектные слои прочитаны для `/work/a`
- **THEN** `config.trustedProjects` и `config.withoutProject.trustedProjects` равны `[/work/a, /work/b]`

### Requirement: config check показывает диагностику файлов проекта
`ConfigCommands.check` SHALL после валидной загрузки конфига загружать файлы проекта для `--cwd` тем же `ProjectFilesLoader` с доверием и каталогом моделей загруженного конфига и печатать каждую диагностику уровня `error` или `warning` строкой `warning: <path>[:<line>[:<column>]]: <message>` перед последней строкой (design.md, D13). Диагностики уровня `info` НЕ SHALL печататься. Диагностики НЕ SHALL считаться проблемами: последняя строка и код выхода определяются только конфигом. При невалидном конфиге файлы проекта НЕ SHALL проверяться. Тексты НЕ SHALL содержать фрагментов файлов.

#### Scenario: Битое определение агента
- **WHEN** конфиг валиден, проект доверенный, а `.codelab/agents/reviewer.md` содержит неизвестный ключ `color` в строке 4
- **THEN** stdout содержит `warning: <cwd>/.codelab/agents/reviewer.md:4:1: unknown key color`, последняя строка `Config: valid`, код `0`

#### Scenario: Одинаково у двух бинарей
- **WHEN** `codelab-agent config check` и `codelab config check` запускаются в том же `cwd` с битым шаблоном `$CODELAB_HOME/prompts/Review.md`
- **THEN** у обоих есть строка `warning:` с путём шаблона и `invalid command name`, коды выхода совпадают
