// IO-барель моста настроек разрешён сторожем только в `lib/app/`
// (design.md change `add-provider-setup-ui`, D20): composition root — единственное
// место, которое знает, как открыть хранилище секретов агента.
import 'package:codelab_client_core/codelab_client_core.dart';
import 'package:codelab_client_io/codelab_client_io.dart'
    show CodelabHomeException, resolveCodelabHome;
import 'package:codelab_setup/io.dart' as setup;

import 'connection_environment.dart';

/// Открывает [ProfileSecrets] поверх `ClientSecretAccess` для `CODELAB_HOME`
/// из [environment] (design.md change `add-provider-setup-ui`, D4, D13).
///
/// Почему функция в `lib/app/`: `ClientSecretAccess` читает
/// `$CODELAB_HOME/config.yaml` и файл секретов — это IO, и IO-барель моста
/// `codelab_setup/io.dart` сторож пускает только сюда (D20). Cubit-ы и
/// виджеты получают готовый порт `ProfileSecrets` kit.
///
/// Для чего: единый источник «куда пишется токен профиля» для диалога «Add
/// connection profile», страницы «Connection» и чтения токена при
/// подключении (`ProfileSecretSource(stored:)`). Хранилище открывается заново
/// при каждом открытии диалога и страницы «Connection» через
/// `ReopenableProfileSecrets` (фабрика — эта функция; решение пользователя,
/// D3): правка `secrets.backend` применяется без перезапуска. Первый раз оно
/// открывается в `main` до сборки root scope, потому что
/// `ProfileSecrets.backend` синхронный, а открытие асинхронно.
///
/// Как использовать: `await openProfileSecrets(environment: …, logger: …)`;
/// результат — аргумент `createCodeLabRootScope(profileSecrets:)`.
/// Недопустимый `CODELAB_HOME` не бросает исключения: хранилище доступно
/// только для чтения с причиной. [logger] получает только события самого
/// `ClientSecretAccess` (например, `secrets.client.fallback`): журнал
/// приложения настраивается внутри root scope, позже этого вызова, поэтому
/// событие `secrets.client.backend` (D18) пишет сам scope по `backend`
/// результата.
Future<ProfileSecrets> openProfileSecrets({
  required ConnectionEnvironment environment,
  required setup.Logger logger,
}) async {
  final String home;
  try {
    home = resolveCodelabHome(environment.variables);
  } on CodelabHomeException catch (error) {
    return UnavailableProfileSecrets(error.message);
  }
  final access = await setup.ClientSecretAccess.open(
    codelabHome: home,
    environment: environment.variables,
    logger: logger,
  );
  final info = access.backend;
  // Причина настройки (битый `config.yaml`, недопустимое `secrets.backend`)
  // приходит отдельным полем; обычный `auto → env` его не заполняет, и для
  // него остаётся совет CLI (design.md change `add-provider-setup-ui`, D3).
  final problem = access.configProblem;
  return ClientProfileSecrets._(
    access,
    home,
    ProfileSecretBackend(
      id: info.id,
      writable: info.writable,
      unavailableReason: info.writable
          ? info.unavailableReason
          : problem != null
          ? _sentence(problem)
          : await _readOnlyReason(access, home),
    ),
    problem,
  );
}

/// Подсказка формы «Store a new token» для бэкенда только для чтения.
///
/// Имя секрета профиля в форме ещё не известно (id правится), поэтому вместо
/// настоящей переменной подставляется `<ID>`; точная переменная придёт в
/// `ReadOnly.reason` при записи.
Future<String> _readOnlyReason(
  setup.ClientSecretAccess access,
  String home,
) async {
  final info = access.backend;
  final String hint;
  final probe = await access.admin.checkStore('codelab/profiles/probe/token');
  if (probe case setup.SecretReadOnly()) {
    hint = _sentence(
      setup.secretReadOnlyHint(
        setup.SecretReadOnly(
          backend: probe.backend,
          variable: 'CODELAB_SECRET_CODELAB_PROFILES_<ID>_TOKEN',
          fileBackendOffered: probe.fileBackendOffered,
        ),
        home,
      ),
    );
  } else {
    hint = 'Secret store ${info.id} is read-only.';
  }
  // Причина `unavailableReason` бэкенда («хранилища ОС недоступны…») здесь не
  // добавляется: подсказка CLI уже называет выход, а причину показывает
  // страница Providers (D3).
  return hint;
}

/// Заглавная первая буква и точка в конце: текст CLI строчный и без точки
/// (design.md change `add-provider-setup-ui`, D3).
String _sentence(String text) {
  final capital = text.isEmpty
      ? text
      : '${text[0].toUpperCase()}${text.substring(1)}';
  return capital.endsWith('.') ? capital : '$capital.';
}

/// Хранилище, которое знает причину своей неисправности для журнала.
///
/// Почему: порт kit отдаёт только текст для UI (с путём дома), а событие
/// `secrets.client.backend` пишет `reason` без путей (design.md change
/// `add-provider-setup-ui`, D18). Как использовать: `secrets is
/// DescribedProfileSecrets ? secrets.backendProblem : null`.
abstract interface class DescribedProfileSecrets {
  /// Причина бэкенда без путей и значений; `null` — неисправности нет.
  String? get backendProblem;
}

/// [ProfileSecrets] поверх `ClientSecretAccess`: токены WebSocket-профилей
/// в том же хранилище, что ключи провайдеров и `codelab secret`.
///
/// Почему адаптер: порт kit не знает стороны агента, а `SecretAdmin` отдаёт
/// исходы на языке агента (`SecretStored`, `SecretReadOnly`…). Адаптер
/// переводит их в закрытые иерархии kit без значений.
///
/// Для чего: `store` не перезаписывает существующее имя (`Exists`, SETUP-5),
/// запись и удаление в хранилище только для чтения дают `ReadOnly` с
/// подсказкой CLI, `read` — единственный путь значения к транспорту, без кэша.
///
/// Как использовать: создаёт только [openProfileSecrets]. Значения в
/// `toString`, в тексте результата и в журнал не попадают.
final class ClientProfileSecrets
    implements ProfileSecrets, DescribedProfileSecrets {
  ClientProfileSecrets._(
    this._access,
    this._home,
    this.backend,
    this.backendProblem,
  );

  @override
  final String? backendProblem;

  final setup.ClientSecretAccess _access;
  final String _home;

  @override
  final ProfileSecretBackend backend;

  @override
  Future<List<String>> names() async {
    final listing = await _access.admin.list();
    return switch (listing) {
      setup.SecretListing(:final names) => names,
      setup.SecretListFailed(:final reason) =>
        throw setup.SecretStoreUnavailableException(
          backend: backend.id,
          reason: reason,
        ),
    };
  }

  @override
  Future<bool> isSet(String name) => _access.isSet(name);

  @override
  Future<String?> read(String name) => _access.read(name);

  @override
  Future<ProfileSecretWrite> store(String name, SecretText value) async {
    try {
      // Проверки без значения раньше записи: бэкенд только для чтения и
      // недопустимое имя не должны выглядеть как «секрет уже есть».
      if (await _access.admin.checkStore(name) case final early?) {
        return profileSecretWriteOf(early, _readOnly);
      }
      if (await _access.isSet(name)) {
        return const Exists();
      }
      return profileSecretWriteOf(
        await _access.admin.store(name, value.reveal()),
        _readOnly,
      );
    } on Object catch (error) {
      return Failed(_failureText(error));
    }
  }

  @override
  Future<ProfileSecretDelete> delete(String name) async {
    try {
      return switch (await _access.admin.delete(name)) {
        setup.SecretDeleted() => const Deleted(),
        setup.SecretNotSet() => const NotSet(),
        final setup.SecretReadOnly readOnly => _readOnly(readOnly),
        setup.SecretFailed(:final reason) => Failed(reason),
        setup.SecretInvalidName() => const Failed('Invalid secret name.'),
      };
    } on Object catch (error) {
      return Failed(_failureText(error));
    }
  }

  ReadOnly _readOnly(setup.SecretReadOnly readOnly) => ReadOnly(
    backendProblem != null
        ? backend.unavailableReason
        : _sentence(setup.secretReadOnlyHint(readOnly, _home)),
  );

  // Текст чужого исключения мог бы процитировать значение: только тип.
  static String _failureText(Object error) =>
      'secret store failed: ${error.runtimeType}';

  @override
  String toString() => 'ClientProfileSecrets(backend: ${backend.id})';
}

/// Переводит исход `SecretAdmin.store` в результат порта kit.
///
/// Почему отдельная функция: `SecretUpdated` — не «записано», а «под этим
/// именем уже что-то было и оно перезаписано» (гонка между проверкой
/// `isSet` и записью, другой процесс успел раньше). Чужой секрет перезаписывать
/// нельзя (SETUP-5), поэтому для порта это [Exists]: `ProfileCommitter` не
/// запишет профиль и не будет откатывать (удалять) то, что создал не он.
/// Значение уже записано `SecretAdmin`; вернуть его нельзя, и честный исход —
/// «секрет уже был».
///
/// Как использовать: [readOnly] строит текст отказа для `SecretReadOnly`;
/// отдельная функция нужна ради теста без гонки.
ProfileSecretWrite profileSecretWriteOf(
  setup.SecretWriteOutcome outcome,
  ReadOnly Function(setup.SecretReadOnly readOnly) readOnly,
) => switch (outcome) {
  setup.SecretStored() => const Stored(),
  setup.SecretUpdated() => const Exists(),
  final setup.SecretReadOnly value => readOnly(value),
  setup.SecretFailed(:final reason) => Failed(reason),
  setup.SecretInvalidName() => const Failed('Invalid secret name.'),
  setup.SecretInvalidValue(:final reason) => Failed('Invalid token: $reason.'),
  setup.SecretCollision(:final variable) => Failed(
    'Another stored secret uses the same environment variable $variable.',
  ),
};

/// Хранилище, которое не удалось открыть: только для чтения, с причиной.
///
/// Почему не исключение: недопустимый `CODELAB_HOME` не должен ронять
/// приложение (design.md change `add-app-settings-shell`, D7), а форма «Add
/// connection profile» должна честно сказать, почему «Store a new token» и
/// «Use stored secret» недоступны. Используется также как значение по
/// умолчанию, пока composition root не передал настоящее хранилище.
final class UnavailableProfileSecrets
    implements ProfileSecrets, DescribedProfileSecrets {
  UnavailableProfileSecrets(String reason)
    : backendProblem = reason,
      backend = ProfileSecretBackend(
        id: 'env',
        writable: false,
        unavailableReason: 'Secret store is unavailable: $reason.',
      );

  @override
  final ProfileSecretBackend backend;

  @override
  final String backendProblem;

  @override
  Future<List<String>> names() async => const [];

  @override
  Future<bool> isSet(String name) async => false;

  @override
  Future<String?> read(String name) async => null;

  @override
  Future<ProfileSecretWrite> store(String name, SecretText value) async =>
      ReadOnly(backend.unavailableReason);

  @override
  Future<ProfileSecretDelete> delete(String name) async =>
      ReadOnly(backend.unavailableReason);
}
