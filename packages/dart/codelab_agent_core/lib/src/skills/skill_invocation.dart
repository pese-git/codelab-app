/// Тексты активации навыка: сообщение `/skill:<name>`, строки повтора и
/// хеш содержимого (design.md change `add-agent-skills`, D7, D8, D15, D18;
/// agent-skills «Команды навыков», «Повторная активация»).
///
/// Почему отдельный файл: один и тот же текст строят и рантайм (сообщение
/// пользователя), и `activeSkills` (сверка записи журнала с текущим снимком,
/// Q48 (б)). Две копии разошлись бы, и повтор перестал бы узнавать
/// собственные записи.
///
/// Как использовать: `invokeSkill(skill, raw)` даёт полный текст, текст повтора
/// и содержимое активации; `skillToolRepeatText` — результат инструмента
/// `skill` для активного навыка. Функции чистые: файлов не читают.
library;

import 'dart:convert';

import 'package:crypto/crypto.dart';

import '../commands/arguments.dart';
import '../prompts/prompts.g.dart';
import 'skill_block.dart';
import 'skill_catalog.dart';

/// SHA-256 [text] (UTF-8) в виде hex нижнего регистра: содержимое активации
/// (`ActiveSkill.content`, D15, D18).
String sha256Hex(String text) => sha256.convert(utf8.encode(text)).toString();

/// Результат инструмента `skill` для уже активного навыка (D7).
String skillToolRepeatText(String name) =>
    'Skill "$name" is already loaded in this conversation; follow the '
    'instructions above.';

/// Первая строка сообщения повтора команды (D8).
String skillCommandRepeatLine(String name) =>
    'The user invoked the skill "$name" again; its instructions are already '
    'loaded above.';

/// Разворачивание `/skill:<name> <raw>`: три значения, считаемые одним
/// проходом по телу.
typedef SkillInvocation = ({
  /// Содержимое активации: SHA-256 тела после подстановки, без хвоста.
  String content,

  /// Сообщение с полным блоком: обёртка `invoked.md`, затем хвост
  /// `ARGUMENTS:` для тела без плейсхолдеров — после блока, вне `<skill>`
  /// (D18: ввод пользователя не должен попадать внутрь доверенного блока).
  /// По этому тексту `activeSkills` узнаёт запись журнала (Q48 (б)).
  String full,

  /// Сообщение повтора: строка повтора и хвост при непустом вводе, независимо
  /// от плейсхолдеров (блок выше подставил прежние значения).
  String repeat,
});

/// Считает тексты команды [skill] с вводом [raw] (D18).
SkillInvocation invokeSkill(SkillDefinition skill, String raw) {
  final r = substitutePlaceholders(skill.body, raw, splitArguments(raw));
  final wrapper = Prompts.skillsInvoked.render({
    'name': skill.name,
    'block': renderSkillBlock(skill, body: r.text),
  });
  final tail = argumentsTail(raw);
  return (
    content: sha256Hex(r.text),
    full: r.usedPlaceholders ? wrapper : '$wrapper$tail',
    repeat: '${skillCommandRepeatLine(skill.name)}$tail',
  );
}
