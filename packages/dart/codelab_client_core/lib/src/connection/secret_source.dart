/// Источник значений секретов по ссылке.
///
/// Почему: профиль подключения хранится и логируется, поэтому токен в нём —
/// только ссылка; значение живёт там, где его держит хост: в памяти формы
/// app, в переменной окружения CLI, в системном хранилище ключей
/// (design D8, `AGENTS.md` §10).
///
/// Для чего: [TransportResolver] читает значение в момент открытия
/// транспорта и никуда его не сохраняет.
///
/// Как использовать: composition root передаёт реализацию резолверу;
/// `null` — секрета с такой ссылкой нет, подключение идёт без него.
abstract interface class SecretSource {
  Future<String?> read(String ref);
}

/// [SecretSource] в памяти процесса.
///
/// Почему: app держит токен WebSocket в состоянии формы и не сохраняет его
/// на диск; тестам нужен источник без внешнего хранилища.
///
/// Для чего: хост кладёт значение перед подключением, резолвер читает его по
/// ссылке профиля.
///
/// Как использовать: `secrets.write('ws-token', token)` перед `connect`;
/// `write(ref, null)` удаляет значение.
final class InMemorySecretSource implements SecretSource {
  final _values = <String, String>{};

  void write(String ref, String? value) {
    if (value == null) {
      _values.remove(ref);
    } else {
      _values[ref] = value;
    }
  }

  @override
  Future<String?> read(String ref) async => _values[ref];
}
