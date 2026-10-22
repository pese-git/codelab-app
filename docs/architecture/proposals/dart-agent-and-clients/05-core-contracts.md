# 5. Контракты ядра

> Часть предложения [«Dart-агент и клиенты CodeLab»](../dart-agent-and-clients.md). Status: Proposed. Исходные решения, связанные документы и порядок чтения — в оглавлении.

← [4. Целевая архитектура](04-target-architecture.md) · [Оглавление](../dart-agent-and-clients.md) · [6. Режимы работы и потоки](06-modes-and-flows.md) →

Окончательные сигнатуры — в документе ядра (§5 для публичного API, §2–§10 для остальных
контрактов). Здесь — только то, на чём держатся решения этого предложения.

## 5.1. Публичный API

```dart
abstract interface class AgentRuntime {
  Future<AgentSession> createSession(SessionSpec spec);   // cwd, mode, model, mcpServers, порты хоста
  Future<AgentSession> loadSession(SessionId id, SessionHostPorts ports);
  Future<List<SessionSummary>> listSessions({String? cwd});
  Future<void> dispose();
}

abstract interface class AgentSession {
  SessionId get id;
  Stream<AgentEvent> get events;             // широковещательный, с буфером текущего хода для поздних подписчиков
  Future<TurnResult> prompt(List<ContentBlock> content, {CancelToken? cancel});
  void steer(List<ContentBlock> content);   // ввод посреди хода
  Future<void> cancel();                     // отменяет текущий ход
  Future<void> setMode(ModeId mode);
  Future<void> setConfigOption(String id, String value);
  Iterable<AgentEvent> replay();             // проекция журнала для session/load
}
```

## 5.2. Инварианты, на которых держится предложение

1. `StreamFunction` никогда не бросает: ошибки провайдера — события, ход не падает (документ ядра §2).
2. Проверка разрешений — первый хук `beforeToolCall` для **любого** инструмента, включая MCP и
   плагины; у MCP нет собственного пути исполнения (§7 документа ядра; закрывает F5.1).
3. «Разрешить всегда» хранится по ключу (инструмент, шаблон аргументов), а не по виду инструмента (F5.3).
4. Запрос разрешения содержит аргументы вызова (`rawInput`), затронутые пути (`locations`) и diff
   для правок (F5.4).
5. Отказ в разрешении возвращается модели текстом, ход продолжается; `cancelled` — только по отмене.
6. `ToolOutcome` содержит `cancelled` и `rejected` как **доменные** значения. ACP-адаптер
   проецирует их в разрешённый спецификацией статус `failed` с `_meta.codelab.outcome`, поэтому
   статус `cancelled` в ACP невозможен по построению (F5.5). Расширение `_meta` вводится через
   OpenSpec (`AGENTS.md` §3.4).
7. Все файловые операции и команды проходят через `ExecutionEnv`, обёрнутый `BoundedEnv` (F5.2).
8. Хосты собирают ядро только через `buildAgentCore` (документ ядра §10): возможности не
   расходятся между `codelab-agent`, встроенным агентом app и CLI.

---

← [4. Целевая архитектура](04-target-architecture.md) · [Оглавление](../dart-agent-and-clients.md) · [6. Режимы работы и потоки](06-modes-and-flows.md) →
