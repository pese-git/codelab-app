## Context

Как сейчас (проверено по коду ветки `develop` на 2026-11-22):

- Порт `RecentProjectsStore` (`load`, `record`), модель `RecentProject` (`path`, `lastOpenedAt`) и `recentProjectsLimit = 10` лежат в `codelab_client_core/lib/src/stores/stores.dart`. По doc-комментарию порта `load` не обязан отдавать список по порядку: сортирует вызывающий.
- App: `CodeLabPlatformModule.builder` (`apps/codelab_desktop/lib/app/app_scope.dart`) привязывает `const SharedPreferencesRecentProjectsStore()`. Шва в `createCodeLabRootScope` нет. Ключ `codelab.recent_projects` хранит JSON-массив `[{path, lastOpenedAt}]`. `load` при битом значении бросает то, что бросят `jsonDecode` и приведения типов.
- Пишет и читает список в app только `SettingsCubit` (`features/workbench/application/settings_cubit.dart`). `selectProject` вызывает `record` и затем `_loadRecentProjects`; оба шага в `try/catch`, ошибка уходит в диагностику предупреждением. «Reopen the last project» берёт проект из снимка `codelab.workspace.snapshot`, а не из недавних. Значит, недоступный список не мешает ни запуску, ни восстановлению.
- `JsonFileRecentProjectsStore` (`codelab_client_io/lib/src/stores/json_file_recent_projects_store.dart`) пишет `{"projects": [...]}` без версии. `record` устроен как «прочитать, изменить, записать». Запись идёт через `writeJsonObject`: уникальный временный файл, `flush`, `rename`. Нет файла — пустой список. Нет списка `projects` — `FormatException`. Элемент не того типа даёт `TypeError` (`project as Map`, `json['path']! as String`), а не `FormatException`. Приложения этот класс не создают.
- `JsonFileProfileStore` — образец: `{"version": 1, ...}`, незнакомая версия — `FormatException`, битый файл не перезаписывается (D4 и D7 change `add-app-settings-shell`). В app он привязан в `CodeLabConnectionModule` через `ConnectionEnvironment.profilesPath`. При недопустимом `CODELAB_HOME` привязан `UnavailableProfileStore`. Шов тестов — `createCodeLabRootScope(profileStore:)`: в `testWidgets` настоящий файл зависал бы в fake-async зоне.
- CLI: `CodelabHome` (`apps/codelab_cli/lib/src/home.dart`) знает `profiles.json` и `cli_history`. Интерактивные режимы — `_runRepl` и `_runTui` в `lib/src/run.dart`. Оба проверяют папку `_sessionFolder` (абсолютный нормализованный путь, папка обязана существовать), вызывают `home.ensureExists()` (каталог `0700`), затем мастер первого запуска `_firstRun`. Headless — `_runHeadless`: `-p`, `-f` и промпт из stdin, если stdin не терминал.
- Изоляция тестов. Интеграционные тесты app задают временный `CODELAB_HOME` (`integration_test/support/e2e_agent.dart`) и подменяют `SharedPreferences` пустым хранилищем (`flutter_test_config.dart`). PTY-помощник e2e CLI (`test/e2e/support/pty_process.dart`) запускает процесс без окружения родителя, но с настоящим `HOME`. `CODELAB_HOME` он задаёт, только если его передал тест.

Ограничения:
- `codelab_client_io` без политики: правила списка живут в kit (`codelab_client_io/AGENTS.md` §2).
- `codelab_client_core` web-безопасен и без `dart:io`.
- Клиенты не импортируют `package:codelab_agent_*`. Этот change агентскую сторону не трогает.
- Приоритеты `AGENTS.md` §2: целостность данных (3) выше удобства. Список недавних — данные пользователя, но малоценные и восстанавливаемые: проект снова попадает в список, когда его открывают.

## Goals / Non-Goals

**Goals:**
- Один файл недавних проектов на app и CLI в `$CODELAB_HOME`, независимый от идентификатора бандла.
- Перенос существующего списка app без потерь и без повторов.
- CLI пополняет список только тогда, когда человек работает в папке интерактивно. Скрипты, CI и тесты список не засоряют.
- Нечитаемый файл не ломает запуск и не перезаписывается молча.

**Non-Goals:**
- Показ и выбор недавних проектов в CLI — отдельный change.
- Межпроцессная блокировка.
- Нормализация путей и чистка несуществующих папок.
- Перенос остальных ключей `shared_preferences` (задача 9.4).

## Decisions

### D1. Хранилище — `JsonFileRecentProjectsStore` в `$CODELAB_HOME/recent_projects.json`, формат с версией

Оба клиента создают `JsonFileRecentProjectsStore(p.join(home, 'recent_projects.json'))`. `home` вычисляет общая функция `resolveCodelabHome`: в app через `ConnectionEnvironment.codelabHome`, в CLI через `CodelabHome.resolve`. Формат:

```json
{"version": 1, "projects": [{"path": "/work/app", "lastOpenedAt": "2026-11-22T10:00:00.000"}]}
```

Версия появляется сейчас, по образцу `profiles.json` (§14 «сначала существующие паттерны»). Файл без версии или с другой версией — `FormatException`. Совместимость со старым форматом `{"projects": [...]}` не нужна: этот файл никто не писал, класс до этого change нигде не создавался.

Альтернативы:
- (отклонена) Оставить `shared_preferences` в app и подключить файл только в CLI. Списки разошлись бы, а список app пропал бы при смене идентификатора бандла (задача 9.4).
- (отклонена) Выводить недавние проекты из подкаталогов `$CODELAB_HOME/sessions/` встроенного агента. Это работает только для встроенного агента, связывает клиент с форматом хранения агента (ADR-0002, клиенты не знают агентской стороны) и не учитывает папки, открытые без сессии.
- (отклонена) Файл в каталоге поддержки app (`path_provider`). Это тот же идентификатор бандла, и CLI его не видит.

### D2. Строгое чтение; нечитаемый файл не перезаписывается

`load`:
- нет файла — пустой список;
- не JSON, не объект, `version != 1`, нет списка `projects`, элемент не объект, `path` не непустая строка, `lastOpenedAt` не строка ISO-8601 — `FormatException` с путём файла. Это касается и случаев, где сейчас вылетает `TypeError`: хост ловит предсказуемый тип (`error-handling.md`; так же `JsonFileProfileStore` после ревью change `add-app-settings-shell`).

`record` и `merge` начинают с `load`. Если `load` бросил, запись не выполняется и ошибка уходит вызывающему. Нечитаемый файл остаётся на диске байт в байт. Инварианты записи совпадают с инвариантами чтения: `record` и `merge` с пустым `path` завершаются `ArgumentError` до чтения и записи, файл не меняется. Иначе хранилище записало бы файл, который само же отвергло бы при следующем `load`.

Почему не перезаписывать: файл незнакомой версии мог записать более новый клиент, и старый клиент затёр бы его. Битый файл мог поправить руками пользователь. Так же устроены `profiles.json` (D4 change `add-app-settings-shell`) и снимок рабочего места (`fix-restorer-read-race`: битый снимок не перезаписывается). Восстановление ручное: удалить файл. Путь называет текст `FormatException` в диагностике app и предупреждение CLI с `--verbose`. Ещё это описывает `docs/ops/codelab-home.md`.

Как деградируют клиенты (`platform-integration.md` §28: «recents недоступны в этой сессии», а не блокировка):
- app — уже реализованные ветки `SettingsCubit`: список пуст или прежний, в диагностике предупреждение `Failed to load recent projects: …` / `Failed to record recent project: …`. Работа с проектом не прерывается;
- CLI — D6.

Альтернативы:
- (отклонена) Самовосстановление: заменить нечитаемый файл новым списком. Это проще для пользователя, но затирает данные незнакомой версии. Приоритет 3 выше простоты.
- (отклонена) Переименовать битый файл в `recent_projects.json.bad` и начать заново. Тогда в `CODELAB_HOME` копятся файлы, и появляется второй путь записи, которого нет у `profiles.json`. Это несогласованно (§14).

### D3. Гонка «прочитать — изменить — записать»: в процессе — очередь, между процессами — допустимая потеря одной записи

**Внутри процесса** экземпляр `JsonFileRecentProjectsStore` выполняет `load`, `record` и `merge` по очереди: цепочка `Future`, следующая операция стартует после завершения предыдущей, ошибка одной не обрывает очередь. Без этого два `selectProject` подряд в app (оба `record` не дожидаются друг друга) могли бы прочитать один и тот же список, и одна запись пропала бы. Очередь стоит десяток строк, тестируется детерминированно и закрывает самый вероятный случай.

**Между процессами** (app и один или несколько `codelab`) запись по-прежнему «прочитать, изменить, переименовать». Если два процесса пишут в пределах одного окна между чтением и `rename` (миллисекунды), побеждает последний `rename`, а проект первого писателя в список не попадает. Оценка:
- файл не портится: `rename` атомарен, у каждого писателя свой временный файл (`writeBytesAtomically`);
- теряется не больше одной записи за столкновение, и она восстанавливается при следующем открытии этого проекта;
- окно возникает, только если человек открывает проект в app и почти в ту же миллисекунду запускает `codelab` в другой папке. Скрипты и CI список не пишут (D6), поэтому параллельные автоматические писатели исключены.

Это приемлемо для списка-подсказки и описано в `docs/ops/codelab-home.md`.

Альтернативы:
- (отклонена) Блокировка файла (`RandomAccessFile.lock(FileLock.exclusive)` на `recent_projects.json.lock`). Нужно ещё ожидание с таймаутом, обработка блокировки, брошенной упавшим процессом, и поведение на сетевых ФС, где advisory-блокировки ненадёжны. Ради списка из 10 подсказок это непропорционально (§13). Если появится вторая общая структура с частой записью из двух клиентов, блокировку стоит ввести одним механизмом для всех файлов `CODELAB_HOME`.
- (отклонена) Оптимистичная запись: перед `rename` перечитать файл и сравнить с прочитанным, при расхождении повторить. Проверка и `rename` не атомарны, окно только сужается. Сложность есть, гарантии нет.

### D4. Одноразовый перенос из `shared_preferences` в app

Перенос — обёртка `MigratingRecentProjectsStore implements RecentProjectsStore` в `apps/codelab_desktop/lib/core/platform/recent_projects_migration.dart`. Это единственное место, где app читает прежний ключ. Обёртка оправдана (§13): у переноса своя политика и свои тесты, а потребители (`SettingsCubit` и Cubit-ы рабочего места) остаются на порте и не меняются.

Алгоритм:
1. Первый вызов `load` или `record` запускает перенос и запоминает его `Future` (`_migration ??= _migrate()`). Все вызовы, в том числе параллельные, сначала ждут его. Пока перенос не закончен, в файл ничего не пишется. Это тот же приём, что в `fix-restorer-read-race`: запись только после чтения.
2. Ключа `codelab.recent_projects` нет или он пуст — переноса нет (повторный запуск — тоже сюда).
3. Значение ключа не разбирается: не JSON, не массив, элемент неверного вида. Ключ удаляется, событие `recent_projects.legacy_unreadable` уровня `warning` без значения и путей. Разобрать значение не сможет и следующий запуск. Если ключ оставить, предупреждение повторялось бы при каждом запуске, а данных он уже не даст. Запись с пустым `path` тоже делает значение ключа неразборчивым целиком: событие `recent_projects.legacy_unreadable`, ключ удаляется, остальные записи этого значения не переносятся. Это сознательное решение: перенос живёт только до первого `stable` (D9), и частичный перенос с пропуском отдельных записей не оправдывает дополнительной логики.
4. Значение разобрано — `target.merge(legacy)` (D5): слияние с тем, что уже лежит в файле (его мог создать новый `codelab` раньше первого запуска нового app), запись файла, затем удаление ключа. Событие `recent_projects.migrated` с числом перенесённых записей, без путей.
5. `merge` бросил: файл нечитаем (D2) или ошибка ФС. Ключ **не** удаляется, событие `recent_projects.migration_failed` с классом ошибки. Обёртка продолжает работу на `target`: `load` и `record` дальше ведут себя по D2, и ошибку увидит `SettingsCubit`. При следующем запуске перенос повторится.
6. Сбой самого `shared_preferences` (чтение или удаление ключа) — событие `recent_projects.migration_failed`. Перенос считается законченным для этого запуска, ошибка наружу не идёт. Если ключ не удалился после успешной записи, следующий запуск повторит слияние и получит тот же результат (п. 7).

Идемпотентность: условие переноса — наличие ключа, а не отсутствие файла. Слияние по пути с более поздним временем (D5) — идемпотентная операция. Сбой между записью файла и удалением ключа даёт при повторе тот же файл.

Конструктор и шов тестов:

```dart
MigratingRecentProjectsStore({
  required JsonFileRecentProjectsStore target,
  required Logger logger,
  Future<void> Function(String key)? legacyKeyRemover,
})
```

`legacyKeyRemover` — шов только для сценария «сбой удаления ключа» (п. 6). По умолчанию ключ удаляет `SharedPreferences`. Чтение ключа шва не имеет: тесты задают значение через `SharedPreferences.setMockInitialValues`. Для сбоя удаления без шва пришлось бы подменять платформенную реализацию из `shared_preferences_platform_interface`, а этот пакет не прямая зависимость app. Шов — одна функция, а не порт: перенос удаляется до первого `stable` (D9), и порт ради одного теста был бы лишней абстракцией (§13).

Записи не фильтруются, перенос переносит список как есть: временные папки smoke-прогонов, несуществующие папки — всё (решение пользователя Q1 (а), 2026-11-22).

Срок жизни переноса — только предвыпускные сборки: код переноса удаляется до первого `stable` 1.0 (решение пользователя Q2 (б), 2026-11-22; D9).

При недопустимом `CODELAB_HOME` обёртка не создаётся (D8), и ключ сохраняется до исправления окружения.

Альтернативы:
- (отклонена) Переносить, только если файла нет. Если пользователь сначала запустил новый `codelab` в папке, файл уже есть, и список app пропал бы молча.
- (отклонена) Оставить ключ после переноса (флаг-маркер `codelab.recent_projects_migrated` или чтение обоих хранилищ). Это лишний ключ или второй источник истины. Плюс один — откат на прежнюю сборку app сохранил бы список. Откат до выпуска 1.0 — сценарий разработчика, ради него держать два источника не стоит.
- (отклонена, Q2 (а)) Держать перенос в 1.0 и удалить через один выпуск после него. В 1.0 у app будет постоянный идентификатор бандла вместо `com.example.codelabApp` (задача 9.4), и `shared_preferences` 1.0 читает другой домен настроек: ключа `codelab.recent_projects` прежних сборок там нет. Перенос в 1.0 ничего бы не нашёл, это мёртвый код в первом `stable`.
- (отклонена) Перенос в `main` до `runApp`. Это задержка старта до первого кадра на файловом вводе-выводе. Ленивый перенос при первом обращении попадает в уже существующий асинхронный `_loadRecentProjects`.
- (отклонена) Переносить через `record` по одной записи. `record` ставит текущее время, и порядок перенесённых проектов перемешался бы с проектами CLI.

### D5. Правило слияния — чистая функция kit `mergeRecentProjects`

`codelab_client_core/lib/src/stores/stores.dart`:

```dart
List<RecentProject> mergeRecentProjects(
  Iterable<RecentProject> a,
  Iterable<RecentProject> b,
);
```

Правило: одна запись на путь (точное сравнение строк) с наибольшим `lastOpenedAt`, сортировка по `lastOpenedAt` по убыванию, при равенстве — порядок появления (сначала `a`), затем первые `recentProjectsLimit`. `JsonFileRecentProjectsStore.record(path)` — это `merge([RecentProject(path, clock())], current)`. Метод `JsonFileRecentProjectsStore.merge(Iterable<RecentProject>)` — это `merge(incoming, current)`, затем запись. Метод только у класса, в порт он не входит: он нужен одному переносу (D4), а порт остаётся узким (§13).

Почему в kit: `codelab_client_io` по своему `AGENTS.md` §2 политики не содержит. Правило «последний первым, не больше лимита» уже живёт в kit (`recentProjectsLimit`), и слияние — его часть. Функция без `dart:io`, `codelab_client_core` остаётся web-безопасным.

Время сравнивается как `DateTime`. Строки ISO-8601 без зоны из `shared_preferences` и из файла записаны одним и тем же `toIso8601String()` локального времени. Расхождение часовых поясов между записями одной машины несущественно для подсказки.

### D6. CLI пишет проект только в интерактивных режимах

`_runRepl` и `_runTui` после `_firstRun` (если мастер завершил процесс — записи нет) и до сборки рабочего пространства вызывают `_recordRecentProject(home, cwd, io, verbose:)`:
- `cwd` — уже проверенная `_sessionFolder` (абсолютный нормализованный путь существующей папки);
- `await JsonFileRecentProjectsStore(home.recentProjectsFile).record(cwd)` в `try/catch`. Ожидание — миллисекунды, без fire-and-forget, поэтому ошибка не теряется (§12);
- сбой (`FormatException`, `FileSystemException`) не меняет поведения и кода выхода. С `--verbose` в stderr идёт одна строка `codelab: cannot record a recent project: <тип ошибки>` — тип без текста, потому что текст `FormatException` содержит путь. Без `--verbose` вывода нет.

Не пишут: headless (`-p`, `-f`, промпт из stdin при stdin не TTY), `test-scenario`, `config`, `provider`, `mcp`, `secret`, `profiles`, алиас `serve`, а также `--version` и `--help`. `/new`, `/resume`, `/profile`, `/reconnect` папку не меняют и повторно не пишут. Запуск с `--resume <id>` или `--continue` — обычный интерактивный запуск в папке и записывает её (решение пользователя Q3, 2026-11-22).

Почему так:
- Headless — режим скриптов и CI: `codelab -p` в цикле по папкам заполнил бы список мусором. Человек, работающий в папке, запускает REPL или TUI.
- Запись до подключения, а не после успешного `session/new`, согласована с app: app пишет проект при выборе (`SettingsCubit.selectProject`), до запуска агента. Папка, где агент не поднялся, — всё равно папка, которую человек открывал. Запись после сессии потребовала бы протянуть хранилище в `Repl` и TUI-адаптер ради малого выигрыша.

Альтернативы:
- (отклонена) Писать во всех режимах, отключать флагом `--no-recent` или переменной `CODELAB_NO_RECENTS`. Это новый контракт CLI, который каждый скрипт должен помнить. Решение «только интерактивные режимы» даёт нужное по умолчанию.
- (отклонена) Писать и в headless, но только с TTY на stdout. Признак ненадёжен: `codelab -p` из терминала — тоже чаще разовый вызов, чем открытие проекта.
- (вне change) Показ списка в CLI (`/projects`, выбор папки при старте) — отдельный change, см. proposal «Не входит».

### D7. Изоляция тестов

- **CLI e2e.** `PtyProcess.start` (`test/e2e/support/pty_process.dart`) при отсутствии `CODELAB_HOME` в переданном окружении задаёт свой временный каталог (удаляется в `addTearDown`). REPL- и TUI-тесты без явного дома уже писали бы настоящий `~/.codelab/cli_history`, а теперь писали бы и `recent_projects.json`. Помощник закрывает оба. Аудит остальных точек запуска CLI в `test/` — задача 3.5: процессные запуски через `dual_binary.dart` и `e2e_agent.dart` и вызовы `runCodelab` в модульных тестах REPL и TUI.
- **App, тесты со scope без шва.** Тест app, который собирает scope через `createCodeLabRootScope` без `recentProjectsStore:` (и без `CodeLabTestBinding`), обязан передать `environment:` с временным `CODELAB_HOME`. Иначе привязка D8 открывает настоящий `~/.codelab/recent_projects.json` разработчика. Ревью итерации 4 нашло такой случай: `test/app/app_scope_embedded_test.dart` писал в настоящий файл Исправление: `app_scope_embedded_test.dart` получил шов `recentProjectsStore:` (двойник `FakeRecentProjectsStore`), а `apps/codelab_desktop/test/flutter_test_config.dart` стал стражем: он сверяет настоящий `$CODELAB_HOME/recent_projects.json` до и после каждого тестового файла и падает с подсказкой задать шов или временный `CODELAB_HOME`. Возможны ложные срабатывания, если во время прогона файл меняет другой процесс: параллельно запущенные `codelab` или app, а также параллельный прогон тестов `-j`, если какой-то тест всё-таки пишет в настоящий файл.
- **App, виджет-тесты.** `CodeLabTestBinding` (`test/support/test_app_scope.dart`) передаёт `recentProjectsStore:` — хранилище в памяти `FakeRecentProjectsStore` в `test/support/`, по образцу `InMemoryProfileStore`. Тесты, которые сейчас подкладывают `codelab.recent_projects` в `preferences` (`settings_cubit_startup_test.dart`), переходят на это хранилище с начальным списком.
- **App, интеграционные тесты** уже идут с временным `CODELAB_HOME`, и файл попадает туда. Комментарий `flutter_test_config.dart`, где подмена `SharedPreferences` объясняется недавними проектами, обновляется: ключа больше нет, причина подмены — снимок и прочие настройки.
- **Перенос** проверяется в обычном `test()` (не `testWidgets`): настоящий файл во временной папке и `SharedPreferences.setMockInitialValues`; сбой удаления ключа — через шов `legacyKeyRemover` (D4).
- **CLI, модульные тесты.** `runCodelab` не получает шва терминала, этот change его не вводит. Поэтому модульные тесты записи (`test/run_recent_projects_test.dart`) запускают REPL с `--resume <несуществующая сессия>` и с `--continue`: запуск интерактивный, папка записывается до подключения (D6), а REPL завершается без ввода с терминала. Обычный REPL без `--resume`, мастер первого запуска и `--ui tui` покрывает PTY-e2e `test/e2e/recent_projects_test.dart` (задача 3.6).

### D8. Привязка в app и шов тестов

`createCodeLabRootScope` получает параметр `RecentProjectsStore? recentProjectsStore`. Тот же приём, что `profileStore`: в `testWidgets` настоящий файл зависал бы. `CodeLabPlatformModule` получает `ConnectionEnvironment`, который уже собран в `createCodeLabRootScope` и передаётся модулям встроенного агента, onboarding и подключения, и привязывает:

```dart
bind<RecentProjectsStore>().toInstance(
  _recentProjectsStore ??
      switch (environment.codelabHome) {
        final home? => MigratingRecentProjectsStore(
          target: JsonFileRecentProjectsStore(p.join(home, 'recent_projects.json')),
          logger: …, // компонент `recent_projects`
        ),
        null => UnavailableRecentProjectsStore(
          environment.homeProblem ?? 'the home folder is not available',
        ),
      },
);
```

Привязка остаётся в модуле платформы, рядом с прежней, потому что потребители (`CodeLabShellParts`, `CodeLabShellCubit`) её уже там берут. В `CodeLabConnectionModule` не переносится: тот модуль — профили и токены. Путь к файлу строится в `app_scope.dart`. Поле `recentProjectsPath` в `ConnectionEnvironment` не добавляется: класс назван и описан как окружение подключения, а дом (`codelabHome`) в нём уже есть.

`UnavailableRecentProjectsStore` и исключение `RecentProjectsUnavailableException` лежат в том же файле, что обёртка переноса, — `apps/codelab_desktop/lib/core/platform/recent_projects_migration.dart`. Отдельного файла нет: оба — малые части одной привязки недавних проектов D8. `UnavailableRecentProjectsStore`: `load` и `record` завершаются ошибкой `RecentProjectsUnavailableException(reason)`, как `UnavailableProfileStore`. `SettingsCubit` выводит её в диагностику, список пуст. Ключ `shared_preferences` не трогается.

### D9. Судьба `SharedPreferencesRecentProjectsStore`

Класс удаляется вместе с тестом `shared_preferences_recent_projects_store_test.dart` и псевдонимом `kRecentProjectsLimit`. Из него остаются два метода чтения и удаления ключа `codelab.recent_projects`. Это закрытая часть `recent_projects_migration.dart` с doc-комментарием «удалить вместе с переносом». Отдельный порт для них не нужен: тест переноса работает с `SharedPreferences.setMockInitialValues`, так же как тест прежнего хранилища.

Реэкспорт `core/platform/recent_projects_store.dart` (`RecentProject`, `RecentProjectsStore`) остаётся, пока по нему импортирует тест `test/features/workbench/application/open_external_link_test.dart` (проверено 2026-11-22; `lib/` и остальные тесты импортируют `codelab_client_core`). Этот change реэкспорт не трогает (§19).

Перенос живёт только в предвыпускных сборках (решение пользователя Q2 (б), 2026-11-22). `MigratingRecentProjectsStore`, чтение и удаление ключа `codelab.recent_projects`, события `recent_projects.migrated`, `recent_projects.legacy_unreadable` и `recent_projects.migration_failed`, а также требование о переносе в spec `agent-workbench-ui` удаляет отдельный change `remove-recent-projects-migration` до первого `stable` 1.0. Условие записано в критериях выхода вехи M4 (`delivery-roadmap.md` §4.5) и в backlog §10.4. После удаления в `CodeLabPlatformModule` привязан сам `JsonFileRecentProjectsStore`.

Почему удаление сразу в 1.0 не теряет ничего сверх неизбежного: 1.0 выходит с постоянным идентификатором бандла (задача 9.4), и прежний домен настроек `com.example.codelabApp` 1.0 не читает ни для недавних проектов, ни для остальных ключей. Перенос в 1.0 не нашёл бы данных, а держать мёртвый код в первом `stable` незачем.

Spec `acp-client-kit` («IO-адаптеры клиента») перестаёт называть `SharedPreferencesRecentProjectsStore` среди реализаций на Flutter-плагинах.

### D10. Пакеты, зависимости, сторож, граф

| Пакет (ADR-0002) | Что меняется | Слой |
|---|---|---|
| `codelab_client_core` | `mergeRecentProjects`, doc-комментарий порта (файл общий, где лежит) | core, без IO |
| `codelab_client_io` | `JsonFileRecentProjectsStore`: версия, строгое чтение, очередь, `merge` | io |
| `apps/codelab_cli` | `CodelabHome.recentProjectsFile`, запись в `_runRepl`/`_runTui`, PTY-помощник | приложение |
| `apps/codelab_desktop` | привязка, шов, перенос, `UnavailableRecentProjectsStore`, удаление прежнего хранилища | `lib/app/`, `lib/core/platform/` |

Направление зависимостей прежнее: приложения → `codelab_client_io` → `codelab_client_core`. App уже зависит от `codelab_client_io` (`JsonFileProfileStore`, `IoProjectFiles`), CLI — тоже. Новых `dependencies` нет, allowlist сторожа не меняется. Новое правило в `codelab_architecture_tests/test/support/rules.dart` не нужно: импорты между пакетами прежние. Граф пакетов в `README.md` не меняется. ACP, агентская сторона и мосты (`codelab_setup`, `codelab_embedded`) не затрагиваются.

### D11. Наблюдаемость

События app (компонент `recent_projects`, категория `application`, логгер `StructuredLogLogger` как у остальных компонентов `app_scope.dart`):
- `recent_projects.migrated` (`info`): `count`;
- `recent_projects.legacy_unreadable` (`warning`): без полей;
- `recent_projects.migration_failed` (`warning`): `error_class`.

Пути проектов в события не попадают: это данные пользователя, тот же принцип, что у событий `terminal` и `skills_settings` («без путей»). Ошибки `load` и `record` после переноса по-прежнему идут в диагностику рабочего места через `SettingsCubit`, как сейчас. CLI событий не пишет: файла лога у него нет. Сбой виден с `--verbose` (D6).

### D12. Документация

- `docs/ops/codelab-home.md` — строка `recent_projects.json` в «Общие файлы»: кто пишет (app при выборе проекта, `codelab` в REPL и TUI), что нечитаемый файл не перезаписывается и как его сбросить, что одновременная запись может потерять одну запись.
- `apps/codelab_desktop/doc/operations.md` — убрать недавние проекты из списка ключей `shared_preferences` и из абзаца про `defaults delete`, добавить перенос при первом запуске. `doc/user-guide.md` — одна фраза: список «Projects» общий с `codelab`.
- `apps/codelab_cli/doc/operations.md` — файл в таблице «Файлы» и на диаграмме; `doc/user-guide.md` — когда CLI добавляет папку в список; `doc/development.md` — строка `home.dart`.
- `packages/dart/codelab_client_io/README.md` (строка про «приложения не используют») и `AGENTS.md` §1, `packages/dart/codelab_client_core/README.md` (таблица реализаций порта, `mergeRecentProjects`).
- `docs/architecture/platform-integration.md` §28 — пример локальных настроек: недавние проекты теперь файл в `CODELAB_HOME` (общий с CLI), а не `shared_preferences`. `technology-stack.md` (строки об изоляции `RecentProjectsStore` и о `codelab_client_io`). `proposals/dart-agent-and-clients/12-4-first-run-and-settings.md` (шаг 5 запуска, строка `stores` таблицы). `12-6-cli-desktop-extras.md` (пример ключа `codelab.recent_projects`). `delivery-roadmap.md` — заметка к задаче 9.4: недавние проекты от идентификатора бандла не зависят, остальные ключи — зависят.

## Risks / Trade-offs

- [Потеря одной записи при одновременной записи app и CLI] → допустимо (D3): файл цел, запись возвращается при следующем открытии; описано в `docs/ops/codelab-home.md`.
- [Нечитаемый файл блокирует пополнение списка до ручного удаления] → ошибка видна в диагностике app и с `--verbose` в CLI, путь назван, `docs/ops/codelab-home.md` описывает сброс. Альтернатива самовосстановления отклонена ради файлов будущих версий (D2).
- [Пользователь предвыпускной сборки обновился сразу на 1.0, не запустив сборку с переносом] → его прежний список не переносится и пропадает: в 1.0 переноса нет (D9), а прежний домен настроек 1.0 и так не читает. Оценка: приемлемо. До 1.0 app ставят только разработчики и тестировщики из исходников или предвыпускных сборок. Список недавних — подсказка из не более 10 путей, она восстанавливается при открытии проектов. Вместе с ним по той же причине (смена идентификатора бандла) пропадают и остальные настройки app в `shared_preferences`, поэтому отдельный механизм только для недавних непропорционален. Что сказать в документации: `apps/codelab_desktop/doc/operations.md` и раздел выпуска 1.0 в `CHANGELOG.md` — «при обновлении с предвыпускной сборки до 1.0 недавние проекты и настройки окна начинаются заново; проекты, открытые в `codelab`, остаются в списке — они в `CODELAB_HOME`» (задача 5.3; `CHANGELOG.md` — при подготовке `release/1.0`).
- [Откат app на прежнюю сборку после переноса] → список в прежней сборке пуст: ключ удалён. Файл и профили целы. При повторном обновлении перенос сольёт то, что прежняя сборка успела записать.
- [Конфликт дельты `acp-client-kit` «IO-адаптеры клиента» с активным change `add-file-preview-and-tree`] → оба change меняют одно требование: там добавлен `IoProjectFiles`, здесь изменены строка `JsonFileRecentProjectsStore` и фраза о Flutter-плагинах. Дельта этого change построена от текущей `openspec/specs`. Тот, кто архивирует change вторым, переносит в свою дельту правку первого. Сверка 2026-11-22 (задача 5.4): правки не пересекаются. Если `add-file-preview-and-tree` архивируется первым, в дельту этого change перед архивированием добавляются пункт `IoProjectFiles` и девять его сценариев.
- [Список виден другим локальным пользователям] → пути проектов — умеренно чувствительные данные. CLI создаёт `CODELAB_HOME` с правами `0700`. App создаёт каталог через `writeBytesAtomically` с правами по umask, так же как `profiles.json` сейчас. Этот change права не меняет. Если app создаёт дом первым, он может оказаться `0755`. Это уже известная особенность `profiles.json`.
- [Значения из файла показываются в сайдбаре] → файл в доме пользователя, доверие то же, что у `profiles.json` (где хранятся даже команды запуска агента). Новых путей выполнения нет: выбор недавнего проекта идёт тем же `SettingsCubit.selectProject`, что и выбор в системном диалоге, а агент работает в папке под прежними правилами containment (`AGENTS.md` §10).
- [Пути не нормализуются] → `/tmp/x` из CLI и `/private/tmp/x` из диалога macOS — две записи. Это не новое поведение (сейчас так же внутри app). Нормализация — вне change.

## Migration Plan

1. Выпуск с этим change: при первом обращении к списку app переносит ключ в файл (D4). Отдельных действий пользователя не нужно.
2. Откат: прежняя сборка app видит пустой список. Файл остаётся, и следующая новая сборка сольёт прежнюю запись при её появлении.
3. Удаление кода переноса — change `remove-recent-projects-migration` до первого `stable` 1.0 (Q2 (б), D9); условие — в критериях выхода M4 (`delivery-roadmap.md` §4.5) и в backlog §10.4.

## Решения пользователя 2026-11-22

Change одобрен пользователем 2026-11-22. Вопросы закрыты так:

- **Q1 — (а).** Перенос переносит список как есть, без фильтрации временных и несуществующих папок (D4). Засорение дальше не растёт благодаря D6 и D7; сбросить список можно удалением `recent_projects.json`.
- **Q2 — (б).** Код переноса удаляется сразу в 1.0: перенос живёт только в предвыпускных сборках и не попадает в первый `stable` (D4, D9, риск «Пользователь предвыпускной сборки…»). Будущий change — `remove-recent-projects-migration`; условие записано в `delivery-roadmap.md` §4.5 (критерии выхода M4) и §10.4.
- **Q3 — да.** `--resume` и `--continue` в REPL и TUI записывают папку как обычный запуск (D6).

Открытых вопросов нет.
