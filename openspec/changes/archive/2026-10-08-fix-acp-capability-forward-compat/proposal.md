## Why

Ручная проверка подключения к реальному, спецификации-совместимому агенту (`@zed-industries/claude-code-acp`, обёртка над настоящим Claude Code) показала, что CodeLab не может установить соединение вообще: `initialize` отвечает `agentCapabilities.sessionCapabilities: {"fork": {}, "list": {}, "resume": {}}`, а `SessionCapabilities.fromJson` (`packages/dart/acp_protocol/lib/src/acp/initialize.dart`) допускает только `list`/`_meta` и выбрасывает `JsonRpcProtocolException.invalidShape` при виде `fork`/`resume` — через общий `requireOnlyRootKeys` (`acp_validation.dart`), который трактует любое незнакомое корневое поле как protocol error. В результате весь handshake падает, соединение помечается `Failed`, и CodeLab не может работать ни с одним агентом, чей набор capability-флагов шире того, что здесь смоделировано на сегодня — а `docs/acp/protocol/` фиксирует лишь снапшот апстрим-спеки на момент вендоринга, и агенты по конструкции ACP анонсируют capability-флаги, добавленные позже.

## What Changes

- Decode-слой capability-объектов `initialize` (в первую очередь `agentCapabilities`/`sessionCapabilities`, и по аналогии остальные вложенные capability-объекты initialize handshake) перестаёт падать на незнакомых корневых полях — неизвестный флаг, которого нет в текущей типизированной модели, игнорируется при decode, а не приводит к отказу всего `initialize`. Не то же самое, что "придумывать" ACP-семантику (AGENTS.md §3.4/§7): CodeLab по-прежнему не интерпретирует и не использует незнакомое поле — оно просто перестаёт быть фатальным для остальной, понятной части ответа.
- Область изменения — только capability-negotiation объекты `initialize` (структуры, которые сама спека ACP предполагает расширяемыми со временem), а не вся валидация ACP-сообщений: `requireOnlyRootKeys`/`requireAcpObject` в остальных местах (`session_update.dart`, `prompt.dart`, `tool_call.dart`, `permission.dart`, `fs.dart`, `terminal.dart`, `session.dart`) продолжают строго отклонять неожиданные поля как раньше — это runtime-сообщения, а не декларация capabilities, и там неожиданное поле — по-прежнему сигнал реальной protocol error, а не будущей capability. Точный механизм (общий helper с allow-list "лояльных" путей vs. точечные правки — см. design.md) определяется в design.md.
- **BREAKING**: нет. Поведение для уже понятных полей не меняется; меняется только реакция на поля, которых CodeLab сегодня не знает.

## Capabilities

### New Capabilities
_Нет._

### Modified Capabilities
- `acp-protocol-client`: требование "Инициализация и capabilities" дополняется сценарием про незнакомые поля внутри capability-объектов `initialize` — они не должны приводить к отказу всего handshake.

## Impact

- `packages/dart/acp_protocol/lib/src/acp/initialize.dart` — `AgentCapabilities.fromJson`/`SessionCapabilities.fromJson`/`SessionListCapabilities.fromJson` (и, по необходимости, соседние capability-модели того же файла) перестают вызывать строгий `requireOnlyRootKeys` для незнакомых полей.
- `packages/dart/acp_protocol/lib/src/acp/acp_validation.dart` — либо новый более лояльный helper рядом с `requireOnlyRootKeys`, либо параметр, отличающий "capability-объект" от "runtime-сообщение" (решается в design.md).
- `packages/dart/acp_protocol/test/` — новые тесты: `initialize` с незнакомыми полями в `sessionCapabilities`/`agentCapabilities` decode'ится успешно и игнорирует их; существующие тесты на strict-валидацию для НЕ-capability объектов (session/prompt/tool_call/...) остаются без изменений и продолжают проходить.
- Реальная интероперабельность: после фикса CodeLab сможет подключаться к `@zed-industries/claude-code-acp` и другим агентам с более широким, чем сегодня смоделировано, набором `sessionCapabilities`.
