> **Черновик, после 1.0.** Задачи уточняются при старте change; метки — по `CLAUDE.md`. Пары «тест → реализация», красный тест первым.

## 0. Разведка и документы

- [ ] 0.1 `[agent]` Разведка утилит (исключение (д), не дольше одного дня; D2) на macOS и Linux со службой `codelab-test`: экранирование в `security -i`, отсутствие эха команды, коды «не найдено», проба Secret Service без вывода значений.
- [ ] 0.2 `[agent]` Документы: §17.5.4 (таблица бэкендов ОС, `auto`), `01-layers-and-packages.md` §1.2 и `technology-stack.md` (`ffi`), `codelab_agent_io/AGENTS.md` §2.

## 1. Бэкенды на утилитах ОС и индекс (D2, D3)

- [ ] 1.1 `[agent]` Тесты `secret_store_backends_test.dart` на фейковом `SecretProcessRunner` (agent-secrets «Бэкенды хранилища ОС»): значение только в stdin, абсолютный `/usr/bin/security`, коды «не найдено», таймаут 10 с, перевод строки. Красный.
- [ ] 1.2 `[agent]` Тесты `secret_names_index_test.dart`. Красный.
- [ ] 1.3 `[agent]` `KeychainMacosSecretStore`, `SecretServiceSecretStore`, `SecretNamesIndex`. 1.1, 1.2 зелёные.

## 2. Сторож: `ffi` (D1)

- [ ] 2.1 `[agent]` Красные `pubspec_allowlist_test.dart` (`ioAllowlist` с `ffi`, ядро без) и `import_guard_test.dart` (FFI только в `lib/src/secrets/wincred/`).
- [ ] 2.2 `[agent]` `ioAllowlist` += `ffi`, правило в `rules.dart`. 2.1 зелёные, `melos run guard` зелёный.

## 3. `wincred` (D4)

- [ ] 3.1 `[agent]` Тесты `wincred_secret_store_test.dart` на фейковом `WinCredApi` и `win_cred_bindings_test.dart` (размер и смещения `CREDENTIALW`). Красные.
- [ ] 3.2 `[agent]` `WinCredApi`, `WincredSecretStore` (`Isolate.run`, 10 с), `FfiWinCredApi`; зависимость `ffi`. 3.1 зелёные.

## 4. Выбор и ручная проверка (D5, D6)

- [ ] 4.1 `[agent]` Тесты `open_secret_store_test.dart` (agent-secrets «Выбор хранилища ОС в auto»). Красный.
- [ ] 4.2 `[agent]` `openSecretStore` с хранилищами ОС; `keychain` без проблемы «not supported yet». 4.1 зелёный.
- [ ] 4.3 `[agent]` `os_keychain_test.dart` с тегом `os-keychain` (`skip` в `dart_test.yaml`); ручной прогон на macOS и Linux. Windows — по возможности, не входит в DoD (OQ6 change 8.9).
- [ ] 4.4 `[desktop]` Вложенный `AGENTS.md` `apps/codelab_desktop`: условие пересмотра при включении App Sandbox (D7).
- [ ] 4.5 `[agent]` Матрица: P-12 — «выполнено»; сверка документов; DoD.
