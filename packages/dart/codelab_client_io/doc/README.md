# Руководство по `codelab_client_io`

Руководство для разработчика объясняет, как устроен пакет `codelab_client_io`: какие порты клиентского слоя он реализует на `dart:io`, кто его собирает, в каком формате пишет файлы и как добавить новое JSON-хранилище. Пакет небольшой, поэтому глав две. Общий обзор и пример подключения — в [README пакета](../README.md), правила изменений — в [`AGENTS.md`](../AGENTS.md).

Нормы лежат в спецификации [`acp-client-kit`](../../../../openspec/specs/acp-client-kit/spec.md) (требование «IO-адаптеры клиента») и в [`client-themes`](../../../../openspec/specs/client-themes/spec.md). Если код и это руководство спорят — прав код. Расхождение кода со спецификацией — дефект, о нём нужно сообщить (AGENTS.md §3.1).

## Главы

| Глава | О чём |
|---|---|
| [01. Обзор и сборка](01-overview.md) | место пакета в слоях, карта `lib/src/`, реализуемые порты, кто и где создаёт адаптеры, границы рабочей папки, тесты |
| [02. Хранилища и расширение](02-stores-and-extending.md) | форматы `profiles.json` и `recent_projects.json`, поведение при пропавшем и битом файле, рецепт нового JSON-хранилища, частые проблемы |

## Кому что читать

| Задача | Главы |
|---|---|
| понять, где пакет стоит и кто его использует | 01 |
| подключить адаптеры в новый хост | 01 |
| разобраться, почему клиент не читает `profiles.json` | 02 |
| добавить новое JSON-хранилище | 02 |

## Смежные документы

- [Настройки на клиенте](../../codelab_client_core/doc/settings-on-client.md) — какие файлы и ключи хранит клиент, как их читают app и CLI, что при повреждении и одновременной записи.
- [`codelab_client_core`](../../codelab_client_core/README.md) и [`codelab_client_core/doc`](../../codelab_client_core/doc/README.md) — порты и политики, которые реализует пакет.
- [`codelab_client_acp`](../../codelab_client_acp/README.md) и [`codelab_client_acp/doc`](../../codelab_client_acp/doc/README.md) — порты `fs/*` и `terminal/*`.
- [Руководство по `codelab`](../../../../apps/codelab_cli/doc/README.md) — composition root терминального клиента.
- [Каталог `CODELAB_HOME`](../../../../docs/ops/codelab-home.md) — где лежат общие файлы и кто их пишет.
- [`docs/architecture/platform-integration.md`](../../../../docs/architecture/platform-integration.md) — почему файлы и процессы живут за границей инфраструктуры.
