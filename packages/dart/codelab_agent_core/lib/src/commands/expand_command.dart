import 'arguments.dart';
import 'command_template.dart';
import 'slash_command.dart';

/// Исходная команда сообщения: что пользователь набрал до разворачивания
/// (design.md change `add-agent-project-files`, D8; `agent-sessions` «Поле
/// записи command»).
///
/// Почему [source] — строка: журнал, написанный более новым ядром, может
/// содержать неизвестный источник (`plugin`), и он сохраняется без потери.
/// Известные значения — `SlashCommandSource.wire`.
final class CommandRef {
  const CommandRef({
    required this.source,
    required this.name,
    required this.args,
    this.extra = const {},
  });

  /// Читает объект `command` записи журнала; `null`, если это не объект с
  /// тремя строковыми полями. Неизвестные поля уходят в [extra], чтобы запись
  /// пережила чтение и запись целиком (совместимость вперёд, §8.2.2).
  static CommandRef? tryParse(Object? json) {
    if (json is! Map<String, Object?>) {
      return null;
    }
    final source = json['source'];
    final name = json['name'];
    final args = json['args'];
    if (source is! String || name is! String || args is! String) {
      return null;
    }
    return CommandRef(
      source: source,
      name: name,
      args: args,
      extra: Map.unmodifiable({
        for (final entry in json.entries)
          if (!const {'source', 'name', 'args'}.contains(entry.key))
            entry.key: entry.value,
      }),
    );
  }

  final String source;

  /// Имя без `/`.
  final String name;

  /// Остаток строки после имени, как введён.
  final String args;

  /// Неизвестные поля объекта `command` журнала: пишутся обратно.
  final Map<String, Object?> extra;

  /// Текст реплея: `/<name>` или `/<name> <args>`.
  String get displayText => args.isEmpty ? '/$name' : '/$name $args';

  Map<String, Object?> toJson() => {
    'source': source,
    'name': name,
    'args': args,
    ...extra,
  };

  @override
  bool operator ==(Object other) =>
      other is CommandRef &&
      other.source == source &&
      other.name == name &&
      other.args == args;

  @override
  int get hashCode => Object.hash(source, name, args);
}

/// Итог [expandCommand].
sealed class CommandExpansion {
  const CommandExpansion();
}

/// Текст не команда шаблона: он уходит модели без изменений.
final class NotACommand extends CommandExpansion {
  const NotACommand();
}

/// Команда развёрнута: [text] заменяет первый текстовый блок промпта.
final class Expanded extends CommandExpansion {
  const Expanded(this.text, this.command);

  final String text;
  final CommandRef command;
}

final _commandWord = RegExp(r'^[A-Za-z0-9][A-Za-z0-9:_-]*$');
final _whitespace = RegExp(r'\s');

/// Разворачивает `/<имя> <аргументы>` шаблоном (§17.2.6 шаги 1 и 4 в объёме
/// шаблонов; D8).
///
/// Почему `NotACommand` для неизвестной команды: ответ «Unknown command» без
/// вызова модели требует механизма, который вводит change встроенных команд
/// (OQ1); до него `/nope x` и путь `/usr/bin/foo` уходят модели, как раньше.
///
/// Как использовать: [text] — первый текстовый блок промпта; результат
/// [Expanded.text] заменяет его, остальные блоки идут следом. Функция чистая:
/// не исполняет shell и не читает файлы (SKL-8).
CommandExpansion expandCommand(String text, List<CommandTemplate> templates) {
  if (!text.startsWith('/')) {
    return const NotACommand();
  }
  final end = text.indexOf(_whitespace);
  final word = text.substring(1, end < 0 ? text.length : end);
  if (!_commandWord.hasMatch(word)) {
    return const NotACommand();
  }
  final template = templates.where((t) => t.name == word).firstOrNull;
  if (template == null) {
    return const NotACommand();
  }
  var raw = end < 0 ? '' : text.substring(end).trimLeft();
  // Завершающий перевод строки снимается и в CRLF: `\r` не должен попасть в
  // `$ARGUMENTS` и в `command.args` журнала.
  if (raw.endsWith('\r\n')) {
    raw = raw.substring(0, raw.length - 2);
  } else if (raw.endsWith('\n')) {
    raw = raw.substring(0, raw.length - 1);
  }
  return Expanded(
    substituteArguments(template.body, raw, splitArguments(raw)),
    CommandRef(source: SlashCommandSource.template.wire, name: word, args: raw),
  );
}
