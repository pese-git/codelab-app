import 'dart:io';
import 'dart:math';

import 'package:codelab_agent_core/codelab_agent_core.dart';

import '../config/config_loader.dart';
import '../config/config_writer.dart';
import '../secrets/secret_process_runner.dart';
import 'config_commands.dart' show ConfigCommandResult;
import 'exit_codes.dart';
import 'silent_logger.dart';

/// Файловый слой, в который пишут и из которого читают подкоманды: флаги
/// `--project` и `--local` (design.md change `add-config-writer-and-reload`,
/// D6).
///
/// Почему отдельный enum, а не `ConfigLayer` ядра: клиентам запрещён
/// `package:codelab_agent_*` (`AGENTS.md` §5), а мост `codelab_setup` отдаёт
/// им только опции подкоманд. Слоёв файлов три: по умолчанию [user],
/// [project] и [local] — для каталога проекта `cwd`.
///
/// Как использовать: приложения передают в опции подкоманд сами флаги
/// (`project`, `local`); выбор слоя и ошибку несовместимых флагов даёт
/// [fromFlags] внутри общей реализации, а не каждое приложение (ревью
/// итерации 4, arch L1).
enum ConfigFileLayer {
  /// `$CODELAB_HOME/config.yaml` — слой по умолчанию.
  user,

  /// `<cwd>/.codelab/config.yaml` — флаг `--project`.
  project,

  /// `<cwd>/.codelab/config.local.yaml` — флаг `--local`.
  local;

  /// Текст ошибки использования при обоих флагах: один у всех подкоманд.
  static const conflictMessage = '--project and --local cannot be combined';

  /// Слой по флагам: без флагов [user]; `null` — заданы оба (несовместимые,
  /// ошибка использования с текстом [conflictMessage]).
  static ConfigFileLayer? fromFlags({
    required bool project,
    required bool local,
  }) {
    if (project && local) {
      return null;
    }
    return project
        ? ConfigFileLayer.project
        : local
        ? ConfigFileLayer.local
        : ConfigFileLayer.user;
  }

  /// Цель записи в каталоге проекта [cwd].
  ConfigTarget target(String cwd) => switch (this) {
    ConfigFileLayer.user => const ConfigTarget.user(),
    ConfigFileLayer.project => ConfigTarget.project(cwd),
    ConfigFileLayer.local => ConfigTarget.projectLocal(cwd),
  };
}

/// Исход [ConfigEditRunner.apply] (ревью итерации 4, arch M1+M2).
///
/// Почему запечатанная иерархия: два nullable-поля допускали невозможные
/// сочетания «оба» и «ни одного». Подкоманда разбирает исход `switch`-ом: либо
/// [EditWritten], либо [EditFinished].
sealed class ConfigEditOutcome {
  const ConfigEditOutcome();
}

/// Правка записана, а при `dryRun` — проверена без записи.
final class EditWritten extends ConfigEditOutcome {
  const EditWritten(this.result);

  /// Файл, предупреждения и ключи, для которых нужен перезапуск (при `dryRun`
  /// — то, что было бы записано).
  final ConfigWriteResult result;
}

/// Запись не состоялась или не нужна: [result] — готовый результат подкоманды
/// (отказ, ошибка использования, «нечего делать»).
///
/// [issues] — типизированные проблемы конфига, если отказ их несёт (итог
/// невалиден, секрет значением): подкоманда выбирает подсказку по
/// `issue.key`, а не по подстроке текста. Для остальных исходов пусто.
final class EditFinished extends ConfigEditOutcome {
  const EditFinished(this.result, {this.issues = const []});

  /// Готовый результат подкоманды: код выхода и строки stdout/stderr.
  final ConfigCommandResult result;

  /// Типизированные проблемы конфига отказа; пусто для прочих исходов.
  final List<ConfigIssue> issues;
}

/// Правки, построенные от снимка слоя: на повторе после конфликта вызываются
/// заново со свежим снимком (`provider add` убирает прежний источник ключа
/// только если он есть в файле, R4-4).
typedef ConfigEditsBuilder = List<ConfigEdit> Function(ConfigSnapshot snapshot);

/// Есть ли в [snapshot] ключ [key] — по пути, а не по значению (ревью
/// итерации 4, safety M).
///
/// Почему не `snapshot.get(key) != null`: ключ со значением `null`
/// (`max_steps:` или `~`) в файле есть, и `unset`/`remove` обязаны его
/// удалить, а не молча ответить «не задан». Элемент списка ищется по полю
/// `name`; при [byNumber] — и по номеру, если имени нет (как
/// `ConfigSnapshot.get`). `mcp remove` передаёт `false`: `remove 0` не должен
/// затрагивать первый сервер.
bool configKeyPresent(
  ConfigSnapshot snapshot,
  String key, {
  bool byNumber = true,
}) {
  final segments = splitKeyPath(key);
  if (segments == null) {
    return false;
  }
  Object? node = snapshot.values;
  for (final segment in segments) {
    if (segment.isElement) {
      if (node is! List<Object?>) {
        return false;
      }
      Object? found;
      var hit = false;
      for (final item in node) {
        if (item is Map && item['name'] == segment.value) {
          found = item;
          hit = true;
          break;
        }
      }
      final index = byNumber ? int.tryParse(segment.value) : null;
      if (!hit && index != null && index >= 0 && index < node.length) {
        found = node[index];
        hit = true;
      }
      if (!hit) {
        return false;
      }
      node = found;
    } else {
      if (node is! Map || !node.containsKey(segment.value)) {
        return false;
      }
      node = node[segment.value];
    }
  }
  return true;
}

/// Общая часть подкоманд записи: цель по слою, чтение снимка, `apply` с одним
/// повтором при конфликте и перевод исключений писателя в коды выхода
/// (design.md change `add-config-writer-and-reload`, D6).
///
/// Почему отдельный класс: `config set|unset`, `provider add|remove` и
/// `mcp add|remove` должны одинаково повторять правку при конфликте
/// ([ConfigConflictException]), одинаково различать «ошибка использования» (`64`)
/// и «итог невалиден» (`1`) и одинаково печатать успех. Без общего места
/// тексты и коды трёх подкоманд разошлись бы между `codelab-agent` и
/// `codelab`.
///
/// Как использовать: подкоманда создаёт [ConfigEditRunner] в конструкторе
/// (швы тестов — `processRunner`, `clock`, `random`, `seam`), вызывает [apply] со
/// построителем правок ([ConfigEditsBuilder]) и разбирает [ConfigEditOutcome]:
/// [EditFinished] — результат подкоманды готов (отказ либо `shortCircuit`);
/// [EditWritten] описывает записанный файл, а [successLines] даёт
/// предупреждения и подсказку о перезапуске. Значения правок в тексты не
/// попадают.
final class ConfigEditRunner {
  ConfigEditRunner({
    SecretProcessRunner? processRunner,
    Clock? clock,
    Random? random,
    String? platform,
    Future<void> Function(ConfigWriteSeam point)? seam,
  }) : _processRunner = processRunner ?? const IoSecretProcessRunner(),
       _clock = clock ?? const SystemClock(),
       _random = random ?? Random.secure(),
       _platform = platform,
       _seam = seam;

  final SecretProcessRunner _processRunner;
  final Clock _clock;
  final Random _random;
  final String? _platform;
  final Future<void> Function(ConfigWriteSeam point)? _seam;

  /// Применяет правки [edits] к слою каталога [cwd], выбранному флагами
  /// [project] и [local] (оба — код `64`, [ConfigFileLayer.conflictMessage]).
  ///
  /// [edits] вызывается на каждой попытке со свежим снимком: правки,
  /// зависящие от содержимого файла, на повторе при конфликте видят актуальное
  /// состояние. [label] — имя подкоманды для текстов ошибок использования
  /// (`config set`). [shortCircuit] вызывается на каждой попытке после чтения
  /// снимка: ненулевой результат завершает подкоманду без записи (`unset`
  /// отсутствующего ключа). [dryRun] — только проверка итога
  /// (`ConfigWriter.validate`): `provider add --api-key-stdin` не должен
  /// сохранять ключ при заведомо невалидном итоге (D6, шаг 1).
  ///
  /// Исключения писателя переводятся в результат: [ConfigInlineSecretException]
  /// и [ConfigException] — код `1` и проблемы построчно; второй подряд
  /// [ConfigConflictException] — код `1` и текст о повторном запуске.
  Future<ConfigEditOutcome> apply({
    required String label,
    required Map<String, String> environment,
    required String cwd,
    required bool project,
    required bool local,
    required ConfigEditsBuilder edits,
    ConfigCommandResult? Function(ConfigSnapshot snapshot)? shortCircuit,
    bool dryRun = false,
  }) async {
    final layer = ConfigFileLayer.fromFlags(project: project, local: local);
    if (layer == null) {
      return EditFinished(
        ConfigCommandResult(
          exitCode: configUsageExit,
          stderr: ['$label: ${ConfigFileLayer.conflictMessage}'],
        ),
      );
    }
    if (!Directory(cwd).existsSync()) {
      return EditFinished(
        ConfigCommandResult(
          exitCode: configUsageExit,
          stderr: ['$label: no such directory: $cwd'],
        ),
      );
    }
    final String home;
    try {
      home = codelabHomeOf(environment);
    } on ConfigUsageException catch (error) {
      return EditFinished(
        ConfigCommandResult(
          exitCode: configUsageExit,
          stderr: ['$label: ${error.message}'],
        ),
      );
    }
    final writer = ConfigWriter(
      codelabHome: home,
      environment: environment,
      loader: ConfigLoader(),
      logger: const SilentLogger(),
      processRunner: _processRunner,
      clock: _clock,
      random: _random,
      cwd: cwd,
      platform: _platform,
      // Шов тестов пробрасывается из швов подкоманд; в рабочем коде он `null`.
      // ignore: invalid_use_of_visible_for_testing_member
      seam: _seam,
    );
    final target = layer.target(cwd);
    try {
      // Правки CLI декларативны, а устаревшего экрана, который нужно
      // защитить, у CLI нет: один конфликт — перечитать и повторить (D6).
      for (var attempt = 0; ; attempt++) {
        final snapshot = await writer.read(target);
        if (shortCircuit?.call(snapshot) case final done?) {
          return EditFinished(done);
        }
        try {
          final list = edits(snapshot);
          final result = dryRun
              ? await writer.validate(snapshot, list)
              : await writer.apply(snapshot, list);
          return EditWritten(result);
        } on ConfigConflictException {
          if (attempt >= 1) {
            return EditFinished(
              const ConfigCommandResult(
                exitCode: configInvalidExit,
                stderr: [
                  'config file changed during the edit; run the command '
                      'again',
                ],
              ),
            );
          }
        }
      }
    } on ConfigException catch (error) {
      // Подкласс [ConfigInlineSecretException] ловится здесь же: его проблемы
      // уже без значения и несут подсказку `codelab secret set <name>`.
      return EditFinished(
        ConfigCommandResult(
          exitCode: configInvalidExit,
          stderr: [for (final issue in error.issues) '$issue'],
        ),
        issues: error.issues,
      );
    } on ConfigUsageException catch (error) {
      return EditFinished(
        ConfigCommandResult(
          exitCode: configUsageExit,
          stderr: ['$label: ${error.message}'],
        ),
      );
    }
  }

  /// Строки после строки успеха: `warning:` по предупреждениям писателя (в
  /// том числе прежним проблемам конфига, R3-1) и `note:` про перезапуск.
  static List<String> successLines(ConfigWriteResult result) => [
    for (final warning in result.warnings)
      warning.key.isEmpty
          ? 'warning: ${warning.message}'
          : 'warning: ${warning.key}: ${warning.message}',
    if (result.restartRequiredKeys.isNotEmpty)
      'note: restart the agent to apply: '
          '${result.restartRequiredKeys.join(', ')}',
  ];
}
