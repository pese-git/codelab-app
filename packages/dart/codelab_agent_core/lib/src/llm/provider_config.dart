import 'dart:math';

import 'package:http/http.dart' as http;

import '../util/clock.dart';
import '../util/logger.dart';
import 'decorators/retry.dart';
import 'model_ref.dart';

/// How a provider expects the reasoning level (§2.12.3).
enum ReasoningFormat { openai, openrouter, none }

/// Watchdog durations of a provider (§2.10.1, §2.10.5, §15.4).
final class LlmTimeouts {
  /// [idleReasoning] shorter than [idle] is a configuration error (§15.5).
  factory LlmTimeouts({
    Duration connect = const Duration(seconds: 30),
    Duration idle = const Duration(seconds: 120),
    Duration idleReasoning = const Duration(seconds: 600),
  }) {
    if (idleReasoning < idle) {
      throw ArgumentError.value(
        idleReasoning,
        'idleReasoning',
        'must not be shorter than idle ($idle)',
      );
    }
    return LlmTimeouts._(connect, idle, idleReasoning);
  }

  const LlmTimeouts._(this.connect, this.idle, this.idleReasoning);

  static const defaults = LlmTimeouts._(
    Duration(seconds: 30),
    Duration(seconds: 120),
    Duration(seconds: 600),
  );

  /// No response headers within this time.
  final Duration connect;

  /// Pause between stream events.
  final Duration idle;

  /// Pause before the first content block of a model with hidden reasoning.
  final Duration idleReasoning;
}

/// One provider entry, already resolved by the host: the key is read from
/// the secret store, `${ENV}` in headers is expanded (§2.7, design.md, D3).
/// Defaults that depend on the host of [baseUrl] are computed here, so the
/// config of stage 8 only overrides them.
final class ProviderConfig {
  ProviderConfig({
    required this.name,
    required this.api,
    required this.baseUrl,
    this.apiKey,
    String? authHeader,
    Map<String, String> headers = const {},
    this.maxTokensField = 'max_completion_tokens',
    this.includeUsage = true,
    ReasoningFormat? reasoningFormat,
    this.systemRole = 'system',
    this.anthropicVersion = '2023-06-01',
    List<String> anthropicBeta = const [],
    bool? promptCacheKey,
    this.listModels = true,
    this.timeouts = LlmTimeouts.defaults,
    this.retry = const RetryPolicy(),
  }) : authHeader =
           authHeader ??
           (api == ProviderApi.anthropicMessages
               ? 'x-api-key'
               : 'Authorization'),
       headers = Map.unmodifiable(headers),
       reasoningFormat =
           reasoningFormat ??
           (baseUrl.host == 'openrouter.ai'
               ? ReasoningFormat.openrouter
               : ReasoningFormat.openai),
       anthropicBeta = List.unmodifiable(anthropicBeta),
       promptCacheKey = promptCacheKey ?? baseUrl.host == 'api.openai.com';

  /// Name for `"<name>/<model>"` references.
  final String name;
  final ProviderApi api;
  final Uri baseUrl;

  /// Already read from the secret store; `null` — no authorization (local
  /// servers).
  final String? apiKey;

  /// `Authorization` — `Bearer <key>`; any other name — the key as is.
  final String authHeader;
  final Map<String, String> headers;

  /// `max_completion_tokens` | `max_tokens` | `null` (not sent).
  final String? maxTokensField;

  /// `stream_options.include_usage`.
  final bool includeUsage;
  final ReasoningFormat reasoningFormat;

  /// `system` | `developer`.
  final String systemRole;
  final String anthropicVersion;
  final List<String> anthropicBeta;

  /// Send `prompt_cache_key` (§2.12.1); OpenAI-compatible only.
  final bool promptCacheKey;

  /// Ask the endpoint for its model list (§2.12.2, stage 8).
  final bool listModels;
  final LlmTimeouts timeouts;
  final RetryPolicy retry;

  /// Values that never reach error texts and logs: the key and the header
  /// values (design.md, D7).
  List<String> get secrets => [
    if (apiKey case final key? when key.isNotEmpty) key,
    for (final value in headers.values)
      if (value.isNotEmpty) value,
  ];
}

/// Host ports the LLM layer needs (PKG-6, §2.10).
final class CoreLlmServices {
  const CoreLlmServices({
    required this.httpClient,
    required this.clock,
    required this.random,
    required this.logger,
  });

  final http.Client httpClient;
  final Clock clock;
  final Random random;
  final Logger logger;
}
