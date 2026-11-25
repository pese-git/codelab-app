## ADDED Requirements

### Requirement: Допуск папки журнала при загрузке
`AgentRuntime.loadSession` SHALL принимать необязательный параметр `admitJournalCwd` — асинхронную функцию `Future<bool> Function(String journalCwd)` (design.md change `add-agent-remote-exec`, D2). Если параметр задан, рантайм SHALL вызывать его с `cwd` из заголовка журнала сразу после открытия журнала, до сборки конфигурации сессии, выбора модели, подключения MCP-серверов и создания `AgentSession`.

Ответ `false` SHALL завершать вызов типизированным исключением `SessionCwdNotAdmitted` с id сессии. Тогда сессия не открывается, в журнал не дописываются записи загрузки, модель не вызывается. Без параметра поведение прежнее. Функцию передаёт ACP-сервер при заданных корнях рабочих папок (agent-acp-server «Корни рабочих папок сервера»). Ядро о корнях не знает.

#### Scenario: Журнал чужой папки не открывается
- **WHEN** журнал сессии `s1` создан с `cwd: "/old"`, а `loadSession(s1, ports, cwd: "/w/proj", admitJournalCwd: (c) async => c.startsWith("/w"))` вызывается
- **THEN** вызов завершается `SessionCwdNotAdmitted`, функция вызвана ровно один раз с `/old`, `AgentSession` не создан, MCP-серверы не подключались, функция модели не вызывалась

#### Scenario: Без параметра
- **WHEN** тот же журнал загружается без `admitJournalCwd` и с `cwd: "/w/proj"`
- **THEN** сессия открывается, как раньше, с `cwd` запроса и записью `codelab.cwd_changed`
