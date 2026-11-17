import 'dart:io';

import 'package:args/args.dart';
import 'package:codelab_agent_io/codelab_agent_io.dart'
    show ConfigCommandResult;

import '../serve/exit_codes.dart';

/// Общие части разбора argv подкоманд записи `config`, `provider`, `mcp`
/// (design.md change `add-config-writer-and-reload`, D6).
///
/// Почему отдельный файл: три парсера одинаково задают флаги слоя
/// `--project`/`--local`, одинаково печатают результат общей реализации и
/// одинаково отвечают на ошибку использования. Тексты и коды самих
/// подкоманд, выбор слоя по флагам и ошибка несовместимых флагов — в
/// `codelab_agent_io`; здесь только оболочка `package:args`.

/// Добавляет в [parser] флаги слоя: `--project` и `--local` (слои 3 и 4).
ArgParser withLayerFlags(ArgParser parser) => parser
  ..addFlag(
    'project',
    negatable: false,
    help: 'Use <cwd>/.codelab/config.yaml.',
  )
  ..addFlag(
    'local',
    negatable: false,
    help: 'Use <cwd>/.codelab/config.local.yaml.',
  );

/// Печатает ошибку использования и справку в [err]; возвращает [usageExit].
///
/// [message] не цитирует присланные слова: среди них может оказаться значение
/// секрета (agent-secrets: ошибка разбора не печатает argv; D8).
int usageFailure(IOSink err, String message, String usage) {
  err
    ..writeln('codelab-agent: $message')
    ..writeln()
    ..writeln(usage);
  return usageExit;
}

/// Печатает результат общей подкоманды и возвращает её код выхода.
int printResult(ConfigCommandResult result, IOSink out, IOSink err) {
  result.stdout.forEach(out.writeln);
  result.stderr.forEach(err.writeln);
  return result.exitCode;
}
