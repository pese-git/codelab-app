import 'dart:async';

import '../errors.dart';
import '../event_stream.dart';
import '../events.dart';
import '../model_ref.dart';
import '../stream_function.dart';
import '../usage.dart';
import 'retry.dart';

/// A switch to the next model of a fallback chain.
final class FallbackNotice {
  const FallbackNotice({
    required this.from,
    required this.to,
    required this.cause,
    required this.message,
  });

  final ModelRef from, to;
  final LlmErrorClass cause;
  final String message;
}

/// Classes that switch to the next model: the model is unavailable, not
/// the request wrong or forbidden (`agent-core-architecture` §2.10.3).
const _switching = {
  LlmErrorClass.rateLimited,
  LlmErrorClass.server,
  LlmErrorClass.network,
  LlmErrorClass.timeout,
  LlmErrorClass.auth,
  LlmErrorClass.unknown,
};

/// Tries the models of [chain] in order (§2.10.3). Each model is called
/// through [forModel] — already wrapped by retry and watchdogs — and the
/// chain is used whatever model the caller passes. An `ErrorEvent` before
/// the commit with a switching class moves to the next model without a
/// delay and reports [FallbackNotice]; after the commit the error goes to
/// the consumer as is (LLM-8). A chain of one model is transparent. The
/// result carries the model that answered and the usage of all models.
StreamFunction withFallback(
  List<ModelRef> chain,
  StreamFunction Function(ModelRef model) forModel, {
  required void Function(FallbackNotice notice) onNotice,
}) => (model, context, {cancel}) {
  final out = AssistantMessageEventStream();
  scheduleMicrotask(() async {
    var failedUsage = Usage.zero;
    var startForwarded = false;
    try {
      for (var i = 0; i < chain.length; i++) {
        final current = chain[i];
        var committed = false;
        StartEvent? bufferedStart;
        ErrorEvent? failure;
        await for (final event in forModel(current)(
          current,
          context,
          cancel: cancel,
        )) {
          if (committed) {
            out.push(addUsage(event, failedUsage));
            continue;
          }
          switch (event) {
            case StartEvent():
              bufferedStart = event;
            case BlockStartEvent() || DoneEvent():
              committed = true;
              if (!startForwarded && bufferedStart != null) {
                out.push(addUsage(bufferedStart, failedUsage));
                startForwarded = true;
              }
              out.push(addUsage(event, failedUsage));
            case ErrorEvent():
              failure = event;
            case BlockDeltaEvent() || BlockEndEvent():
              out.push(addUsage(event, failedUsage));
          }
        }
        if (failure == null) {
          break;
        }
        final cls = failure.error.errorClass ?? LlmErrorClass.unknown;
        final hasNext = i + 1 < chain.length;
        if (!hasNext ||
            !_switching.contains(cls) ||
            (cancel?.isCancelled ?? false)) {
          if (!startForwarded && bufferedStart != null) {
            out.push(addUsage(bufferedStart, failedUsage));
          }
          out.push(addUsage(failure, failedUsage));
          break;
        }
        failedUsage += failure.error.usage;
        final next = chain[i + 1];
        onNotice(
          FallbackNotice(
            from: current,
            to: next,
            cause: cls,
            message: cls == LlmErrorClass.rateLimited
                ? 'Model ${current.provider}/${current.id} hit a rate limit; '
                      'switched to ${next.provider}/${next.id}.'
                : 'Model ${current.provider}/${current.id} failed '
                      '(${cls.name}); switched to ${next.provider}/${next.id}.',
          ),
        );
      }
    } finally {
      out.end();
    }
  });
  return out;
};
