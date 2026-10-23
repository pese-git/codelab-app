import 'package:codelab_agent_core/codelab_agent_core.dart';
import 'package:codelab_agent_core/testing.dart';
import 'package:test/test.dart';

final _anthropic = ProviderConfig(
  name: 'anthropic',
  api: ProviderApi.anthropicMessages,
  baseUrl: Uri.parse('https://api.anthropic.com'),
);

final _local = ProviderConfig(
  name: 'ollama',
  api: ProviderApi.openaiChat,
  baseUrl: Uri.parse('http://localhost:11434/v1'),
);

const _builtIn = {
  'claude-opus-5-5': ModelInfo(
    contextWindow: 1000000,
    maxOutputTokens: 128000,
    cost: ModelCost(input: 4, output: 20, cacheRead: 0.2, cacheWrite: 5),
    supportsImages: true,
    supportsReasoning: true,
  ),
  'claude-opus': ModelInfo(contextWindow: 100, maxOutputTokens: 50),
  'tiny': ModelInfo(contextWindow: 1100, maxOutputTokens: 4096),
};

StaticModelCatalog _catalog(
  List<CatalogProvider> providers, {
  RecordingLogger? logger,
}) => StaticModelCatalog(
  providers,
  builtIn: _builtIn,
  logger: logger ?? RecordingLogger(),
);

void main() {
  test('models keep the config order; duplicates are dropped', () {
    final catalog = _catalog([
      CatalogProvider(
        _anthropic,
        models: const {
          'claude-opus-5-5': ModelInfo(),
          'claude-sonnet-5-5': ModelInfo(displayName: 'Sonnet'),
        },
      ),
      CatalogProvider(_local, models: const {'qwen3:4b': ModelInfo()}),
      CatalogProvider(
        _anthropic,
        models: const {'claude-opus-5-5': ModelInfo()},
      ),
    ]);

    expect(catalog.models.map((m) => m.id.value), [
      'anthropic/claude-opus-5-5',
      'anthropic/claude-sonnet-5-5',
      'ollama/qwen3:4b',
    ]);
    expect(catalog.models.map((m) => m.name), [
      'claude-opus-5-5',
      'Sonnet',
      'qwen3:4b',
    ]);
    expect(catalog.models.every((m) => m.fromConfig), isTrue);
  });

  test('ModelId splits provider and model at the first slash', () {
    const id = ModelId('openrouter/anthropic/claude-sonnet-4.5');

    expect(id.provider, 'openrouter');
    expect(id.model, 'anthropic/claude-sonnet-4.5');
  });

  test('resolve: config override, then built-in, then safe defaults', () {
    final catalog = _catalog([
      CatalogProvider(
        _anthropic,
        models: const {'claude-opus-5-5': ModelInfo(maxOutputTokens: 64000)},
      ),
    ]);

    final model = catalog.resolve(const ModelId('anthropic/claude-opus-5-5'))!;

    expect(model.provider, 'anthropic');
    expect(model.id, 'claude-opus-5-5');
    expect(model.api, ProviderApi.anthropicMessages);
    expect(model.baseUrl, Uri.parse('https://api.anthropic.com'));
    expect(model.contextWindow, 1000000);
    expect(model.maxOutputTokens, 64000);
    expect(model.cost?.input, 4);
    expect(model.supportsImages, isTrue);
    expect(model.supportsReasoning, isTrue);
    expect(model.hiddenReasoning, isFalse);
    final entry = catalog.models.single;
    expect(entry.provenance['contextWindow'], ModelInfoSource.builtIn);
    expect(entry.provenance['maxOutputTokens'], ModelInfoSource.override);
    expect(entry.provenance['hiddenReasoning'], ModelInfoSource.safeDefault);
  });

  test('built-in lookup by the longest prefix before "-" or the end', () {
    final catalog = _catalog([
      CatalogProvider(
        _anthropic,
        models: const {
          'claude-opus-5-5-20260101': ModelInfo(),
          'claude-opusx': ModelInfo(),
        },
      ),
      CatalogProvider(
        _local,
        models: const {'acme/claude-opus-5-5': ModelInfo()},
      ),
    ]);

    expect(
      catalog
          .resolve(const ModelId('anthropic/claude-opus-5-5-20260101'))!
          .contextWindow,
      1000000,
    );
    expect(
      catalog.resolve(const ModelId('anthropic/claude-opusx'))!.contextWindow,
      32000,
      reason: '"claude-opus" is not followed by "-" or the end',
    );
    expect(
      catalog
          .resolve(const ModelId('ollama/acme/claude-opus-5-5'))!
          .contextWindow,
      1000000,
      reason: 'the part after the last "/" is looked up too',
    );
  });

  test('maxOutputTokens is limited by the window minus 1024, at least 256', () {
    final catalog = _catalog([
      CatalogProvider(
        _local,
        models: const {
          'tiny': ModelInfo(),
          'micro': ModelInfo(contextWindow: 1000, maxOutputTokens: 4096),
        },
      ),
    ]);

    expect(catalog.resolve(const ModelId('ollama/tiny'))!.maxOutputTokens, 256);
    expect(
      catalog.resolve(const ModelId('ollama/micro'))!.maxOutputTokens,
      256,
    );
    final big = _catalog([
      CatalogProvider(
        _local,
        models: const {
          'big': ModelInfo(contextWindow: 10000, maxOutputTokens: 9500),
        },
      ),
    ]);
    expect(big.resolve(const ModelId('ollama/big'))!.maxOutputTokens, 8976);
  });

  test('unknown model resolves to safe defaults with one warning', () {
    final logger = RecordingLogger();
    final catalog = _catalog([
      CatalogProvider(_local, models: const {'qwen3:4b': ModelInfo()}),
    ], logger: logger);

    final model = catalog.resolve(const ModelId('ollama/qwen3:4b'))!;
    catalog.resolve(const ModelId('ollama/qwen3:4b'));

    expect(model.contextWindow, 32000);
    expect(model.maxOutputTokens, 4096);
    expect(model.supportsImages, isFalse);
    expect(model.supportsReasoning, isFalse);
    expect(model.cost, isNull);
    final warning = logger.eventsOf('llm.catalog.default_used').single;
    expect(warning.level, LogLevel.warning);
    expect(warning.fields['model'], 'ollama/qwen3:4b');
    expect(warning.fields['fields'], contains('contextWindow'));
  });

  test('reasoning effort only for a model with reasoning', () {
    final catalog = _catalog([
      CatalogProvider(
        _anthropic,
        models: const {'claude-opus-5-5': ModelInfo()},
      ),
      CatalogProvider(_local, models: const {'qwen3:4b': ModelInfo()}),
    ]);

    expect(
      catalog
          .resolve(
            const ModelId('anthropic/claude-opus-5-5'),
            effort: ReasoningEffort.high,
          )!
          .reasoningEffort,
      ReasoningEffort.high,
    );
    expect(
      catalog
          .resolve(
            const ModelId('ollama/qwen3:4b'),
            effort: ReasoningEffort.high,
          )!
          .reasoningEffort,
      isNull,
    );
  });

  test('a model outside the list resolves to null', () {
    final catalog = _catalog([
      CatalogProvider(_local, models: const {'qwen3:4b': ModelInfo()}),
    ]);

    expect(catalog.resolve(const ModelId('ollama/llama3')), isNull);
    expect(catalog.resolve(const ModelId('other/qwen3:4b')), isNull);
  });

  test('refresh does nothing and never throws', () async {
    final catalog = _catalog([
      CatalogProvider(_local, models: const {'qwen3:4b': ModelInfo()}),
    ]);
    var changes = 0;
    catalog.changes.listen((_) => changes++);

    await catalog.refresh(force: true);

    expect(changes, 0);
    expect(catalog.models, hasLength(1));
  });
}
