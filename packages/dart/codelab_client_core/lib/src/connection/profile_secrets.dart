import 'package:meta/meta.dart';

/// Правило имени секрета хранилища агента: `^[a-z0-9][a-z0-9._/-]{0,127}$`,
/// без `..`, пустых сегментов и завершающего `/`.
///
/// Почему копия правила `SecretNames` агента: kit не зависит от пакетов
/// агента (design.md change `add-provider-setup-ui`, D13), а ссылка
/// `secret:<имя>` в профиле должна читаться ровно тогда, когда такое имя
/// принимает хранилище. Правило kit не мягче правила агента (пустые сегменты
/// `a//b` kit отвергает дополнительно, spec acp-client-kit «Ссылка на токен
/// профиля»).
///
/// Как использовать: проверка до обращения к порту [ProfileSecrets]; сам
/// порт имя повторно проверяет своим правилом.
bool isValidSecretName(String name) =>
    _secretName.hasMatch(name) &&
    !name.contains('..') &&
    !name.contains('//') &&
    !name.endsWith('/');

final _secretName = RegExp(r'^[a-z0-9][a-z0-9._/-]{0,127}$');

/// Имя секрета, который создаёт «Store a new token» для профиля [profileId]:
/// `codelab/profiles/<id>/token` (design.md change `add-provider-setup-ui`,
/// D13).
///
/// Почему имя выводится из id, а не вводится: так секрет «принадлежит»
/// профилю, и `ProfileCommitter.remove` вправе удалить именно его, не задевая
/// секреты, выбранные через «Use stored secret».
String ownTokenSecretName(String profileId) =>
    'codelab/profiles/$profileId/token';

/// Секреты хранилища, которые «Use stored secret» предлагает как токен
/// профиля: только `codelab/profiles/*` и только имена, которые принимает kit
/// ([isValidSecretName]), по алфавиту.
///
/// Почему фильтр: в хранилище лежат и ключи провайдеров (`codelab/<id>`), и
/// секреты MCP-серверов — выбрать их токеном WebSocket-профиля почти всегда
/// ошибка, а профиль со ссылкой на чужой секрет при «Remove» только запутал
/// бы пользователя (решение пользователя по ревью итерации 1 change
/// `add-provider-setup-ui`, D14).
///
/// Для чего: список ComboBox формы app; порядок — по алфавиту и без повторов
/// (выбор для ComboBox). Фильтр касается только
/// выбора в UI: ручная ссылка `secret:<любое допустимое имя>` в
/// `profiles.json` по-прежнему читается ([ProfileTokenRef.parse]).
List<String> selectableProfileTokenSecrets(Iterable<String> names) {
  const prefix = 'codelab/profiles/';
  final selectable = <String>{
    for (final name in names)
      if (name.startsWith(prefix) &&
          name.length > prefix.length &&
          isValidSecretName(name))
        name,
  };
  return selectable.toList()..sort();
}

/// Значение нового токена в памяти формы: никогда не печатается.
///
/// Почему отдельный тип: токен живёт в черновике профиля между вводом и
/// записью, а `toString` черновика, состояния Cubit и текст исключения
/// попадают в журналы и сообщения тестов. `SecretText` делает утечку по
/// недосмотру невозможной: и `toString()`, и JSON — `***`. Отдельный от
/// `SecretValue` моста настроек тип нужен, потому что kit не зависит от
/// стороны агента (design.md change `add-provider-setup-ui`, D13).
///
/// Для чего: вход [ProfileSecrets.store].
///
/// Как использовать: `SecretText(поле.value)`; значение читает только
/// [reveal] — вызывать его допустимо лишь в адаптере хранилища.
/// Состояние формы после закрытия обязано
/// забыть экземпляр.
@immutable
final class SecretText {
  const SecretText(this._value);

  final String _value;

  /// Значение. Единственное место, где оно доступно.
  String reveal() => _value;

  bool get isEmpty => _value.isEmpty;

  /// JSON-представление — `***`: значение не уходит ни в профиль, ни в лог.
  String toJson() => '***';

  @override
  bool operator ==(Object other) =>
      other is SecretText && other._value == _value;

  @override
  int get hashCode => _value.hashCode;

  @override
  String toString() => '***';
}

/// Описание бэкенда хранилища секретов для подписей формы.
///
/// Почему: форма «Store a new token» должна сказать, куда уйдёт значение, и
/// отключить вариант, если бэкенд только для чтения (design.md change
/// `add-provider-setup-ui`, D14).
@immutable
final class ProfileSecretBackend {
  const ProfileSecretBackend({
    required this.id,
    required this.writable,
    this.unavailableReason,
  });

  /// Идентификатор бэкенда: `file`, `env`, `keychain`… — для подписей.
  final String id;

  /// `false` — запись невозможна (например бэкенд `env`).
  final bool writable;

  /// Почему запись недоступна; `null`, если доступна.
  final String? unavailableReason;
}

/// Результат [ProfileSecrets.store]. Значения не содержит.
sealed class ProfileSecretWrite {
  const ProfileSecretWrite();
}

/// Результат [ProfileSecrets.delete]. Значения не содержит.
sealed class ProfileSecretDelete {
  const ProfileSecretDelete();
}

/// Секрет записан.
final class Stored extends ProfileSecretWrite {
  const Stored();

  @override
  String toString() => 'Stored()';
}

/// Секрет с таким именем уже есть; значение не изменено (SETUP-5: чужой
/// секрет не перезаписывается без явного «Replace it»).
final class Exists extends ProfileSecretWrite {
  const Exists();

  @override
  String toString() => 'Exists()';
}

/// Секрета с таким именем нет: нечего удалять.
final class NotSet extends ProfileSecretDelete {
  const NotSet();

  @override
  String toString() => 'NotSet()';
}

/// Секрет удалён.
final class Deleted extends ProfileSecretDelete {
  const Deleted();

  @override
  String toString() => 'Deleted()';
}

/// Бэкенд только для чтения: ни запись, ни удаление невозможны.
///
/// Общий для [ProfileSecretWrite] и [ProfileSecretDelete]: смысл один и тот
/// же, а [reason] — подсказка бэкенда для пользователя.
final class ReadOnly implements ProfileSecretWrite, ProfileSecretDelete {
  const ReadOnly([this.reason]);

  final String? reason;

  @override
  String toString() => 'ReadOnly()';
}

/// Операция не удалась. [message] прошёл редактирование секретов и значения
/// не содержит — его можно показать и записать в журнал.
final class Failed implements ProfileSecretWrite, ProfileSecretDelete {
  const Failed(this.message);

  final String message;

  @override
  String toString() => 'Failed($message)';
}

/// Порт хранилища секретов профилей (design.md change
/// `add-provider-setup-ui`, D13).
///
/// Почему порт: токен WebSocket-профиля лежит в хранилище секретов агента
/// (`$CODELAB_HOME`, keychain…), а kit — чистый Dart и стороны агента не
/// знает. Реализацию даёт composition root хоста (`lib/app/` app, `run.dart`
/// CLI) поверх `ClientSecretAccess`.
///
/// Для чего: имена для «Use stored secret» ([names]), признак «set» для
/// строки профиля ([isSet], значение не читается), запись и удаление
/// секрета профиля ([store], [delete]) и чтение значения для транспорта
/// ([read]).
///
/// Как использовать: [read] вызывает только `ProfileSecretSource` в момент
/// открытия транспорта; остальные методы — формы и `ProfileCommitter`.
/// Результаты [store] и [delete] — закрытые иерархии без значений.
abstract interface class ProfileSecrets {
  ProfileSecretBackend get backend;

  Future<List<String>> names();

  Future<bool> isSet(String name);

  /// Записывает [value] под [name]; существующее имя не перезаписывается
  /// ([Exists]).
  Future<ProfileSecretWrite> store(String name, SecretText value);

  Future<ProfileSecretDelete> delete(String name);

  /// Значение секрета или `null`. Без кэша: следующее чтение видит замену.
  Future<String?> read(String name);
}
