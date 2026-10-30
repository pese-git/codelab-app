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
final class Expansion {
  const Expansion(this.text, this.missing, this.secretRefs);

  /// Строка после подстановки.
  final String text;

  /// Имена переменных, которых нет в окружении.
  final List<String> missing;

  /// Имена секретов из `${secret:<name>}`: читать их до change
  /// `add-agent-secret-store` нечем (D8).
  final List<String> secretRefs;
}

final _variable = RegExp(r'^\$\{([A-Za-z_][A-Za-z0-9_]*)\}');
final _secretRef = RegExp(r'^\$\{secret:([^}]+)\}');

/// Раскрывает `${NAME}` в [source] значениями [environment].
Expansion expandEnvironment(String source, Map<String, String> environment) {
  final out = StringBuffer();
  final missing = <String>[];
  final secrets = <String>[];
  var i = 0;
  while (i < source.length) {
    if (source.codeUnitAt(i) != 0x24 /* $ */ ) {
      out.writeCharCode(source.codeUnitAt(i));
      i++;
      continue;
    }
    final rest = source.substring(i);
    if (rest.startsWith(r'$${')) {
      out.write(r'${');
      i += 3;
    } else if (_secretRef.firstMatch(rest) case final match?) {
      secrets.add(match.group(1)!);
      out.write(match.group(0));
      i += match.group(0)!.length;
    } else if (_variable.firstMatch(rest) case final match?) {
      final name = match.group(1)!;
      final value = environment[name];
      if (value == null) {
        missing.add(name);
      } else {
        out.write(value);
      }
      i += match.group(0)!.length;
    } else {
      out.write(r'$');
      i++;
    }
  }
  return Expansion(out.toString(), missing, secrets);
}
