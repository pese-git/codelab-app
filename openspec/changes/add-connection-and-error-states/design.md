## Context

Состояние соединения клиента — закрытая иерархия `ConnectionView` в `codelab_client_core`:

```text
Disconnected → Connecting → Connected | ConnectionFailed
reconnect():   Reconnecting → Connected | ConnectionFailed
сбой транспорта в Connected → ConnectionFailed
```

`ConnectionFailed` описывает два разных для пользователя события одним вариантом:

- попытка `connect()` или `reconnect()` не удалась — пользователь только что нажал кнопку и ждёт результата;
- соединение оборвалось само, когда пользователь работал в ленте.

Desktop показывает экран подключения с Reconnect (`CodeLabConnectionScreen`) только при пустой ленте (`main_pane.dart`). Если в ленте уже есть записи, на обрыв указывают только статус в шапке и недоступный композер.

Сбой хода сейчас проходит такой путь:

1. Агент отвечает на `session/prompt` JSON-RPC ошибкой `-32603` с `data.codelab {errorClass, message, retryable}` (spec `agent-acp-server`, §13.8 документа ядра).
2. `AcpClientApplication.sendPrompt` ловит исключение и передаёт в `SessionStateMachine.failTurn` строку `error.toString()`.
3. `TranscriptProjector` строит `NoticeItem(kind: error, text: 'Failed to send prompt: …')`.
4. `ui_mappers.dart` рисует из неё диагностическую запись `Prompt failed`.

Структурированная причина теряется уже на шаге 2.

Ограничения:

- граница ACP (`AGENTS.md` §7): разбор `data.codelab` — в `codelab_client_acp`, виджеты протокол не разбирают;
- явные автоматы состояний (§8);
- поздние события старого поколения не меняют состояние (§9);
- секреты не попадают в UI-тексты и логи (§16).

## Goals / Non-Goals

**Goals:**

- Различать «соединение потеряно» и «подключиться не удалось» в автомате ядра клиента, а не эвристикой в UI.
- Показывать состояние соединения над непустой лентой с действием Reconnect.
- Хранить сбой хода типизированно и показывать понятную заметку с действием Retry там, где повтор имеет смысл.

**Non-Goals:**

- Автоматическое переподключение с повторами и паузами — отдельное решение. Kit по-прежнему делает одну попытку (spec `acp-client-kit` «Явный автомат соединения»).
- Судьба хода, прерванного обрывом, после переподключения — change `add-resumed-turn-after-reload`.
- Локализация текстов. Тексты UI на английском, как во всём workbench.
- Отображение `data.codelab.rateLimit` — только через OpenSpec `add-rate-limit-info` (§13.8).
- Явная кнопка Disconnect и баннер для `Disconnected` — такого действия в UI сейчас нет.

## Decisions

### D1. `ConnectionView.lost` — отдельный вариант, а не флаг в `ConnectionFailed`

Добавляется `ConnectionView.lost({required ConnectionFailureReason reason, required String message})`. Переход: сбой транспорта в `Connected` → `ConnectionLost`. `reconnect()` из `ConnectionLost` идёт так же, как из `ConnectionFailed`: `Reconnecting` → `Connected | ConnectionFailed`.

Источником служит то, что `ClientWorkspace` видит переход `ClientConnectionReady → ClientConnectionFailed` вне своего вызова `connect()` или `reconnect()`. Эту развилку `client_workspace.dart` уже проводит, чтобы не задваивать диагностику (spec `agent-workbench-ui` «Workbench честно отражает спонтанную потерю соединения»).

Рассмотренные альтернативы:

- **Поле `wasConnected` в `ConnectionFailed`.** Отклонено: это тот же булев флаг, от которого уходит §8. UI легко забудет его проверить, а исчерпывающий `switch` по новому варианту заставит разобрать случай.
- **Вывод «потеряно» в UI по истории состояний.** Отклонено: state Cubit-а — проекция, а не источник истины (`codelab_client_core/AGENTS.md`). Решение о смысле перехода принадлежит ядру клиента.

В `codelab_client_acp` автомат `ClientConnectionState` не меняется: «потеряно» — понятие рабочего пространства, а не протокола.

### D2. `PromptFailure` — типизированный сбой хода в `codelab_client_acp`

```dart
sealed class PromptFailure {
  agent({String? errorClass, String message, bool? retryable})  // из data.codelab
  request({int code, String message})        // JSON-RPC ошибка без data.codelab
  connectionLost()                            // ход прервала потеря соединения
  unknown({String message})                   // прочие исключения
}
```

- `PromptTurn` получает `PromptFailure? failure`. `failureMessage` остаётся строкой для диагностики и журнала.
- `PromptTurnStateMachine.fail` и `SessionStateMachine.failTurn` принимают `failure` вместе с `message`.
- Разбор `JsonRpcError.data` выполняет одна функция на границе ACP в `codelab_client_acp`.

Правила разбора:

- `errorClass` хранится строкой, а не enum. Это расширение агента CodeLab, его словарь (`LlmErrorClass`, `AgentErrorClass`) растёт. Неизвестное значение не должно ломать разбор: forward compatibility, §7.
- Нет `data.codelab`, или `data.codelab` не объект, — получается `request`.
- `retryable` не `bool` — получается `null`, «неизвестно».

Ход, прерванный обрывом, получает `connectionLost`. Сейчас обрыв проявляется исключением ожидающего `session/prompt` при сбое транспорта; классификация идёт по типу этого исключения и по тому, что соединение к этому моменту перешло в `failed`. Ход старого поколения, прерванный заменой транспорта, остаётся под требованием «Ход, прерванный заменой транспорта».

Альтернатива — класть разбор в `codelab_client_core`. Отклонено: core видит только `PromptTurn`, а разбор wire-формата — ответственность протокольного слоя (§7, «изменения wire protocol локализовать на ACP/application boundary»).

### D3. Заметка о сбое — проекция `PromptFailure`, тексты — в app

`NoticeItem` вида `error` получает `PromptFailure? failure` и `bool canRetry`. Поле `text` остаётся: это нейтральная строка для CLI, где UI-текстов нет.

Тексты строит `ui_mappers.dart` по `errorClass`:

| `errorClass` | Заголовок |
|---|---|
| `auth` | The agent could not sign in to the model provider |
| `network`, `timeout`, `server` | The model provider is unavailable |
| `rateLimited` | The model provider's rate limit was reached |
| `overflow` | The conversation is too long for the model |
| прочие, `request`, `unknown` | The agent could not complete the turn |
| `connectionLost` | The connection to the agent was lost |

Тело заметки:

- для `agent` — `message` агента. Это текст для пользователя, например `401 Unauthorized from openai: check api_key_env`. Секреты агент в него не кладёт (§12 документа ядра).
- для `request` — `message` JSON-RPC.

Сырой текст исключения уходит в свёрнутый блок Details. Блок закрыт по умолчанию, как сырой ввод в панели одобрения.

Альтернатива — тексты в `codelab_client_core`. Отклонено: core общий для app и CLI и web-безопасен; формулировки для человека — дело представления.

### D4. Retry — команда kit, повторяющая промпт новым ходом

`ClientWorkspace.retryTurn(sessionId)` берёт `prompt` последнего хода сессии и отправляет его как новый `session/prompt` по обычному пути, с той же очередью и теми же правилами занятости. Ходы не редактируются и не удаляются: сорвавшийся ход остаётся в ленте как история.

`canRetry` истинно, только если выполнены все условия:

- ход — последний в сессии и `failed`;
- `failure` — не `connectionLost`;
- `failure` — не `agent` с `retryable == false`;
- сессия не занята;
- соединение `Connected`.

`retryable == null` повтор не запрещает. Агент мог не прислать признак, а повторить ход пользователь может и вручную.

Альтернатива — заполнять композер текстом промпта. Отклонено: промпт может содержать нетекстовые блоки, а действие в один клик и есть смысл Retry из макета.

### D5. Ход, прерванный обрывом, повторяется через переподключение, а не через Retry

У `connectionLost` заметка говорит «The connection to the agent was lost» и не предлагает Retry. Действие Reconnect находится в баннере (D6).

После переподключения сессия перезагружается (`add-session-list-and-reload`). Что станет с прерванным ходом — отменён по реплею сейчас, возобновлён после change `add-resumed-turn-after-reload` — решает та работа.

Retry здесь отправил бы второй ход поверх, возможно, ещё живого хода агента. Это нарушило бы корректность протокола, приоритет 2 в §2.

### D6. Баннер — молекула `CodeLabConnectionBanner` на fluent `InfoBar`

`codelab_ui` получает молекулу без логики. Её параметры:

- `status`: `lost`, `failed` или `reconnecting`;
- `message`;
- `onReconnect`;
- `onConfigureConnection`.

Desktop кладёт её над лентой в `WorkbenchMainPane`, когда лента не пуста и `ConnectionView` — `lost`, `failed` или `reconnecting`.

| Статус | Severity `InfoBar` | Заголовок | Действия |
|---|---|---|---|
| `lost` | `warning` | Connection to the agent lost | Reconnect, Connection settings |
| `failed` | `error` | Could not connect to the agent | Reconnect, Connection settings |
| `reconnecting` | `info` | Reconnecting… | индикатор прогресса, кнопки нет |

При пустой ленте баннер не показывается: там остаётся `CodeLabConnectionScreen`, чтобы одно состояние не рисовалось дважды.

Баннер не закрывается крестиком. Он отражает состояние, а не событие: исчезает, когда соединение снова `Connected`.

Альтернатива — `ContentDialog`. Отклонено: модальное окно мешает читать ленту, а при потере соединения пользователь как раз хочет видеть, на чём остановился ход.

## Risks / Trade-offs

- **Новый вариант `ConnectionView` ломает исчерпывающие `switch` у потребителей.**
  → Потребитель сейчас один (`ui_mappers.dart`), компилятор найдёт остальные. Статус в шапке для `lost` — `failed` с тем же цветом, чтобы не плодить визуальных состояний.
- **Агент без `data.codelab`** — сторонний ACP-агент.
  → Сбой разбирается как `request`. Пользователь видит общий заголовок и `message` JSON-RPC, Retry доступен. Это не хуже сегодняшнего.
- **`message` агента может быть длинным или многострочным.**
  → В теле заметки показываются первые строки с переносом, полный текст — в Details.
- **Retry сразу после `retryable: false` скрыт, хотя пользователь мог исправить причину**, например `api_key_env`.
  → Промпт можно отправить заново из композера. Скрытие — честная передача решения агента.

## Migration Plan

Сохранённых данных change не меняет: снимок рабочего пространства хранит только проект, профиль и сессии, не ходы. Откат — revert ветки.

## Open Questions

Нет: решения D1–D6 закрывают объём пункта 2.2 плана.
