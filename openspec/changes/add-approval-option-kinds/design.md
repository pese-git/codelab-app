## Context

`CodeLabShellCubit._approvalOption` (`shell_cubit.dart:809-819`) уже получает `PermissionOption.kind: PermissionOptionKind` из протокола на входе — данные есть. Но `AcpApprovalOption` (`acp_approval_option_group.dart:8-19`) не имеет поля `kind`, только `id`/`label`/`description`/`tone`, поэтому маппинг сворачивает 4 значения kind в 2 значения tone, и `kind` дальше нигде не используется. Шорткаты (`_defaultApproveOptionId`/`_defaultRejectOptionId`, `acp_approval_option_group.dart:82-110`) ищут "allow"/"approve"/"reject"/"deny" **в тексте**, который приходит от агента (`option.name`) — не гарантированно на английском, не гарантированно содержит эти слова.

## Goals / Non-Goals

**Goals:**
- `AcpApprovalOption.kind` — прямое зеркало `PermissionOptionKind`, без потери информации между протоколом и UI.
- Шорткаты назначаются по `kind`, детерминированно, не завися от текста label.
- Explicit override (`approveOptionId`/`rejectOptionId`) остаётся доступным для случаев, когда поведение по умолчанию не подходит.
- Collapsible "View raw input" в `AcpApprovalPanel`, свёрнут по умолчанию.

**Non-Goals:**
- Не меняется сама approval-safety модель (risk levels, permission modes) — только то, как рендерятся уже существующие 4 kind опций.
- Не меняется способ, которым агент формулирует `option.name` — CodeLab не переписывает текст агента.
- Raw input в инспекторе (`_InspectorRawBlock`, `inspector_pane.dart`) не трогаем — это отдельная область, за пределами approval-панели.

## Decisions

- **`AcpApprovalOptionKind` — новый enum в `acp_ui`**, а не переиспользование `PermissionOptionKind` из `acp_protocol` напрямую в UI-слое: `acp_ui` не должен зависеть от протокольного пакета для чисто presentational enum (границы пакетов, `AGENTS.md` §5/§7) — `shell_cubit.dart` мапит `PermissionOptionKind` → `AcpApprovalOptionKind` явно, одна строка на каждое значение, 1:1.
- **Шорткаты — фиксированная таблица по kind**, не настраиваемая через props сверх текущих `approveOptionId`/`rejectOptionId` override. Четыре стандартных сочетания (см. proposal.md) — этого достаточно для MVP; полная кастомизация шорткатов пользователем не входит в scope.
- **"View raw input" — свёрнут по умолчанию, `ExpandableSection`-подобный виджет** (или инлайн `Expander` из fluent_ui, если он покрывает потребность — проверить на этапе задач перед тем, как писать собственный) — данные берутся из уже существующих полей approval-запроса (rawInput tool call), не требуют нового протокольного маппинга.

## Risks / Trade-offs

- [Явный `kind` на UI-уровне может разойтись с протокольным `PermissionOptionKind`, если протокол добавит новый kind в будущей версии ACP] → `PermissionOptionKind.fromJson` в протокольном слое уже бросает `JsonRpcProtocolException` на неизвестный kind (`permission.dart:40-50`) — новый kind сначала сломает протокольный парсинг, что даст явную ошибку раньше, чем тихое несоответствие в UI; маппинг в `shell_cubit.dart` в этом случае потребует обновления одновременно с протокольным пакетом.
- [Изменение публичного API `AcpApprovalOption` (новое обязательное поле) — breaking change для `acp_ui` как пакета] → единственный вызывающий код сегодня — `shell_cubit.dart`, миграция тривиальна и делается в этом же change; не оставляем deprecated-путь ради гипотетических внешних потребителей пакета, которых нет.
