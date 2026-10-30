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
    final llm = _readLlm(path);
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
    return LlmScript._(function, _modelRefs(llm, models));
  }

  /// Модели сценария без построения функции: хост просит их до загрузки
  /// конфига, чтобы описать провайдера сценария слоем флагов (design.md
  /// change `add-agent-configuration`, D4). Те же правила, что у [load].
  static List<ModelRef> modelsOf(
    String path, {
    required List<ModelId> models,
  }) => _modelRefs(_readLlm(path), models);

  static Map<String, Object?> _readLlm(String path) {
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
    return switch (json) {
      {'llm': final Map<String, Object?> llm} => llm,
      _ => throw UsageError(
        '--llm-script $path: the file must be {"llm": {"model": {...}, '
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

/// Журнал сценария, который помнит рабочую папку каждой сессии.
///
/// Почему: шаги `--llm-script` общие для сессий процесса, а `${cwd}` —
/// папка сессии запроса (D3 change `add-codelab-agent-binary`). Сценарий
/// узнаёт её по id сессии (`LlmContext.cacheKey`) через [cwdOf]. Папка
/// запоминается и при [open]: сессию, загруженную `session/load` после
/// перезапуска процесса, никто не создаёт заново (D2 change
/// `add-llm-script-session-store`).
///
/// Как использовать: хост оборачивает хранилище сценария —
/// `CwdTrackingStore(MemorySessionStore())` без `--sessions-dir`,
/// `CwdTrackingStore(JsonlSessionStore(...))` с ним — и передаёт [cwdOf] в
/// `LlmScript.load`.
final class CwdTrackingStore implements SessionStore {
  CwdTrackingStore(this._inner);

  final SessionStore _inner;
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
  Future<SessionSnapshot> open(SessionId id) async {
    final snapshot = await _inner.open(id);
    _cwd[snapshot.header.id.value] = snapshot.header.cwd;
    return snapshot;
  }

  @override
  Future<SessionPage> list({String? cwd, String? cursor, int pageSize = 50}) =>
      _inner.list(cwd: cwd, cursor: cursor, pageSize: pageSize);

  @override
  Future<void> close(SessionId id) => _inner.close(id);
}
