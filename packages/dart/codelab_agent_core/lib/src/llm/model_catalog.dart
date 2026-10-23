import 'dart:math';

import '../util/logger.dart';
import 'builtin_models.dart';
import 'model_ref.dart';
import 'provider_config.dart';

/// Model catalog (`agent-core-architecture` §2.12.2): the only source of
/// [ModelRef] for the core — the model list of the `model` option and the
/// metadata of each model. Stage 1 has the port and [StaticModelCatalog]
/// without network; the endpoint `/models`, the remote metadata catalog, the
/// disk cache and the background refresh come at stage 8 (L-15).

/// `"<provider>/<model>"`; the model part may contain `/`.
extension type const ModelId(String value) {
  String get provider => value.substring(0, value.indexOf('/'));

  String get model => value.substring(value.indexOf('/') + 1);
}

/// Model metadata from one source; `null` — the source does not know it.
final class ModelInfo {
  const ModelInfo({
    this.displayName,
    this.contextWindow,
    this.maxOutputTokens,
    this.cost,
    this.supportsImages,
    this.supportsReasoning,
    this.hiddenReasoning,
  });

  final String? displayName;
  final int? contextWindow, maxOutputTokens;
  final ModelCost? cost;
  final bool? supportsImages, supportsReasoning, hiddenReasoning;
}

/// Where a field of a resolved model came from.
enum ModelInfoSource {
  override,
  role,
  endpoint,
  remoteCatalog,
  builtIn,
  safeDefault,
}

final class ModelEntry {
  const ModelEntry({
    required this.id,
    required this.name,
    required this.fromConfig,
    required this.provenance,
  });

  final ModelId id;

  /// Name for the selector.
  final String name;

  /// The model is declared in the config.
  final bool fromConfig;

  /// Field of [ModelInfo] → its source (for `/status` and tests).
  final Map<String, ModelInfoSource> provenance;
}

abstract interface class ModelCatalog {
  /// In the publication order: the config order of providers and models.
  List<ModelEntry> get models;

  /// `null` — the model is not in the list. [effort] is the effective
  /// reasoning level of the session; it reaches only a model with
  /// reasoning (§2.12.3).
  ModelRef? resolve(ModelId id, {ReasoningEffort? effort});

  /// The list or the metadata changed.
  Stream<void> get changes;

  /// Background update; never throws.
  Future<void> refresh({bool force = false});
}

/// A provider with the models its config declares, in config order.
final class CatalogProvider {
  const CatalogProvider(this.config, {this.models = const {}});

  final ProviderConfig config;

  /// Model id at the provider → explicit values of the config
  /// (`providers.<id>.models.<model>`, §15.4).
  final Map<String, ModelInfo> models;
}

/// Catalog of the models from the config or the binary flags, resolved by
/// the explicit values, then the built-in table, then the safe defaults
/// (window 32 000, max output 4 096, no images, no reasoning, unknown
/// prices). No network; [refresh] does nothing.
final class StaticModelCatalog implements ModelCatalog {
  StaticModelCatalog(
    List<CatalogProvider> providers, {
    Map<String, ModelInfo> builtIn = builtinModels,
    required Logger logger,
  }) : _builtIn = builtIn,
       _logger = logger {
    for (final provider in providers) {
      for (final MapEntry(key: model, value: info) in provider.models.entries) {
        final id = ModelId('${provider.config.name}/$model');
        if (_known.containsKey(id)) {
          continue;
        }
        _known[id] = (provider.config, info);
      }
    }
    _models = List.unmodifiable([
      for (final MapEntry(key: id, value: (_, info)) in _known.entries)
        ModelEntry(
          id: id,
          name: info.displayName ?? id.model,
          fromConfig: true,
          provenance: Map.unmodifiable(_resolveFields(id, info).provenance),
        ),
    ]);
  }

  final Map<String, ModelInfo> _builtIn;
  final Logger _logger;
  final _known = <ModelId, (ProviderConfig, ModelInfo)>{};
  late final List<ModelEntry> _models;
  final _warned = <ModelId>{};

  @override
  List<ModelEntry> get models => _models;

  @override
  Stream<void> get changes => const Stream.empty();

  @override
  Future<void> refresh({bool force = false}) async {}

  @override
  ModelRef? resolve(ModelId id, {ReasoningEffort? effort}) {
    final known = _known[id];
    if (known == null) {
      return null;
    }
    final (config, info) = known;
    final fields = _resolveFields(id, info);
    // Unknown prices are not warned about: a local model has none.
    final defaults = [
      for (final MapEntry(:key, :value) in fields.provenance.entries)
        if (value == ModelInfoSource.safeDefault && key != 'cost') key,
    ];
    if (defaults.isNotEmpty && _warned.add(id)) {
      _logger.log(
        LogLevel.warning,
        'llm.catalog.default_used',
        fields: {'model': id.value, 'fields': defaults},
      );
    }
    final window = fields.contextWindow;
    final reasoning = fields.supportsReasoning;
    return ModelRef(
      provider: config.name,
      id: id.model,
      api: config.api,
      baseUrl: config.baseUrl,
      contextWindow: window,
      maxOutputTokens: max(256, min(fields.maxOutputTokens, window - 1024)),
      cost: fields.cost,
      supportsImages: fields.supportsImages,
      supportsReasoning: reasoning,
      reasoningEffort: reasoning ? effort : null,
      hiddenReasoning: fields.hiddenReasoning,
    );
  }

  _Fields _resolveFields(ModelId id, ModelInfo override) {
    final builtIn = _lookupBuiltIn(id.model);
    final provenance = <String, ModelInfoSource>{};
    T pick<T>(String field, T? Function(ModelInfo info) read, T fallback) {
      for (final (source, info) in [
        (ModelInfoSource.override, override),
        (ModelInfoSource.builtIn, builtIn),
      ]) {
        if (info == null) {
          continue;
        }
        final value = read(info);
        if (value != null) {
          provenance[field] = source;
          return value;
        }
      }
      provenance[field] = ModelInfoSource.safeDefault;
      return fallback;
    }

    return _Fields(
      contextWindow: pick('contextWindow', (i) => i.contextWindow, 32000),
      maxOutputTokens: pick('maxOutputTokens', (i) => i.maxOutputTokens, 4096),
      cost: pick<ModelCost?>('cost', (i) => i.cost, null),
      supportsImages: pick('supportsImages', (i) => i.supportsImages, false),
      supportsReasoning: pick(
        'supportsReasoning',
        (i) => i.supportsReasoning,
        false,
      ),
      hiddenReasoning: pick('hiddenReasoning', (i) => i.hiddenReasoning, false),
      provenance: provenance,
    );
  }

  /// Exact id; then the longest key that is a prefix of the id followed by
  /// `-` or the end (`claude-opus-5-5` finds `claude-opus-5-5-20260101`);
  /// then the same for the part after the last `/`.
  ModelInfo? _lookupBuiltIn(String model) {
    for (final candidate in {
      model,
      model.substring(model.lastIndexOf('/') + 1),
    }) {
      if (_builtIn[candidate] case final info?) {
        return info;
      }
      String? best;
      for (final key in _builtIn.keys) {
        final fits =
            candidate.startsWith(key) &&
            (candidate.length == key.length || candidate[key.length] == '-');
        if (fits && (best == null || key.length > best.length)) {
          best = key;
        }
      }
      if (best != null) {
        return _builtIn[best];
      }
    }
    return null;
  }
}

final class _Fields {
  const _Fields({
    required this.contextWindow,
    required this.maxOutputTokens,
    required this.cost,
    required this.supportsImages,
    required this.supportsReasoning,
    required this.hiddenReasoning,
    required this.provenance,
  });

  final int contextWindow, maxOutputTokens;
  final ModelCost? cost;
  final bool supportsImages, supportsReasoning, hiddenReasoning;
  final Map<String, ModelInfoSource> provenance;
}
