import 'dart:convert';
import 'dart:io';

import 'package:codelab_agent_core/codelab_agent_core.dart';
import 'package:codelab_agent_core/testing.dart';

/// Невалидный сценарий модели: не JSON, нет блока `llm`, поле не того вида
/// или файл не читается.
///
/// Почему отдельный тип: разбор сценария общий у бинаря (`--llm-script`) и
/// встроенного агента (`scriptedEmbeddedAgentOpener`), а перевод ошибки в
/// результат у них разный. Бинарь отвечает кодом `64` (`UsageError`),
/// встроенный открыватель — своим исключением; `UsageError` принадлежит
/// приложению и в IO-пакет не попадает (design.md change
/// `add-embedded-agent-mode`, D8).
///
/// Как использовать: ловить `on LlmScriptException`; [message] — готовый текст
/// с источником и путём поля (`llm.steps`), без значений секретов.
final class LlmScriptException implements Exception {
  const LlmScriptException(this.message);

  final String message;

  @override
  String toString() => 'LlmScriptException: $message';
}

/// Сценарий модели из блока `llm` фикстуры или файла `--llm-script` (документ
/// ядра §15.6, §14.7).
///
/// Почему: тестам клиентов (e2e codelab-app, транспортные фикстуры, драйвер
/// `codelab test-scenario`) нужен детерминированный агент без сети; формат —
/// блок `llm` фикстуры, чтобы сценарии писались так же, как фикстуры
/// (design.md change `add-codelab-agent-binary`, D3). Код перенесён из
/// `apps/codelab_agent`, чтобы бинарь и встроенный агент разбирали сценарий
/// одинаково (design.md change `add-embedded-agent-mode`, D8).
///
/// Как использовать: `LlmScript.load(path, models: …, clock: …, cwdOf: …)` для
/// файла `{"llm": {…}}` либо `LlmScript.fromJson(llm, …)` для готового блока;
/// невалидный сценарий — [LlmScriptException]. [models] — модели каталога:
/// `scripted/<id>` из `--model`, иначе модель `llm.model`.
final class LlmScript {
  LlmScript._(this.function, this.models);

  final ScriptedStreamFunction function;
  final List<ModelRef> models;

  /// Читает файл сценария `{"llm": {...}}` по пути [path].
  ///
  /// Тексты ошибок начинаются с `--llm-script <path>:` — прежний контракт
  /// бинаря (design.md change `add-embedded-agent-mode`, D8: «тексты ошибок
  /// прежние»).
  static LlmScript load(
    String path, {
    required List<ModelId> models,
    required Clock clock,
    required String? Function(String sessionId) cwdOf,
  }) => fromJson(
    _readLlm(path),
    models: models,
    clock: clock,
    cwdOf: cwdOf,
    source: _sourceOf(path),
  );

  /// Строит сценарий из готового блока [llm] (без обёртки `{"llm": …}`).
  ///
  /// [source] — начало текста ошибки: по умолчанию `llm`, у [load] —
  /// `--llm-script <path>`.
  static LlmScript fromJson(
    Map<String, Object?> llm, {
    required List<ModelId> models,
    required Clock clock,
    required String? Function(String sessionId) cwdOf,
    String source = 'llm',
  }) {
    final ScriptedStreamFunction function;
    try {
      function = ScriptedStreamFunction.fromJson(
        llm,
        clock: clock,
        cwdOf: cwdOf,
      );
    } on FormatException catch (error) {
      throw LlmScriptException('$source: ${error.message}');
    }
    return LlmScript._(function, _modelRefs(llm, models));
  }

  /// Модели сценария без построения функции: хост просит их до загрузки
  /// конфига, чтобы описать провайдера сценария слоем флагов (design.md
  /// change `add-agent-configuration`, D4). Те же правила, что у [load].
  static List<ModelRef> modelsOf(
    String path, {
    required List<ModelId> models,
  }) => _modelRefs(_readLlm(path), models);

  static String _sourceOf(String path) => '--llm-script $path';

  static Map<String, Object?> _readLlm(String path) {
    final Object? json;
    try {
      json = jsonDecode(File(path).readAsStringSync());
    } on FileSystemException catch (error) {
      throw LlmScriptException(
        '${_sourceOf(path)}: ${error.osError?.message ?? error.message}',
      );
    } on FormatException catch (error) {
      throw LlmScriptException(
        '${_sourceOf(path)}: invalid JSON: ${error.message}',
      );
    }
    return switch (json) {
      {'llm': final Map<String, Object?> llm} => llm,
      _ => throw LlmScriptException(
        '${_sourceOf(path)}: the file must be {"llm": {"model": {...}, '
        '"steps": [...]}}',
      ),
    };
  }

  static List<ModelRef> _modelRefs(
    Map<String, Object?> llm,
    List<ModelId> models,
  ) {
    final model = switch (llm['model']) {
      final Map<String, Object?> model => model,
      _ => const <String, Object?>{},
    };
    final window = model['contextWindow'] as int? ?? 32768;
    final ids = models.isNotEmpty
        ? models
        : [
            ModelId(
              '${model['provider'] as String? ?? 'scripted'}/'
              '${model['modelId'] as String? ?? 'scripted-1'}',
            ),
          ];
    return [
      for (final id in ids)
        ModelRef(
          provider: id.provider,
          id: id.model,
          api: ProviderApi.openaiChat,
          baseUrl: Uri.parse('http://scripted.invalid/v1'),
          contextWindow: window,
          maxOutputTokens: 4096,
        ),
    ];
  }
}
