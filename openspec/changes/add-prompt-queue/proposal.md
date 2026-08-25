## Why

`SessionStateMachine._startTurn` уже корректно отклоняет новый prompt turn, если сессия не в статусе `idle`/`active` — то есть во время `runningTurn` или `awaitingApproval` (`packages/dart/acp_client_core/lib/src/domain/state_machines.dart:793-795`, `_rejected('session already has an active prompt turn')`). Protocol-корректность на уровне domain уже обеспечена.

Но `CodeLabShellCubit.submitPrompt()` (`shell_cubit.dart:532-560`) не знает об этом инварианте: сообщение пользователя оптимистично добавляется в транскрипт **до** попытки отправки, а `AcpPromptComposer._submit()` синхронно очищает текстовое поле сразу после вызова `onSubmit`, не дожидаясь результата (`acp_prompt_composer.dart`, `_submit()`). Если сессия занята (approval pending или turn ещё выполняется), запрос отклоняется state machine, в транскрипте появляется запись "Prompt failed" — а набранный пользователем текст уже потерян: поле ввода пустое, восстановить текст можно только вручную перечитав неудавшуюся запись в транскрипте.

## What Changes

- `CodeLabShellCubit` получает клиентскую очередь сообщений (`queuedPrompts` в `CodeLabShellState`): если на момент `submitPrompt()` сессия не может принять новый turn (`isPromptSubmitting` или `pendingApproval != null`), сообщение **не пытается отправиться** и не добавляется в транскрипт как отправленное — вместо этого попадает в очередь.
- Появляется панель "Queued messages" между транскриптом и композером, видимая только при непустой очереди: на каждый элемент — текст сообщения, действия **Edit** (возвращает текст в композер, убирает из очереди), **Delete** (удаляет), **Send Now** (немедленная попытка отправки вне очереди — если сессия всё ещё занята, сообщение возвращается в очередь с тем же местом); плюс **Clear All** для всей очереди.
- Когда блокирующее состояние снимается (turn завершается или approval разрешается), самое старое сообщение в очереди отправляется автоматически, по порядку (FIFO) — без необходимости вручную нажимать "Send Now".
- **BREAKING**: нет. `SessionStateMachine`/ACP contracts не меняются — очередь строится поверх уже существующего, корректного guard'а, а не заменяет его.

## Capabilities

### New Capabilities

_(нет)_

### Modified Capabilities

- `agent-workbench-ui`: требование "Agent workbench interaction patterns" уже упоминает "compact transcript" и общий прогрессивный поток взаимодействия — эта delta уточняет, что происходит с вводом пользователя, когда сессия занята, вместо недосказанности в исходном требовании.

## Impact

- `apps/codelab_app/lib/features/workbench/application/shell_cubit.dart` — `submitPrompt()` проверяет, может ли сессия принять turn, прежде чем отправлять; новые методы `editQueuedPrompt`/`deleteQueuedPrompt`/`sendQueuedPromptNow`/`clearQueuedPrompts`; авто-drain очереди при снятии блокировки.
- `apps/codelab_app/lib/features/workbench/application/shell_cubit.dart` (state) — новое поле `queuedPrompts: List<CodeLabQueuedPrompt>`.
- `packages/flutter/acp_ui/lib/src/organisms/` — новый `AcpPromptQueuePanel`.
- `packages/flutter/acp_ui/lib/src/molecules/acp_prompt_composer.dart` — `initialPrompt` уже поддержан для возврата текста при Edit, изменений не требует (переиспользуется как есть).
- `apps/codelab_app/lib/features/workbench/presentation/widgets/main_pane.dart` — интеграция панели очереди.
- `apps/codelab_app/test/widget_test.dart` — тесты на постановку в очередь, edit/delete/send-now/clear-all, авто-drain.
