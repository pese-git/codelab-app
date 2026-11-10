/// Переходный алиас `codelab serve` → `codelab-agent serve`.
///
/// Почему: скрипты, профили и конфигурации редакторов запускали Python-агента
/// командой `codelab serve --stdio`; чтобы они не сломались сразу после
/// переключения на Dart-агента, `codelab` до удаления Python-агента запускает
/// `codelab-agent` (change `retire-python-agent`, D6–D11; spec codelab-cli
/// «Алиас codelab serve»).
///
/// Для чего: алиас — отдельный процесс `codelab-agent` с общими stdin, stdout
/// и stderr, а не встроенный сервер: протокольного кода здесь нет, поэтому
/// кадры ACP, буферизация и порядок stderr совпадают с прямым запуском
/// (D6). Файл — единственное место алиаса с `dart:io` (процесс и сигналы,
/// `AGENTS.md` приложения §2); чистые части ([locateAgentExecutable],
/// [serveAliasExitCode], тексты) проверяются модульными тестами.
///
/// Как использовать: `run.dart` вызывает [runServeAlias] для
/// `CliCommand.serveAlias` до открытия домашнего каталога и профилей.
library;

import 'dart:async';
import 'dart:io';

import 'package:path/path.dart' as p;

import 'cli_io.dart';
import 'exit_codes.dart';
import 'signals.dart';

/// Предупреждение об алиасе: одна строка в stderr до запуска (D9). Версия
/// снятия не называется: она зависит от условия D4 change.
const serveAliasWarning =
    'codelab: "codelab serve" is deprecated and will be removed in a future '
    'release; use "codelab-agent serve" instead.';

/// Сообщение «бинарь не найден» (D9): называет оба места поиска, но не
/// печатает `PATH`.
const serveAliasNotFound =
    'codelab: codelab-agent was not found next to codelab or in PATH; '
    'install it or run "codelab-agent serve" directly';

/// Сообщение о рекурсии алиаса: `codelab-agent` оказался обёрткой вокруг
/// `codelab serve` (без аргументов: в них могут быть секреты, D9).
const serveAliasRecursion =
    'codelab: "codelab serve" cannot run itself; check that codelab-agent is '
    'not a wrapper around codelab serve, or run "codelab-agent serve" '
    'directly.';

/// Переменная-маркер в окружении дочернего процесса: не секрет. Если `codelab
/// serve` видит её у себя, значит, его запустил другой алиас (скрипт-обёртка
/// `codelab-agent → codelab serve` обходит проверку канонического пути, D7).
const serveAliasMarker = 'CODELAB_SERVE_ALIAS_ACTIVE';

/// Сообщение о сбое `Process.start`; [message] — `ProcessException.message`
/// без аргументов (D9; правило change `redact-cli-stdio-profile-args`: в
/// аргументах агента могут быть значения секретов).
String serveAliasStartFailure(String message) =>
    'codelab: cannot start codelab-agent: $message';

/// Код выхода `codelab` по коду дочернего процесса (D9).
///
/// Почему: на POSIX Dart отдаёт смерть от сигнала `N` как `-N`, а
/// оболочка и скрипты ждут `128 + N`, как у прямого запуска.
int serveAliasExitCode(int childExitCode) =>
    childExitCode < 0 ? 128 - childExitCode : childExitCode;

/// Ищет `codelab-agent` (D7).
///
/// Порядок: каталог [codelabExecutable], затем абсолютные записи [path]
/// (разделитель [pathSeparator]). Пустые и относительные записи (в том числе
/// `.`) пропускаются, чтобы текущая папка, например клонированный
/// репозиторий, не подставила свой `codelab-agent`. Кандидат, канонический
/// путь которого равен каноническому пути [codelabExecutable], отбрасывается
/// и поиск идёт дальше: иначе ссылка `codelab-agent → codelab` дала бы
/// бесконечную цепочку процессов. Имя — `codelab-agent.exe` при [isWindows].
///
/// Чистая функция: файловая система приходит функциями [isExecutableFile] и
/// [canonicalize]. Возвращает `null`, если бинаря нет.
String? locateAgentExecutable({
  required String codelabExecutable,
  required String? path,
  required String pathSeparator,
  required bool isWindows,
  required bool Function(String file) isExecutableFile,
  required String Function(String file) canonicalize,
}) {
  final context = p.Context(style: isWindows ? p.Style.windows : p.Style.posix);
  final name = isWindows ? 'codelab-agent.exe' : 'codelab-agent';
  final self = canonicalize(codelabExecutable);
  final directories = [
    context.dirname(codelabExecutable),
    ...?path
        ?.split(pathSeparator)
        // На Windows записи `PATH` бывают в кавычках (`"C:\Program Files\x"`
        // — так разрешены `;` в пути): кавычки снимаются до проверки.
        .map((entry) => isWindows ? _unquote(entry) : entry)
        // Пустая запись тоже отсекается: `isAbsolute('')` ложно (D7).
        .where(context.isAbsolute),
  ];
  for (final directory in directories) {
    final candidate = context.join(directory, name);
    if (isExecutableFile(candidate) && canonicalize(candidate) != self) {
      return candidate;
    }
  }
  return null;
}

String _unquote(String entry) =>
    entry.length >= 2 && entry.startsWith('"') && entry.endsWith('"')
    ? entry.substring(1, entry.length - 1)
    : entry;

/// Запущенный агент для [runServeAlias]: то, что алиасу нужно от процесса.
///
/// Почему: `Process` нельзя подделать в модульном тесте; шов позволяет
/// проверить порядок сигналов и `flush` без настоящего процесса.
final class AgentProcess {
  const AgentProcess({required this.kill, required this.exitCode});

  /// Посылает сигнал процессу агента.
  final bool Function(ProcessSignal signal) kill;

  /// Код выхода агента.
  final Future<int> exitCode;
}

/// Запускает агента: [executable] с аргументами [args], общие stdio;
/// [extraEnvironment] добавляется к окружению процесса `codelab`.
typedef StartAgent =
    Future<AgentProcess> Function(
      String executable,
      List<String> args,
      Map<String, String> extraEnvironment,
    );

Future<AgentProcess> _startAgentProcess(
  String executable,
  List<String> args,
  Map<String, String> extraEnvironment,
) async {
  final process = await Process.start(
    executable,
    args,
    environment: extraEnvironment,
    mode: ProcessStartMode.inheritStdio,
  );
  return AgentProcess(kill: process.kill, exitCode: process.exitCode);
}

/// Запускает `codelab-agent serve [agentArgs]` и возвращает код выхода
/// `codelab` (D6, D9, D10).
///
/// Порядок: записать предупреждение и дождаться записи (порядок строк в
/// stderr детерминирован); отказать при рекурсии (маркер
/// [serveAliasMarker] в окружении); найти бинарь; подписаться на сигналы;
/// запустить процесс с `inheritStdio`, окружением `codelab` и маркером;
/// дождаться `exitCode`; снять подписки. stdout алиас не трогает: для
/// `--stdio` это канал ACP.
///
/// Сигналы (D10): `SIGTERM` и `SIGHUP` пересылаются агенту (пришедшие до
/// старта запоминаются и пересылаются сразу после него); `SIGINT`
/// перехватывается, чтобы `codelab` не умер раньше агента, но не
/// пересылается — терминал доставляет его всей группе процессов, а второй
/// сигнал завершил бы агента без дописанного журнала. На Windows
/// отслеживается только `SIGINT`.
///
/// Тесты подставляют [startAgent], [codelabExecutable], [isWindows],
/// [isExecutableFile] и [canonicalize]; по умолчанию — настоящие процесс и
/// файловая система.
Future<int> runServeAlias(
  List<String> agentArgs, {
  required Map<String, String> environment,
  required CliIo io,
  SignalSeam signals = const SignalSeam(),
  String? codelabExecutable,
  bool? isWindows,
  bool Function(String file)? isExecutableFile,
  String Function(String file)? canonicalize,
  StartAgent startAgent = _startAgentProcess,
}) async {
  final windows = isWindows ?? Platform.isWindows;
  io.stderr.writeln(serveAliasWarning);
  await io.flush();

  if (environment.containsKey(serveAliasMarker)) {
    io.stderr.writeln(serveAliasRecursion);
    return failureExit;
  }

  final executable = locateAgentExecutable(
    codelabExecutable: codelabExecutable ?? Platform.resolvedExecutable,
    path: environment['PATH'],
    pathSeparator: windows ? ';' : ':',
    isWindows: windows,
    isExecutableFile: isExecutableFile ?? _isExecutableFile,
    canonicalize: canonicalize ?? _canonicalize,
  );
  if (executable == null) {
    io.stderr.writeln(serveAliasNotFound);
    return failureExit;
  }

  AgentProcess? child;
  final early = <ProcessSignal>[];
  void forward(ProcessSignal signal) {
    final running = child;
    if (running == null) {
      early.add(signal);
    } else {
      running.kill(signal);
    }
  }

  final term =
      signals.sigterm ?? (windows ? null : ProcessSignal.sigterm.watch());
  final hup = signals.sighup ?? (windows ? null : ProcessSignal.sighup.watch());
  final subscriptions = <StreamSubscription<ProcessSignal>>[
    // Перехват без пересылки: сам факт подписки отменяет завершение процесса
    // `codelab` по умолчанию (D10).
    (signals.sigint ?? ProcessSignal.sigint.watch()).listen((_) {}),
    ?term?.listen((_) => forward(ProcessSignal.sigterm)),
    ?hup?.listen((_) => forward(ProcessSignal.sighup)),
  ];
  try {
    try {
      child = await startAgent(
        executable,
        ['serve', ...agentArgs],
        const {serveAliasMarker: '1'},
      );
    } on ProcessException catch (error) {
      io.stderr.writeln(serveAliasStartFailure(error.message));
      return failureExit;
    }
    early.forEach(child.kill);
    return serveAliasExitCode(await child.exitCode);
  } finally {
    for (final subscription in subscriptions) {
      await subscription.cancel();
    }
  }
}

/// Обычный файл с битом исполнения (на Windows достаточно существования).
bool _isExecutableFile(String path) {
  final stat = FileStat.statSync(path);
  if (stat.type != FileSystemEntityType.file) {
    return false;
  }
  return Platform.isWindows || (stat.mode & 0x49) != 0;
}

/// Канонический путь с раскрытыми ссылками; недоступный путь — как есть.
String _canonicalize(String path) {
  try {
    return File(path).resolveSymbolicLinksSync();
  } on FileSystemException {
    return path;
  }
}
