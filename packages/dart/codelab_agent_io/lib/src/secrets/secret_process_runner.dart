import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:meta/meta.dart';

/// Абсолютный путь утилиты `chmod`: `/bin/chmod`, а на NixOS, где его нет,
/// `/usr/bin/chmod`.
///
/// Почему абсолютный: [IoSecretProcessRunner] не передаёт дочернему процессу
/// `PATH` (и вообще окружение родителя), поиск по имени не гарантирован.
/// Для чего: один путь для [FileSecretStore] и `ConfigWriter`. Вызывающий
/// кладёт его в `run(...)` первым аргументом; в argv идут только режим и путь.
@internal
String chmodExecutablePath() =>
    File('/bin/chmod').existsSync() ? '/bin/chmod' : '/usr/bin/chmod';

/// Результат запуска процесса через [SecretProcessRunner].
///
/// Почему только код выхода: stdout и stderr служебных утилит могут цитировать
/// аргументы и окружение, а значит — секрет (CFG-10). Бэкенду `file` нужен лишь
/// успех или отказ `chmod`; текст причины он формулирует сам. Бэкендам утилит
/// ОС (`openspec/changes/add-agent-os-secret-backends/`) понадобится stdout
/// (чтение секрета): они добавят необязательное поле результата, не меняя
/// существующих вызывающих.
@immutable
final class SecretProcessResult {
  const SecretProcessResult({required this.exitCode, this.timedOut = false});

  /// Код выхода; `-1`, если процесс убит по таймауту.
  final int exitCode;

  /// Процесс не завершился за `timeout` и был убит.
  final bool timedOut;
}

/// Узкий порт запуска процесса для бэкендов секретов (design.md change
/// `add-agent-secret-store`, D5).
///
/// Почему порт: в `dart:io` нет API смены прав файла, поэтому бэкенд `file`
/// выставляет `0600` утилитой `/bin/chmod`; порт даёт тесту фейк, который
/// проверяет порядок «права до записи значения» и содержимое argv. Тот же шов
/// понадобится бэкендам утилит ОС после 1.0
/// (`openspec/changes/add-agent-os-secret-backends/`).
///
/// Для чего: единственное место, через которое бэкенды секретов запускают
/// дочерние процессы. Значение секрета НЕ ДОЛЖНО попадать в [arguments]
/// (argv виден через `ps`, CFG-10); если процессу нужно значение, оно
/// передаётся в [stdin].
///
/// Второй потребитель — `ConfigWriter` (design.md change
/// `add-config-writer-and-reload`, D5): он переносит права существующего
/// `config.yaml` на пустой tmp тем же `chmod`, до записи содержимого. Порт не
/// переименован (§19 корневого `AGENTS.md`): имя остаётся узким по смыслу
/// «запуск служебной утилиты без значений секретов в argv».
///
/// Как использовать: хост не создаёт порт сам — [FileSecretStore],
/// `ConfigWriter` и `openSecretStore` берут [IoSecretProcessRunner] по
/// умолчанию; тесты передают фейк.
abstract interface class SecretProcessRunner {
  /// Запускает [executable] с [arguments] без оболочки и ждёт завершения.
  ///
  /// [stdin] записывается в стандартный ввод и закрывается; [timeout] — предел
  /// ожидания (по истечении процесс убивается, `timedOut: true`). Ошибку
  /// запуска (нет исполняемого файла) порт пробрасывает исключением.
  Future<SecretProcessResult> run(
    String executable,
    List<String> arguments, {
    String? stdin,
    Duration? timeout,
  });
}

/// Реализация [SecretProcessRunner] на `Process.start` (D5).
///
/// Почему без оболочки и без родительского окружения: аргументы не
/// интерпретируются (путь с пробелом или `;` безопасен), а дочерний процесс не
/// получает `CODELAB_SECRET_*` и другие переменные хоста.
///
/// Как использовать: `const IoSecretProcessRunner()`. [run] принимает
/// АБСОЛЮТНЫЙ путь исполняемого файла (`/bin/chmod`): `PATH` дочернему
/// процессу не передаётся, поиск по имени не гарантирован. Потоки stdout и
/// stderr в этой версии вычитываются и отбрасываются (см.
/// [SecretProcessResult]).
final class IoSecretProcessRunner implements SecretProcessRunner {
  const IoSecretProcessRunner();

  @override
  Future<SecretProcessResult> run(
    String executable,
    List<String> arguments, {
    String? stdin,
    Duration? timeout,
  }) async {
    final process = await Process.start(
      executable,
      arguments,
      includeParentEnvironment: false,
      runInShell: false,
    );
    unawaited(process.stdout.drain<void>());
    unawaited(process.stderr.drain<void>());
    // Ошибка канала stdin может прийти и асинхронно через `done`; без
    // обработчика она стала бы необработанной ошибкой зоны.
    process.stdin.done.ignore();
    // Ошибка записи в закрытый канал (процесс завершился раньше) — не отказ
    // порта: код выхода всё равно расскажет, чем кончилось.
    try {
      if (stdin != null) {
        process.stdin.add(utf8.encode(stdin));
      }
      await process.stdin.close();
    } on IOException {
      // см. комментарий выше
    }
    var timedOut = false;
    final exitCode = timeout == null
        ? await process.exitCode
        : await process.exitCode.timeout(
            timeout,
            onTimeout: () {
              timedOut = true;
              process.kill(ProcessSignal.sigkill);
              return -1;
            },
          );
    return SecretProcessResult(exitCode: exitCode, timedOut: timedOut);
  }
}
