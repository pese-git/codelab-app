# Папка, модель, режим и агент

Глава объясняет, как выбрать папку проекта, модель и режим сессии, а также как работать с агентом не по умолчанию: программой, которую запускает `codelab`, агентом по сети или сохранённым профилем. Оглавление руководства — [руководство пользователя](../user-guide.md).

## Выбрать папку, модель и режим

| Флаг | Что делает |
|---|---|
| `-C <папка>` (`--cwd`) | папка сессии; по умолчанию текущая. Несуществующая папка — ошибка и код `64` |
| `-m <id>` (`--model`) | модель сессии до первого запроса |
| `--mode <id>` | режим сессии до первого запроса |
| `-v` (`--verbose`) | диагностика соединения в stderr |
| `--no-color` | вывод без цветов |

В диалоге модель и режим меняют `/model` и `/mode` ([глава о диалоге](02-repl.md#команды-codelab)). Какие режимы есть и что они значат — в [главе о разрешениях](../../../codelab_agent/doc/user/05-permissions.md#режимы); доступные модели зависят от провайдеров ([провайдеры моделей](06-providers.md)). Папка сессии определяет, какие файлы видит агент, какие сессии и какой слой проектной конфигурации (`.codelab/config.yaml`) он использует.

Все флаги печатает `codelab --help`; полный список — в [справочнике](11-reference.md).

## Выбрать агента

По умолчанию `codelab` работает со встроенным агентом: агент выполняется внутри процесса `codelab`, отдельная программа не нужна. `-a default` и `-a embedded` выбирают его же.

Другого агента выбирают флагом `-a` (`--agent`):

| Значение `-a` | Агент |
|---|---|
| не задано, `embedded`, `default` | встроенный агент |
| `stdio:<команда> [аргументы]` | программа-агент, которую `codelab` запускает в папке сессии, например `-a "stdio:codelab-agent serve --stdio"` |
| `ws://…`, `wss://…` | агент, который уже работает по этому адресу |
| `<id>` | сохранённый профиль |

Как запустить сам `codelab-agent` и что значат его режимы `--stdio` и `--ws` — в [главе об установке и запуске агента](../../../codelab_agent/doc/user/01-install-and-run.md).

Токен для подключения по WebSocket берётся из переменной окружения `CODELAB_AGENT_TOKEN`; в выводе он не показывается. Профиль, созданный в CodeLab app, может ссылаться на другую переменную или на секрет из хранилища — `codelab` понимает обе ссылки.

В диалоге `/profile` показывает текущего агента, а `/profile <id>` переключает на другого. Настройки встроенного агента (`/provider`, `/settings`) к внешнему агенту не относятся: у агента по WebSocket они только для чтения, а у программы, не являющейся `codelab-agent`, их ведёт сама программа.

## Профили

Профиль — сохранённый способ подключения. Сохранить профили:

```bash
codelab profiles add devbox ws://127.0.0.1:8765
codelab profiles add local-agent "stdio:codelab-agent serve --stdio"
```

```text
Saved profile devbox.
Saved profile local-agent.
```

Список профилей:

```bash
codelab profiles list
```

```text
devbox       ws: ws://127.0.0.1:8765
local-agent  stdio: codelab-agent (2 arguments)
```

Подробности одного профиля:

```bash
codelab profiles show devbox
```

```text
id: devbox
type: webSocket
uri: ws://127.0.0.1:8765
token: env CODELAB_AGENT_TOKEN
```

```bash
codelab profiles show local-agent
```

```text
id: local-agent
type: stdio
command: codelab-agent
args: 2 (values hidden)
```

Удалить профиль:

```bash
codelab profiles remove local-agent
```

```text
Removed profile local-agent.
```

Если профилей нет, `codelab profiles list` отвечает `No agent profiles. Add one with "codelab profiles add <id> stdio:<command>".`

Правила:

- Аргументы программы-агента `codelab` не печатает: в них может оказаться токен. Видно только их число.
- Идентификатор профиля — строчные латинские буквы, цифры, `.`, `_` и `-`, начинается с буквы или цифры, до 64 символов.
- Имена `embedded` и `default` зарезервированы за встроенным агентом: сохранить профиль с ними нельзя.

```bash
codelab profiles add embedded embedded
```

```text
codelab: embedded is built in; use --agent embedded
```

- Профили лежат в `$CODELAB_HOME/profiles.json` и общие с CodeLab app — [каталог `CODELAB_HOME`](../../../../docs/ops/codelab-home.md#общие-файлы). Не кладите в аргументы токены: значения аргументов лежат в этом файле открытым текстом.
- Отсутствующий профиль: `codelab profiles show nope` печатает `codelab: Unknown agent profile "nope".` и выходит с кодом `1`; `codelab -a nope` — ошибка использования с кодом `64`.

## Смотрите также

- [Провайдеры моделей](06-providers.md)
- [Диалог](02-repl.md) — `/model`, `/mode`, `/profile`
- [Справочник флагов и команд](11-reference.md)
