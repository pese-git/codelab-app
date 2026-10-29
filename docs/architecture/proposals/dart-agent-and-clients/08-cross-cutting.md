# 8. Сквозные аспекты

> Часть предложения [«Dart-агент и клиенты CodeLab»](../dart-agent-and-clients.md). Status: Accepted. Исходные решения, связанные документы и порядок чтения — в оглавлении.

← [7. Источники решений](07-decision-sources.md) · [Оглавление](../dart-agent-and-clients.md) · [9. План миграции](09-00-migration-plan.md) →

| Аспект | Решение |
|---|---|
| Ошибки | три класса: события (LLM, цикл, инструменты), `Result` (env), исключения только для программных ошибок; провайдер никогда не бросает (документ ядра §12) |
| Отмена | `CancelToken` во всех операциях; мягкая отмена между инструментами; `terminal/kill` для живых процессов (документ ядра §3) |
| Таймауты | connect и idle для LLM; таймаут на `fs/*` client-RPC; бесконечное ожидание только для `terminal/wait_for_exit` с watchdog; в клиенте — таймаут на каждый JSON-RPC запрос, кроме `session/prompt` (этап 5) |
| Безопасность | одна точка проверки (§5.2); `BoundedEnv`; редакция секретов до записи в журнал и перед провайдером; `env` процессов — по allowlist, без утечки окружения GUI |
| Наблюдаемость | `Logger`-порт; структурированные события; protocol trace в ACP-адаптере и клиенте; usage и стоимость в `TurnEnded` (документ ядра §12) |
| Конфигурация | YAML: `~/.codelab/config.yaml` + проектный `.codelab/config.yaml` + env; `CODELAB_HOME`; валидация до старта (документ ядра §15); `codelab.toml` Python-агента не читается — при нём без YAML-конфига одно предупреждение `config.legacy_found` (§15.7); профили клиентов — `~/.codelab/profiles.json` |
| Совместимость данных | старые JSON-сессии Python не переносятся: форматы разные, журналы в разных каталогах (agent-core-architecture §8.9, §16.1); настройки `codelab.toml` переносятся вручную по таблице agent-core-architecture §15.7 (команды `codelab config migrate` нет) |
| Проверка границ | тест-сторож `codelab_architecture_tests` (§9.5): запреты импортов и allowlist зависимостей; ядро и платформенно-нейтральные пакеты компилируются `dart compile js` и `dart compile wasm` в CI |
| Версии протокола | `AcpClientApplication.supportedProtocolVersion = 1`; агент отвечает той же версией; расширения — только `_meta` и `_codelab/*` |

---

← [7. Источники решений](07-decision-sources.md) · [Оглавление](../dart-agent-and-clients.md) · [9. План миграции](09-00-migration-plan.md) →
