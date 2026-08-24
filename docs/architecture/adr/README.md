# Architecture Decision Records

Этот каталог содержит Architecture Decision Records (ADR) проекта **ACP Client**.

ADR фиксируют значимые архитектурные решения, которые:

* влияют на структуру системы;
* меняют dependency boundaries;
* вводят или заменяют ключевые технологии;
* изменяют lifecycle, security или integration model;
* имеют долгосрочные последствия;
* требуют понимания причин принятого решения.

ADR не заменяют актуальную архитектурную документацию.

Актуальное состояние системы описывается в:

* `AGENTS.md`
* `docs/architecture/`

История значимых архитектурных решений хранится в:

`docs/architecture/adr/`

---

## 1. Назначение ADR

ADR отвечает на вопрос:

> Почему было принято это архитектурное решение?

Architecture documentation отвечает на вопрос:

> Как система устроена сейчас?

OpenSpec отвечает на вопрос:

> Как система должна вести себя?

Связь документов:

```text
OpenSpec
    │
    └── product behavior / contracts

Architecture docs
    │
    └── current system design

ADR
    │
    └── history and rationale of significant decisions
```

---

## 2. Когда нужен ADR

ADR СЛЕДУЕТ создавать при значимом изменении:

* package boundaries;
* dependency direction;
* state-management strategy;
* dependency injection strategy;
* UI framework/design system;
* ACP transport architecture;
* session lifecycle architecture;
* reconnect strategy;
* permission/security model;
* persistence technology;
* networking stack;
* error-handling model;
* platform integration strategy;
* testing strategy;
* крупной cross-cutting abstraction.

---

## 3. Когда ADR не нужен

ADR обычно НЕ требуется для:

* локального refactoring;
* переименования;
* небольшого bug fix;
* добавления отдельного Widget;
* implementation detail;
* patch/minor upgrade dependency без архитектурного влияния;
* мелкой оптимизации;
* изменения formatting/lints.

---

## 4. Нумерация

Файлы ADR должны иметь последовательную нумерацию.

Формат:

```text
0001-short-decision-name.md
0002-another-decision.md
```

Пример:

```text
docs/architecture/adr/
├── README.md
├── 0001-use-flutter-bloc.md
├── 0002-use-cherrypick-for-di.md
└── 0003-separate-acp-protocol-and-transports.md
```

---

## 5. Статус ADR

Каждый ADR должен иметь статус.

Допустимые значения:

* `Proposed`
* `Accepted`
* `Deprecated`
* `Superseded`

Если ADR заменён другим решением:

```text
Status: Superseded by ADR-0012
```

Старый ADR не удаляется.

---

## 6. Изменяемость ADR

После принятия ADR его rationale не следует переписывать так, будто новое решение существовало всегда.

Если решение существенно меняется:

1. Создать новый ADR.
2. Старый пометить как `Superseded`.
3. Обновить актуальную architecture documentation.

Небольшие исправления:

* typo;
* broken link;
* clarification, не меняющее смысл;

допустимы.

---

## 7. ADR и OpenSpec

Одно изменение может требовать одновременно ADR и OpenSpec change.

Например:

```text
"Добавить persistent permissions"

OpenSpec:
    определяет product behavior

ADR:
    фиксирует storage/security architecture

Architecture docs:
    описывают итоговую permission architecture
```

ADR не должен становиться product specification.

---

## 8. ADR и implementation

ADR может предшествовать implementation.

Типичный flow:

```text
problem
  ↓
ADR proposed
  ↓
decision accepted
  ↓
OpenSpec/design updated if needed
  ↓
implementation
  ↓
architecture docs updated
```

---

## 9. Краткость

ADR должен быть достаточно коротким.

Обычно достаточно:

* Context
* Decision
* Alternatives
* Consequences

Не следует превращать ADR в многодесятковый design document.

Подробный design можно хранить отдельно и ссылаться на него.

---

## 10. Template

Использовать следующий шаблон.

```md
# ADR-XXXX: <Название решения>

Status: Proposed

Date: YYYY-MM-DD

## Context

Какую архитектурную проблему нужно решить?

Почему существующая архитектура недостаточна?

Какие constraints существуют?

## Decision

Какое решение принято?

Какие boundaries или технологии затрагиваются?

## Alternatives

### Alternative A

Описание.

Почему не выбрана.

### Alternative B

Описание.

Почему не выбрана.

## Consequences

### Positive

- ...

### Negative

- ...

### Risks

- ...

## Migration

Если требуется:

- ...

## Related

- OpenSpec: ...
- Architecture: ...
- ADR: ...
```

---

## 11. Context

Раздел `Context` должен описывать проблему, а не заранее оправдывать выбранное решение.

Хорошо:

```text
ACP client core должен использоваться и Flutter-приложением,
и возможным CLI client. Текущий код зависит от Flutter.
```

Плохо:

```text
Нам нужен pure Dart package, потому что pure Dart лучше.
```

---

## 12. Decision

Decision должен быть конкретным.

Хорошо:

```text
Session lifecycle размещается в acp_client_core.
Flutter BLoC получает immutable session state через public API.
```

Плохо:

```text
Будем использовать clean architecture.
```

---

## 13. Alternatives

Следует перечислить реальные альтернативы, которые рассматривались.

Не нужно создавать искусственные alternatives только ради шаблона.

Пример:

```text
1. Session lifecycle внутри BLoC
2. Session lifecycle внутри acp_client_core
3. Отдельный session package
```

---

## 14. Consequences

ADR должен фиксировать не только преимущества, но и стоимость решения.

Например:

```text
Positive:
- pure Dart testing
- reusable session logic

Negative:
- дополнительный mapping в Flutter layer
- более строгий public API

Risk:
- acp_client_core может стать слишком большим
```

---

## 15. Migration

Migration обязателен, если решение требует:

* перемещения существующего кода;
* изменения public API;
* migration persisted data;
* удаления старой технологии;
* staged rollout.

---

## 16. Related links

ADR должен ссылаться на релевантные документы.

Например:

```text
Architecture:
docs/architecture/state-management.md

OpenSpec:
openspec/changes/session-reconnect/

Related ADR:
ADR-0004
```

---

## 17. Naming

Название ADR должно описывать решение.

Хорошо:

```text
Use flutter_bloc for presentation state
Use Cherrypick for dependency injection
Keep ACP client core pure Dart
```

Плохо:

```text
Architecture decision
Refactoring
New approach
```

---

## 18. ADR для dependency

Не каждая dependency требует ADR.

ADR нужен, если dependency:

* определяет архитектурный style;
* становится cross-cutting;
* заменяет существующий framework;
* создаёт долгосрочный lock-in;
* влияет на public API.

Например:

```text
flutter_bloc
Cherrypick
persistence database
```

обычно достойны ADR.

Небольшой utility package — обычно нет.

---

## 19. ADR для package boundaries

Новый package может требовать ADR, если он вводит новую долговременную boundary.

Например:

```text
split acp_client_core into:
- acp_session
- acp_permissions
```

Это архитектурное изменение.

---

## 20. ADR для state management

Следует создавать ADR при:

* выборе основного framework;
* переходе с одного framework на другой;
* введении второго подхода;
* существенном изменении ownership state.

---

## 21. ADR для security

Security-related ADR особенно важны для:

* persistent permissions;
* credential storage;
* trust model external agent;
* sandboxing;
* shell execution policy.

---

## 22. ADR для ACP

ADR может понадобиться для:

* выбора transport abstraction;
* multiple transport strategy;
* version compatibility architecture;
* session recovery model.

Wire behavior при этом должен оставаться в OpenSpec.

---

## 23. AI-agent workflow

AI-agent должен рассмотреть необходимость ADR, если задача:

* меняет архитектурную boundary;
* вводит новый framework;
* меняет cross-cutting policy;
* меняет dependency direction;
* создаёт новый core package.

Агент НЕ ДОЛЖЕН автоматически создавать ADR для каждого изменения.

---

## 24. Checklist перед ADR

Перед созданием ADR определить:

1. Решение действительно долгоживущее?
2. Есть несколько разумных alternatives?
3. Решение влияет на архитектуру?
4. Будет ли через полгода полезно знать, почему оно принято?
5. Можно ли описать проблему отдельно от решения?
6. Нужно ли одновременно OpenSpec change?
7. Какие architecture docs нужно обновить?

---

## 25. Checklist после принятия ADR

После `Accepted`:

1. Обновить architecture docs.
2. Обновить OpenSpec, если меняется behavior.
3. Создать implementation tasks.
4. Обновить dependency rules, если требуется.
5. Добавить migration plan.
6. Добавить/обновить tests.

---

## 26. Основной invariant

ADR хранит **историю причины решения**, но не является единственным местом, где описана текущая архитектура.

После принятия решения developer или AI-agent должен иметь возможность понять текущую архитектуру через:

`docs/architecture/`

без чтения всей истории ADR.
