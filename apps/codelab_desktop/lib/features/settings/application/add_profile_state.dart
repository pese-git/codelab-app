import 'package:codelab_client_core/codelab_client_core.dart'
    show
        EnvToken,
        NewSecretToken,
        NoToken,
        ProfileDraft,
        ProfileDraftField,
        ProfileKind,
        StoredSecretToken;

/// Вариант токена WebSocket-профиля, как его выбирает пользователь (D14).
///
/// Почему отдельный enum, а не `ProfileTokenChoice` kit: у каждого варианта
/// форма показывает своё поле и подсказку, а `KeepTokenRef` в диалоге
/// создания не встречается. Порядок значений — порядок радиокнопок.
enum AddProfileTokenKind { none, stored, newToken, env }

/// Всё, что форма «Add connection profile» показывает и редактирует.
///
/// Почему отдельное значение, а не поля каждого состояния: Editing,
/// ConfirmingPlaintext, Saving и SaveFailed рисуют одну и ту же форму, и
/// виджет не должен собирать её из разных наборов полей (design.md change
/// `add-app-settings-shell`, D12; проверки подключения в форме нет —
/// `remove-test-connection`, D1).
///
/// Для чего: хранит черновик ([draft], правила — `ProfileDraft` kit) и то,
/// что вычислил Cubit: тексты ошибок и подсказок ([errors], [warning],
/// [tokenNotice]) и доступность «Save» ([canSave]). Виджет только показывает
/// их и не решает, что допустимо (AGENTS.md §7, §10).
///
/// Как использовать: создаёт только `AddProfileCubit`. Значение нового токена
/// лежит в черновике только как `SecretText` (`NewSecretToken`): его
/// `toString()` и `toString()` формы — `***` и без значения (D13).
final class AddProfileForm {
  const AddProfileForm({
    required this.draft,
    required this.kinds,
    required this.useByDefault,
    required this.idEdited,
    required this.tokenEnvName,
    required this.secretNames,
    required this.storedSecretsHint,
    required this.newTokenAvailable,
    required this.newTokenHint,
    required this.touched,
    required this.errors,
    required this.warning,
    required this.tokenNotice,
    required this.canSave,
  });

  final ProfileDraft draft;

  /// Типы, которые хост умеет открывать (`profileKindsFor`, SETUP-22). Если
  /// тип один, переключателя нет.
  final List<ProfileKind> kinds;

  /// Флажок «Use by default» (по умолчанию выключен).
  final bool useByDefault;

  /// Пользователь правил id сам: тогда он не следует за именем.
  final bool idEdited;

  /// Имя переменной токена, которое помнится при переключении «No token» ↔
  /// «From environment variable».
  final String tokenEnvName;

  /// Имена хранилища секретов для «Use stored secret» (`ProfileSecrets.names`).
  final List<String> secretNames;

  /// Почему «Use stored secret» недоступен (`No stored secrets in <backend>.`);
  /// `null` — вариант доступен.
  final String? storedSecretsHint;

  /// «Store a new token» доступен: бэкенд принимает запись.
  final bool newTokenAvailable;

  /// Подсказка под «Store a new token»: куда сохранится значение или почему
  /// вариант недоступен (D3, D14).
  final String newTokenHint;

  /// Вариант токена, выбранный в черновике.
  AddProfileTokenKind get tokenKind => switch (draft.token) {
    EnvToken() => AddProfileTokenKind.env,
    StoredSecretToken() => AddProfileTokenKind.stored,
    NewSecretToken() => AddProfileTokenKind.newToken,
    NoToken() || _ => AddProfileTokenKind.none,
  };

  /// Выбранное имя «Use stored secret»; `null`, если выбран другой вариант.
  String? get storedSecretName => switch (draft.token) {
    StoredSecretToken(:final name) => name,
    _ => null,
  };

  /// Поля, которых пользователь касался (ввод, потеря фокуса, «Save»):
  /// ошибка поля видна только для них. Форма не должна открываться красной и
  /// краснеть после смены типа, но [canSave] решает `validate` независимо от
  /// этого множества.
  final Set<ProfileDraftField> touched;

  /// Первая ошибка каждого поля; пусто, пока нет правок (`touched`).
  final Map<ProfileDraftField, String> errors;

  /// Подсказка `ws://` к другой машине под URL: про токен, если он выбран,
  /// иначе про трафик; не блокирует сохранение (D11, D20).
  final String? warning;

  /// текст «NAME is not set in CodeLab's environment.» — переменная токена не
  /// задана; сохранение остаётся доступным (spec, сценарий «Переменная не
  /// задана»).
  final String? tokenNotice;

  /// «Save» доступна: у черновика нет блокирующих ошибок.
  final bool canSave;

  // Значения токена и env здесь быть не должно, но на всякий случай
  // `toString` не печатает черновик: в нём ввод пользователя.
  @override
  String toString() => 'AddProfileForm(${draft.kind.name})';
}

/// Состояние диалога «Add connection profile» — явный автомат (D12;
/// `state-management.md` §13): невозможные сочетания вроде «ждём подтверждения
/// `ws://` и идёт сохранение» не представимы.
sealed class AddProfileState {
  const AddProfileState();
}

/// Хранилище секретов открывается, формы ещё нет.
///
/// Почему отдельное состояние: хранилище переоткрывается при каждом показе
/// диалога (ревью итерации 1), и до ответа нельзя ни показывать варианты
/// токена, ни принимать ввод. Явное состояние вместо набора флагов.
/// Диалог рисует его индикатором загрузки.
final class OpeningSecrets extends AddProfileState {
  const OpeningSecrets();
}

/// Состояния, в которых диалог показывает форму.
sealed class AddProfileInProgress extends AddProfileState {
  const AddProfileInProgress(this.form);

  final AddProfileForm form;

  ProfileDraft get draft => form.draft;
}

/// Форма редактируется.
final class Editing extends AddProfileInProgress {
  const Editing(super.form);
}

/// `ws://` к другой машине: ждём «Save anyway» (SETUP-10).
final class ConfirmingPlaintext extends AddProfileInProgress {
  const ConfirmingPlaintext(super.form, {required this.message});

  /// Текст подтверждения: адрес показан как `scheme://host:port`, без
  /// `userinfo`, пути и query (D17).
  final String message;
}

/// Профиль записывается.
final class Saving extends AddProfileInProgress {
  const Saving(super.form);
}

/// Запись не удалась; черновик сохранён, можно повторить.
final class SaveFailed extends AddProfileInProgress {
  const SaveFailed(super.form, {required this.message});

  /// Общий текст без `toString()` исключения (D17).
  final String message;
}

/// Id профиля, записанного за жизнь диалога.
///
/// Почему: «Add another» даёт несколько записей за одно открытие, а закрытие
/// диалога («Cancel», Esc) не оставляет `Saved` в состоянии; страница
/// «Connection» по списку перечитывает `profiles.json` и показывает каждый
/// (`remove-test-connection`, D1: исхода проверки больше нет, остался только
/// id).
typedef SavedProfile = ({String profileId});

/// Профиль записан; диалог показывает экран «Profile saved».
final class Saved extends AddProfileState {
  const Saved({
    required this.profileId,
    required this.label,
    required this.useByDefault,
  });

  final String profileId;

  /// Имя для экрана «Profile saved».
  final String label;

  /// Профиль стал профилем по умолчанию.
  final bool useByDefault;
}
