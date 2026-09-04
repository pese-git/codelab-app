## Why

`PermissionOptionKind` (`packages/dart/acp_protocol/lib/src/acp/permission.dart:30-34`) уже полностью моделирует четыре стандартных варианта решения по разрешению: `allowOnce`, `allowAlways`, `rejectOnce`, `rejectAlways`. Но при маппинге в UI-модель (`CodeLabShellCubit._approvalOption`, `shell_cubit.dart:809-819`) этот `kind` используется только чтобы выбрать один из двух `AcpTone` (success/danger) — сам `kind` в `AcpApprovalOption` не попадает, там нет такого поля вообще (`acp_approval_option_group.dart:8-19`). В результате `AcpApprovalOptionGroup` назначает клавиатурные шорткаты через **поиск подстроки** `.contains('allow')`/`.contains('reject')` в `label` — тексте, который вообще-то присылает агент (`option.name`), а не сам CodeLab (`acp_approval_option_group.dart:82-110`). Опция без слова "allow"/"reject" в названии от агента останется без шортката.

## What Changes

- `AcpApprovalOption` (`acp_ui`) получает поле `kind: AcpApprovalOptionKind` (`allowOnce`/`allowAlways`/`rejectOnce`/`rejectAlways`) — прямое зеркало `PermissionOptionKind`, не новая семантика.
- `AcpApprovalOptionGroup` назначает шорткаты **по `kind`**, а не по тексту label: `allowOnce` → `Ctrl/Cmd+Enter`, `allowAlways` → `Alt/Option+Ctrl/Cmd+Enter`, `rejectOnce` → `Ctrl/Cmd+Backspace`, `rejectAlways` → `Alt/Option+Ctrl/Cmd+Backspace`. Текущие параметры `approveOptionId`/`rejectOptionId` (string-based override) остаются как ручной override для нестандартных случаев, но перестают быть единственным механизмом.
- `CodeLabShellCubit._approvalOption` передаёт `kind` напрямую, не сворачивая его до tone — tone продолжает выводиться из kind (allow→success, reject→danger), но kind больше не теряется.
- Добавляется свёрнутая по умолчанию секция "View raw input" в `AcpApprovalPanel` — раскрывающийся блок с сырыми входными данными tool call (то, что сейчас всегда видно как обрезанный `rawInput` в инспекторе, `inspector_pane.dart:224`, здесь — по требованию, не всегда).
- **BREAKING**: нет — `AcpApprovalOption.kind` необязательное или с безопасным default? Нет: делаем обязательным полем, но это internal API `acp_ui`, единственный вызывающий код — `shell_cubit.dart`, который уже имеет `PermissionOptionKind` под рукой на этой строке — миграция тривиальна, ACP contracts не затрагиваются.

## Capabilities

### New Capabilities

_(нет)_

### Modified Capabilities

- `agent-workbench-ui`: уточняет требование "Agent workbench interaction patterns" (уже упоминающее "inline approvals") — approval-опции должны различать 4 стандартных kind с соответствующими им шорткатами, а не угадывать по тексту.

## Impact

- `packages/flutter/acp_ui/lib/src/molecules/acp_approval_option_group.dart` — добавление `kind`, замена string-heuristics на kind-based маппинг шорткатов.
- `packages/flutter/acp_ui/lib/src/organisms/acp_approval_panel.dart` — добавление collapsible "View raw input".
- `apps/codelab_app/lib/features/workbench/application/shell_cubit.dart:809-819` — `_approvalOption` передаёт `kind`.
- `packages/flutter/acp_ui/test/` — тесты на kind-based шорткаты и на дефолтный collapsed-раскрывающийся raw input.
