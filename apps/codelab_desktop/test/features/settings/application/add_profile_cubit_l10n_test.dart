// Красные тесты задачи 4.1 change `add-desktop-localization`:
// `AddProfileCubit` и язык (spec app-settings «Диалог «Add connection
// profile»», «Локализация интерфейса app», сценарии «Уже показанные ошибки и
// InfoBar пересобираются», «Закрытый компонент не реагирует на смену языка»;
// design.md D5 правила 1–3 и 9, D6 «`ProfileDraftIssue.message` — app
// переводит по коду», D9, D12).
//
// Что проверяется. Тексты формы, которые Cubit выводит из черновика, —
// ошибки полей по `ProfileDraftIssueCode`, подсказки «Use stored secret» и
// «Store a new token», предупреждение `ws://` под URL, заметка «<NAME> is not
// set in CodeLab's environment.» — функция «(черновик, язык)»: смена языка
// пересобирает их из последнего черновика, а сам черновик (ввод пользователя),
// выбранные поля и состояние автомата остаются. Подписка одна, снимается в
// `close()`. Исходы записи (`ProfileCommitter`) — разовые сообщения, их текст
// собирает presentation (`add_profile_dialog_l10n_test.dart`).
//
// Заглушка задачи 4.1: параметр `strings` у `AddProfileCubit` принят и не
// используется, поэтому проверки перевода и подписки красные на `expect`, а
// проверки «прежние строки на en» и «состояние сохраняется» зелёные. Русские
// строки — по глоссарию («токен», «секрет», «хранилище секретов», «окружение»,
// «профиль»); остальные — вне глоссария (отчёт задачи 4.1); сообщения с
// меткой security вычитывает пользователь (задача 4.3, D14).

import 'package:codelab_client_core/codelab_client_core.dart';
import 'package:codelab_desktop/app/language/app_language_cubit.dart'
    show AppStrings;
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

const _both = [ProfileKind.stdio, ProfileKind.webSocket];

const _dev = ConnectionProfile.stdio(
  id: 'dev',
  label: 'Dev',
  command: 'codelab-agent',
);

/// Случай «код проблемы → текст у поля»: как довести форму до проблемы, у
/// какого поля она видна и как выглядит на каждом языке.
typedef _Case = ({
  String name,
  Future<void> Function(AddProfileCubit cubit) drive,
  ProfileDraftField field,
  String en,
  String ru,
});

AddProfileForm _form(AddProfileCubit cubit) =>
    (cubit.state as AddProfileInProgress).form;

void main() {
  late ProfileStore store;
  late FakeProfileSecrets secrets;
  late TestAppStrings strings;

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    store = InMemoryProfileStore([_dev]);
    secrets = FakeProfileSecrets();
    strings = TestAppStrings(AppLocalizationsEn());
    addTearDown(strings.close);
  });

  AddProfileCubit build(
    AppStrings port, {
    Map<String, String> environment = const {},
    List<ProfileKind> kinds = _both,
  }) {
    final cubit = AddProfileCubit(
      store: store,
      openSecrets: () async => secrets,
      preferences: const SharedPreferencesConnectionPreferences(),
      kinds: kinds,
      environment: environment,
      strings: port,
    );
    addTearDown(cubit.close);
    return cubit;
  }

  Future<AddProfileCubit> started(
    AppStrings port, {
    Map<String, String> environment = const {},
  }) async {
    final cubit = build(port, environment: environment);
    await cubit.start();
    return cubit;
  }

  Future<void> switchTo(AppLocalizations next) async {
    strings.emit(next);
    await pumpEventQueue();
  }

  // Ошибки по `ProfileDraftIssueCode` (D6): тексты на en — как в спецификации
  // и в ядре; на ru — глоссарий и список вне глоссария.
  final cases = <_Case>[
    (
      name: 'labelEmpty',
      drive: (c) async => c.setLabel(''),
      field: ProfileDraftField.label,
      en: 'Enter a name.',
      ru: 'Введите имя.',
    ),
    (
      name: 'idEmpty',
      drive: (c) async => c.setLabel('!!!'),
      field: ProfileDraftField.id,
      en: 'Id is required.',
      ru: 'Укажите id.',
    ),
    (
      name: 'idReserved',
      drive: (c) async {
        c.setLabel('Box');
        c.setId('embedded');
      },
      field: ProfileDraftField.id,
      en: '"embedded" is reserved for the built-in agent.',
      ru: '«embedded» зарезервирован для встроенного агента.',
    ),
    (
      name: 'idTaken',
      drive: (c) async {
        c.setLabel('Box');
        c.setId('dev');
      },
      field: ProfileDraftField.id,
      en: 'A profile with id "dev" already exists.',
      ru: 'Профиль с id «dev» уже существует.',
    ),
    (
      name: 'idInvalid',
      drive: (c) async {
        c.setLabel('Box');
        c.setId('Bad Id');
      },
      field: ProfileDraftField.id,
      en:
          'Use lowercase letters, digits, ".", "_" and "-" (up to 64 '
          'characters).',
      ru:
          'Используйте строчные буквы, цифры, «.», «_» и «-» (до 64 '
          'символов).',
    ),
    (
      name: 'commandEmpty',
      drive: (c) async => c.setCommand(''),
      field: ProfileDraftField.command,
      en: 'Enter the command that starts the agent.',
      ru: 'Введите команду, которая запускает агента.',
    ),
    (
      name: 'argsInvalid',
      drive: (c) async => c.setArgs('serve "unclosed'),
      field: ProfileDraftField.args,
      en: 'Arguments have an unclosed quote.',
      ru: 'В аргументах не закрыта кавычка.',
    ),
    (
      // security: совет про секреты в окружении; `${secret:…}` — синтаксис
      // конфигурации агента и не переводится.
      name: 'envSecretLike',
      drive: (c) async => c.setEnv('API_KEY=x'),
      field: ProfileDraftField.env,
      en:
          'API_KEY looks like a secret. Set it in the system environment or '
          r'reference it from the agent config as ${secret:…}.',
      ru:
          'API_KEY похоже на секрет. Задайте его в системном окружении или '
          r'сошлитесь на него в конфигурации агента как ${secret:…}.',
    ),
    (
      name: 'urlInvalid',
      drive: (c) async {
        c.selectKind(ProfileKind.webSocket);
        c.setUrl('http://box');
      },
      field: ProfileDraftField.url,
      en: 'Use ws:// or wss:// with a host.',
      ru: 'Укажите ws:// или wss:// и хост.',
    ),
    (
      // security: учётные данные в URL.
      name: 'urlUserInfo',
      drive: (c) async {
        c.selectKind(ProfileKind.webSocket);
        c.setUrl('wss://user:pass@box:7420');
      },
      field: ProfileDraftField.url,
      en:
          'Remove the user name and password from the URL; use the Token '
          'setting instead.',
      ru:
          'Уберите имя пользователя и пароль из URL; вместо этого '
          'используйте поле «Токен».',
    ),
    (
      name: 'tokenEnvNameInvalid',
      drive: (c) async {
        c.selectKind(ProfileKind.webSocket);
        c.selectTokenEnv();
        c.setTokenEnvName('1BAD');
      },
      field: ProfileDraftField.token,
      en: 'Variable name: letters, digits and "_", not starting with a digit.',
      ru: 'Имя переменной: буквы, цифры и «_», не может начинаться с цифры.',
    ),
    (
      name: 'tokenSecretEmpty',
      drive: (c) async {
        c.selectKind(ProfileKind.webSocket);
        c.selectTokenNew();
      },
      field: ProfileDraftField.token,
      en: 'Enter the token.',
      ru: 'Введите токен.',
    ),
    (
      // Имя секрета строится из id: `a..b` годится профилю, но не секрету.
      name: 'tokenSecretNameInvalid (id)',
      drive: (c) async {
        c.selectKind(ProfileKind.webSocket);
        c.setLabel('Box');
        c.selectTokenNew();
        c.setNewToken('value');
        c.setId('a..b');
      },
      field: ProfileDraftField.id,
      en: 'This id cannot name a stored token; avoid "..".',
      ru: 'Этот id не подходит для имени сохранённого токена; избегайте «..».',
    ),
  ];

  group('FixedAppStrings(en): ошибки полей как раньше', () {
    for (final c in cases) {
      test('${c.name}: «${c.en}»', () async {
        final cubit = await started(FixedAppStrings(AppLocalizationsEn()));

        await c.drive(cubit);

        expect(_form(cubit).errors[c.field], c.en);
      });
    }
  });

  group('FixedAppStrings(ru): ошибки полей на русском с первой публикации', () {
    for (final c in cases) {
      test('${c.name}: «${c.ru}»', () async {
        final cubit = await started(FixedAppStrings(AppLocalizationsRu()));

        await c.drive(cubit);

        expect(_form(cubit).errors[c.field], c.ru);
      });
    }
  });

  group('TestAppStrings: уже показанные ошибки пересобираются', () {
    for (final c in cases) {
      test('${c.name}: en → ru → en', () async {
        final cubit = await started(strings);
        await c.drive(cubit);
        expect(_form(cubit).errors[c.field], c.en);

        await switchTo(AppLocalizationsRu());
        expect(_form(cubit).errors[c.field], c.ru);

        await switchTo(AppLocalizationsEn());
        expect(_form(cubit).errors[c.field], c.en);
      });
    }

    test('«секрет уже есть» после отказа записи: текст с именем и '
        'хранилищем, команда без изменений (security)', () async {
      secrets = FakeProfileSecrets(
        values: {'codelab/profiles/box/token': 'old-secret-value'},
      );
      final cubit = await started(strings);
      cubit
        ..selectKind(ProfileKind.webSocket)
        ..setLabel('Box')
        ..setUrl('wss://box:7420')
        ..selectTokenNew()
        ..setNewToken('new-secret-value');
      await cubit.save();
      expect(
        _form(cubit).errors[ProfileDraftField.token],
        'A stored token codelab/profiles/box/token already exists in file. '
        'Choose it with "Use stored secret" or remove it with codelab secret '
        'delete.',
      );

      await switchTo(AppLocalizationsRu());

      expect(
        _form(cubit).errors[ProfileDraftField.token],
        'Сохранённый токен «codelab/profiles/box/token» уже есть в file. '
        'Выберите его в варианте «Использовать сохранённый секрет» или '
        'удалите командой codelab secret delete.',
      );
    });
  });

  group('подсказки токена и предупреждения под полями', () {
    test('«Use stored secret» без имён: подсказка с хранилищем', () async {
      final cubit = await started(strings);
      cubit.selectKind(ProfileKind.webSocket);
      expect(_form(cubit).storedSecretsHint, 'No stored secrets in file.');

      await switchTo(AppLocalizationsRu());

      expect(
        _form(cubit).storedSecretsHint,
        'В file нет сохранённых секретов.',
      );
    });

    test('«Use stored secret» с именами подсказки не даёт ни на одном '
        'языке', () async {
      secrets = FakeProfileSecrets(values: {'codelab/profiles/ci/token': 'v'});
      final cubit = await started(strings);

      await switchTo(AppLocalizationsRu());

      expect(_form(cubit).storedSecretsHint, isNull);
    });

    test('«Store a new token»: куда сохранится значение (security)', () async {
      final cubit = await started(strings);
      cubit
        ..selectKind(ProfileKind.webSocket)
        ..setLabel('Box');
      expect(
        _form(cubit).newTokenHint,
        'Saved as codelab/profiles/box/token in file. The value is never '
        'shown again or written to profiles.json.',
      );

      await switchTo(AppLocalizationsRu());

      expect(
        _form(cubit).newTokenHint,
        'Сохраняется как «codelab/profiles/box/token» в file. Значение больше '
        'не показывается и не записывается в profiles.json.',
      );
    });

    test(
      '«Store a new token» без id: имя секрета с <id>, как в макете',
      () async {
        strings = TestAppStrings(AppLocalizationsRu());
        final cubit = await started(strings);

        expect(
          _form(cubit).newTokenHint,
          'Сохраняется как «codelab/profiles/<id>/token» в file. Значение больше '
          'не показывается и не записывается в profiles.json.',
        );
      },
    );

    test('хранилище только для чтения без причины: текст приложения '
        'переводится', () async {
      secrets = FakeProfileSecrets(
        backend: const ProfileSecretBackend(id: 'env', writable: false),
      );
      final cubit = await started(strings);
      expect(_form(cubit).newTokenHint, 'Secret store env is read-only.');

      await switchTo(AppLocalizationsRu());

      expect(
        _form(cubit).newTokenHint,
        'Хранилище секретов env доступно только для чтения.',
      );
    });

    test('хранилище только для чтения с причиной: текст бэкенда как '
        'есть (D6, D7)', () async {
      secrets = FakeProfileSecrets(
        backend: const ProfileSecretBackend(
          id: 'env',
          writable: false,
          unavailableReason: 'OS key stores are not available yet',
        ),
      );
      final cubit = await started(strings);

      await switchTo(AppLocalizationsRu());

      expect(_form(cubit).newTokenHint, 'OS key stores are not available yet');
    });

    test('предупреждение `ws://` с токеном и без токена (security)', () async {
      final cubit = await started(strings);
      cubit
        ..selectKind(ProfileKind.webSocket)
        ..setUrl('ws://box:7420');
      expect(
        _form(cubit).warning,
        'ws:// to another machine: traffic is sent unencrypted.',
      );

      await switchTo(AppLocalizationsRu());
      expect(
        _form(cubit).warning,
        'ws:// к другой машине: трафик передаётся без шифрования.',
      );

      cubit.selectTokenEnv();
      expect(
        _form(cubit).warning,
        'ws:// к другой машине: токен передаётся без шифрования.',
      );

      await switchTo(AppLocalizationsEn());
      expect(
        _form(cubit).warning,
        'ws:// to another machine: the token is sent unencrypted.',
      );
    });

    test('локальный `ws://` и `wss://` предупреждения не дают', () async {
      final cubit = await started(strings);
      cubit
        ..selectKind(ProfileKind.webSocket)
        ..setUrl('ws://localhost:7420');
      await switchTo(AppLocalizationsRu());
      expect(_form(cubit).warning, isNull);

      cubit.setUrl('wss://box:7420');
      expect(_form(cubit).warning, isNull);
    });

    test('«<NAME> is not set in CodeLab\'s environment.»: имя — '
        'плейсхолдер', () async {
      final cubit = await started(strings);
      cubit
        ..selectKind(ProfileKind.webSocket)
        ..selectTokenEnv()
        ..setTokenEnvName('DEVBOX_TOKEN');
      expect(
        _form(cubit).tokenNotice,
        "DEVBOX_TOKEN is not set in CodeLab's environment.",
      );

      await switchTo(AppLocalizationsRu());

      expect(
        _form(cubit).tokenNotice,
        'DEVBOX_TOKEN не задана в окружении CodeLab.',
      );
    });

    test('переменная задана: заметки нет ни на одном языке', () async {
      final cubit = await started(
        strings,
        environment: const {'DEVBOX_TOKEN': 'x'},
      );
      cubit
        ..selectKind(ProfileKind.webSocket)
        ..selectTokenEnv()
        ..setTokenEnvName('DEVBOX_TOKEN');

      await switchTo(AppLocalizationsRu());

      expect(_form(cubit).tokenNotice, isNull);
    });
  });

  group('смена языка не трогает черновик и состояние автомата (D5 п. 9)', () {
    test('введённое, выбранное и видимые ошибки сохраняются', () async {
      final cubit = await started(strings);
      cubit
        ..selectKind(ProfileKind.webSocket)
        ..setLabel('Box')
        ..setUrl('ws://box:7420')
        ..selectTokenEnv()
        ..setTokenEnvName('DEVBOX_TOKEN')
        ..setUseByDefault(true);
      final before = _form(cubit);

      await switchTo(AppLocalizationsRu());

      final after = _form(cubit);
      expect(cubit.state, isA<Editing>());
      expect(after.draft.label, 'Box');
      expect(after.draft.id, 'box');
      expect(after.draft.url, 'ws://box:7420');
      expect(after.tokenKind, AddProfileTokenKind.env);
      expect(after.tokenEnvName, 'DEVBOX_TOKEN');
      expect(after.useByDefault, isTrue);
      expect(after.touched, before.touched);
      expect(after.canSave, before.canSave);
      expect(after.errors.keys, before.errors.keys);
    });

    test(
      'подтверждение `ws://` остаётся на экране и не сбрасывается',
      () async {
        final cubit = await started(strings);
        cubit
          ..selectKind(ProfileKind.webSocket)
          ..setLabel('Box')
          ..setUrl('ws://box:7420');
        await cubit.save();
        expect(cubit.state, isA<ConfirmingPlaintext>());

        await switchTo(AppLocalizationsRu());

        expect(cubit.state, isA<ConfirmingPlaintext>());
        expect(_form(cubit).draft.url, 'ws://box:7420');
        expect((await store.load()).map((p) => p.id), ['dev']);
      },
    );

    test('экран «Profile saved» и сбой записи сохраняются', () async {
      final cubit = await started(strings);
      cubit.setLabel('Box');
      await cubit.save();
      expect(cubit.state, isA<Saved>());

      await switchTo(AppLocalizationsRu());

      final saved = cubit.state as Saved;
      expect(saved.profileId, 'box');
      expect(saved.label, 'Box');
      expect(cubit.savedProfiles, [(profileId: 'box')]);
    });

    test('сбой записи остаётся сбоем с тем же черновиком', () async {
      store = _FailingStore();
      final cubit = await started(strings);
      cubit.setLabel('Box');
      await cubit.save();
      expect(cubit.state, isA<SaveFailed>());

      await switchTo(AppLocalizationsRu());

      expect(cubit.state, isA<SaveFailed>());
      expect(_form(cubit).draft.label, 'Box');
    });
  });

  group('подписка на AppStrings (D5 правила 1–3; R3)', () {
    test('одна подписка с момента создания, снимается в close()', () async {
      final cubit = build(strings);
      expect(strings.subscriberCount, 1);

      await cubit.start();
      cubit
        ..setLabel('Box')
        ..selectKind(ProfileKind.webSocket);
      expect(strings.subscriberCount, 1);

      await cubit.close();

      expect(strings.hasListener, isFalse);
    });

    test('после close событие языка не меняет состояние', () async {
      final cubit = await started(strings);
      cubit.setLabel('');
      final before = cubit.state;
      await cubit.close();

      await switchTo(AppLocalizationsRu());

      expect(identical(cubit.state, before), isTrue);
    });

    test('язык, сменённый, пока открывается хранилище, учитывается в '
        'первой форме', () async {
      final cubit = build(strings);
      await switchTo(AppLocalizationsRu());
      await cubit.start();
      cubit.setLabel('');

      expect(_form(cubit).errors[ProfileDraftField.label], 'Введите имя.');
    });
  });
}

/// Хранилище, у которого запись падает: исход — `SaveFailed`.
final class _FailingStore implements ProfileStore {
  @override
  Future<List<ConnectionProfile>> load() async => const [];

  @override
  Future<void> save(ConnectionProfile profile) async =>
      throw StateError('disk is read-only');

  @override
  Future<bool> remove(String id) async => false;
}
