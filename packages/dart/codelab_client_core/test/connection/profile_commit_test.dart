// Запись и удаление профиля с токеном в хранилище секретов (task 1.3
// change `add-provider-setup-ui`; spec acp-client-kit «Запись профиля с
// новым токеном»; design.md, D13; SETUP-19, SETUP-24). Двойники пишут
// общий журнал вызовов — порядок проверяется без таймеров.

import 'package:codelab_client_core/codelab_client_core.dart';
import 'package:test/test.dart';

import '../support/profile_fakes.dart';

const _leak = 'sk-test-leak-0123456789';
const _ownName = 'codelab/profiles/devbox/token';

ProfileDraft _draft({
  String id = 'devbox',
  ProfileTokenChoice token = const NewSecretToken(SecretText(_leak)),
}) => ProfileDraft(
  kind: ProfileKind.webSocket,
  id: id,
  label: 'Devbox',
  url: 'wss://devbox:7420',
  token: token,
);

WebSocketProfile _ws(String id, String? tokenRef) => WebSocketProfile(
  id: id,
  label: id,
  uri: Uri.parse('wss://$id:7420'),
  tokenRef: tokenRef,
);

void main() {
  late CallLog log;
  late FakeProfileStore store;
  late FakeProfileSecrets secrets;
  late ProfileCommitter committer;

  setUp(() {
    log = CallLog();
    store = FakeProfileStore(log: log);
    secrets = FakeProfileSecrets(log: log);
    committer = ProfileCommitter(store: store, secrets: secrets);
  });

  group('save', () {
    test('a new token: the secret is stored before the profile and the '
        'profile refers to it', () async {
      final result = await committer.save(_draft());

      expect(result, isA<ProfileSaved>());
      final saved = (result as ProfileSaved).profile as WebSocketProfile;
      expect(saved.tokenRef, 'secret:$_ownName');
      expect(log.entries.where((e) => e != 'profile.load'), [
        'secret.store:$_ownName',
        'profile.save:devbox',
      ]);
      expect(secrets.values[_ownName], _leak);
      expect(store.profiles.single.toString(), isNot(contains(_leak)));
    });

    test('the ids are re-read before the secret is written; a taken id '
        'gives idTaken and writes nothing', () async {
      // Между проверкой формы и записью другой процесс занял id.
      store.appearOnNextLoad = [_ws('devbox', null)];

      final result = await committer.save(_draft());

      expect(result, isA<ProfileRejected>());
      expect(
        (result as ProfileRejected).issues.map((i) => i.code),
        contains(ProfileDraftIssueCode.idTaken),
      );
      expect(log.entries, ['profile.load']);
      expect(secrets.values, isEmpty);
    });

    test('the id is checked again right before the profile write: a profile '
        'that appeared meanwhile is idTaken and the created secret is '
        'rolled back', () async {
      // Между записью секрета и записью профиля (например `codelab profiles
      // add` в другом процессе) id занят.
      store.appearOnSecondLoad = [_ws('devbox', null)];

      final result = await committer.save(_draft());

      expect(result, isA<ProfileRejected>());
      expect(
        (result as ProfileRejected).issues.map((i) => i.code),
        contains(ProfileDraftIssueCode.idTaken),
      );
      expect(log.entries.where((e) => e != 'profile.load'), [
        'secret.store:$_ownName',
        'secret.delete:$_ownName',
      ]);
      expect(secrets.values, isEmpty);
      expect(store.profiles.single.toString(), isNot(contains(_leak)));
      // Чужой профиль не перезаписан.
      expect((store.profiles.single as WebSocketProfile).tokenRef, isNull);
    });

    test(
      'a failed rollback after the id race reports the orphaned secret',
      () async {
        store.appearOnSecondLoad = [_ws('devbox', null)];
        secrets.nextDelete = const Failed('locked');

        final result = await committer.save(_draft());

        expect(result, isA<ProfileSaveFailed>());
        expect((result as ProfileSaveFailed).orphanedSecret, _ownName);
      },
    );

    test('ProfileSaveFailed carries only the type name of the store '
        'exception', () async {
      store.failSave = StateError('disk full, Bearer $_leak');

      final failed = await committer.save(_draft()) as ProfileSaveFailed;

      expect(failed.errorType, 'StateError');
      expect(failed.toString(), isNot(contains(_leak)));
    });

    test('the secret write is rolled back when the profile write fails; '
        'profiles stay unchanged', () async {
      store.failSave = StateError('disk full, Bearer $_leak');

      final result = await committer.save(_draft());

      expect(result, isA<ProfileSaveFailed>());
      final failed = result as ProfileSaveFailed;
      expect(failed.reason, ProfileSaveFailedReason.profileWrite);
      expect(failed.orphanedSecret, isNull);
      expect(failed.message, isNot(contains(_leak)));
      expect(log.entries.where((e) => e != 'profile.load'), [
        'secret.store:$_ownName',
        'profile.save:devbox',
        'secret.delete:$_ownName',
      ]);
      expect(secrets.values, isEmpty);
      expect(store.profiles, isEmpty);
    });

    test(
      'a failed rollback is reported with the orphaned secret name',
      () async {
        store.failSave = StateError('disk full');
        secrets.nextDelete = const Failed('locked');

        final result = await committer.save(_draft()) as ProfileSaveFailed;

        expect(result.orphanedSecret, _ownName);
        expect(result.message, isNot(contains(_leak)));
      },
    );

    test('an existing secret gives tokenSecretExists without writing the '
        'profile or touching the value', () async {
      secrets.values[_ownName] = 'old';

      final result = await committer.save(_draft());

      expect(result, isA<ProfileRejected>());
      final issues = (result as ProfileRejected).issues;
      expect(issues.single.code, ProfileDraftIssueCode.tokenSecretExists);
      expect(issues.single.field, ProfileDraftField.token);
      expect(secrets.values[_ownName], 'old');
      expect(log.entries.any((e) => e.startsWith('profile.save')), isFalse);
      // Чужой секрет не удаляется и «откатом».
      expect(log.entries.any((e) => e.startsWith('secret.delete')), isFalse);
    });

    test(
      'a read-only or failing backend is ProfileSaveFailed without writing the '
      'profile',
      () async {
        secrets.nextWrite = const ReadOnly('env backend');
        final readOnly = await committer.save(_draft()) as ProfileSaveFailed;
        expect(readOnly.reason, ProfileSaveFailedReason.secretReadOnly);

        secrets.nextWrite = const Failed('boom');
        final failed = await committer.save(_draft()) as ProfileSaveFailed;
        expect(failed.reason, ProfileSaveFailedReason.secretWrite);

        expect(log.entries.any((e) => e.startsWith('profile.save')), isFalse);
        expect(log.entries.any((e) => e.startsWith('secret.delete')), isFalse);
      },
    );

    test('Use stored secret writes only the profile with the chosen '
        'name', () async {
      secrets.values['codelab/ws-ci'] = 'v';

      final result = await committer.save(
        _draft(token: const StoredSecretToken('codelab/ws-ci')),
      );

      final saved = (result as ProfileSaved).profile as WebSocketProfile;
      expect(saved.tokenRef, 'secret:codelab/ws-ci');
      expect(log.entries.where((e) => e != 'profile.load'), [
        'profile.save:devbox',
      ]);
    });

    test('Use stored secret does not delete the chosen secret when the '
        'profile write fails', () async {
      secrets.values['codelab/ws-ci'] = 'v';
      store.failSave = StateError('disk full');

      final result = await committer.save(
        _draft(token: const StoredSecretToken('codelab/ws-ci')),
      );

      expect(result, isA<ProfileSaveFailed>());
      expect(secrets.values['codelab/ws-ci'], 'v');
      expect(log.entries.any((e) => e.startsWith('secret.')), isFalse);
    });

    test('an invalid secret name is rejected as a draft problem', () async {
      final result = await committer.save(
        _draft(token: const StoredSecretToken('Bad Name')),
      );

      expect(
        (result as ProfileRejected).issues.single.code,
        ProfileDraftIssueCode.tokenSecretNameInvalid,
      );
      expect(log.entries.any((e) => e.startsWith('profile.save')), isFalse);
    });

    test('no token, env token: no secret is touched', () async {
      await committer.save(_draft(token: const NoToken()));
      await committer.save(
        _draft(id: 'b', token: const EnvToken('DEVBOX_TOKEN')),
      );

      expect(log.entries.any((e) => e.startsWith('secret.')), isFalse);
      expect(store.profiles.length, 2);
    });
  });

  group('remove', () {
    test('deleteOwnSecret removes the profile first, then its own '
        'secret only', () async {
      secrets.values
        ..[_ownName] = 'v'
        ..['codelab/ws-ci'] = 'w';
      store.profiles.addAll([
        _ws('devbox', 'secret:$_ownName'),
        _ws('ci', 'secret:codelab/ws-ci'),
      ]);

      final removed = await committer.remove('devbox', deleteOwnSecret: true);

      expect(removed, isA<ProfileRemoved>());
      expect((removed as ProfileRemoved).secret, OwnSecretOutcome.deleted);
      expect(log.entries.where((e) => e != 'profile.load'), [
        'profile.remove:devbox',
        'secret.delete:$_ownName',
      ]);

      // Профиль со своим чужим именем секрета: секрет не трогается.
      final other = await committer.remove('ci', deleteOwnSecret: true);
      expect((other as ProfileRemoved).secret, OwnSecretOutcome.notOwned);
      expect(secrets.values['codelab/ws-ci'], 'w');
    });

    test('without deleteOwnSecret the secret stays', () async {
      secrets.values[_ownName] = 'v';
      store.profiles.add(_ws('devbox', 'secret:$_ownName'));

      final removed = await committer.remove('devbox') as ProfileRemoved;

      expect(removed.secret, OwnSecretOutcome.notRequested);
      expect(secrets.values[_ownName], 'v');
    });

    test('a secret referenced by another profile is not deleted', () async {
      secrets.values['codelab/profiles/a/token'] = 'v';
      store.profiles.addAll([
        _ws('a', 'secret:codelab/profiles/a/token'),
        // Правка файла вручную: b ссылается на секрет профиля a.
        _ws('b', 'secret:codelab/profiles/a/token'),
      ]);

      final removed =
          await committer.remove('a', deleteOwnSecret: true) as ProfileRemoved;

      expect(removed.secret, OwnSecretOutcome.shared);
      expect(secrets.values['codelab/profiles/a/token'], 'v');
      expect(store.profiles.map((p) => p.id), ['b']);
    });

    test('a failing secret delete does not bring the profile back and '
        'reports the name', () async {
      secrets.values[_ownName] = 'v';
      store.profiles.add(_ws('devbox', 'secret:$_ownName'));
      secrets.nextDelete = const Failed('locked');

      final removed =
          await committer.remove('devbox', deleteOwnSecret: true)
              as ProfileRemoved;

      expect(removed.secret, OwnSecretOutcome.deleteFailed);
      expect(removed.secretName, _ownName);
      expect(store.profiles, isEmpty);
    });

    test(
      'a failing profile remove never touches the secret (SETUP-24)',
      () async {
        secrets.values[_ownName] = 'v';
        store.profiles.add(_ws('devbox', 'secret:$_ownName'));
        store.failRemove = StateError('read-only file');

        final result = await committer.remove('devbox', deleteOwnSecret: true);

        expect(result, isA<RemoveFailed>());
        expect(secrets.values[_ownName], 'v');
        expect(log.entries.any((e) => e.startsWith('secret.')), isFalse);
      },
    );

    test(
      'RemoveFailed carries only the type name of the store exception',
      () async {
        store.profiles.add(_ws('devbox', null));
        store.failRemove = StateError('read-only file, Bearer $_leak');

        final result = await committer.remove('devbox') as RemoveFailed;

        expect(result.errorType, 'StateError');
        expect(result.message, isNot(contains(_leak)));
      },
    );

    test('a missing profile is ProfileNotFound; a profile with an env '
        'token has no own secret', () async {
      expect(await committer.remove('nope'), isA<ProfileNotFound>());

      store.profiles.add(_ws('envp', 'env:DEVBOX_TOKEN'));
      final removed =
          await committer.remove('envp', deleteOwnSecret: true)
              as ProfileRemoved;
      expect(removed.secret, OwnSecretOutcome.notOwned);
      expect(log.entries.any((e) => e.startsWith('secret.')), isFalse);
    });
  });
}
