---
description: Двойное ревью текущей ветки CodeLab (архитектура + безопасность/ACP) с прогоном melos check
argument-hint: [change-id или фокус ревью]
---
Контекст: $ARGUMENTS

1. **check-runner** — `melos run check` (параллельно с шагом 2).
2. **architecture-reviewer** и **acp-safety-reviewer** — параллельно; diff: `git diff develop...HEAD` плюс незакоммиченные изменения. Если указан change-id — передай путь `openspec/changes/<change-id>/`, иначе пусть ревьюверы сами найдут связанный change.
3. Покажи пользователю: таблицу проверок, оба вердикта, сводный список замечаний (сначала CRITICAL/BLOCKER).

Ничего не исправляй без просьбы. Если пользователь попросит — раздай замечания исполнителям по зонам (protocol / agent / client / desktop) и повтори ревью.
