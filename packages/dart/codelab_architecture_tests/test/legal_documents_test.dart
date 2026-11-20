/// Проверка правовых документов в корне репозитория: `PRIVACY.md`,
/// `PRIVACY.ru.md`, `TERMS.md`, `TERMS.ru.md` (задача 1.1 change
/// `add-app-legal-page`; spec licensing-and-attribution «Политика
/// конфиденциальности и условия использования»; design.md D3).
///
/// Почему: документы — юридический текст, который читают на GitHub и в app.
/// Тихая потеря обязательного раздела или расхождение редакций по датам
/// заметны только юристу, поэтому форму документов держит тест (REL-9).
///
/// Для чего: проверяет форму, а не смысл. Файлы есть; первая строка — дата
/// редакции своего языка, у пары одна дата; обязательные заголовки второго
/// уровня идут первыми и в порядке `design.md` D3; слов согласия нет
/// (§12.7.7а: принимать нечего); корневой `README.md` ссылается на оба
/// документа. Сверку копий в `apps/codelab_desktop/assets/legal/` делает
/// `legal_assets_test.dart` app, не этот тест.
///
/// Как использовать: `fvm dart test test/legal_documents_test.dart` в пакете
/// или `fvm dart run melos run guard`. Сообщение называет файл и ожидаемый
/// заголовок. Тексты документов пишет docs-writer (задача 1.2).
library;

import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:test/test.dart';

import 'support/repo_root.dart';

/// Обязательные заголовки второго уровня: таблица D3, порядок §12.7.7 и
/// §12.7.7а.
const _headings = {
  'PRIVACY.md': [
    '1. No telemetry',
    '2. Network requests',
    '3. What is stored on this computer',
    '4. Third-party policies',
    '5. Contact and changes',
  ],
  'PRIVACY.ru.md': [
    '1. Телеметрии нет',
    '2. Сетевые запросы',
    '3. Что хранится на компьютере',
    '4. Сторонние политики',
    '5. Контакт и изменения',
  ],
  'TERMS.md': [
    '1. Status and the license',
    '2. Your use and responsibility',
    '3. Services you connect',
    '4. No warranty, limited liability',
    '5. Model output',
    '6. Changes and contact',
  ],
  'TERMS.ru.md': [
    '1. Статус условий и лицензия',
    '2. Использование и ответственность пользователя',
    '3. Сторонние сервисы',
    '4. Отказ от гарантий и ограничение ответственности',
    '5. Содержимое, сгенерированное моделью',
    '6. Изменения и контакт',
  ],
};

/// Формат первой строки по языку файла (D3).
final _firstLine = {
  false: RegExp(r'^Last revised: (\d{4}-\d{2}-\d{2})$'),
  true: RegExp(r'^Редакция от (\d{4}-\d{2}-\d{2})$'),
};

/// Слова согласия: условия справочные, принимать нечего (§12.7.7а).
final _consent = RegExp(
  r'I agree|accept these terms|--accept-terms|Принимаю',
  caseSensitive: false,
);

bool _isRussian(String name) => name.endsWith('.ru.md');

void main() {
  final root = repoRoot();
  File file(String name) => File(p.join(root, name));

  String textOf(String name) {
    final f = file(name);
    expect(f.existsSync(), isTrue, reason: 'нет корневого файла $name');
    return f.readAsStringSync();
  }

  group('legal documents', () {
    for (final name in _headings.keys) {
      group(name, () {
        test('файл существует', () {
          expect(file(name).existsSync(), isTrue, reason: 'нет файла $name');
        });

        test('первая строка — дата редакции своего языка', () {
          final first = textOf(name).split('\n').first.trimRight();

          expect(
            _firstLine[_isRussian(name)]!.hasMatch(first),
            isTrue,
            reason:
                '$name: первая строка должна быть '
                '${_isRussian(name) ? '«Редакция от ГГГГ-ММ-ДД»' : '"Last revised: YYYY-MM-DD"'}, '
                'а не «$first»',
          );
        });

        test('обязательные заголовки второго уровня идут первыми и по '
            'порядку', () {
          final found = [
            for (final line in textOf(name).split('\n'))
              if (line.startsWith('## ')) line.substring(3).trimRight(),
          ];
          final expected = _headings[name]!;

          for (var i = 0; i < expected.length; i++) {
            expect(
              found.length > i ? found[i] : null,
              expected[i],
              reason:
                  '$name: на месте №${i + 1} ожидается заголовок '
                  '«## ${expected[i]}»',
            );
          }
        });

        test('слов согласия нет', () {
          final match = _consent.firstMatch(textOf(name));

          expect(
            match,
            isNull,
            reason:
                '$name содержит слова согласия «${match?.group(0)}»: '
                'условия справочные, принимать нечего',
          );
        });
      });
    }

    for (final base in ['PRIVACY', 'TERMS']) {
      test('$base.md и $base.ru.md: одна дата редакции', () {
        String? dateOf(String name) {
          final first = textOf(name).split('\n').first.trimRight();
          return _firstLine[_isRussian(name)]!.firstMatch(first)?.group(1);
        }

        final en = dateOf('$base.md');
        final ru = dateOf('$base.ru.md');

        expect(en, isNotNull, reason: '$base.md: нет даты редакции');
        expect(
          ru,
          en,
          reason:
              'даты редакций $base.md ($en) и $base.ru.md ($ru) разошлись: '
              'у пары одна дата',
        );
      });
    }

    test('README.md ссылается на PRIVACY.md и TERMS.md', () {
      final readme = textOf('README.md');

      for (final name in ['PRIVACY.md', 'TERMS.md']) {
        expect(
          readme,
          contains(name),
          reason: 'README.md не ссылается на $name',
        );
      }
    });
  });
}
