import 'dart:convert';
import 'dart:io';

import '../cli_args.dart';
import '../cli_io.dart';

/// Читает промпт headless по правилам H-01.
///
/// Почему: скрипты передают промпт тремя способами — текстом, файлом и
/// через pipe, — и CLI должен понимать их одинаково и предсказуемо: текст
/// `-p` файлом не считается никогда (spec cli-headless «Источники промпта
/// headless»).
///
/// Как использовать: `runCodelab` вызывает функцию перед подключением к
/// агенту. `-p` — текст как есть; `-f <файл>` — содержимое файла в UTF-8;
/// `-f -` или ни `-p`, ни `-f` — весь stdin. Пустой промпт и ошибка чтения —
/// [UsageError] (код `64`), агент не запускается.
Future<String> readPrompt(CliOptions options, CliIo io) async {
  final text = switch ((options.prompt, options.promptFile)) {
    (final prompt?, _) => prompt,
    (_, '-') || (null, null) => await _readStdin(io),
    (_, final path?) => await _readFile(path),
  };
  if (text.trim().isEmpty) {
    throw const UsageError('No prompt.');
  }
  return text;
}

Future<String> _readStdin(CliIo io) => io.stdin.transform(utf8.decoder).join();

Future<String> _readFile(String path) async {
  try {
    return await File(path).readAsString();
  } on FileSystemException catch (error) {
    final reason = error.osError?.message ?? error.message;
    throw UsageError('Cannot read the prompt file $path: $reason');
  } on FormatException {
    throw UsageError('The prompt file $path is not UTF-8 text.');
  }
}
