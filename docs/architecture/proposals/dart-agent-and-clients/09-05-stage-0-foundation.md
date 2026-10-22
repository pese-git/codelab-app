# 9.5. Этап 0 — Фундамент

> Часть предложения [«Dart-агент и клиенты CodeLab»](../dart-agent-and-clients.md). Status: Proposed. Исходные решения, связанные документы и порядок чтения — в оглавлении.

← [9. План миграции](09-00-migration-plan.md) · [Оглавление](../dart-agent-and-clients.md) · [9.6. Этап 1 — LLM](09-06-stage-1-llm.md) →

**Цель.** Подготовить монорепозиторий так, чтобы каждое следующее изменение проверялось
автоматически: CI, сторож архитектуры, сборка ядра для web, корпус фикстур ACP.

**Задачи.**

1. **0.1. Свести конфигурацию melos.** Перенести недостающие скрипты (`test:e2e:app:plan-checklist`,
   `test:e2e:app:prompt-queue`, `test:e2e:app:multi-session`) в секцию `melos:` корневого
   `pubspec.yaml`, удалить `melos.yaml` (melos 8 читает конфигурацию из `pubspec.yaml`). Проверка:
   `melos list` и `melos run check` работают как раньше.
2. **0.2. Разделить `acp_transports`.** Создать `packages/dart/acp_transports/lib/io.dart` и
   перенести в него экспорт `StdioAcpTransport` и `WebSocketAcpTransport`. Классы конфигурации
   (`StdioAcpTransportConfig`, `StdioAcpAgentProfile`, `WebSocketAcpTransportConfig`) перенести в
   новый файл `lib/src/transport_configs.dart` без `dart:io` и экспортировать из основного бареля.
   Обновить импорты в `apps/codelab_app` (`shell_cubit.dart`, `app_scope.dart`), `acp_testing` и
   тестах. Классы конфигурации объявлены через `freezed` (сейчас — в `stdio_acp_transport.dart` и
   `websocket_acp_transport.dart` с `part '*.freezed.dart'`): после переноса сгенерированный код
   пересобирается — `fvm dart run build_runner build --delete-conflicting-outputs` в
   `packages/dart/acp_transports` (появляется `lib/src/transport_configs.freezed.dart`, старые
   `*.freezed.dart` теряют перенесённые классы); сгенерированные файлы коммитятся, как сейчас.
   Изменение публичного API → OpenSpec.
3. **0.3. Создать пакет `packages/dart/codelab_agent_core`** с `pubspec.yaml` по скелету ниже,
   `lib/codelab_agent_core.dart` (пока только `const codelabAgentCorePackageName`) и
   `test/web_smoke/main.dart`, который импортирует барель и печатает имя пакета. Добавить пакет в
   `workspace:` корневого `pubspec.yaml`.
4. **0.4. Создать пакет `packages/dart/codelab_architecture_tests`** с тестом-сторожем (код
   ниже): запреты импортов во всех файлах `lib/**/*.dart` пакетов (включая `part` и
   `lib/testing.dart`), allowlist зависимостей ядра (`pubspec_allowlist_test.dart`),
   негативный тест на временном пакете.
5. **0.5. Добавить скрипты melos** `guard`, `web-compile`, `conformance:client`, `test:dart`
   (YAML ниже) и включить их в `check`.
6. **0.6. Создать CI** `.github/workflows/ci.yml` (эскиз ниже) и
   `.github/pull_request_template.md` с чек-листом: OpenSpec change, тесты, пункт о стороннем коде
   (§7а).
7. **0.7. Корпус фикстур.** Создать `packages/dart/acp_testing/fixtures/acp/` (файлы плоско,
   `<id>.json`, раскладка — agent-core-architecture §14.2) и в `packages/dart/acp_testing/lib/src/fixtures/`:
   `fixture.dart` (модель фикстуры и загрузчик, громко падает на неполной фикстуре), `matcher.dart`
   (сравнение с нормализацией: id запросов, время, абсолютные пути → плейсхолдеры) и
   `client_conformance.dart` (проигрывает кадры агента в `FakeAcpTransport` и сверяет ответы
   клиента). На этапе 0 — только клиентский драйвер: агента ещё нет, драйвер агентской проверки
   `agent_conformance.dart` создаётся в задаче 4.8 (§9.9). Модель фикстуры сразу знает поле
   `roles` (agent-core-architecture §14.4; по умолчанию `["agent", "client"]`), а кадры `fs/*` и
   `terminal/*` в фикстурах — часть сценария (§14.9): клиентский драйвер отвечает на них из
   `setup.files` через fake-порты клиента. Первые 12 фикстур: `acp/initialize-capabilities` (R-01), `acp/session-new-modes-config`,
   `acp/prompt-text-end-turn`, `acp/prompt-cancel-mid-tool`, `acp/prompt-tool-permission-allow` (P-02),
   `acp/prompt-tool-permission-reject-continues` (P-04), `acp/tool-status-lifecycle`,
   `acp/tool-read-range` (T-01), `acp/tool-exec-terminal-embed` (T-08), `acp/prompt-update-plan` (C-05),
   `acp/set-config-option-model` (R-06), `acp/errors-unknown-session-update-tolerated`. Id в скобках —
   строки целей в `agent-parity-goals.md`, которые фикстура закрывает; фикстуры без строки — базовые
   для корпуса. Каждая ссылается на раздел `docs/acp/protocol/*`.
8. **0.8. Клиентский прогон корпуса**:
   `packages/dart/acp_client_core/test/fixtures/client_fixture_conformance_test.dart` — для каждой
   фикстуры, у которой `roles` содержит `client`, поднимает `AcpClientApplication` на `FakeAcpTransport` и
   проверяет ответы и итоговое состояние сессии.
9. **0.9. Лицензия.** Лицензия — MIT (§11); добавить в корень `LICENSE` (текст MIT с правообладателем репозитория),
   `THIRD_PARTY_NOTICES.md` (заголовок и пустой список с форматом записи из §7а) и раздел о
   лицензиях в `README`.
10. **0.10. Незавершённые OpenSpec changes Python-агента** (`context-manager-implementation`,
    `session-hot-cold-split` и другие — каталог `../codelab-agent/openspec/changes/` соседнего
    репозитория `codelab-agent`, путь от корня `codelab-app`): по каждому — «закрыть» или
    «перенести в backlog Dart-агента», список фиксируется в `proposal.md` change этапа 0.
11. **0.11. `AGENTS.md`: правила агентских пакетов, TDD и готовность итерации.** В корневом `AGENTS.md` — раздел §5
    (структура monorepo) дополняется агентскими пакетами и ссылкой на
    [документ ядра](../agent-core-architecture.md) как источник архитектуры агента, правилом
    стороннего кода §7а. Вложенные `AGENTS.md` в `packages/dart/codelab_agent_*`, созданных на этом
    этапе (`codelab_agent_core`): правила ядра PKG-1…PKG-6 (agent-core-architecture §1), сторож
    импортов (задача 0.4), TDD по §9.0, правило 3 (красный тест из критерия матрицы → минимальный
    код → рефакторинг), и определение завершённой итерации по §9.0, правило 8 (feature first,
    unit- и интеграционные тесты, готовность к следующей итерации, расширение через точки
    расширения документа ядра). Новые пакеты следующих этапов получают вложенный `AGENTS.md` в своём
    этапе; задача 9.7 дописывает корневой `AGENTS.md` окончательно, а не создаёт его.

**OpenSpec change.** `add-workspace-ci-and-architecture-guards` (задачи 0.1–0.6, 0.9, 0.11; scope:
CI, сторож, разделение `acp_transports` как изменение публичного API пакета, правила
`AGENTS.md` для агентских пакетов и TDD) и `add-acp-golden-fixture-corpus` (задачи 0.7–0.8;
scope: формат и корпус фикстур с полем `roles`, клиентский драйвер, правила изменения фикстур).
`tasks.md` — пары «тест → реализация» со ссылкой на критерий (§9.0, правило 3).

**Что прочитать.** Документ ядра §1 (пакеты и инварианты PKG-1…PKG-6), §14 (формат фикстур);
`docs/architecture/testing.md` §6, §12, §15; `docs/architecture/layers-and-dependencies.md`.

**Definition of Done.**

* `melos run check` зелёный; в CI зелёные все шесть джобов.
* `fvm dart test packages/dart/codelab_architecture_tests` проходит, а его негативный тест
  `import_guard_test.dart: reports dart:io imported by a core library` подтверждает, что
  нарушение ловится.
* `fvm dart compile js packages/dart/codelab_agent_core/test/web_smoke/main.dart -o build/web_smoke/core.js`
  и `fvm dart compile wasm ... -o build/web_smoke/core.wasm` проходят.
* `fvm dart test packages/dart/acp_client_core/test/fixtures` проходит на 12 фикстурах
  (клиентский драйвер; агентского драйвера на этапе 0 нет — задача 4.8).
* Корневой `AGENTS.md` §5 ссылается на документ ядра; `packages/dart/codelab_agent_core/AGENTS.md`
  есть и перечисляет PKG-1…PKG-6, сторож импортов, правило TDD и определение завершённой итерации (задача 0.11).
* `grep -rn "dart:io" packages/dart/acp_transports/lib/acp_transports.dart packages/dart/acp_transports/lib/src/transport_configs.dart` — пусто.
* 8 интеграционных тестов app проходят (`melos run test:e2e:app:stdio` и остальные).

**Зависимости.** Нет. Этап блокирует все остальные.

**Риски.** Разделение `acp_transports` ломает импорты в app — снижается тем, что изменение
механическое и защищено тестами app. FVM в CI медленно ставит SDK — кэш каталога FVM.

## Артефакт: скрипты melos

Добавить в секцию `melos: scripts:` корневого `pubspec.yaml` (у каждого скрипта также поле
`description`, здесь опущено; скрипты для пакетов, которых ещё нет, добавляются на своих этапах):

```yaml
    test:dart: fvm dart run melos exec -c 4 --no-flutter --dir-exists=test --fail-fast -- "fvm dart test"
    guard: fvm dart test packages/dart/codelab_architecture_tests
    web-compile: >-
      fvm dart compile js -O1 -o build/web_smoke/core.js packages/dart/codelab_agent_core/test/web_smoke/main.dart &&
      fvm dart compile wasm -o build/web_smoke/core.wasm packages/dart/codelab_agent_core/test/web_smoke/main.dart
    conformance:client: fvm dart test packages/dart/acp_client_core/test/fixtures
    conformance:agent: fvm dart test packages/dart/codelab_agent_acp/test/conformance                 # этап 4
    build:agent: fvm dart compile exe apps/codelab_agent/bin/codelab_agent.dart -o build/bin/codelab-agent  # этап 4
    build:cli: fvm dart compile exe apps/codelab_cli/bin/codelab.dart -o build/bin/codelab              # этап 6
    test:e2e:cli: fvm dart test apps/codelab_cli/test/e2e                                              # этап 6
    test:e2e:app:dart-agent: >-                                                                        # этап 4, контракт — §9.9, задача 4.9
      fvm dart run melos run build:agent &&
      fvm dart run melos exec --scope=codelab_app -- "fvm flutter test integration_test -d macos
      --exclude-tags scripted-only --dart-define=CODELAB_E2E_AGENT=dart
      --dart-define=CODELAB_E2E_AGENT_BIN=../../build/bin/codelab-agent"
    test:e2e:app:embedded: >-                                                                          # этап 7
      fvm dart run melos exec --scope=codelab_app -- "fvm flutter test integration_test -d macos
      --dart-define=CODELAB_E2E_AGENT=embedded --dart-define=CODELAB_ALLOW_SCRIPTED_LLM=true"
    check:
      description: Run format, analyze, guard, tests, conformance and web compile.
      steps: [check-format, analyze, guard, test, protocol-conformance, conformance:client, web-compile]
```

`conformance:agent` добавляется в `check` на этапе 4; `test:e2e:*` в `check` не входят (нужен
macOS и реальные процессы) и запускаются отдельным джобом CI.

## Артефакт: CI

Общие шаги подготовки — составное действие `.github/actions/prepare/action.yml`:

```yaml
name: prepare
description: Install the FVM-pinned Flutter SDK and resolve the pub workspace.
runs:
  using: composite
  steps:
    - uses: dart-lang/setup-dart@v1
    - uses: actions/cache@v4
      with:
        path: |
          ~/fvm
          ~/.pub-cache
        key: fvm-${{ runner.os }}-${{ hashFiles('.fvmrc', 'pubspec.lock') }}
    - shell: bash
      run: dart pub global activate fvm && fvm install && fvm dart pub get
```

`.github/workflows/ci.yml` — шесть обязательных джобов из одной матрицы и отдельный macOS-джоб:

```yaml
name: ci
on:
  push: {branches: [main]}
  pull_request:
  schedule: [{cron: "0 3 * * *"}]          # ночной прогон e2e
concurrency: {group: "ci-${{ github.ref }}", cancel-in-progress: true}

jobs:
  checks:
    name: ${{ matrix.job }}
    runs-on: ubuntu-latest
    strategy:
      fail-fast: false
      matrix:
        include:
          - {job: format, scripts: "check-format"}
          - {job: analyze, scripts: "analyze"}
          - {job: test, scripts: "test"}
          - {job: conformance, scripts: "protocol-conformance conformance:client"}   # + conformance:agent с этапа 4
          - {job: guard, scripts: "guard"}
          - {job: web-compile, scripts: "web-compile"}                                # + flutter build web с этапа 10
    steps:
      - uses: actions/checkout@v4
      - uses: ./.github/actions/prepare
      - run: for s in ${{ matrix.scripts }}; do fvm dart run melos run "$s" || exit 1; done

  e2e-macos:                                 # ночью, на main и по метке PR "e2e"
    if: github.event_name != 'pull_request' || contains(github.event.pull_request.labels.*.name, 'e2e')
    needs: checks
    runs-on: macos-latest
    steps:
      - uses: actions/checkout@v4
      - uses: ./.github/actions/prepare
      - run: |
          for s in stdio permission fs terminal plan-checklist prompt-queue multi-session open-project; do
            fvm dart run melos run "test:e2e:app:$s" || exit 1
          done
      # с этапа 4: test:e2e:app:dart-agent; с этапа 6: test:e2e:cli; с этапа 7: test:e2e:app:embedded
```

Джобы `format`, `analyze`, `test`, `conformance`, `guard`, `web-compile` обязательны для слияния
(branch protection). `e2e-macos` не блокирует PR без метки, но блокирует релиз. Сценарий
выпуска — отдельный `.github/workflows/release.yml` (по тегу `v*`, окружение `release` с
ручным одобрением для подписи и публикации) — §12.7.8; этап 0 его не создаёт.

## Артефакт: тест-сторож архитектуры

Правила хранятся в одном месте и повторяют таблицу §4.1. Алгоритм — agent-core-architecture §1.4:
сторож обходит **все** файлы `lib/**/*.dart` каждого пакета из таблицы, включая файлы `part`
и точки входа верхнего уровня (`lib/testing.dart` ядра тоже проверяется), и разбирает
директивы `import`, `export`, `part`; каждое альтернативное URI условного импорта
проверяется отдельно. Обход всех файлов делает транзитивную проверку через барели ненужной.

```dart
// packages/dart/codelab_architecture_tests/test/support/rules.dart
const webUnsafe = ['dart:io', 'dart:isolate', 'dart:ffi', 'dart:html', 'dart:js_interop',
    'package:web/', 'package:flutter/', 'package:acp_transports/io.dart'];

final class PackageRule {
  const PackageRule(this.dir, {required this.forbidden, this.exclude = const []});
  final String dir;             // пакет (сканируется его lib/) или каталог внутри lib/
  final List<String> forbidden; // префиксы URI
  final List<String> exclude;   // вне правила: путь файла или префикс каталога с '/' (IO-точка входа и её реализация)
  // файлы вне exclude не должны ссылаться на файлы из exclude (agent-core-architecture §1.4) — отдельная проверка
}

const rules = [
  PackageRule('packages/dart/codelab_agent_core',
      forbidden: [...webUnsafe, 'package:acp_protocol/', 'package:acp_transports/']),
  PackageRule('packages/dart/acp_transports', forbidden: webUnsafe, exclude: ['lib/io.dart', 'lib/src/io/']),
  PackageRule('packages/dart/acp_client_core', forbidden: webUnsafe),
  // этап 2: codelab_agent_io — ['package:flutter/', 'package:acp_']
  // этап 4: codelab_agent_acp — webUnsafe; этап 8: codelab_agent_mcp — webUnsafe
  // этап 5: acp_client_kit — webUnsafe; acp_client_io — ['package:flutter/']
  // этап 6: apps/codelab_cli — ['package:flutter/', 'package:codelab_agent_']
  // этап 7: codelab_embedded — webUnsafe, exclude: ['lib/io.dart', 'lib/src/io/']; apps/codelab_app — ['package:codelab_agent_']
  // этап 7: codelab_setup — [...webUnsafe, 'package:codelab_agent_io/', 'package:acp_', 'package:flutter/'],
  //   exclude: ['lib/io.dart', 'lib/src/io/'];
  //   apps/codelab_app/lib/features/settings/presentation — ['package:codelab_setup/io.dart', 'dart:io'] (§12.4.2, SETUP-9)
];
```

```dart
// packages/dart/codelab_architecture_tests/test/support/import_scanner.dart
import 'dart:io';
import 'package:path/path.dart' as p;
import 'rules.dart';

final _directive = RegExp(r'''^\s*(?:import|export|part)\s+['"]([^'"]+)['"]''');
final _conditional = RegExp(r'''if\s*\([^)]*\)\s*['"]([^'"]+)['"]''');

/// Нарушения правила в виде `файл:строка -> URI`.
List<String> scan(String root, PackageRule rule) {
  final base = p.join(root, rule.dir);
  final dir = Directory(p.split(rule.dir).contains('lib') ? base : p.join(base, 'lib'));
  final violations = <String>[];
  for (final file in dir.listSync(recursive: true).whereType<File>()) {
    final rel = p.relative(file.path, from: base);
    if (!file.path.endsWith('.dart') ||
        rule.exclude.any((e) => e.endsWith('/') ? rel.startsWith(e) : rel == e)) continue;
    final lines = file.readAsLinesSync();
    for (var i = 0; i < lines.length; i++) {
      final uris = [
        for (final m in _directive.allMatches(lines[i])) m.group(1)!,
        for (final m in _conditional.allMatches(lines[i])) m.group(1)!, // каждая альтернатива
      ];
      for (final uri in uris.where((u) => rule.forbidden.any(u.startsWith))) {
        violations.add('${p.relative(file.path, from: root)}:${i + 1} -> $uri');
      }
    }
  }
  return violations;
}
```

```dart
// packages/dart/codelab_architecture_tests/test/import_guard_test.dart
import 'dart:io';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';
import 'support/import_scanner.dart';
import 'support/rules.dart';

void main() {
  final root = p.normalize(p.join(Directory.current.path, '..', '..', '..'));

  for (final rule in rules) {
    test('${rule.dir}: no forbidden imports in lib/', () {
      final violations = scan(root, rule);
      expect(violations, isEmpty, reason: violations.join('\n'));
    });
  }

  test('reports dart:io imported by a core library', () {
    final tmp = Directory.systemTemp.createTempSync('guard_');
    addTearDown(() => tmp.deleteSync(recursive: true));
    File(p.join(tmp.path, 'lib', 'src', 'x.dart'))
      ..createSync(recursive: true)
      ..writeAsStringSync("import 'a.dart' if (dart.library.io) 'dart:io';\n");

    final violations = scan(tmp.path, PackageRule('.', forbidden: webUnsafe));

    expect(violations.single, endsWith('lib/src/x.dart:1 -> dart:io'));
  });
}
```

Allowlist зависимостей — отдельный тест `codelab_architecture_tests/test/pubspec_allowlist_test.dart`
(agent-core-architecture §1.4, §1.7): ключи секции `dependencies:` в `pubspec.yaml` ядра — подмножество
`{http, meta, collection, async, crypto}` (PKG-2; `crypto` подключается, когда понадобится SHA-256, — agent-core-architecture §1.2). Сторож разбирает директивы регулярным выражением, без
анализатора: это быстро и без тяжёлых зависимостей. Если в коде появятся директивы, которые
выражение не распознаёт, сканер переводится на `package:analyzer` (`parseString`).

## Артефакт: скелеты `pubspec.yaml` новых пакетов

Все пакеты: `version: 0.1.0`, `publish_to: none`, `resolution: workspace`,
`environment.sdk: ">=3.8.0 <4.0.0"`, dev-зависимости `lints: ^6.0.0` и `test: ^1.26.3`, как в
существующих пакетах. Ниже — имя, описание и зависимости; путь `../X` означает
`{path: ../X}` (для приложений — `../../packages/dart/X`). Пакет создаётся на указанном этапе.

| Пакет (этап) | `description` | `dependencies` | особые поля |
|---|---|---|---|
| `codelab_agent_core` (0) | Embeddable pure Dart CodeLab agent core — LLM, loop, tools, permissions, sessions. | `async: ^2.12.0`, `collection: ^1.19.0`, `http: ^1.2.0`, `meta: ^1.16.0` — и только они (PKG-2) | — |
| `codelab_architecture_tests` (0) | Repository-wide architecture guards (imports, dependency allowlists). | — | `dev_dependencies`: `path: ^1.9.0`, `test` |
| `codelab_agent_io` (2) | dart:io adapters for the CodeLab agent core — local env, processes, JSONL store, config. | `../codelab_agent_core`, `path: ^1.9.0`; этап 8 — `yaml` (разбор конфига и frontmatter определений агентов и skills), `yaml_edit` (запись конфига с сохранением форматирования), `toml` (только чтение устаревшего `codelab.toml`) | — |
| `codelab_agent_acp` (4) | ACP agent-side server over the CodeLab agent core. | `../acp_protocol`, `../acp_transports`, `../codelab_agent_core` | `dev_dependencies`: `../acp_client_core`, `../acp_testing` (contract test) |
| `apps/codelab_agent` (4) | codelab-agent binary — serves the Dart agent over ACP stdio and WebSocket. | `acp_transports`, `codelab_agent_acp`, `codelab_agent_core`, `codelab_agent_io`, `args: ^2.6.0`; этап 8 — `codelab_agent_mcp` | `executables: {codelab-agent: codelab_agent}` |
| `acp_client_kit` (5) | UI-agnostic ACP client workspace shared by codelab_app and codelab_cli. | `../acp_client_core`, `../acp_protocol`, `meta: ^1.16.0` | `dev_dependencies`: `../acp_testing` |
| `acp_client_io` (5) | dart:io implementations of ACP client ports — fs, terminal, profile and project stores. | `../acp_client_core`, `../acp_client_kit`, `path: ^1.9.0` | — |
| `apps/codelab_cli` (6) | codelab — terminal ACP client with REPL and headless modes. | `acp_client_core`, `acp_client_io`, `acp_client_kit`, `acp_transports`, `args: ^2.6.0`, `structured_log: 0.3.1`; этап 7 — `codelab_embedded` | `executables: {codelab: codelab}` |
| `codelab_embedded` (7) | Builds the in-process CodeLab agent for ACP clients. | `../acp_transports`, `../codelab_agent_acp`, `../codelab_agent_core`, `../codelab_agent_io` (импортируется только из `lib/io.dart`); этап 8 — `../codelab_agent_mcp` | — |
| `codelab_setup` (7) | Provider setup wizard, settings view models and config access shared by codelab_app and codelab_cli. | `../codelab_agent_core`, `http: ^1.2.0`, `meta: ^1.16.0`, `../codelab_agent_io` (импортируется только из `lib/io.dart`) | — |
| `codelab_agent_mcp` (8) | MCP client for the CodeLab agent core — streamable HTTP and stdio via host port. | `../codelab_agent_core`, `http: ^1.2.0` | — |
| `codelab_agent_web` (10) | Browser adapters for the CodeLab agent core — IndexedDB env and session store. | `../codelab_agent_core`, `web` (версия — при создании) | — |

Пример полного файла:

```yaml
# packages/dart/codelab_agent_core/pubspec.yaml
name: codelab_agent_core
description: Embeddable pure Dart CodeLab agent core — LLM, loop, tools, permissions, sessions.
version: 0.1.0
publish_to: none
resolution: workspace

environment:
  sdk: ">=3.8.0 <4.0.0"

dependencies:            # allowlist PKG-2; расширение — только через OpenSpec
  async: ^2.12.0
  collection: ^1.19.0
  http: ^1.2.0
  meta: ^1.16.0

dev_dependencies:
  lints: ^6.0.0
  test: ^1.26.3
```

`args` — новая зависимость для разбора командной строки агента и CLI; добавляется в OpenSpec
change этапа 4 с обоснованием (стандартный пакет для Dart-команд, альтернатив в проекте нет).

---

← [9. План миграции](09-00-migration-plan.md) · [Оглавление](../dart-agent-and-clients.md) · [9.6. Этап 1 — LLM](09-06-stage-1-llm.md) →
