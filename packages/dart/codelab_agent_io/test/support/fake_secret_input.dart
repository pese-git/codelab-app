import 'package:codelab_agent_io/codelab_agent_io.dart';

/// Фейковый ввод `secret set` для тестов `SecretCommands` (design.md change
/// `add-agent-secret-store`, D8).
///
/// Почему фейк: настоящий stdin процесса в тесте недоступен, а порядок
/// «проверки до чтения значения» (D8) и выбор ветки TTY/не-TTY нужно видеть.
///
/// Как использовать: [hasTerminal] и [text] задают сценарий; [events] —
/// журнал обращений (`readHidden:<prompt>`, `readAll`), общий с фейковым
/// хранилищем, если тесту нужен порядок между ними.
final class FakeSecretInput implements SecretInput {
  FakeSecretInput(
    this.text, {
    this.hasTerminal = false,
    this.failure,
    List<String>? events,
  }) : events = events ?? [];

  /// Содержимое stdin или ввода с терминала; `null` у `readHidden` — EOF.
  final String? text;

  /// Что бросить вместо значения: `FormatException` (недопустимый UTF-8) или
  /// `MultilineSecretException` (вставка нескольких строк).
  final Object? failure;

  @override
  final bool hasTerminal;

  final List<String> events;

  int get reads => events.where((e) => e.startsWith('read')).length;

  @override
  Future<String?> readHidden(String prompt) async {
    events.add('readHidden:$prompt');
    if (failure case final failure?) {
      throw failure;
    }
    return text;
  }

  @override
  Future<String> readAll() async {
    events.add('readAll');
    if (failure case final failure?) {
      throw failure;
    }
    return text ?? '';
  }
}
