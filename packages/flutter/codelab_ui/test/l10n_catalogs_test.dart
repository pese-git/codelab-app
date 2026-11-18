// Красные тесты согласованности каталогов кита (задача 2.1 change
// `add-desktop-localization`; design.md D3, D4; spec app-settings «Каталоги
// согласованы»).
//
// Паттерн — тест каталогов app (`apps/codelab_desktop/test/l10n/
// l10n_catalogs_test.dart`): ARB читаются как JSON с диска, без
// сгенерированного кода, поэтому тест проверяет сами файлы и называет ключ
// сообщения. `gen-l10n` расхождение `en`/`ru` фатальным не считает.
//
// Красный сейчас: в шаблоне кита одно сообщение (задача 1.8), а к концу
// задачи 2.2 их около 150. Тесты равенства ключей и плейсхолдеров и формы
// plural сегодня зелёные и охраняют каталог, который 2.2 наполняет.

import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

const _enPath = 'lib/src/l10n/codelab_ui_en.arb';
const _ruPath = 'lib/src/l10n/codelab_ui_ru.arb';

Map<String, dynamic> _json(String path) {
  final file = File(path);
  expect(file.existsSync(), isTrue, reason: 'нет каталога кита $path');
  return jsonDecode(file.readAsStringSync()) as Map<String, dynamic>;
}

Map<String, String> _messages(Map<String, dynamic> json) => {
  for (final entry in json.entries)
    if (!entry.key.startsWith('@')) entry.key: entry.value as String,
};

/// Имена плейсхолдеров ICU-сообщения: `{name}` и `{name, plural|select, …}`;
/// `one{`, `few{` и т. п. (слово перед скобкой) плейсхолдерами не считаются.
Set<String> _placeholders(String message) => {
  for (final m in RegExp(r'(?<!\w)\{\s*(\w+)\s*[,}]').allMatches(message))
    m.group(1)!,
};

void main() {
  // Чтение в setUp, а не при объявлении: отсутствие ARB должно давать
  // упавший тест, а не ошибку загрузки файла.
  late Map<String, dynamic> enJson;
  late Map<String, String> en;
  late Map<String, String> ru;

  setUp(() {
    enJson = _json(_enPath);
    en = _messages(enJson);
    ru = _messages(_json(_ruPath));
  });

  test('каталог кита наполнен целиком (около 150 сообщений, D12)', () {
    // Нижняя граница с запасом: точное число 2.2 не фиксируется, но шаблон из
    // одного сообщения означает, что литералы кита ещё не переехали.
    expect(
      en.length,
      greaterThanOrEqualTo(100),
      reason:
          'в каталоге кита ${en.length} сообщений; литералы lib/src/** '
          'должны быть вынесены в ARB (задача 2.2)',
    );
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

  test('у каждого сообщения en есть описание для переводчика (D3)', () {
    final withoutDescription = <String>[
      for (final key in en.keys)
        if (((enJson['@$key'] as Map<String, dynamic>?)?['description']
                    as String? ??
                '')
            .trim()
            .isEmpty)
          key,
    ];
    expect(
      withoutDescription,
      isEmpty,
      reason: 'нет @key.description у сообщений',
    );
  });

  test('значения ru не пусты', () {
    final empty = [
      for (final entry in ru.entries)
        if (entry.value.trim().isEmpty) entry.key,
    ];
    expect(empty, isEmpty);
  });
}
