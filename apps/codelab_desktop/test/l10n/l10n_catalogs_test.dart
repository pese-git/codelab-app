// Красные тесты согласованности каталогов app (задача 1.1 change
// `add-desktop-localization`; design.md D3; spec app-settings «Каталоги
// согласованы»).
//
// `gen-l10n` не считает расхождение `en`/`ru` фатальным, поэтому его ловит
// этот тест и называет ключ сообщения. Каталоги читаются как JSON с диска, без
// сгенерированного кода: тест проверяет сами ARB.

import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

Map<String, String> _messages(String path) {
  final file = File(path);
  expect(
    file.existsSync(),
    isTrue,
    reason: 'нет каталога $path (add-desktop-localization 1.2)',
  );
  final json = jsonDecode(file.readAsStringSync()) as Map<String, dynamic>;
  return {
    for (final entry in json.entries)
      if (!entry.key.startsWith('@')) entry.key: entry.value as String,
  };
}

/// Имена плейсхолдеров ICU-сообщения: `{name}` и `{name, plural|select, …}`;
/// `one{`, `few{` и т. п. (слово перед скобкой) плейсхолдерами не считаются.
Set<String> _placeholders(String message) => {
  for (final m in RegExp(r'(?<!\w)\{\s*(\w+)\s*[,}]').allMatches(message))
    m.group(1)!,
};

void main() {
  late Map<String, String> en;
  late Map<String, String> ru;

  // Чтение в setUp, а не при объявлении: отсутствие ARB должно давать
  // упавший тест, а не ошибку загрузки файла.
  setUp(() {
    en = _messages('lib/l10n/app_en.arb');
    ru = _messages('lib/l10n/app_ru.arb');
  });

  test('каталоги не пусты', () {
    expect(en, isNotEmpty);
    expect(ru, isNotEmpty);
  });

  test('наборы ключей en и ru равны', () {
    expect(
      ru.keys.toSet().difference(en.keys.toSet()),
      isEmpty,
      reason: 'ключи есть в ru, но нет в en',
    );
    expect(
      en.keys.toSet().difference(ru.keys.toSet()),
      isEmpty,
      reason: 'ключи есть в en, но нет в ru',
    );
  });

  test('плейсхолдеры каждого сообщения совпадают', () {
    final mismatched = <String>[
      for (final key in en.keys)
        if (ru.containsKey(key) &&
            !_placeholders(en[key]!).containsAll(_placeholders(ru[key]!)) |
                !_placeholders(ru[key]!).containsAll(_placeholders(en[key]!)))
          key,
    ];
    expect(mismatched, isEmpty, reason: 'плейсхолдеры различаются');
  });

  test('у plural в ru есть формы one, few, many, other', () {
    final broken = <String>[
      for (final entry in ru.entries)
        if (entry.value.contains(RegExp(r',\s*plural\s*,')) &&
            !['one', 'few', 'many', 'other'].every(
              (form) => RegExp('(?<!\\w)$form\\s*\\{').hasMatch(entry.value),
            ))
          entry.key,
    ];
    expect(broken, isEmpty, reason: 'неполные формы plural в ru');
  });
}
