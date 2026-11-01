# AGENTS.md — codelab_desktop

Правила этого приложения дополняют корневой `AGENTS.md` для каталога `apps/codelab_desktop`.

Источники: `design.md` OpenSpec change `add-agent-secret-store` (D15 — встроенные профили этапа 7, D16 — почему не готовая библиотека); `09-12-stage-7-embedded.md`.

## Секреты

* Секреты (ключи провайдеров, токены) читаются и пишутся только через общие бэкенды `codelab_agent_io` — через `package:codelab_setup/io.dart` (`SecretAdmin`, `openSecretStore`; тот же файл реэкспортирует `DescribedSecretStore`, `SecretStoreUnavailableException` и `Logger`) и встроенный профиль `codelab_embedded` (этап 7, ещё не существует). Приложение не импортирует `package:codelab_agent_*` напрямую (корневой `AGENTS.md` §5).
* `flutter_secure_storage` и другие Flutter-плагины хранения секретов на desktop НЕ ИСПОЛЬЗУЮТСЯ: у приложения, CLI и автономного агента ОДНО хранилище (общий файловый бэкенд `$CODELAB_HOME/secrets.yaml` и переменные `CODELAB_SECRET_*`; после 1.0 — общие записи хранилища ОС, change `add-agent-os-secret-backends`), иначе записи разошлись бы (D15, D16).
* Значения секретов живут только в памяти и проходят через `SecretAdmin`; в виджетах, состоянии (Cubit/`SessionView`), логах и диагностике их быть НЕ ДОЛЖНО — только имя секрета и признак «задан».
* Условие macOS App Sandbox: сейчас `com.apple.security.app-sandbox = false` в `macos/Runner/*.entitlements`. Если песочницу включат, бэкенды файла и ОС потребуют пересмотра — это отдельный change, а не правка на месте.
