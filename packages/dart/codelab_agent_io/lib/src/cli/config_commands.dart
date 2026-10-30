import 'dart:io';

import 'package:codelab_agent_core/codelab_agent_core.dart';

import '../config/config_loader.dart';
import 'exit_codes.dart';

/// Параметры `config check`, уже разобранные приложением (D13).
///
/// Почему не флаги строкой: разбор аргументов — дело `package:args` каждого
/// приложения (в allowlist `codelab_agent_io` его нет), а общая часть
/// получает типизированный вход.
///
/// Как использовать: [cwd] — каталог проекта (приложение подставляет текущий,
/// если `--cwd` не задан), [environment] — переменные процесса
/// (`Platform.environment`).
final class CheckOptions {
  const CheckOptions({required this.cwd, required this.environment});

  final String cwd;
  final Map<String, String> environment;
}

/// Результат подкоманды: код выхода и строки двух потоков (D13).
///
/// Почему данные, а не печать: приложение само пишет в свои stdout/stderr,
/// а тест сравнивает вывод `codelab` и `codelab-agent` построчно.
final class ConfigCommandResult {
  const ConfigCommandResult({
    required this.exitCode,
    this.stdout = const [],
    this.stderr = const [],
  });

  /// [configValidExit], [configInvalidExit] или [configUsageExit].
  final int exitCode;
  final List<String> stdout, stderr;
}

/// Общая реализация подкоманд `config` для `codelab-agent` и `codelab`
/// (design.md change `add-agent-configuration`, D13; `agent-core-architecture`
/// §17.5.5).
///
/// Почему в `codelab_agent_io`: тексты, правила и коды выхода должны жить в
/// одном месте, иначе два бинаря разойдутся. Здесь есть `dart:io` и
/// [ConfigLoader].
///
/// Для чего: [check] выполняет полную загрузку §15.5 без запуска агента.
/// Ничего не пишет на диск, не читает stdin, значений секретов не печатает:
/// [ConfigIssue.message] строится из путей и типов (CFG-2).
///
/// Как использовать: `ConfigCommands().check(CheckOptions(cwd: …,
/// environment: Platform.environment))`, затем напечатать `stdout`/`stderr`
/// результата и завершиться с `exitCode`.
final class ConfigCommands {
  ConfigCommands();

  /// Печатает слои, проблемы и предупреждения, итог — последней строкой.
  ConfigCommandResult check(CheckOptions options) {
    if (!Directory(options.cwd).existsSync()) {
      return ConfigCommandResult(
        exitCode: configUsageExit,
        stderr: ['config check: no such directory: ${options.cwd}'],
      );
    }
    final ConfigLoadResult loaded;
    try {
      // Флагов у `check` нет: проверяется то, что увидит `serve` без флагов.
      loaded = ConfigLoader().load(
        cwd: options.cwd,
        environment: options.environment,
      );
    } on ConfigUsageException catch (error) {
      return ConfigCommandResult(
        exitCode: configUsageExit,
        stderr: ['config check: ${error.message}'],
      );
    }
    final issues = loaded.issues;
    return ConfigCommandResult(
      exitCode: issues.isEmpty ? configValidExit : configInvalidExit,
      stdout: [
        'Sources: ${loaded.sources.join(', ')}',
        for (final issue in issues) '$issue',
        for (final warning in loaded.warnings) 'warning: $warning',
        issues.isEmpty
            ? 'Config: valid'
            : 'Config: invalid (issues: ${issues.length})',
      ],
    );
  }
}
