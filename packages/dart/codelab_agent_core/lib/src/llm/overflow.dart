/// Context overflow signs (`agent-core-architecture` §2.11).
library;

import 'errors.dart';
import 'messages.dart';

/// Phrases of overflow errors, compared case-insensitively.
const overflowPhrases = [
  'prompt is too long',
  'context length',
  'context window',
  'maximum context',
  'too many tokens',
  'exceeds the context',
  'input is too long',
  'reduce the length',
  'context_length_exceeded',
  'token limit',
];

/// Signs of a rate limit: an overflow phrase next to them is not overflow.
const rateLimitHints = ['rate limit', 'tokens per minute', 'per day', 'quota'];

/// Whether [text] says the context overflowed and does not talk about a
/// rate limit.
bool hasOverflowPhrase(String text) {
  final lower = text.toLowerCase();
  return overflowPhrases.any(lower.contains) &&
      !rateLimitHints.any(lower.contains);
}

final _overflowStatus = RegExp(r'^\S+ (400|413|422): ');

/// Whether [message] failed or ended because the context overflowed:
///
/// 1. the adapter set `errorClass: overflow` (an overflow code of the
///    provider);
/// 2. an error with HTTP status 400, 413 or 422 whose text has an overflow
///    phrase and no rate limit sign;
/// 3. silent overflow — `stop` with `input + cacheRead` above the window;
/// 4. `length` with no output at 99 % of the window or more.
///
/// The adapter applies rules 2–4 when it builds the message; the loop does
/// not retry such a request and hands it to compaction (§9).
bool isContextOverflow(AssistantMessage message, {required int contextWindow}) {
  if (message.errorClass == LlmErrorClass.overflow) {
    return true;
  }
  final error = message.errorMessage;
  if (message.stopReason == StopReason.error &&
      error != null &&
      _overflowStatus.hasMatch(error) &&
      hasOverflowPhrase(error)) {
    return true;
  }
  return silentOverflow(message, contextWindow: contextWindow) != null;
}

/// The note of rules 3 and 4 of [isContextOverflow], or `null`.
String? silentOverflow(AssistantMessage message, {required int contextWindow}) {
  final input = message.usage.input + message.usage.cacheRead;
  if (message.stopReason == StopReason.stop && input > contextWindow) {
    return 'context overflow: the input of $input tokens exceeds the context '
        'window of $contextWindow tokens';
  }
  if (message.stopReason == StopReason.length &&
      message.usage.output == 0 &&
      input >= 0.99 * contextWindow) {
    return 'context overflow: no output with an input of $input tokens in a '
        'context window of $contextWindow tokens';
  }
  return null;
}
