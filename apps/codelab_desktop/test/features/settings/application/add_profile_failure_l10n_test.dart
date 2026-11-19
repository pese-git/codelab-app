// Тесты задачи 4.2 change `add-desktop-localization`: отказ записи профиля в
// `AddProfileCubit` хранится типизированно (D5, вид «разовое сообщение»; D6
// «`ProfileSaveFailed.storeReason`»; spec acp-client-kit «Причина хранилища у
// отказа записи профиля», app-settings «Текст хранилища секретов не
// переводится»).
//
// Что проверяется на уровне состояний (экран — в `add_profile_dialog_l10n_test`):
// причина, названная хранилищем, лежит в `SecretStoreReadOnlyFailure.reason`, а
// без причины там `null` и текст даёт app; app не сравнивает `message` с
// запасной строкой ядра. Смена языка не стирает отказ.

import 'package:codelab_client_core/codelab_client_core.dart';
import 'package:codelab_desktop/core/platform/connection_preferences.dart';
import 'package:codelab_desktop/features/settings/application/add_profile_cubit.dart';
import 'package:codelab_desktop/l10n/app_localizations.dart';
import 'package:codelab_desktop/l10n/app_localizations_en.dart';
import 'package:codelab_desktop/l10n/app_localizations_ru.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../support/app_strings.dart';
import '../../../support/fake_profile_secrets.dart';
import '../../../support/in_memory_profile_store.dart';

void main() {
  late FakeProfileSecrets secrets;
  late TestAppStrings strings;

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    secrets = FakeProfileSecrets();
    strings = TestAppStrings(AppLocalizationsEn());
    addTearDown(strings.close);
  });

  Future<AddProfileCubit> failedSave() async {
    final cubit = AddProfileCubit(
      store: InMemoryProfileStore(),
      openSecrets: () async => secrets,
      preferences: const SharedPreferencesConnectionPreferences(),
      kinds: const [ProfileKind.webSocket],
      environment: const {},
      strings: strings,
    );
    addTearDown(cubit.close);
    await cubit.start();
    cubit
      ..setLabel('Box')
      ..setUrl('wss://box:7420')
      ..selectTokenNew()
      ..setNewToken('value');
    await cubit.save();
    return cubit;
  }

  String text(AddProfileCubit cubit, AppLocalizations l10n) =>
      addProfileFailureText(l10n, (cubit.state as SaveFailed).failure);

  test('хранилище назвало причину: она в состоянии и показывается как '
      'есть', () async {
    secrets.nextWrite = const ReadOnly('keychain is read-only.');

    final cubit = await failedSave();

    final failure = (cubit.state as SaveFailed).failure;
    expect(failure, isA<SecretStoreReadOnlyFailure>());
    expect(
      (failure as SecretStoreReadOnlyFailure).reason,
      'keychain is read-only.',
    );
    expect(text(cubit, AppLocalizationsEn()), 'keychain is read-only.');
    expect(text(cubit, AppLocalizationsRu()), 'keychain is read-only.');
  });

  test('хранилище причину не назвало: в состоянии `null`, текст — перевод '
      'app', () async {
    secrets.nextWrite = const ReadOnly();

    final cubit = await failedSave();

    final failure = (cubit.state as SaveFailed).failure;
    expect((failure as SecretStoreReadOnlyFailure).reason, isNull);
    expect(text(cubit, AppLocalizationsEn()), 'The secret store is read-only.');
    expect(
      text(cubit, AppLocalizationsRu()),
      'Хранилище секретов доступно только для чтения.',
    );
  });

  test('хранилище отказало словами запасной строки ядра: это всё равно '
      'причина хранилища, а не «причины нет»', () async {
    // Сравнение `message` со строкой ядра ошиблось бы здесь; тип не ошибается.
    secrets.nextWrite = const ReadOnly('The secret store is read-only.');

    final cubit = await failedSave();

    final failure = (cubit.state as SaveFailed).failure;
    expect(
      (failure as SecretStoreReadOnlyFailure).reason,
      'The secret store is read-only.',
    );
    expect(text(cubit, AppLocalizationsRu()), 'The secret store is read-only.');
  });

  test('отказ записи секрета: тип без текста, значение токена не в '
      'состоянии', () async {
    secrets.nextWrite = const Failed('backend broke: value');

    final cubit = await failedSave();

    expect((cubit.state as SaveFailed).failure, isA<SecretWriteFailed>());
    expect(
      text(cubit, AppLocalizationsRu()),
      'Не удалось сохранить токен. Повторите попытку.',
    );
    expect(cubit.state.toString(), isNot(contains('value')));
  });

  test('смена языка не стирает отказ и не меняет его тип', () async {
    secrets.nextWrite = const ReadOnly('keychain is read-only.');
    final cubit = await failedSave();
    final before = (cubit.state as SaveFailed).failure;

    strings.emit(AppLocalizationsRu());
    await pumpEventQueue();

    expect(cubit.state, isA<SaveFailed>());
    expect(identical((cubit.state as SaveFailed).failure, before), isTrue);
  });
}
