# CodeLab — документация пользователя

## Что такое CodeLab

CodeLab — рабочее место для работы с AI-агентами по протоколу ACP (Agent Client Protocol). Состоит из трёх частей:

| Часть | Что это |
|---|---|
| CodeLab app | настольное приложение (Flutter Desktop) с окном сессий, транскриптом и разрешениями |
| `codelab` | терминальный клиент: интерактивный режим (`--ui=tui` — полноэкранный), headless `-p`, команды `config`, `provider`, `mcp`, `secret`, `profiles` |
| `codelab-agent` | Dart-агент: `codelab-agent serve --stdio` или `--ws`; подключается к любому ACP-клиенту, например к Zed |

`codelab` и app — клиенты. По умолчанию они запускают **встроенный агент** внутри своего процесса: отдельный `codelab-agent` для этого не нужен. `codelab-agent` нужен, когда агент подключается к стороннему клиенту или работает как отдельный процесс.

## Оглавление

1. [Запуск из исходников](run-from-source.md) — сборка `codelab` и `codelab-agent`, запуск app и CLI. Установщик — с выпуском 1.0.
2. [Настройка](configuration.md) — `config.yaml`, секреты, `codelab config check`, LiteLLM Proxy.
3. [Переход с Python-агента](migrating-from-python-agent.md) — что изменилось и как перенести настройки.
   - Сессии Python-агента не переносятся — [подробности](migrating-from-python-agent.md#сессии-python-агента-не-переносятся).
   - Python-агент заморожен: только исправления безопасности, условия удаления — [поддержка Python-агента](migrating-from-python-agent.md#поддержка-python-агента).
4. [Zed](zed.md) — подключение `codelab-agent serve --stdio` к Zed.

До выпуска 1.0 тексты промптов и вывод инструментов в журналах сессий и логах агента не редактируются — [что попадает в логи и журналы](configuration.md#что-попадает-в-логи-и-журналы).
