# Документация CodeLab

Указатель: где что лежит и с чего начать. Сам каталог `docs/` — только часть документации: README и `doc/` приложений и пакетов лежат рядом с кодом, а поведение продукта описано в `openspec/`.

## С чего начать

| Кто вы | Куда идти |
|---|---|
| Пользователь | [`user/README.md`](user/README.md) — запуск из исходников, настройка агента, руководства app и CLI |
| Эксплуатация (DevOps) | [`ops/README.md`](ops/README.md) — сборка, запуск в CI, каталог `CODELAB_HOME`, переменные окружения |
| Разработчик | [`architecture/README.md`](architecture/README.md) — слои, границы, ACP, тесты; README приложений и пакетов — таблица «[Структура](../README.md#структура)» корневого `README.md`; поведение продукта — [`openspec/specs/`](../openspec/specs/), источник истины (`AGENTS.md` §3.1) |
| AI-агент | [`AGENTS.md`](../AGENTS.md) — обязательные правила репозитория; [`CLAUDE.md`](../CLAUDE.md) — команда субагентов и команды Claude Code; [`README-claude-team.md`](../README-claude-team.md) — как работать с этой командой |

## Каталоги

- [`architecture/`](architecture/README.md) — архитектура: слои и зависимости, граница ACP, сессии, потоки, разрешения, тесты; ADR и предложения в `adr/` и `proposals/`.
- [`user/`](user/README.md) — документация пользователя app и CLI.
- [`ops/`](ops/README.md) — документация эксплуатации.
- [`protocols/`](protocols/README.md) — референсные спецификации ACP, A2A, MCP и Agent Skills и справочник `AGENTS-GUIDE.md` о написании `AGENTS.md`. Их не изменяют (`AGENTS.md` §3.4, §5).
- [`backlog/`](backlog/README.md) — отчёты смоук-прогонов и ревью с найденными пунктами; из них заводят changes и issues.
- `design/` — визуальные материалы:
  - [`brand/`](design/brand/README.md) — знак, логотип и иконки приложения, генератор иконок;
  - [`claude-design/`](design/claude-design/README.md) — текущий экспорт канваса UI/UX (app, CLI, планшет, смартфон), обновлён 2026-11-22;
  - [`ui-canvas/`](design/ui-canvas/README.md) — ранний канвас UI/UX рабочего места, 21 артборд; каталог не менялся с 2026-10-28.
  Канвасы — референс, а не спецификация: при расхождении верны `openspec/` и `docs/architecture/`.
- [`integrations/`](integrations/claude-code.md) — работа с внешними агентами; сейчас один документ: Claude Code по ACP и его отличия от эталонного протокола.
- [`codelab-spec.md`](codelab-spec.md) — исходная спецификация MVP. Исторический документ, не нормативен.

## Что публикуется на сайте

Сайт CodeLab (`site/`) публикует только файлы из allowlist `site/src/lib/publish.ts`:

- `docs/user/**/*.md`;
- `docs/ops/**/*.md`;
- `README.md` и `doc/**/*.md` приложений (`apps/*`) и пакетов (`packages/*/*`).

Файлы `AGENTS.md` не публикуются нигде. Остальное из `docs/` — `architecture/`, `backlog/`, `design/`, `protocols/`, `integrations/`, `codelab-spec.md` и этот указатель — на сайт не попадает.
