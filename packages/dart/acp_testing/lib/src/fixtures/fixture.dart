import 'dart:convert';
import 'dart:io';
import 'dart:isolate';

/// Golden ACP fixture model and loader — format of
/// `docs/architecture/proposals/agent-core/14-golden-fixtures.md` §14.4.
///
/// The loader checks the structure itself (design.md D2): required fields,
/// types, allowed values and unknown keys. `fixtures/acp/_schema.json`
/// describes the same format for authors; `fixtures_schema_sync_test.dart`
/// keeps both key sets equal via [fixtureFormatKeys].

/// Which conformance run takes the fixture (§14.4, `roles`).
enum FixtureRole { agent, client }

/// Frame direction: `c2a` — client → agent, `a2c` — agent → client.
enum FrameDirection { c2a, a2c }

/// Allowed keys of every closed object of the format, by `_schema.json`
/// name: `fixture` is the schema root, the rest are its `$defs`.
const fixtureFormatKeys = <String, Set<String>>{
  'fixture': {
    'id',
    'spec',
    'description',
    'goals',
    'extensions',
    'roles',
    'setup',
    'llm',
    'frames',
    'normalize',
    'after',
  },
  'setup': {
    'cwd',
    'files',
    'profile',
    'mode',
    'config',
    'clientCapabilities',
    'terminal',
    'web',
    'skipInitialize',
  },
  'terminalCommand': {'output', 'exitCode'},
  'frame': {'dir', 'frame', 'unordered', 'note', 'optional', 'repeat', 'match'},
  'llm': {'model', 'steps'},
  'llmModel': {'provider', 'modelId', 'contextWindow'},
  'llmStep': {
    'expect',
    'reply',
    'stopReason',
    'error',
    'delayMs',
    'waitForCancel',
    'usage',
  },
  'llmReplyBlock': {'text', 'thinking', 'toolCall'},
  'llmToolCall': {'id', 'name', 'arguments'},
  'llmError': {'class', 'message'},
  'normalize': {'replace'},
  'replaceRule': {'path', 'regex', 'with'},
  'after': {'files'},
};

/// Allowed `stopReason` of an `llm` step (§14.7).
const fixtureLlmStopReasons = {'stop', 'toolUse', 'length', 'error', 'aborted'};

/// Default working directory of a fixture without `setup.cwd`.
const defaultFixtureCwd = '/work/fixture';

/// A fixture that is incomplete or contradictory. Loading fails loudly
/// instead of producing a false green run (§14.9, step 1).
final class FixtureFormatException implements Exception {
  const FixtureFormatException({
    required this.file,
    required this.path,
    required this.message,
  });

  final String file;

  /// JSON path of the offending field, e.g. `$.frames[1].dir`.
  final String path;
  final String message;

  @override
  String toString() => 'FixtureFormatException: $file: $path: $message';
}

final class AcpFixture {
  const AcpFixture({
    required this.id,
    required this.spec,
    required this.description,
    required this.goals,
    required this.extensions,
    required this.roles,
    required this.setup,
    required this.frames,
    required this.normalize,
    this.llm,
    this.after,
    this.sourcePath,
  });

  /// Parses [json] read from [fileName]; the fixture id must be
  /// `acp/<fileName without .json>`.
  factory AcpFixture.fromJson(
    Map<String, Object?> source, {
    required String fileName,
    String? sourcePath,
  }) {
    final r = _Reader(fileName);
    // Canonical JSON types for every nested value, whatever the caller built.
    final Map<String, Object?> json;
    try {
      json = jsonDecode(jsonEncode(source)) as Map<String, Object?>;
    } on JsonUnsupportedObjectError catch (error) {
      r.fail(r'$', 'is not JSON: ${error.unsupportedObject}');
    }
    const root = r'$';
    r.closed(json, root, 'fixture');

    final expectedId = 'acp/${_stripJsonExtension(fileName)}';
    final id = r.string(json, root, 'id', required: true)!;
    if (id != expectedId) {
      r.fail('$root.id', 'expected "$expectedId" to match the file, got "$id"');
    }

    final spec = r.stringList(json, root, 'spec', required: true)!;
    if (spec.isEmpty) {
      r.fail('$root.spec', 'must be a non-empty list of spec references');
    }

    final rolesPath = '$root.roles';
    final rawRoles = r.stringList(json, root, 'roles');
    final roles = <FixtureRole>{};
    if (rawRoles == null) {
      roles.addAll(FixtureRole.values);
    } else {
      if (rawRoles.isEmpty) {
        r.fail(rolesPath, 'must be a non-empty list');
      }
      for (final (i, name) in rawRoles.indexed) {
        final role = FixtureRole.values.asNameMap()[name];
        if (role == null) {
          r.fail('$rolesPath[$i]', 'expected "agent" or "client", got "$name"');
        }
        if (!roles.add(role)) {
          r.fail(rolesPath, 'duplicate role "$name"');
        }
      }
    }

    final rawFrames = r.list(json, root, 'frames', required: true)!;
    if (rawFrames.isEmpty) {
      r.fail('$root.frames', 'must be a non-empty list');
    }

    return AcpFixture(
      id: id,
      spec: spec,
      description: r.string(json, root, 'description', required: true)!,
      goals: r.stringList(json, root, 'goals') ?? const [],
      extensions: r.stringList(json, root, 'extensions') ?? const [],
      roles: roles,
      setup: FixtureSetup._parse(
        r,
        r.object(json, root, 'setup', required: true)!,
        '$root.setup',
      ),
      llm: switch (r.object(json, root, 'llm')) {
        final llm? => FixtureLlmScript._parse(r, llm, '$root.llm'),
        null => null,
      },
      frames: [
        for (final (i, raw) in rawFrames.indexed)
          FixtureFrame._parse(r, raw, '$root.frames[$i]', i),
      ],
      normalize: switch (r.object(json, root, 'normalize')) {
        final n? => FixtureNormalize._parse(r, n, '$root.normalize'),
        null => const FixtureNormalize(replace: []),
      },
      after: switch (r.object(json, root, 'after')) {
        final a? => FixtureAfter._parse(r, a, '$root.after'),
        null => null,
      },
      sourcePath: sourcePath,
    );
  }

  final String id;

  /// References relative to `docs/acp/protocol/`: `"<file>.md#<anchor>"`.
  final List<String> spec;
  final String description;

  /// Parity goal ids (`agent-parity-goals.md`).
  final List<String> goals;

  /// ACP extensions the fixture uses (§13.12).
  final List<String> extensions;
  final Set<FixtureRole> roles;
  final FixtureSetup setup;

  /// Scripted model for the agent run (§14.7); parsed, not executed here.
  final FixtureLlmScript? llm;
  final List<FixtureFrame> frames;
  final FixtureNormalize normalize;
  final FixtureAfter? after;

  /// File the fixture was loaded from, when it came from disk.
  final String? sourcePath;
}

final class FixtureSetup {
  const FixtureSetup({
    required this.cwd,
    required this.files,
    required this.terminal,
    required this.skipInitialize,
    this.profile,
    this.mode,
    this.config,
    this.clientCapabilities,
    this.web,
  });

  factory FixtureSetup._parse(
    _Reader r,
    Map<String, Object?> json,
    String path,
  ) {
    r.closed(json, path, 'setup');
    final terminal = <String, FixtureTerminalCommand>{};
    final rawTerminal = r.object(json, path, 'terminal');
    if (rawTerminal != null) {
      for (final MapEntry(:key, :value) in rawTerminal.entries) {
        final commandPath = '$path.terminal${_key(key)}';
        final command = r.asObject(value, commandPath);
        r.closed(command, commandPath, 'terminalCommand');
        terminal[key] = FixtureTerminalCommand(
          output: r.string(command, commandPath, 'output') ?? '',
          exitCode: r.integer(command, commandPath, 'exitCode'),
        );
      }
    }

    return FixtureSetup(
      cwd: r.string(json, path, 'cwd') ?? defaultFixtureCwd,
      files: r.stringMap(json, path, 'files') ?? const {},
      profile: r.string(json, path, 'profile'),
      mode: r.string(json, path, 'mode'),
      config: r.object(json, path, 'config'),
      clientCapabilities: r.object(json, path, 'clientCapabilities'),
      terminal: terminal,
      web: r.object(json, path, 'web'),
      skipInitialize: r.boolean(json, path, 'skipInitialize') ?? false,
    );
  }

  /// Working directory of the scenario, written as `${cwd}` in frames.
  final String cwd;

  /// Files of the working directory before the scenario, by relative path.
  final Map<String, String> files;
  final String? profile;
  final String? mode;
  final Map<String, Object?>? config;
  final Map<String, Object?>? clientCapabilities;

  /// Client run only: scripted processes of the client's fake terminal
  /// port, keyed by the command line.
  final Map<String, FixtureTerminalCommand> terminal;

  /// After MVP: fake HTTP answers for web tools (§17.1.10).
  final Map<String, Object?>? web;
  final bool skipInitialize;
}

final class FixtureTerminalCommand {
  const FixtureTerminalCommand({required this.output, this.exitCode});

  final String output;
  final int? exitCode;
}

final class FixtureFrame {
  const FixtureFrame({
    required this.index,
    required this.direction,
    required this.optional,
    required this.repeated,
    this.frame,
    this.unordered,
    this.note,
    this.matchText,
  });

  factory FixtureFrame._parse(_Reader r, Object? raw, String path, int index) {
    final json = r.asObject(raw, path);
    r.closed(json, path, 'frame');

    final dir = r.string(json, path, 'dir', required: true)!;
    final direction = FrameDirection.values.asNameMap()[dir];
    if (direction == null) {
      r.fail('$path.dir', 'expected "c2a" or "a2c", got "$dir"');
    }

    final frame = r.object(json, path, 'frame');
    final unordered = r.list(json, path, 'unordered');
    if ((frame == null) == (unordered == null)) {
      r.fail(path, 'must have exactly one of "frame" or "unordered"');
    }
    if (unordered != null && unordered.isEmpty) {
      r.fail('$path.unordered', 'must be a non-empty list');
    }

    final repeat = r.string(json, path, 'repeat');
    if (repeat != null && repeat != '+') {
      r.fail('$path.repeat', 'expected "+", got "$repeat"');
    }

    String? matchText;
    final match = r.object(json, path, 'match');
    if (match != null) {
      if (repeat == null) {
        r.fail('$path.match', 'is only allowed together with repeat "+"');
      }
      final matchPath = '$path.match';
      if (match.length != 1 || match[r'$text'] is! String) {
        r.fail(matchPath, r'must be {"$text": "<concatenated text>"}');
      }
      matchText = match[r'$text']! as String;
    }

    return FixtureFrame(
      index: index,
      direction: direction,
      frame: frame,
      unordered: unordered == null
          ? null
          : [
              for (final (i, item) in unordered.indexed)
                r.asObject(item, '$path.unordered[$i]'),
            ],
      note: r.string(json, path, 'note'),
      optional: r.boolean(json, path, 'optional') ?? false,
      repeated: repeat != null,
      matchText: matchText,
    );
  }

  /// Position in `frames`, used in failure messages.
  final int index;
  final FrameDirection direction;

  /// JSON-RPC object; may contain matchers (§14.6) and `${…}` variables.
  final Map<String, Object?>? frame;

  /// Instead of [frame]: frames of one direction in any order.
  final List<Map<String, Object?>>? unordered;
  final String? note;
  final bool optional;

  /// `repeat: "+"` — one or more consecutive frames.
  final bool repeated;

  /// `match.$text` — concatenated `content.text` of all repetitions.
  final String? matchText;
}

final class FixtureLlmScript {
  const FixtureLlmScript({required this.steps, this.model});

  factory FixtureLlmScript._parse(
    _Reader r,
    Map<String, Object?> json,
    String path,
  ) {
    r.closed(json, path, 'llm');
    final model = r.object(json, path, 'model');
    if (model != null) {
      final modelPath = '$path.model';
      r.closed(model, modelPath, 'llmModel');
      r.string(model, modelPath, 'provider');
      r.string(model, modelPath, 'modelId');
      r.integer(model, modelPath, 'contextWindow');
    }
    final steps = r.list(json, path, 'steps', required: true)!;
    return FixtureLlmScript(
      model: model,
      steps: [
        for (final (i, step) in steps.indexed)
          FixtureLlmStep._parse(r, step, '$path.steps[$i]'),
      ],
    );
  }

  final Map<String, Object?>? model;
  final List<FixtureLlmStep> steps;
}

/// One model answer of the scripted model (§14.7). Executed by the agent
/// driver from stage 4 (design.md D6); here only its structure is checked.
final class FixtureLlmStep {
  const FixtureLlmStep({
    required this.waitForCancel,
    this.expect,
    this.reply,
    this.stopReason,
    this.error,
    this.delayMs,
    this.usage,
  });

  factory FixtureLlmStep._parse(_Reader r, Object? raw, String path) {
    final json = r.asObject(raw, path);
    r.closed(json, path, 'llmStep');

    final stopReason = r.string(json, path, 'stopReason');
    if (stopReason != null && !fixtureLlmStopReasons.contains(stopReason)) {
      r.fail(
        '$path.stopReason',
        'expected one of ${fixtureLlmStopReasons.join(', ')}, got "$stopReason"',
      );
    }

    final reply = r.list(json, path, 'reply');
    final error = r.object(json, path, 'error');
    if (reply != null && error != null) {
      r.fail(path, 'must have "reply" or "error", not both');
    }

    final blocks = <Map<String, Object?>>[];
    for (final (i, item) in (reply ?? const []).indexed) {
      final blockPath = '$path.reply[$i]';
      final block = r.asObject(item, blockPath);
      r.closed(block, blockPath, 'llmReplyBlock');
      if (block.length != 1) {
        r.fail(blockPath, 'must have exactly one of text, thinking, toolCall');
      }
      r.string(block, blockPath, 'text');
      r.string(block, blockPath, 'thinking');
      final toolCall = r.object(block, blockPath, 'toolCall');
      if (toolCall != null) {
        final callPath = '$blockPath.toolCall';
        r.closed(toolCall, callPath, 'llmToolCall');
        r.string(toolCall, callPath, 'id', required: true);
        r.string(toolCall, callPath, 'name', required: true);
        r.object(toolCall, callPath, 'arguments', required: true);
      }
      blocks.add(block);
    }

    if (error != null) {
      final errorPath = '$path.error';
      r.closed(error, errorPath, 'llmError');
      r.string(error, errorPath, 'class', required: true);
      r.string(error, errorPath, 'message');
    }

    return FixtureLlmStep(
      expect: r.object(json, path, 'expect'),
      reply: reply == null ? null : blocks,
      stopReason: stopReason,
      error: error,
      delayMs: r.integer(json, path, 'delayMs'),
      waitForCancel: r.boolean(json, path, 'waitForCancel') ?? false,
      usage: r.object(json, path, 'usage'),
    );
  }

  final Map<String, Object?>? expect;
  final List<Map<String, Object?>>? reply;
  final String? stopReason;
  final Map<String, Object?>? error;
  final int? delayMs;
  final bool waitForCancel;
  final Map<String, Object?>? usage;
}

final class FixtureNormalize {
  const FixtureNormalize({required this.replace});

  factory FixtureNormalize._parse(
    _Reader r,
    Map<String, Object?> json,
    String path,
  ) {
    r.closed(json, path, 'normalize');
    final rules = r.list(json, path, 'replace') ?? const [];
    return FixtureNormalize(
      replace: [
        for (final (i, raw) in rules.indexed)
          FixtureReplaceRule._parse(r, raw, '$path.replace[$i]'),
      ],
    );
  }

  final List<FixtureReplaceRule> replace;
}

/// `normalize.replace[i]`: replace [regex] by [replacement] in the string
/// at [path] (`$.a.b[0].c`) of both expected and actual frames (§14.5).
final class FixtureReplaceRule {
  const FixtureReplaceRule({
    required this.path,
    required this.regex,
    required this.replacement,
  });

  factory FixtureReplaceRule._parse(_Reader r, Object? raw, String path) {
    final json = r.asObject(raw, path);
    r.closed(json, path, 'replaceRule');
    final rulePath = r.string(json, path, 'path', required: true)!;
    if (!rulePath.startsWith(r'$')) {
      r.fail('$path.path', r'must be a JSON path starting with "$"');
    }
    final pattern = r.string(json, path, 'regex', required: true)!;
    final RegExp regex;
    try {
      regex = RegExp(pattern);
    } on FormatException catch (error) {
      r.fail('$path.regex', 'invalid regular expression: ${error.message}');
    }
    return FixtureReplaceRule(
      path: rulePath,
      regex: regex,
      replacement: r.string(json, path, 'with', required: true)!,
    );
  }

  final String path;
  final RegExp regex;
  final String replacement;
}

final class FixtureAfter {
  const FixtureAfter({required this.files});

  factory FixtureAfter._parse(
    _Reader r,
    Map<String, Object?> json,
    String path,
  ) {
    r.closed(json, path, 'after');
    return FixtureAfter(files: r.stringMap(json, path, 'files') ?? const {});
  }

  /// Expected content of working-directory files after the scenario.
  final Map<String, String> files;
}

/// `packages/dart/acp_testing/fixtures/acp`, resolved through the package
/// config, so tests do not depend on the current directory (design.md D1).
String defaultFixtureCorpusDirectory() => _packageRoot()
    .resolve('fixtures/acp')
    .toFilePath()
    .replaceAll(RegExp(r'[/\\]$'), '');

/// Root of `acp_testing`. `Isolate.resolvePackageUriSync` is unsupported
/// under `flutter test`, which `melos run test` uses for every package; then
/// the nearest `.dart_tool/package_config.json` above the current directory
/// is read instead (the workspace config lists every package).
Uri _packageRoot() {
  try {
    final library = Isolate.resolvePackageUriSync(
      Uri.parse('package:acp_testing/acp_testing.dart'),
    );
    if (library != null) {
      return library.resolve('..');
    }
  } on UnsupportedError {
    // Fall back to the package config below.
  }

  for (var dir = Directory.current.absolute; ; dir = dir.parent) {
    final config = File('${dir.path}/.dart_tool/package_config.json');
    if (config.existsSync()) {
      final json =
          jsonDecode(config.readAsStringSync()) as Map<String, Object?>;
      for (final package in json['packages']! as List<Object?>) {
        if (package case {
          'name': 'acp_testing',
          'rootUri': final String rootUri,
        }) {
          final root = config.uri.resolve(rootUri);
          return root.path.endsWith('/') ? root : Uri.parse('$root/');
        }
      }
    }
    if (dir.parent.path == dir.path) {
      throw StateError('package:acp_testing is not in any package config.');
    }
  }
}

/// Loads one fixture file.
AcpFixture loadFixtureFile(String path) {
  final file = File(path);
  final fileName = file.uri.pathSegments.last;
  final Object? decoded;
  try {
    decoded = jsonDecode(file.readAsStringSync());
  } on FormatException catch (error) {
    throw FixtureFormatException(
      file: fileName,
      path: r'$',
      message: 'invalid JSON: ${error.message}',
    );
  }
  if (decoded is! Map<String, Object?>) {
    throw FixtureFormatException(
      file: fileName,
      path: r'$',
      message: 'must be a JSON object',
    );
  }
  return AcpFixture.fromJson(decoded, fileName: fileName, sourcePath: path);
}

/// Loads every `*.json` fixture of a flat corpus directory, sorted by id.
/// Files starting with `_` (`_schema.json`) are not fixtures.
List<AcpFixture> loadFixtureCorpus({String? directory}) {
  final dir = Directory(directory ?? defaultFixtureCorpusDirectory());
  final fixtures = <AcpFixture>[];
  for (final entity in dir.listSync()) {
    final name = entity.uri.pathSegments.lastWhere((s) => s.isNotEmpty);
    if (entity is Directory) {
      throw FixtureFormatException(
        file: name,
        path: r'$',
        message: 'the fixture corpus is flat: subdirectories are not allowed',
      );
    }
    if (entity is! File || !name.endsWith('.json') || name.startsWith('_')) {
      continue;
    }
    fixtures.add(loadFixtureFile(entity.path));
  }
  fixtures.sort((a, b) => a.id.compareTo(b.id));
  return fixtures;
}

String _stripJsonExtension(String fileName) => fileName.endsWith('.json')
    ? fileName.substring(0, fileName.length - '.json'.length)
    : fileName;

String _key(String key) =>
    RegExp(r'^[A-Za-z_][A-Za-z0-9_]*$').hasMatch(key) ? '.$key' : '["$key"]';

/// Typed field access that fails with the file and the JSON path.
final class _Reader {
  _Reader(this.file);

  final String file;

  Never fail(String path, String message) =>
      throw FixtureFormatException(file: file, path: path, message: message);

  void closed(Map<String, Object?> json, String path, String schemaName) {
    final allowed = fixtureFormatKeys[schemaName]!;
    for (final key in json.keys) {
      if (!allowed.contains(key)) {
        fail(
          '$path${_key(key)}',
          'unknown key; allowed: ${allowed.join(', ')}',
        );
      }
    }
  }

  Map<String, Object?> asObject(Object? value, String path) {
    if (value is! Map<String, Object?>) {
      fail(path, 'must be an object');
    }
    return value;
  }

  Object? _field(
    Map<String, Object?> json,
    String path,
    String key, {
    required bool required,
  }) {
    if (!json.containsKey(key)) {
      if (required) {
        fail('$path${_key(key)}', 'required field is missing');
      }
      return null;
    }
    return json[key];
  }

  String? string(
    Map<String, Object?> json,
    String path,
    String key, {
    bool required = false,
  }) {
    final value = _field(json, path, key, required: required);
    if (value != null && value is! String) {
      fail('$path${_key(key)}', 'must be a string');
    }
    return value as String?;
  }

  int? integer(Map<String, Object?> json, String path, String key) {
    final value = _field(json, path, key, required: false);
    if (value != null && value is! int) {
      fail('$path${_key(key)}', 'must be an integer');
    }
    return value as int?;
  }

  bool? boolean(Map<String, Object?> json, String path, String key) {
    final value = _field(json, path, key, required: false);
    if (value != null && value is! bool) {
      fail('$path${_key(key)}', 'must be a boolean');
    }
    return value as bool?;
  }

  Map<String, Object?>? object(
    Map<String, Object?> json,
    String path,
    String key, {
    bool required = false,
  }) {
    final value = _field(json, path, key, required: required);
    if (value == null && !required) {
      return null;
    }
    return asObject(value, '$path${_key(key)}');
  }

  List<Object?>? list(
    Map<String, Object?> json,
    String path,
    String key, {
    bool required = false,
  }) {
    final value = _field(json, path, key, required: required);
    if (value == null && !required) {
      return null;
    }
    if (value is! List<Object?>) {
      fail('$path${_key(key)}', 'must be a list');
    }
    return value;
  }

  List<String>? stringList(
    Map<String, Object?> json,
    String path,
    String key, {
    bool required = false,
  }) {
    final values = list(json, path, key, required: required);
    if (values == null) {
      return null;
    }
    return [
      for (final (i, value) in values.indexed)
        if (value is String)
          value
        else
          fail('$path${_key(key)}[$i]', 'must be a string'),
    ];
  }

  Map<String, String>? stringMap(
    Map<String, Object?> json,
    String path,
    String key,
  ) {
    final values = object(json, path, key);
    if (values == null) {
      return null;
    }
    return {
      for (final MapEntry(key: name, :value) in values.entries)
        name: value is String
            ? value
            : fail('$path${_key(key)}${_key(name)}', 'must be a string'),
    };
  }
}
