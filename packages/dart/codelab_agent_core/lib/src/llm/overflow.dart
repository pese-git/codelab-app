/// Context overflow signs (`agent-core-architecture` §2.11).
library;

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
