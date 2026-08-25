# CodeLab UI/UX Canvas

Визуальный референс UI/UX для CodeLab — 19 экранов/компонентов ("артбордов"), выверенных по реальным исходникам `packages/flutter/acp_ui` и `fluent_ui` (цвета, типографика, spacing взяты из кода, а не на глаз).

## Как смотреть

- **Быстро, по одному экрану**: открыть любой `*.dc.html` файл напрямую в браузере — каждый самодостаточен.
- **Как единый pan/zoom канвас**: есть приватная опубликованная версия — ссылку на неё уточните в команде, здесь она намеренно не публикуется (репозиторий публичный).
- `canvas.json` описывает раскладку артбордов на канвасе (позиции, размеры) — используется только при пересборке единого канваса, не нужен для просмотра отдельных файлов.

## Список артбордов

| Файл | Что показывает |
|---|---|
| `Main.dc.html` | Workbench — активная сессия: командная панель, вкладки сессий/файлов, транскрипт, progress checklist, композер с чипами модели/режима, свёрнутый терминал |
| `ConnectionStdio.dc.html` | Подключение — stdio-профиль |
| `ConnectionWebSocket.dc.html` | Подключение — WebSocket, замаскированный токен |
| `EditProfileDialog.dc.html` | Диалог настройки профиля подключения |
| `CommandPalette.dc.html` | Command palette — оверлей по `Ctrl/Cmd+K` |
| `InlineCommandTrigger.dc.html` | Command palette — inline-триггер по `/` в композере |
| `ApprovalDiff.dc.html` | Approval-панель: 4 опции по `PermissionOptionKind`, диф-вьюер, collapsible raw input |
| `PromptQueue.dc.html` | Очередь сообщений, отправленных пока сессия занята |
| `PlanChecklist.dc.html` | Progress checklist на основе `PlanEntry` |
| `SessionOptionsRow.dc.html` | Селекторы модели и permission-mode (проектное предложение) |
| `FilePreview.dc.html` | Read-only просмотр файла (из tool call или с диска) |
| `AddContext.dc.html` | Вложение файлов/картинок в промпт (`ContentBlock`) |
| `FilesAndTerminal.dc.html` | Дерево каталогов + развёрнутый терминал |
| `ResizablePanels.dc.html` | Перетаскиваемые границы панелей |
| `ErrorReconnect.dc.html` | Disconnected/failed состояние с конкретным действием восстановления |
| `NarrowResponsive.dc.html` | Узкое окно — rail + drawer вместо полного скрытия панелей |
| `MultiSessionSplit.dc.html` | Multi-session split view (north-star, по паттерну Claude Code Desktop) |
| `ComponentSheet.dc.html` | Справочник компонентов `acp_ui`: цвета, типографика, кнопки, бейджи, spacing/radius-токены |
| `NavigationFlow.dc.html` | Карта переходов между состояниями |

## Связь с OpenSpec

Большинство экранов здесь соответствуют конкретным `openspec/changes/*`:

- `wire-command-palette` — `CommandPalette.dc.html`, `InlineCommandTrigger.dc.html`
- `complete-transport-setup-actions` — `EditProfileDialog.dc.html`
- `add-file-preview-and-tree` — `FilePreview.dc.html`, `FilesAndTerminal.dc.html` (дерево)
- `add-integrated-terminal` — `FilesAndTerminal.dc.html` (терминал)
- `add-approval-option-kinds` — `ApprovalDiff.dc.html`
- `add-plan-progress-checklist` — `PlanChecklist.dc.html`
- `add-prompt-queue` — `PromptQueue.dc.html`
- `add-resizable-panels` — `ResizablePanels.dc.html`

`SessionOptionsRow.dc.html`, `AddContext.dc.html`, `MultiSessionSplit.dc.html` — проектные предложения, ещё не оформленные как OpenSpec change.

Это референс для обсуждения и проектирования, не спецификация для дословной реализации — при расхождении с `openspec/changes/*` источником истины являются сами change'ы.
