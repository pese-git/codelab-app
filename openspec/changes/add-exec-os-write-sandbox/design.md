## Context

### Угроза

Модель — недоверенный автор команд: её может вести prompt injection из файла, страницы или вывода инструмента. Правка `config.yaml`, навыка или промпта действует со следующего шага. Через неё можно ослабить разрешения или подменить инструкции (PERM-11; Q9, Q16, Q30 change `add-agent-skills`). Для `exec` защита сейчас — разбор строки команды (§7.6.1 `07-permissions.md`). Её известные пределы перечислены там же. Каждое ревью добавляло новые (proposal, «Why»). Разбор строки не видит, куда пишет программа, запущенная этой строкой.

### Эксперимент (macOS 27.0.1, arm64, 2026-11-13)

Профиль `(version 1)(allow default)(deny file-write* (subpath P))(deny file-write-create file-write-unlink (literal A))`, команды через `/bin/sh -c`:

| Попытка | Результат |
|---|---|
| `echo x > .codelab/config.yaml`, `>>` в новый файл, `touch`, `chmod`, `rm` | `Operation not permitted`, файл не изменён |
| `python3 -c "open('.codelab/config.yaml','w')"` | `PermissionError: [Errno 1]` |
| `mkdir -p .agents/skills/x` при отсутствующем `.agents` (литерал предка) | отказ |
| `mkdir .CODELAB` при отсутствующем защищаемом `.codelab` (APFS без учёта регистра) | отказ |
| `mv .codelab /tmp/x`, `cd .. && mv proj proj2` (литерал предка) | отказ |
| `ln .codelab/config.yaml ../other/hl` (жёсткая ссылка наружу) | отказ |
| запись через существующую symlink `../other/sl` → защищаемый файл | отказ |
| фоновый `( sleep; echo > … ) &` после выхода родителя | отказ: песочница наследуется |
| `touch .` (utimes корня-предка), запись вне защищаемых путей, `/tmp` | разрешено |
| путь в параметре `-D P0=…` с `"`, `)`, `(allow file-write*` в имени | отказ записи, профиль не сломан |
| параметр `-D P0=/tmp/x` (не канонический) | правило **не** срабатывает: нужен `/private/tmp/x` |
| `sandbox-exec` внутри `sandbox-exec` | `sandbox_apply: Operation not permitted`, код 71 |
| невалидный профиль, отсутствующий параметр | код 65, сообщение `sandbox-exec: …` в stderr |
| `sandbox-exec … /bin/sh -c 'echo $$'` | pid совпадает с pid запуска: `sandbox-exec` делает `exec` на месте |
| 10 запусков `sandbox-exec … /usr/bin/true` | ~110 мс, ~11 мс на запуск |
| `(deny appleevent-send)(deny lsopen)` + `osascript` | `osascript` отработал: делегирование не закрыто |

`man sandbox-exec` помечает команду `DEPRECATED`, но она есть в системе и работает. Ею пользуются и другие инструменты, например SwiftPM при сборке манифестов. Риск удаления — в «Risks / Trade-offs».

### Как устроено сейчас (сверено с `develop`, `8277295c`)

- `ExecTool.execute` (`tools/builtin/exec.dart`) зовёт `ctx.env.exec(command, ExecOptions(...))`. `ctx.env` — `BoundedEnv` поверх `LocalExecutionEnv`: встроенный агент, `ports.env == null` или `localEnv`. Либо поверх `ListingOverlayEnv`/`AcpClientExecutionEnv`: `serve`, терминал клиента.
- `LocalExecutionEnv.exec` запускает `Process.start(_shell, ['-c', command], includeParentEnvironment: false)`. Окружение — allowlist (ENV-6). Отмена — снимок дерева процессов (`process_tree.dart`).
- Политика (`policy.dart`) получает `AgentConfigPaths` сессии от рантайма: `_sessionConfigPaths(skillsLoad)` = поле хоста `.withSession(sessionRoots, skillDirs)`. На каждой проверке политика пересчитывает `AgentConfigScope.resolve`. Проектное правило `.codelab/{config*.yaml, cli.yaml, agents, skills, prompts, hooks}` и `.agents/skills` — предикат `isAgentConfigPath` относительно корня сессии.
- `autopilot` (`modes.dart`, `policy.dart`): критический шаблон и путь конфигурации дают `Denied` без вопроса — `critical command blocked in autopilot: <label>` и `Editing agent configuration requires a human: <path>`. Режим `exec` без критичности разрешает.
- Признак `SessionHostPorts.execOnHost` (D17 change `add-agent-skills`) — явное «env исполняет на машине агента». Он задаётся по виду env, а не по типу объекта, потому что обёртки скрывают тип.

## Goals / Non-Goals

**Goals**
- Процессы `exec` и все их потомки не могут создать, изменить, удалить, переименовать, связать ссылкой или сменить атрибуты файлов в защищаемых путях сессии. Каталоги-предки защищаемых путей они не могут создать, удалить или переименовать.
- Отказ механизма — fail closed: команда не выполняется. Отсутствие механизма — прежняя текстовая эвристика, видимая в журнале и в `config check`.
- Ядро остаётся чистым Dart без `Platform.is*` (PKG-1, `AGENTS.md` §11).

**Non-Goals**
- Сетевая изоляция, запрет чтения, ограничение записи вне путей конфигурации агента.
- Linux и Windows в этом change (D6).
- Терминал клиента ACP (D14).

## Decisions

### D1. Два рубежа: текстовая проверка остаётся первой

Предложение пользователя подтверждается. Текстовая проверка §7.6/§7.6.1 не меняется и идёт первой, ОС-слой — второй.

Почему не только ОС-слой:
1. **Вопрос человеку.** PERM-11 обещает вопрос в любом режиме с человеком и отказ без человека. ОС-слой может только запретить. Без текста команда сразу падала бы с `EPERM`, и человек не смог бы осознанно разрешить правку.
2. **Fallback.** На Linux, Windows и в терминале клиента ОС-слоя нет.
3. **Ранний понятный отказ.** Модель получает `Permission denied for exec: critical command: write to agent configuration`, а не `Operation not permitted` в середине сборки.
4. **Остальные шаблоны §7.6** (`rm -rf /`, `sudo`, `git push -f`) к ОС-слою не относятся.

Почему не ослаблять текст при активной песочнице: эвристика консервативна, её ложные срабатывания стоят вопроса. Перенос решения на ОС-слой превратил бы вопрос в молчаливый отказ `EPERM` (D11) и сделал бы поведение зависимым от платформы. Ослабление — отдельный change, если ложные срабатывания будут мешать.

Обратное верно: ОС-слой строже текстового (D2). Например, `echo x > .codelab/notes.txt` текст пропускает, а ОС-слой отклоняет. Расхождение допустимо только в эту сторону.

### D2. Что защищается

Множество `P` на один вызов `exec` строит `ExecWriteGuard` (D4):
1. `AgentConfigPaths.paths` сессии — то же значение, что у политики: поле хоста `agentConfigPaths` и пути сессии `withSession`. В нём: конфиги и `secrets.yaml` `$CODELAB_HOME`, файл `--config`, проектный конфиг корня запуска, `$CODELAB_HOME/{agents,prompts,skills,state}`, `~/.agents/skills`, абсолютные `skills.extra_roots`, корни навыков сессии по Q27/Q44. Каждый путь защищается **поддеревом**.
2. `<корень сессии>/.codelab` и `<корень сессии>/.agents/skills` — **целиком**, поддеревом, существуют они или нет. Это строже предиката `isAgentConfigPath`: тот совпадает с `config*.yaml`, `cli.yaml`, `agents`, `skills`, `prompts`, `hooks`. Маски `config*.yaml` в SBPL пришлось бы выражать регулярным выражением из пути, а это новая поверхность ошибок. Других файлов агент в проектном `.codelab` не держит (`profiles.json` клиента — в `~/.codelab`), а запись модели в `.codelab/**` — ровно то, что PERM-11 запрещает. Решение — вопрос Q5.
3. **Предки.** Каждый каталог-предок каждого пути из 1–2, кроме самих путей и включая `/`, защищается **литералом** только от создания и удаления (`file-write-create`, `file-write-unlink`). Это закрывает:
   - сборку поддерева снаружи с переносом на место: `mkdir x; echo > x/config.yaml; mv x .codelab`;
   - перенос или удаление проекта и `$CODELAB_HOME`: `mv ~/proj x`, затем новый `~/proj/.codelab` (R5-2 change `add-config-writer-and-reload`).

   Литерал не мешает создавать файлы внутри предка (`touch ./new`), менять его время (`touch .`) и права. Это проверено экспериментом.

`$CODELAB_HOME` целиком не защищается. Там журналы сессий и `profiles.json` клиента, и вложенный `codelab -p` из `exec` должен их писать. Защищены перечисленные пути внутри него и литерал самого каталога: его нельзя удалить или переименовать.

Канонизация — в реализации ОС-слоя (D5): каждый путь даёт лексическую и каноническую форму, как `AgentConfigScope.resolve`.

**Исключения навыков E1–E3 и `execOnHost`.** E1–E3 (Q24, Q25, Q29, Q47) действуют только в текстовом рубеже: они снимают *вопрос* о запуске скрипта навыка. ОС-слой их не знает. Скрипт навыка исполняется под той же защитой и не может писать ни в свой каталог, ни в другие корни. Так закрывается остаточный риск Q25 «скрипт навыка сам пишет в свой каталог» и совпадает с решением «корни навыков только для чтения» (D5 change `add-agent-skills`). Цена: навык, который пишет кэш или вывод в свой каталог, получает `EPERM`. Python молча пропускает запись `__pycache__`. `execOnHost` на ОС-слой не влияет: защиту даёт или не даёт сам env (D3), а `execOnHost` по-прежнему решает только вопрос `cwd` в корнях только для чтения.

### D3. Порт ядра

В `lib/src/env/execution_env.dart`:

```dart
/// Пути, запись в которые процесс команды не должен получить (D2).
final class ExecWriteProtection {
  ExecWriteProtection(Iterable<String> paths);   // абсолютные пути ядра (POSIX), поддеревом
  final List<String> paths;
}

// ExecOptions: + final ExecWriteProtection? writeProtection;  copyWith сохраняет поле
// ExecResult:  + final bool writeProtected;                    // по умолчанию false
// ExecErrorCode: + sandboxFailed                               // команда не запускалась

sealed class ExecSandboxStatus { const ExecSandboxStatus(); }
final class ExecSandboxActive extends ExecSandboxStatus { const ExecSandboxActive(this.mechanism); final String mechanism; }   // 'sandbox-exec'
final class ExecSandboxUnavailable extends ExecSandboxStatus { const ExecSandboxUnavailable(this.reason); final String reason; }

/// Опциональная возможность Shell (проверяется через `is`, как DirectoryListing).
abstract interface class ExecSandboxShell { ExecSandboxStatus get execSandbox; }
```

- Если `writeProtection` не `null`, env с `ExecSandboxActive` ОБЯЗАН применить защиту или вернуть `Err(sandboxFailed)`, не запуская команду. Тогда `ExecResult.writeProtected == true`. С `null` команда идёт без песочницы: так работает снятие по одобрению (D4) и режим `off`.
- `BoundedEnv` и `ListingOverlayEnv` **всегда** реализуют `ExecSandboxShell` и отдают статус внутреннего env (у `ListingOverlayEnv` — `primary`). Если внутренний env возможности не реализует, они отдают `ExecSandboxUnavailable('environment has no OS sandbox')`. Это не «выдуманная возможность» (ENV-4): обёртка честно сообщает статус и не обещает защиту. Удвоение восьми классов `_Bounded*` ради условной реализации не оправдано (§13). `_Bounded.exec` передаёт `writeProtection` дальше: `copyWith` сохраняет поле.
- `MemoryExecutionEnv` и `AcpClientExecutionEnv` возможность не реализуют.

**Альтернативы.**
- Признак хоста, как `execOnHost`, а не возможность env. Статус жил бы отдельно от объекта, который применяет защиту, и мог бы разойтись с ним молча (fail open). Возможность на самом env закрывает это по построению.
- Метод в `Shell`. Пришлось бы менять все реализации и фейки во всех пакетах ради одной возможности. Опциональный интерфейс — установленный паттерн (§14).
- Обёртка над строкой команды в ядре (`exec sandbox-exec … /bin/sh -c '…'`). Ядро знало бы о механизме ОС, а строку получил бы и терминал клиента.

### D4. `ExecWriteGuard` — сессионный построитель защиты

Новый `lib/src/permissions/exec_write_guard.dart`, один объект на сессию (и на субагента — он получает guard родителя, как хранилище решений). Создаёт рантайм при открытии сессии рядом с политикой.

```dart
final class ExecWriteGuard {
  ExecWriteGuard({required String root, required AgentConfigPaths? paths, required ExecSandboxMode mode});
  ExecSandboxMode get mode;                         // auto | required | off  (D8)
  void approve(String toolCallId);                  // политика: человек разрешил PERM-11-вызов exec
  ExecWriteProtection? protectionFor(String toolCallId);   // null при off или снятии; снятие одноразово
}
```

- `protectionFor` строит `P` по D2 на каждый вызов. Пути хоста и сессии берутся из того же `AgentConfigPaths`, что у политики. Сравнение и канонизация — в env (D5): ядро IO не делает.
- **Снятие одобрением.** Если человек ответил `allowOnce` на запрос с критической меткой `write to agent configuration` для `exec`, политика вызывает `guard.approve(ctx.toolCallId)`. Метка может стоять в списке через `; `. Ответ `allowAlways` у критических шаблонов не предлагается. Следующий `protectionFor(тот же id)` вернёт `null` и сотрёт отметку. Решение относится к одному `toolCallId` и повторно не действует (PERM-4). Иначе человек разрешал бы правку, а команда падала бы с `EPERM`, и вопрос PERM-11 потерял бы смысл. Другие критические метки (`unparsable command`, `recursive delete …`) и обычное одобрение `exec` защиту **не** снимают: человек не видел, что команда пишет в конфигурацию. Метка `write in unknown working directory` из `harden-exec-cwd-tracking` защиту тоже не снимает: этот change от неё не зависит, расширение — вопрос Q2. Альтернатива «никогда не снимать» — в Q2.
- **`autopilot`.** Политика не спрашивает и `approve` не вызывает, поэтому защита в `autopilot` не снимается никогда (D10).
- Без `Manager`/`Service`: значение режима, ссылка на пути и множество одобренных id.

Связь с `harden-exec-cwd-tracking`: guard читает только итоговую метку запроса и `toolCallId`. Типы лексера и обхода каталога он не использует. Кодовой зависимости нет.

### D5. macOS: `sandbox-exec` с постоянным профилем и параметрами

Новый `codelab_agent_io/lib/src/env/exec_sandbox.dart`:
- `sealed class OsWriteSandbox` — механизм, который строит argv запуска. Реализации: `MacSandboxExec` (D5) и `NoOsWriteSandbox(reason)`. Две реализации и место для третьей (Linux, Q1) оправдывают тип (§13).
- `Future<OsWriteSandbox> detectExecSandbox({ProcessRunner?, Directory? probeDir})` — единственное место с `Platform.isMacOS` (§11, `platform-integration.md` §5: проверки платформы допустимы в адаптере инфраструктуры).

**Профиль постоянный, пути — параметры.** Текст профиля — константа в коде: `(version 1)(allow default)`, затем правила `deny` со ссылками `(param "W0")…(param "Wn")` и `(param "A0")…(param "Am")`. Число параметров меняется, поэтому профиль собирается из фиксированных фрагментов по счётчику. Строки путей в текст профиля **не попадают**: они уходят в argv `-D W0=<путь>`. Эксперимент: путь с `"`, `)` и `(allow file-write*` не ломает профиль.

Это единственный способ без экранирования SBPL. Экранирование (`\"`, `\\`) — своя грамматика Scheme-строк, ошибка в ней даёт инъекцию правила `allow`. Путь с символом NUL до argv не дойдёт: такой вызов возвращает `sandboxFailed`, команда не запускается. Юнит-тесты генерации (задача 3.1) проверяют, что текст профиля не зависит от путей.

**Канонические формы.** Seatbelt сравнивает путь после разрешения ссылок: `/tmp/x` в правиле не срабатывает, нужен `/private/tmp/x`. Для каждого пути из `P` env кладёт лексическую форму и каноническую. Каноническая — `realpath` самого глубокого существующего предка плюс остаток, тем же алгоритмом, что `canonicalPath` в `agent_config_paths.dart` пакета `codelab_agent_io`. Пересчёт идёт на каждом вызове `exec`: каталог мог стать ссылкой после старта (§7.6.1). Предки (D2, п. 3) считаются от обеих форм. Дубликаты убираются, порядок стабилен — сортировка, ради тестов.

**Правила профиля:**

```scheme
(version 1)
(allow default)
(deny file-write* (subpath (param "W0")) … )
(deny file-write-create file-write-unlink (literal (param "A0")) … )
```

`file-write*` покрывает `write`, `create`, `unlink`, `rename` (источник и цель), `link`, `symlink`, `setattr`, `chmod`, `utimes`, `xattr`.

**Запуск.** `Process.start('/usr/bin/sandbox-exec', ['-p', profile, '-D', 'W0=…', …, _shell, '-c', command])`. Окружение, `cwd`, буфер, таймаут и отмена — как в §4.6. `sandbox-exec` делает `exec` на месте, поэтому pid корня — pid оболочки, и `terminateTree` не меняется.

**Проба.** `detectExecSandbox` один раз при сборке хоста:
1. проверяет, что `/usr/bin/sandbox-exec` существует;
2. во временном каталоге запускает `sandbox-exec -p <профиль> -D W0=<tmp>/p /bin/sh -c 'echo x > <tmp>/p/f'`;
3. ожидает ненулевой код и отсутствие файла, затем запуск с записью вне `W0` — код 0.

Проба функциональная, а не «команда есть»: агент, запущенный внутри чужой песочницы, получит `sandbox_apply: Operation not permitted` и статус `unavailable` с этой причиной.

**Отказ на вызове.** Проба прошла, а конкретный запуск не смог применить профиль: нет `sandbox-exec`, ошибка `Process.start`, путь с NUL. Результат — `Err(ExecError(sandboxFailed, message))`, команда не исполнялась. Код 65 или 71 *от уже запущенного* `sandbox-exec` неотличим от кода команды. Поэтому профиль проверяется заранее, а не по коду выхода: он постоянный и проверен пробой, а параметры — строки без синтаксиса. Остаточный случай: невалидный параметр после пробы, например пустая строка. Его env отсекает до запуска (`sandboxFailed`).

### D6. Linux: в этом change механизма нет

Рассмотрены варианты:
- **landlock** — модель разрешённого списка: процесс объявляет, куда *можно* писать. Выразить «везде, кроме `.codelab`» нельзя: разрешение `/` покрывает и `.codelab`. Перечислять соседей на каждом уровне — новые файлы рядом с корнем станут недоступны. Кроме того, `landlock_restrict_self` действует на вызывающий процесс. Из Dart `Process.start` нельзя вклиниться между `fork` и `exec`, а ограничить сам процесс агента недопустимо. Нужен вспомогательный бинарь. Отклонено.
- **FFI или вспомогательный бинарь на C/Rust** — новый язык сборки и дистрибуции в Dart-monorepo, подпись и доставка бинаря в три клиента. Против `technology-stack.md`. Отклонено для этого change.
- **bubblewrap** (`bwrap --bind / / --dev-bind /dev /dev --ro-bind P P … /bin/sh -c …`) — ближе всего:
  - mount-namespace делает существующие пути только для чтения;
  - rename и unlink точки монтирования дают `EBUSY`;
  - `link` через границу монтирования даёт `EXDEV`.

  Пределы:
  1. **несуществующий путь** не смонтировать. `<корень>/.codelab`, которого нет, `bwrap` создал бы как точку монтирования на настоящем диске (`/` смонтирован на запись), то есть мусор в проекте пользователя. Иначе путь остаётся незащищённым.
  2. **переименование предка** (`mv ~/proj x`) в namespace разрешено: ограничен только сам путь монтирования.
  3. `bwrap` нет по умолчанию в образах GitHub `ubuntu-latest`. Ubuntu 24.04 ограничивает непривилегированные user namespaces через AppArmor (`kernel.apparmor_restrict_unprivileged_userns`) — требует проверки на runner.

  Гарантии на Linux вышли бы слабее, чем на macOS, по двум классам из D2.

Решение: в этом change на Linux и Windows `detectExecSandbox` даёт `NoOsWriteSandbox('not implemented on <os>')`, статус `unavailable` и прежнюю текстовую эвристику. Linux с `bwrap` и частичными гарантиями — отдельный change после ответа пользователя (Q1). Точка расширения — новая реализация `OsWriteSandbox`, порт ядра не меняется.

### D7. Платформенная изоляция

- Ядро знает только `ExecSandboxStatus` и `ExecWriteProtection`. Слов `sandbox-exec`, `Platform` и `dart:io` в нём нет (PKG-1, `AGENTS.md` §11). Строка `mechanism` в статусе — непрозрачная метка для журнала.
- `Platform.isMacOS` встречается в одном месте — `detectExecSandbox` (`codelab_agent_io`, адаптер инфраструктуры). `LocalExecutionEnv` получает `OsWriteSandbox` конструктором: `LocalExecutionEnv(cwd:, sandbox:)`, по умолчанию `NoOsWriteSandbox('not configured')`.
- Composition root (`codelab_embedded/lib/src/io/local_opener.dart`, `scripted_opener.dart`, `apps/codelab_agent/lib/src/host/agent_host.dart`) вызывает `detectExecSandbox()` один раз и передаёт результат всем фабрикам `LocalExecutionEnv` процесса. `config_commands.dart` вызывает его для строки `config check` (D9).

### D8. Режим `permissions.exec_sandbox`

Значения:
- `auto` (по умолчанию) — защищать, если механизм есть, иначе только текст;
- `required` — без механизма политика отклоняет `exec`;
- `off` — ОС-слой выключен, остаётся только текст, как до change.

Правила ключа:
- раздел `permissions` → `restartRequired: true`;
- живой перезагрузкой ключ не меняется, как остальные `permissions.*` (R0-1);
- проектный слой только ужесточает: `off < auto < required`, ослабление отбрасывается с `config.project.untrusted_key`, как `permissions.mode`;
- дескриптор `SettingsRegistry` — `enum`, `scope: fileOnly` с причиной `exec sandbox is configured in the config file`.

Зачем `off`: вложенная песочница невозможна (эксперимент: код 71). Инструменты, которые сами зовут `sandbox-exec`, под защитой падают. Пример — SwiftPM: у него есть свой выход `--disable-sandbox`. Модель увидит ошибку и сможет повторить с флагом. Пользователю, которому это мешает, нужен выход без пересборки. `off` равен прежнему поведению, то есть не слабее состояния до change, а правит ключ только человек (PERM-11). Решение — Q3.

### D9. Без механизма: текстовая эвристика, видимая пользователю

- Fail closed здесь означает следующее: команда без ОС-защиты проходит **ту же** текстовую проверку, что сейчас. Ослабления нет. Механизм есть, но не сработал — команда не исполняется (D5, D11).
- **Журнал** (`structured-logging`, §16). При открытии сессии одно событие `exec.sandbox.status` с полями `session_id`, `mode`, `status` (`active`/`unavailable`/`off`), `mechanism` или `reason`. Уровень `info` для `active` и `off`, `warning` для `unavailable` при `auto` и `required`.

  На вызовах:
  - `exec.sandbox.lifted` (`info`, `tool_call_id`) — снятие одобрением;
  - `exec.sandbox.failed` (`error`, `tool_call_id`, `message`);
  - `permission.denied` с причиной для `required`.

  Пути не логируются в `info`, только их число: пути `HOME` — персональные данные. Список — на уровне `debug`.
- **`config check`** перед строкой `Default model:` или перед последней строкой печатает `Exec sandbox: active (sandbox-exec)`, `Exec sandbox: unavailable (<reason>)` или `Exec sandbox: off`. Если `required` и механизма нет — ещё `warning: permissions.exec_sandbox: required, but no OS sandbox is available: exec will be denied`. Код выхода от этого не меняется. Строка печатается и у невалидного конфига: статус от конфига не зависит, режим — значение по умолчанию.
- **ACP** ничего не получает (D18). Клиент видит статус через `config check` и журнал.
- **`required`.** Политика на шаге после явных запретов (шаги 1–2 §7.4) и до критических шаблонов проверяет: `tool.name == 'exec'`, `guard.mode == required` и `ctx.env` не `ExecSandboxShell` с `ExecSandboxActive`. Тогда `Denied('OS write protection is required but unavailable: <reason>')` без вопроса. Отказ до вопроса: иначе человек одобрил бы команду, которая не запустится.

### D10. `autopilot`

`autopilot` (CFG-4, только флаг headless) не меняется: критические шаблоны и PERM-11 отклоняются текстом без вопроса, остальной `exec` разрешён. ОС-слой в нём действует всегда и не снимается: человека нет, `approve` не вызывается (D4). Именно здесь второй рубеж ценнее всего: модель работает без присмотра, а текстовые обходы ничем не прикрыты.

`required` в `autopilot` автоматически не включается: на Linux и Windows `exec` в `autopilot` пропал бы целиком. Решение — Q4.

### D11. Ошибки и сообщения модели

- **Запрет записи** процесс видит как ошибку ОС `EPERM` («Operation not permitted»). Агент её не перехватывает: это данные команды (ненулевой код — `Ok(ExecResult)`, `agent-execution-env`). Если `writeProtected == true`, код ненулевой, а вывод содержит `Operation not permitted`, `ExecTool` добавляет заметку:
  `[Note: writes to agent configuration (.codelab, CODELAB_HOME, skill roots) are blocked by the OS sandbox. Do not retry; ask the user to make this change.]`
  Заметка эвристическая, ложное добавление безвредно.
- **`sandboxFailed`**: `Command was not run: OS write protection could not be applied (<message>).` Это ошибка инструмента (`isError`), не отмена хода.
- Тексты для модели — по-английски, inline в `exec.dart`, как остальные сообщения `_failure`. Описание инструмента `exec` не меняется, `prompts:check` не затрагивается.

### D12. Что запрещено и известные пределы

Запрещено в поддереве `P`: любая запись (`file-write*`) — создание, изменение, усечение, удаление, переименование (в обе стороны), создание жёсткой и символической ссылки, смена прав, времени и расширенных атрибутов. Жёсткая ссылка *на* защищаемый файл из незащищённого места тоже запрещена (эксперимент). На предках запрещены создание и удаление/переименование самого каталога. Чтение не ограничено.

Известные пределы ОС-слоя (macOS):
1. **Делегирование записи** процессу вне дерева: `osascript`/AppleEvents, `open`, `launchctl`, `docker run -v` (пишет демон), `ssh localhost`, `crontab`/`at`. `(deny appleevent-send)` и `(deny lsopen)` это не закрыли (эксперимент). Остаётся текстовая эвристика. Возможный шаг — отдельный change с `(deny mach-lookup …)` для служб `launchd`. Его цена для обычных команд не оценена.
2. **Жёсткая ссылка, созданная до сессии** вне защищаемого пути, ведёт на защищаемый inode. Запись по ней разрешена: правило сравнивает путь, а не inode. Тот же предел у E3 (`nlink`).
3. **Нормализация Unicode** (NFC/NFD) на APFS в правилах Seatbelt — требует проверки (задача 3.3). Регистр на нечувствительном к регистру томе Seatbelt учитывает (эксперимент).
4. **Фоновые процессы** сохраняют `P` на момент запуска. Новый корень навыков, добавленный позже, их не касается.
5. **Окно между построением `P` и запуском.** Предки защищены литералом только внутри песочницы. Другая команда без песочницы (снятие одобрением, `off`) может подменить предок ссылкой. Это окно — одна одобренная человеком команда.
6. **`sandbox-exec` помечен deprecated** («Risks / Trade-offs»).

### D13. Наследование и фоновые процессы

Seatbelt наследуется всеми потомками через `fork`/`exec`, включая `nohup … &`, пережившие `exec` (эксперимент). Отдельного фонового режима у `exec` нет: `ExecOptions` без него, а фоновые процессы — потомки оболочки. Отмена и таймаут убивают дерево как раньше. Набор `P` фонового процесса — на момент запуска (D12, п. 4). Процесс одобренной команды (D4) и его потомки идут без песочницы: это решение человека.

### D14. Терминал клиента ACP — вне scope

`AcpClientExecutionEnv` исполняет `exec` через `terminal/create` клиента (`codelab_client_io/terminal_process_runner.dart`). Его в change не включаем:
1. **ACP.** `terminal/create` не несёт защищаемых путей, а придумывать поле или `_meta`-расширение без OpenSpec нельзя (`AGENTS.md` §3.4). Пути — знание агента: его `CODELAB_HOME` и его навыки.
2. **Другая машина.** Клиент может быть на другой машине: для `--ws` — loopback, но в общем случае нет. Пути агента там ничего не значат.
3. **Внешние агенты.** Терминал клиента обслуживает и внешних агентов. Песочница по их путям — отдельная функция клиента со своей политикой (`AGENTS.md` §10: для `terminal/*` вместо одобрения — containment по `cwd`).

Такие сессии получают `ExecSandboxUnavailable('environment has no OS sandbox')`: `AcpClientExecutionEnv` возможности не реализует. Действует текстовая эвристика, а в `required` — отказ. Профиль по умолчанию в app и CLI — встроенный агент с `localEnv`, то есть с ОС-слоем на macOS.

### D15. Пересчёт защищаемых путей

- **На каждый вызов** `exec`. `protectionFor` строит `P` из текущего `AgentConfigPaths` сессии и её корня. Env канонизирует пути в момент запуска: ссылка, созданная после старта, учитывается.
- **Перезагрузка конфига.** Пути хоста строит `agentConfigPathsFor` при сборке. Текстовая политика их при живой перезагрузке не пересчитывает, ОС-слой — тоже: у обоих один источник. `skills.extra_roots` корня запуска после перезагрузки попадут под защиту обоих рубежей вместе — после перезапуска или в новой сессии через `sessionRoots` (Q44). Расхождения рубежей нет по построению.
- **Новые корни навыков и сессии в разных папках** (Q27, Q44, Q45). Каждая сессия получает свой guard со своим корнем и своим `withSession`: проектные `.codelab` и `.agents/skills` — по `cwd` сессии, корни уровней выше `cwd` — из фазы навыков этой сессии. Предел Q46 (а) сохраняется: без результата фазы навыков корни выше `cwd` не защищены ни одним рубежом. Корни хоста и `<cwd>/.codelab`, `<cwd>/.agents/skills` защищены всегда (D2, п. 2).
- **Несуществующие пути.** Seatbelt сравнивает путь операции, а не существующий inode. Поэтому `subpath` несуществующего `.codelab` запрещает его создание, создание файлов внутри и символическую ссылку с этим именем. Литерал предков запрещает собрать каталог снаружи и перенести его на место (эксперимент). Каноническая форма несуществующего пути — через самый глубокий существующий предок.

### D16. Тесты и CI

- **Юнит, ядро** (`codelab_agent_core/test/`, Dart VM, без процессов): `ExecOptions.copyWith`, проброс статуса и `writeProtection` в `BoundedEnv` и `ListingOverlayEnv`, `ExecWriteGuard` (состав `P`, одноразовое снятие, `off`), политика (`required`, `approve` только для метки PERM-11 и `allowOnce`, `autopilot`), `ExecTool` (заметка, `sandboxFailed`, события журнала) на фейковом env с `ExecSandboxShell`.
- **Юнит, io** (`codelab_agent_io/test/env/exec_sandbox_test.dart`, все ОС): текст профиля — константа, не зависящая от путей (сравнение с эталоном при путях с `"`, `)`, `\`, `;`, переводом строки, `(allow default)` и юникодом). Ещё: argv `-D Wi=…`/`Ai=…`, порядок и дедупликация, обе формы пути, предки до `/`, NUL → `sandboxFailed`, `NoOsWriteSandbox` не меняет argv. Канонизация — на временном каталоге со ссылкой (`/tmp` → `/private/tmp` проверяется только на macOS).
- **Интеграция, macOS** (`local_exec_sandbox_test.dart`, `@TestOn('mac-os')`; `skip` с причиной, если `detectExecSandbox()` не `MacSandboxExec`). Реальный `LocalExecutionEnv` и временный проект, сценарии таблицы эксперимента:
  - запись, `>>`, `python3 -c` при наличии python, иначе `skip` шага;
  - `mkdir` несуществующего `.codelab` и `.CODELAB`;
  - `mv` предка;
  - hardlink и symlink;
  - фоновый процесс;
  - чтение и запись вне `P` разрешены;
  - `writeProtected == true`;
  - `sandboxFailed` при подменённом пути к `sandbox-exec` — файл-маркер команды не создан;
  - проба внутри песочницы → `unavailable`;
  - отмена и таймаут убивают дерево под песочницей (ENV-5).
- **Linux и Windows**: тест `detectExecSandbox()` → `NoOsWriteSandbox` с причиной. Интеграционные тесты macOS там пропускаются аннотацией.
- **CI.** GitHub CI на pull request — только `ubuntu-latest` (`ci.yml`), macOS-джобов для PR в `develop` нет и не будет (`AGENTS.md` §21). Интеграционный тест песочницы там пропускается. Его прогон — локально на macOS: разработчик и проверка перед PR затронутого `codelab_agent_io`. Устройств и симуляторов нет: только Dart VM. Риск: регрессию механизма macOS CI не поймает (Q6).
- **Матрица `exec`** (`agent-permissions`): существующие тесты `critical_patterns_test.dart`, `config_exec_whitelist_test.dart` не меняются. ОС-слой их не трогает (D1).

### D17. Пакеты, зависимости, сторож, граф

- `codelab_agent_core` (`agent`/`core`, ADR-0002): порт, guard, политика, `ExecTool`, рантайм, схема конфига. Зависимости и PKG-2 не меняются, `dart:io` нет, web-безопасность сохраняется. Публичный барель экспортирует новые типы порта (`ExecWriteProtection`, `ExecSandboxStatus`, `ExecSandboxShell`, `ExecSandboxMode`): они нужны `codelab_agent_io`. `ExecWriteGuard` экспортируется, если его создаёт хост субагентов вне рантайма; иначе остаётся в `src`.
- `codelab_agent_io` (`agent`/`io`): `exec_sandbox.dart`, `LocalExecutionEnv`, `ConfigCommands`. Новых зависимостей нет: `Process` из `dart:io`.
- `codelab_embedded` (мост), `apps/codelab_agent`: composition root. Импорты между пакетами не меняются: `codelab_embedded` уже импортирует `codelab_agent_io` в `lib/io.dart`.
- Направление зависимостей прежнее: `io → core`, мост → `io`/`core`, app → мост.
- Новое правило сторожа не нужно. Новых пакетов и межпакетных импортов нет, `Platform.is*` в `codelab_agent_io` разрешён. Граф пакетов в `README.md` не меняется.

### D18. ACP

Ни методов, ни полей, ни состояний. `session/request_permission` для критической команды прежний: метка `write to agent configuration` в `_meta.codelab.label`. Ответ `allow_once` теперь ещё и снимает песочницу для этого вызова — это внутреннее поведение агента. Фикстуры ACP не меняются: в них нет `exec` под песочницей. Тексты ошибок `exec` в фикстурах — только в путях, которых change не касается (`required` по умолчанию выключен).

## Risks / Trade-offs

- **Deprecated `sandbox-exec`.** Apple может удалить команду. Тогда проба даст `unavailable` и агент откатится к тексту. В `required` `exec` будет отклонён — отказ безопасный, не тихий. Замена — App Sandbox, непригодный для произвольных команд, или Endpoint Security, требующий entitlement. Пересмотр — при первом сигнале удаления.
- **Ложные `EPERM`.** Команды, которые законно пишут в `.codelab/**` вне списка §7.6.1 или в каталог навыка (кэш навыка). Также инструменты с собственной песочницей (SwiftPM, код 71). Смягчение: заметка модели (D11), `off` (D8).
- **Стоимость.** ~11 мс на запуск плюс канонизация `P`: несколько `realpath` на путь, их число — десятки. Для `exec` (таймаут по умолчанию 120 с) несущественно.
- **Расхождение платформ.** На macOS защищено больше, чем на Linux и Windows. Это видно в `config check` и журнале. Поведение текстового рубежа одинаково везде.
- **Снятие одобрением (D4).** Одобренная команда целиком идёт без песочницы, включая её фоновых потомков. Это эквивалент сегодняшнего поведения для одобренной команды. Альтернатива — Q2.
- **Субагенты** делят guard родителя. Одобрение по `toolCallId` не переходит между вызовами.

## Migration Plan

Изменение аддитивно. По умолчанию `auto`: на macOS со встроенным агентом песочница включается сама. На Linux и Windows поведение прежнее. Откат — `permissions.exec_sandbox: off` в глобальном конфиге или откат кода. Данные и форматы не меняются.

Порядок: итерация 1 — порт ядра, guard, политика, ключ (задачи 1–2); итерация 2 — macOS в `codelab_agent_io` и composition root (задача 3). Итерации можно вливать отдельно: после первой статус везде `unavailable`, поведение прежнее.

## Open Questions

- **Q1. Linux.** Отложить (D6) или делать `bwrap` итерацией 3 с частичными гарантиями: не защищены несуществующие пути под широким предком и переименование предков, `bwrap` нужно ставить? **Рекомендация:** отложить в отдельный change. Сначала проверить на `ubuntu-latest` наличие `bwrap` и ограничение user namespaces AppArmor. Частичную защиту честно показывать статусом `partial`, а не `active`.
  **Решено пользователем (2026-11-13):** отдельный change. В этом change Linux остаётся без механизма (D6).
- **Q2. Снятие песочницы одобрением человека.** (а) Снимать для одного `toolCallId`, если одобрена критическая метка `write to agent configuration` (D4). (б) Не снимать никогда: правка конфигурации только через `write`/`edit`, а `exec` с этой меткой при активной песочнице — отказ с подсказкой без вопроса. **Рекомендация:** (а). Человек явно видел, что команда пишет в конфигурацию. Вариант (б) превращает ложные срабатывания консервативного текста в жёсткие отказы. Дополнительно: снимать ли и для `write in unknown working directory`, когда `harden-exec-cwd-tracking` будет влит? Рекомендация — нет: метка не говорит человеку, что пишется конфигурация.
  **Решено пользователем (2026-11-13):** (а). Песочница снимается для одного `toolCallId` и только при метке `write to agent configuration`. Для `write in unknown working directory` не снимается.
- **Q3. Ключ `permissions.exec_sandbox` и значение `off`.** **Рекомендация:** ключ с `auto` по умолчанию, `required` и `off`. `off` нужен для инструментов с вложенной песочницей (SwiftPM). Проектный слой `off` не включит: он только ужесточает. Альтернатива — без ключа, всегда `auto`: проще, но без выхода для SwiftPM и без `required`.
  Открыт: пользователь подтвердит при ревью PR change.
- **Q4. `autopilot` без механизма.** Форсировать `required` в `autopilot`? **Рекомендация:** нет. На Linux headless-прогоны потеряли бы `exec`. Пользователь, которому это нужно, ставит `required` в глобальном конфиге.
  **Решено пользователем (2026-11-13):** нет, в `autopilot` действует `auto`.
- **Q5. Проектный `.codelab` целиком (D2, п. 2) или только список §7.6.1.** **Рекомендация:** целиком. Правило проще и строже, расхождение с текстом — только в безопасную сторону.
  Открыт: пользователь подтвердит при ревью PR change.
- **Q6. Регрессии macOS в CI.** PR в `develop` проверяется только на Linux, интеграционный тест песочницы там пропускается. Добавить ли его в ночной прогон на macOS-runner (не PR, `AGENTS.md` §21 это не запрещает) или в приёмку `release/*`? **Рекомендация:** в приёмку `release/*` как Dart VM-тест (`melos run check` на macOS уже входит в неё). Ночной macOS-джоб — по решению пользователя.
  Открыт: пользователь подтвердит при ревью PR change.
