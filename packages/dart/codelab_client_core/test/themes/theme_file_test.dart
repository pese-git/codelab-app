// Красный тест 1.3 change `add-app-appearance-page`: разбор файла темы.
// Spec `client-themes`: «Формат файла пользовательской темы», «Роли цветов
// темы», «Нестрогий разбор темы в app»; design.md D2. Реализация — 1.4.
import 'dart:convert';

import 'package:codelab_client_core/codelab_client_core.dart';
import 'package:test/test.dart';

ThemeLoaded _loaded(String fileName, String text) {
  final result = ThemeFile.parse(fileName, text);
  expect(result, isA<ThemeLoaded>(), reason: 'тема должна загружаться');
  return result as ThemeLoaded;
}

ThemeIssue _rejected(String fileName, String text) {
  final result = ThemeFile.parse(fileName, text);
  expect(result, isA<ThemeRejected>(), reason: 'тема не должна загружаться');
  return (result as ThemeRejected).issue;
}

/// Сводка проблемы для читаемых сообщений: код и позиция `строка:колонка`.
List<Object?> _at(ThemeIssue i) => [i.code, i.line, i.column];

Rgb _rgb(int v) => Rgb(v);

void main() {
  group('Формат файла: сценарии спецификации', () {
    test('«Минимальная тема»: база dark, все роли из dark, без проблем', () {
      final loaded = _loaded('acme.json', '{"name": "acme"}');
      expect(loaded.theme.name, 'acme');
      expect(loaded.theme.base, ThemeBase.dark);
      expect(loaded.warnings, isEmpty);
      expect(loaded.theme.roles.keys, containsAll(ThemeRole.values));
      expect(
        loaded.theme.roles.values,
        everyElement(isA<DefaultColor>()),
        reason: 'ничего не задано — всё берётся из extends',
      );
      expect(loaded.unsetRoles, unorderedEquals(ThemeRole.values));
    });

    test(
      '«Имя не совпадает с файлом»: nameMismatch, позиция значения name',
      () {
        final issue = _rejected('acme.json', '{\n  "name": "other"\n}');
        expect(issue.code, ThemeIssueCode.nameMismatch);
        expect([issue.line, issue.column], [2, 11]);
      },
    );

    test('«Имя встроенной темы»: reservedName', () {
      expect(
        _rejected('dark.json', '{"name": "dark"}').code,
        ThemeIssueCode.reservedName,
      );
    });

    test('все имена встроенных тем зарезервированы', () {
      for (final name in ['auto', 'dark', 'light', 'high-contrast', 'mono']) {
        expect(
          _rejected('$name.json', '{"name": "$name"}').code,
          ThemeIssueCode.reservedName,
          reason: name,
        );
      }
    });

    test('extends: light, dark, high-contrast; по умолчанию dark', () {
      const expected = {
        'light': ThemeBase.light,
        'dark': ThemeBase.dark,
        'high-contrast': ThemeBase.highContrast,
      };
      for (final e in expected.entries) {
        final loaded = _loaded(
          'acme.json',
          '{"name": "acme", "extends": "${e.key}"}',
        );
        expect(loaded.theme.base, e.value, reason: e.key);
      }
    });
  });

  group('Роли цветов: сценарии спецификации', () {
    test('«Палитра кода»: code.keyword задан, остальные code.* из extends', () {
      final loaded = _loaded(
        'acme.json',
        '{"name": "acme", "colors": {"code": {"keyword": "#ff79c6"}}}',
      );
      final roles = loaded.theme.roles;
      expect(roles[ThemeRole.codeKeyword], _rgb(0xff79c6));
      for (final role in ThemeRole.values.where((r) => r.isCode)) {
        if (role == ThemeRole.codeKeyword) continue;
        expect(roles[role], isA<DefaultColor>(), reason: role.qualifiedName);
        expect(loaded.unsetRoles, contains(role));
      }
      expect(loaded.unsetRoles, isNot(contains(ThemeRole.codeKeyword)));
      expect(loaded.warnings, isEmpty);
    });

    test('«Роль, которой нет у клиента»: status_bg без предупреждения', () {
      final loaded = _loaded(
        'acme.json',
        '{"name": "acme", "colors": {"status_bg": "#101010"}}',
      );
      expect(loaded.warnings, isEmpty);
      expect(loaded.theme.roles[ThemeRole.statusBg], _rgb(0x101010));
    });

    test('набор ролей закрыт: имена JSON в snake_case, code с префиксом', () {
      expect(
        ThemeRole.values.map((r) => r.qualifiedName),
        containsAll([
          'text', 'accent', 'muted', 'success', 'error', 'warning', 'info',
          'diff_add_bg', 'diff_remove_bg', 'selection', 'approval_border',
          'status_bg', //
          'code.background', 'code.keyword', 'code.string', 'code.comment',
          'code.number', 'code.type', 'code.function', 'code.variable',
          'code.operator', 'code.attribute',
        ]),
      );
      expect(ThemeRole.values, hasLength(22));
    });

    test('каждая роль colors принимается и сохраняется', () {
      final colors = <String, Object?>{};
      final code = <String, Object?>{};
      for (final role in ThemeRole.values) {
        (role.isCode ? code : colors)[role.key] = '#0a0b0c';
      }
      colors['code'] = code;
      final text = jsonEncode({'name': 'acme', 'colors': colors});
      final loaded = _loaded('acme.json', text);
      expect(loaded.warnings, isEmpty);
      expect(loaded.unsetRoles, isEmpty);
      for (final role in ThemeRole.values) {
        expect(loaded.theme.roles[role], _rgb(0x0a0b0c), reason: role.key);
      }
    });
  });

  group('Нестрогий разбор: сценарии спецификации', () {
    test('«Неизвестный ключ с подсказкой»: unknownKey acent, 6:5, accent', () {
      const text =
          '{\n'
          '  "name": "acme-night",\n'
          '  "extends": "dark",\n'
          '  "colors": {\n'
          '    "success": "#00ff00",\n'
          '    "acent": "#b4a0ff"\n'
          '  }\n'
          '}';
      final loaded = _loaded('acme-night.json', text);
      expect(loaded.warnings, hasLength(1));
      final w = loaded.warnings.single;
      expect(_at(w), [ThemeIssueCode.unknownKey, 6, 5]);
      expect(w.key, 'acent');
      expect(w.hint, 'accent');
      expect(loaded.theme.roles[ThemeRole.success], _rgb(0x00ff00));
    });

    test('«Ключ, не похожий на роль»: tab_bg без подсказки', () {
      final loaded = _loaded(
        'acme.json',
        '{"name": "acme", "colors": {"tab_bg": "#1b1830"}}',
      );
      final w = loaded.warnings.single;
      expect(w.code, ThemeIssueCode.unknownKey);
      expect(w.key, 'tab_bg');
      expect(w.hint, isNull);
    });

    test('«Справка о незаданных ролях»: перечень без предупреждений', () {
      final loaded = _loaded(
        'acme.json',
        '{"name": "acme", "extends": "dark", "colors": {'
            '"accent": "#b4a0ff", "success": "#00ff00", "error": "#ff0000",'
            '"code": {"keyword": "#ff79c6"}}}',
      );
      expect(loaded.warnings, isEmpty);
      expect(
        loaded.unsetRoles,
        containsAll([
          ThemeRole.warning,
          ThemeRole.info,
          ThemeRole.selection,
          ThemeRole.approvalBorder,
          ThemeRole.codeNumber,
        ]),
      );
      for (final set in [
        ThemeRole.accent,
        ThemeRole.success,
        ThemeRole.error,
        ThemeRole.codeKeyword,
      ]) {
        expect(loaded.unsetRoles, isNot(contains(set)), reason: set.key);
      }
      expect(loaded.unsetRoles, hasLength(ThemeRole.values.length - 4));
    });

    test('«Неверное значение цвета»: invalidValue, ключ accent, позиция', () {
      const text =
          '{\n  "name": "acme",\n  "colors": {\n'
          '    "accent": "#12345"\n  }\n}';
      final issue = _rejected('acme.json', text);
      expect(_at(issue), [ThemeIssueCode.invalidValue, 4, 15]);
      expect(issue.key, 'accent');
      expect(issue.value, '#12345');
    });

    test('«Битый JSON»: invalidJson с позицией обрыва', () {
      final issue = _rejected('acme.json', '{"name": "acme"');
      expect(_at(issue), [ThemeIssueCode.invalidJson, 1, 16]);
    });

    test('«Битый JSON» на нескольких строках: позиция конца текста', () {
      final issue = _rejected(
        'acme.json',
        '{\n  "name": "acme",\n  "colors": {',
      );
      expect(_at(issue), [ThemeIssueCode.invalidJson, 3, 14]);
    });

    test('«Терминальный цвет»: terminalColor, роль из extends', () {
      final loaded = _loaded(
        'acme.json',
        '{"name": "acme", "colors": {"accent": "cyan"}}',
      );
      final w = loaded.warnings.single;
      expect(w.code, ThemeIssueCode.terminalColor);
      expect(w.key, 'accent');
      expect(loaded.theme.roles[ThemeRole.accent], isA<DefaultColor>());
    });

    test('terminalColor для 256:<n> и bright_*', () {
      final loaded = _loaded(
        'acme.json',
        '{"name": "acme", "colors": {"accent": "256:200", "error": "bright_red"}}',
      );
      expect(
        loaded.warnings.map((w) => [w.code, w.key]),
        unorderedEquals([
          [ThemeIssueCode.terminalColor, 'accent'],
          [ThemeIssueCode.terminalColor, 'error'],
        ]),
      );
      expect(loaded.theme.roles[ThemeRole.accent], isA<DefaultColor>());
      expect(loaded.theme.roles[ThemeRole.error], isA<DefaultColor>());
    });

    test('значение default — роль из extends, без предупреждения', () {
      final loaded = _loaded(
        'acme.json',
        '{"name": "acme", "colors": {"accent": "default"}}',
      );
      expect(loaded.warnings, isEmpty);
      expect(loaded.theme.roles[ThemeRole.accent], isA<DefaultColor>());
    });
  });

  group('Коды ошибок: тема не загружается', () {
    test('tooLarge: текст больше 64 КиБ', () {
      final text = '{"name": "acme", "pad": "${'x' * themeFileMaxBytes}"}';
      expect(_rejected('acme.json', text).code, ThemeIssueCode.tooLarge);
    });

    test(
      'граница размера: ровно 64 КиБ допустимо, на байт больше — tooLarge',
      () {
        const head = '{"name": "acme", "pad": "';
        const tail = '"}';
        final fill = themeFileMaxBytes - head.length - tail.length;
        final ok = '$head${'x' * fill}$tail';
        expect(utf8.encode(ok), hasLength(themeFileMaxBytes));
        // Неизвестный ключ — предупреждение, а не отказ.
        expect(ThemeFile.parse('acme.json', ok), isA<ThemeLoaded>());
        expect(
          _rejected(
            'acme.json',
            '${ok.substring(0, ok.length - 2)}x$tail',
          ).code,
          ThemeIssueCode.tooLarge,
        );
      },
    );

    test('размер считается в байтах UTF-8, а не в символах', () {
      // 40 000 символов «я» — 80 000 байт.
      final text = '{"name": "acme", "pad": "${'я' * 40000}"}';
      expect(text.length, lessThan(themeFileMaxBytes));
      expect(_rejected('acme.json', text).code, ThemeIssueCode.tooLarge);
    });

    test('tooLarge по байтам: parseBytes', () {
      final result = ThemeFile.parseBytes(
        'acme.json',
        List<int>.filled(themeFileMaxBytes + 1, 0x20),
      );
      expect((result as ThemeRejected).issue.code, ThemeIssueCode.tooLarge);
    });

    test('notUtf8: parseBytes с недопустимой последовательностью', () {
      final bytes = [
        ...utf8.encode('{"name": "acme", "x": "'),
        0xff,
        0x22,
        0x7d,
      ];
      final result = ThemeFile.parseBytes('acme.json', bytes);
      expect((result as ThemeRejected).issue.code, ThemeIssueCode.notUtf8);
    });

    test('parseBytes корректного файла даёт тот же результат, что parse', () {
      final result = ThemeFile.parseBytes(
        'acme.json',
        utf8.encode('{"name": "acme"}'),
      );
      expect(result, isA<ThemeLoaded>());
    });

    test('notAnObject: корень — массив, строка, число, null', () {
      for (final text in ['[]', '"acme"', '1', 'null']) {
        expect(
          _rejected('acme.json', text).code,
          ThemeIssueCode.notAnObject,
          reason: text,
        );
      }
    });

    test('invalidJson: пустой текст и глубина больше 32', () {
      expect(_rejected('acme.json', '').code, ThemeIssueCode.invalidJson);
      final deep = '${'{"a":' * 40}1${'}' * 40}';
      expect(_rejected('acme.json', deep).code, ThemeIssueCode.invalidJson);
    });

    test('missingName: ключа name нет', () {
      expect(_rejected('acme.json', '{}').code, ThemeIssueCode.missingName);
      expect(
        _rejected('acme.json', '{"extends": "dark"}').code,
        ThemeIssueCode.missingName,
      );
    });

    test('name не строка: missingName или invalidName, но не загрузка', () {
      for (final value in ['1', 'null', '["acme"]', '{}']) {
        expect(
          _rejected('acme.json', '{"name": $value}').code,
          isIn([ThemeIssueCode.missingName, ThemeIssueCode.invalidName]),
          reason: value,
        );
      }
    });

    test('invalidName: шаблон [a-z0-9-]{1,32}', () {
      final bad = ['Acme', 'acme night', 'acme_night', 'акме', '', 'a' * 33];
      for (final name in bad) {
        expect(
          _rejected('$name.json', '{"name": ${jsonEncode(name)}}').code,
          ThemeIssueCode.invalidName,
          reason: '«$name»',
        );
      }
      expect(
        ThemeFile.parse('${'a' * 32}.json', '{"name": "${'a' * 32}"}'),
        isA<ThemeLoaded>(),
        reason: '32 символа — граница допустима',
      );
    });

    test('invalidName проверяется до nameMismatch и reservedName', () {
      expect(
        _rejected('other.json', '{"name": "Dark"}').code,
        ThemeIssueCode.invalidName,
      );
    });

    test('invalidExtends: auto, mono, регистр, не строка', () {
      for (final value in ['"auto"', '"mono"', '"Dark"', '1', 'null']) {
        final issue = _rejected(
          'acme.json',
          '{"name": "acme", "extends": $value}',
        );
        expect(issue.code, ThemeIssueCode.invalidExtends, reason: value);
      }
    });

    test('invalidExtends: позиция значения', () {
      final issue = _rejected(
        'acme.json',
        '{\n  "name": "acme",\n  "extends": "auto"\n}',
      );
      expect([issue.line, issue.column], [3, 14]);
    });

    test('invalidValue: colors и colors.code не объекты', () {
      expect(
        _rejected('acme.json', '{"name": "acme", "colors": []}').code,
        ThemeIssueCode.invalidValue,
      );
      expect(
        _rejected(
          'acme.json',
          '{"name": "acme", "colors": {"code": "red"}}',
        ).code,
        ThemeIssueCode.invalidValue,
      );
    });

    test('invalidValue: значение роли не строка', () {
      for (final value in ['1', 'true', 'null', '[]', '{}']) {
        final issue = _rejected(
          'acme.json',
          '{"name": "acme", "colors": {"accent": $value}}',
        );
        expect(issue.code, ThemeIssueCode.invalidValue, reason: value);
        expect(issue.key, 'accent');
      }
    });

    test('invalidValue: ключ роли кода называется с префиксом', () {
      final issue = _rejected(
        'acme.json',
        '{"name": "acme", "colors": {"code": {"keyword": "#zz0000"}}}',
      );
      expect(issue.code, ThemeIssueCode.invalidValue);
      expect(issue.key, 'code.keyword');
    });

    test('первая ошибка отклоняет тему, даже если есть предупреждения', () {
      final issue = _rejected(
        'acme.json',
        '{"name": "acme", "colors": {"acent": "#ffffff", "accent": "oops"}}',
      );
      expect(issue.code, ThemeIssueCode.invalidValue);
    });
  });

  group('Формат цвета: ThemeColorValue.tryParse', () {
    test('#rrggbb в любом регистре', () {
      expect(ThemeColorValue.tryParse('#b4a0ff'), _rgb(0xb4a0ff));
      expect(ThemeColorValue.tryParse('#B4A0FF'), _rgb(0xb4a0ff));
      expect(ThemeColorValue.tryParse('#000000'), _rgb(0));
    });

    test('неверные #-формы', () {
      for (final text in [
        '#12345',
        '#1234567',
        '#fff',
        '#gg0000',
        'b4a0ff',
        '# b4a0f',
        '#12345g',
        '',
      ]) {
        expect(ThemeColorValue.tryParse(text), isNull, reason: text);
      }
    });

    test('default', () {
      expect(ThemeColorValue.tryParse('default'), isA<DefaultColor>());
    });

    test('16 цветов ANSI и bright_*', () {
      const names = [
        'black',
        'red',
        'green',
        'yellow',
        'blue',
        'magenta',
        'cyan',
        'white',
      ];
      for (final n in [...names, ...names.map((n) => 'bright_$n')]) {
        final v = ThemeColorValue.tryParse(n);
        expect(v, isA<AnsiColor>(), reason: n);
        expect((v as AnsiColor).name, n);
      }
      for (final n in ['orange', 'Red', 'bright_', 'bright_orange', 'gray']) {
        expect(ThemeColorValue.tryParse(n), isNull, reason: n);
      }
    });

    test('256:<n> для целых от 0 до 255', () {
      for (final n in [0, 7, 255]) {
        final v = ThemeColorValue.tryParse('256:$n');
        expect(v, isA<IndexedColor>(), reason: '$n');
        expect((v as IndexedColor).index, n);
      }
      for (final t in [
        '256:256',
        '256:-1',
        '256:1.5',
        '256:',
        '256:x',
        '256: 5',
      ]) {
        expect(ThemeColorValue.tryParse(t), isNull, reason: t);
      }
    });
  });

  group('Предупреждения: duplicateKey и подсказки', () {
    test('duplicateKey: применяется последнее значение, позиция повтора', () {
      const text =
          '{\n  "name": "acme",\n  "colors": {\n'
          '    "accent": "#111111",\n    "accent": "#222222"\n  }\n}';
      final loaded = _loaded('acme.json', text);
      expect(loaded.theme.roles[ThemeRole.accent], _rgb(0x222222));
      final w = loaded.warnings.single;
      expect(_at(w), [ThemeIssueCode.duplicateKey, 5, 5]);
      expect(w.key, 'accent');
    });

    test('duplicateKey на верхнем уровне и в colors.code', () {
      final top = _loaded('acme.json', '{"name": "acme", "name": "acme"}');
      expect(top.warnings.map((w) => w.code), [ThemeIssueCode.duplicateKey]);
      final code = _loaded(
        'acme.json',
        '{"name": "acme", "colors": {"code": {"keyword": "#111111", "keyword": "#222222"}}}',
      );
      expect(code.warnings.map((w) => w.code), [ThemeIssueCode.duplicateKey]);
      expect(code.theme.roles[ThemeRole.codeKeyword], _rgb(0x222222));
    });

    test('неизвестный ключ верхнего уровня: unknownKey без подсказки', () {
      final loaded = _loaded('acme.json', '{"name": "acme", "author": "me"}');
      final w = loaded.warnings.single;
      expect(w.code, ThemeIssueCode.unknownKey);
      expect(w.key, 'author');
      expect(w.hint, isNull);
    });

    test('подсказка: расстояние 1 и 2 — есть, 3 — нет', () {
      String? hintFor(String key) {
        final loaded = _loaded(
          'acme.json',
          '{"name": "acme", "colors": {"$key": "#ffffff"}}',
        );
        return loaded.warnings.single.hint;
      }

      expect(hintFor('acent'), 'accent'); // 1
      expect(hintFor('axxent'), 'accent'); // 2
      expect(hintFor('axxxnt'), isNull); // 3
      expect(hintFor('Accent'), 'accent'); // регистр — замена, расстояние 1
    });

    test('подсказка только из ролей той же области', () {
      // `keywrd` похож на роль code.keyword, но стоит в `colors`.
      final inColors = _loaded(
        'acme.json',
        '{"name": "acme", "colors": {"keywrd": "#ffffff"}}',
      );
      expect(inColors.warnings.single.hint, isNull);

      // `acent` похож на accent, но стоит в `colors.code`.
      final inCode = _loaded(
        'acme.json',
        '{"name": "acme", "colors": {"code": {"acent": "#ffffff"}}}',
      );
      expect(inCode.warnings.single.code, ThemeIssueCode.unknownKey);
      expect(inCode.warnings.single.hint, isNull);

      // В своей области подсказка есть: роль `keyword` палитры кода.
      final okCode = _loaded(
        'acme.json',
        '{"name": "acme", "colors": {"code": {"keywrd": "#ffffff"}}}',
      );
      expect(okCode.warnings.single.hint, 'keyword');
    });

    test('неизвестный ключ пропускается: значение не влияет на роли', () {
      final loaded = _loaded(
        'acme.json',
        '{"name": "acme", "colors": {"acent": "#123456"}}',
      );
      expect(loaded.theme.roles.values, everyElement(isA<DefaultColor>()));
    });
  });

  group('D2: ядро не строит английский текст проблемы', () {
    test('ThemeIssue — код, позиция и аргументы; равенство по значению', () {
      const a = ThemeIssue(
        ThemeIssueCode.unknownKey,
        line: 6,
        column: 5,
        key: 'acent',
        hint: 'accent',
      );
      const b = ThemeIssue(
        ThemeIssueCode.unknownKey,
        line: 6,
        column: 5,
        key: 'acent',
        hint: 'accent',
      );
      expect(a, equals(b));
      expect(a.hashCode, b.hashCode);
      // Текст сообщения строит клиент по ARB; в `toString` ядра его нет.
      expect(a.toString(), isNot(contains('Did you mean')));
      expect(a.toString(), isNot(contains('Ignored')));
    });

    test('результат разбора: предупреждение не содержит готового текста', () {
      final loaded = _loaded(
        'acme.json',
        '{"name": "acme", "colors": {"acent": "#ffffff"}}',
      );
      final w = loaded.warnings.single;
      for (final field in [w.key, w.value, w.hint]) {
        expect(field ?? '', isNot(contains(' ')), reason: 'аргумент, не фраза');
      }
      expect(w.toString(), isNot(contains('Did you mean')));
    });
  });
}
