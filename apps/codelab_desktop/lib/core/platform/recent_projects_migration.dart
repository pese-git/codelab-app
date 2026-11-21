// Перенос недавних проектов из `shared_preferences` в общий файл
// `$CODELAB_HOME/recent_projects.json` (change `share-recent-projects-store`,
// D4, D9, D11) и заглушка для недопустимого `CODELAB_HOME` (D8).
//
// Срок жизни переноса: только предвыпускные сборки. Код переноса
// (`MigratingRecentProjectsStore`, чтение и удаление ключа
// `codelab.recent_projects`, события `recent_projects.*`) и его тест удаляет
// change `remove-recent-projects-migration` до первого `stable` 1.0 (решение
// пользователя Q2 (б), 2026-11-22; условие — `delivery-roadmap.md` §4.5 и
// §10.4): у 1.0 постоянный идентификатор бандла, прежний домен настроек он не
// читает, и держать мёртвый код в первом `stable` незачем. Заглушка и
// исключение ниже остаются.

import 'dart:convert';

import 'package:codelab_client_acp/codelab_client_acp.dart' show Logger;
import 'package:codelab_client_core/codelab_client_core.dart'
    show RecentProject, RecentProjectsStore;
import 'package:codelab_client_io/codelab_client_io.dart'
    show JsonFileRecentProjectsStore;
import 'package:shared_preferences/shared_preferences.dart';

/// Ключ списка в `shared_preferences` у сборок до этого change.
const _legacyKey = 'codelab.recent_projects';

/// Одноразовый перенос прежнего списка в файл при первом обращении.
///
/// Почему: до change `share-recent-projects-store` app хранил недавние
/// проекты в `shared_preferences`, и без переноса список пользователя
/// предвыпускной сборки пропал бы молча (D4). Обёртка, а не код в Cubit:
/// у переноса своя политика и свои тесты, потребители остаются на порте.
///
/// Для чего: первый `load` или `record` (в том числе параллельные) ждёт один
/// и тот же перенос (`_migration ??= _migrate()`), поэтому в файл ничего не
/// пишется до его конца. Алгоритм: нет ключа — нет переноса; значение не
/// разбирается — ключ удаляется, событие `recent_projects.legacy_unreadable`;
/// иначе `target.merge`, затем удаление ключа и `recent_projects.migrated`;
/// `merge` бросил (нечитаемый файл, D2) или сбой `shared_preferences` —
/// `recent_projects.migration_failed`, ключ остаётся, ошибка наружу не идёт:
/// дальше `load` и `record` ведут себя по D2 на [target]. Идемпотентность
/// даёт слияние по пути (D5): повтор после сбоя удаления ключа даёт тот же
/// файл. Записи не фильтруются (Q1 (а)). События без путей (D11).
///
/// Как использовать: composition root при допустимом `CODELAB_HOME` —
/// `MigratingRecentProjectsStore(target: JsonFileRecentProjectsStore(…),
/// logger: …)`. [legacyKeyRemover] — шов тестов для сбоя удаления ключа.
final class MigratingRecentProjectsStore implements RecentProjectsStore {
  MigratingRecentProjectsStore({
    required JsonFileRecentProjectsStore target,
    required Logger logger,
    Future<void> Function(String key)? legacyKeyRemover,
  }) : _target = target,
       _logger = logger,
       _legacyKeyRemover = legacyKeyRemover ?? _removeFromPreferences;

  final JsonFileRecentProjectsStore _target;
  final Logger _logger;
  final Future<void> Function(String key) _legacyKeyRemover;

  Future<void>? _migration;

  static Future<void> _removeFromPreferences(String key) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(key);
  }

  @override
  Future<List<RecentProject>> load() async {
    await (_migration ??= _migrate());
    return _target.load();
  }

  @override
  Future<void> record(String path) async {
    await (_migration ??= _migrate());
    await _target.record(path);
  }

  Future<void> _migrate() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_legacyKey);
      if (raw == null || raw.isEmpty) return;

      final List<RecentProject> legacy;
      try {
        legacy = _parse(raw);
      } on Object {
        // Значение не разберёт и следующий запуск: ключ удаляется, иначе
        // предупреждение повторялось бы каждый раз (D4 п. 3).
        _logger.warning('recent_projects.legacy_unreadable');
        await _legacyKeyRemover(_legacyKey);
        return;
      }

      await _target.merge(legacy);
      await _legacyKeyRemover(_legacyKey);
      _logger.info(
        'recent_projects.migrated',
        context: {'count': legacy.length},
      );
    } on Object catch (error) {
      // Только класс ошибки: текст `FormatException` содержит путь (D11).
      _logger.warning(
        'recent_projects.migration_failed',
        context: {'error_class': error.runtimeType.toString()},
      );
    }
  }

  static List<RecentProject> _parse(String raw) {
    final decoded = jsonDecode(raw) as List<Object?>;
    final projects = [
      for (final entry in decoded)
        RecentProject.fromJson(entry! as Map<String, Object?>),
    ];
    // Пустой путь файл отвергает (`FormatException`): такая запись сделала бы
    // `recent_projects.json` нечитаемым, а потеря значения безопасна (D4 п. 3).
    if (projects.any((project) => project.path.isEmpty)) {
      throw const FormatException('empty project path');
    }
    return projects;
  }
}

/// Список недавних проектов недоступен: `CODELAB_HOME` недопустим.
///
/// Почему: без дома нет файла `recent_projects.json`, а молча писать в другое
/// место нельзя (change `share-recent-projects-store`, D8).
///
/// Для чего: типизированная ошибка (`error-handling.md`) для `load` и
/// `record` у [UnavailableRecentProjectsStore]; `SettingsCubit` ловит её и
/// выводит в диагностику, список остаётся пустым.
///
/// Как использовать: бросается только хранилищем-заглушкой; [reason] —
/// причина от `ConnectionEnvironment.homeProblem`, текст без перевода.
final class RecentProjectsUnavailableException implements Exception {
  const RecentProjectsUnavailableException(this.reason);

  final String reason;

  @override
  String toString() => 'RecentProjectsUnavailableException: $reason';
}

/// Хранилище недавних проектов при недопустимом `CODELAB_HOME`.
///
/// Почему: composition root не должен падать из-за окружения; как и
/// `UnavailableProfileStore`, заглушка отдаёт ошибку на каждой операции и не
/// создаёт файлов и каталогов (D8). Ключ `shared_preferences` не трогается.
///
/// Для чего: старт, выбор проекта и восстановление сессии продолжаются, а
/// причина видна в диагностике app.
///
/// Как использовать: привязывается в `CodeLabPlatformModule`, когда
/// `ConnectionEnvironment.codelabHome == null`.
///
/// Лежит в файле переноса по D8: после удаления переноса (change
/// `remove-recent-projects-migration`) заглушка остаётся в этом файле.
final class UnavailableRecentProjectsStore implements RecentProjectsStore {
  const UnavailableRecentProjectsStore(this.reason);

  final String reason;

  @override
  Future<List<RecentProject>> load() =>
      Future.error(RecentProjectsUnavailableException(reason));

  @override
  Future<void> record(String path) =>
      Future.error(RecentProjectsUnavailableException(reason));
}
