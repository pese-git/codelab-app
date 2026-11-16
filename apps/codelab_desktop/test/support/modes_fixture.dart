// Фикстура страницы «Agents & modes» (задача 1.1 change
// `add-settings-agents-modes`; design.md D4, D6, D11).
//
// Почему настоящий `FileAgentConfigStore` во временной папке, а не двойник:
// итог режима, источник, предупреждение недоверенного проекта и
// `restartRequiredKeys` дают загрузчик и писатель ядра, а клиент
// `codelab_desktop` не зависит от `codelab_agent_core` и не может построить
// `CoreConfig` сам. Правило доверия не подменяется моком. Временная папка
// создаётся в системном каталоге и удаляется в `dispose`; `$CODELAB_HOME`
// разработчика не читается.

import 'dart:async';
import 'dart:io';

import 'package:codelab_desktop/features/settings/application/provider_settings_session.dart';
import 'package:codelab_setup/codelab_setup.dart';

import 'real_config_session.dart';

/// Запись `apply`: путь слоя-основы и правки.
typedef AppliedEdit = ({String path, List<ConfigEdit> edits});

/// Хранилище-обёртка: настоящее чтение и запись плюс управление тестом.
///
/// Почему: тесты Cubit-а должны удерживать снимок или запись (поздний
/// результат, повторный выбор во время записи), подменять исход записи
/// (конфликт, `restartRequiredKeys`) и считать вызовы.
final class ControlledConfigStore implements AgentConfigStore {
  ControlledConfigStore(this._inner);

  final AgentConfigStore _inner;

  /// Вызовы `snapshot`.
  var snapshotCalls = 0;

  /// Вызовы `apply` (путь слоя и правки).
  final applied = <AppliedEdit>[];

  /// Ожидание после чтения снимка; аргумент — номер вызова с 1. Возвращённое
  /// будущее удерживает именно этот вызов.
  Future<void>? Function(int call)? onSnapshot;

  /// Ожидание внутри `apply` до записи.
  Future<void> Function()? onApply;

  /// Исход вместо настоящей записи; файл при этом не меняется.
  ConfigSaveOutcome? forcedOutcome;

  /// Исключение вместо записи.
  Object? applyError;

  @override
  Future<AgentConfigSnapshot> snapshot({required String cwd}) async {
    final call = ++snapshotCalls;
    final snapshot = await _inner.snapshot(cwd: cwd);
    await onSnapshot?.call(call);
    return snapshot;
  }

  @override
  Future<ConfigSaveOutcome> apply(
    ConfigSnapshot base,
    List<ConfigEdit> edits,
  ) async {
    applied.add((path: base.path, edits: edits));
    await onApply?.call();
    if (applyError case final error?) {
      throw error;
    }
    return forcedOutcome ?? await _inner.apply(base, edits);
  }
}

/// Сессия настроек страницы: только `config`, остальное страница «Agents &
/// modes» не использует (tasks.md 1.3).
final class ModesSession implements ProviderSettingsSession {
  ModesSession(this.config);

  @override
  final ControlledConfigStore config;

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnimplementedError('${invocation.memberName}');
}

/// Временные `CODELAB_HOME` и проект с настоящим хранилищем конфига.
final class ModesFixture {
  ModesFixture._(this._root, this.home, this.project, this.store, this.access);

  final Directory _root;

  /// `$CODELAB_HOME` теста.
  final String home;

  /// Папка проекта (с раскрытыми символьными ссылками: сравнение доверия идёт
  /// по каноническому пути).
  final String project;

  final ControlledConfigStore store;

  /// Доступ профиля: тот же дом и проект.
  final EditableSettings access;

  /// Создаёт фикстуру. [userYaml] дописывается к минимальному конфигу дома
  /// (`realHomeConfig`); [trusted] добавляет проект в `trusted_projects`;
  /// [localYaml] и [projectYaml] — содержимое `config.local.yaml` и
  /// `config.yaml` проекта.
  static Future<ModesFixture> open({
    String userYaml = '',
    bool trusted = true,
    String? localYaml,
    String? projectYaml,
    bool withProject = true,
  }) async {
    final root = Directory.systemTemp.createTempSync('codelab_modes_');
    final real = root.resolveSymbolicLinksSync();
    final home = '$real/home';
    final project = '$real/project';
    Directory(home).createSync();
    Directory(project).createSync();
    if (localYaml != null || projectYaml != null) {
      Directory('$project/.codelab').createSync();
      if (localYaml != null) {
        File(
          '$project/.codelab/config.local.yaml',
        ).writeAsStringSync(localYaml);
      }
      if (projectYaml != null) {
        File('$project/.codelab/config.yaml').writeAsStringSync(projectYaml);
      }
    }
    final session = await RealConfigSession.open(
      home: home,
      project: project,
      config:
          '$realHomeConfig$userYaml'
          '${trusted ? 'trusted_projects:\n  - $project\n' : ''}',
    );
    return ModesFixture._(
      root,
      home,
      project,
      ControlledConfigStore(session.config),
      withProject
          ? session.access
          : EditableSettings(ConfigPaths(codelabHome: home)),
    );
  }

  /// Текст пользовательского `config.yaml`.
  String get userConfig => File('$home/config.yaml').readAsStringSync();

  /// Текст `config.local.yaml` проекта; пусто, если файла нет.
  String get localConfig {
    final file = File('$project/.codelab/config.local.yaml');
    return file.existsSync() ? file.readAsStringSync() : '';
  }

  /// Текст `.codelab/config.yaml` проекта; пусто, если файла нет.
  String get projectConfig {
    final file = File('$project/.codelab/config.yaml');
    return file.existsSync() ? file.readAsStringSync() : '';
  }

  /// Корень временной папки: этот путь не должен попасть в журнал.
  String get rootPath => _root.path;

  void dispose() => _root.deleteSync(recursive: true);
}
