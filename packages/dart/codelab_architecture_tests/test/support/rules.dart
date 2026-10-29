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

const rules = [
  PackageRule(
    'packages/dart/codelab_agent_core',
    forbidden: [
      ...webUnsafe,
      'package:codelab_acp_protocol/',
      'package:codelab_acp_transports/',
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
  // Ядро экрана — чистые `reduce` и `render`: ни пакета TUI, ни dart:io
  // (TUI-5; design.md change `add-cli-tui`, D3).
  PackageRule(
    'apps/codelab_cli/lib/src/tui/core',
    forbidden: ['package:dart_tui/', 'dart:io'],
  ),
  // stage 7: codelab_embedded — webUnsafe, exclude: ['lib/io.dart', 'lib/src/io/'];
  //   apps/codelab_desktop — ['package:codelab_agent_'] already above
  // stage 7: codelab_setup — [...webUnsafe, 'package:codelab_agent_io/', 'package:codelab_acp_', 'package:codelab_client_', 'package:flutter/'],
  //   exclude: ['lib/io.dart', 'lib/src/io/'];
  //   apps/codelab_desktop/lib/features/settings/presentation — ['package:codelab_setup/io.dart', 'dart:io'] (§12.4.2, SETUP-9)
];
