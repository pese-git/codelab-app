import 'package:codelab_agent_core/codelab_agent_core.dart';
import 'package:codelab_agent_core/src/session/user_words.dart';

import '../support/models.dart';

/// Записи региона сжатия с заданной оценкой в токенах (§9.3): текст длиной
/// `(tokens - 4) * 4` символов даёт ровно `tokens`.
final class RegionBuilder {
  final records = <SessionRecord>[];
  final _at = DateTime.utc(2026);
  var _n = 0;

  String _id() => 'r${(_n++).toString().padLeft(7, '0')}';

  String? get _parent => records.isEmpty ? null : records.last.id;

  String _text(int tokens, String fill) => fill * ((tokens - 4) * 4);

  void _message(Message message, {RecordOrigin? origin}) {
    final fields = switch (origin) {
      RecordOrigin.loopNudge => originFieldsOf(
        const LoopNudgeOrigin(LoopNudgeReason.emptyResponse, 1),
      ),
      _ => null,
    };
    records.add(
      MessageRecord(
        id: _id(),
        parentId: _parent,
        timestamp: _at,
        message: message,
        origin: fields?.origin,
        nudge: fields?.nudge,
        attempt: fields?.attempt,
      ),
    );
  }

  /// Слова пользователя (`isUserWords`).
  void user(int tokens, {String fill = 'u'}) =>
      _message(UserMessage([TextContent(_text(tokens, fill))], timestamp: _at));

  /// Подсказка цикла — служебное user-сообщение, не ход пользователя.
  void nudge(int tokens) => _message(
    UserMessage([TextContent(_text(tokens, 'n'))], timestamp: _at),
    origin: RecordOrigin.loopNudge,
  );

  void assistant(int tokens) =>
      _message(_answer([TextContent(_text(tokens, 'a'))]));

  /// Ответ с одним вызовом [name] (`{"path": ...}`).
  void call(String callId, String name, {String path = 'a.txt'}) => _message(
    _answer([
      ToolCall(id: callId, name: name, arguments: {'path': path}),
    ], stop: StopReason.toolUse),
  );

  /// Ответ с несколькими вызовами.
  void calls(List<String> callIds, String name) => _message(
    _answer([
      for (final id in callIds)
        ToolCall(id: id, name: name, arguments: {'path': '$id.txt'}),
    ], stop: StopReason.toolUse),
  );

  /// Результат: `content + ceil(name / 4) + 4 = tokens`.
  void result(String callId, String name, int tokens) {
    final content = (tokens - 4 - (name.length / 4).ceil()) * 4;
    _message(
      ToolResultMessage(
        toolCallId: callId,
        toolName: name,
        content: [TextContent('o' * content)],
        isError: false,
        timestamp: _at,
      ),
    );
  }

  void modeChange(String mode) => records.add(
    ModeChangeRecord(
      id: _id(),
      parentId: _parent,
      timestamp: _at,
      modeId: mode,
    ),
  );

  void plan() => records.add(
    PlanRecord(id: _id(), parentId: _parent, timestamp: _at, entries: const []),
  );

  void modelChange() => records.add(
    ModelChangeRecord(
      id: _id(),
      parentId: _parent,
      timestamp: _at,
      provider: testModel.provider,
      modelId: testModel.id,
    ),
  );

  AssistantMessage _answer(
    List<ContentBlock> content, {
    StopReason stop = StopReason.stop,
  }) => AssistantMessage(
    content: content,
    model: testModel,
    usage: Usage.zero,
    stopReason: stop,
    timestamp: _at,
  );
}
