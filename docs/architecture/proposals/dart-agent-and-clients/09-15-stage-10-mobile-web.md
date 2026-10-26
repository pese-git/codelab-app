# 9.15. Этап 10 — Мобильные и web

> Часть предложения [«Dart-агент и клиенты CodeLab»](../dart-agent-and-clients.md). Status: Accepted. Исходные решения, связанные документы и порядок чтения — в оглавлении.

← [9.14. Этап 9 — Цели Must и переключение по умолчанию](09-14-stage-9-switch-default.md) · [Оглавление](../dart-agent-and-clients.md) · [10. Риски](10-risks.md) →

**Цель.** codelab-app со встроенным агентом работает на iOS, Android и в браузере — без shell и
без stdio-MCP.

**Задачи.**

1. **10.1. Пакет `packages/dart/codelab_agent_web`:** `PersistentWebEnv` (файлы в IndexedDB через
   `package:web` и `dart:js_interop`, снимки рабочей папки) и `IndexedDbSessionStore`. Отдельный
   пакет, потому что ядру `package:web` запрещён, а `codelab_agent_io` — только `dart:io`.
2. **10.2. Профили `mobile` и `web`** в `buildAgentCore`: `shellExec` выключен («нет shell на
   платформе»), MCP только по HTTP, хранилище сессий — папка документов приложения или IndexedDB.
3. **10.3. Composition root app по платформам:** `apps/codelab_desktop/lib/app/platform_services.dart`
   с условным импортом (`if (dart.library.io)` / `if (dart.library.js_interop)`); на web и
   мобильных нет stdio-профилей, клиент не объявляет `terminal`, `codelab_client_io` не подключается.
4. **10.4. Мобильные:** рабочая папка — каталог документов приложения (`path_provider` уже в
   зависимостях); `LocalExecutionEnv` с выключенным `exec` — `mobileHostServices` из
   `codelab_embedded/lib/io.dart` (§9.12).
5. **10.5. Web:** только встроенный режим. Подключение к внешнему агенту по WebSocket из браузера
   откладывается: браузер не даёт задать заголовок авторизации, а токен в URL запрещён правилами
   приватности; способ передачи токена — отдельный OpenSpec change.
6. **10.6. Сборки:** `fvm flutter build web`, `fvm flutter build ios --simulator`,
   `fvm flutter build apk --debug` для `apps/codelab_desktop`; web-сборка — в CI-джобе `web-compile`.
7. **10.7. Тест** `apps/codelab_desktop/integration_test/embedded_no_shell_flow_test.dart`: промпт →
   чтение и запись файла в рабочей папке → в списке инструментов модели нет `exec` (HOST-4
   документа ядра).

**OpenSpec change.** `add-mobile-and-web-hosts` — scope: профили `mobile` и `web`,
`codelab_agent_web`, ограничения подключения в web.

**Что прочитать.** Документ ядра §4 (реализации env), §10 (матрица профилей), §16;
`docs/architecture/platform-integration.md`; экраны смартфона и планшета, раскладка по ширине и
открытые вопросы UI — [§12.8](12-8-phone-and-tablet.md).

**Definition of Done.**

* `fvm flutter build web` для app проходит в CI.
* `embedded_no_shell_flow_test.dart` зелёный на iOS-симуляторе (`fvm flutter test integration_test/embedded_no_shell_flow_test.dart -d "iPhone 16"`) и Android-эмуляторе.
* `melos run guard`: `codelab_agent_web` не импортирует `dart:io`; основной барель
  `codelab_embedded` собирается `dart compile js`.

**Зависимости.** Этап 9 (стабильное ядро); технически возможен после этапа 7.

**Риски.** Ограничения IndexedDB по объёму — предел размера рабочей папки и понятная ошибка.
Ограничения магазинов приложений на исполнение кода — shell выключен по построению профиля.

---

← [9.14. Этап 9 — Цели Must и переключение по умолчанию](09-14-stage-9-switch-default.md) · [Оглавление](../dart-agent-and-clients.md) · [10. Риски](10-risks.md) →
