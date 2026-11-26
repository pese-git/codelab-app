# CodeLab — документация пользователя

## Что такое CodeLab

CodeLab — рабочее место для работы с AI-агентами по протоколу ACP (Agent Client Protocol). Состоит из трёх частей:

| Часть | Что это |
|---|---|
| CodeLab app | настольное приложение (Flutter Desktop) с окном сессий, транскриптом и разрешениями |
| `codelab` | терминальный клиент: интерактивный режим (`--ui=tui` — полноэкранный), headless `-p`, команды `config`, `provider`, `mcp`, `secret`, `profiles` |
| `codelab-agent` | Dart-агент: `codelab-agent serve --stdio` или `--ws`; подключается к любому ACP-клиенту, например к Zed — [о программе](../../apps/codelab_agent/README.md) |

`codelab` и app — клиенты. По умолчанию они запускают **встроенный агент** внутри своего процесса: отдельный `codelab-agent` для этого не нужен. `codelab-agent` нужен, когда агент подключается к стороннему клиенту или работает как отдельный процесс.

## Оглавление

1. [Запуск из исходников](run-from-source.md) — сборка `codelab` и `codelab-agent`, запуск app и CLI. Установщик — с выпуском 1.0.
2. [Настройка](configuration.md) — `config.yaml`, секреты, MCP-серверы, навыки, `codelab config check`, LiteLLM Proxy.
3. [Переход с Python-агента](migrating-from-python-agent.md) — что изменилось и как перенести настройки.
   - Сессии Python-агента не переносятся — [подробности](migrating-from-python-agent.md#сессии-python-агента-не-переносятся).
   - Python-агент заморожен: только исправления безопасности, условия удаления — [поддержка Python-агента](migrating-from-python-agent.md#поддержка-python-агента).
4. [Zed](zed.md) — подключение `codelab-agent serve --stdio` к Zed.
   - Обратное направление — Claude Code как внешний агент в CodeLab app: [интеграция с Claude Code](../integrations/claude-code.md).
5. [Настольное приложение CodeLab app](../../apps/codelab_desktop/doc/user-guide.md) — 11 глав: [обзор окна](../../apps/codelab_desktop/doc/user/00-overview.md), установка и первый запуск, проекты и сессии, диалог с агентом, разрешения, файлы, терминал и палитра команд, подключение и профили, провайдеры, MCP и навыки, [настройки](../../apps/codelab_desktop/doc/user/09-settings.md) (оформление, [язык интерфейса](../../apps/codelab_desktop/doc/user/09-settings.md#язык-интерфейса), правовая информация), если что-то пошло не так.
6. [Терминальный клиент `codelab`](../../apps/codelab_cli/doc/user-guide.md) — 13 глав: [обзор режимов](../../apps/codelab_cli/doc/user/00-overview.md), установка и мастер первого запуска, диалог (REPL), полноэкранный режим (TUI), один запрос `-p` для скриптов и CI, папка, модель и агент, провайдеры, секреты, MCP, `config`, `test-scenario`, [справочник команд и флагов](../../apps/codelab_cli/doc/user/11-reference.md), если что-то пошло не так.
7. [Агент CodeLab](../../apps/codelab_agent/doc/user-guide.md) — то, что агент умеет в любом клиенте (встроенным в app и `codelab` или отдельным `codelab-agent`): [обзор и способы запуска](../../apps/codelab_agent/doc/user/00-overview.md), подключение к клиентам, модель, [инструменты](../../apps/codelab_agent/doc/user/04-tools.md), [разрешения](../../apps/codelab_agent/doc/user/05-permissions.md), [контекст проекта](../../apps/codelab_agent/doc/user/06-project-context.md) (`AGENTS.md`, шаблоны команд, определения агентов, навыки), субагенты и задачи, MCP, сессии и сжатие контекста, данные и логи, если что-то пошло не так.

Правовые документы общие для app и `codelab`: [политика конфиденциальности](../../PRIVACY.md) ([русская редакция](../../PRIVACY.ru.md)) и [условия использования](../../TERMS.md) ([русская редакция](../../TERMS.ru.md)). В app они же открываются на странице настроек «Legal» — [подробности](../../apps/codelab_desktop/doc/user/09-settings.md#правовая-информация).

До выпуска 1.0 тексты промптов и вывод инструментов в журналах сессий и логах агента не редактируются — [что попадает в логи и журналы](configuration.md#что-попадает-в-логи-и-журналы).

Переменные окружения, коды выхода и сопровождение установки — в [руководстве по эксплуатации](../ops/README.md).

## Лицензия

Код CodeLab распространяется по лицензии MIT — полный текст в файле [`LICENSE`](../../LICENSE). Учёт воспроизведённых внешних фрагментов — [`THIRD_PARTY_NOTICES.md`](../../THIRD_PARTY_NOTICES.md). В app лицензия открывается на странице настроек «Legal», вкладка «License» — [подробности](../../apps/codelab_desktop/doc/user/09-settings.md#правовая-информация).
