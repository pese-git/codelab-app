import 'messages.dart';

/// Streaming events of a model answer (`agent-core-architecture` §2.3).
///
/// Grammar: the first event is [StartEvent] or, on a failure before the
/// response headers, [ErrorEvent]; blocks open with [BlockStartEvent], grow
/// with [BlockDeltaEvent] and close with [BlockEndEvent] of the same
/// `index`; several blocks may be open at once; all are closed before
/// [DoneEvent]; nothing follows the terminal event.
///
/// Every event carries the snapshot [partial] of the answer at that moment
/// (LLM-4). The snapshot is built lazily on first access and cached, so a
/// consumer that only needs the delta does not pay for it.
sealed class AssistantMessageEvent {
  AssistantMessageEvent(this._snapshot);

  final AssistantMessage Function() _snapshot;
  AssistantMessage? _partial;

  AssistantMessage get partial => _partial ??= _snapshot();

  /// The same event with the snapshot mapped by [map] — lazily, the way
  /// decorators add usage of failed attempts (§2.10.2).
  AssistantMessageEvent withPartial(
    AssistantMessage Function(AssistantMessage partial) map,
  ) {
    AssistantMessage snapshot() => map(partial);
    return switch (this) {
      StartEvent() => StartEvent(snapshot),
      BlockStartEvent(:final index, :final kind) => BlockStartEvent(
        snapshot,
        index: index,
        kind: kind,
      ),
      BlockDeltaEvent(:final index, :final delta) => BlockDeltaEvent(
        snapshot,
        index: index,
        delta: delta,
      ),
      BlockEndEvent(:final index, :final block) => BlockEndEvent(
        snapshot,
        index: index,
        block: block,
      ),
      DoneEvent() => DoneEvent(snapshot()),
      ErrorEvent(:final retryAfter) => ErrorEvent(
        snapshot(),
        retryAfter: retryAfter,
      ),
    };
  }
}

enum BlockKind { text, thinking, toolCall }

/// The response headers have arrived.
final class StartEvent extends AssistantMessageEvent {
  StartEvent(super.snapshot);
}

final class BlockStartEvent extends AssistantMessageEvent {
  BlockStartEvent(super.snapshot, {required this.index, required this.kind});

  /// Position of the block in `partial.content`.
  final int index;
  final BlockKind kind;
}

final class BlockDeltaEvent extends AssistantMessageEvent {
  BlockDeltaEvent(super.snapshot, {required this.index, required this.delta});

  final int index;

  /// Text, reasoning, or a raw JSON fragment of tool call arguments.
  final String delta;
}

final class BlockEndEvent extends AssistantMessageEvent {
  BlockEndEvent(super.snapshot, {required this.index, required this.block});

  final int index;

  /// The closed block; a tool call has parsed arguments (LLM-6).
  final ContentBlock block;
}

final class DoneEvent extends AssistantMessageEvent {
  DoneEvent(AssistantMessage message) : super(() => message);

  AssistantMessage get message => partial;
}

final class ErrorEvent extends AssistantMessageEvent {
  ErrorEvent(AssistantMessage error, {this.retryAfter}) : super(() => error);

  /// `stopReason` error or aborted, `errorMessage`, `errorClass`, and the
  /// content received before the failure.
  AssistantMessage get error => partial;

  /// From the headers of 429 and 503, when present.
  final Duration? retryAfter;
}
