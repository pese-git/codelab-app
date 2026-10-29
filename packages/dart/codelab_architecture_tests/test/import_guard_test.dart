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
}
