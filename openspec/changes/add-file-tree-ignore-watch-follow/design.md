## Context

Change выделен из `add-file-preview-and-tree` 2026-11-23. Технические решения итераций 3–5 приняты и записаны в design.md того change:
- D1 — пакеты и слои (`GitIgnoreMatcher`, `IgnoreStack` в kit);
- D2 — контракт `ProjectFiles`, включая будущие `list(…, IgnoreStack)` и `watch`;
- D6 — состояние `ProjectFilesCubit`;
- D8 — «Open file» и Following;
- D11 — наблюдение;
- D12 — тесты;
- D13 — отступления от артборда «Files» («Show ignored files»);
- D14 — строка «Show ignored files» на странице «General»;
- решения пользователя Q4, Q6, Q7, Q9.

Здесь они не повторяются; ссылки «D8», «Q4» в `tasks.md` ведут в design.md `add-file-preview-and-tree` (после архивирования — `openspec/changes/archive/<дата>-add-file-preview-and-tree/design.md`).

## Goals / Non-Goals

**Goals:** итерации 3–5 панели Files в отдельном change, чтобы `add-file-preview-and-tree` можно было архивировать и перенести требования панели v1 в `openspec/specs/`.

**Non-Goals:** пересмотр решений D1–D14; изменение поведения панели v1.

## Decisions

### D1. Разделение по итерациям

Сюда уходят итерации 3–5 целиком, с прежними номерами задач, и их требования:
- `workspace-file-browser` — четыре требования итераций 3–5 (ADDED). Требования панели v1 их не упоминают, поэтому смешанных требований нет;
- `acp-client-kit` — «Места вызова с номером строки» (итерация 5);
- `app-settings` — вся дельта: строка «Show ignored files» показывается только вместе с фильтром `.gitignore` (SETUP-17), то есть с итерацией 3.

Альтернатива — синхронизировать готовые требования в `openspec/specs/` без разделения. Тогда дельта исходного change перестала бы совпадать с главной спецификацией, и при архивировании понадобился бы `--skip-specs` без проверки.

### D2. Порядок архивирования

ADDED этого change в `workspace-file-browser` добавляются в capability, которую создаёт `add-file-preview-and-tree`. Поэтому тот архивируется первым.

## Risks / Trade-offs

- **[Контракт порта в спецификации]** Требование `acp-client-kit` «Чтение папки проекта в границах рабочей папки» перечисляет члены порта `ProjectFiles` (`canonicalRoot`, `list`, `read`). Итерации 3 и 4 добавляют в порт `IgnoreStack` у `list` и `watch` (D2). Исходная дельта этих членов в требованиях kit не описывала, и здесь они не придумываются. → Если по ходу итераций 3–4 перечень членов порта в спецификации нужно расширить, это MODIFIED «Чтение папки проекта…» в этом change. Решение — до задачи 3.3 (открытый вопрос ниже).
- **[Ссылки на задачи]** `apps/codelab_desktop/AGENTS.md` («Show ignored files», задачи 3.5–3.6) и `12-4-first-run-and-settings.md` ссылались на итерацию 3 исходного change. → Ссылки в `docs/architecture/` и `apps/codelab_desktop/AGENTS.md` обновлены при разделении; строку о владельце `ShowIgnoredFilesCubit` дописывает задача 3.6.

## Open Questions

- Нужен ли MODIFIED требования `acp-client-kit` «Чтение папки проекта в границах рабочей папки» с членами `list(…, IgnoreStack)` и `watch`, или порт описывают требования `workspace-file-browser`? Решить до задачи 3.3.
