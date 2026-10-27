## Why

Сверка codelab_desktop с макетом (артборд States) показала два пробела в сценариях сбоя:

- **Обрыв соединения посреди работы почти не виден.** Экран подключения с кнопкой Reconnect рисуется только при пустой ленте (`main_pane.dart`). Если в ленте уже есть записи, о потере соединения говорит лишь статус в шапке, а композер молча становится недоступен.
- **Сорвавшийся ход показан сырым текстом исключения.** Пользователь видит строку вида `Failed to send prompt: ACP request session/prompt failed: Turn failed` и не может повторить ход, не набирая промпт заново.

При этом агент уже присылает машиночитаемую причину сбоя хода в `data.codelab` (`errorClass`, `message`, `retryable`, spec `agent-acp-server`, §13.8 документа ядра). Клиент её теряет: ядро клиента сохраняет только `error.toString()`.

Это пункт 2.2 фазы 2 плана UI/UX (этап 5). Пункт 2.1, список сессий и перезагрузка, уже в `develop`.

## What Changes

- **Ядро клиента различает «соединение потеряно» и «подключиться не удалось».** Неожиданный сбой транспорта в `Connected` даёт новое состояние `ConnectionLost`, а не `ConnectionFailed`. `ConnectionFailed` остаётся за неудачными `connect()` и `reconnect()`.
  **BREAKING** для потребителей `ConnectionView`, которые перебирают его варианты исчерпывающим `switch`.
- **Сбой хода хранится типизированно.** `codelab_client_acp` разбирает ответ-ошибку на `session/prompt` в `PromptFailure`:
  - `agent`: из `data.codelab` — `errorClass`, `message`, `retryable`;
  - `request`: прочие JSON-RPC ошибки;
  - `connectionLost`: ход прервал обрыв соединения;
  - `unknown`.

  Строка `failureMessage` остаётся для диагностики. Неизвестный `errorClass` не ломает разбор.
- **Баннер соединения над лентой.** Если лента не пуста и соединение потеряно, подключение не удалось или идёт переподключение, над лентой показывается баннер:
  - текст причины;
  - действие Reconnect, пока соединение потеряно или подключиться не удалось;
  - индикатор прогресса, пока идёт переподключение;
  - ссылка на настройки подключения.

  Пустая лента по-прежнему показывает экран подключения.
- **Понятная заметка о сбое хода.** Вместо `Prompt failed` с сырым текстом лента показывает заметку:
  - заголовок по классу сбоя;
  - сообщение агента;
  - свёрнутые технические подробности.

  У последнего сорвавшегося хода есть действие Retry: оно отправляет тот же промпт новым ходом. Действия Retry нет у сбоя с `retryable: false` и у хода, прерванного обрывом соединения: такой ход переподключается через баннер.

## Capabilities

### New Capabilities

Нет.

### Modified Capabilities

- `acp-client-kit`:
  - автомат соединения получает состояние `ConnectionLost`;
  - проекция транскрипта несёт типизированный сбой хода в `NoticeItem` вида `error`;
  - kit даёт команду повтора последнего сорвавшегося хода.
- `acp-protocol-client`: ответ-ошибка на `session/prompt` сохраняется в ходе как типизированный `PromptFailure`, расширение `data.codelab` разбирается.
- `agent-workbench-ui`:
  - «Workbench честно отражает спонтанную потерю соединения»: состояние `lost` и баннер вместо одного статуса `failed`;
  - новые требования — баннер соединения над лентой и заметка о сбое хода с Retry.

## Impact

- `packages/dart/codelab_client_acp`:
  - `PromptTurn` получает поле `failure`;
  - разбор `JsonRpcError.data.codelab` на границе ACP;
  - `PromptTurnStateMachine.fail` принимает `PromptFailure`.
- `packages/dart/codelab_client_core`:
  - `ConnectionView.lost`;
  - переход из `Connected` по сбою транспорта;
  - `NoticeItem` с `failure`;
  - `ClientWorkspace.retryTurn`.
- `packages/flutter/codelab_ui`:
  - молекула `CodeLabConnectionBanner` на `InfoBar` из fluent_ui;
  - заметка о сбое хода в `CodeLabTranscriptPanel` с действием и свёрнутыми подробностями;
  - статус `lost` в `CodeLabConnectionStatus`.
- `apps/codelab_desktop`:
  - `ui_mappers.dart`: тексты по `errorClass`, статус соединения;
  - `main_pane.dart`: баннер;
  - Cubit-ы: действие Retry.
- Фикстуры ACP: в корпусе уже есть `acp/prompt-failed-provider-auth` и сбои `network` и `server`. Новые сообщения протокола не вводятся.
- Пересечение с change `add-resumed-turn-after-reload` (ведётся отдельно): он решает, что происходит с прерванным ходом после переподключения. Этот change лишь помечает такой ход как `connectionLost` и не предлагает для него Retry (design D5).
