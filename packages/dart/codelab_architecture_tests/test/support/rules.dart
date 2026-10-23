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
  'package:acp_transports/io.dart',
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
      'package:acp_protocol/',
      'package:acp_transports/',
    ],
  ),
  PackageRule(
    'packages/dart/acp_transports',
    forbidden: webUnsafe,
    exclude: ['lib/io.dart', 'lib/src/io/'],
  ),
  PackageRule('packages/dart/acp_client_core', forbidden: webUnsafe),
  PackageRule('apps/codelab_app', forbidden: ['package:codelab_agent_']),
  // stage 2: codelab_agent_io — ['package:flutter/', 'package:acp_']
  // stage 4: codelab_agent_acp — webUnsafe; stage 8: codelab_agent_mcp — webUnsafe
  // stage 5: acp_client_kit — webUnsafe; acp_client_io — ['package:flutter/']
  // stage 6: apps/codelab_cli — ['package:flutter/', 'package:codelab_agent_'];
  //   apps/codelab_cli/lib/src — ['package:dart_tui/'], exclude: ['tui/'], sealExclude: false
  //   (dart_tui only in lib/src/tui/, §12.2.7; the rest of the CLI goes through TuiRunner)
  // stage 7: codelab_embedded — webUnsafe, exclude: ['lib/io.dart', 'lib/src/io/'];
  //   apps/codelab_app — ['package:codelab_agent_'] already above
  // stage 7: codelab_setup — [...webUnsafe, 'package:codelab_agent_io/', 'package:acp_', 'package:flutter/'],
  //   exclude: ['lib/io.dart', 'lib/src/io/'];
  //   apps/codelab_app/lib/features/settings/presentation — ['package:codelab_setup/io.dart', 'dart:io'] (§12.4.2, SETUP-9)
];
