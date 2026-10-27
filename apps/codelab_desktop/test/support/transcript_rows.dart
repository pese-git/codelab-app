import 'package:codelab_ui/codelab_ui.dart';

/// Короткие проверки строк ленты в тестах.
///
/// Почему: строки ленты — запечатанная иерархия без общих полей «заголовок»
/// и «тело» (design D1 change `redesign-transcript-rows`), а тестам
/// поведения достаточно текста строки и её вида.
///
/// Для чего: [text] — текст сообщения, ответа, мыслей или заметки, у вызова —
/// «метка деталь»; [kind] — вид строки словом; [approval] — одобрение
/// вызова или `null` у остальных строк.
///
/// Как использовать: `state.transcriptRows.last.text`; импортируют и
/// widget-, и e2e-тесты.
extension TranscriptRowForTests on CodeLabTranscriptRow {
  String get text => switch (this) {
    CodeLabUserRow(:final text) ||
    CodeLabAgentTextRow(:final text) ||
    CodeLabThoughtRow(:final text) => text,
    CodeLabToolCallRow(:final label, :final detail) => [
      label,
      detail,
    ].where((part) => part.isNotEmpty).join(' '),
    CodeLabNoticeRow(:final body) => body,
  };

  String get kind => switch (this) {
    CodeLabUserRow() => 'user',
    CodeLabAgentTextRow() => 'agent',
    CodeLabThoughtRow() => 'thought',
    CodeLabToolCallRow() => 'tool',
    CodeLabNoticeRow() => 'notice',
  };

  CodeLabTranscriptApproval? get approval => switch (this) {
    CodeLabToolCallRow(:final approval) => approval,
    _ => null,
  };
}
