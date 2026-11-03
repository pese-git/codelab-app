import 'dart:io';
import 'dart:math';

import 'package:codelab_agent_core/testing.dart';
import 'package:codelab_agent_io/codelab_agent_io.dart';
import 'package:codelab_agent_io/src/config/config_writer.dart'
    show ConfigWriteSeam;

import 'fake_secret_process_runner.dart';

/// Минимальный валидный конфиг: провайдер `p` с моделями `m` и `n`.
const baseConfig = '''
providers:
  p:
    kind: openai-compatible
    base_url: https://llm.test/v1
    models:
      m: {}
      n: {}
agent:
  default_model: p/m
''';

/// Окружение теста `ConfigWriter` (design.md change
/// `add-config-writer-and-reload`, D5, D15): временные `CODELAB_HOME` и
/// `cwd`, фейковые часы, генератор случайных чисел и порт `chmod`.
///
/// Почему отдельный файл: `config_writer_test.dart` и
/// `config_writer_atomic_test.dart` строят один и тот же писатель; различие
/// только в шве между записью tmp и `rename` и в платформе.
///
/// Как использовать: `final h = ConfigWriterHarness.create()` в `setUp`,
/// `h.dispose()` в `tearDown`. Тест не читает настоящий `~/.codelab`:
/// `CODELAB_HOME` и окружение передаются явно.
final class ConfigWriterHarness {
  ConfigWriterHarness._({
    required this.root,
    required this.home,
    required this.cwd,
    required this.clock,
    required this.logger,
    required this.runner,
    required this.writer,
  });

  factory ConfigWriterHarness.create({
    SecretProcessRunner? runner,
    Future<void> Function(ConfigWriteSeam point)? seam,
    String? platform,
    Map<String, String> environment = const {},
    String Function(String home)? homeFor,
    String cwdName = 'proj',
  }) {
    // Каталог сразу канонический (на macOS `/var` — ссылка на
    // `/private/var`): писатель раскрывает ссылки, и пути в ожиданиях теста
    // должны совпадать с ним.
    final root = Directory(
      Directory.systemTemp
          .createTempSync('config_writer_test')
          .resolveSymbolicLinksSync(),
    );
    final home = '${root.path}/home';
    final cwd = '${root.path}/$cwdName';
    Directory(home).createSync();
    Directory(cwd).createSync();
    final clock = FakeClock();
    final logger = RecordingLogger();
    final fakeRunner = runner ?? FakeSecretProcessRunner();
    return ConfigWriterHarness._(
      root: root,
      home: home,
      cwd: cwd,
      clock: clock,
      logger: logger,
      runner: fakeRunner,
      writer: ConfigWriter(
        codelabHome: homeFor?.call(home) ?? home,
        environment: {'CODELAB_HOME': home, ...environment},
        loader: ConfigLoader(),
        logger: logger,
        processRunner: fakeRunner,
        clock: clock,
        random: Random(7),
        cwd: cwd,
        platform: platform,
        seam: seam,
      ),
    );
  }

  final Directory root;
  final String home;
  final String cwd;
  final FakeClock clock;
  final RecordingLogger logger;
  final SecretProcessRunner runner;
  final ConfigWriter writer;

  /// Файл слоя `user`.
  String get userPath => '$home/config.yaml';

  /// Файл слоя `project`.
  String get projectPath => '$cwd/.codelab/config.yaml';

  /// Файл слоя `projectLocal`.
  String get localPath => '$cwd/.codelab/config.local.yaml';

  void write(String path, String text) {
    File(path)
      ..parent.createSync(recursive: true)
      ..writeAsStringSync(text);
  }

  String read(String path) => File(path).readAsStringSync();

  /// Каталог файла без служебных имён: найденные `.lock`, `.tmp-*`.
  List<String> leftovers(String path) {
    final dir = File(path).parent;
    if (!dir.existsSync()) {
      return const [];
    }
    final base = path.split('/').last;
    return [
      for (final entity in dir.listSync(followLinks: false))
        if (entity.path.split('/').last != base &&
            entity.path.split('/').last.startsWith(base))
          entity.path.split('/').last,
    ]..sort();
  }

  /// Проставляет время изменения файла относительно часов теста: возраст
  /// lock и брошенных tmp считается по `Clock` писателя, а не по настоящему
  /// времени (D5).
  void touch(String path, {required Duration age}) {
    File(path).setLastModifiedSync(clock.now().subtract(age));
  }

  void dispose() {
    if (root.existsSync()) {
      root.deleteSync(recursive: true);
    }
  }
}
