import 'dart:convert';
import 'dart:io';

import 'package:codelab_agent_core/codelab_agent_core.dart';
import 'package:meta/meta.dart';

import '../secrets/secrets_backend_problem.dart';
import 'config_link_containment.dart';
import 'environment_layer.dart';
import 'legacy_notice.dart';
import 'provider_preconfig.dart';
import 'yaml_reader.dart';

/// Ошибка использования загрузчика: запрос, который нельзя выполнить и нельзя
/// считать проблемой конфигурации (`--config x.toml`).
///
/// Почему отдельный тип: хост переводит его в «ошибку использования» с кодом
/// `64` и справкой (`agent-core-architecture` §13.10), а проблемы файлов —
/// это [ConfigIssue] в результате загрузки. Сообщение значений не содержит.
final class ConfigUsageException implements Exception {
  const ConfigUsageException(this.message, {this.source});

  final String message;

  /// Что именно задано неверно: `CODELAB_HOME`, `CODELAB_CONFIG` или
  /// `--config`. Хост без разбора текста называет источник в проблеме
  /// (встроенный агент, `EmbeddedAgentConfigException`); `null` — источник не
  /// определён.
  final String? source;

  @override
  String toString() => 'ConfigUsageException: $message';
}

/// Абсолютный ли путь: POSIX `/…` или Windows `C:\\…` / `C:/…`.
///
/// Почему отдельно: одну проверку используют загрузчик и подкоманды `secret`
/// (design.md change `add-agent-secret-store`, D8), и она не должна
/// расходиться.
bool isAbsoluteConfigPath(String path) =>
    path.startsWith('/') || RegExp(r'^[A-Za-z]:[\\/]').hasMatch(path);

/// Проверяет значение `CODELAB_CONFIG`: имя файла и абсолютный путь.
///
/// Почему: относительный путь переменной зависел бы от каталога, из которого
/// клиент запустил процесс, — один и тот же `CODELAB_CONFIG` читал бы разные
/// файлы. Флаг `--config` вводит пользователь в этом каталоге, поэтому для
/// него требование не действует. Нарушение — [ConfigUsageException]; одну
/// функцию вызывают `ConfigLoader` и `SecretCommands`.
void checkConfigEnvPath(String path) {
  checkConfigFileName(path, origin: 'CODELAB_CONFIG');
  if (!isAbsoluteConfigPath(path)) {
    throw const ConfigUsageException(
      'CODELAB_CONFIG must be an absolute path',
      source: 'CODELAB_CONFIG',
    );
  }
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
      source: origin,
    );
  }
  if (!lower.endsWith('.yaml') && !lower.endsWith('.yml')) {
    throw ConfigUsageException(
      '$origin needs a .yaml or .yml file',
      source: origin,
    );
  }
}

/// Предел размера файла конфигурации: 1 MiB (CFG-21, `agent-core-
/// architecture` §15.5). Настоящий конфиг на порядки меньше.
const maxConfigBytes = 1024 * 1024;

/// Итоговый текст слоя, который запишет та же операция следом (R8-10).
///
/// Почему: проверка кандидата одного файла сливает его с остальными слоями с
/// диска; когда файлов несколько (`secret migrate --all`), нужен итог всех
/// правок сразу. Значение — текст конфига: в `toString` не попадает.
final class PendingConfigText {
  const PendingConfigText({required this.kind, required this.text});

  /// Слой, чей файл получит [text]: кандидат этого слоя заменяется текстом
  /// при слиянии, остальные слои читаются с диска (R8-10).
  final ConfigLayerKind kind;

  /// Полный текст файла слоя после правки. Может содержать значения
  /// секретов, поэтому в `toString` не попадает.
  final String text;

  @override
  String toString() => 'PendingConfigText($kind)';
}

/// Итог [ConfigLoader.validateCandidate]: проблемы запрещают запись, а
/// предупреждения (в том числе `config.project.untrusted_key` и незаданная
/// `${VAR}`) сообщаются вызывающему (design.md change
/// `add-config-writer-and-reload`, D5).
typedef ConfigCandidateResult = ({
  List<ConfigIssue> issues,
  List<ConfigIssue> warnings,
});

/// Вид слоя загрузчика по слою записи (`ConfigLayer` ядра): одно отображение
/// для загрузчика и писателя.
@internal
ConfigLayerKind configLayerKindOf(ConfigLayer layer) => switch (layer) {
  ConfigLayer.user => ConfigLayerKind.user,
  ConfigLayer.project => ConfigLayerKind.project,
  ConfigLayer.projectLocal => ConfigLayerKind.projectLocal,
};

bool _isUnsetVariable(ConfigIssue issue) => issue.event == unsetVariableEvent;

/// Домашний каталог пользователя: `HOME`, на Windows `USERPROFILE`.
///
/// Пустое значение считается отсутствующим: тильда с пустым `HOME` не должна
/// превращаться в корень (`/x`), поэтому без домашнего каталога раскрытия нет.
///
/// Для чего: единственный источник домашнего каталога процесса для корней
/// навыков и PERM-11. Как использовать: хост берёт результат из того же
/// словаря окружения, что передаёт в `agentConfigPathsFor`, и отдаёт его в
/// `ProjectFilesLoader(userHome:)` — тогда корни загрузки навыков и пути
/// защиты PERM-11 не расходятся (design.md change `add-agent-skills`, D9,
/// D19). `Platform.environment` напрямую хосты не читают: тест подставляет
/// временный каталог словарём.
String? userHomeOf(Map<String, String> environment) {
  for (final name in const ['HOME', 'USERPROFILE']) {
    final value = environment[name];
    if (value != null && value.isNotEmpty) {
      return value;
    }
  }
  return null;
}

/// Раскрывает `~` и `~/…` в [home]; прочее и пустой [home] — без изменений.
///
/// Почему: оболочка не раскрывает тильду в кавычках (`CODELAB_HOME='~/x'`), а
/// относительный `~/x` молча указывал бы на `./~` (решение пользователя
/// 2026-10-30; D17 change `add-agent-project-files`). Одна функция для
/// `CODELAB_HOME` и `trusted_projects` (`agent-core-architecture` §15.6), чтобы
/// формы не расходились. Ошибки использования для
/// `CODELAB_HOME` бросает [codelabHomeOf], а запись `trusted_projects`, которую
/// нельзя раскрыть, остаётся как есть и ничему не равна (fail-closed).
String _expandHomeTilde(String path, String? home) {
  if (home == null || home.isEmpty) {
    return path;
  }
  if (path == '~' || path.startsWith('~/')) {
    return '$home${path.substring(1)}';
  }
  return path;
}

/// `CODELAB_HOME` (с раскрытием `~`) или `~/.codelab`
/// (`agent-core-architecture` §15.6).
///
/// Для чего: один способ найти корень состояния у загрузчика и хостов
/// (журналы сессий, пользовательский конфиг, файлы проекта); все места агента
/// берут домашний каталог только отсюда.
///
/// Как использовать: `~` и `~/…` раскрываются в `HOME` (`USERPROFILE`). Без
/// домашнего каталога и для любого значения на `~`, кроме `~` и `~/…`
/// (`~bob/x`, `~\x`), бросает [ConfigUsageException] (хост
/// превращает её в ошибку использования, код `64`): молча принять `~user`
/// значило бы читать конфиг из каталога `./~user` (D17).
String codelabHomeOf(Map<String, String> environment) {
  final home = userHomeOf(environment);
  final explicit = environment['CODELAB_HOME'];
  if (explicit != null && explicit.isNotEmpty) {
    if (explicit.startsWith('~') && explicit.length > 1 && explicit[1] != '/') {
      throw const ConfigUsageException(
        'CODELAB_HOME: ~user is not supported, use an absolute path',
        source: 'CODELAB_HOME',
      );
    }
    if (home == null && (explicit == '~' || explicit.startsWith('~/'))) {
      throw const ConfigUsageException(
        'CODELAB_HOME: cannot expand ~ without HOME or USERPROFILE, use an '
        'absolute path',
        source: 'CODELAB_HOME',
      );
    }
    return _expandHomeTilde(explicit, home);
  }
  return '${home ?? '.'}/.codelab';
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
/// 6. переменные `CODELAB_*`: сначала предконфигурация провайдера
///    `CODELAB_PROVIDER_*` ([preconfigLayer]), затем остальные
///    ([buildEnvironmentLayer]);
/// 7. флаги: сначала предконфигурация `--provider-type`/`--provider-config`
///    ([ProviderPreconfigFlags]), затем дерево флагов, которое строит хост
///    (поэтому `--model` побеждает модель предконфигурации, а `CODELAB_MODEL`
///    ей проигрывает; design.md change `add-config-writer-and-reload`, D3).
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
  /// флагов, `null` — флагов нет. [knownVariables] — имена `CODELAB_*`,
  /// которые назвал хост (переменная токена `--token-env`): они не опечатка.
  /// Неизвестные `CODELAB_*` попадают в `warnings` событием
  /// `config.env.unknown` (D13): правило одно для `serve` и `config check`.
  /// [preconfigFlags] — предконфигурация провайдера из флагов `serve`: если
  /// задана, переменные `CODELAB_PROVIDER_*` не читаются (D3). Её значение
  /// не попадает ни в проблемы, ни в лог.
  /// [platform] подменяет `Platform.operatingSystem` в тестах: на `windows`
  /// `secrets.backend: file` — проблема конфигурации (change
  /// `add-agent-secret-store`, D14).
  ///
  /// [pinnedTrustedProjects] — закреплённое доверие проектам (design.md change
  /// `add-config-writer-and-reload`, D8): загрузчик лишь передаёт список в
  /// `CoreConfig.fromLayers`, а доверие вычисляет ядро. Передаёт
  /// `FileConfigSource` (`initial.config.trustedProjects`); `null` — доверие
  /// по слоям, как при старте.
  ConfigLoadResult load({
    required String cwd,
    required Map<String, String> environment,
    ConfigTree? flags,
    ProviderPreconfigFlags? preconfigFlags,
    String? extraConfig,
    bool scripted = false,
    Set<String> knownVariables = const {},
    String? platform,
    List<String>? pinnedTrustedProjects,
  }) => loadWithLayers(
    cwd: cwd,
    environment: environment,
    flags: flags,
    preconfigFlags: preconfigFlags,
    extraConfig: extraConfig,
    scripted: scripted,
    knownVariables: knownVariables,
    platform: platform,
    pinnedTrustedProjects: pinnedTrustedProjects,
  ).result;

  /// Проверяет итоговый [text] слоя [target] теми же слоями и `fromLayers`,
  /// что обычная загрузка, не читая файл этого слоя с диска (design.md change
  /// `add-config-writer-and-reload`, D5, шаг 6 `agent-core-architecture`
  /// §17.5.5).
  ///
  /// Почему здесь: порядок слоёв, канонизация `trusted_projects`, слой
  /// окружения и правила доверия принадлежат загрузчику; писатель не
  /// повторяет их, иначе проверка записи разошлась бы с загрузкой.
  ///
  /// [pending] — итоговые тексты ДРУГИХ слоёв, которые та же операция запишет
  /// следом (`secret migrate --all`, R8-10): без них правка первого файла
  /// сливалась бы с ещё не переписанным вторым и давала промежуточный
  /// конфликт источников ключа (R8-6). По умолчанию пусто — одиночная запись
  /// не меняется.
  ///
  /// Как использовать: [cwd] — корень запуска (для слоёв `project` — каталог
  /// проекта), [environment] — переменные процесса писателя. Остальные слои
  /// читаются с диска. Незаданная `${VAR}` попадает в `warnings`, а не в
  /// `issues` (окружение агента может отличаться от окружения писателя);
  /// значения кандидата в проблемы не попадают (CFG-2).
  ///
  /// Проверка идёт в режиме `collectAll` ядра (R3-1, R3-3, решение
  /// пользователя 2026-11-03): ошибка ранней ступени не скрывает ошибки
  /// поздних, поэтому набор проблем исходного файла и кандидата полный и
  /// сравнивается писателем по сигнатуре. Обычная загрузка [load] режима не
  /// использует.
  ConfigCandidateResult validateCandidate(
    ConfigTarget target,
    String text, {
    required String cwd,
    required Map<String, String> environment,
    String? platform,
    @internal List<PendingConfigText> pending = const [],
  }) {
    final kind = configLayerKindOf(target.layer);
    ConfigLoadResult run(Map<String, String> env) => loadWithLayers(
      cwd: cwd,
      environment: env,
      platform: platform,
      candidate: (kind: kind, text: text),
      pending: pending,
      collectAll: true,
    ).result;

    var loaded = run(environment);
    // Незаданная `${VAR}` — предупреждение: окружение агента может
    // отличаться от окружения писателя (§17.5.5, шаг 6). Но без значения
    // переменной ядро не строит провайдера, и следом идут проблемы-
    // последствия (`default_model` не в каталоге). Поэтому проверка
    // повторяется с подставленным значением, а исходные проблемы
    // подстановки остаются предупреждениями.
    final unset = [
      for (final issue in loaded.issues)
        if (_isUnsetVariable(issue)) issue,
    ];
    if (unset.isNotEmpty) {
      loaded = run({
        for (final issue in unset)
          '${issue.fields['variable']}': 'https://unset.invalid',
        ...environment,
      });
    }
    final issues = <ConfigIssue>[];
    final warnings = [...unset, ...loaded.warnings];
    for (final issue in loaded.issues) {
      if (_isUnsetVariable(issue)) {
        warnings.add(issue);
      } else {
        issues.add(issue);
      }
    }
    return (issues: issues, warnings: warnings);
  }

  /// То же, что [load], плюс разобранные слои по порядку приоритета.
  ///
  /// Почему: `config check` называет файл и строку ключа, на который ссылается
  /// предупреждение о секрете (`providers.p.api_key_secret`), а результат
  /// ядра позиций ссылок не хранит (design.md change `add-agent-secret-store`,
  /// D9). Слои — те же деревья, что ушли в `CoreConfig.fromLayers`; в них могут
  /// быть и значения, вписанные в конфиг (`api_key`), поэтому вызывающий
  /// использует только позиции ключей, а значения не печатает.
  ///
  /// Как использовать: только внутри пакета (`ConfigCommands`); для
  /// приложений — [load].
  @internal
  ({ConfigLoadResult result, List<ConfigTree> layers}) loadWithLayers({
    required String cwd,
    required Map<String, String> environment,
    ConfigTree? flags,
    ProviderPreconfigFlags? preconfigFlags,
    String? extraConfig,
    bool scripted = false,
    Set<String> knownVariables = const {},
    String? platform,
    ({ConfigLayerKind kind, String text})? candidate,
    List<PendingConfigText> pending = const [],
    bool collectAll = false,
    List<String>? pinnedTrustedProjects,
  }) {
    final extraPath =
        _nonEmpty(extraConfig) ?? _nonEmpty(environment['CODELAB_CONFIG']);
    final extraOrigin = _nonEmpty(extraConfig) != null
        ? '--config'
        : 'CODELAB_CONFIG';
    if (extraPath != null) {
      if (extraOrigin == 'CODELAB_CONFIG') {
        checkConfigEnvPath(extraPath);
      } else {
        checkConfigFileName(extraPath, origin: extraOrigin);
      }
    }

    final root = _canonical(cwd);
    // Под сценарием `--llm-script` `$CODELAB_HOME` не читается и не проверяется
    // (D16, D17): неверная тильда не должна давать код 64. Пустой [home]
    // используется только в ветках `!scripted`.
    final home = scripted ? '' : codelabHomeOf(environment);
    final layers = <ConfigTree>[const ConfigTree.defaults()];
    final issues = <ConfigIssue>[];
    final warnings = <ConfigIssue>[];

    var yamlFound = false;
    // [origin]: файл назван пользователем (`--config`, `CODELAB_CONFIG`), и
    // его отсутствие — ошибка; файлы слоёв 2–4 необязательны.
    // У явного файла источник проблемы чтения — имя флага или переменной
    // ([origin]), а путь идёт в текст: так stderr называет, откуда пришёл путь.
    void readFile(String path, ConfigLayerKind kind, {String? origin}) {
      final String? text;
      final PendingConfigText? replacement =
          candidate != null && candidate.kind == kind
          ? PendingConfigText(kind: candidate.kind, text: candidate.text)
          : pending.where((p) => p.kind == kind).firstOrNull;
      if (replacement != null) {
        // Кандидат записи заменяет слой целиком (D5, шаг 6): файла на диске
        // может не быть или он может отличаться от того, что будет записано.
        // Имя источника остаётся путём слоя, чтобы проблемы называли файл
        // конфига, а не tmp.
        yamlFound = true;
        if (utf8.encode(replacement.text).length > maxConfigBytes) {
          issues.add(
            ConfigIssue(
              kind: ConfigIssueKind.syntax,
              key: '',
              source: path,
              message: 'the file is larger than 1 MiB',
            ),
          );
          return;
        }
        text = replacement.text;
      } else {
        // 8.5: проектный слой читается только по реальному пути внутри
        // `<cwd>/.codelab` (проверенное и открытое совпадают). Существующая
        // цель вне `.codelab`, цикл и `..` в хвосте — проблема с путём слоя,
        // без содержимого и цели ссылки; висячая ссылка (внутрь или наружу) —
        // слой молча отсутствует: ничего снаружи не читается, а проект с
        // `.codelab`-ссылкой на общий каталог без config-файлов должен
        // запускаться. Слой `user` и `--config` пользователь выбрал сам.
        var readFrom = path;
        if (kind == ConfigLayerKind.project ||
            kind == ConfigLayerKind.projectLocal) {
          switch (checkProjectLayer(path, root)) {
            case ProjectLayerReadable(:final realPath):
              readFrom = realPath;
            case ProjectLayerAbsent():
              return;
            case ProjectLayerRefused(:final message):
              yamlFound = true;
              issues.add(
                ConfigIssue(
                  kind: ConfigIssueKind.syntax,
                  key: '',
                  source: path,
                  message: message,
                ),
              );
              return;
          }
        }
        if (!FileSystemEntity.isFileSync(readFrom)) {
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
        text = _readText(path, issues, origin: origin, readFrom: readFrom);
        if (text == null) {
          return;
        }
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

    warnings.addAll(
      unknownEnvironmentWarnings(environment, extraKnown: knownVariables),
    );
    // Слои 6 и 7 (D3): предконфигурация идёт первой в своём слое, чтобы более
    // частное значение (`CODELAB_MODEL`, `--model`) её переопределяло.
    final preconfig = preconfigLayer(environment, flags: preconfigFlags);
    issues.addAll(preconfig.issues);
    warnings.addAll(preconfig.notices);
    final preconfigFromFlags = preconfig.layer?.kind == ConfigLayerKind.flags;
    if (preconfig.layer case final layer? when !preconfigFromFlags) {
      layers.add(layer);
    }
    final env = buildEnvironmentLayer(environment);
    issues.addAll(env.issues);
    if (env.layer case final layer?) {
      layers.add(layer);
    }
    if (preconfig.layer case final layer? when preconfigFromFlags) {
      layers.add(layer);
    }
    if (flags != null && flags.values.isNotEmpty) {
      layers.add(flags);
    }

    if (issues.isNotEmpty) {
      return (
        result: ConfigLoadResult(
          issues: issues,
          warnings: warnings,
          sources: [for (final layer in layers) layer.source],
        ),
        layers: layers,
      );
    }
    final result = CoreConfig.fromLayers(
      layers,
      environment: environment,
      projectRoot: root,
      collectAll: collectAll,
      pinnedTrustedProjects: pinnedTrustedProjects,
    );
    final windowsFile = scripted
        ? null
        : _fileBackendOnWindows(result, layers, platform);
    if (windowsFile != null) {
      return (
        result: ConfigLoadResult(
          issues: [...result.issues, windowsFile],
          warnings: [...warnings, ...result.warnings],
          sources: result.sources,
          values: result.values,
        ),
        layers: layers,
      );
    }
    return (
      result: ConfigLoadResult(
        config: result.config,
        host: result.host,
        issues: result.issues,
        warnings: [...warnings, ...result.warnings],
        sources: result.sources,
        values: result.values,
      ),
      layers: layers,
    );
  }

  /// Проблема `secrets.backend: file` на Windows (agent-secrets «Бэкенд file»,
  /// design.md change `add-agent-secret-store`, D7, D14).
  ///
  /// Почему здесь, а не в ядре: ядро платформу не знает (PKG-1). Права NTFS
  /// `dart:io` не проверяет, поэтому открытый файл на Windows недопустим;
  /// `FileSecretStore` отказывает и сам (защита в глубину). Со [scripted]
  /// проверки нет: сценарий всегда использует `env` (D11). Позиция берётся из
  /// слоя, где задан ключ, чтобы сообщение указало файл и строку.
  ConfigIssue? _fileBackendOnWindows(
    ConfigLoadResult result,
    List<ConfigTree> layers,
    String? platform,
  ) {
    // Тот же `secretsBackendProblem`, что у `openSecretStore`: тексты не
    // расходятся. Ядро уже отсекло `keychain` и незнакомые значения, поэтому
    // здесь срабатывает только `file` на Windows.
    final problem = secretsBackendProblem(
      result.host?.secretsBackend,
      platform ?? Platform.operatingSystem,
    );
    if (problem == null) {
      return null;
    }
    ConfigTree? origin;
    for (final layer in layers.reversed) {
      if (layer.positions.containsKey('secrets.backend')) {
        origin = layer;
        break;
      }
    }
    final position = origin?.positions['secrets.backend'];
    return ConfigIssue(
      kind: ConfigIssueKind.value,
      key: 'secrets.backend',
      source: origin?.source ?? 'config',
      line: position?.line,
      column: position?.column,
      message: problem.message,
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
  /// символов, которая исказила бы ключи. [readFrom] — реальный путь проектного
  /// слоя (8.5): читается он, а в проблемах называется [path].
  String? _readText(
    String path,
    List<ConfigIssue> issues, {
    String? origin,
    String? readFrom,
  }) {
    void fail(String message, {bool unreadable = false}) => issues.add(
      ConfigIssue(
        kind: ConfigIssueKind.syntax,
        key: '',
        source: unreadable ? origin ?? path : path,
        message: message,
      ),
    );
    try {
      final actual = readFrom ?? path;
      if (File(actual).statSync().size > maxConfigBytes) {
        fail('the file is larger than 1 MiB');
        return null;
      }
      return utf8.decode(File(actual).readAsBytesSync());
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
    final home = userHomeOf(environment);
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
    final expanded = _expandHomeTilde(entry, home);
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

  bool _isAbsolute(String path) => isAbsoluteConfigPath(path);

  String? _nonEmpty(String? value) =>
      value == null || value.isEmpty ? null : value;
}
