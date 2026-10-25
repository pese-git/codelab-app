import 'dart:convert';

import '../cancel/cancel_token.dart';
import '../llm/errors.dart';
import '../llm/event_stream.dart';
import '../llm/events.dart';
import '../llm/messages.dart';
import '../llm/model_ref.dart';
import '../llm/stream_function.dart';
import '../llm/stream_state.dart';
import '../llm/usage.dart';
import '../util/clock.dart';
import 'fake_clock.dart';

/// Deterministic model built from a script in the format of the `llm`
/// block of a golden fixture (`agent-core-architecture` §14.7).
///
/// The n-th request gets the n-th step; `expect` of a step is an assertion
/// about the request, not a condition. The function never throws (LLM-1): a
/// mismatch or an extra request answers `ErrorEvent(badRequest)` with the
/// mismatch text — what the `--llm-script` binary shows — and is recorded;
/// [verify] throws [ScriptedLlmFailure] with every mismatch, extra request
/// and unused step (design.md, D8).
final class ScriptedStreamFunction {
  ScriptedStreamFunction._(this._steps, this.clock, this.cwd, this.sessionId);

  /// [json] is the `llm` object: `{"model": {...}, "steps": [...]}`.
  factory ScriptedStreamFunction.fromJson(
    Map<String, Object?> json, {
    Clock? clock,
    String? cwd,
    String? sessionId,
  }) {
    _checkKeys(json, const {'model', 'steps'}, 'llm');
    final steps = json['steps'];
    if (steps is! List<Object?>) {
      throw const FormatException('llm.steps must be a list');
    }
    return ScriptedStreamFunction._(
      [
        for (final (i, step) in steps.indexed)
          _Step.fromJson(step, 'llm.steps[$i]'),
      ],
      clock ?? FakeClock(),
      cwd,
      sessionId,
    );
  }

  final List<_Step> _steps;
  final Clock clock;

  /// Substituted for `${cwd}` in `text` and `thinking`.
  final String? cwd;

  /// Substituted for `${sessionId}`; without it — `LlmContext.cacheKey`.
  final String? sessionId;

  final _requests = <LlmContext>[];
  final _failures = <String>[];

  /// Requests received so far, in order.
  List<LlmContext> get requests => List.unmodifiable(_requests);

  AssistantMessageEventStream call(
    ModelRef model,
    LlmContext context, {
    CancelToken? cancel,
  }) {
    _requests.add(context);
    final number = _requests.length;
    return runProvider(model, cancel, clock, (state) async {
      if (number > _steps.length) {
        _fail(
          state,
          'request $number: the script has only ${_steps.length} steps',
        );
        return;
      }
      final step = _steps[number - 1];
      final mismatch = step.check(context);
      if (mismatch != null) {
        _fail(state, 'step $number: $mismatch');
        return;
      }
      await step.play(
        state,
        cancel,
        clock,
        (text) => _substitute(text, context),
      );
    });
  }

  /// Throws [ScriptedLlmFailure] unless every step was used exactly once
  /// with a matching request.
  void verify() {
    final problems = [
      ..._failures,
      for (var i = _requests.length; i < _steps.length; i++)
        'step ${i + 1} was not used',
    ];
    if (problems.isNotEmpty) {
      throw ScriptedLlmFailure(problems);
    }
  }

  void _fail(ProviderStreamState state, String problem) {
    _failures.add(problem);
    state
      ..start()
      ..fail(LlmErrorClass.badRequest, 'scripted model: $problem');
  }

  String _substitute(String text, LlmContext context) => text
      .replaceAll(r'${cwd}', cwd ?? r'${cwd}')
      .replaceAll(r'${sessionId}', sessionId ?? context.cacheKey ?? '');
}

/// The script and the requests disagree.
final class ScriptedLlmFailure implements Exception {
  const ScriptedLlmFailure(this.problems);

  final List<String> problems;

  @override
  String toString() =>
      'ScriptedLlmFailure:\n${problems.map((p) => '  - $p').join('\n')}';
}

const _stepKeys = {
  'expect',
  'reply',
  'stopReason',
  'error',
  'delayMs',
  'waitForCancel',
  'usage',
};

/// Text and thinking are sent in deltas of this many characters.
const _deltaLength = 16;

final class _Step {
  _Step({
    required this.expect,
    required this.reply,
    required this.stopReason,
    required this.error,
    required this.delay,
    required this.waitForCancel,
    required this.usage,
  });

  factory _Step.fromJson(Object? raw, String path) {
    if (raw is! Map<String, Object?>) {
      throw FormatException('$path must be an object');
    }
    _checkKeys(raw, _stepKeys, path);
    final stopReason = raw['stopReason'];
    final error = raw['error'];
    final usage = raw['usage'];
    final delayMs = raw['delayMs'];
    return _Step(
      expect: raw['expect'] as Map<String, Object?>?,
      reply: [
        for (final (i, block)
            in (raw['reply'] as List<Object?>? ?? const []).indexed)
          _ReplyBlock.fromJson(block, '$path.reply[$i]'),
      ],
      stopReason: stopReason == null
          ? null
          : StopReason.values.asNameMap()[stopReason] ??
                (throw FormatException('$path.stopReason: "$stopReason"')),
      error: error as Map<String, Object?>?,
      delay: delayMs is int ? Duration(milliseconds: delayMs) : null,
      waitForCancel: raw['waitForCancel'] == true,
      usage: usage is Map<String, Object?> ? Usage.fromJson(usage) : null,
    );
  }

  final Map<String, Object?>? expect;
  final List<_ReplyBlock> reply;
  final StopReason? stopReason;
  final Map<String, Object?>? error;
  final Duration? delay;
  final bool waitForCancel;
  final Usage? usage;

  /// A description of the mismatch, or `null` when the request matches.
  String? check(LlmContext context) {
    final expect = this.expect;
    if (expect == null) {
      return null;
    }
    final problems = <String>[];
    if (expect['lastMessage'] case final Map<String, Object?> wanted) {
      final last = context.messages.isEmpty ? null : context.messages.last;
      final role = wanted['role'];
      final contains = wanted[r'$textContains'];
      final actual = last == null ? null : _describe(last);
      if (last == null ||
          (role != null && _role(last) != role) ||
          (contains is String && !_text(last).contains(contains))) {
        problems.add(
          'expect.lastMessage: expected ${jsonEncode(wanted)}, got $actual',
        );
      }
    }
    if (expect['toolResult'] case final Map<String, Object?> wanted) {
      final results = _trailingToolResults(context.messages);
      final match = results.where((r) => r.toolCallId == wanted['toolCallId']);
      if (match.isEmpty ||
          (wanted.containsKey('isError') &&
              match.first.isError != wanted['isError'])) {
        problems.add(
          'expect.toolResult: expected ${jsonEncode(wanted)}, got '
          '${jsonEncode([
            for (final r in results) {'toolCallId': r.toolCallId, 'isError': r.isError},
          ])}',
        );
      }
    }
    if (expect['tools'] case final List<Object?> wanted) {
      final actual = [for (final tool in context.tools) tool.name];
      if (jsonEncode(actual) != jsonEncode(wanted)) {
        problems.add(
          'expect.tools: expected ${jsonEncode(wanted)}, '
          'got ${jsonEncode(actual)}',
        );
      }
    }
    if (expect['systemPrompt'] case {r'$textContains': final String text}) {
      if (!context.systemPrompt.contains(text)) {
        problems.add(
          'expect.systemPrompt: expected text containing ${jsonEncode(text)}',
        );
      }
    }
    return problems.isEmpty ? null : problems.join('; ');
  }

  Future<void> play(
    ProviderStreamState state,
    CancelToken? cancel,
    Clock clock,
    String Function(String text) substitute,
  ) async {
    if (delay case final delay?) {
      await clock.delay(delay, cancel: cancel);
    }
    if (waitForCancel) {
      if (cancel == null) {
        state
          ..start()
          ..fail(
            LlmErrorClass.badRequest,
            'scripted model: waitForCancel without a cancel token',
          );
        return;
      }
      state.start();
      // С reply — отмена посреди стрима: блоки ответа уже ушли, шаг ждёт
      // отмены (фикстура acp/prompt-cancel-mid-stream; design.md change
      // add-dart-agent-acp-server, D15).
      for (final block in reply) {
        block.play(state, substitute);
      }
      await cancel.onCancel;
      cancel.throwIfCancelled();
    }
    state.start();
    for (final block in reply) {
      block.play(state, substitute);
    }
    if (usage case final usage?) {
      state.setUsage(usage);
    }
    if (error case final error?) {
      state.fail(
        LlmErrorClass.values.asNameMap()[error['class']] ??
            LlmErrorClass.unknown,
        '${error['message'] ?? error['class']}',
      );
      return;
    }
    final reason =
        stopReason ??
        (reply.any((b) => b.toolCall != null)
            ? StopReason.toolUse
            : StopReason.stop);
    switch (reason) {
      case StopReason.error:
        state.fail(LlmErrorClass.unknown, 'scripted error');
      case StopReason.aborted:
        state.fail(LlmErrorClass.aborted, 'Request was aborted', aborted: true);
      case StopReason.stop || StopReason.length || StopReason.toolUse:
        state.finish(reason);
    }
  }

  static String _role(Message message) => switch (message) {
    UserMessage() => 'user',
    AssistantMessage() => 'assistant',
    ToolResultMessage() => 'toolResult',
  };

  static String _text(Message message) =>
      message.content.whereType<TextContent>().map((b) => b.text).join('\n');

  static String _describe(Message message) =>
      '${_role(message)} message ${jsonEncode(_text(message))}';

  static List<ToolResultMessage> _trailingToolResults(List<Message> messages) {
    final results = <ToolResultMessage>[];
    for (final message in messages.reversed) {
      if (message is! ToolResultMessage) {
        break;
      }
      results.insert(0, message);
    }
    return results;
  }
}

final class _ReplyBlock {
  _ReplyBlock({this.text, this.thinking, this.toolCall});

  factory _ReplyBlock.fromJson(Object? raw, String path) {
    if (raw is! Map<String, Object?> || raw.length != 1) {
      throw FormatException(
        '$path must have exactly one of text, thinking, toolCall',
      );
    }
    _checkKeys(raw, const {'text', 'thinking', 'toolCall'}, path);
    final toolCall = raw['toolCall'];
    if (toolCall != null && toolCall is! Map<String, Object?>) {
      throw FormatException('$path.toolCall must be an object');
    }
    return _ReplyBlock(
      text: raw['text'] as String?,
      thinking: raw['thinking'] as String?,
      toolCall: toolCall as Map<String, Object?>?,
    );
  }

  final String? text;
  final String? thinking;
  final Map<String, Object?>? toolCall;

  void play(ProviderStreamState state, String Function(String) substitute) {
    if (text case final text?) {
      _stream(state, state.openBlock(BlockKind.text), substitute(text));
    } else if (thinking case final thinking?) {
      _stream(state, state.openBlock(BlockKind.thinking), substitute(thinking));
    } else if (toolCall case final call?) {
      final index = state.openBlock(
        BlockKind.toolCall,
        id: call['id'] as String?,
        name: call['name'] as String?,
      );
      state
        ..append(index, jsonEncode(call['arguments'] ?? const {}))
        ..closeBlock(index);
    }
  }

  static void _stream(ProviderStreamState state, int index, String text) {
    final runes = text.runes.toList();
    for (var i = 0; i < runes.length; i += _deltaLength) {
      final end = i + _deltaLength < runes.length
          ? i + _deltaLength
          : runes.length;
      state.append(index, String.fromCharCodes(runes.sublist(i, end)));
    }
    state.closeBlock(index);
  }
}

void _checkKeys(Map<String, Object?> json, Set<String> allowed, String path) {
  for (final key in json.keys) {
    if (!allowed.contains(key)) {
      throw FormatException('$path.$key: unknown key');
    }
  }
}
