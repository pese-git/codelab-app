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

/// Одна запись провайдера с готовыми значениями (§2.7; design.md, D3).
///
/// Почему так: у записи из конфига этапа 8 `${ENV}` в заголовках уже
/// раскрыт, а ключ и заголовки со `${secret:…}` — ещё ссылки
/// (`CatalogProvider.key`, `headerTemplates`). Их читает
/// `createRoutedStreamFunction` при первом запросе и кладёт сюда через
/// [copyWith] (design.md change `add-agent-secret-store`, D4).
///
/// Для чего: единый вход адаптеров. Умолчания, зависящие от хоста [baseUrl],
/// вычисляются здесь, поэтому конфиг этапа 8 только переопределяет их.
///
/// Как использовать: хост, собирающий запись вручную, может сразу задать
/// [apiKey]. Значения, которые нельзя показывать, перечисляет [secrets].
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
    List<String> extraSecrets = const [],
  }) : authHeader =
           authHeader ??
           (api == ProviderApi.anthropicMessages
               ? 'x-api-key'
               : 'Authorization'),
       headers = Map.unmodifiable(headers),
       extraSecrets = List.unmodifiable(extraSecrets),
       reasoningFormat =
           reasoningFormat ??
           (baseUrl.host == 'openrouter.ai'
               ? ReasoningFormat.openrouter
               : ReasoningFormat.openai),
       anthropicBeta = List.unmodifiable(anthropicBeta),
       promptCacheKey = promptCacheKey ?? baseUrl.host == 'api.openai.com';

  /// Имя для ссылок `"<name>/<model>"`.
  final String name;
  final ProviderApi api;
  final Uri baseUrl;

  /// Значение ключа, если оно уже есть у хоста. `null` — запросы без
  /// авторизации (локальные серверы) либо ключ — ссылка, которую
  /// `createRoutedStreamFunction` разрешает при первом запросе (design.md
  /// change `add-agent-secret-store`, D4).
  final String? apiKey;

  /// `Authorization` — `Bearer <key>`; любое другое имя — ключ как есть.
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

  /// Исходные значения секретов, из которых собраны [headers] по шаблонам
  /// (`Bearer ${secret:x}` → `x`). Собранная строка заголовка не равна
  /// значению секрета, а тело ответа провайдера может повторить только
  /// значение; без этого списка вычистка его не нашла бы (design.md change
  /// `add-agent-secret-store`, D7).
  final List<String> extraSecrets;

  /// Копия с разрешёнными значениями ключа и заголовков (остальные поля те
  /// же). Зовёт `createRoutedStreamFunction` после чтения секретов (D4);
  /// [apiKey] `null` оставляет прежний ключ, [extraSecrets] дополняют
  /// прежние.
  ProviderConfig copyWith({
    String? apiKey,
    Map<String, String>? headers,
    List<String> extraSecrets = const [],
  }) => ProviderConfig(
    name: name,
    api: api,
    baseUrl: baseUrl,
    apiKey: apiKey ?? this.apiKey,
    authHeader: authHeader,
    headers: headers ?? this.headers,
    maxTokensField: maxTokensField,
    includeUsage: includeUsage,
    reasoningFormat: reasoningFormat,
    systemRole: systemRole,
    anthropicVersion: anthropicVersion,
    anthropicBeta: anthropicBeta,
    promptCacheKey: promptCacheKey,
    listModels: listModels,
    timeouts: timeouts,
    retry: retry,
    extraSecrets: [...this.extraSecrets, ...extraSecrets],
  );

  /// Значения, которые не попадают в тексты ошибок и логи: ключ, значения
  /// заголовков и исходные значения секретов шаблонов (design.md, D7).
  List<String> get secrets => [
    if (apiKey case final key? when key.isNotEmpty) key,
    for (final value in headers.values)
      if (value.isNotEmpty) value,
    for (final value in extraSecrets)
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
