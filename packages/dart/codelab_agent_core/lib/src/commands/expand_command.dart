import 'arguments.dart';
import 'command_line.dart';
import 'command_template.dart';
import '../skills/skill_commands.dart' show skillCommandPrefix;
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

  /// Источник команды: `SlashCommandSource.wire` или значение из более нового
  /// журнала (хранится как есть).
  final String source;

  /// Имя без `/`.
  final String name;

  /// Остаток строки после имени, как введён.
  final String args;

  /// Неизвестные поля объекта `command` журнала: пишутся обратно.
  final Map<String, Object?> extra;

  /// Текст реплея: `/<name>` или `/<name> <args>`; у навыка — с префиксом
  /// `skill:` (`name` в журнале хранится без него, D18).
  String get displayText {
    final word = source == SlashCommandSource.skill.wire
        ? '$skillCommandPrefix$name'
        : name;
    return args.isEmpty ? '/$word' : '/$word $args';
  }

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
///
/// Почему sealed: вызывающий обязан обработать обе ветки (не команда и
/// развёрнутая команда), иначе новая ветка пройдёт мимо компилятора.
///
/// Как использовать: `switch` по значению; [NotACommand] — текст уходит модели
/// как есть, [Expanded] — текст и ссылка на команду для журнала.
sealed class CommandExpansion {
  const CommandExpansion();
}

/// Текст не команда шаблона: он уходит модели без изменений.
///
/// Неизвестную команду (слово без шаблона и без встроенной команды) не
/// отличает: ответ «Unknown command» даёт `BuiltinCommands.match` раньше, до
/// вызова этой функции (design.md change `add-agent-builtin-slash-commands`,
/// D3, D4).
///
/// Как использовать: константный экземпляр, создаёт [expandCommand].
final class NotACommand extends CommandExpansion {
  const NotACommand();
}

/// Команда развёрнута: [text] заменяет первый текстовый блок промпта.
///
/// Почему рядом [command]: журнал хранит и развёрнутый текст, и то, что
/// набрал пользователь, чтобы клиент мог показать исходную команду (D8).
///
/// Как использовать: результат [expandCommand]; рантайм подставляет [text] в
/// промпт и пишет [command] в запись сообщения.
final class Expanded extends CommandExpansion {
  const Expanded(this.text, this.command);

  /// Текст для модели: тело шаблона после подстановки аргументов.
  final String text;

  /// Исходная команда для журнала: источник, имя и сырые аргументы.
  final CommandRef command;
}

/// Разворачивает `/<имя> <аргументы>` шаблоном (§17.2.6 шаги 1 и 4 в объёме
/// шаблонов; D8).
///
/// Почему `NotACommand` для слова без шаблона: «Unknown command» отвечает
/// `BuiltinCommands.match` на шаге 4 разбора D3 (change
/// `add-agent-builtin-slash-commands`); здесь только шаблоны (шаг 3).
///
/// Как использовать: [text] — первый текстовый блок промпта; результат
/// [Expanded.text] заменяет его, остальные блоки идут следом. Функция чистая:
/// не исполняет shell и не читает файлы (SKL-8).
CommandExpansion expandCommand(String text, List<CommandTemplate> templates) {
  final line = parseCommandLine(text);
  if (line == null) {
    return const NotACommand();
  }
  final template = templates.where((t) => t.name == line.word).firstOrNull;
  if (template == null) {
    return const NotACommand();
  }
  final raw = line.raw;
  return Expanded(
    substituteArguments(template.body, raw, splitArguments(raw)),
    CommandRef(
      source: SlashCommandSource.template.wire,
      name: line.word,
      args: raw,
    ),
  );
}
