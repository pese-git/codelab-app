// Подсказки интерфейса с командой `codelab-agent serve --ws` должны совпадать с
// настоящими флагами агента.
//
// Почему: `--ws` — флаг без значения, порт задаётся отдельно `--port`
// (`apps/codelab_agent/lib/src/cli/serve_args.dart`). Подсказка
// «Join a session started in the CLI» советовала `serve --ws <port>`, и
// пользователь, скопировав её, получал ошибку разбора аргументов. Тест читает
// ARB с диска, как `l10n_catalogs_test.dart`, и проверяет оба каталога.

import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

Map<String, String> _messages(String path) {
  final json =
      jsonDecode(File(path).readAsStringSync()) as Map<String, dynamic>;
  return {
    for (final entry in json.entries)
      if (!entry.key.startsWith('@')) entry.key: entry.value as String,
  };
}

void main() {
  for (final path in ['lib/l10n/app_en.arb', 'lib/l10n/app_ru.arb']) {
    test('$path: порт для serve --ws передаётся флагом --port', () {
      final wrong = RegExp(r'--ws\s+<');
      final offenders = [
        for (final entry in _messages(path).entries)
          if (wrong.hasMatch(entry.value)) entry.key,
      ];
      expect(
        offenders,
        isEmpty,
        reason: 'у serve нет значения после --ws, порт — --port <port>',
      );
    });
  }

  test('подсказка о сессии из CLI называет --ws --port', () {
    for (final path in ['lib/l10n/app_en.arb', 'lib/l10n/app_ru.arb']) {
      expect(
        _messages(path)['connectionJoinCliBody'],
        contains('codelab-agent serve --ws --port <port>'),
        reason: path,
      );
    }
  });
}
