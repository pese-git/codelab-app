import '../secrets/secret_template.dart';

/// Подстановка `${ENV}` в разрешённых ключах (`agent-core-architecture`
/// §15.5, «Подстановка `${ENV}`»; design.md change `add-agent-configuration`,
/// D4, D8).
///
/// Почему своя функция: правила узкие и проверяются тестом
/// `config_interpolation_test.dart`: только `${NAME}`, `$${` — литерал `${`,
/// `$NAME` — литерал, незаданная переменная — ошибка, а не пустая строка
/// (она давала бы тихие отказы авторизации), результат повторно не
/// раскрывается.
///
/// Для чего: значения переменных после подстановки — секреты (токены в
/// заголовках), поэтому результат не попадает в сообщения об ошибках:
/// [Expansion.missing] хранит только имена.
///
/// С этапа 8.9 `${secret:<name>}` не читается и в строку не раскрывается:
/// результат — шаблон [Expansion.template] из литералов (уже после `${ENV}` и
/// `$${`) и ссылок (design.md change `add-agent-secret-store`, D4). Строкой
/// значение хранить нельзя: литерал `$${secret:x}` после раскрытия неотличим
/// от ссылки (§15.5, п. 5).
final class Expansion {
  const Expansion(this.text, this.missing, this.secretRefs, this.template);

  /// Строка после подстановки; ссылки `${secret:<name>}` остаются в ней
  /// как есть — для значений без ссылок это окончательный результат.
  final String text;

  /// Имена переменных, которых нет в окружении.
  final List<String> missing;

  /// Имена секретов из `${secret:<name>}` в порядке появления.
  final List<String> secretRefs;

  /// Литералы и ссылки; без ссылок состоит из одного литерала [text].
  final SecretTemplate template;
}

final _variable = RegExp(r'^\$\{([A-Za-z_][A-Za-z0-9_]*)\}');
final _secretRef = RegExp(r'^\$\{secret:([^}]+)\}');

/// Раскрывает `${NAME}` в [source] значениями [environment].
Expansion expandEnvironment(String source, Map<String, String> environment) {
  final out = StringBuffer();
  final missing = <String>[];
  final secrets = <String>[];
  final parts = <SecretTemplatePart>[];
  // Литерал накапливается отдельно от [out]: [out] хранит строку с
  // неразобранными ссылками, шаблон — части.
  final literal = StringBuffer();
  void flush() {
    if (literal.isNotEmpty) {
      parts.add(SecretLiteral(literal.toString()));
      literal.clear();
    }
  }

  var i = 0;
  while (i < source.length) {
    if (source.codeUnitAt(i) != 0x24 /* $ */ ) {
      out.writeCharCode(source.codeUnitAt(i));
      literal.writeCharCode(source.codeUnitAt(i));
      i++;
      continue;
    }
    final rest = source.substring(i);
    if (rest.startsWith(r'$${')) {
      out.write(r'${');
      literal.write(r'${');
      i += 3;
    } else if (_secretRef.firstMatch(rest) case final match?) {
      secrets.add(match.group(1)!);
      flush();
      parts.add(SecretReference(match.group(1)!));
      out.write(match.group(0));
      i += match.group(0)!.length;
    } else if (_variable.firstMatch(rest) case final match?) {
      final name = match.group(1)!;
      final value = environment[name];
      if (value == null) {
        missing.add(name);
      } else {
        out.write(value);
        literal.write(value);
      }
      i += match.group(0)!.length;
    } else {
      out.write(r'$');
      literal.write(r'$');
      i++;
    }
  }
  flush();
  return Expansion(out.toString(), missing, secrets, SecretTemplate(parts));
}
