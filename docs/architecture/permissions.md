# Permissions и security boundary

Этот документ определяет архитектуру permission flow для действий AI agent, которые требуют разрешения пользователя или дополнительной security policy.

Цели:

* не позволять UI самостоятельно определять безопасность операций;
* не позволять protocol/transport слою показывать dialogs;
* централизовать permission policy;
* корректно связывать решение пользователя с конкретным tool call;
* обеспечить deny-by-default для неизвестных опасных capabilities;
* сделать permission flow тестируемым вне Flutter UI.

Связанные документы:

* `AGENTS.md`
* `docs/architecture/acp-boundary.md`
* `docs/architecture/session-lifecycle.md`
* `docs/architecture/concurrency.md`
* `docs/architecture/state-management.md`
* `docs/architecture/observability.md`
* `docs/architecture/testing.md`

---

## 1. Основной принцип

Permission flow — это application/security concern.

Presentation отвечает за отображение запроса и получение решения пользователя.

Она НЕ отвечает за определение того, требует ли операция разрешения.

Основной flow:

```text
ACP tool/action request
        │
        ▼
ACP client/application
        │
        ▼
Permission policy
        │
        ├── allow
        │
        ├── deny
        │
        └── require user decision
                    │
                    ▼
             PermissionRequest
                    │
                    ▼
              Presentation
                    │
                    ▼
               User decision
                    │
                    ▼
              Application
                    │
                    ▼
               ACP response
```

---

## 2. Что считается permission-sensitive operation

К permission-sensitive operations могут относиться:

* filesystem write/delete;
* shell/process execution;
* network access;
* credential access;
* secure storage;
* clipboard;
* opening external applications;
* modifying system state;
* invoking native APIs;
* потенциально destructive tool calls.

Конкретный набор определяется ACP/OpenSpec и application security policy.

AI-agent НЕ ДОЛЖЕН придумывать новую classification самостоятельно.

### Исключение: ACP client-side `fs/*` и `terminal/*` методы

`fs/read_text_file`, `fs/write_text_file` и `terminal/create`/`terminal/output`/`terminal/wait_for_exit`/`terminal/kill`/`terminal/release` формально попадают в "filesystem write/delete" и "shell/process execution" из списка выше, но явно исключены из client-side approval-гейта (`AGENTS.md §10`).

Причина: сама спецификация ACP делает `session/request_permission` перед этими методами опциональным (`MAY`) решением агента, а не обязательным протокольным шагом клиента — ни `docs/acp/protocol/09-File System.md`, ни `docs/acp/protocol/10-Terminal.md` не связывают эти методы с permission. Введение собственного approval-гейта для них — расширение поведения сверх протокола, а не его требование.

Компенсирующий контроль вместо approval: `path`/`cwd` из этих запросов ограничены рабочей директорией активной сессии (working directory containment); выход за её пределы отклоняется как protocol/security error на уровне application, до выполнения операции.

Полное обоснование и рассмотренные альтернативы — `openspec/changes/add-acp-fs-client-support/design.md`, `openspec/changes/add-acp-terminal-client-support/design.md`.

---

## 3. Security policy owner

Permission policy должна иметь одного authoritative owner.

Предпочтительно:

```text
acp_client_core / application security layer
```

или отдельный reusable security component, если это оправдано архитектурой.

НЕ ДОЛЖНЫ быть authoritative owners:

* Widget;
* dialog;
* `acp_protocol`;
* `acp_transports`;
* platform plugin.

---

## 4. Presentation responsibility

Presentation может:

* показать capability;
* показать параметры действия;
* объяснить риск;
* показать allow/deny controls;
* получить решение;
* показать pending state.

Presentation НЕ ДОЛЖНА:

* определять, dangerous ли capability;
* silently auto-approve;
* изменять requested capability;
* подменять policy;
* применять решение к другому tool call.

---

## 5. Protocol responsibility

`acp_protocol` может описывать protocol representation permission request/response, если это часть ACP.

Он НЕ ДОЛЖЕН:

* вызывать UI;
* знать о dialogs;
* определять UX;
* хранить user preferences;
* принимать security decisions.

---

## 6. Transport responsibility

`acp_transports` только доставляет ACP data.

Transport НЕ ДОЛЖЕН:

* классифицировать tool call;
* показывать permission UI;
* разрешать или запрещать operations;
* изменять permission semantics.

---

## 7. Permission model

Permission request должен иметь достаточную identity.

Conceptual model:

```text
PermissionRequest
├── sessionId
├── requestId
├── toolCallId
├── capability
├── operation
├── argumentsSummary
├── risk
└── metadata
```

Конкретные поля должны соответствовать ACP/OpenSpec и существующей реализации.

---

## 8. Correlation

Permission decision должен однозначно относиться к конкретному request/tool call.

Нельзя хранить только:

```text
lastPermissionDecision = allow
```

Предпочтительно связывать решение с:

* session;
* request;
* tool call;
* operation generation, если требуется.

---

## 9. Decision model

Типовые decisions:

```text
allow
deny
```

Дополнительные варианты допустимы только если они определены продуктом или ACP.

Например:

```text
allowOnce
allowForSession
alwaysAllow
```

НЕ ДОЛЖНЫ появляться без явно определённой semantics и persistence policy.

---

## 10. Deny by default

Неизвестная потенциально опасная capability должна обрабатываться по принципу:

```text
unknown + security-sensitive → deny / require explicit decision
```

Нельзя автоматически разрешать неизвестное действие только потому, что client не знает его classification.

---

## 11. Safe by construction

Лучше проектировать capability model так, чтобы permission-sensitive behavior было явным.

Предпочтительно:

```text
Capability.fileRead
Capability.fileWrite
Capability.shellExecute
```

чем:

```text
String capabilityName
```

если protocol/application model позволяет typed representation.

---

## 12. Unknown capability

Unknown capability следует:

* сохранить как unknown;
* залогировать;
* не интерпретировать как известную;
* применить conservative security policy.

Нельзя делать:

```text
unknown → safe
```

---

## 13. Capability classification

Classification должна быть централизована.

Например:

```text
PermissionPolicy.evaluate(action)
```

а не размазана по:

* widgets;
* BLoC;
* transport;
* filesystem adapter.

---

## 14. Policy result

Удобная conceptual model:

```text
PermissionEvaluation
├── allowed
├── denied
└── requiresUserDecision
```

Она позволяет application layer решить следующий шаг без UI-specific logic.

---

## 15. Auto-allow

Auto-allow допустим только для явно безопасных или ранее одобренных operations, если это разрешено product policy.

Auto-allow НЕ ДОЛЖЕН быть default для неизвестных actions.

---

## 16. Auto-deny

Auto-deny допустим для:

* запрещённых capabilities;
* invalid request;
* unsupported security-sensitive operation;
* policy violation.

Presentation может получить user-visible reason.

---

## 17. User confirmation

Если требуется explicit user confirmation, application создаёт typed `PermissionRequest`.

UI показывает запрос и возвращает decision.

UI не должен изменять underlying request.

---

## 18. Information shown to user

Permission UI должен по возможности показывать достаточно context для осознанного решения.

Например:

* действие;
* target;
* path;
* command;
* host;
* scope;
* side effects.

Но не следует показывать secrets без необходимости.

---

## 19. Command execution

Для shell/process actions желательно показывать пользователю точную или безопасно нормализованную команду.

Не следует скрывать meaningful arguments.

При этом sensitive values должны маскироваться, если это необходимо.

---

## 20. Filesystem operations

Для filesystem action желательно показывать:

* operation type;
* path;
* recursive/destructive nature;
* overwrite behavior.

Например:

```text
Write file:
~/project/config.json
```

или:

```text
Delete directory recursively:
~/project/build/
```

---

## 21. Network operations

Для network action желательно показывать:

* destination host;
* protocol/port, если релевантно;
* operation type.

Политика должна различать local и external network только если это явно определено.

---

## 22. Credentials

Запрос доступа к credentials должен иметь повышенную security sensitivity.

Секретное значение НЕ ДОЛЖНО отображаться в permission dialog без необходимости.

---

## 23. Persistence permission

Если решение можно запоминать, persistence scope должен быть явным.

Возможные scopes:

```text
once
session
workspace
application
```

Не следует вводить `always allow` без ясной revoke strategy.

---

## 24. Stored permission

Persistent permission должен включать достаточно context.

Например:

```text
capability
scope
target pattern
origin/agent identity
expiry
```

если это предусмотрено продуктом.

Нельзя хранить один global:

```text
allowShell = true
```

если permission должна быть scoped.

---

## 25. Revocation

Любая persistent permission model должна иметь понятный revoke mechanism.

Без revoke path persistent allow следует считать архитектурно подозрительным.

---

## 26. Agent identity

Если приложение может подключаться к разным agents, permission scope не должен автоматически переноситься между ними.

Следует учитывать agent identity, если она существует в protocol/application model.

---

## 27. Workspace scope

Если permission связана с workspace/project, scope должен быть явно привязан к workspace identity.

Permission одного проекта не должна автоматически применяться к другому.

---

## 28. Path scope

Для filesystem permissions следует избегать overly broad scope.

Например, permission:

```text
write /tmp/a.txt
```

не должна автоматически означать:

```text
write anywhere
```

если продукт не определяет именно такое поведение.

---

## 29. Path normalization

Перед policy evaluation filesystem path следует нормализовать на infrastructure/application boundary.

Важно учитывать:

* relative paths;
* symlinks;
* `..`;
* platform separators;
* case sensitivity.

Security policy не должна сравнивать raw user-controlled strings наивным способом.

---

## 30. Symlinks

Если path-based permission имеет security значение, symlink resolution должен учитываться там, где это возможно и требуется.

Нельзя считать разрешённым путь только по textual prefix.

---

## 31. Shell arguments

Если command permission scoped по executable, arguments тоже могут иметь security значение.

Например:

```text
git status
```

и:

```text
git clean -fdx
```

не обязательно должны иметь одинаковый risk.

Classification должна соответствовать product policy.

---

## 32. Race: permission vs cancellation

Если user отменяет request, пока открыт permission dialog:

```text
waitingForPermission
      │
      ├── cancel
      └── user approves late
```

Late approval НЕ ДОЛЖЕН реанимировать cancelled request.

Application должен проверить актуальность tool call перед применением decision.

---

## 33. Race: permission vs reconnect

Если connection потеряна во время permission request, old decision может стать stale.

После reconnect решение следует применять только если:

* session ещё та же;
* request всё ещё active;
* tool call identity совпадает;
* protocol допускает продолжение.

---

## 34. Duplicate permission request

Duplicate/replayed tool call не должен показывать второй dialog, если это тот же logical request.

Нужна deduplication по stable identity.

---

## 35. Concurrent permission requests

Если protocol допускает несколько pending permission requests, architecture должна либо:

* явно поддерживать очередь/несколько dialogs;
* либо сериализовать их;
* либо запрещать concurrency на application level.

Это не должно происходить случайно.

---

## 36. Queue

Если используется очередь permission requests, она должна иметь:

* FIFO или иную явно определённую policy;
* owner;
* cancellation;
* stale filtering;
* cleanup on disconnect.

---

## 37. Modal UI

Использование modal dialog — presentation decision.

Permission architecture не должна зависеть от того, отображается ли request как:

* dialog;
* side panel;
* inline card;
* notification.

---

## 38. Permission state

Permission lifecycle может выглядеть так:

```text
requested
    │
    ▼
evaluating
    │
    ├── allowed
    ├── denied
    └── awaitingUser
              │
              ├── approved
              ├── rejected
              ├── cancelled
              └── stale
```

Конкретные states определяются implementation/OpenSpec.

---

## 39. Tool call lifecycle

Permission является частью tool call lifecycle, но не обязательно частью session state.

Например:

```text
ToolCallState.awaitingPermission
```

может существовать независимо от:

```text
SessionState.running
```

---

## 40. Presentation state

BLoC может хранить derived presentation state:

```text
showPermissionPrompt
permissionTitle
permissionDetails
```

Но authoritative policy result должен поступать из application layer.

---

## 41. BLoC role

BLoC может:

* получить `PermissionRequired`;
* показать presentation state;
* принять user decision;
* отправить typed decision application layer.

BLoC НЕ ДОЛЖЕН:

* классифицировать capability;
* самостоятельно изменять risk;
* обходить policy.

---

## 42. Auditability

Security-sensitive permission flow должен быть диагностируемым.

Следует логировать:

* capability;
* tool call id;
* session/request id;
* policy result;
* user decision;
* decision scope.

Не следует логировать sensitive payload целиком.

---

## 43. Audit log vs debug log

Если продукт требует security audit trail, это отдельный concept от обычного debug logging.

Audit log должен иметь:

* defined retention;
* integrity expectations;
* privacy policy;
* schema.

Не следует случайно считать обычный logger полноценным audit system.

---

## 44. Secrets в logs

НЕ ДОЛЖНЫ попадать в logs:

* API keys;
* auth tokens;
* passwords;
* private credentials;
* sensitive file contents.

Masking должен происходить до записи.

---

## 45. Permission errors

Следует различать:

```text
permission denied by policy
permission denied by user
permission request stale
permission UI unavailable
invalid permission request
```

UI может показывать их по-разному.

---

## 46. Fail closed

При внутренней ошибке permission subsystem безопасный default для dangerous action:

```text
deny
```

а не:

```text
allow because policy failed
```

---

## 47. UI failure

Если permission UI не удалось показать, dangerous operation не должна автоматически выполняться.

Fail closed.

---

## 48. Timeout

Если permission request имеет timeout, semantics должна быть явной.

Без explicit product rule timeout следует трактовать консервативно:

```text
timeout → deny/cancel
```

а не auto-approve.

---

## 49. App shutdown

Pending permission requests должны корректно завершаться при shutdown.

Нельзя оставлять dangling operation в agent.

Application должна:

* invalidate requests;
* при необходимости отправить deny/cancel;
* закрыть UI state.

---

## 50. Testing policy

Permission policy должна тестироваться pure Dart tests без Flutter.

Минимальные scenarios:

* safe action → allow;
* dangerous action → requires user;
* forbidden action → deny;
* unknown dangerous capability → deny;
* stale request decision ignored;
* wrong tool call id rejected;
* cancelled request cannot be approved;
* reconnect invalidates old request, если это policy.

---

## 51. Presentation tests

Widget/BLoC tests должны проверять:

* request отображается;
* approve отправляет правильный decision;
* deny отправляет правильный decision;
* pending state блокирует duplicate action;
* stale request закрывается;
* secrets маскируются.

Они не должны повторять classification policy.

---

## 52. Integration tests

Полезные end-to-end scenarios:

```text
tool request
    ↓
permission required
    ↓
user approve
    ↓
ACP response
    ↓
tool continues
```

и:

```text
tool request
    ↓
permission required
    ↓
user deny
    ↓
ACP deny response
```

---

## 53. Test fake

`acp_testing` может предоставлять:

* fake permission policy;
* permission request builder;
* fake tool call;
* decision recorder.

Production package не зависит от test helpers.

---

## 54. Нежелательные patterns

### Security decision в widget

```dart
if (tool.name == 'shell') {
  showDialog(...);
}
```

НЕ ДОЛЖНО быть authoritative permission logic.

---

### Auto-allow unknown

```dart
default:
  return PermissionDecision.allow;
```

опасный default.

---

### Global allow flag

```dart
bool allowTools = true;
```

без scope и classification.

---

### Dialog вызывает transport

```text
Dialog
   ↓
Transport.send(...)
```

нарушает application boundary.

---

### Approval без correlation

```text
approveCurrentTool()
```

если в системе могут быть несколько/stale tool calls.

---

## 55. Добавление новой capability

Перед добавлением permission-sensitive capability агент ОБЯЗАН определить:

1. Как она представлена в ACP.
2. Кто является application owner.
3. Какой у неё risk level.
4. Требуется ли user confirmation.
5. Можно ли её auto-allow.
6. Какой permission scope допустим.
7. Какие данные нужно показать пользователю.
8. Какие данные нельзя логировать.
9. Как обрабатывается cancellation.
10. Как обрабатывается reconnect.
11. Какие tests нужны.

---

## 56. Главные invariants

### PERM-001 — UI не определяет security policy

Presentation только отображает и собирает decision.

### PERM-002 — Dangerous unknown fails closed

Неизвестное опасное действие не auto-approved.

### PERM-003 — Decision correlated

Решение всегда связано с конкретным operation/tool call.

### PERM-004 — Stale approval не выполняет action

Late user decision не может реанимировать cancelled/stale request.

### PERM-005 — Protocol/transport не показывают dialogs

Security UI находится выше ACP boundary.

### PERM-006 — Persistent permission scoped

Запомненное разрешение не должно быть бесконтрольно глобальным.

### PERM-007 — Secrets не попадают в logs/UI без необходимости

Sensitive data маскируется.

---

## 57. Основная модель

Предпочтительный permission pipeline:

```text
incoming action
      │
      ▼
normalize
      │
      ▼
classify
      │
      ▼
evaluate policy
      │
      ├── allow ───────► continue
      │
      ├── deny ────────► reject
      │
      └── ask user
              │
              ▼
        PermissionRequest
              │
              ▼
          Presentation
              │
              ▼
         User decision
              │
              ▼
       validate correlation
              │
              ▼
          continue/reject
```

Если безопасность operation зависит от `if` внутри widget или от того, какой dialog сейчас открыт, permission architecture следует пересмотреть.
