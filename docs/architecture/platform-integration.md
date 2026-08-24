# Platform integration в ACP Client

Этот документ определяет правила интеграции ACP Client с desktop-платформами и внешней операционной средой.

Цели:

* изолировать platform-specific APIs;
* не допускать распространения `dart:io` и platform plugins по feature-коду;
* сделать desktop integration тестируемой;
* сохранить portability между Windows, macOS и Linux;
* контролировать filesystem, process execution и secure storage;
* обеспечить единый lifecycle platform resources.

Связанные документы:

* `AGENTS.md`
* `docs/architecture/layers-and-dependencies.md`
* `docs/architecture/technology-stack.md`
* `docs/architecture/permissions.md`
* `docs/architecture/concurrency.md`
* `docs/architecture/testing.md`

---

## 1. Основной принцип

Platform-specific behavior является infrastructure concern.

Предпочтительная модель:

```text
Application / Feature
        │
        ▼
Platform abstraction
        ▲
        │
Desktop adapter
        │
        ▼
OS / Flutter plugin / dart:io
```

Feature-код не должен напрямую зависеть от конкретного platform plugin, если это не presentation-only concern.

---

## 2. Поддерживаемые платформы

Desktop application должна сохранять возможность работы на поддерживаемых платформах проекта:

* Windows;
* macOS;
* Linux.

Новая dependency или platform integration должна быть проверена на совместимость со всеми обязательными платформами проекта.

Если capability поддерживается не везде, это должно быть выражено явно.

---

## 3. Platform capability

Следует различать:

```text
application capability
```

и:

```text
platform implementation
```

Например:

```text
OpenFile
```

является application capability.

А:

```text
Windows file picker
macOS NSOpenPanel
Linux GTK picker
```

являются implementation details.

---

## 4. Platform abstraction

Platform abstraction должна быть узкой и semantic.

Предпочтительно:

```dart
abstract interface class FilePicker {
  Future<String?> pickFile();
}
```

вместо:

```dart
abstract interface class PlatformService {
  Future<dynamic> execute(String action, Map<String, dynamic> args);
}
```

Generic platform service скрывает responsibilities и ухудшает type safety.

---

## 5. `Platform.is*`

Проверки:

```dart
Platform.isWindows
Platform.isMacOS
Platform.isLinux
```

допустимы в:

* infrastructure adapters;
* bootstrap/composition;
* platform-specific utility layer.

Не следует использовать их непосредственно в:

* domain;
* reusable ACP core;
* BLoC;
* feature widgets;

если поведение можно скрыть за abstraction.

---

## 6. Conditional imports

Conditional imports допустимы, если implementation действительно отличается между platforms.

Например:

```text
platform_window.dart
platform_window_windows.dart
platform_window_macos.dart
platform_window_linux.dart
```

Это предпочтительнее большого количества runtime `if (Platform...)` в business/application code.

---

## 7. Flutter plugins

Flutter plugin следует считать infrastructure dependency, если он предоставляет доступ к:

* filesystem;
* native window API;
* secure storage;
* clipboard;
* notifications;
* process/system integration.

Plugin API не должен автоматически становиться public API application layer.

---

## 8. Plugin isolation

Предпочтительная схема:

```text
Feature
   │
   ▼
App abstraction
   ▲
   │
Plugin adapter
   │
   ▼
Flutter plugin
```

Это позволяет:

* тестировать feature без plugin;
* заменять plugin;
* изолировать platform differences;
* уменьшать coupling.

---

## 9. Filesystem

Filesystem является infrastructure concern.

Direct `File`, `Directory` и другие `dart:io` primitives следует использовать только в подходящем infrastructure layer.

Не следует использовать их напрямую из Widget или domain.

---

## 10. File access abstraction

Если application logic зависит от работы с файлами, следует использовать abstraction.

Например:

```dart
abstract interface class FileStore {
  Future<String> readText(String path);
  Future<void> writeText(String path, String content);
}
```

Конкретная API должна соответствовать реальной semantics задачи.

---

## 11. Path handling

Paths должны обрабатываться platform-aware способом.

Нельзя полагаться на:

* hardcoded `/`;
* Windows-only drive syntax;
* manually concatenated path strings.

Следует использовать approved path handling mechanism проекта.

---

## 12. Application directories

Для app data/config/cache следует использовать platform-appropriate directories.

Не следует хардкодить:

```text
C:\Users\...
/Users/...
/home/...
```

Application должна получать корректные directories через platform abstraction/plugin.

---

## 13. Temp files

Temporary files должны:

* иметь owner;
* удаляться после использования, если это возможно;
* не хранить secrets без необходимости;
* использовать OS-appropriate temp directory.

---

## 14. File write safety

Для critical data желательно использовать безопасную write strategy.

Например:

```text
write temp
   ↓
flush
   ↓
atomic replace
```

если это необходимо для защиты от partial writes.

---

## 15. Destructive operations

Удаление, overwrite и recursive filesystem operations могут быть security-sensitive.

Если action инициирована AI agent, она должна проходить permission policy.

Подробнее:

`docs/architecture/permissions.md`

---

## 16. Symlinks

Для security-sensitive file operations нужно учитывать symlinks.

Path:

```text
workspace/file
```

может фактически указывать вне workspace.

Permission/security layer не должна полагаться только на textual path prefix.

---

## 17. File watchers

Если используются filesystem watchers, каждый watcher должен иметь:

* owner;
* lifecycle;
* cleanup;
* error handling.

Watcher не должен переживать закрытие feature/workspace без явной причины.

---

## 18. External processes

Запуск external process является infrastructure concern.

Например:

```text
agent process
shell command
helper executable
```

должен иметь явного owner.

---

## 19. Process abstraction

Предпочтительно скрывать process API за abstraction, если он используется application logic.

Например:

```dart
abstract interface class ProcessRunner {
  Future<ProcessResult> run(...);
}
```

Для ACP transport может существовать специализированный process transport вместо generic runner.

---

## 20. Agent process ownership

Если AI agent запускается как child process, transport/infrastructure layer должен владеть:

* process start;
* stdin/stdout;
* stderr;
* exit code;
* termination;
* cleanup.

UI не должен напрямую управлять `Process`.

---

## 21. `stdout` и `stderr`

Если ACP работает через stdio:

```text
stdout
    → ACP transport

stderr
    → diagnostics
```

если это соответствует protocol contract.

Не следует смешивать diagnostics и protocol stream без explicit framing.

---

## 22. Process termination

Следует различать:

```text
graceful shutdown
terminate
force kill
```

Application lifecycle должен определять, когда используется каждый вариант.

---

## 23. Orphan processes

При закрытии приложения не должны оставаться orphan child processes, если это не intentional product behavior.

Shutdown flow должен включать cleanup process resources.

---

## 24. Process exit code

Exit code относится к infrastructure diagnostics.

Он может быть преобразован в application-level failure, например:

```text
agent process exited unexpectedly
```

UI не должен анализировать numeric exit codes напрямую.

---

## 25. Secure storage

Secrets должны храниться через secure storage abstraction.

К secrets относятся:

* auth tokens;
* API keys;
* credentials;
* private tokens.

Обычный local preferences storage не следует использовать для sensitive data.

---

## 26. Secure storage boundary

Application layer должен работать с semantic API.

Например:

```dart
abstract interface class CredentialStore {
  Future<String?> readToken();
  Future<void> saveToken(String token);
  Future<void> deleteToken();
}
```

а не напрямую с plugin-specific API.

---

## 27. Secrets lifecycle

Secrets должны:

* минимально долго находиться в memory;
* не логироваться;
* не попадать в exception messages;
* не сохраняться в debug dump без masking.

---

## 28. Clipboard

Clipboard является platform capability.

Если clipboard используется для обычного UI action, direct Flutter API может быть допустим на presentation boundary.

Если clipboard access инициируется AI agent или имеет security implications, следует применять permission/security policy.

---

## 29. Notifications

System notifications являются presentation/platform concern.

Application layer может выражать intent:

```text
NotifyUser
```

но concrete notification plugin должен оставаться platform adapter.

---

## 30. Window management

Window management может включать:

* minimize;
* maximize;
* restore;
* close;
* always-on-top;
* custom title bar.

Эти действия должны быть локализованы в app/platform layer.

Feature domain не должен зависеть от window API.

---

## 31. Close interception

Desktop app может перехватывать close для:

* unsaved data;
* active ACP session;
* running agent process.

Close flow должен быть application-controlled, а не случайным `dispose`.

---

## 32. Window state persistence

Если сохраняются:

* size;
* position;
* maximized state;

это presentation/platform persistence concern.

Такой state не должен смешиваться с ACP session state.

---

## 33. Multi-window

Если в будущем появится multi-window, window-scoped dependencies должны иметь корректный scope.

Нельзя заранее делать все services global singleton, если они потенциально должны быть window-scoped.

---

## 34. Open external URL

Открытие внешнего URL является platform action.

Если инициировано пользователем из UI — это presentation/platform concern.

Если инициировано agent — может требовать permission.

---

## 35. Deep links

Если application поддерживает deep links, parsing должен быть отделён от navigation.

Например:

```text
OS deep link
    ↓
parse/validate
    ↓
application intent
    ↓
navigation
```

---

## 36. Drag and drop

Drag-and-drop является presentation/platform interaction.

Dropped files следует преобразовывать в normalized application model/path before дальнейшей обработки.

---

## 37. Native dialogs

Native file dialog или system dialog — implementation detail.

Application layer должен получать typed result, а не зависеть от dialog API.

---

## 38. Platform errors

Platform-specific exceptions следует преобразовывать в typed infrastructure/application failures.

Например:

```text
PlatformException
    ↓
SecureStorageFailure
```

или:

```text
FileSystemException
    ↓
FileAccessFailure
```

UI не должен показывать raw `PlatformException.toString()`.

---

## 39. Unsupported platform capability

Если capability недоступна на конкретной platform, это должно быть explicit state/error.

Не следует делать silent no-op для критичной operation.

---

## 40. Feature detection

Предпочтительнее проверять capability:

```text
supportsTray
supportsSecureStorage
supportsWindowControl
```

чем напрямую в feature-коде проверять OS name.

---

## 41. Capability facade

Для сложных desktop integrations может быть полезен facade:

```dart
abstract interface class DesktopCapabilities {
  bool get supportsTray;
  bool get supportsNotifications;
}
```

Но не следует создавать giant facade для всех platform APIs.

---

## 42. Configuration

Platform-specific configuration должна быть локализована.

Например:

* entitlements;
* plist;
* manifest;
* desktop runner settings.

Такие изменения следует документировать рядом с соответствующей capability.

---

## 43. macOS permissions

macOS может требовать:

* entitlements;
* sandbox permissions;
* user prompts.

Application security policy не должна путать OS-level permission и ACP user permission.

Это разные layers.

---

## 44. Windows specifics

Windows-specific behavior может включать:

* process creation semantics;
* path case-insensitivity;
* executable extensions;
* registry;
* credential manager.

Такой код должен быть локализован.

---

## 45. Linux specifics

Linux desktop environment может отличаться по:

* notification backend;
* keyring;
* file dialogs;
* window manager behavior.

Не следует предполагать единый Linux desktop environment без необходимости.

---

## 46. Cross-platform invariant

Business/application behavior должно быть максимально одинаковым между platforms.

Platform differences должны влиять только там, где capability действительно отличается.

---

## 47. Platform branching в tests

Platform-specific code следует тестировать отдельно.

Pure application tests не должны зависеть от host OS CI runner.

---

## 48. Fake platform adapters

Для tests следует использовать fakes:

```text
FakeFileStore
FakeCredentialStore
FakeWindowController
FakeProcessRunner
```

Это позволяет тестировать application logic без real OS calls.

---

## 49. Integration tests

Real platform integrations следует проверять integration tests там, где это оправдано.

Особенно:

* file access;
* secure storage;
* process execution;
* desktop window APIs.

---

## 50. Permissions и platform APIs

Если platform action инициирована AI agent, architecture должна разделять:

```text
agent intent
    ↓
permission policy
    ↓
approved application operation
    ↓
platform adapter
```

Platform adapter НЕ ДОЛЖЕН сам решать, разрешено ли действие.

---

## 51. Shell execution

Shell execution — high-risk capability.

Если оно поддерживается, следует:

* централизовать execution;
* использовать permission policy;
* логировать metadata без secrets;
* ограничивать lifetime process;
* корректно обрабатывать cancellation.

Не следует выполнять shell command напрямую из BLoC/Widget.

---

## 52. Environment variables

Sensitive environment variables не должны попадать в logs.

При запуске child process следует передавать только необходимые environment values.

Не следует автоматически наследовать весь environment, если это создаёт security risk и продукт этого не требует.

---

## 53. Working directory

Process working directory должен быть explicit.

Не следует полагаться на current process directory как implicit workspace.

---

## 54. Executable resolution

Executable path следует разрешать предсказуемо.

Не следует blindly использовать `PATH` для security-sensitive process execution, если требуется более строгая policy.

---

## 55. External executable trust

Если application запускает external agent binary, следует определить:

* откуда он берётся;
* кто его выбрал;
* нужно ли проверять path;
* какова trust model.

Это security concern, а не только transport detail.

---

## 56. App resources

Bundled resources должны использовать Flutter-approved resource mechanism.

Не следует обращаться к source-tree relative paths в production.

---

## 57. Workspace files

Workspace/project files отличаются от application internal files.

Security policy должна различать:

```text
app config
app cache
workspace data
arbitrary filesystem
```

если product behavior это требует.

---

## 58. Backup и recovery

Если application пишет важные local data, следует определить:

* atomicity;
* backup strategy;
* corruption handling;
* migration.

Это относится к persistence architecture, если такая появится.

---

## 59. Platform adapter naming

Adapters следует называть по responsibility.

Хорошо:

```text
WindowsWindowController
SecureCredentialStore
StdioAgentTransport
```

Плохо:

```text
PlatformHelper
SystemManager
NativeUtils
```

---

## 60. Не создавать `PlatformService`

Generic `PlatformService` с десятками несвязанных методов обычно нарушает SRP.

Лучше несколько узких ports/adapters.

---

## 61. Dependency Injection

Concrete platform adapters создаются в composition root через Cherrypick.

Например:

```text
WindowController
    → FluentWindowController

CredentialStore
    → NativeCredentialStore
```

Application code зависит от abstraction.

---

## 62. Scope platform resources

Platform resources должны иметь подходящий lifecycle:

```text
application-scoped
workspace-scoped
session-scoped
window-scoped
operation-scoped
```

Не следует делать все platform adapters singleton по умолчанию.

---

## 63. Hot restart / debug

Development lifecycle Flutter может отличаться от production.

Не следует строить correctness на assumptions hot reload/hot restart.

Agent process и subscriptions должны корректно переживать dev lifecycle либо явно перезапускаться.

---

## 64. Observability

Platform integration должна логировать:

* operation type;
* success/failure;
* relevant correlation;
* platform capability unavailable.

Не логировать sensitive payload.

---

## 65. Performance

Platform I/O не должно блокировать rendering.

Большие filesystem scans, process output parsing и hashing должны быть вынесены из rendering-critical path.

---

## 66. Large filesystem operations

Для больших directory scans следует рассмотреть:

* streaming;
* batching;
* isolate;
* cancellation;
* progress.

Не загружать весь filesystem tree в memory без необходимости.

---

## 67. File encoding

Text file operations должны явно учитывать encoding, если это важно.

Не следует предполагать UTF-8 для arbitrary external file, если product semantics требуют другого.

---

## 68. Line endings

Windows/macOS/Linux могут иметь разные line ending conventions.

Не следует нормализовать line endings без product requirement.

---

## 69. Case sensitivity

Filesystem case sensitivity различается между platforms.

Path identity logic должна учитывать это, если она влияет на correctness/security.

---

## 70. Path comparison

Для security-sensitive path comparison нельзя использовать простое:

```dart
path.startsWith(root)
```

без normalization/canonicalization.

---

## 71. Network boundary

Если desktop integration включает network access вне ACP transport, оно должно быть отдельным infrastructure concern.

Не следует прятать network request внутри platform adapter, если это не platform-specific capability.

---

## 72. Native FFI

Если используется FFI, его следует изолировать в отдельном adapter/package.

Application code не должен напрямую работать с pointers/native lifecycle.

---

## 73. FFI lifecycle

Native resources должны иметь explicit cleanup.

Следует документировать ownership:

```text
allocate
use
dispose
```

---

## 74. Platform channel

Если используется custom platform channel, его API должен быть typed и узким.

Не следует делать generic channel:

```text
invokeMethod("doAnything", map)
```

если можно определить конкретный contract.

---

## 75. Error normalization

Platform layer должен нормализовать implementation-specific errors до понятных typed failures.

Это позволяет application layer оставаться cross-platform.

---

## 76. Checklist перед platform integration

Перед добавлением platform-specific functionality агент ОБЯЗАН определить:

1. Это presentation или infrastructure concern?
2. Нужна ли abstraction?
3. Поддерживается ли capability на всех target platforms?
4. Как выглядит unsupported behavior?
5. Нужна ли permission policy?
6. Кто владеет lifecycle resource?
7. Нужно ли cleanup/dispose?
8. Может ли operation пережить owner?
9. Какие secrets/data участвуют?
10. Какие tests нужны?
11. Требуется ли ADR?
12. Не протекает ли plugin API в application/domain?

---

## 77. Главные invariants

### PLATFORM-001 — Platform APIs изолированы

OS/plugin details не распространяются по application code.

### PLATFORM-002 — Pure Dart boundaries сохраняются

`acp_protocol`, `acp_client_core` и другие pure Dart packages не получают Flutter/platform dependency без архитектурного решения.

### PLATFORM-003 — Agent-triggered side effects проходят permission policy

Filesystem/process/network actions не обходят security boundary.

### PLATFORM-004 — Platform resources имеют owner

Process, watcher, subscription и native handle имеют lifecycle и cleanup.

### PLATFORM-005 — Unsupported capability явна

Silent no-op не используется для критичных operations.

### PLATFORM-006 — UI не владеет infrastructure

Widgets не создают process/filesystem/native adapters напрямую.

---

## 78. Основная модель

Предпочтительная архитектура:

```text
Feature / Application
        │
        ▼
Semantic Port
        ▲
        │
Platform Adapter
        │
        ▼
Flutter Plugin / dart:io / OS API
```

Если feature напрямую знает о конкретном desktop plugin, platform path rules и OS branching, boundary следует пересмотреть.

Дальше логично закрыть cross-cutting части: `observability.md`, затем `testing.md`.
