import 'dart:convert';
import 'dart:io';

import 'package:codelab_agent_core/codelab_agent_core.dart';

import 'environment_layer.dart';
import 'legacy_notice.dart';
import 'yaml_reader.dart';

/// Ошибка использования загрузчика: запрос, который нельзя выполнить и нельзя
/// считать проблемой конфигурации (`--config x.toml`).
///
/// Почему отдельный тип: хост переводит его в «ошибку использования» с кодом
/// `64` и справкой (`agent-core-architecture` §13.10), а проблемы файлов —
/// это [ConfigIssue] в результате загрузки. Сообщение значений не содержит.
final class ConfigUsageException implements Exception {
  const ConfigUsageException(this.message);

  final String message;

  @override
  String toString() => 'ConfigUsageException: $message';
}

/// Проверяет имя файла `--config` / `CODELAB_CONFIG`: `.yaml` или `.yml`.
///
/// Почему отдельной функцией: `codelab.toml` не поддерживается (D12), и
/// ошибку должен дать уже разбор флагов, а не только загрузчик. [origin] —
/// `--config` или `CODELAB_CONFIG` для текста. Нарушение —
/// [ConfigUsageException]; `.toml` получает отдельный текст про
/// `codelab.toml` (D4, `agent-core-architecture` §15.7).
void checkConfigFileName(String path, {required String origin}) {
  final lower = path.toLowerCase();
  if (lower.endsWith('.toml')) {
    throw ConfigUsageException(
      '$origin needs a .yaml file; codelab.toml is not supported, see '
      'agent-core-architecture §15.7',
    );
  }
  if (!lower.endsWith('.yaml') && !lower.endsWith('.yml')) {
    throw ConfigUsageException('$origin needs a .yaml or .yml file');
  }
}

/// Предел размера файла конфигурации: 1 MiB (CFG-21, `agent-core-
/// architecture` §15.5). Настоящий конфиг на порядки меньше.
const maxConfigBytes = 1024 * 1024;

/// `CODELAB_HOME` или `~/.codelab` (`agent-core-architecture` §15.6).
///
/// Для чего: один способ найти корень состояния у загрузчика и хостов
/// (журналы сессий, пользовательский конфиг).
String codelabHomeOf(Map<String, String> environment) {
  final explicit = environment['CODELAB_HOME'];
  if (explicit != null && explicit.isNotEmpty) {
    return explicit;
  }
  final user = environment['HOME'] ?? environment['USERPROFILE'] ?? '.';
  return '$user/.codelab';
}

/// Собирает конфигурацию из файлов, окружения и флагов (`agent-core-
/// architecture` §15.2, §15.5, §15.6; design.md change
/// `add-agent-configuration`, D4).
///
/// Почему в `codelab_agent_io`: только здесь есть `dart:io` и `package:yaml`
/// (CFG-5, PKG-1, PKG-2). Загрузчик читает файлы и строит деревья слоёв, а
/// проверку, доверие, слияние и подстановку делает чистая
/// `CoreConfig.fromLayers`.
///
/// Для чего: единый вход для `serve`, `config check` и встроенных хостов;
/// порядок слоёв (низший приоритет первым):
/// 1. встроенные умолчания;
/// 2. `$CODELAB_HOME/config.yaml`;
/// 3. `<cwd>/.codelab/config.yaml`;
/// 4. `<cwd>/.codelab/config.local.yaml`;
/// 5. файл `--config` / `CODELAB_CONFIG` (`.yaml` или `.yml`);
/// 6. переменные `CODELAB_*` ([buildEnvironmentLayer]);
/// 7. флаги (дерево строит хост).
///
/// Как использовать: один [ConfigLoader] на процесс —
/// `loader.load(cwd: …, environment: Platform.environment, flags: …)`.
/// Отсутствующий файл слоёв 2–4 пропускается, а файл `--config` / `CODELAB_CONFIG` обязан существовать (иначе `syntax`). Ошибка синтаксиса, нарушение профиля YAML
/// и нечисловая переменная — [ConfigIssue] в `issues` (конфиг тогда `null`),
/// а не исключение. [ConfigUsageException] — только для `--config` с чужим
/// расширением. Со [scripted] (`--llm-script`) слои 2–4 не читаются и каталог
/// `$CODELAB_HOME` не трогается; `--config` читается. Предупреждения файлов
/// (`config.file.ignored`) идут в `warnings` результата перед предупреждениями
/// ядра.
final class ConfigLoader {
  ConfigLoader();

  /// Корни, для которых `config.legacy_found` уже выдавалось: одно
  /// предупреждение на процесс и `cwd` (D12), а не на каждую загрузку.
  final _legacyReported = <String>{};

  /// Загружает конфигурацию для корня запуска [cwd].
  ///
  /// [environment] — переменные процесса: из них берутся `CODELAB_HOME`,
  /// `CODELAB_CONFIG`, слой окружения и подстановка `${ENV}`. [extraConfig] —
  /// значение `--config` (приоритетнее `CODELAB_CONFIG`). [flags] — слой
  /// флагов, `null` — флагов нет.
  ConfigLoadResult load({
    required String cwd,
    required Map<String, String> environment,
    ConfigTree? flags,
    String? extraConfig,
    bool scripted = false,
  }) {
    final extraPath =
        _nonEmpty(extraConfig) ?? _nonEmpty(environment['CODELAB_CONFIG']);
    final extraOrigin = _nonEmpty(extraConfig) != null
        ? '--config'
        : 'CODELAB_CONFIG';
    if (extraPath != null) {
      checkConfigFileName(extraPath, origin: extraOrigin);
      // Относительный путь переменной зависел бы от каталога, из которого
      // клиент запустил процесс: один и тот же `CODELAB_CONFIG` читал бы
      // разные файлы. Флаг `--config` вводит пользователь в этом каталоге.
      if (extraOrigin == 'CODELAB_CONFIG' && !_isAbsolute(extraPath)) {
        throw const ConfigUsageException(
          'CODELAB_CONFIG must be an absolute path',
        );
      }
    }

    final root = _canonical(cwd);
    final home = codelabHomeOf(environment);
    final layers = <ConfigTree>[const ConfigTree.defaults()];
    final issues = <ConfigIssue>[];
    final warnings = <ConfigIssue>[];

    var yamlFound = false;
    // [origin]: файл назван пользователем (`--config`, `CODELAB_CONFIG`), и
    // его отсутствие — ошибка; файлы слоёв 2–4 необязательны.
    // У явного файла источник проблемы чтения — имя флага или переменной
    // ([origin]), а путь идёт в текст: так stderr называет, откуда пришёл путь.
    void readFile(String path, ConfigLayerKind kind, {String? origin}) {
      if (!FileSystemEntity.isFileSync(path)) {
        if (origin != null) {
          issues.add(
            ConfigIssue(
              kind: ConfigIssueKind.syntax,
              key: '',
              source: origin,
              message: 'cannot read the file: $path: no such file',
            ),
          );
        }
        return;
      }
      yamlFound = true;
      final text = _readText(path, issues, origin: origin);
      if (text == null) {
        return;
      }
      final result = readYamlTree(text, source: path, kind: kind);
      if (result.tree case final tree?) {
        layers.add(
          kind == ConfigLayerKind.user
              ? _withCanonicalTrust(tree, environment)
              : tree,
        );
      } else {
        issues.addAll(result.issues);
      }
    }

    if (!scripted) {
      readFile('$home/config.yaml', ConfigLayerKind.user);
      readFile('$root/.codelab/config.yaml', ConfigLayerKind.project);
      readFile(
        '$root/.codelab/config.local.yaml',
        ConfigLayerKind.projectLocal,
      );
      warnings.addAll([
        ..._ignoredYml('$home/config.yml'),
        ..._ignoredYml('$root/.codelab/config.yml'),
        ..._ignoredYml('$root/.codelab/config.local.yml'),
      ]);
    }
    if (extraPath != null) {
      final path = _isAbsolute(extraPath) ? extraPath : '$root/$extraPath';
      readFile(path, ConfigLayerKind.extra, origin: extraOrigin);
    }

    // D12: подсказка только когда пользователь ещё не перешёл на YAML.
    if (!scripted &&
        extraPath == null &&
        !yamlFound &&
        _legacyReported.add(root)) {
      if (legacyConfigNotice(home: home, cwd: root) case final notice?) {
        warnings.add(notice);
      }
    }

    final env = buildEnvironmentLayer(environment);
    issues.addAll(env.issues);
    if (env.layer case final layer?) {
      layers.add(layer);
    }
    if (flags != null && flags.values.isNotEmpty) {
      layers.add(flags);
    }

    if (issues.isNotEmpty) {
      return ConfigLoadResult(
        issues: issues,
        warnings: warnings,
        sources: [for (final layer in layers) layer.source],
      );
    }
    final result = CoreConfig.fromLayers(
      layers,
      environment: environment,
      projectRoot: root,
    );
    return ConfigLoadResult(
      config: result.config,
      host: result.host,
      issues: result.issues,
      warnings: [...warnings, ...result.warnings],
      sources: result.sources,
    );
  }

  /// `config.yml` не читается: выбирать между ним и `config.yaml` значило бы
  /// угадывать намерение, а молчать — терять настройки (D4).
  List<ConfigIssue> _ignoredYml(String path) {
    if (!FileSystemEntity.isFileSync(path)) {
      return const [];
    }
    final hint =
        'rename it to ${path.replaceFirst(RegExp(r'\.yml$'), '.yaml')}';
    return [
      ConfigIssue(
        kind: ConfigIssueKind.semantic,
        key: '',
        source: path,
        message:
            'ignored: only config.yaml and config.local.yaml are read; $hint',
        event: 'config.file.ignored',
        fields: {'path': path, 'hint': hint},
      ),
    ];
  }

  /// Читает файл не больше [maxConfigBytes]: размер проверяется по `stat` до
  /// чтения, чтобы файл в гигабайты не попал в память (CFG-21). Байты
  /// декодируются строго: не-UTF-8 — проблема файла, а не молчаливая замена
  /// символов, которая исказила бы ключи.
  String? _readText(String path, List<ConfigIssue> issues, {String? origin}) {
    void fail(String message, {bool unreadable = false}) => issues.add(
      ConfigIssue(
        kind: ConfigIssueKind.syntax,
        key: '',
        source: unreadable ? origin ?? path : path,
        message: message,
      ),
    );
    try {
      if (File(path).statSync().size > maxConfigBytes) {
        fail('the file is larger than 1 MiB');
        return null;
      }
      return utf8.decode(File(path).readAsBytesSync());
    } on FileSystemException catch (error) {
      fail(
        'cannot read the file: $path: '
        '${error.osError?.message ?? error.message}',
        unreadable: true,
      );
    } on FormatException {
      fail('the file is not valid UTF-8');
    }
    return null;
  }

  /// Заменяет существующие элементы `trusted_projects` глобального слоя их
  /// каноническими путями (`~` раскрыт).
  ///
  /// Почему здесь: корень запуска канонический (symlink раскрыт), а ядро
  /// сравнивает пути лексически; запись на symlink иначе не доверяла бы
  /// проекту, а подменённая symlink-ом на чужой каталог доверяла бы чужому
  /// (приоритет 1). Несуществующий элемент остаётся как записан.
  ConfigTree _withCanonicalTrust(
    ConfigTree tree,
    Map<String, String> environment,
  ) {
    final roots = tree.values['trusted_projects'];
    if (roots is! List<Object?>) {
      return tree;
    }
    final home = environment['HOME'] ?? environment['USERPROFILE'];
    final canonical = <Object?>[
      for (final root in roots)
        if (root is String) _canonicalEntry(root, home) else root,
    ];
    return ConfigTree(
      kind: tree.kind,
      source: tree.source,
      values: {...tree.values, 'trusted_projects': canonical},
      positions: tree.positions,
    );
  }

  String _canonicalEntry(String entry, String? home) {
    final expanded = home != null && (entry == '~' || entry.startsWith('~/'))
        ? '$home${entry.substring(1)}'
        : entry;
    try {
      return Directory(expanded).resolveSymbolicLinksSync();
    } on FileSystemException {
      return entry;
    }
  }

  /// Канонический корень запуска: symlink раскрыт, как у
  /// `LocalExecutionEnv`, чтобы `trusted_projects` и выбор снимка D9
  /// сравнивали одинаковые пути.
  String _canonical(String cwd) {
    try {
      return Directory(cwd).resolveSymbolicLinksSync();
    } on FileSystemException {
      return Directory(cwd).absolute.path;
    }
  }

  bool _isAbsolute(String path) =>
      path.startsWith('/') || RegExp(r'^[A-Za-z]:[\\/]').hasMatch(path);

  String? _nonEmpty(String? value) =>
      value == null || value.isEmpty ? null : value;
}
