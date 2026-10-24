import 'dart:async';
import 'dart:convert';

import '../cancel/cancel_token.dart';
import '../util/clock.dart';
import 'errors.dart';
import 'event_stream.dart';
import 'events.dart';
import 'messages.dart';
import 'model_ref.dart';
import 'overflow.dart';
import 'usage.dart';

/// Common frame of a provider adapter (`agent-core-architecture` §2.5).
///
/// Runs [body] in a microtask, so the caller subscribes first. A cancelled
/// [cancel] gives `ErrorEvent(aborted)` without calling [body];
/// [CancelledException] from [body] is aborted too; any other exception is
/// an `ErrorEvent` of the class from [classify] (§2.9; [LlmErrorClass.unknown]
/// without it). A body that ends without a terminal event gets one. The
/// stream never throws (LLM-1) and always has one terminal event (LLM-2).
AssistantMessageEventStream runProvider(
  ModelRef model,
  CancelToken? cancel,
  Clock clock,
  Future<void> Function(ProviderStreamState state) body, {
  LlmErrorClass Function(Object error)? classify,
}) {
  final out = AssistantMessageEventStream();
  final state = ProviderStreamState(model, clock, out);
  scheduleMicrotask(() async {
    try {
      cancel?.throwIfCancelled();
      await body(state);
      if (!state.isTerminated) {
        state.failUnexpectedEnd();
      }
    } on CancelledException {
      state.fail(LlmErrorClass.aborted, 'Request was aborted', aborted: true);
    } catch (error) {
      state.fail(classify?.call(error) ?? LlmErrorClass.unknown, '$error');
    } finally {
      out.end();
    }
  });
  return out;
}

/// Mutable accumulator of one answer. Every method that emits pushes one
/// event to the output stream; nothing happens after the terminal event.
///
/// Snapshots without quadratic cost: blocks keep their fragments in
/// growing lists; an event remembers only the length of each list and the
/// block metadata at its moment, and its `partial` joins the fragments on
/// first access.
final class ProviderStreamState {
  ProviderStreamState(this.model, this.clock, this._out)
    : _timestamp = clock.now();

  final ModelRef model;
  final Clock clock;
  final AssistantMessageEventStream _out;
  DateTime _timestamp;
  final _blocks = <_Block>[];
  final _notes = <String>[];
  var _usage = Usage.zero;
  String? _rawStopReason;
  var _terminated = false;

  bool get isTerminated => _terminated;

  /// Blocks that are open now, by index.
  Iterable<int> get openBlocks => [
    for (final (i, block) in _blocks.indexed)
      if (!block.closed) i,
  ];

  Usage get usage => _usage;

  /// The provider finish or stop reason remembered so far.
  String? get rawStopReason => _rawStopReason;

  /// Number of blocks opened since [start].
  int get blockCount => _blocks.length;

  void start() {
    if (_terminated) {
      return;
    }
    _timestamp = clock.now();
    _blocks.clear();
    _push(StartEvent.new);
  }

  /// Appends a block and returns its index.
  int openBlock(
    BlockKind kind, {
    String? id,
    String? name,
    ProviderApi? api,
    bool redacted = false,
  }) {
    final index = _blocks.length;
    if (_terminated) {
      return index;
    }
    _blocks.add(
      _Block(
        kind,
        id: id ?? '',
        name: name ?? '',
        api: api,
        redacted: redacted,
      ),
    );
    _push((snapshot) => BlockStartEvent(snapshot, index: index, kind: kind));
    return index;
  }

  /// Appends text, reasoning, or a raw JSON fragment of call arguments.
  void append(int index, String fragment) {
    if (_terminated || fragment.isEmpty) {
      return;
    }
    _blocks[index].chunks.add(fragment);
    _push(
      (snapshot) => BlockDeltaEvent(snapshot, index: index, delta: fragment),
    );
  }

  /// Raw JSON arguments accumulated so far, for adapters that compare
  /// repeated frames (§2.7).
  String argumentsOf(int index) => _blocks[index].chunks.join();

  String nameOf(int index) => _blocks[index].name;

  String idOf(int index) => _blocks[index].id;

  void setId(int index, String id) {
    if (!_terminated) {
      _blocks[index].id = id;
    }
  }

  void setName(int index, String name) {
    if (!_terminated) {
      _blocks[index].name = name;
    }
  }

  void setSignature(int index, String signature) {
    if (!_terminated) {
      _blocks[index].signature = signature;
    }
  }

  void setUsage(Usage usage) {
    if (!_terminated) {
      _usage = usage;
    }
  }

  void setRawStopReason(String reason) {
    if (!_terminated) {
      _rawStopReason = reason;
    }
  }

  /// Closes a block; a tool call parses its arguments once: an empty string
  /// is `{}`, a parse error is `{}` and a note in `errorMessage` (LLM-6).
  void closeBlock(int index) {
    if (_terminated) {
      return;
    }
    final block = _blocks[index];
    if (block.closed) {
      return;
    }
    block.closed = true;
    if (block.kind == BlockKind.toolCall) {
      block.arguments = _parseArguments(block);
    }
    final closed = block.snapshot(block.chunks.length).build();
    _push((snapshot) => BlockEndEvent(snapshot, index: index, block: closed));
  }

  /// Whether the arguments of a closed tool call failed to parse.
  bool argumentsInvalid(int index) => _blocks[index].argumentsInvalid;

  /// Closes all open blocks and emits [DoneEvent].
  void finish(StopReason reason, {String? note}) {
    if (_terminated) {
      return;
    }
    for (final index in openBlocks.toList()) {
      closeBlock(index);
    }
    if (note != null) {
      _notes.add(note);
    }
    _usage = calculateCost(_usage, model.cost);
    final message = _snapshot(reason)();
    final overflow = silentOverflow(
      message,
      contextWindow: model.contextWindow,
    );
    if (overflow != null) {
      fail(LlmErrorClass.overflow, overflow);
      return;
    }
    _terminated = true;
    _out.push(DoneEvent(message));
  }

  /// Emits [ErrorEvent]; open blocks stay as they are.
  void fail(
    LlmErrorClass errorClass,
    String message, {
    bool aborted = false,
    Duration? retryAfter,
  }) {
    if (_terminated) {
      return;
    }
    _terminated = true;
    _usage = calculateCost(_usage, model.cost);
    final error = _snapshot(
      aborted ? StopReason.aborted : StopReason.error,
    )().copyWith(errorMessage: _joinNotes(message), errorClass: errorClass);
    _out.push(ErrorEvent(error, retryAfter: retryAfter));
  }

  /// Protection against a body that forgot its terminal event.
  void failUnexpectedEnd() => fail(
    LlmErrorClass.network,
    'provider stream ended without a terminal event',
  );

  void _push(
    AssistantMessageEvent Function(AssistantMessage Function() snapshot) make,
  ) => _out.push(make(_snapshot(StopReason.stop)));

  AssistantMessage Function() _snapshot(StopReason stopReason) {
    final blocks = [for (final b in _blocks) b.snapshot(b.chunks.length)];
    final usage = _usage;
    final rawStopReason = _rawStopReason;
    final notes = _joinNotes(null);
    final timestamp = _timestamp;
    return () => AssistantMessage(
      content: [for (final b in blocks) b.build()],
      model: model,
      usage: usage,
      stopReason: stopReason,
      rawStopReason: rawStopReason,
      errorMessage: notes,
      timestamp: timestamp,
    );
  }

  String? _joinNotes(String? message) {
    final parts = [?message, ..._notes];
    return parts.isEmpty ? null : parts.join('; ');
  }

  Map<String, Object?> _parseArguments(_Block block) {
    final raw = block.chunks.join();
    if (raw.trim().isEmpty) {
      return const {};
    }
    try {
      final decoded = jsonDecode(raw);
      if (decoded is Map<String, Object?>) {
        return decoded;
      }
    } on FormatException {
      // Falls through to the note below.
    }
    block.argumentsInvalid = true;
    _notes.add(
      'arguments of tool call ${block.id} (${block.name}) are not valid JSON',
    );
    return const {};
  }
}

final class _Block {
  _Block(
    this.kind, {
    required this.id,
    required this.name,
    this.api,
    this.redacted = false,
  });

  final BlockKind kind;
  String id;
  String name;
  final ProviderApi? api;
  final bool redacted;
  final chunks = <String>[];
  String? signature;
  var closed = false;
  var argumentsInvalid = false;
  Map<String, Object?> arguments = const {};

  _BlockSnapshot snapshot(int length) => _BlockSnapshot(
    this,
    length,
    id,
    name,
    signature,
    closed ? arguments : const {},
  );
}

final class _BlockSnapshot {
  _BlockSnapshot(
    this.block,
    this.length,
    this.id,
    this.name,
    this.signature,
    this.arguments,
  );

  final _Block block;
  final int length;
  final String id;
  final String name;
  final String? signature;
  final Map<String, Object?> arguments;

  ContentBlock build() {
    final text = block.chunks.take(length).join();
    return switch (block.kind) {
      BlockKind.text => TextContent(text),
      BlockKind.thinking => ThinkingContent(
        text,
        signature: signature,
        redacted: block.redacted,
        api: block.api,
      ),
      BlockKind.toolCall => ToolCall(
        id: id,
        name: name,
        arguments: arguments,
        signature: signature,
      ),
    };
  }
}
