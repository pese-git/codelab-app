## Why

Лента transcript прокручивается к низу только при появлении нового pending approval. Всё остальное, что дописывается в конец, — ответ агента, карточки инструментов, результаты — остаётся ниже видимой части, пока пользователь не прокрутит ленту сам. С Dart-агентом это видно сразу: карточки инструментов (`read`, `write`, `exec`) занимают высоту, и итоговое сообщение агента оказывается за пределами ленивого списка. e2e `fs_flow_test` и `terminal_flow_test` против бинаря `codelab-agent` падают именно так: сообщение есть в `transcriptEntries`, но виджет offstage.

Следование за хвостом уже запланировано в `docs/architecture/proposals/dart-agent-and-clients/12-3-desktop-display.md` (A2, шаг 5), но в утверждённом spec `agent-workbench-ui` его нет. Это изменение видимого поведения, поэтому оно оформляется отдельным change.

## What Changes

- Если перед обновлением ленты пользователь был у низа (в пределах 80 px, существующий порог `_autoScrollBottomThreshold`) и не прокручивал ленту вверх, после кадра лента прокручивается к низу без анимации.
- Если пользователь прокрутил ленту вверх, чтобы читать историю, позиция не меняется.
- Лента продолжает держать низ, когда ленивый список уточняет высоту ещё не построенных записей, пока пользователь сам не прокрутит ленту.
- Анимированная автопрокрутка к новому pending approval не меняется.
- Не входит: кнопка «К последнему сообщению» из плана A2 — отдельное изменение.
- **BREAKING**: нет.

## Capabilities

### New Capabilities
_Нет._

### Modified Capabilities
- `agent-workbench-ui`: новое требование «Лента transcript следует за хвостом».

## Impact

- `packages/flutter/codelab_ui/lib/src/organisms/codelab_transcript_panel.dart` — `_CodeLabTranscriptPanelState`: решение о следовании в `didUpdateWidget`, прокрутка после кадра, сброс при прокрутке пользователем.
- `packages/flutter/codelab_ui/test/codelab_organisms_test.dart` — widget-тесты панели.
- e2e `apps/codelab_desktop/integration_test/fs_flow_test.dart`, `terminal_flow_test.dart` против Dart-агента находят итоговое сообщение без изменений тестов.
