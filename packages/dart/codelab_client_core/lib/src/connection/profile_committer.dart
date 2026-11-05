import '../diagnostics/diagnostics.dart';
import '../stores/stores.dart';
import 'connection_profile.dart';
import 'profile_draft.dart';
import 'profile_secrets.dart';

/// Исход [ProfileCommitter.save].
sealed class ProfileCommitResult {
  const ProfileCommitResult();
}

/// Профиль записан (и секрет, если выбран «Store a new token»).
final class ProfileSaved extends ProfileCommitResult {
  const ProfileSaved(this.profile);

  final ConnectionProfile profile;

  @override
  String toString() => 'ProfileSaved(${profile.id})';
}

/// Запись не начата или остановлена проблемой черновика: `idTaken`,
/// `tokenSecretExists` и прочие из [ProfileDraft.validate]. Ничего не
/// изменено.
final class ProfileRejected extends ProfileCommitResult {
  const ProfileRejected(this.issues);

  final List<ProfileDraftIssue> issues;

  @override
  String toString() => 'ProfileRejected(${issues.map((i) => i.code.name)})';
}

/// Причина [ProfileSaveFailed].
enum ProfileSaveFailedReason {
  /// Бэкенд хранилища секретов только для чтения.
  secretReadOnly,

  /// Секрет не записан (сбой бэкенда); профиль не записан.
  secretWrite,

  /// Профиль не записан; созданный секрет откачен (см.
  /// [ProfileSaveFailed.orphanedSecret], если откат не удался).
  profileWrite,
}

/// Запись не удалась. [message] прошёл редактирование секретов.
///
/// [orphanedSecret] — имя секрета, который создан этой операцией, но не
/// удалён при откате: хост показывает «The profile was not saved; the token
/// stays in BACKEND as NAME. Remove it with codelab secret delete NAME.» (с
/// подстановкой бэкенда и имени) и пишет `connection_profile.token_rollback_failed` (D13).
final class ProfileSaveFailed extends ProfileCommitResult {
  const ProfileSaveFailed(
    this.reason,
    this.message, {
    this.orphanedSecret,
    this.errorType,
  });

  final ProfileSaveFailedReason reason;
  final String message;
  final String? orphanedSecret;

  /// `runtimeType` исключения хранилища — фиксированное имя типа без текста
  /// (для журнала хоста: текст мог бы процитировать значение); `null`, если
  /// отказ не исключение.
  final String? errorType;

  @override
  String toString() => 'ProfileSaveFailed(${reason.name})';
}

/// Что стало с собственным секретом профиля при [ProfileCommitter.remove].
enum OwnSecretOutcome {
  /// `deleteOwnSecret: false`.
  notRequested,

  /// Профиль не ссылается на собственный `codelab/profiles/<id>/token`
  /// («Use stored secret», `env:`, без токена): секрет не трогается.
  notOwned,

  /// На тот же секрет ссылается другой профиль файла: секрет остаётся.
  shared,

  /// Секрет удалён.
  deleted,

  /// Секрета уже не было.
  alreadyAbsent,

  /// Удалить не удалось (бэкенд только для чтения или сбой); профиль при
  /// этом уже удалён и не восстанавливается.
  deleteFailed,
}

/// Исход [ProfileCommitter.remove].
sealed class ProfileRemoveResult {
  const ProfileRemoveResult();
}

/// Профиль удалён. [secret] — судьба собственного секрета; [secretName] и
/// [message] заполнены при [OwnSecretOutcome.deleteFailed], чтобы хост
/// показал `codelab secret delete <name>` и записал
/// `connection_profile.token_delete_failed`.
final class ProfileRemoved extends ProfileRemoveResult {
  const ProfileRemoved(this.secret, {this.secretName, this.message});

  final OwnSecretOutcome secret;
  final String? secretName;
  final String? message;

  @override
  String toString() => 'ProfileRemoved(${secret.name})';
}

/// Профиля с таким id нет (уже удалён другим процессом).
final class ProfileNotFound extends ProfileRemoveResult {
  const ProfileNotFound();

  @override
  String toString() => 'ProfileNotFound()';
}

/// Профиль удалить не удалось; секрет не тронут (SETUP-24).
final class RemoveFailed extends ProfileRemoveResult {
  const RemoveFailed(this.message, {this.errorType});

  final String message;

  /// `runtimeType` исключения хранилища без текста сообщения.
  final String? errorType;

  @override
  String toString() => 'RemoveFailed()';
}

/// Запись и удаление профиля вместе с его секретом токена.
///
/// Почему: токен WebSocket-профиля лежит в хранилище секретов, а сам профиль —
/// в `profiles.json`; две записи не атомарны, и порядок обязан исключить
/// профиль со ссылкой на несуществующий секрет и секрет-сироту без ведома
/// пользователя (SETUP-19, SETUP-24; design.md change
/// `add-provider-setup-ui`, D13, таблица D21). Политика живёт в kit, чтобы app
/// и CLI не разошлись.
///
/// Для чего: [save] — «секрет, затем профиль» с откатом созданного секрета;
/// [remove] — «профиль, затем собственный секрет».
///
/// Как использовать: composition root создаёт
/// `ProfileCommitter(store: …, secrets: …)`; Cubit формы вызывает [save] с
/// черновиком и показывает исход, не бросающий исключений. Один вызов — одна
/// запись: параллельные записи хост сериализует состоянием `Saving`.
final class ProfileCommitter {
  ProfileCommitter({
    required ProfileStore store,
    required ProfileSecrets secrets,
  }) : _store = store,
       _secrets = secrets;

  final ProfileStore _store;
  final ProfileSecrets _secrets;

  /// Сохраняет профиль по [draft].
  ///
  /// Порядок (D13):
  /// 1. id перечитываются из хранилища — до записи секрета, потому что между
  ///    проверкой формы и записью id мог занять другой процесс; занятый id —
  ///    [ProfileRejected] с `idTaken`;
  /// 2. для [NewSecretToken] — `store` секрета `codelab/profiles/<id>/token`;
  ///    `Exists` — `tokenSecretExists` без перезаписи и без записи профиля;
  ///    `ReadOnly`/`Failed` — [ProfileSaveFailed] без записи профиля;
  /// 3. запись профиля; отказ — удаление секрета, созданного на шаге 2
  ///    (только его: секрет «Use stored secret» не создавался и не
  ///    удаляется).
  Future<ProfileCommitResult> save(ProfileDraft draft) async {
    final List<ConnectionProfile> existing;
    try {
      existing = await _store.load();
    } on Object catch (error) {
      return ProfileSaveFailed(
        ProfileSaveFailedReason.profileWrite,
        describeFailure(error),
        errorType: error.runtimeType.toString(),
      );
    }
    final accepted = draft.toProfile([for (final p in existing) p.id]);
    final ConnectionProfile profile;
    switch (accepted) {
      case DraftRejected(:final issues):
        return ProfileRejected(issues);
      case DraftAccepted(profile: final accepted):
        profile = accepted;
    }

    final token = draft.token;
    String? created;
    if (token is NewSecretToken && profile is WebSocketProfile) {
      final name = ownTokenSecretName(profile.id);
      final ProfileSecretWrite write;
      try {
        write = await _secrets.store(name, token.value);
      } on Object catch (error) {
        return ProfileSaveFailed(
          ProfileSaveFailedReason.secretWrite,
          describeFailure(error),
          errorType: error.runtimeType.toString(),
        );
      }
      switch (write) {
        case Stored():
          created = name;
        case Exists():
          return const ProfileRejected([
            ProfileDraftIssue(
              code: ProfileDraftIssueCode.tokenSecretExists,
              field: ProfileDraftField.token,
              message:
                  'A stored token for this profile already exists. '
                  'Use the stored secret or remove it first.',
            ),
          ]);
        case ReadOnly(:final reason):
          return ProfileSaveFailed(
            ProfileSaveFailedReason.secretReadOnly,
            reason ?? 'The secret store is read-only.',
          );
        case Failed(:final message):
          return ProfileSaveFailed(
            ProfileSaveFailedReason.secretWrite,
            message,
          );
      }
    }

    try {
      // Повторная проверка id непосредственно перед записью: между первым
      // перечитыванием и записью секрета другой процесс (`codelab profiles
      // add`) мог занять id, а `ProfileStore.save` заменяет профиль с тем же
      // id молча. Окно гонки остаётся (load и save не атомарны), но сужено до
      // двух соседних вызовов.
      final latest = await _store.load();
      if (draft.toProfile([for (final p in latest) p.id]) case DraftRejected(
        :final issues,
      )) {
        final orphan = created == null ? null : await _rollback(created);
        return orphan == null
            ? ProfileRejected(issues)
            : ProfileSaveFailed(
                ProfileSaveFailedReason.profileWrite,
                'The profile id was taken meanwhile.',
                orphanedSecret: orphan,
              );
      }
      await _store.save(profile);
    } on Object catch (error) {
      final message = describeFailure(error);
      return ProfileSaveFailed(
        ProfileSaveFailedReason.profileWrite,
        message,
        orphanedSecret: created == null ? null : await _rollback(created),
        errorType: error.runtimeType.toString(),
      );
    }
    return ProfileSaved(profile);
  }

  /// Удаляет секрет [name], созданный этой операцией. Возвращает [name], если
  /// откат не удался (секрет остался в хранилище), иначе `null`.
  Future<String?> _rollback(String name) async {
    try {
      return switch (await _secrets.delete(name)) {
        Deleted() || NotSet() => null,
        ReadOnly() || Failed() => name,
      };
    } on Object catch (_) {
      return name;
    }
  }

  /// Удаляет профиль [id] и, если [deleteOwnSecret], его собственный секрет.
  ///
  /// Порядок (SETUP-24): сначала запись профиля; секрет — только после её
  /// успеха, только если профиль ссылается именно на
  /// `codelab/profiles/<id>/token` и ни один другой профиль файла на это имя
  /// не ссылается. Секрет, выбранный «Use stored secret», не удаляется
  /// никогда. Ошибка удаления секрета профиль не восстанавливает.
  Future<ProfileRemoveResult> remove(
    String id, {
    bool deleteOwnSecret = false,
  }) async {
    final List<ConnectionProfile> before;
    try {
      before = await _store.load();
    } on Object catch (error) {
      return RemoveFailed(
        describeFailure(error),
        errorType: error.runtimeType.toString(),
      );
    }
    final ownName = ownTokenSecretName(id);
    final ownRef = 'secret:$ownName';
    final target = before.where((p) => p.id == id).firstOrNull;
    final ownsSecret = target is WebSocketProfile && target.tokenRef == ownRef;
    final sharedWithOthers = before.any(
      (p) => p.id != id && p is WebSocketProfile && p.tokenRef == ownRef,
    );

    try {
      if (!await _store.remove(id)) {
        return const ProfileNotFound();
      }
    } on Object catch (error) {
      return RemoveFailed(
        describeFailure(error),
        errorType: error.runtimeType.toString(),
      );
    }

    if (!deleteOwnSecret) {
      return const ProfileRemoved(OwnSecretOutcome.notRequested);
    }
    if (!ownsSecret) {
      return const ProfileRemoved(OwnSecretOutcome.notOwned);
    }
    if (sharedWithOthers) {
      return const ProfileRemoved(OwnSecretOutcome.shared);
    }
    try {
      return switch (await _secrets.delete(ownName)) {
        Deleted() => const ProfileRemoved(OwnSecretOutcome.deleted),
        NotSet() => const ProfileRemoved(OwnSecretOutcome.alreadyAbsent),
        ReadOnly(:final reason) => ProfileRemoved(
          OwnSecretOutcome.deleteFailed,
          secretName: ownName,
          message: reason ?? 'The secret store is read-only.',
        ),
        Failed(:final message) => ProfileRemoved(
          OwnSecretOutcome.deleteFailed,
          secretName: ownName,
          message: message,
        ),
      };
    } on Object catch (error) {
      return ProfileRemoved(
        OwnSecretOutcome.deleteFailed,
        secretName: ownName,
        message: describeFailure(error),
      );
    }
  }
}
