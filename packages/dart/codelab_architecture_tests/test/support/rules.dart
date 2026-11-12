/// Import rules for every guarded package — one table for the whole
/// repository (dart-agent-and-clients §4.1, agent-core-architecture §1.4).
library;

/// URI prefixes that break web compilation or pull in Flutter.
const webUnsafe = [
  'dart:io',
  'dart:isolate',
  'dart:ffi',
  'dart:html',
  'dart:js_interop',
  'package:web/',
  'package:flutter/',
  'package:codelab_acp_transports/io.dart',
];

final class PackageRule {
  const PackageRule(
    this.dir, {
    required this.forbidden,
    this.exclude = const [],
    this.sealExclude = true,
  });

  /// A package (its `lib/` is scanned) or a directory inside `lib/`,
  /// relative to the repository root.
  final String dir;

  /// Forbidden URI prefixes.
  final List<String> forbidden;

  /// Outside the rule: a file path or a directory prefix ending with `/`,
  /// relative to [dir] (an IO entry point and its implementation).
  final List<String> exclude;

  /// `true` — files outside [exclude] must not reference files inside it
  /// (agent-core-architecture §1.4); `false` — [exclude] only lifts the
  /// prohibitions (a directory allowed to use one package).
  final bool sealExclude;
}

/// Транзитивные пакеты `gpt_markdown`, запрещённые в kit и app
/// (design.md change `add-desktop-markdown`, D10).
const _markdownTransitive = [
  'package:material_ui/',
  'package:cupertino_ui/',
  'package:val_highlight_flutter/',
  'package:val_latex_flutter/',
  'package:flutter_svg/',
];

const rules = [
  PackageRule(
    'packages/dart/codelab_agent_core',
    forbidden: [
      ...webUnsafe,
      'package:codelab_acp_protocol/',
      'package:codelab_acp_transports/',
      // CFG-5: разборщики конфигурации — только в codelab_agent_io, ядро
      // получает готовое ConfigTree. Allowlist PKG-2 их и так не пустит, но
      // правило импорта даёт точное сообщение и ловит транзитивный export
      // (change `add-agent-configuration`, D1).
      'package:yaml/',
      'package:yaml_edit/',
      'package:toml/',
    ],
  ),
  PackageRule(
    'packages/dart/codelab_acp_transports',
    forbidden: webUnsafe,
    exclude: ['lib/io.dart', 'lib/src/io/'],
  ),
  PackageRule('packages/dart/codelab_client_acp', forbidden: webUnsafe),
  // Общий клиентский слой app и CLI — чистый Dart и web-безопасен; IO-адаптеры
  // клиента — в codelab_client_io (design D11 change `extract-acp-client-kit`).
  PackageRule('packages/dart/codelab_client_core', forbidden: webUnsafe),
  // dart:io-адаптеры клиента для app и CLI: dart:io и IO-транспорты разрешены,
  // Flutter — нет (design D11 change `extract-acp-client-kit`).
  PackageRule(
    'packages/dart/codelab_client_io',
    forbidden: ['package:flutter/'],
  ),
  PackageRule(
    'packages/dart/codelab_agent_io',
    forbidden: [
      'package:flutter/',
      'package:codelab_acp_',
      'package:codelab_client_',
    ],
  ),
  // Сценарий модели (`LlmScript`, слой провайдеров сценария, `CwdTrackingStore`)
  // живёт в `lib/testing.dart` и `lib/src/scripted/`; основной барель и остальной
  // код пакета на них не ссылаются, поэтому сценарий структурно не попадает в
  // рабочую сборку клиентов через `codelab_embedded/io.dart` (design.md change
  // `add-embedded-agent-mode`, D8, задача 2.9).
  PackageRule(
    'packages/dart/codelab_agent_io',
    forbidden: [],
    exclude: ['lib/testing.dart', 'lib/src/scripted/'],
  ),
  // `package:codelab_agent_io/testing.dart` — только `lib/src/testing/` моста
  // встроенного агента (`io.dart` и остальной `lib/` — нет); бинарь
  // `apps/codelab_agent` (флаг `--llm-script`) и тесты правилом не охвачены
  // (сторож сканирует только `lib/` пакетов).
  PackageRule(
    'packages/dart/codelab_embedded/lib',
    // `package:codelab_agent_mcp/testing.dart` (фейковый MCP-сервер) — тоже
    // только слой `testing` моста (`FakeMcpHttpHost`; change
    // `add-provider-setup-ui`, Q28).
    forbidden: [
      'package:codelab_agent_io/testing.dart',
      'package:codelab_agent_mcp/testing.dart',
    ],
    // Seal: `io.dart` и `src/io/` не ссылаются на `testing.dart` и
    // `src/testing/` ни пакетным, ни относительным путём (D3, D8).
    exclude: ['testing.dart', 'src/testing/'],
  ),
  // ACP-сервер агента обслуживает любой транспорт: транспорты и локальный
  // листинг передаёт хост (PKG-3).
  PackageRule('packages/dart/codelab_agent_acp', forbidden: webUnsafe),
  PackageRule('apps/codelab_desktop', forbidden: ['package:codelab_agent_']),
  // Бинарь агента — чистый Dart и composition root: IO-транспорты ему
  // разрешены, Flutter и клиентские пакеты — нет (design.md change
  // `add-codelab-agent-binary`, D11). HOST-6 — host_assembly_guard_test.dart.
  PackageRule(
    'apps/codelab_agent',
    forbidden: [
      'package:flutter/',
      'package:fluent_ui/',
      'package:codelab_client_acp/',
      'package:codelab_ui/',
    ],
  ),
  // MCP-клиент агента — web-безопасен, `lib/testing.dart` тоже; ему нельзя
  // ACP, клиентские пакеты и IO-пакет агента (PKG-3; design.md change
  // `add-agent-mcp-client`, D14).
  PackageRule(
    'packages/dart/codelab_agent_mcp',
    forbidden: [
      ...webUnsafe,
      'package:codelab_acp_',
      'package:codelab_client_',
      'package:codelab_agent_io/',
    ],
  ),
  // Терминальный клиент — чистый Dart и composition root: dart:io и
  // IO-транспорты разрешены, Flutter, UI и ядро агента — нет (design.md change
  // `add-codelab-cli`, D3).
  PackageRule(
    'apps/codelab_cli',
    forbidden: [
      'package:flutter/',
      'package:fluent_ui/',
      'package:codelab_ui/',
      'package:codelab_agent_',
    ],
  ),
  // Тестовый пакет — только драйверу фикстур `test-scenario` (design.md
  // change `add-codelab-cli`, D3).
  PackageRule(
    'apps/codelab_cli/lib/src',
    forbidden: ['package:codelab_acp_testing/'],
    exclude: ['scenario/'],
    sealExclude: false,
  ),
  // dart_tui — только адаптеру полноэкранного режима `lib/src/tui/`;
  // остальной CLI запускает его через `TuiRunner` (design.md change
  // `add-cli-tui`, D3).
  PackageRule(
    'apps/codelab_cli/lib/src',
    forbidden: ['package:dart_tui/'],
    exclude: ['tui/'],
    sealExclude: false,
  ),
  // IO-барель моста настроек агента — только `run.dart` (`codelab config
  // check`); остальной CLI не знает о нём (design.md change
  // `add-agent-configuration`, D14).
  PackageRule(
    'apps/codelab_cli/lib/src',
    forbidden: ['package:codelab_setup/io.dart'],
    exclude: ['run.dart'],
    sealExclude: false,
  ),
  // IO-барель встроенного агента — только composition root CLI; остальной код
  // получает агента через `EmbeddedTransportResolver` (design.md change
  // `add-embedded-agent-mode`, D3; workspace-architecture «IO-барель
  // встроенного агента вне composition root»). Правило на весь `lib/`, чтобы
  // барель `lib/codelab_cli.dart` не мог его реэкспортировать; точка входа
  // `bin/` — следующим правилом.
  PackageRule(
    'apps/codelab_cli/lib',
    forbidden: ['package:codelab_embedded/io.dart'],
    exclude: ['src/composition_root.dart'],
    sealExclude: false,
  ),
  // Сценарий модели встроенного агента — только драйверу фикстур
  // `test-scenario` (`lib/src/scenario/`), как `codelab_acp_testing` (D3, D8):
  // тестовый код не попадает в остальной рабочий код CLI.
  PackageRule(
    'apps/codelab_cli/lib',
    forbidden: ['package:codelab_embedded/testing.dart'],
    exclude: ['src/scenario/'],
    sealExclude: false,
  ),
  // Точка входа рабочего бинаря не знает ни IO-барель, ни сценарий модели:
  // сборка агента — в composition root.
  PackageRule(
    'apps/codelab_cli/bin',
    forbidden: [
      'package:codelab_embedded/io.dart',
      'package:codelab_embedded/testing.dart',
    ],
  ),
  // Ядро экрана — чистые `reduce` и `render`: ни пакета TUI, ни dart:io
  // (TUI-5; design.md change `add-cli-tui`, D3).
  PackageRule(
    'apps/codelab_cli/lib/src/tui/core',
    forbidden: ['package:dart_tui/', 'dart:io'],
  ),
  // Встроенный агент (мост между сторонами без префикса стороны, ADR-0002;
  // design.md change `add-embedded-agent-mode`, D3). Основной барель чист:
  // web-безопасен (`webUnsafe`), не знает IO-пакет агента и клиентские пакеты.
  // `lib/io.dart` и `lib/src/io/` (настольный открыватель) и `lib/testing.dart`
  // с `lib/src/testing/` (сценарий модели, D8) вне запретов, но без ссылок
  // снаружи (sealExclude).
  PackageRule(
    'packages/dart/codelab_embedded',
    forbidden: [
      ...webUnsafe,
      'package:codelab_agent_io/',
      'package:codelab_client_',
    ],
    exclude: [
      'lib/io.dart',
      'lib/src/io/',
      'lib/testing.dart',
      'lib/src/testing/',
    ],
  ),
  // `exclude` выше снимает запреты целиком; Flutter, UI и клиентские пакеты не
  // нужны и `io.dart` с `testing.dart` (мост не зависит от клиентов).
  PackageRule(
    'packages/dart/codelab_embedded',
    forbidden: [
      'package:flutter/',
      'package:fluent_ui/',
      'package:codelab_ui/',
      'package:codelab_client_',
    ],
  ),
  // Правила CLI на `codelab_embedded/io.dart` и `testing.dart` — выше (задача
  // 3.4). Десктопный клиент: IO-барель встроенного агента — только composition
  // root `lib/app/` (workspace-architecture «IO-барель встроенного агента вне
  // composition root»; design.md change `add-embedded-agent-mode`, D3, задача
  // 4.4); виджеты и Cubit-ы получают агента через `EmbeddedTransportResolver`.
  PackageRule(
    'apps/codelab_desktop/lib',
    forbidden: ['package:codelab_embedded/io.dart'],
    exclude: ['app/'],
    sealExclude: false,
  ),
  // Сценарий модели не попадает в приложение вообще, `lib/app/` тоже: тестам
  // его даёт шов `createCodeLabRootScope(embeddedOpener:)` (testing-quality
  // «Тестовый сценарий не попадает в app»; D3, D8).
  PackageRule(
    'apps/codelab_desktop/lib',
    forbidden: ['package:codelab_embedded/testing.dart'],
  ),
  // Мост настроек агента для клиентов (dart-agent-and-clients §12.4.2; design.md
  // change `add-agent-configuration`, D14): основной барель чист и не знает
  // IO-пакет агента, `lib/io.dart` и `lib/src/io/` — вне запретов
  // `webUnsafe`, но без ссылок снаружи (sealExclude).
  PackageRule(
    'packages/dart/codelab_setup',
    forbidden: [
      ...webUnsafe,
      'package:codelab_agent_io/',
      'package:codelab_acp_',
      'package:codelab_client_',
    ],
    exclude: ['lib/io.dart', 'lib/src/io/'],
  ),
  // `exclude` выше снимает запреты целиком; Flutter, ACP и клиентские пакеты
  // не нужны и IO-барелю моста.
  PackageRule(
    'packages/dart/codelab_setup',
    forbidden: [
      'package:flutter/',
      'package:codelab_acp_',
      'package:codelab_client_',
      'package:codelab_agent_io/testing.dart',
    ],
  ),
  // Клиент HTTP для `dart:io` и браузера — только `io.dart` моста настроек:
  // основной барель проверяет `/models` поверх абстрактного `http.Client`
  // (`package:http/http.dart` web-безопасен) и обязан собираться в JS и Wasm;
  // `IOClient` создаёт `ioProviderCheck()` (workspace-architecture «http в
  // мосте настроек»; design.md change `add-provider-setup-ui`, D8, D20).
  PackageRule(
    'packages/dart/codelab_setup',
    forbidden: [
      'package:http/io_client.dart',
      'package:http/browser_client.dart',
    ],
    exclude: ['lib/io.dart', 'lib/src/io/'],
    sealExclude: false,
  ),
  // IO-барель моста настроек в десктопном клиенте: только composition root
  // `lib/app/`, как `codelab_embedded/io.dart` (workspace-architecture
  // «IO-барель моста настроек вне composition root app»; design.md change
  // `add-provider-setup-ui`, D20). Cubit-ы и виджеты получают хранилище секретов
  // портом `ProfileSecrets` kit, а не этим барелем.
  PackageRule(
    'apps/codelab_desktop/lib',
    forbidden: ['package:codelab_setup/io.dart'],
    exclude: ['app/'],
    sealExclude: false,
  ),
  // Терминал пользователя (design.md change `add-integrated-terminal`, D11).
  // Модель эмулятора `xterm2_core` — чистый Dart: её держит feature `terminal`
  // (Cubit-ы владеют `Terminal`), остальной код app модель не импортирует.
  PackageRule(
    'apps/codelab_desktop/lib',
    forbidden: ['package:xterm2_core/'],
    exclude: ['features/terminal/'],
    sealExclude: false,
  ),
  // Виджет `TerminalView` из `xterm2` — только presentation терминала:
  // application получает модель из `xterm2_core` и не импортирует пакет
  // рендера напрямую. Это запрет ПРЯМЫХ импортов: транзитивно application
  // через порты `core/platform` всё равно зависит от Flutter-пакета app, а
  // чистоту application от `package:flutter/` держит правило ниже (D11, D3).
  PackageRule(
    'apps/codelab_desktop/lib',
    forbidden: ['package:xterm2/'],
    exclude: ['features/terminal/presentation/'],
    sealExclude: false,
  ),
  // PTY-пакет — нативный API и инфраструктура (`AGENTS.md` §11,
  // `platform-integration.md`): только адаптер `UserShellLauncher`; остальной
  // код видит порт (D2, D11).
  PackageRule(
    'apps/codelab_desktop/lib',
    forbidden: ['package:pty2/'],
    exclude: ['core/platform/user_shell_launcher.dart'],
    sealExclude: false,
  ),
  // Открытие адреса во внешнем приложении — нативный API: `url_launcher` только
  // за портом `ExternalLinkOpener` в `core/platform/` (D11, Q16).
  PackageRule(
    'apps/codelab_desktop/lib',
    forbidden: ['package:url_launcher/'],
    exclude: ['core/platform/'],
    sealExclude: false,
  ),
  // Application терминала не знает Flutter (D11, правило 3; задача 2.0): модель
  // эмулятора — чистый Dart из `xterm2_core`, виджеты — только presentation.
  PackageRule(
    'apps/codelab_desktop/lib/features/terminal/application',
    forbidden: ['package:flutter/'],
  ),
  // ZModem выключен (D3, D11 правило 5): `xterm.dart` реэкспортирует
  // `zmodem.dart`, поэтому запрещены пакет и оба пути; presentation берёт
  // `TerminalView` из `package:xterm2/ui.dart`.
  PackageRule(
    'apps/codelab_desktop/lib',
    forbidden: [
      'package:zmodem/',
      'package:xterm2/xterm.dart',
      'package:xterm2/zmodem.dart',
    ],
    sealExclude: false,
  ),
  // Presentation настроек не знает ни `dart:io`, ни IO-барель моста: файлы,
  // процессы и хранилище секретов — дело infrastructure и composition root
  // (workspace-architecture «dart:io в presentation настроек»; §12.4.2,
  // SETUP-9; `AGENTS.md` §6).
  PackageRule(
    'apps/codelab_desktop/lib/features/settings/presentation',
    forbidden: ['dart:io', 'package:codelab_setup/io.dart'],
  ),
  // Markdown в ленте desktop (design.md change `add-desktop-markdown`, D2,
  // D10). Парсер `gpt_markdown` и движок подсветки `val_highlight` - только
  // слою `lib/src/rendering/` kit: при замене пакета меняется один каталог, а
  // остальной kit и app получают готовые виджеты.
  PackageRule(
    'packages/flutter/codelab_ui/lib',
    forbidden: ['package:gpt_markdown/', 'package:val_highlight/'],
    exclude: ['src/rendering/'],
    sealExclude: false,
  ),
  // Эти пакеты приходят транзитивно с `gpt_markdown`, но тянут Material,
  // Cupertino, SVG-загрузку и собственные виджеты подсветки: интерфейс -
  // Fluent, SVG по сети не грузим (D4, D6). Запрещены в kit и app целиком,
  // `rendering/` не исключён. Префиксы с `/` на конце: `val_highlight/` не
  // совпадает с `val_highlight_flutter/`.
  PackageRule(
    'packages/flutter/codelab_ui/lib',
    forbidden: _markdownTransitive,
  ),
  PackageRule('apps/codelab_desktop/lib', forbidden: _markdownTransitive),
  // Открытие внешних ссылок - инфраструктура: `url_launcher` только в порту
  // `core/platform/` app; Cubit-ы и виджеты идут через `ExternalLinkOpener`
  // (D5; `platform-integration.md`).
  PackageRule(
    'apps/codelab_desktop/lib',
    forbidden: ['package:url_launcher/'],
    exclude: ['core/platform/'],
    sealExclude: false,
  ),
  // Панель Files: чтение файлов — порт `ProjectFiles` kit и `IoProjectFiles`
  // из `codelab_client_io`, который собирает только composition root
  // `lib/app/`; feature не знает `dart:io` во всех слоях (design.md change
  // `add-file-preview-and-tree`, D10; `AGENTS.md` §6, §11).
  PackageRule(
    'apps/codelab_desktop/lib/features/project_files',
    forbidden: ['dart:io'],
  ),
];
