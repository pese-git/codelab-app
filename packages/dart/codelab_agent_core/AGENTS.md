# AGENTS.md — codelab_agent_core

Правила этого пакета дополняют корневой `AGENTS.md`. Источник архитектуры — `docs/architecture/proposals/agent-core-architecture.md`, для этого пакета — §1 (`agent-core/01-layers-and-packages.md`). Код пишется по этим документам и `design.md` OpenSpec change этапа; если документов не хватает, сначала дополняется документация, потом пишется код.

## 1. Инварианты пакета (agent-core-architecture §1.5)

* **PKG-1.** Ни один файл `lib/**` НЕ ДОЛЖЕН импортировать `dart:io`, `dart:isolate`, `dart:ffi`, `dart:html`, `dart:js_interop`, `package:web`, `package:flutter`, `package:codelab_acp_protocol`, `package:codelab_acp_transports` — в том числе через `export`, `part` и альтернативы условного импорта.
* **PKG-2.** `dependencies` в `pubspec.yaml` — только подмножество `{http, meta, collection, async, crypto}`. Расширение allowlist — только через OpenSpec change.
* **PKG-3.** `codelab_agent_acp` и `codelab_agent_mcp` (после MVP — и `codelab_agent_a2a`) не импортируют `dart:io` — правило этих пакетов, ядро от них не зависит.
* **PKG-4.** Клиенты (`apps/codelab_desktop`, `apps/codelab_cli`) НЕ ДОЛЖНЫ импортировать `package:codelab_agent_*`. Доступ к агенту у них — только через `codelab_setup` (мост настроек; создан в минимальном составе change `add-agent-configuration`, D14) и с этапа 7 — через `codelab_embedded` (ещё не создан, заготовка правила — в `test/support/rules.dart` сторожа).
* **PKG-5.** Публичный экспорт ядра НЕ ДОЛЖЕН раскрывать `lib/src/llm/providers/*` и внутренние классы цикла: адаптеры провайдеров — через фабрики `createStreamFunction(ProviderConfig config, CoreLlmServices services)` и `createRoutedStreamFunction` для нескольких провайдеров конфигурации (§2.10).
* **PKG-6.** Ядро НЕ ДОЛЖНО само создавать HTTP-клиент, таймеры ожидания, случайность и id: `http.Client`, `Clock`, `Random` и `IdGenerator` приходят от хоста (в тестах — детерминированные).

* **CFG-5.** `lib/src/config/` — модель и проверка конфигурации без файлов и разборщиков (agent-core-architecture §15; design.md change `add-agent-configuration`, D1, D3): ядро НЕ ДОЛЖНО импортировать `package:yaml`, `package:yaml_edit` и `package:toml` (правило ядра в `rules.dart`; сторож проверяет только эту импортную часть CFG-5, остальное — тесты и ревью). Хост разбирает файлы в `ConfigTree` и вызывает чистую функцию `CoreConfig.fromLayers`; результат — `ConfigLoadResult` с проблемами (`ConfigIssue`: источник, строка, столбец, путь ключа), а не исключение. Новый ключ конфигурации — строка схемы `schema.dart` вместе со своим потребителем; ключ схемы без потребителя даёт `config.key.not_applied` (D6).

PKG-1, PKG-2, PKG-4 и импортную часть CFG-5 проверяет `melos run guard` (`packages/dart/codelab_architecture_tests`); `melos run web-compile` компилирует `test/web_smoke/main.dart` в JavaScript и WebAssembly. Нарушение — красный `check` и красный CI, а не предмет обсуждения на ревью.

## 2. TDD (dart-agent-and-clients §9.0, правило 3)

* Каждая задача начинается с красного теста из критерия приёмки матрицы целей (`agent-parity-goals.md`) или из раздела «Как проверить» документа ядра; затем минимальный код до зелёного; затем рефакторинг.
* Пункты `tasks.md` идут парами «тест → реализация» со ссылкой на критерий. В PR красный тест виден в истории коммитов до кода, или PR ссылается на критерий, который закрывает.
* Уровень теста — минимально необходимый (`docs/architecture/testing.md` §1): чистый Dart там, где можно.
* Исключения: (а) рефакторинг существующего кода — сначала характеризационные тесты; (б) интеграционные тесты app и PTY-e2e CLI — приёмочные ворота этапа, а не цикл разработки; (в) UI — test-first для Cubit и модели отображения; (г) реальные провайдеры, keychain, процессы ОС — test-first на фейках, реальные проверки отдельными интеграционными тестами; (д) разведка — spike с ограничением по времени без тестов, затем код по TDD.

## 3. Итерации: feature first (dart-agent-and-clients §9.0, правило 8)

Итерация — тонкий сквозной срез одной функции через все нужные ей слои, обычно 1–3 PR и не дольше недели. Архитектура закладывается с первой итерации, но пустые пакеты и абстракции «на вырост» не создаются (корневой `AGENTS.md` §6, §13).

Итерация завершена, когда:

* (а) функция работает без ошибок: критерии строк матрицы зелёные, полный `melos run check` зелёный в CI на `develop` после merge, проверки затронутого (корневой `AGENTS.md` §21) зелёные локально и в CI pull request;
* (б) unit-тесты покрывают каждое новое поведение и публичный элемент; интеграционные тесты — для каждой пересечённой границы (кадры ACP, файлы, процессы, HTTP, хранилище) на фейках или в процессе; если интеграционный тест невозможен, PR говорит почему;
* (в) архитектура готова к следующей итерации: PR называет следующую итерацию и точку, куда встаёт её функция; контракты расширяются без изменения используемых сигнатур;
* (г) архитектура легко расширяема: функция добавлена в точке расширения документа ядра (`ToolRegistry`, порты `AgentCoreServices`, capabilities `HostProfile`, ветка sealed-иерархии `AgentEvent`, ключ схемы конфига, фабрика провайдеров), а не условиями в существующем коде; сторож и allowlist зелёные; нет `TODO` без задачи, `// ignore:` без причины, временных флагов без задачи на удаление;
* (д) рефакторинг сделан;
* (е) документы и код не расходятся.

## 4. Ручной smoke провайдеров

`tool/llm_smoke.dart` отправляет один запрос реальному провайдеру через адаптер и печатает события и usage. Так SSE-фикстуры `test/fixtures/sse/` сверяются с настоящими потоками (design.md change `add-agent-core-llm-contract`, D9). В CI скрипт не запускается: ему нужен ключ.

```bash
CODELAB_SMOKE_PROVIDER=openai-compatible \
CODELAB_SMOKE_BASE_URL=https://api.openai.com/v1 \
CODELAB_SMOKE_MODEL=gpt-4.1-mini \
CODELAB_SMOKE_API_KEY="$OPENAI_API_KEY" \
fvm dart run tool/llm_smoke.dart
```

`CODELAB_SMOKE_PROVIDER=anthropic` с `CODELAB_SMOKE_BASE_URL=https://api.anthropic.com` проверяет адаптер Anthropic; `CODELAB_SMOKE_REASONING=low|medium|high` включает рассуждение; `CODELAB_SMOKE_THINKING=budget` нужен моделям Claude 4.5 и старше (по умолчанию `adaptive` — для Claude 4.6 и новее). Для локальных серверов (Ollama, LM Studio) ключ не нужен. Если поток провайдера расходится с фикстурой, фикстура исправляется со ссылкой на документацию провайдера.

