## ADDED Requirements

### Requirement: Объявление расширений CodeLab при initialize
CodeLab SHALL отправлять в `InitializeRequest.clientCapabilities._meta.codelab` объект с расширениями, данные которых клиент понимает (design.md change `add-subagents-and-tasks`, D9, D21): `{"tasks": {"version": 1}, "subagents": {"version": 1}, "subagentToolCalls": {"version": 1}}`; `subagentToolCalls` — согласие получать вызовы потомков деревом. Других полей вне `_meta` CodeLab для этого НЕ SHALL добавлять (`15-Extensibility.md`).

Блок `agentCapabilities._meta.codelab` в ответе SHALL разбираться терпимо:
- его отсутствие — «агент расширений CodeLab не объявил»;
- неизвестные ключи, нецелый или больший `version` и неверная форма значения SHALL игнорироваться без отказа `initialize`;
- известные значения (`subagents.maxDepth`, наличие `tasks`) SHALL быть доступны приложению как согласованные возможности соединения.

Данные `_meta.codelab.task` и `_meta.codelab.subagent` SHALL приниматься и без объявления агента: клиент на объявление не полагается, чтобы показ не зависел от того, кто и как загрузил сессию.

#### Scenario: Запрос initialize клиента CodeLab
- **WHEN** CodeLab выполняет `initialize`
- **THEN** `clientCapabilities._meta.codelab` равен `{"tasks": {"version": 1}, "subagents": {"version": 1}, "subagentToolCalls": {"version": 1}}`, остальные поля `clientCapabilities` — как прежде (фикстура `acp/initialize-codelab-extensions`, роль `client`)

#### Scenario: Агент без блока объявлений
- **WHEN** агент отвечает на `initialize` без `agentCapabilities._meta`
- **THEN** `initialize` успешен, согласованных расширений CodeLab нет, `plan` с `_meta.codelab.task` от такого агента всё равно разбирается

#### Scenario: Будущая версия расширения
- **WHEN** ответ содержит `agentCapabilities._meta.codelab.tasks: {"version": 2, "x": 1}` и ключ `board: true`
- **THEN** `initialize` успешен, неизвестное игнорируется без ошибки
