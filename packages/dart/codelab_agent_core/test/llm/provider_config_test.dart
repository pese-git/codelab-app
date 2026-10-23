import 'package:codelab_agent_core/codelab_agent_core.dart';
import 'package:test/test.dart';

ProviderConfig _config(
  String baseUrl, {
  ProviderApi api = ProviderApi.openaiChat,
}) => ProviderConfig(name: 'p', api: api, baseUrl: Uri.parse(baseUrl));

void main() {
  test('prompt_cache_key is on by default only for api.openai.com', () {
    expect(_config('https://api.openai.com/v1').promptCacheKey, isTrue);
    expect(_config('https://openrouter.ai/api/v1').promptCacheKey, isFalse);
    expect(_config('http://localhost:11434/v1').promptCacheKey, isFalse);
    expect(
      ProviderConfig(
        name: 'p',
        api: ProviderApi.openaiChat,
        baseUrl: Uri.parse('http://localhost:1234/v1'),
        promptCacheKey: true,
      ).promptCacheKey,
      isTrue,
    );
  });

  test('reasoning format is openrouter for openrouter.ai, else openai', () {
    expect(
      _config('https://openrouter.ai/api/v1').reasoningFormat,
      ReasoningFormat.openrouter,
    );
    expect(
      _config('https://api.openai.com/v1').reasoningFormat,
      ReasoningFormat.openai,
    );
  });

  test('auth header defaults by api', () {
    expect(_config('https://api.openai.com/v1').authHeader, 'Authorization');
    expect(
      _config(
        'https://api.anthropic.com',
        api: ProviderApi.anthropicMessages,
      ).authHeader,
      'x-api-key',
    );
  });

  test('defaults of §2.7 and §2.10', () {
    final config = _config('https://api.openai.com/v1');

    expect(config.maxTokensField, 'max_completion_tokens');
    expect(config.includeUsage, isTrue);
    expect(config.systemRole, 'system');
    expect(config.anthropicVersion, '2023-06-01');
    expect(config.anthropicBeta, isEmpty);
    expect(config.timeouts.connect, const Duration(seconds: 30));
    expect(config.timeouts.idle, const Duration(seconds: 120));
    expect(config.timeouts.idleReasoning, const Duration(seconds: 600));
    expect(config.retry.maxAttempts, 4);
    expect(config.retry.rateLimitRetries, 3);
  });

  test('idleReasoning below idle is a configuration error', () {
    expect(
      () => LlmTimeouts(
        idle: const Duration(seconds: 120),
        idleReasoning: const Duration(seconds: 60),
      ),
      throwsArgumentError,
    );
  });

  test('the secrets of a config are the key and the header values', () {
    final config = ProviderConfig(
      name: 'p',
      api: ProviderApi.openaiChat,
      baseUrl: Uri.parse('https://api.openai.com/v1'),
      apiKey: 'sk-1',
      headers: const {'OpenAI-Organization': 'org-1'},
    );

    expect(config.secrets, unorderedEquals(['sk-1', 'org-1']));
  });
}
