import 'package:codelab_client_core/codelab_client_core.dart';

/// Хранилище секретов, которое можно переоткрыть без перезапуска CodeLab.
///
/// Почему: пользователь правит `secrets.backend` в `config.yaml` в редакторе
/// (app этот ключ не пишет, design.md change `add-provider-setup-ui`, D3), и
/// выбранный при запуске бэкенд устаревает. По решению пользователя
/// (ревью итерации 1) хранилище открывается заново при каждом открытии
/// диалога «Add connection profile» и страницы «Connection»; тот же шов
/// понадобится странице Providers.
///
/// Для чего: [reopen] открывает хранилище фабрикой composition root и делает
/// результат текущим; сам объект — [ProfileSecrets], который делегирует
/// текущему экземпляру. Поэтому `ProfileSecretSource(stored: …)`, которым
/// читается токен при подключении и проверке, всегда видит актуальный бэкенд.
/// Cubit-ы получают из [reopen] свой экземпляр и держат его, пока открыты.
///
/// Как использовать: создаёт только `app_scope.dart`; [open] — фабрика
/// (`openProfileSecrets` в `main`); без неё [reopen] возвращает [initial] (шов
/// тестов). Параллельные [reopen] нумеруются: текущим становится только
/// результат самого свежего вызова, поздний результат устаревшего вызова
/// отбрасывается (AGENTS.md §9, §12), хотя вызвавший получает свой экземпляр.
/// Фабрика не должна бросать исключений; если бросила, остаётся прежнее
/// хранилище.
final class ReopenableProfileSecrets implements ProfileSecrets {
  ReopenableProfileSecrets({
    required ProfileSecrets initial,
    Future<ProfileSecrets> Function()? open,
    void Function(ProfileSecrets opened)? onOpened,
  }) : _current = initial,
       _open = open,
       _onOpened = onOpened {
    onOpened?.call(initial);
  }

  final Future<ProfileSecrets> Function()? _open;
  final void Function(ProfileSecrets opened)? _onOpened;
  ProfileSecrets _current;

  /// Номер последнего начатого [reopen].
  var _generation = 0;

  /// Переоткрывает хранилище и возвращает свежий экземпляр.
  Future<ProfileSecrets> reopen() async {
    final open = _open;
    if (open == null) {
      return _current;
    }
    final generation = ++_generation;
    final ProfileSecrets opened;
    try {
      opened = await open();
    } on Object {
      return _current;
    }
    if (generation == _generation) {
      _current = opened;
      _onOpened?.call(opened);
    }
    return opened;
  }

  @override
  ProfileSecretBackend get backend => _current.backend;

  @override
  Future<List<String>> names() => _current.names();

  @override
  Future<bool> isSet(String name) => _current.isSet(name);

  @override
  Future<String?> read(String name) => _current.read(name);

  @override
  Future<ProfileSecretWrite> store(String name, SecretText value) =>
      _current.store(name, value);

  @override
  Future<ProfileSecretDelete> delete(String name) => _current.delete(name);
}
