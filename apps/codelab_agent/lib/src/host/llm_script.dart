import 'dart:convert';
import 'dart:io';

import 'package:codelab_agent_core/codelab_agent_core.dart';
import 'package:codelab_agent_core/testing.dart';

import '../cli/serve_args.dart';

/// Сценарий модели из файла `--llm-script` (документ ядра §15.6, §14.7).
///
/// Почему: тестам клиентов (e2e codelab-app, транспортные фикстуры) нужен
/// детерминированный агент без сети; формат файла — блок `llm` фикстуры,
/// чтобы сценарии писались так же, как фикстуры (design.md change
/// `add-codelab-agent-binary`, D3).
///
/// Как использовать: `LlmScript.load(path, models: …, clock: …,
/// cwdOf: …)`; невалидный файл — [UsageError] с путём поля. [models] —
/// модели каталога: `scripted/<id>` из `--model`, иначе модель `llm.model`.
final class LlmScript {
  LlmScript._(this.function, this.models);

  final ScriptedStreamFunction function;
  final List<ModelRef> models;

  static LlmScript load(
    String path, {
    required List<ModelId> models,
    required Clock clock,
    required String? Function(String sessionId) cwdOf,
  }) {
    final Object? json;
    try {
      json = jsonDecode(File(path).readAsStringSync());
    } on FileSystemException catch (error) {
      throw UsageError(
        '--llm-script $path: ${error.osError?.message ?? error.message}',
      );
    } on FormatException catch (error) {
      throw UsageError('--llm-script $path: invalid JSON: ${error.message}');
    }
    final llm = switch (json) {
      {'llm': final Map<String, Object?> llm} => llm,
      _ => throw UsageError(
        '--llm-script $path: the file must be {"llm": {"model": {...}, '
        '"steps": [...]}}',
      ),
    };
    final ScriptedStreamFunction function;
    try {
      function = ScriptedStreamFunction.fromJson(
        llm,
        clock: clock,
        cwdOf: cwdOf,
      );
    } on FormatException catch (error) {
      throw UsageError('--llm-script $path: ${error.message}');
    }
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
    return LlmScript._(function, [
      for (final id in ids)
        ModelRef(
          provider: id.provider,
          id: id.model,
          api: ProviderApi.openaiChat,
          baseUrl: Uri.parse('http://scripted.invalid/v1'),
          contextWindow: window,
          maxOutputTokens: 4096,
        ),
    ]);
  }
}

/// Журнал в памяти, который помнит рабочую папку каждой сессии.
///
/// Почему: шаги `--llm-script` общие для сессий процесса, а `${cwd}` —
/// папка сессии запроса (D3). Сценарий узнаёт её по id сессии
/// (`LlmContext.cacheKey`) через [cwdOf].
final class CwdTrackingStore implements SessionStore {
  final _inner = MemorySessionStore();
  final _cwd = <String, String>{};

  String? cwdOf(String sessionId) => _cwd[sessionId];

  @override
  Future<void> create(SessionHeader header) {
    _cwd[header.id.value] = header.cwd;
    return _inner.create(header);
  }

  @override
  Future<void> append(
    SessionId id,
    SessionRecord record, {
    bool durable = false,
  }) => _inner.append(id, record, durable: durable);

  @override
  Future<void> flush(SessionId id) => _inner.flush(id);

  @override
  Future<SessionSnapshot> open(SessionId id) => _inner.open(id);

  @override
  Future<SessionPage> list({String? cwd, String? cursor, int pageSize = 50}) =>
      _inner.list(cwd: cwd, cursor: cursor, pageSize: pageSize);

  @override
  Future<void> close(SessionId id) => _inner.close(id);
}
