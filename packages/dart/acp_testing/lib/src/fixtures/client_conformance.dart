import 'dart:async';
import 'dart:collection';
import 'dart:convert';

import 'package:acp_client_core/acp_client_core.dart';
import 'package:acp_protocol/acp_protocol.dart';

import '../fake_acp_transport.dart';
import '../fake_terminal_process_runner.dart';
import 'fixture.dart';
import 'matcher.dart';

/// Client conformance driver — `14-golden-fixtures.md` §14.10, design.md D4.
///
/// The driver plays the agent: `a2c` frames are turned into concrete frames
/// and fed to the client through [FakeAcpTransport.emitInbound]; `c2a`
/// frames are awaited among the messages the client sends and compared
/// after normalization. Frames the client sends on a user action
/// (`session/prompt`, the answer to `session/request_permission`,
/// `session/cancel`, and the standard handshake) need the client's API: the
/// driver calls `onBeforeExpect` before waiting, and the test performs the
/// action there.

/// `sessionId` of the standard `session/new` answer of the driver.
const standardFixtureSessionId = 'fixture-session-1';

/// Called before the driver waits for a `c2a` frame.
typedef ClientFixtureHook<C> = void Function(ClientFixtureStep<C> step);

/// What the client under test is built from.
final class ClientFixtureEnvironment {
  const ClientFixtureEnvironment({
    required this.fixture,
    required this.transport,
    required this.fileSystem,
    required this.terminal,
  });

  final AcpFixture fixture;

  /// Transport with `autoRespondToInitialize` off: the driver answers.
  final FakeAcpTransport transport;

  /// `fs/*` port of the client, filled from `setup.files`.
  final InMemoryFixtureFileSystem fileSystem;

  /// `terminal/*` port of the client, scripted by `setup.terminal`.
  final FixtureTerminalProcessRunner terminal;

  String get cwd => fixture.setup.cwd;
}

/// A `c2a` frame the driver is about to wait for.
final class ClientFixtureStep<C> {
  ClientFixtureStep._({
    required this.client,
    required this.environment,
    required this.frame,
    required this.expectedFrames,
    required this.variables,
    required void Function(Future<Object?>) track,
  }) : _track = track;

  final C client;
  final ClientFixtureEnvironment environment;
  final FixtureFrame frame;

  /// Expected frames with known variables substituted; matchers stay.
  /// One element unless the frame is `unordered`.
  final List<Map<String, Object?>> expectedFrames;

  /// Variables of the run: `cwd`, `sessionId` and captures so far.
  final Map<String, Object?> variables;
  final void Function(Future<Object?>) _track;

  Map<String, Object?> get expected => expectedFrames.first;

  /// `true` for the frames of the standard handshake.
  bool get isHandshake => frame.index < 0;

  /// Registers a user action started in the hook. The driver does not
  /// await it before the frame (the action usually completes only after a
  /// later `a2c` frame), but fails the run on its error and awaits it at
  /// the end of the scenario.
  void track(Future<Object?> action) => _track(action);
}

final class ClientFixtureResult<C> {
  const ClientFixtureResult._({
    required this.skipped,
    this.skipReason,
    this.client,
    this.environment,
    this.variables = const {},
  });

  final bool skipped;
  final String? skipReason;
  final C? client;
  final ClientFixtureEnvironment? environment;
  final Map<String, Object?> variables;
}

/// The client diverged from the fixture.
final class ClientFixtureFailure implements Exception {
  const ClientFixtureFailure({
    required this.fixtureId,
    required this.frameIndex,
    required this.message,
    this.note,
    this.mismatches = const [],
    this.expected,
    this.actual,
  });

  final String fixtureId;

  /// Index in `frames`; negative for the standard handshake, `frames.length`
  /// for checks after the scenario.
  final int frameIndex;
  final String message;
  final String? note;
  final List<FrameMismatch> mismatches;
  final Object? expected;
  final Object? actual;

  @override
  String toString() {
    final buffer = StringBuffer('ClientFixtureFailure: $fixtureId ')
      ..write(frameIndex < 0 ? 'handshake frame' : 'frame #$frameIndex')
      ..write(note == null ? '' : ' ($note)')
      ..write(': $message');
    for (final mismatch in mismatches) {
      buffer.write('\n  - $mismatch');
    }
    if (expected != null) {
      buffer.write('\n  expected: ${_encode(expected)}');
    }
    if (actual != null) {
      buffer.write('\n  actual:   ${_encode(actual)}');
    }
    return buffer.toString();
  }
}

/// Plays [fixture] against the client built by [clientFactory].
///
/// Returns a skipped result for a fixture without the `client` role, throws
/// [ClientFixtureFailure] on the first divergence. Unless
/// `setup.skipInitialize` is set, the driver first plays the standard
/// handshake: `initialize` answered with protocol version 1, `session/new`
/// answered with [standardFixtureSessionId] and, with `setup.mode`, a
/// `modes` block of that single mode. `setup.config` is the agent config
/// (§15) and is not read by the client run; a fixture that needs specific
/// `session/new` answers writes the handshake itself with `skipInitialize`.
Future<ClientFixtureResult<C>> runClientFixture<C>(
  AcpFixture fixture,
  C Function(ClientFixtureEnvironment env) clientFactory, {
  ClientFixtureHook<C>? onBeforeExpect,
  Duration frameTimeout = const Duration(seconds: 5),
  Duration quietPeriod = const Duration(milliseconds: 100),
}) async {
  if (!fixture.roles.contains(FixtureRole.client)) {
    return ClientFixtureResult._(
      skipped: true,
      skipReason:
          '${fixture.id} has roles '
          '[${fixture.roles.map((r) => r.name).join(', ')}] without "client"',
    );
  }

  final setup = fixture.setup;
  final transport = FakeAcpTransport()..autoRespondToInitialize = false;
  final environment = ClientFixtureEnvironment(
    fixture: fixture,
    transport: transport,
    fileSystem: InMemoryFixtureFileSystem(cwd: setup.cwd, files: setup.files),
    terminal: FixtureTerminalProcessRunner(setup.terminal),
  );
  final inbox = _SentInbox(transport);
  final run = _ClientRun<C>(
    fixture: fixture,
    environment: environment,
    inbox: inbox,
    matcher: FrameMatcher(cwd: setup.cwd, replace: fixture.normalize.replace),
    hook: onBeforeExpect,
    frameTimeout: frameTimeout,
    quietPeriod: quietPeriod,
  );

  try {
    final client = clientFactory(environment);
    await run.play(client);
    return ClientFixtureResult._(
      skipped: false,
      client: client,
      environment: environment,
      variables: Map.unmodifiable(run.matcher.variables),
    );
  } finally {
    await inbox.cancel();
  }
}

final class _ClientRun<C> {
  _ClientRun({
    required this.fixture,
    required this.environment,
    required this.inbox,
    required this.matcher,
    required this.hook,
    required this.frameTimeout,
    required this.quietPeriod,
  });

  final AcpFixture fixture;
  final ClientFixtureEnvironment environment;
  final _SentInbox inbox;
  final FrameMatcher matcher;
  final ClientFixtureHook<C>? hook;
  final Duration frameTimeout;
  final Duration quietPeriod;
  final _actions = <Future<void>>[];

  Future<void> play(C client) async {
    final frames = [
      if (!fixture.setup.skipInitialize) ..._handshake(fixture.setup),
      ...fixture.frames,
    ];
    if (!fixture.setup.skipInitialize) {
      matcher.variables['sessionId'] = standardFixtureSessionId;
    }

    for (final frame in frames) {
      switch (frame.direction) {
        case FrameDirection.a2c:
          _emit(frame);
          // Let the client finish handling the frame (e.g. complete the
          // future of `session/new`) before the next user action.
          await Future<void>.delayed(Duration.zero);
        case FrameDirection.c2a:
          hook?.call(
            ClientFixtureStep._(
              client: client,
              environment: environment,
              frame: frame,
              expectedFrames: [
                for (final template in _templates(frame))
                  matcher.substitute(template)! as Map<String, Object?>,
              ],
              variables: Map.unmodifiable(matcher.variables),
              track: _track,
            ),
          );
          await _expect(frame);
      }
    }

    await _settleActions();
    await _expectSilence();
    _checkAfter();
  }

  List<Map<String, Object?>> _templates(FixtureFrame frame) =>
      frame.unordered ?? [frame.frame!];

  void _emit(FixtureFrame frame) {
    for (final template in _templates(frame)) {
      final Object? concrete;
      try {
        concrete = matcher.materialize(template);
      } on FixtureMatchException catch (error) {
        _fail(frame, error.message, expected: template);
      }
      if (frame.matchText case final text?) {
        _setText(concrete, matcher.substitute(text)! as String);
      }
      final JsonRpcMessage message;
      try {
        message = jsonRpcMessageFromJson(concrete! as Map<String, Object?>);
      } on Object catch (error) {
        _fail(
          frame,
          'a2c frame is not a JSON-RPC message: $error',
          expected: concrete,
        );
      }
      environment.transport.emitInbound(message);
    }
  }

  Future<void> _expect(FixtureFrame frame) async {
    if (frame.unordered case final templates?) {
      final actual = <Object?>[];
      for (var i = 0; i < templates.length; i++) {
        actual.add(await _next(frame, frameTimeout));
      }
      final mismatches = matcher.matchUnordered(templates, actual);
      if (mismatches.isNotEmpty) {
        _fail(
          frame,
          'unordered frames differ',
          mismatches: mismatches,
          expected: templates,
          actual: actual,
        );
      }
      return;
    }

    final template = frame.frame!;
    if (frame.optional) {
      if (await inbox.waitFor(quietPeriod, _hasActionError) &&
          matcher.match(template, inbox.peek()).isEmpty) {
        inbox.take();
      }
      return;
    }

    final first = await _next(frame, frameTimeout);
    final mismatches = matcher.match(template, first);
    if (mismatches.isNotEmpty) {
      _fail(
        frame,
        'c2a frame differs',
        mismatches: mismatches,
        expected: matcher.substitute(template),
        actual: first,
      );
    }
    if (!frame.repeated) {
      return;
    }

    final repeats = [first];
    while (await inbox.waitFor(quietPeriod, _hasActionError) &&
        matcher.match(template, inbox.peek()).isEmpty) {
      repeats.add(inbox.take());
    }
    if (frame.matchText case final text?) {
      final textMismatches = matcher.matchText(text, repeats);
      if (textMismatches.isNotEmpty) {
        _fail(frame, 'repeated frames differ', mismatches: textMismatches);
      }
    }
  }

  Future<Object?> _next(FixtureFrame frame, Duration timeout) async {
    if (!await inbox.waitFor(timeout, _hasActionError)) {
      _failOnActionError(frame);
      _fail(
        frame,
        'timed out after ${timeout.inMilliseconds} ms waiting for a c2a frame',
        expected: _templates(frame).length == 1
            ? matcher.substitute(_templates(frame).single)
            : _templates(frame),
      );
    }
    _failOnActionError(frame);
    return inbox.take();
  }

  (Object, StackTrace)? _actionError;

  bool _hasActionError() => _actionError != null;

  void _track(Future<Object?> action) {
    _actions.add(
      action.then<void>(
        (_) {},
        onError: (Object error, StackTrace stackTrace) {
          _actionError ??= (error, stackTrace);
          inbox.wake();
        },
      ),
    );
  }

  void _failOnActionError(FixtureFrame frame) {
    if (_actionError case (final error, _)) {
      _fail(frame, 'user action failed: $error');
    }
  }

  Future<void> _settleActions() async {
    final atEnd = _endFrame();
    try {
      await Future.wait(_actions).timeout(frameTimeout);
    } on TimeoutException {
      _fail(atEnd, 'a user action did not complete by the end of the scenario');
    }
    _failOnActionError(atEnd);
  }

  Future<void> _expectSilence() async {
    await Future<void>.delayed(quietPeriod);
    if (inbox.isNotEmpty) {
      _fail(
        _endFrame(),
        'unexpected frames from the client after the scenario',
        actual: inbox.takeAll(),
      );
    }
  }

  void _checkAfter() {
    final expectedFiles = fixture.after?.files ?? const {};
    final actualFiles = environment.fileSystem.files;
    final mismatches = [
      for (final MapEntry(key: path, value: content) in expectedFiles.entries)
        if (actualFiles[path] != content)
          FrameMismatch(
            'after.files["$path"]',
            'expected ${_encode(content)}, got ${_encode(actualFiles[path])}',
          ),
    ];
    if (mismatches.isNotEmpty) {
      _fail(
        _endFrame(),
        'files after the scenario differ',
        mismatches: mismatches,
      );
    }
  }

  FixtureFrame _endFrame() => FixtureFrame(
    index: fixture.frames.length,
    direction: FrameDirection.c2a,
    optional: false,
    repeated: false,
    note: 'after the scenario',
  );

  Never _fail(
    FixtureFrame frame,
    String message, {
    List<FrameMismatch> mismatches = const [],
    Object? expected,
    Object? actual,
  }) => throw ClientFixtureFailure(
    fixtureId: fixture.id,
    frameIndex: frame.index,
    note: frame.note,
    message: message,
    mismatches: mismatches,
    expected: expected,
    actual: actual,
  );
}

List<FixtureFrame> _handshake(FixtureSetup setup) {
  FixtureFrame frame(
    int index,
    FrameDirection dir,
    String note,
    Map<String, Object?> json,
  ) => FixtureFrame(
    index: index,
    direction: dir,
    optional: false,
    repeated: false,
    note: note,
    frame: json,
  );

  final capabilities = setup.clientCapabilities;
  final mode = setup.mode;
  return [
    frame(-4, FrameDirection.c2a, 'handshake: initialize', {
      'jsonrpc': '2.0',
      'id': {r'$capture': 'initializeId'},
      'method': 'initialize',
      'params': {
        r'$partial': {
          'protocolVersion': 1,
          if (capabilities != null)
            'clientCapabilities': {r'$partial': capabilities},
        },
      },
    }),
    frame(-3, FrameDirection.a2c, 'handshake: initialize result', {
      'jsonrpc': '2.0',
      'id': r'${initializeId}',
      'result': {
        'protocolVersion': 1,
        'agentCapabilities': <String, Object?>{},
      },
    }),
    frame(-2, FrameDirection.c2a, 'handshake: session/new', {
      'jsonrpc': '2.0',
      'id': {r'$capture': 'sessionNewId'},
      'method': 'session/new',
      'params': {
        r'$partial': {'cwd': r'${cwd}'},
      },
    }),
    frame(-1, FrameDirection.a2c, 'handshake: session/new result', {
      'jsonrpc': '2.0',
      'id': r'${sessionNewId}',
      'result': {
        'sessionId': standardFixtureSessionId,
        if (mode != null)
          'modes': {
            'currentModeId': mode,
            'availableModes': [
              {'id': mode, 'name': mode},
            ],
          },
      },
    }),
  ];
}

/// Puts the `match.$text` of a repeated `a2c` frame into its
/// `params.update.content.text`: the driver sends one chunk with the whole
/// text.
void _setText(Object? frame, String text) {
  if (frame case {
    'params': {'update': {'content': final Map<String, Object?> content}},
  }) {
    content['text'] = text;
  }
}

/// Messages the client sent, as wire JSON, in order.
final class _SentInbox {
  _SentInbox(FakeAcpTransport transport) {
    _subscription = transport.sent.listen((message) {
      _queue.add(jsonDecode(encodeJsonRpcMessage(message)));
      wake();
    });
  }

  late final StreamSubscription<JsonRpcMessage> _subscription;
  final _queue = Queue<Object?>();
  Completer<void>? _signal;

  bool get isNotEmpty => _queue.isNotEmpty;

  Object? peek() => _queue.first;

  Object? take() => _queue.removeFirst();

  List<Object?> takeAll() {
    final all = _queue.toList();
    _queue.clear();
    return all;
  }

  void wake() {
    final signal = _signal;
    _signal = null;
    if (signal != null && !signal.isCompleted) {
      signal.complete();
    }
  }

  /// Waits until a message is queued; `false` on [timeout] or as soon as
  /// [hasError] reports a failed user action.
  Future<bool> waitFor(Duration timeout, bool Function() hasError) async {
    final deadline = DateTime.now().add(timeout);
    while (_queue.isEmpty) {
      final left = deadline.difference(DateTime.now());
      if (left <= Duration.zero) {
        return false;
      }
      final signal = _signal ??= Completer<void>();
      try {
        await signal.future.timeout(left);
      } on TimeoutException {
        return _queue.isNotEmpty;
      }
      if (_queue.isEmpty && hasError()) {
        return false;
      }
    }
    return true;
  }

  Future<void> cancel() => _subscription.cancel();
}

/// In-memory `fs/*` port of the client: files of `setup.files` under `cwd`.
/// Line slicing follows the app adapter
/// (`apps/codelab_app/lib/core/platform/text_file_io.dart`): `line` is
/// 1-based, the result is the selected lines joined by `\n`.
final class InMemoryFixtureFileSystem
    implements TextFileReader, TextFileWriter {
  InMemoryFixtureFileSystem({
    required String cwd,
    Map<String, String> files = const {},
  }) : _cwd = _slash(cwd) {
    for (final MapEntry(key: path, value: content) in files.entries) {
      _files['$_cwd/$path'] = content;
    }
  }

  final String _cwd;
  final _files = <String, String>{};

  /// Current files; paths under `cwd` are relative.
  Map<String, String> get files => {
    for (final MapEntry(key: path, value: content) in _files.entries)
      (path.startsWith('$_cwd/') ? path.substring(_cwd.length + 1) : path):
          content,
  };

  @override
  Future<String> readText({required String path, int? line, int? limit}) async {
    final content = _files[_slash(path)];
    if (content == null) {
      throw FsNotFoundFailure(path);
    }
    if (line == null && limit == null) {
      return content;
    }
    final lines = const LineSplitter().convert(content);
    final start = ((line ?? 1) - 1).clamp(0, lines.length);
    final end = limit == null
        ? lines.length
        : (start + limit).clamp(start, lines.length);
    return lines.sublist(start, end).join('\n');
  }

  @override
  Future<void> writeText({
    required String path,
    required String content,
  }) async {
    _files[_slash(path)] = content;
  }

  static String _slash(String path) => path.replaceAll(r'\', '/');
}

/// `terminal/*` port of the client scripted by `setup.terminal`: a command
/// line (`command` and `args` joined by spaces, or just `command`) gets its
/// output and exits at once with its exit code; a script without
/// `exitCode` keeps running until `terminal/kill` or `terminal/release`.
final class FixtureTerminalProcessRunner implements TerminalProcessRunner {
  FixtureTerminalProcessRunner(this.commands);

  final Map<String, FixtureTerminalCommand> commands;
  final started = <FakeTerminalProcessStart>[];

  @override
  Future<TerminalProcessHandle> start({
    required String command,
    required List<String> args,
    required Map<String, String> env,
    required String cwd,
    int? outputByteLimit,
  }) async {
    final line = [command, ...args].join(' ');
    final script = commands[line] ?? commands[command];
    if (script == null) {
      throw TerminalStartFailure(
        'setup.terminal has no script for "$line"; '
        'known: ${commands.keys.join(', ')}',
      );
    }
    started.add(
      FakeTerminalProcessStart(
        command: command,
        args: args,
        env: env,
        cwd: cwd,
        outputByteLimit: outputByteLimit,
      ),
    );
    final handle = FakeTerminalProcessHandle(outputByteLimit: outputByteLimit)
      ..appendOutput(script.output);
    if (script.exitCode case final exitCode?) {
      handle.exit(exitCode: exitCode);
    }
    return handle;
  }
}

String _encode(Object? value) {
  try {
    return jsonEncode(value);
  } on JsonUnsupportedObjectError {
    return '$value';
  }
}
