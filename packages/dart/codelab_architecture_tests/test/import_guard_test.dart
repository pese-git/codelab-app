import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:test/test.dart';

import 'support/import_scanner.dart';
import 'support/repo_root.dart';
import 'support/rules.dart';

void main() {
  final root = repoRoot();

  for (final rule in rules) {
    test('${rule.dir}: no forbidden imports in lib/', () {
      expect(
        Directory(p.join(root, rule.dir)).existsSync(),
        isTrue,
        reason: '${rule.dir} is listed in rules.dart but does not exist',
      );
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

  // CFG-5: разборщики конфигурации живут только в codelab_agent_io; ядро
  // получает уже разобранные деревья (change `add-agent-configuration`, D1).
  test('reports a configuration parser imported by the agent core', () {
    final tmp = Directory.systemTemp.createTempSync('guard_cfg_');
    addTearDown(() => tmp.deleteSync(recursive: true));
    File(p.join(tmp.path, 'lib', 'src', 'config', 'reader.dart'))
      ..createSync(recursive: true)
      ..writeAsStringSync("import 'package:yaml/yaml.dart';\n");
    final rule = rules.firstWhere(
      (r) => r.dir == 'packages/dart/codelab_agent_core',
    );

    final violations = scan(
      tmp.path,
      PackageRule('.', forbidden: rule.forbidden),
    );

    expect(
      violations.single,
      endsWith('lib/src/config/reader.dart:1 -> package:yaml/yaml.dart'),
    );
  });

  test('reports ACP imported by the IO package of the agent', () {
    final tmp = Directory.systemTemp.createTempSync('guard_io_');
    addTearDown(() => tmp.deleteSync(recursive: true));
    File(p.join(tmp.path, 'lib', 'src', 'env.dart'))
      ..createSync(recursive: true)
      ..writeAsStringSync(
        "import 'package:codelab_acp_protocol/codelab_acp_protocol.dart';\n",
      );
    final rule = rules.firstWhere(
      (r) => r.dir == 'packages/dart/codelab_agent_io',
    );

    final violations = scan(
      tmp.path,
      PackageRule('.', forbidden: rule.forbidden),
    );

    expect(
      violations.single,
      endsWith(
        'lib/src/env.dart:1 -> package:codelab_acp_protocol/codelab_acp_protocol.dart',
      ),
    );
  });

  test('reports dart:io and the IO transports in the ACP server', () {
    final tmp = Directory.systemTemp.createTempSync('guard_acp_');
    addTearDown(() => tmp.deleteSync(recursive: true));
    File(p.join(tmp.path, 'lib', 'src', 'server.dart'))
      ..createSync(recursive: true)
      ..writeAsStringSync(
        "import 'dart:io';\nimport 'package:codelab_acp_transports/io.dart';\n",
      );
    final rule = rules.firstWhere(
      (r) => r.dir == 'packages/dart/codelab_agent_acp',
    );

    final violations = scan(
      tmp.path,
      PackageRule('.', forbidden: rule.forbidden),
    );

    expect(violations, hasLength(2));
    expect(violations.first, endsWith('lib/src/server.dart:1 -> dart:io'));
  });

  test('reports dart:io and ACP in the MCP client of the agent', () {
    final tmp = Directory.systemTemp.createTempSync('guard_mcp_');
    addTearDown(() => tmp.deleteSync(recursive: true));
    File(p.join(tmp.path, 'lib', 'src', 'client.dart'))
      ..createSync(recursive: true)
      ..writeAsStringSync(
        "import 'dart:io';\n"
        "import 'package:codelab_acp_protocol/codelab_acp_protocol.dart';\n",
      );
    final rule = rules.firstWhere(
      (r) => r.dir == 'packages/dart/codelab_agent_mcp',
    );

    final violations = scan(
      tmp.path,
      PackageRule('.', forbidden: rule.forbidden),
    );

    // Клиент MCP web-безопасен и не знает ACP (PKG-3; design.md change
    // `add-agent-mcp-client`, D14).
    expect(violations, hasLength(2));
    expect(violations.first, endsWith('lib/src/client.dart:1 -> dart:io'));
  });

  test('reports the IO package of the agent and client packages in the MCP '
      'client', () {
    final rule = rules.firstWhere(
      (r) => r.dir == 'packages/dart/codelab_agent_mcp',
    );

    expect(
      rule.forbidden,
      containsAll([
        'package:codelab_client_',
        'package:codelab_agent_io/',
        'package:flutter/',
      ]),
    );
  });

  test('reports Flutter and client packages in the agent binary', () {
    final tmp = Directory.systemTemp.createTempSync('guard_bin_');
    addTearDown(() => tmp.deleteSync(recursive: true));
    File(p.join(tmp.path, 'lib', 'src', 'serve.dart'))
      ..createSync(recursive: true)
      ..writeAsStringSync(
        "import 'package:flutter/widgets.dart';\n"
        "import 'package:codelab_client_acp/codelab_client_acp.dart';\n"
        "import 'package:codelab_acp_transports/io.dart';\n",
      );
    final rule = rules.firstWhere((r) => r.dir == 'apps/codelab_agent');

    final violations = scan(
      tmp.path,
      PackageRule('.', forbidden: rule.forbidden),
    );

    // IO-транспорты бинарю разрешены: он composition root (AGENTS.md §5).
    expect(violations, hasLength(2));
    expect(
      violations.first,
      endsWith('lib/src/serve.dart:1 -> package:flutter/widgets.dart'),
    );
  });

  test('reports dart:io, Flutter and the IO transports in the client kit', () {
    final tmp = Directory.systemTemp.createTempSync('guard_kit_');
    addTearDown(() => tmp.deleteSync(recursive: true));
    File(p.join(tmp.path, 'lib', 'src', 'workspace.dart'))
      ..createSync(recursive: true)
      ..writeAsStringSync(
        "import 'dart:io';\n"
        "import 'package:flutter/foundation.dart';\n"
        "import 'package:codelab_acp_transports/io.dart';\n"
        "import 'package:codelab_client_acp/codelab_client_acp.dart';\n",
      );
    final rule = rules.firstWhere(
      (r) => r.dir == 'packages/dart/codelab_client_core',
    );

    final violations = scan(
      tmp.path,
      PackageRule('.', forbidden: rule.forbidden),
    );

    // Kit — чистый Dart и web-безопасен (design D11 change
    // `extract-acp-client-kit`); ядро клиента ему разрешено.
    expect(violations, hasLength(3));
    expect(violations.first, endsWith('lib/src/workspace.dart:1 -> dart:io'));
  });

  test('reports Flutter in the client IO package, but not dart:io', () {
    final tmp = Directory.systemTemp.createTempSync('guard_client_io_');
    addTearDown(() => tmp.deleteSync(recursive: true));
    File(p.join(tmp.path, 'lib', 'src', 'stores.dart'))
      ..createSync(recursive: true)
      ..writeAsStringSync(
        "import 'dart:io';\n"
        "import 'package:codelab_acp_transports/io.dart';\n"
        "import 'package:flutter/foundation.dart';\n",
      );
    final rule = rules.firstWhere(
      (r) => r.dir == 'packages/dart/codelab_client_io',
    );

    final violations = scan(
      tmp.path,
      PackageRule('.', forbidden: rule.forbidden),
    );

    // IO-адаптеры клиента — его единственное место для `dart:io` и
    // IO-транспортов вне app (design D2, D11 change `extract-acp-client-kit`).
    expect(
      violations.single,
      endsWith('lib/src/stores.dart:3 -> package:flutter/foundation.dart'),
    );
  });
  test('reports Flutter and the agent core in the terminal client', () {
    final tmp = Directory.systemTemp.createTempSync('guard_cli_');
    addTearDown(() => tmp.deleteSync(recursive: true));
    File(p.join(tmp.path, 'lib', 'src', 'run.dart'))
      ..createSync(recursive: true)
      ..writeAsStringSync(
        "import 'dart:io';\n"
        "import 'package:codelab_acp_transports/io.dart';\n"
        "import 'package:codelab_agent_core/codelab_agent_core.dart';\n"
        "import 'package:flutter/foundation.dart';\n",
      );
    final rule = rules.firstWhere((r) => r.dir == 'apps/codelab_cli');

    final violations = scan(
      tmp.path,
      PackageRule('.', forbidden: rule.forbidden),
    );

    // CLI — composition root: dart:io и IO-транспорты ему разрешены, ядро
    // агента и Flutter — нет (design.md change `add-codelab-cli`, D3).
    expect(violations, hasLength(2));
    expect(
      violations.first,
      endsWith(
        'lib/src/run.dart:3 -> package:codelab_agent_core/codelab_agent_core.dart',
      ),
    );
  });

  test('allows the testing package only in the scenario driver of the '
      'terminal client', () {
    final tmp = Directory.systemTemp.createTempSync('guard_cli_testing_');
    addTearDown(() => tmp.deleteSync(recursive: true));
    const import =
        "import 'package:codelab_acp_testing/codelab_acp_testing.dart';\n";
    File(p.join(tmp.path, 'lib', 'src', 'repl', 'repl.dart'))
      ..createSync(recursive: true)
      ..writeAsStringSync(import);
    File(p.join(tmp.path, 'lib', 'src', 'scenario', 'driver.dart'))
      ..createSync(recursive: true)
      ..writeAsStringSync(import);
    final rule = rules.firstWhere((r) => r.dir == 'apps/codelab_cli/lib/src');

    final violations = scan(
      tmp.path,
      PackageRule(
        'lib/src',
        forbidden: rule.forbidden,
        exclude: rule.exclude,
        sealExclude: rule.sealExclude,
      ),
    );

    // `test-scenario` — рабочая команда бинаря, поэтому тестовый пакет ему
    // разрешён, но только драйверу фикстур (design.md change
    // `add-codelab-cli`, D3).
    expect(
      violations.single,
      endsWith(
        'lib/src/repl/repl.dart:1 -> '
        'package:codelab_acp_testing/codelab_acp_testing.dart',
      ),
    );
  });

  test('allows the TUI package only in the TUI adapter of the terminal '
      'client', () {
    final tmp = Directory.systemTemp.createTempSync('guard_cli_tui_');
    addTearDown(() => tmp.deleteSync(recursive: true));
    const import = "import 'package:dart_tui/dart_tui.dart';\n";
    for (final file in ['repl/repl.dart', 'tui/tui_app.dart']) {
      File(p.join(tmp.path, 'lib', 'src', file))
        ..createSync(recursive: true)
        ..writeAsStringSync(import);
    }
    File(p.join(tmp.path, 'lib', 'src', 'tui', 'core', 'tui_view.dart'))
      ..createSync(recursive: true)
      ..writeAsStringSync("${import}import 'dart:io';\n");
    final tuiRules = rules.where(
      (r) =>
          r.dir.startsWith('apps/codelab_cli/lib/src') &&
          r.forbidden.contains('package:dart_tui/'),
    );

    final violations = [
      for (final rule in tuiRules)
        ...scan(
          tmp.path,
          PackageRule(
            rule.dir.replaceFirst('apps/codelab_cli/', ''),
            forbidden: rule.forbidden,
            exclude: rule.exclude,
            sealExclude: rule.sealExclude,
          ),
        ),
    ];

    // dart_tui — только адаптер TUI, а ядро экрана `tui/core/` не знает ни
    // пакета, ни dart:io (design.md change `add-cli-tui`, D3; TUI-5).
    expect(violations, hasLength(3));
    expect(
      violations,
      containsAll([
        endsWith('lib/src/repl/repl.dart:1 -> package:dart_tui/dart_tui.dart'),
        endsWith(
          'lib/src/tui/core/tui_view.dart:1 -> package:dart_tui/dart_tui.dart',
        ),
        endsWith('lib/src/tui/core/tui_view.dart:2 -> dart:io'),
      ]),
    );
  });

  // Мост `codelab_setup`: основной барель чистый и не знает IO-пакет агента,
  // `lib/io.dart` его импортирует (design.md change `add-agent-configuration`,
  // D14; workspace-architecture «Основной барель моста импортирует IO-пакет
  // агента»).
  List<String> scanSetupBridge(Directory tmp) {
    final setupRules = rules.where(
      (r) => r.dir == 'packages/dart/codelab_setup',
    );
    expect(setupRules, isNotEmpty, reason: 'нет правила codelab_setup');
    return [
      for (final rule in setupRules)
        ...scan(
          tmp.path,
          PackageRule(
            '.',
            forbidden: rule.forbidden,
            exclude: rule.exclude,
            sealExclude: rule.sealExclude,
          ),
        ),
    ];
  }

  test('reports the IO package of the agent in the main barrel of the setup '
      'bridge only', () {
    final tmp = Directory.systemTemp.createTempSync('guard_setup_');
    addTearDown(() => tmp.deleteSync(recursive: true));
    const import = "import 'package:codelab_agent_io/codelab_agent_io.dart';\n";
    for (final file in ['codelab_setup.dart', 'io.dart']) {
      File(p.join(tmp.path, 'lib', file))
        ..createSync(recursive: true)
        ..writeAsStringSync(import);
    }

    final violations = scanSetupBridge(tmp);

    expect(violations, hasLength(1));
    expect(
      violations.single,
      endsWith(
        'lib/codelab_setup.dart:1 -> '
        'package:codelab_agent_io/codelab_agent_io.dart',
      ),
    );
  });

  test('reports dart:io and a reference to io.dart in the main barrel of '
      'the setup bridge', () {
    final tmp = Directory.systemTemp.createTempSync('guard_setup_io_');
    addTearDown(() => tmp.deleteSync(recursive: true));
    File(p.join(tmp.path, 'lib', 'codelab_setup.dart'))
      ..createSync(recursive: true)
      ..writeAsStringSync("import 'dart:io';\nexport 'io.dart';\n");
    File(
      p.join(tmp.path, 'lib', 'io.dart'),
    ).writeAsStringSync("import 'dart:io';\nexport 'src/io/x.dart';\n");
    File(p.join(tmp.path, 'lib', 'src', 'io', 'x.dart'))
      ..createSync(recursive: true)
      ..writeAsStringSync('');

    final violations = scanSetupBridge(tmp);

    // dart:io разрешён только io.dart и src/io/; основной барель не должен
    // ссылаться на них даже относительным путём (sealExclude).
    expect(violations, hasLength(2));
    expect(violations.first, endsWith('lib/codelab_setup.dart:1 -> dart:io'));
    expect(
      violations.last,
      endsWith('lib/codelab_setup.dart:2 -> io.dart (excluded file)'),
    );
  });

  test('reports Flutter, ACP and client packages in io.dart of the setup '
      'bridge', () {
    final tmp = Directory.systemTemp.createTempSync('guard_setup_acp_');
    addTearDown(() => tmp.deleteSync(recursive: true));
    File(p.join(tmp.path, 'lib', 'io.dart'))
      ..createSync(recursive: true)
      ..writeAsStringSync(
        "import 'dart:io';\n"
        "import 'package:codelab_agent_io/codelab_agent_io.dart';\n"
        "import 'package:flutter/foundation.dart';\n"
        "import 'package:codelab_acp_protocol/codelab_acp_protocol.dart';\n"
        "import 'package:codelab_client_core/codelab_client_core.dart';\n",
      );

    final violations = scanSetupBridge(tmp);

    expect(violations, hasLength(3));
    expect(
      violations,
      containsAll([
        endsWith('lib/io.dart:3 -> package:flutter/foundation.dart'),
        endsWith(
          'lib/io.dart:4 -> package:codelab_acp_protocol/codelab_acp_protocol.dart',
        ),
        endsWith(
          'lib/io.dart:5 -> package:codelab_client_core/codelab_client_core.dart',
        ),
      ]),
    );
  });

  test('allows the IO barrel of the setup bridge only in run.dart of the '
      'terminal client', () {
    final tmp = Directory.systemTemp.createTempSync('guard_cli_setup_');
    addTearDown(() => tmp.deleteSync(recursive: true));
    const import = "import 'package:codelab_setup/io.dart';\n";
    File(p.join(tmp.path, 'lib', 'src', 'run.dart'))
      ..createSync(recursive: true)
      ..writeAsStringSync(import);
    File(p.join(tmp.path, 'lib', 'src', 'repl', 'repl.dart'))
      ..createSync(recursive: true)
      ..writeAsStringSync(import);

    final violations = [
      for (final rule in rules.where(
        (r) => r.dir == 'apps/codelab_cli/lib/src',
      ))
        ...scan(
          tmp.path,
          PackageRule(
            'lib/src',
            forbidden: rule.forbidden,
            exclude: rule.exclude,
            sealExclude: rule.sealExclude,
          ),
        ),
    ];

    // `config check` — единственный потребитель моста в CLI; он живёт в
    // `run.dart` (design.md change `add-agent-configuration`, D14).
    expect(
      violations.single,
      endsWith('lib/src/repl/repl.dart:1 -> package:codelab_setup/io.dart'),
    );
  });

  // Встроенный агент `codelab_embedded` (design.md change
  // `add-embedded-agent-mode`, D3): основной барель чист и не знает IO-пакет
  // агента, `io.dart` и `testing.dart` вне запретов `webUnsafe`, но без ссылок
  // снаружи (sealExclude). Пакета на момент итерации 1.7 ещё нет: правила
  // проверяются на временном каталоге, а общий цикл выше краснеет по причине
  // «пакет не существует» до задачи 1.9.
  List<String> scanEmbedded(Directory tmp) {
    final embeddedRules = rules.where(
      (r) => r.dir == 'packages/dart/codelab_embedded',
    );
    expect(
      embeddedRules,
      hasLength(2),
      reason: 'нужны два правила packages/dart/codelab_embedded',
    );
    return [
      for (final rule in embeddedRules)
        ...scan(
          tmp.path,
          PackageRule(
            '.',
            forbidden: rule.forbidden,
            exclude: rule.exclude,
            sealExclude: rule.sealExclude,
          ),
        ),
    ];
  }

  void writeLib(Directory tmp, String file, String content) {
    File(p.join(tmp.path, 'lib', file))
      ..createSync(recursive: true)
      ..writeAsStringSync(content);
  }

  test('reports the IO package of the agent in the main barrel of the '
      'embedded agent only', () {
    final tmp = Directory.systemTemp.createTempSync('guard_embedded_');
    addTearDown(() => tmp.deleteSync(recursive: true));
    const import = "import 'package:codelab_agent_io/codelab_agent_io.dart';\n";
    for (final file in [
      'codelab_embedded.dart',
      'src/agent.dart',
      'io.dart',
      'src/io/opener.dart',
    ]) {
      writeLib(tmp, file, import);
    }

    final violations = scanEmbedded(tmp);

    expect(violations, hasLength(2));
    expect(
      violations,
      containsAll([
        endsWith(
          'lib/codelab_embedded.dart:1 -> '
          'package:codelab_agent_io/codelab_agent_io.dart',
        ),
        endsWith(
          'lib/src/agent.dart:1 -> '
          'package:codelab_agent_io/codelab_agent_io.dart',
        ),
      ]),
    );
  });

  test('reports dart:io and references to io.dart and testing.dart in the '
      'main barrel of the embedded agent', () {
    final tmp = Directory.systemTemp.createTempSync('guard_embedded_io_');
    addTearDown(() => tmp.deleteSync(recursive: true));
    writeLib(
      tmp,
      'codelab_embedded.dart',
      "import 'dart:io';\nexport 'io.dart';\nexport 'testing.dart';\n",
    );
    writeLib(tmp, 'io.dart', "import 'dart:io';\n");
    writeLib(tmp, 'testing.dart', "import 'dart:io';\n");

    final violations = scanEmbedded(tmp);

    expect(violations, hasLength(3));
    expect(
      violations.first,
      endsWith('lib/codelab_embedded.dart:1 -> dart:io'),
    );
    expect(
      violations,
      containsAll([
        endsWith('lib/codelab_embedded.dart:2 -> io.dart (excluded file)'),
        endsWith('lib/codelab_embedded.dart:3 -> testing.dart (excluded file)'),
      ]),
    );
  });

  test('reports Flutter, UI and client packages in io.dart and testing.dart '
      'of the embedded agent', () {
    final tmp = Directory.systemTemp.createTempSync('guard_embedded_ui_');
    addTearDown(() => tmp.deleteSync(recursive: true));
    const imports =
        "import 'package:flutter/foundation.dart';\n"
        "import 'package:fluent_ui/fluent_ui.dart';\n"
        "import 'package:codelab_ui/codelab_ui.dart';\n"
        "import 'package:codelab_client_core/codelab_client_core.dart';\n"
        "import 'package:codelab_agent_io/codelab_agent_io.dart';\n";
    writeLib(tmp, 'io.dart', imports);
    writeLib(tmp, 'testing.dart', imports);

    final violations = scanEmbedded(tmp);

    // Четыре запрета на каждый из двух файлов; IO-пакет агента им разрешён.
    expect(violations, hasLength(8));
    expect(violations, isNot(contains(contains('package:codelab_agent_io/'))));
  });

  test('allows the ACP packages and the web-safe transports in the main '
      'barrel of the embedded agent', () {
    final tmp = Directory.systemTemp.createTempSync('guard_embedded_acp_');
    addTearDown(() => tmp.deleteSync(recursive: true));
    writeLib(
      tmp,
      'codelab_embedded.dart',
      "import 'package:codelab_acp_protocol/codelab_acp_protocol.dart';\n"
          "import 'package:codelab_acp_transports/codelab_acp_transports.dart';\n"
          "import 'package:codelab_agent_acp/codelab_agent_acp.dart';\n"
          "import 'package:codelab_agent_mcp/codelab_agent_mcp.dart';\n"
          "import 'package:codelab_agent_core/codelab_agent_core.dart';\n",
    );

    expect(scanEmbedded(tmp), isEmpty);
  });
}
