/// Значение с ссылками на секреты (`agent-core-architecture` §15.5, п. 7;
/// design.md change `add-agent-secret-store`, D4).
library;

import 'package:collection/collection.dart';

/// Часть [SecretTemplate]: литерал или ссылка на секрет.
///
/// Почему sealed: `switch` по частям исчерпывающий, и новая ветка не
/// проходит мимо `render` и `names`. Для чего: шаблон хранит значение ключа
/// конфига как список частей, а не строку. Как использовать: части создаёт
/// раскрытие значений конфига (`config/resolve.dart`), потребитель их не
/// строит.
sealed class SecretTemplatePart {
  const SecretTemplatePart();
}

/// Литерал: текст, уже прошедший раскрытие `${ENV}` и `$${`.
///
/// Почему отдельная часть: `$${secret:x}` после раскрытия выглядит как
/// ссылка, но ссылкой не является (§15.5, п. 5); литерал второй раз не
/// разбирается. Как использовать: [text] выводится как есть. `toString` не
/// печатает текст: он может быть частью секретного значения.
final class SecretLiteral extends SecretTemplatePart {
  const SecretLiteral(this.text);

  /// Готовый текст части: сам по себе не ссылка, но может быть частью
  /// секретного значения (`Bearer `), поэтому в `toString` и логи не идёт.
  final String text;

  @override
  bool operator ==(Object other) =>
      other is SecretLiteral && other.text == text;

  @override
  int get hashCode => text.hashCode;

  @override
  String toString() => 'SecretLiteral';
}

/// Ссылка `${secret:<name>}`; [name] проходит `SecretNames`.
///
/// Почему хранится имя: значение читается позже и не должно оседать в
/// конфиге (D4). Для чего: `SecretTemplate.names` собирает имена для
/// `SecretResolver`. Как использовать: `render` подставляет значение по
/// [name]; `toString` показывает только имя, оно не секрет.
final class SecretReference extends SecretTemplatePart {
  const SecretReference(this.name);

  /// Имя секрета, прошедшее `SecretNames.problem`; по нему резолвер ищет
  /// значение. Само имя не секрет и может попадать в логи и сообщения.
  final String name;

  @override
  bool operator ==(Object other) =>
      other is SecretReference && other.name == name;

  @override
  int get hashCode => name.hashCode;

  @override
  String toString() => 'SecretReference($name)';
}

/// Значение ключа конфига с `${secret:<name>}`: список литералов и ссылок.
///
/// Почему шаблон, а не строка: литерал `$${secret:x}` после раскрытия
/// неотличим от ссылки и раскрылся бы повторно, а §15.5, п. 5 это запрещает.
/// Шаблон строится при загрузке конфига (секрет не читается), а раскрывается
/// позже, по месту потребителя: заголовки провайдера — при первом запросе,
/// `env`/`headers` MCP-сервера — перед подключением (D4).
///
/// Как использовать: хост и ядро берут [names] для обращения к
/// `SecretResolver`, затем собирают строку [render] из найденных значений.
/// `toString` значений не содержит (их в шаблоне нет).
final class SecretTemplate {
  SecretTemplate(List<SecretTemplatePart> parts)
    : parts = List.unmodifiable(parts);

  /// Неизменяемый список частей в порядке записи в конфиге. Порядок важен:
  /// [render] склеивает значение слева направо, и `Bearer ${secret:x}` не
  /// должно превращаться в `${secret:x}Bearer `.
  final List<SecretTemplatePart> parts;

  /// Имена секретов без повторов, в порядке появления.
  List<String> get names => {
    for (final part in parts)
      if (part case SecretReference(:final name)) name,
  }.toList(growable: false);

  /// Собирает строку; [values] — имя секрета → значение. Имя без значения —
  /// `StateError`: вызывающий обязан сначала разрешить все [names].
  String render(Map<String, String> values) {
    final out = StringBuffer();
    for (final part in parts) {
      switch (part) {
        case SecretLiteral(:final text):
          out.write(text);
        case SecretReference(:final name):
          out.write(
            values[name] ?? (throw StateError('secret is not resolved')),
          );
      }
    }
    return out.toString();
  }

  @override
  bool operator ==(Object other) =>
      other is SecretTemplate &&
      const ListEquality<SecretTemplatePart>().equals(other.parts, parts);

  @override
  int get hashCode => const ListEquality<SecretTemplatePart>().hash(parts);

  @override
  String toString() => 'SecretTemplate(${names.join(', ')})';
}
