import 'dart:io';

import 'package:codelab_agent_io/codelab_agent_io.dart';

/// Один вызов [SecretProcessRunner], записанный [FakeSecretProcessRunner].
final class RecordedProcessCall {
  const RecordedProcessCall({
    required this.executable,
    required this.arguments,
    required this.stdin,
    required this.lastArgumentLength,
  });

  final String executable;
  final List<String> arguments;
  final String? stdin;

  /// Размер файла, названного последним аргументом, в момент вызова (`null` —
  /// файла нет). Для `/bin/chmod 600 <tmp>` это проверка «права выставлены до
  /// записи значения»: временный файл в этот момент ещё пуст (D14).
  final int? lastArgumentLength;
}

/// Фейк порта запуска процесса для тестов бэкенда `file`.
///
/// Почему: настоящий `/bin/chmod` нужен, чтобы права реально выставились, но
/// тесту ещё нужны порядок вызовов, содержимое argv и точки отказа (D5, D14).
/// Как использовать: по умолчанию выполняет настоящий `chmod` через
/// `Process.runSync` (независимо от `IoSecretProcessRunner`); [beforeRun]
/// может бросить исключение, [skipChmod] имитирует «успех без эффекта».
final class FakeSecretProcessRunner implements SecretProcessRunner {
  FakeSecretProcessRunner({
    this.beforeRun,
    this.skipChmod = false,
    this.skipWhen,
    this.failWhen,
  });

  final void Function(int callNumber)? beforeRun;
  final bool skipChmod;

  /// Пропускает настоящий `chmod` только для вызовов, где предикат истинен
  /// (например, лишь для `600` на временном файле, но не для `700` каталогов).
  final bool Function(List<String> arguments)? skipWhen;

  /// Возвращает код выхода `1` без выполнения `chmod` для вызовов, где
  /// предикат истинен (имитация `EPERM` у не-владельца каталога).
  final bool Function(List<String> arguments)? failWhen;
  final calls = <RecordedProcessCall>[];

  @override
  Future<SecretProcessResult> run(
    String executable,
    List<String> arguments, {
    String? stdin,
    Duration? timeout,
  }) async {
    final last = arguments.isEmpty ? null : arguments.last;
    int? length;
    if (last != null && File(last).existsSync()) {
      length = File(last).lengthSync();
    }
    calls.add(
      RecordedProcessCall(
        executable: executable,
        arguments: List.unmodifiable(arguments),
        stdin: stdin,
        lastArgumentLength: length,
      ),
    );
    beforeRun?.call(calls.length);
    if (failWhen?.call(arguments) ?? false) {
      return const SecretProcessResult(exitCode: 1);
    }
    if (skipChmod || (skipWhen?.call(arguments) ?? false)) {
      return const SecretProcessResult(exitCode: 0);
    }
    final result = Process.runSync(executable, arguments);
    return SecretProcessResult(exitCode: result.exitCode);
  }
}
