> **Черновик, после 1.0.** Не реализуется до архивации `add-agent-secret-store` и до решения о старте работ после выпуска 1.0. Создан при сужении задачи 8.9 (решение пользователя 2026-10-31), чтобы сохранить проработанные решения по хранилищам ОС.

## Why

В 1.0 агент хранит ключи провайдеров и токены MCP в переменных `CODELAB_SECRET_*` и в открытом файле `$CODELAB_HOME/secrets.yaml` (`0600`, только по явному `secrets.backend: file`) — change `add-agent-secret-store` (8.9). Цель P-12 («секреты по имени в хранилище ОС») закрыта частично. Этот change подключает хранилища ОС за тем же портом `SecretStore`: связку ключей macOS, Secret Service на Linux и Windows Credential Manager.

## What Changes

- Бэкенды `keychain-macos` (`/usr/bin/security`, значение только в stdin), `secret-service` (`secret-tool`), `wincred` (свои привязки `advapi32` через `dart:ffi` и `package:ffi` за портом `WinCredApi`).
- Индекс имён `$CODELAB_HOME/secret-names.json` (только имена) для macOS и Linux; на Windows — `CredEnumerateW`.
- `auto` выбирает хранилище ОС лениво, при первом обращении; иначе `env`. `auto` по-прежнему никогда не выбирает `file`. `keychain` перестаёт быть проблемой «not supported yet».
- `ffi` в allowlist `codelab_agent_io`; правило сторожа: `dart:ffi` и `package:ffi/` только в `lib/src/secrets/wincred/`.
- Ручной интеграционный тест настоящих хранилищ с тегом `os-keychain`, пропущенный по умолчанию.
- Условие пересмотра для desktop при включении macOS App Sandbox.

## Не входит

- изменения порта ядра `SecretStore`, резолвера, подкоманд `secret`, `SecretAdmin`, `config check` — они из change 8.9 и не меняются;
- мобильные и web-хранилища (D16 change 8.9);
- перенос секретов из `secrets.yaml` (OQ1 design.md);
- ACP не меняется.

## Capabilities

### Modified Capabilities
- `agent-secrets` (создаётся change 8.9): бэкенды хранилища ОС и выбор хранилища ОС в `auto`.

## Impact

- `codelab_agent_io`: `lib/src/secrets/` — `KeychainMacosSecretStore`, `SecretServiceSecretStore`, `WincredSecretStore`, `WinCredApi`, `SecretNamesIndex`; `lib/src/secrets/wincred/` — `FfiWinCredApi`; зависимость `ffi`; правка `openSecretStore`.
- `codelab_architecture_tests`: `ioAllowlist` += `ffi`; правило импорта FFI.
- Документы: §17.5.4, `01-layers-and-packages.md` §1.2, `technology-stack.md`, `codelab_agent_io/AGENTS.md`, `agent-parity-goals.md` (P-12 — «выполнено»).
