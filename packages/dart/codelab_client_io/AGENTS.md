# AGENTS.md — codelab_client_io

Правила этого пакета дополняют корневой `AGENTS.md`. Источник архитектуры — `docs/architecture/proposals/dart-agent-and-clients/09-10-stage-5-client-kit.md` (задача 5.8) и `design.md` OpenSpec change `extract-acp-client-kit` (D2, D8, D11); поведение — spec `acp-client-kit`, требование «IO-адаптеры клиента».

## 1. Назначение

`dart:io`-реализации портов клиентского слоя, общие для `apps/codelab_desktop` и `apps/codelab_cli` (этап 6):

* `IoTextFileIo` и `IoTerminalProcessRunner` — порты `fs/*` и `terminal/*` из `codelab_client_acp`;
* `WorkingDirectoryProvider` / `IoWorkingDirectoryProvider` — рабочая папка процесса клиента;
* `ioTransportResolver` — `ConfigTransportResolver` kit с фабриками `StdioAcpTransport` и `WebSocketAcpTransport`;
* `resolveCodelabHome` (`platform/codelab_home.dart`) — единственное правило `$CODELAB_HOME` для CLI и app (`~`, `~/…`, ошибка `CodelabHomeException`; design.md change `add-app-settings-shell`, D7);
* `IoProjectFiles` — порт `ProjectFiles` kit для панели Files: граница рабочей папки по realpath до перечисления и чтения, перечисление одного уровня (лимит 5000, `.git` скрыт), чтение не больше `maxBytes + 1` байт; правила (нормализация пути, двоичный/большой файл, сортировка) — чистые функции kit (change `add-file-preview-and-tree`, D3, D4);
* `JsonFileProfileStore` (`$CODELAB_HOME/profiles.json`, общий у CLI и app) и `JsonFileRecentProjectsStore` — порты хранилищ kit.

Реализации на Flutter-плагинах (`SharedPreferencesRecentProjectsStore`, `FileSelectorProjectFolderPicker`) остаются в app.

## 2. Границы

* `lib/**` НЕ ДОЛЖЕН импортировать `package:flutter/`; `dart:io` и `package:codelab_acp_transports/io.dart` разрешены (правило в `codelab_architecture_tests/test/support/rules.dart`).
* `dependencies` — только подмножество `{codelab_client_core, codelab_client_acp, codelab_acp_protocol, codelab_acp_transports, path, meta}` (`pubspec_allowlist_test.dart`). Расширение — через OpenSpec change.
* Политики здесь нет: правила очереди, проекции, недавних проектов и профилей — в kit; пакет только переносит их на файлы, процессы и сокеты.
* Секреты в файлы не пишутся: профиль хранит `tokenRef`, значение даёт `SecretSource` при открытии транспорта.
* Запись JSON-файлов (`stores/json_file.dart`) — во временный файл в том же каталоге с `flush: true` до `rename`: после сбоя питания остаётся целый старый или целый новый файл.
* Тестовые маркеры секретов не должны попадать в вывод тестов, в том числе в сообщения `expect`.
* Импортируют пакет только composition root и тесты.

## 3. Тесты

`fvm dart test packages/dart/codelab_client_io` — на Dart VM с настоящими файлами во временной папке, дочерними процессами `/bin/sh` и агентом из `codelab_acp_testing`, WebSocket-сервером на loopback.
