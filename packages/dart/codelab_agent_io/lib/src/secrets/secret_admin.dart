import 'dart:io';

import 'package:codelab_agent_core/codelab_agent_core.dart';
import 'package:meta/meta.dart';

import 'secret_value_checks.dart';

/// Результат [SecretAdmin.store] и [SecretAdmin.checkStore].
///
/// Почему sealed-иерархия, а не исключения: ошибка пользователя (плохое имя,
/// пустое значение, бэкенд только для чтения) — штатный исход, который
/// страница настроек и `SecretCommands` должны показать текстом; исчерпывающий
/// `switch` не даёт забыть ветку (design.md change `add-agent-secret-store`,
/// D15). Ни один результат не содержит значения секрета, `toString` его не
/// печатает (CFG-10); у всех он единого вида `Класс(поле: значение, …)`.
sealed class SecretWriteOutcome {
  const SecretWriteOutcome();
}

/// Результат [SecretAdmin.delete]; делит с [SecretWriteOutcome] ветки
/// [SecretInvalidName], [SecretReadOnly] и [SecretFailed].
sealed class SecretDeleteOutcome {
  const SecretDeleteOutcome();
}

/// Результат [SecretAdmin.list].
sealed class SecretListOutcome {
  const SecretListOutcome();
}

/// Секрет сохранён впервые.
@immutable
final class SecretStored extends SecretWriteOutcome {
  const SecretStored(this.name, this.backend);

  final String name;

  /// `SecretBackendInfo.id` бэкенда.
  final String backend;

  @override
  String toString() => 'SecretStored(name: $name, backend: $backend)';
}

/// Секрет уже был в хранилище и перезаписан без вопроса (OQ5, решение
/// 2026-10-31).
@immutable
final class SecretUpdated extends SecretWriteOutcome {
  const SecretUpdated(this.name, this.backend);

  final String name;
  final String backend;

  @override
  String toString() => 'SecretUpdated(name: $name, backend: $backend)';
}

/// Имя не прошло `SecretNames`.
@immutable
final class SecretInvalidName
    implements SecretWriteOutcome, SecretDeleteOutcome {
  const SecretInvalidName(this.reason);

  /// Английская причина `SecretNames.problem` — без самого имени.
  final String reason;

  @override
  String toString() => 'SecretInvalidName(reason: $reason)';
}

/// Значение пустое, многострочное, длиннее 64 КиБ или не воспроизводится
/// при записи (непарный суррогат).
@immutable
final class SecretInvalidValue extends SecretWriteOutcome {
  const SecretInvalidValue(this.reason);

  final String reason;

  @override
  String toString() => 'SecretInvalidValue(reason: $reason)';
}

/// `SecretNames.envOverride(name)` совпадает с переменной другого имени
/// хранилища (D2, D8).
@immutable
final class SecretCollision extends SecretWriteOutcome {
  const SecretCollision({
    required this.name,
    required this.other,
    required this.variable,
  });

  final String name;
  final String other;
  final String variable;

  @override
  String toString() =>
      'SecretCollision(name: $name, other: $other, variable: $variable)';
}

/// Бэкенд не допускает записи (`env`).
///
/// Почему структура, а не готовая фраза: текст подсказки — дело `SecretCommands`
/// и страницы настроек (они знают настоящий путь `$CODELAB_HOME` и свой язык);
/// здесь только данные для неё (D8, п. 3).
@immutable
final class SecretReadOnly implements SecretWriteOutcome, SecretDeleteOutcome {
  const SecretReadOnly({
    required this.backend,
    required this.variable,
    required this.fileBackendOffered,
  });

  final String backend;

  /// Имя переменной, которой можно задать секрет
  /// (`SecretNames.envOverride`).
  final String variable;

  /// Можно ли предложить `secrets.backend: file`: `false` на Windows, где
  /// бэкенд `file` недоступен (D7, D14).
  final bool fileBackendOffered;

  @override
  String toString() =>
      'SecretReadOnly(backend: $backend, variable: $variable, '
      'fileBackendOffered: $fileBackendOffered)';
}

/// Хранилище отказало (права `secrets.yaml`, сбой записи).
@immutable
final class SecretFailed implements SecretWriteOutcome, SecretDeleteOutcome {
  const SecretFailed(this.reason);

  /// Причина хранилища; значения в ней нет.
  final String reason;

  @override
  String toString() => 'SecretFailed(reason: $reason)';
}

/// Секрет удалён.
@immutable
final class SecretDeleted extends SecretDeleteOutcome {
  const SecretDeleted(this.name, this.backend);

  final String name;
  final String backend;

  @override
  String toString() => 'SecretDeleted(name: $name, backend: $backend)';
}

/// Секрета не было: удаление идемпотентно (D8).
@immutable
final class SecretNotSet extends SecretDeleteOutcome {
  const SecretNotSet(this.name, this.backend);

  final String name;
  final String backend;

  @override
  String toString() => 'SecretNotSet(name: $name, backend: $backend)';
}

/// Содержимое хранилища: бэкенд, имена и имена переменных переопределения.
@immutable
final class SecretListing extends SecretListOutcome {
  const SecretListing({
    required this.backend,
    required this.names,
    required this.overrides,
  });

  final SecretBackendInfo backend;

  /// Имена по алфавиту (у `file` — ключи `secrets.yaml`, у `env` — пусто, D6).
  final List<String> names;

  /// Имена (не значения!) заданных переменных `CODELAB_SECRET_*` по алфавиту.
  final List<String> overrides;

  @override
  String toString() =>
      'SecretListing(backend: ${backend.id}, names: $names, '
      'overrides: $overrides)';
}

/// Хранилище недоступно для перечисления.
@immutable
final class SecretListFailed extends SecretListOutcome {
  const SecretListFailed(this.reason);

  final String reason;

  @override
  String toString() => 'SecretListFailed(reason: $reason)';
}

/// Программный путь `store`/`delete`/`list` для страницы настроек и
/// `SecretCommands` (design.md change `add-agent-secret-store`, D15;
/// agent-secrets «Программная запись секретов»).
///
/// Почему отдельный класс: проверки (имя, значение, коллизия переменной,
/// бэкенд только для чтения) и тексты причин должны совпадать у CLI и у
/// страницы настроек; `SecretCommands` только форматирует результаты.
///
/// Для чего: значение живёт в памяти процесса и уходит прямо в
/// `SecretStore.write` — не в argv, stdin, лог или журнал.
///
/// Как использовать: `SecretAdmin(store: openSecretStore(…), environment:
/// Platform.environment)`. Порядок проверок `store`: имя, бэкенд только для
/// чтения, значение (дешёвые проверки без обращения к хранилищу), коллизия,
/// запись; [checkStore] выполняет проверки имени, бэкенда и коллизии без
/// значения, чтобы CLI не просил ввод секрета, который всё равно отвергнут; исключения хранилища превращаются в [SecretFailed] (в причину идёт
/// только наш текст или тип ошибки). Запись не сбрасывает кэш резолвера в том
/// же процессе (D15, ограничение до 8.10).
final class SecretAdmin {
  SecretAdmin({
    required DescribedSecretStore store,
    required Map<String, String> environment,
    String? platform,
  }) : _store = store,
       _environment = environment,
       _platform = platform ?? Platform.operatingSystem;

  final DescribedSecretStore _store;
  final Map<String, String> _environment;
  final String _platform;

  /// Проверки, не требующие значения: имя, бэкенд только для чтения, коллизия
  /// переменной. `null` — имя можно сохранять.
  ///
  /// Почему отдельно: `secret set` читает значение из tty или stdin, и
  /// пользователь не должен вводить ключ, чтобы узнать, что бэкенд только для
  /// чтения. Хранилище при этом только читается (`names()`), не меняется.
  Future<SecretWriteOutcome?> checkStore(String name) async =>
      (await _inspect(name)).outcome;

  /// Сохраняет [value] под [name].
  Future<SecretWriteOutcome> store(String name, String value) async {
    // Дешёвые проверки имени и бэкенда идут раньше проверки значения, а
    // обращение к хранилищу (коллизия) — после неё.
    final early = _cheapChecks(name);
    if (early != null) {
      return early;
    }
    if (value.isEmpty) {
      return const SecretInvalidValue('empty secret value');
    }
    if (secretValueProblem(value) case final problem?) {
      return SecretInvalidValue(problem);
    }
    final inspected = await _inspect(name);
    if (inspected.outcome != null) {
      return inspected.outcome!;
    }
    final backend = _store.backend.id;
    try {
      await _store.write(name, value);
      return inspected.existing.contains(name)
          ? SecretUpdated(name, backend)
          : SecretStored(name, backend);
    } on SecretStoreUnavailableException catch (error) {
      return SecretFailed(error.reason);
    } on Object catch (error) {
      return SecretFailed(_typeOnly(error));
    }
  }

  SecretWriteOutcome? _cheapChecks(String name) {
    if (SecretNames.problem(name) case final problem?) {
      return SecretInvalidName(problem);
    }
    if (!_store.backend.writable) {
      return _readOnly(name);
    }
    return null;
  }

  /// Общая часть [checkStore] и [store]: дешёвые проверки и коллизия;
  /// [existing] нужен [store], чтобы отличить [SecretUpdated] от [SecretStored].
  ///
  /// Окно гонки: проверка коллизии и запись не атомарны относительно другого
  /// процесса или другого `SecretAdmin` (порт `SecretStore` общей очереди не
  /// даёт); последствие — два имени одной переменной, о чём резолвер скажет
  /// при чтении.
  Future<({SecretWriteOutcome? outcome, List<String> existing})> _inspect(
    String name,
  ) async {
    final early = _cheapChecks(name);
    if (early != null) {
      return (outcome: early, existing: const <String>[]);
    }
    try {
      final existing = await _store.names();
      final variable = SecretNames.envOverride(name);
      for (final other in existing) {
        if (other != name && SecretNames.envOverride(other) == variable) {
          return (
            outcome: SecretCollision(
              name: name,
              other: other,
              variable: variable,
            ),
            existing: existing,
          );
        }
      }
      return (outcome: null, existing: existing);
    } on SecretStoreUnavailableException catch (error) {
      return (outcome: SecretFailed(error.reason), existing: const <String>[]);
    } on Object catch (error) {
      return (
        outcome: SecretFailed(_typeOnly(error)),
        existing: const <String>[],
      );
    }
  }

  /// Удаляет [name]; отсутствующее имя — [SecretNotSet], не ошибка.
  Future<SecretDeleteOutcome> delete(String name) async {
    if (SecretNames.problem(name) case final problem?) {
      return SecretInvalidName(problem);
    }
    if (!_store.backend.writable) {
      return _readOnly(name);
    }
    final backend = _store.backend.id;
    try {
      final existing = await _store.names();
      if (!existing.contains(name)) {
        return SecretNotSet(name, backend);
      }
      await _store.delete(name);
      return SecretDeleted(name, backend);
    } on SecretStoreUnavailableException catch (error) {
      return SecretFailed(error.reason);
    } on Object catch (error) {
      return SecretFailed(_typeOnly(error));
    }
  }

  /// Бэкенд, имена и имена переменных переопределения (значения не читаются).
  Future<SecretListOutcome> list() async {
    try {
      final names = (await _store.names()).toList()..sort();
      final overrides = [
        for (final entry in _environment.entries)
          if (entry.key.startsWith(_overridePrefix) &&
              entry.key.length > _overridePrefix.length &&
              entry.value.isNotEmpty)
            entry.key,
      ]..sort();
      return SecretListing(
        backend: _store.backend,
        names: names,
        overrides: overrides,
      );
    } on SecretStoreUnavailableException catch (error) {
      return SecretListFailed(error.reason);
    } on Object catch (error) {
      return SecretListFailed(_typeOnly(error));
    }
  }

  static const _overridePrefix = 'CODELAB_SECRET_';

  /// Данные для подсказки D8, п. 3; на Windows `file` не предлагается (D7,
  /// D14).
  SecretReadOnly _readOnly(String name) => SecretReadOnly(
    backend: _store.backend.id,
    variable: SecretNames.envOverride(name),
    fileBackendOffered: _platform != 'windows',
  );

  // Чужая реализация порта: текст исключения мог бы цитировать значение.
  String _typeOnly(Object error) => 'secret store failed: ${error.runtimeType}';
}
