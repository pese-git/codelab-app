/// Разбор и подстановка аргументов шаблона команды (design.md change
/// `add-agent-project-files`, D8; `agent-core/17-2-skills-and-templates.md`
/// §17.2.6; SKL-8).
///
/// Почему отдельный файл: это чистые функции над строками, без файлов, shell
/// и сети. Разбор аргументов НЕ исполняет и НЕ читает ничего (SKL-8), поэтому
/// значения, введённые пользователем, остаются текстом.
///
/// Как использовать: [expandCommand] зовёт [splitArguments] для `$1`…`$9` и
/// [substituteArguments] для тела; [usesPlaceholders] нужен разбору шаблона
/// ради подсказки ввода.
library;

final _space = RegExp(r'\s');

bool _isSpace(String char) => _space.hasMatch(char);

/// Делит [raw] на аргументы (§17.2.6).
///
/// Правила: разделитель — пробельные символы; `"…"` и `'…'` группируют слово,
/// кавычки снимаются, пустая пара кавычек даёт пустой аргумент; внутри `"…"`
/// экранируются только `\"` и `\\`, внутри `'…'` экранирования нет; вне
/// кавычек `\` даёт следующий символ, а `\` в конце ввода остаётся буквой.
///
/// Незакрытая кавычка закрывается концом ввода (отступление D8 от §17.2.6:
/// механизма ответа без модели, нужного для `CommandFailed`, ещё нет), поэтому
/// функция не бросает исключений.
List<String> splitArguments(String raw) {
  final out = <String>[];
  final word = StringBuffer();
  var inWord = false;
  String? quote;
  for (var i = 0; i < raw.length; i++) {
    final c = raw[i];
    if (quote == '"') {
      if (c == r'\' && i + 1 < raw.length && '"\\'.contains(raw[i + 1])) {
        word.write(raw[++i]);
      } else if (c == '"') {
        quote = null;
      } else {
        word.write(c);
      }
    } else if (quote == "'") {
      if (c == "'") {
        quote = null;
      } else {
        word.write(c);
      }
    } else if (c == '"' || c == "'") {
      quote = c;
      inWord = true;
    } else if (c == r'\' && i + 1 < raw.length) {
      word.write(raw[++i]);
      inWord = true;
    } else if (_isSpace(c)) {
      if (inWord) {
        out.add(word.toString());
        word.clear();
        inWord = false;
      }
    } else {
      word.write(c);
      inWord = true;
    }
  }
  if (inWord) {
    out.add(word.toString());
  }
  return out;
}

/// Один проход по [body]: каждый плейсхолдер заменяется результатом
/// [onPlaceholder], остальное копируется.
///
/// Значения подставляются в выходной буфер и дальше не сканируются, поэтому
/// `$1` со значением `$ARGUMENTS` остаётся текстом (D8, «безопасность
/// подстановки»).
///
/// Экранирование (design.md change `add-agent-skills`, D8, D18; решения Q7,
/// Q15 (а)): `\$` и `$$` дают литерал `$` и плейсхолдером не считаются;
/// `\\` копируется как есть, оба символа, а следующий `$…` разбирается
/// обычным правилом (до change `\` ничего не значил, и `\\$1` в шаблоне
/// давал `\\x` — рабочие шаблоны и пути Windows не ломаются); `\` перед
/// другим символом и в конце тела остаётся литералом.
String _scan(
  String body,
  String Function(String name, int? index) onPlaceholder,
) {
  final out = StringBuffer();
  var i = 0;
  while (i < body.length) {
    final c = body[i];
    if (c == r'\' && i + 1 < body.length) {
      final next = body[i + 1];
      if (next == r'$') {
        out.write(r'$');
        i += 2;
      } else if (next == r'\') {
        out.write(r'\\');
        i += 2;
      } else {
        out.write(c);
        i++;
      }
      continue;
    }
    if (c != r'$' || i + 1 >= body.length) {
      out.write(c);
      i++;
      continue;
    }
    final next = body[i + 1];
    if (next == r'$') {
      out.write(r'$');
      i += 2;
    } else if (body.startsWith('ARGUMENTS', i + 1)) {
      out.write(onPlaceholder('ARGUMENTS', null));
      i += 1 + 'ARGUMENTS'.length;
    } else if (next.codeUnitAt(0) >= 0x31 && next.codeUnitAt(0) <= 0x39) {
      // Номер — одна цифра: `$10` это `$1`, затем литерал `0`.
      out.write(onPlaceholder('N', next.codeUnitAt(0) - 0x30));
      i += 2;
    } else {
      out.write(r'$');
      i++;
    }
  }
  return out.toString();
}

/// Тело содержит `$ARGUMENTS` или `$1`…`$9` (не экранированные `$$` и `\$`).
bool usesPlaceholders(String body) {
  var found = false;
  _scan(body, (name, index) {
    found = true;
    return '';
  });
  return found;
}

/// Подстановка без хвоста: [text] и признак, что в теле был плейсхолдер.
///
/// Почему отдельно от [substituteArguments]: навыку хвост `ARGUMENTS:` нужен
/// после блока, вне `<skill>`, и не входит в содержимое активации (D18,
/// `ActiveSkill.content`). Внутренняя функция, в барель не экспортируется.
({String text, bool usedPlaceholders}) substitutePlaceholders(
  String body,
  String raw,
  List<String> args,
) {
  var used = false;
  final text = _scan(body, (name, index) {
    used = true;
    if (index == null) {
      return raw;
    }
    return index <= args.length ? args[index - 1] : '';
  });
  return (text: text, usedPlaceholders: used);
}

/// Хвост для тела без плейсхолдеров: `''` при пустом [raw], иначе
/// `\n\nARGUMENTS: <raw>`, чтобы введённое не потерялось (D8, D18).
String argumentsTail(String raw) => raw.isEmpty ? '' : '\n\nARGUMENTS: $raw';

/// Подставляет аргументы в [body] одним проходом слева направо (§17.2.6).
///
/// `$ARGUMENTS` → [raw] как введён; `$1`…`$9` → [args] (нет аргумента —
/// пустая строка); `$$` и `\$` → `$`; `$` перед другим символом остаётся.
/// Если в теле нет ни одного плейсхолдера, а [raw] не пуст, к телу
/// дописывается [argumentsTail]. `{{…}}` тела не обрабатываются. Публичная
/// функция для шаблонов; навыки зовут [substitutePlaceholders] (D18).
String substituteArguments(String body, String raw, List<String> args) {
  final r = substitutePlaceholders(body, raw, args);
  return r.usedPlaceholders ? r.text : '${r.text}${argumentsTail(raw)}';
}
